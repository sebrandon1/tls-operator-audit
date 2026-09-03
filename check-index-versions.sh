#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Query catalog indexes for the latest available operator versions and update
the index version tracker. Compares against last-scanned versions to flag
operators that need re-scanning.

Options:
  --kubeconfig <path>     Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
  --operators <file>      Operators list file (default: operators.yaml)
  --concurrency <N>       Max parallel oc calls (default: 5)
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors
  -h, --help              Show this help
EOF
}

KUBECONFIG_PATH=""
OPERATORS_FILE="$SCRIPT_DIR/operators.yaml"
CONCURRENCY=5

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubeconfig)     require_arg "$1" "${2:-}"; KUBECONFIG_PATH="$2"; shift 2 ;;
        --operators)      require_arg "$1" "${2:-}"; OPERATORS_FILE="$2"; shift 2 ;;
        --concurrency)    require_arg "$1" "${2:-}"; CONCURRENCY="$2"; shift 2 ;;
        --verbose)        export LOG_LEVEL=4; shift ;;
        --quiet)          export LOG_LEVEL=0; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

require_cmd oc jq yq
resolve_kubeconfig "$KUBECONFIG_PATH"
require_cluster

TRACKER_FILE="$SCRIPT_DIR/docs/_data/index-versions.json"
SCAN_RESULTS="$SCRIPT_DIR/docs/_data/scan-results.json"

operator_count=$(yq '.operators | length' "$OPERATORS_FILE")
log_info "Checking index versions for $operator_count operators..."

check_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Load existing tracker for history
if [[ -f "$TRACKER_FILE" ]]; then
    existing_tracker=$(cat "$TRACKER_FILE")
else
    existing_tracker='{"checked":"","operators":[]}'
fi

# Load last-scanned versions for comparison
scanned_versions='{}'
if [[ -f "$SCAN_RESULTS" ]]; then
    scanned_versions=$(jq '[.operators[] | {(.name): .version}] | add // {}' "$SCAN_RESULTS")
fi

# Build catalog name → image mapping from cluster
catalog_images=$(oc get catalogsource -n openshift-marketplace -o json 2>/dev/null | jq '
    [.items[] | {(.metadata.name): .spec.image}] | add // {}')

# Map known Red Hat catalog images to their catalog.redhat.com URLs
catalog_url_for() {
    local image="$1"
    case "$image" in
        *redhat-operator-index*)
            echo "https://catalog.redhat.com/en/software/containers/redhat/redhat-operator-index/5f0e4759dd19c7063a78b1f8" ;;
        *certified-operator-index*)
            echo "https://catalog.redhat.com/en/software/containers/redhat/certified-operator-index/5f0e47c7d19c7063a78b1f96" ;;
        *community-operator-index*)
            echo "https://catalog.redhat.com/en/software/containers/redhat/community-operator-index/5f0e481add19c7063a78b1fa" ;;
        *)
            echo "" ;;
    esac
}

# Create temp directories for shared data and worker results
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# Batch-fetch all CSVs and write to temp file
oc get csv -A -o json 2>/dev/null > "$TMPDIR_WORK/all-csvs.json" || echo '{"items":[]}' > "$TMPDIR_WORK/all-csvs.json"

# Batch-fetch packagemanifest names and write to temp file
oc get packagemanifest -n openshift-marketplace -o json 2>/dev/null > "$TMPDIR_WORK/all-pm-names.json" || echo '{"items":[]}' > "$TMPDIR_WORK/all-pm-names.json"

# Build operator list arrays (fast local yq reads)
declare -a op_names=()
declare -a op_catalogs=()
declare -a op_channels=()

for i in $(seq 0 $((operator_count - 1))); do
    op_names+=("$(yq -r ".operators[$i].name" "$OPERATORS_FILE")")
    op_catalogs+=("$(yq -r ".operators[$i].catalog" "$OPERATORS_FILE")")
    op_channels+=("$(yq -r ".operators[$i].channel" "$OPERATORS_FILE")")
done

