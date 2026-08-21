#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/discovery.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Full pipeline: scan all operators for TLS/ML-KEM compliance, export dashboard
data, and check index versions for drift. Wraps tls-test-all.sh,
export-dashboard.sh, and check-index-versions.sh into a single command.

Options:
  --kubeconfig <path>     Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
  --operators <file>      Operators list file (default: operators.yaml)
  --only <name>           Scan a single operator
  --exclude <name>        Exclude operator(s) from scanning (repeatable)
  --skip-scan             Skip scanning, just re-export from existing results
  --skip-teardown         Leave operators installed after scanning (default: true)
  --dry-run               Preview scan actions without changing the cluster or dashboard
  --update-jira           Post scan results as comments on operators.yaml Jira tickets
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors
  -h, --help              Show this help
EOF
}

KUBECONFIG_PATH=""
OPERATORS_FILE="$SCRIPT_DIR/operators.yaml"
ONLY_OPERATOR=""
EXCLUDE_OPERATORS=()
SKIP_SCAN=false
SKIP_TEARDOWN=true
DRY_RUN=false
UPDATE_JIRA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubeconfig)     require_arg "$1" "${2:-}"; KUBECONFIG_PATH="$2"; shift 2 ;;
        --operators)      require_arg "$1" "${2:-}"; export OPERATORS_FILE="$2"; shift 2 ;;
        --only)           require_arg "$1" "${2:-}"; ONLY_OPERATOR="$2"; shift 2 ;;
        --exclude)        require_arg "$1" "${2:-}"; EXCLUDE_OPERATORS+=("$2"); shift 2 ;;
        --skip-scan)      SKIP_SCAN=true; shift ;;
        --skip-teardown)  SKIP_TEARDOWN=true; shift ;;
        --dry-run)        DRY_RUN=true; shift ;;
        --update-jira)    UPDATE_JIRA=true; shift ;;
        --verbose)        export LOG_LEVEL=4; shift ;;
        --quiet)          export LOG_LEVEL=0; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

require_cmd oc jq yq bc
resolve_kubeconfig "$KUBECONFIG_PATH"
require_cluster

start_timer

# ============================================================================
# Gather cluster info
# ============================================================================
log_info "Gathering cluster info..."
if [[ "$DRY_RUN" != "true" ]]; then
    precheck_tco
    TCO_VERSION=$(echo "$TCO_IMAGE" | sed 's/.*://')
else
    log_info "Dry run: skipping tls-compliance-operator precheck"
    TCO_VERSION=""
fi

OCP_VERSION=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion // "unknown"')
CLUSTER=$(oc whoami --show-server 2>/dev/null | sed 's|https://api\.||;s|\..*||')

log_info "Cluster: $CLUSTER"
log_info "OCP: $OCP_VERSION"
if [[ -n "$TCO_VERSION" ]]; then
    log_info "TCO: $TCO_VERSION"
fi

# ============================================================================
# Step 1: Scan
# ============================================================================
if [[ "$SKIP_SCAN" == "false" ]]; then
    log_info "Starting operator scan..."
    scan_args=(--kubeconfig "$KUBECONFIG")
    if [[ "$SKIP_TEARDOWN" == "true" ]]; then
        scan_args+=(--skip-teardown)
    fi
    if [[ -n "$ONLY_OPERATOR" ]]; then
        scan_args+=(--only "$ONLY_OPERATOR")
    fi
    for excluded in "${EXCLUDE_OPERATORS[@]}"; do
        scan_args+=(--exclude "$excluded")
    done
    if [[ "$DRY_RUN" == "true" ]]; then
        scan_args+=(--dry-run)
    fi
    if [[ "$UPDATE_JIRA" == "true" ]]; then
        scan_args+=(--update-jira)
    fi
    if [[ "${LOG_LEVEL:-3}" -ge 4 ]]; then
        scan_args+=(--verbose)
    fi

    bash "$SCRIPT_DIR/tls-test-all.sh" "${scan_args[@]}"
else
    log_info "Skipping scan (--skip-scan), using existing results"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run: skipping dashboard export and index version check"
    print_duration
    exit 0
fi

# ============================================================================
# Step 2: Export dashboard
# ============================================================================
log_info "Exporting dashboard data..."
SCAN_MODE="all-operators"
if [[ -n "$ONLY_OPERATOR" ]]; then
    SCAN_MODE="single-operator"
fi
export_args=(
    --results-dir "$SCRIPT_DIR/results"
    --cluster "$CLUSTER"
    --ocp-version "$OCP_VERSION"
    --tco-version "$TCO_VERSION"
    --scan-mode "$SCAN_MODE"
    --scan-kubeconfig "$KUBECONFIG"
)
if [[ -n "$ONLY_OPERATOR" ]]; then
    export_args+=(--scan-operator "$ONLY_OPERATOR")
fi
if [[ "${LOG_LEVEL:-3}" -ge 4 ]]; then
    export_args+=(--verbose)
fi

bash "$SCRIPT_DIR/export-dashboard.sh" "${export_args[@]}"

# ============================================================================
# Step 3: Check index versions
# ============================================================================
log_info "Checking index versions..."
version_args=(--kubeconfig "$KUBECONFIG")
if [[ "${LOG_LEVEL:-3}" -ge 4 ]]; then
    version_args+=(--verbose)
fi

bash "$SCRIPT_DIR/check-index-versions.sh" "${version_args[@]}"

# ============================================================================
# Summary
# ============================================================================
scan_results="$SCRIPT_DIR/docs/_data/scan-results.json"
index_versions="$SCRIPT_DIR/docs/_data/index-versions.json"

total_ops=$(jq '.summary.total_operators' "$scan_results")
mlkem_pct=$(jq '.summary.mlkem_percent' "$scan_results")
mlkem_eps=$(jq '.summary.mlkem_endpoints' "$scan_results")
total_eps=$(jq '.summary.total_endpoints' "$scan_results")
updates=$(jq '[.operators[] | select(.update_available)] | length' "$index_versions")

print_summary "Scan & Export Complete" \
    "Cluster" "$CLUSTER" \
    "OCP version" "$OCP_VERSION" \
    "TCO version" "$TCO_VERSION" \
    "Operators" "$total_ops" \
    "ML-KEM" "${mlkem_pct}% ($mlkem_eps/$total_eps endpoints)" \
    "Index updates" "$updates"

print_duration

# List changed files for easy commit
echo ""
log_info "Changed data files:"
git -C "$SCRIPT_DIR" diff --name-only 2>/dev/null | grep -E "^docs/_data/|^docs/badges/" || echo "  (none)"
git -C "$SCRIPT_DIR" ls-files --others --exclude-standard 2>/dev/null | grep -E "^docs/" || true
