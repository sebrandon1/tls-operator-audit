#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/discovery.sh"
source "$SCRIPT_DIR/lib/scan.sh"
source "$SCRIPT_DIR/lib/results.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Audit OCP operators for TLS compliance using tls-compliance-operator.

Required:
  --kubeconfig <path>     Path to kubeconfig file
  --operator <name>       Operator name to audit (fuzzy match against CSVs)

Optional:
  --version <version>     Filter CSV match by version
  --list-operators        List all available operators on the cluster
  --all-operators         Scan every operator on the cluster
  --output-dir <dir>      Results directory (default: results)
  --keep-reports          Do not clean up TLSComplianceReport CRs after scan
  -h, --help              Show this help

Examples:
  $(basename "$0") --operator cert-manager-operator --kubeconfig ~/kubeconfig
  $(basename "$0") --list-operators --kubeconfig ~/kubeconfig
  $(basename "$0") --all-operators --kubeconfig ~/kubeconfig
  $(basename "$0") --operator cert-manager --version 1.15.0 --kubeconfig ~/kubeconfig
EOF
}

# Defaults
KUBECONFIG_PATH=""
OPERATOR_NAME=""
OPERATOR_VERSION=""
OUTPUT_DIR="$SCRIPT_DIR/results"
LIST_OPERATORS=false
ALL_OPERATORS=false
KEEP_REPORTS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubeconfig)
            require_arg "$1" "${2:-}"; KUBECONFIG_PATH="$2"; shift 2 ;;
        --operator)
            require_arg "$1" "${2:-}"; OPERATOR_NAME="$2"; shift 2 ;;
        --version)
            require_arg "$1" "${2:-}"; OPERATOR_VERSION="$2"; shift 2 ;;
        --output-dir)
            require_arg "$1" "${2:-}"; OUTPUT_DIR="$2"; shift 2 ;;
        --list-operators)
            LIST_OPERATORS=true; shift ;;
        --all-operators)
            ALL_OPERATORS=true; shift ;;
        --keep-reports)
            KEEP_REPORTS=true; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1 ;;
    esac
done

# Validation
if [[ -z "$KUBECONFIG_PATH" ]]; then
    log_error "Missing required flag: --kubeconfig"
    usage
    exit 1
fi

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    log_error "Kubeconfig file not found: $KUBECONFIG_PATH"
    exit 1
fi

if [[ "$LIST_OPERATORS" == "false" && "$ALL_OPERATORS" == "false" && -z "$OPERATOR_NAME" ]]; then
    log_error "Missing required flag: --operator (or use --list-operators / --all-operators)"
    usage
    exit 1
fi

require_cmd oc jq

export KUBECONFIG="$KUBECONFIG_PATH"

log_info "Connecting to cluster..."
require_cluster
log_success "Connected to $(oc whoami --show-server 2>/dev/null || echo 'cluster')"

start_timer

# Precheck: find tls-compliance-operator on cluster
precheck_tco

# List mode
if [[ "$LIST_OPERATORS" == "true" ]]; then
    list_operators
    print_duration
    exit 0
fi

# Scan a single operator
audit_operator() {
    local op_name="$1"
    local op_namespace="$2"
    local op_display="$3"
    local _op_version="$4"
    local image="$5"

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local results_dir="${OUTPUT_DIR}/${op_name}/${timestamp}"
    mkdir -p "$results_dir"

    log_info "Starting TLS audit for: $op_display"

    run_scan "$op_namespace" "$results_dir" "$image"
    local exit_code="${SCAN_EXIT_CODE:-2}"

    generate_reports "$results_dir"
    print_scan_summary "$results_dir" "$op_display" "$op_namespace" "$exit_code"

    if [[ "$KEEP_REPORTS" == "false" ]]; then
        cleanup_reports "$op_namespace"
    fi

    return "$exit_code"
}

# All-operators mode
if [[ "$ALL_OPERATORS" == "true" ]]; then
    discover_all_operators

    op_count=$(echo "$ALL_OPERATORS_LIST" | jq 'length')
    log_info "Scanning $op_count operators..."

    overall_exit=0
    for i in $(seq 0 $((op_count - 1))); do
        csv_name=$(echo "$ALL_OPERATORS_LIST" | jq -r ".[$i].csv_name")
        ns=$(echo "$ALL_OPERATORS_LIST" | jq -r ".[$i].namespace")
        display=$(echo "$ALL_OPERATORS_LIST" | jq -r ".[$i].display")
        version=$(echo "$ALL_OPERATORS_LIST" | jq -r ".[$i].version")

        echo ""
        log_info "━━━ Operator $((i + 1))/$op_count: $display ━━━"

        if ! audit_operator "$csv_name" "$ns" "$display" "$version" "$TCO_IMAGE"; then
            overall_exit=1
        fi
    done

    print_duration
    exit "$overall_exit"
fi

# Single operator mode
discover_operator "$OPERATOR_NAME" "$OPERATOR_VERSION"

audit_operator "$OPERATOR_CSV_NAME" "$OPERATOR_NAMESPACE" "$OPERATOR_DISPLAY_NAME" "$OPERATOR_VERSION" "$TCO_IMAGE"
exit_code=$?

print_duration
exit "$exit_code"
