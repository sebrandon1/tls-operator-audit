#!/bin/bash

# ============================================================================
# SCAN RUN COMPARISON
# ============================================================================

# Derive the operator name from a report.json path.
# Supports results/<op>/<timestamp>/report.json and <op>/report.json.
operator_from_report_path() {
    local report_file="$1"
    local dir parent
    dir=$(dirname "$report_file")
    parent=$(basename "$dir")
    if [[ "$parent" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        basename "$(dirname "$dir")"
    else
        echo "$parent"
    fi
}

# List report.json files for a timestamp, directory, or file.
# Args: spec results_dir
# Prints: operator<TAB>path  (one per line)
list_report_files() {
    local spec="$1"
    local results_dir="$2"
    local f

    if [[ -f "$spec" ]]; then
        printf '%s\t%s\n' "$(operator_from_report_path "$spec")" "$spec"
        return 0
    fi

    if [[ -d "$spec" ]]; then
        if [[ -f "$spec/report.json" ]]; then
            printf '%s\t%s\n' "$(basename "$spec")" "$spec/report.json"
            return 0
        fi
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            printf '%s\t%s\n' "$(operator_from_report_path "$f")" "$f"
        done < <(find "$spec" -name report.json -type f | sort)
        return 0
    fi

    if [[ "$spec" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
        while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            printf '%s\t%s\n' "$(operator_from_report_path "$f")" "$f"
        done < <(find "$results_dir" -path "*/${spec}/report.json" -type f | sort)
        return 0
    fi

    log_error "Cannot resolve scan run: $spec (expected timestamp, directory, or report.json)"
    return 1
}

# Normalize a TLS report (array or {items:[]}) into endpoint objects.
normalize_report() {
    jq -c '
        def items: if type == "object" and has("items") then .items else . end;
        [items[] | {
            key: ((.spec.sourceNamespace // "") + "|" + (.spec.host // "") + "|" + ((.spec.port // 0) | tostring)),
            namespace: (.spec.sourceNamespace // ""),
            host: (.spec.host // ""),
            port: (.spec.port // 0),
            mlkem: (.status.mlkemSupported == true),
            compliance: (.status.complianceStatus // ""),
            closed: ((.status.complianceStatus == "Closed") or (.status.complianceStatus == "Timeout"))
        }]
    '
}

# Load all reports for a run into {operator: {key: endpoint}}.
# Args: spec results_dir
load_run() {
    local spec="$1"
    local results_dir="$2"
    local listing op path eps
    local json='{}'

    listing=$(list_report_files "$spec" "$results_dir") || return 1
    if [[ -z "$listing" ]]; then
        log_error "No report.json files found for: $spec"
        return 1
    fi

    while IFS=$'\t' read -r op path; do
        [[ -z "$op" || -z "$path" ]] && continue
        eps=$(normalize_report < "$path")
        json=$(jq -c --arg op "$op" --argjson eps "$eps" '
            .[$op] = (
                $eps
                | map({key: .key, value: {mlkem, host, port, namespace, compliance, closed}})
                | from_entries
            )
        ' <<< "$json")
    done <<< "$listing"

    echo "$json"
}

# Diff two load_run JSON objects. Prints {summary, changes, operators}.
compare_runs() {
    local before_json="$1"
    local after_json="$2"

    jq -n --argjson before "$before_json" --argjson after "$after_json" '
        def flatten($run):
            $run | to_entries
            | map(.key as $op | .value | to_entries | map(.value + {operator: $op, key: .key}))
            | add // [];

        def index_by_op_key:
            map({key: (.operator + "\t" + .key), value: .}) | from_entries;

        def op_status($eps):
            ($eps | length) as $total
            | ([$eps[] | select(.closed == true)] | length) as $closed
            | ($total - $closed) as $reachable
            | ([$eps[] | select(.mlkem == true)] | length) as $mlkem
            | if $reachable == 0 then "NONE"
              elif $mlkem == $reachable then "PASS"
              elif $mlkem > 0 then "PARTIAL"
              else "FAIL"
              end;

        (flatten($before) | index_by_op_key) as $b
        | (flatten($after) | index_by_op_key) as $a
        | (($b | keys) + ($a | keys) | unique) as $keys
        | [
            $keys[] as $k
            | ($b[$k] // null) as $be
            | ($a[$k] // null) as $ae
            | {
                operator: (($ae // $be).operator),
                endpoint: (
                    (($ae // $be).namespace)
                    + "/"
                    + (($ae // $be).host)
                    + ":"
                    + ((($ae // $be).port) | tostring)
                ),
                before: (if $be == null then null else $be.mlkem end),
                after: (if $ae == null then null else $ae.mlkem end),
                change: (
                    if $be == null then "added"
                    elif $ae == null then "removed"
                    elif ($be.mlkem == false) and ($ae.mlkem == true) then "gained"
                    elif ($be.mlkem == true) and ($ae.mlkem == false) then "lost"
                    else "unchanged"
                    end
                )
            }
          ] as $changes
        | (($before | keys) + ($after | keys) | unique) as $ops
        | {
            summary: {
                gained: ([$changes[] | select(.change == "gained")] | length),
                lost: ([$changes[] | select(.change == "lost")] | length),
                added: ([$changes[] | select(.change == "added")] | length),
                removed: ([$changes[] | select(.change == "removed")] | length),
                unchanged: ([$changes[] | select(.change == "unchanged")] | length)
            },
            changes: $changes,
            operators: [
                $ops[] as $op
                | {
                    name: $op,
                    before: (if $before[$op] then op_status($before[$op] | to_entries | map(.value)) else null end),
                    after: (if $after[$op] then op_status($after[$op] | to_entries | map(.value)) else null end)
                }
                | . + {
                    change: (
                        if .before == null then "added"
                        elif .after == null then "removed"
                        elif .before == .after then "unchanged"
                        else "changed"
                        end
                    )
                }
            ]
          }
    '
}

print_compare_table() {
    local diff_json="$1"
    local gained lost added removed unchanged

    read -r gained lost added removed unchanged < <(
        echo "$diff_json" | jq -r '[.summary.gained, .summary.lost, .summary.added, .summary.removed, .summary.unchanged] | @tsv'
    )

    echo ""
    echo -e "${BOLD}SCAN COMPARISON${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  %-24s %-52s %-10s %-10s %s\n" "OPERATOR" "ENDPOINT" "BEFORE" "AFTER" "CHANGE"
    printf "  %-24s %-52s %-10s %-10s %s\n" "--------" "--------" "------" "-----" "------"

    echo "$diff_json" | jq -r '
        .changes[]
        | select(.change != "unchanged")
        | [
            .operator,
            .endpoint,
            (if .before == null then "-" elif .before then "true" else "false" end),
            (if .after == null then "-" elif .after then "true" else "false" end),
            .change
          ] | @tsv
    ' | while IFS=$'\t' read -r op endpoint before after change; do
        color="$NC"
        case "$change" in
            gained)  color="$GREEN" ;;
            lost)    color="$RED" ;;
            added)   color="$CYAN" ;;
            removed) color="$YELLOW" ;;
        esac
        printf "  ${color}%-24s %-52s %-10s %-10s %s${NC}\n" "$op" "$endpoint" "$before" "$after" "$change"
    done

    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Gained: ${GREEN}${gained}${NC}  Lost: ${RED}${lost}${NC}  Added: ${CYAN}${added}${NC}  Removed: ${YELLOW}${removed}${NC}  Unchanged: ${unchanged}"
    echo ""
}

emit_compare_output() {
    local format="$1"
    local diff_json="$2"

    case "$format" in
        table|"")
            print_compare_table "$diff_json"
            ;;
        json)
            echo "$diff_json" | jq '{summary, operators, changes: [.changes[] | select(.change != "unchanged")]}'
            ;;
        csv)
            echo "$diff_json" | jq -r '
                (["operator","endpoint","before","after","change"] | @csv),
                (.changes[]
                 | select(.change != "unchanged")
                 | [
                     .operator,
                     .endpoint,
                     (if .before == null then "" elif .before then "true" else "false" end),
                     (if .after == null then "" elif .after then "true" else "false" end),
                     .change
                   ] | @csv)
            '
            ;;
        markdown)
            echo "$diff_json" | jq -r '
                "| operator | endpoint | before | after | change |",
                "| --- | --- | --- | --- | --- |",
                (.changes[]
                 | select(.change != "unchanged")
                 | "| \(.operator) | \(.endpoint) | \(if .before == null then "-" elif .before then "true" else "false" end) | \(if .after == null then "-" elif .after then "true" else "false" end) | \(.change) |")
            '
            ;;
        *)
            log_error "Invalid --output-format '${format}' (expected table, json, csv, or markdown)"
            return 1
            ;;
    esac
}

compare_lost_count() {
    echo "$1" | jq '.summary.lost'
}
