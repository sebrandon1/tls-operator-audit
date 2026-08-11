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
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors
  -h, --help              Show this help
EOF
}

KUBECONFIG_PATH=""
OPERATORS_FILE="$SCRIPT_DIR/operators.yaml"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubeconfig)     require_arg "$1" "${2:-}"; KUBECONFIG_PATH="$2"; shift 2 ;;
        --operators)      require_arg "$1" "${2:-}"; OPERATORS_FILE="$2"; shift 2 ;;
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

entries="[]"
updates_available=0

for i in $(seq 0 $((operator_count - 1))); do
    op_name=$(yq -r ".operators[$i].name" "$OPERATORS_FILE")
    op_catalog=$(yq -r ".operators[$i].catalog" "$OPERATORS_FILE")
    op_channel=$(yq -r ".operators[$i].channel" "$OPERATORS_FILE")

    if [[ "$op_catalog" == "null" ]]; then
        log_debug "Skipping $op_name (no catalog)"

        # For pre-installed operators, get version from installed CSV
        installed_version=$(oc get csv -A -o json 2>/dev/null | jq -r --arg name "$op_name" '
            [.items[]
            | select(.status.phase == "Succeeded")
            | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
            | .[0].spec.version // ""')

        entry=$(jq -n \
            --arg name "$op_name" \
            --arg catalog "pre-installed" \
            --arg channel "" \
            --arg catalog_image "" \
            --arg catalog_url "" \
            --arg index_version "$installed_version" \
            --arg scanned_version "$(echo "$scanned_versions" | jq -r --arg n "$op_name" '.[$n] // ""')" \
            '{
                name: $name,
                catalog: $catalog,
                channel: $channel,
                catalog_image: $catalog_image,
                catalog_url: $catalog_url,
                index_version: $index_version,
                scanned_version: $scanned_version,
                update_available: ($index_version != $scanned_version and $index_version != "" and $scanned_version != "")
            }')
        entries=$(echo "$entries" | jq --argjson e "$entry" '. + [$e]')
        continue
    fi

    log_debug "Checking $op_name in $op_catalog/$op_channel..."

    pm_json=$(oc get packagemanifest "$op_name" -n openshift-marketplace -o json 2>/dev/null || echo '{}')

    if [[ "$pm_json" == "{}" ]]; then
        log_warn "$op_name not found in any catalog"
        catalog_image=$(echo "$catalog_images" | jq -r --arg c "$op_catalog" '.[$c] // ""')
        catalog_url=$(catalog_url_for "$catalog_image")
        entry=$(jq -n \
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
            }')
        entries=$(echo "$entries" | jq --argjson e "$entry" '. + [$e]')
        continue
    fi

    index_version=$(echo "$pm_json" | jq -r --arg ch "$op_channel" '
        .status.channels[]
        | select(.name == $ch)
        | .currentCSVDesc.version // ""')

    scanned_version=$(echo "$scanned_versions" | jq -r --arg n "$op_name" '.[$n] // ""')

    # Get previous index version from tracker for history
    prev_index=$(echo "$existing_tracker" | jq -r --arg n "$op_name" '
        .operators[]? | select(.name == $n) | .index_version // ""')

    update_available="false"
    if [[ -n "$index_version" && -n "$scanned_version" && "$index_version" != "$scanned_version" ]]; then
        update_available="true"
        updates_available=$((updates_available + 1))
    fi

    version_changed="false"
    if [[ -n "$prev_index" && -n "$index_version" && "$prev_index" != "$index_version" ]]; then
        version_changed="true"
    fi

    catalog_image=$(echo "$catalog_images" | jq -r --arg c "$op_catalog" '.[$c] // ""')
    catalog_url=$(catalog_url_for "$catalog_image")

    entry=$(jq -n \
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
        } + (if $version_changed then {version_changed: true, prev_index_version: $prev_index_version} else {} end)')

    entries=$(echo "$entries" | jq --argjson e "$entry" '. + [$e]')

    if [[ "$update_available" == "true" ]]; then
        log_warn "$op_name: index=$index_version scanned=$scanned_version (UPDATE AVAILABLE)"
    elif [[ "$version_changed" == "true" ]]; then
        log_info "$op_name: index=$index_version (changed from $prev_index)"
    else
        log_debug "$op_name: index=$index_version (up to date)"
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
