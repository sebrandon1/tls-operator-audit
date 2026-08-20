#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Read local scan results and generate dashboard data files for the GitHub Pages site.

Optional:
  --results-dir <dir>     Results directory (default: results)
  --cluster <name>        Cluster name for metadata (default: unknown)
  --ocp-version <ver>     OCP version for metadata (default: unknown)
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors

  --tco-version <ver>    tls-compliance-operator version used for scan

Scan settings (recorded in history for provenance):
  --scan-mode <mode>      How scan was run: all-operators | single-operator | operators-yaml
  --scan-operator <name>  Operator name (if single-operator mode)
  --scan-kubeconfig <path> Kubeconfig path used
  --scan-version <ver>    Version filter used (if any)
  --scan-keep-reports     Whether --keep-reports was used

  -h, --help              Show this help

Examples:
  $(basename "$0")
  $(basename "$0") --results-dir results --cluster cnfdt16 --ocp-version 4.18.6
  $(basename "$0") --cluster cnfdt16 --ocp-version 5.0 --scan-mode all-operators
EOF
}

# Defaults
readonly UNKNOWN_VALUE="unknown"
RESULTS_DIR="results"
CLUSTER="$UNKNOWN_VALUE"
OCP_VERSION="$UNKNOWN_VALUE"
TCO_VERSION=""
SCAN_MODE=""
SCAN_OPERATOR=""
SCAN_KUBECONFIG=""
SCAN_VERSION=""
SCAN_KEEP_REPORTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --results-dir)
            require_arg "$1" "${2:-}"; RESULTS_DIR="$2"; shift 2 ;;
        --cluster)
            require_arg "$1" "${2:-}"; CLUSTER="$2"; shift 2 ;;
        --ocp-version)
            require_arg "$1" "${2:-}"; OCP_VERSION="$2"; shift 2 ;;
        --tco-version)
            require_arg "$1" "${2:-}"; TCO_VERSION="$2"; shift 2 ;;
        --scan-mode)
            require_arg "$1" "${2:-}"; SCAN_MODE="$2"; shift 2 ;;
        --scan-operator)
            require_arg "$1" "${2:-}"; SCAN_OPERATOR="$2"; shift 2 ;;
        --scan-kubeconfig)
            require_arg "$1" "${2:-}"; SCAN_KUBECONFIG="$2"; shift 2 ;;
        --scan-version)
            require_arg "$1" "${2:-}"; SCAN_VERSION="$2"; shift 2 ;;
        --scan-keep-reports)
            SCAN_KEEP_REPORTS=true; shift ;;
        --verbose)
            export LOG_LEVEL=4; shift ;;
        --quiet)
            export LOG_LEVEL=0; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1 ;;
    esac
done

auto_detect_value() {
    local current_value="$1"
    local field_name="$2"
    local oc_command="$3"

    if [[ "$current_value" != "$UNKNOWN_VALUE" ]]; then
        return
    fi

    log_debug "Auto-detecting $field_name"
    local detected_value
    detected_value=$(eval "$oc_command" 2>/dev/null || echo "")

    if [[ -n "$detected_value" ]]; then
        log_info "Auto-detected $field_name: $detected_value"
        eval "$4='$detected_value'"
    else
        log_warn "Could not auto-detect $field_name, using '$UNKNOWN_VALUE'"
    fi
}

if command -v oc &>/dev/null; then
    auto_detect_value "$CLUSTER" "cluster name" \
        "oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'" \
        "CLUSTER"

    auto_detect_value "$OCP_VERSION" "OCP version" \
        "oc get clusterversion version -o jsonpath='{.status.desired.version}'" \
        "OCP_VERSION"
fi

require_cmd jq yq bc

OPERATORS_YAML="$SCRIPT_DIR/operators.yaml"
if [[ ! -f "$OPERATORS_YAML" ]]; then
    log_error "operators.yaml not found at $OPERATORS_YAML"
    exit 1
fi