# Function to build a single operator entry (runs in background workers)
build_entry() {
    local op_name="$1"
    local op_catalog="$2"
    local op_channel="$3"
    local scanned_versions_json="$4"
    local existing_tracker_json="$5"
    local catalog_images_json="$6"
    local all_csvs_file="$7"
    local output_file="$8"

    local scanned_version
    scanned_version=$(echo "$scanned_versions_json" | jq -r --arg n "$op_name" '.[$n] // ""')

    if [[ "$op_catalog" == "null" ]]; then
        # Pre-installed operator: look up from batch-fetched CSVs
        local installed_version
        installed_version=$(jq -r --arg name "$op_name" '
            [.items[]
            | select(.status.phase == "Succeeded")
            | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
            | .[0].spec.version // ""' "$all_csvs_file")

        jq -n \
            --arg name "$op_name" \
            --arg catalog "pre-installed" \
            --arg channel "" \
            --arg catalog_image "" \
            --arg catalog_url "" \
            --arg index_version "$installed_version" \
            --arg scanned_version "$scanned_version" \
            '{
                name: $name,
                catalog: $catalog,
                channel: $channel,
                catalog_image: $catalog_image,
                catalog_url: $catalog_url,
                index_version: $index_version,
                scanned_version: $scanned_version,
                update_available: ($index_version != $scanned_version and $index_version != "" and $scanned_version != "")
            }' > "$output_file"
        return
    fi

    # Catalog operator: check if packagemanifest exists (from batch query)
    local pm_exists
    pm_exists=$(jq -r --arg name "$op_name" '
        [.items[].metadata.name | select(. == $name)] | length > 0' "$TMPDIR_WORK/all-pm-names.json")

    if [[ "$pm_exists" != "true" ]]; then
        local catalog_image catalog_url
        catalog_image=$(echo "$catalog_images_json" | jq -r --arg c "$op_catalog" '.[$c] // ""')
        catalog_url=$(catalog_url_for "$catalog_image")
        jq -n \
            --arg name "$op_name" \
            --arg catalog "$op_catalog" \
            --arg channel "$op_channel" \
            --arg catalog_image "$catalog_image" \
            --arg catalog_url "$catalog_url" \
            '{
                name: $name,
                catalog: $catalog,
                channel: $channel,
                catalog_image: $catalog_image,
                catalog_url: $catalog_url,
                index_version: "",
                scanned_version: "",
                update_available: false,
                error: "not found in catalog"
            }' > "$output_file"
        return
    fi

    # Fetch full packagemanifest data (individual call, parallelized)
    local pm_json
    pm_json=$(oc get packagemanifest "$op_name" -n openshift-marketplace -o json 2>/dev/null || echo '{}')

    if [[ "$pm_json" == "{}" ]]; then
        local catalog_image catalog_url
        catalog_image=$(echo "$catalog_images_json" | jq -r --arg c "$op_catalog" '.[$c] // ""')
        catalog_url=$(catalog_url_for "$catalog_image")
        jq -n \
            --arg name "$op_name" \
            --arg catalog "$op_catalog" \
            --arg channel "$op_channel" \
            --arg catalog_image "$catalog_image" \
            --arg catalog_url "$catalog_url" \
            '{
                name: $name,
                catalog: $catalog,
                channel: $channel,
                catalog_image: $catalog_image,
                catalog_url: $catalog_url,
                index_version: "",
                scanned_version: "",
                update_available: false,
                error: "not found in catalog"
            }' > "$output_file"
        return
    fi

    local index_version
    index_version=$(echo "$pm_json" | jq -r --arg ch "$op_channel" '
        .status.channels[]
        | select(.name == $ch)
        | .currentCSVDesc.version // ""')

    local prev_index
    prev_index=$(echo "$existing_tracker_json" | jq -r --arg n "$op_name" '
        .operators[]? | select(.name == $n) | .index_version // ""')

    local update_available="false"
    if [[ -n "$index_version" && -n "$scanned_version" && "$index_version" != "$scanned_version" ]]; then
        update_available="true"
    fi

    local version_changed="false"
    if [[ -n "$prev_index" && -n "$index_version" && "$prev_index" != "$index_version" ]]; then
        version_changed="true"
    fi

    local catalog_image catalog_url
    catalog_image=$(echo "$catalog_images_json" | jq -r --arg c "$op_catalog" '.[$c] // ""')
    catalog_url=$(catalog_url_for "$catalog_image")

    jq -n \
        --arg name "$op_name" \
        --arg catalog "$op_catalog" \
        --arg channel "$op_channel" \
        --arg catalog_image "$catalog_image" \
        --arg catalog_url "$catalog_url" \
        --arg index_version "$index_version" \
        --arg scanned_version "$scanned_version" \
        --argjson update_available "$update_available" \
        --argjson version_changed "$version_changed" \
        --arg prev_index_version "$prev_index" \
        '{
            name: $name,
            catalog: $catalog,
            channel: $channel,
            catalog_image: $catalog_image,
            catalog_url: $catalog_url,
            index_version: $index_version,
            scanned_version: $scanned_version,
            update_available: $update_available
        } + (if $version_changed then {version_changed: true, prev_index_version: $prev_index_version} else {} end)' > "$output_file"
}

# Launch parallel workers with semaphore
active_jobs=0
job_pids=()

for idx in "${!op_names[@]}"; do
    op_name="${op_names[$idx]}"
    op_catalog="${op_catalogs[$idx]}"
    op_channel="${op_channels[$idx]}"

    # Wait if we've hit the concurrency limit
    while [[ $active_jobs -ge $CONCURRENCY ]]; do
        new_pids=()
        for pid in "${job_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                new_pids+=("$pid")
            fi
        done
        job_pids=("${new_pids[@]}")
        active_jobs=${#job_pids[@]}
        if [[ $active_jobs -ge $CONCURRENCY ]]; then
            sleep 0.1
        fi
    done

    output_file="$TMPDIR_WORK/${op_name}.json"

    (
        build_entry "$op_name" "$op_catalog" "$op_channel" \
            "$scanned_versions" "$existing_tracker" "$catalog_images" \
            "$TMPDIR_WORK/all-csvs.json" \
            "$output_file"

        # Emit log messages to stderr so they mix with main process output
        local_index=$(jq -r '.index_version // ""' "$output_file")
        local_update=$(jq -r '.update_available' "$output_file")
        local_vchanged=$(jq -r '.version_changed // false' "$output_file")

        if [[ "$op_catalog" == "null" ]]; then
            if [[ -n "$local_index" ]]; then
                log_debug "$op_name: index=$local_index (pre-installed)"
            else
                log_debug "$op_name: no version found (pre-installed)"
            fi
        elif [[ "$local_update" == "true" ]]; then
            local_scanned=$(jq -r '.scanned_version' "$output_file")
            log_warn "$op_name: index=$local_index scanned=$local_scanned (UPDATE AVAILABLE)"
        elif [[ "$local_vchanged" == "true" ]]; then
            local_prev=$(jq -r '.prev_index_version // ""' "$output_file")
            log_info "$op_name: index=$local_index (changed from $local_prev)"
        else
            log_debug "$op_name: index=$local_index (up to date)"
        fi
    ) &
    job_pids+=($!)
    active_jobs=$((active_jobs + 1))
done

# Wait for all remaining jobs
for pid in "${job_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
done

# Collect results in operator order
entries="[]"
updates_available=0

for idx in "${!op_names[@]}"; do
    op_name="${op_names[$idx]}"
    entry_file="$TMPDIR_WORK/${op_name}.json"

    if [[ -f "$entry_file" ]]; then
        entry=$(cat "$entry_file")
        entries=$(echo "$entries" | jq --argjson e "$entry" '. + [$e]')

        update_avail=$(echo "$entry" | jq -r '.update_available')
        if [[ "$update_avail" == "true" ]]; then
            updates_available=$((updates_available + 1))
        fi
    else
        # Fallback: worker failed, create minimal entry
        log_warn "$op_name: worker failed, creating placeholder entry"
        entry=$(jq -n \
            --arg name "$op_name" \
            --arg catalog "${op_catalogs[$idx]}" \
            --arg channel "${op_channels[$idx]}" \
            '{
                name: $name,
                catalog: $catalog,
                channel: $channel,
                index_version: "",
                scanned_version: "",
                update_available: false,
                error: "worker failed"
            }')
        entries=$(echo "$entries" | jq --argjson e "$entry" '. + [$e]')
    fi
done

tracker=$(jq -n \
    --arg checked "$check_date" \
    --argjson operators "$entries" \
    '{checked: $checked, operators: $operators}')

echo "$tracker" > "$TRACKER_FILE"
log_success "Wrote $TRACKER_FILE"

# Summary
total=$(echo "$entries" | jq 'length')
with_updates=$(echo "$entries" | jq '[.[] | select(.update_available)] | length')
changed=$(echo "$entries" | jq '[.[] | select(.version_changed == true)] | length')

print_summary "Index Version Check" \
    "Checked" "$check_date" \
    "Total operators" "$total" \
    "Updates available" "$with_updates" \
    "Index versions changed" "$changed"

if [[ "$updates_available" -gt 0 ]]; then
    echo ""
    log_warn "Operators with newer versions available in the index:"
    echo "$entries" | jq -r '.[] | select(.update_available) | "  \(.name): scanned=\(.scanned_version) → index=\(.index_version)"'
    echo ""
fi