DOCS_DIR="$SCRIPT_DIR/docs"
DATA_DIR="$DOCS_DIR/_data"
BADGES_DIR="$DOCS_DIR/badges"
OPERATORS_DIR="$DOCS_DIR/operators"

mkdir -p "$DATA_DIR" "$BADGES_DIR" "$OPERATORS_DIR"

# ============================================================================
# Cross-platform stat helper: returns file modification time as epoch seconds
# ============================================================================
file_mtime_epoch() {
    local filepath="$1"
    if stat -f '%m' "$filepath" &>/dev/null; then
        # macOS
        stat -f '%m' "$filepath"
    else
        # Linux
        stat -c '%Y' "$filepath"
    fi
}

# ============================================================================
# Cross-platform date formatting: epoch seconds to ISO 8601
# ============================================================================
epoch_to_iso() {
    local epoch="$1"
    if date -r "$epoch" -u '+%Y-%m-%dT%H:%M:%SZ' &>/dev/null; then
        # macOS
        date -r "$epoch" -u '+%Y-%m-%dT%H:%M:%SZ'
    else
        # Linux
        date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    fi
}

# ============================================================================
# Process operators
# ============================================================================
log_info "Reading operators from $OPERATORS_YAML"

operator_count=$(yq -r '.operators | length' "$OPERATORS_YAML")
log_info "Found $operator_count operators"

# Accumulators for the summary
summary_pass=0
summary_partial=0
summary_none=0
summary_error=0
summary_na=0
total_endpoints_all=0
mlkem_endpoints_all=0
latest_mtime=0

# Build per-operator JSON array
operators_json="[]"

for i in $(seq 0 $((operator_count - 1))); do
    op_name=$(yq -r ".operators[$i].name" "$OPERATORS_YAML")
    op_catalog_raw=$(yq -r ".operators[$i].catalog" "$OPERATORS_YAML")
    op_jira=$(yq -r ".operators[$i].jira // \"\"" "$OPERATORS_YAML")
    op_project=$(yq -r ".operators[$i].project // \"$op_name\"" "$OPERATORS_YAML")

    catalog_skipped=false
    if [[ "$op_catalog_raw" == "null" || -z "$op_catalog_raw" ]]; then
        catalog_skipped=true
        op_catalog="pre-installed"
    else
        op_catalog="$op_catalog_raw"
    fi

    log_debug "Processing operator: $op_name"

    # Find the latest report.json
    latest_report=""
    latest_report=$(find "$RESULTS_DIR/$op_name" -name "report.json" -type f 2>/dev/null | sort | tail -1 || true)

    if [[ -z "$latest_report" || ! -f "$latest_report" ]]; then
        if [[ "$catalog_skipped" == "true" ]]; then
            op_status="N/A"
            summary_na=$((summary_na + 1))
            log_info "No report.json for $op_name (catalog skipped), recording N/A"
        else
            op_status="ERROR"
            summary_error=$((summary_error + 1))
            log_warn "No report.json found for $op_name"
        fi

        op_json=$(jq -n \
            --arg name "$op_name" \
            --arg catalog "$op_catalog" \
            --arg jira "$op_jira" \
            --arg project "$op_project" \
            --arg status "$op_status" \
            --arg version "" \
            '{
                name: $name,
                catalog: $catalog,
                jira: $jira,
                project: $project,
                status: $status,
                version: $version,
                total_endpoints: 0,
                reachable_endpoints: 0,
                closed_endpoints: 0,
                mlkem_endpoints: 0,
                endpoints: []
            }')

        operators_json=$(echo "$operators_json" | jq --argjson op "$op_json" '. + [$op]')
        continue
    fi

    # Track latest modification time across all reports
    report_mtime=$(file_mtime_epoch "$latest_report")
    if [[ "$report_mtime" -gt "$latest_mtime" ]]; then
        latest_mtime=$report_mtime
    fi

    # Read operator version from metadata.json if present
    report_dir=$(dirname "$latest_report")
    op_version=""
    if [[ -f "$report_dir/metadata.json" ]]; then
        op_version=$(jq -r '.operator_version // ""' "$report_dir/metadata.json")
    fi

    # Extract endpoint data using jq
    endpoints_json=$(jq '[.[] | {
        host: (.spec.host // ""),
        port: (.spec.port // 0),
        source_kind: (.spec.sourceKind // ""),
        source_name: (.spec.sourceName // ""),
        source_namespace: (.spec.sourceNamespace // ""),
        compliance_status: (.status.complianceStatus // ""),
        mlkem_supported: (.status.mlkemSupported // false),
        pqc_readiness: (.status.pqcReadiness // ""),
        overall_cipher_grade: (.status.overallCipherGrade // ""),
        forward_secrecy: (.status.forwardSecrecy // false),
        tls_versions: (.status.tlsVersions // {}),
        cipher_suites: (.status.cipherSuites // {}),
        certificate_info: {
            issuer: (.status.certificateInfo.issuer // ""),
            subject: (.status.certificateInfo.subject // ""),
            days_until_expiry: (.status.certificateInfo.daysUntilExpiry // 0),
            public_key_algorithm: (.status.certificateInfo.publicKeyAlgorithm // ""),
            public_key_bits: (.status.certificateInfo.publicKeyBits // 0),
            signature_algorithm: (.status.certificateInfo.signatureAlgorithm // ""),
            hostname_match: (.status.certificateInfo.hostnameMatch // false)
        },
        workload: (.workload // {pods: []})
    }]' "$latest_report")

    total_ep=$(echo "$endpoints_json" | jq 'length')
    reachable_ep=$(echo "$endpoints_json" | jq '[.[] | select(.compliance_status != "Closed" and .compliance_status != "Timeout")] | length')
    closed_ep=$(echo "$endpoints_json" | jq '[.[] | select(.compliance_status == "Closed" or .compliance_status == "Timeout")] | length')
    mlkem_ep=$(echo "$endpoints_json" | jq '[.[] | select(.compliance_status != "Closed" and .compliance_status != "Timeout") | select(.mlkem_supported == true)] | length')

    # Determine status
    op_status=$(determine_status "$reachable_ep" "$mlkem_ep")

    case "$op_status" in
        PASS)
            summary_pass=$((summary_pass + 1))
            ;;
        PARTIAL)
            summary_partial=$((summary_partial + 1))
            ;;
        NONE)
            summary_none=$((summary_none + 1))
            ;;
        FAIL)
            summary_error=$((summary_error + 1))
            ;;
    esac

    if [[ "$reachable_ep" -gt 0 ]]; then
        mlkem_pct=$(echo "scale=1; $mlkem_ep * 100 / $reachable_ep" | bc)
    else
        mlkem_pct="0.0"
    fi

    total_endpoints_all=$((total_endpoints_all + reachable_ep))
    mlkem_endpoints_all=$((mlkem_endpoints_all + mlkem_ep))

    op_json=$(jq -n \
        --arg name "$op_name" \
        --arg catalog "$op_catalog" \
        --arg jira "$op_jira" \
        --arg project "$op_project" \
        --arg status "$op_status" \
        --arg version "$op_version" \
        --argjson total_endpoints "$total_ep" \
        --argjson reachable_endpoints "$reachable_ep" \
        --argjson closed_endpoints "$closed_ep" \
        --argjson mlkem_endpoints "$mlkem_ep" \
        --argjson mlkem_percent "$mlkem_pct" \
        --argjson endpoints "$endpoints_json" \
        '{
            name: $name,
            catalog: $catalog,
            jira: $jira,
            project: $project,
            status: $status,
            version: $version,
            total_endpoints: $total_endpoints,
            reachable_endpoints: $reachable_endpoints,
            closed_endpoints: $closed_endpoints,
            mlkem_endpoints: $mlkem_endpoints,
            mlkem_percent: $mlkem_percent,
            endpoints: $endpoints
        }')

    operators_json=$(echo "$operators_json" | jq --argjson op "$op_json" '. + [$op]')

    log_success "$op_name: $op_status ($mlkem_ep/$reachable_ep ML-KEM endpoints)"
done

# ============================================================================
# Compute scan date from latest report modification time
# ============================================================================
if [[ "$latest_mtime" -gt 0 ]]; then
    scan_date=$(epoch_to_iso "$latest_mtime")
else
    scan_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

# ============================================================================
# Compute ML-KEM percentage across all reachable endpoints
# ============================================================================
if [[ "$total_endpoints_all" -gt 0 ]]; then
    mlkem_percent=$(echo "scale=1; $mlkem_endpoints_all * 100 / $total_endpoints_all" | bc)
else
    mlkem_percent="0.0"
fi

# ============================================================================
# Build and write scan-results.json
# ============================================================================
total_operators=$((summary_pass + summary_partial + summary_none + summary_error + summary_na))

scan_results=$(jq -n \
    --arg scan_date "$scan_date" \
    --arg cluster "$CLUSTER" \
    --arg ocp_version "$OCP_VERSION" \
    --arg tco_version "$TCO_VERSION" \
    --argjson total_operators "$total_operators" \
    --argjson pass "$summary_pass" \
    --argjson partial "$summary_partial" \
    --argjson none "$summary_none" \
    --argjson error "$summary_error" \
    --argjson na "$summary_na" \
    --argjson total_endpoints "$total_endpoints_all" \
    --argjson mlkem_endpoints "$mlkem_endpoints_all" \
    --argjson mlkem_percent "$mlkem_percent" \
    --argjson operators "$operators_json" \
    '{
        scan_date: $scan_date,
        cluster: $cluster,
        ocp_version: $ocp_version,
        tco_version: $tco_version,
        summary: {
            total_operators: $total_operators,
            pass: $pass,
            partial: $partial,
            none: $none,
            error: $error,
            na: $na,
            total_endpoints: $total_endpoints,
            mlkem_endpoints: $mlkem_endpoints,
            mlkem_percent: $mlkem_percent
        },
        operators: $operators
    }')

echo "$scan_results" > "$DATA_DIR/scan-results.json"
log_success "Wrote $DATA_DIR/scan-results.json"

# ============================================================================
# Append snapshot to scan-history.json
# ============================================================================
history_file="$DATA_DIR/scan-history.json"

if [[ -f "$history_file" ]]; then
    existing_history=$(cat "$history_file")
else
    existing_history="[]"
fi

# Build scan_settings object if any --scan-* flags were provided
scan_settings_json="null"
if [[ -n "$SCAN_MODE" || -n "$SCAN_OPERATOR" || -n "$SCAN_KUBECONFIG" || -n "$SCAN_VERSION" || "$SCAN_KEEP_REPORTS" == "true" ]]; then
    scan_settings_json=$(jq -n \
        --arg mode "$SCAN_MODE" \
        --arg operator "$SCAN_OPERATOR" \
        --arg kubeconfig "$SCAN_KUBECONFIG" \
        --arg version "$SCAN_VERSION" \
        --argjson keep_reports "$SCAN_KEEP_REPORTS" \
        '{
            mode: (if $mode != "" then $mode else null end),
            operator: (if $operator != "" then $operator else null end),
            kubeconfig: (if $kubeconfig != "" then $kubeconfig else null end),
            version: (if $version != "" then $version else null end),
            keep_reports: $keep_reports
        } | with_entries(select(.value != null and .value != false))')
fi

# Build operator summary list (lightweight, without full endpoint data)
operator_summary=$(echo "$operators_json" | jq '[.[] | {
    name: .name,
    status: .status,
    version: .version,
    reachable_endpoints: .reachable_endpoints,
    mlkem_endpoints: .mlkem_endpoints,
    mlkem_percent: .mlkem_percent
}]')

# Build a history entry with operator-level summary
history_entry=$(jq -n \
    --arg scan_date "$scan_date" \
    --arg cluster "$CLUSTER" \
    --arg ocp_version "$OCP_VERSION" \
    --arg tco_version "$TCO_VERSION" \
    --argjson total_operators "$total_operators" \
    --argjson pass "$summary_pass" \
    --argjson partial "$summary_partial" \
    --argjson none "$summary_none" \
    --argjson error "$summary_error" \
    --argjson na "$summary_na" \
    --argjson total_endpoints "$total_endpoints_all" \
    --argjson mlkem_endpoints "$mlkem_endpoints_all" \
    --argjson mlkem_percent "$mlkem_percent" \
    --argjson scan_settings "$scan_settings_json" \
    --argjson operators "$operator_summary" \
    '{
        scan_date: $scan_date,
        cluster: $cluster,
        ocp_version: $ocp_version,
        tco_version: $tco_version,
        summary: {
            total_operators: $total_operators,
            pass: $pass,
            partial: $partial,
            none: $none,
            error: $error,
            na: $na,
            total_endpoints: $total_endpoints,
            mlkem_endpoints: $mlkem_endpoints,
            mlkem_percent: $mlkem_percent
        },
        operators: $operators
    } + (if $scan_settings != null then {scan_settings: $scan_settings} else {} end)')

# Deduplicate by scan_date+cluster, replacing any existing entry with the same key
updated_history=$(echo "$existing_history" | jq --argjson entry "$history_entry" '
    [.[] | select(.scan_date != $entry.scan_date or .cluster != $entry.cluster)] + [$entry]')
echo "$updated_history" > "$history_file"
log_success "Wrote snapshot to $history_file"

# ============================================================================
# Generate shields.io badge JSON
# ============================================================================
# Determine badge color based on ML-KEM percentage
badge_color="red"
if echo "$mlkem_percent >= 80" | bc -l | grep -q '^1'; then
    badge_color="green"
elif echo "$mlkem_percent >= 50" | bc -l | grep -q '^1'; then
    badge_color="yellow"
fi

jq -n \
    --argjson schemaVersion 1 \
    --arg label "ML-KEM Compliance" \
    --arg message "${mlkem_percent}%" \
    --arg color "$badge_color" \
    '{
        schemaVersion: $schemaVersion,
        label: $label,
        message: $message,
        color: $color
    }' > "$BADGES_DIR/mlkem.json"

log_success "Wrote $BADGES_DIR/mlkem.json"

# ============================================================================
# Generate per-operator .md stubs
# ============================================================================
generated_stubs=0
for i in $(seq 0 $((operator_count - 1))); do
    op_name=$(yq -r ".operators[$i].name" "$OPERATORS_YAML")
    stub_file="$OPERATORS_DIR/${op_name}.md"

    if [[ ! -f "$stub_file" ]]; then
        cat > "$stub_file" <<EOF
---
layout: operator
operator: ${op_name}
title: "${op_name}"
---
EOF
        generated_stubs=$((generated_stubs + 1))
        log_debug "Created operator stub: $stub_file"
    fi
done

if [[ "$generated_stubs" -gt 0 ]]; then
    log_success "Generated $generated_stubs new operator page stubs"
fi

# ============================================================================
# Print summary
# ============================================================================
print_summary "Dashboard Export Complete" \
    "Scan date" "$scan_date" \
    "Cluster" "$CLUSTER" \
    "OCP version" "$OCP_VERSION" \
    "Total operators" "$total_operators" \
    "PASS" "$summary_pass" \
    "PARTIAL" "$summary_partial" \
    "NONE" "$summary_none" \
    "ERROR" "$summary_error" \
    "N/A" "$summary_na" \
    "Total endpoints" "$total_endpoints_all" \
    "ML-KEM endpoints" "$mlkem_endpoints_all" \
    "ML-KEM percentage" "${mlkem_percent}%"
