#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/discovery.sh"
source "$SCRIPT_DIR/lib/install.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install each operator from operators.yaml one at a time, scan for ML-KEM
compliance using the tls-compliance-operator, collect results, then tear down.

Options:
  --kubeconfig <path>     Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
  --operators <file>      Operators list file (default: operators.yaml)
  --only <name>           Test a single operator from the list
  --skip-teardown         Leave operators installed after scanning
  --scan-wait <seconds>   Time to wait for endpoint discovery (default: 90)
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors
  -h, --help              Show this help
EOF
}

KUBECONFIG_PATH=""
OPERATORS_FILE="$SCRIPT_DIR/operators.yaml"
ONLY_OPERATOR=""
SKIP_TEARDOWN=false
SCAN_WAIT=90

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubeconfig)     require_arg "$1" "${2:-}"; KUBECONFIG_PATH="$2"; shift 2 ;;
        --operators)      require_arg "$1" "${2:-}"; OPERATORS_FILE="$2"; shift 2 ;;
        --only)           require_arg "$1" "${2:-}"; ONLY_OPERATOR="$2"; shift 2 ;;
        --skip-teardown)  SKIP_TEARDOWN=true; shift ;;
        --scan-wait)      require_arg "$1" "${2:-}"; SCAN_WAIT="$2"; shift 2 ;;
        --verbose)        LOG_LEVEL=4; shift ;;
        --quiet)          LOG_LEVEL=0; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ ! -f "$OPERATORS_FILE" ]]; then
    log_error "Operators file not found: $OPERATORS_FILE"; exit 1
fi

require_cmd oc jq yq
resolve_kubeconfig "$KUBECONFIG_PATH"

log_info "Connecting to cluster..."
require_cluster
log_success "Connected to $(oc whoami --show-server 2>/dev/null || echo 'cluster')"

start_timer
precheck_tco

operator_count=$(yq '.operators | length' "$OPERATORS_FILE")
RESULTS_BASE="$SCRIPT_DIR/results"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Collect summary data for final table
declare -a SUMMARY_NAMES=()
declare -a SUMMARY_STATUS=()
declare -a SUMMARY_TOTAL=()
declare -a SUMMARY_MLKEM=()
declare -a SUMMARY_DETAIL=()

collect_endpoint_data() {
    local op_name="$1"
    local op_index="$2"
    local results_dir="$3"

    local ns_count
    ns_count=$(yq ".operators[$op_index].namespaces | length" "$OPERATORS_FILE")

    local ns_filter=""
    for j in $(seq 0 $((ns_count - 1))); do
        local ns
        ns=$(yq -r ".operators[$op_index].namespaces[$j]" "$OPERATORS_FILE")
        if [[ -n "$ns_filter" ]]; then
            ns_filter="${ns_filter} or "
        fi
        ns_filter="${ns_filter}.spec.sourceNamespace == \"$ns\""
    done

    local report_json
    report_json=$(oc get tlscompliancereports -o json 2>/dev/null)

    local endpoints
    endpoints=$(echo "$report_json" | jq --argjson dummy 0 "
        [.items[] | select($ns_filter)]")

    echo "$endpoints" > "$results_dir/report.json"

    local total mlkem compliant closed
    total=$(echo "$endpoints" | jq 'length')
    mlkem=$(echo "$endpoints" | jq '[.[] | select(.status.mlkemSupported == true)] | length')
    compliant=$(echo "$endpoints" | jq '[.[] | select(.status.complianceStatus == "Compliant")] | length')
    closed=$(echo "$endpoints" | jq '[.[] | select(.status.complianceStatus == "Closed" or .status.complianceStatus == "Timeout")] | length')

    local reachable=$((total - closed))
    local status
    if [[ "$total" -eq 0 ]]; then
        status="NONE"
    elif [[ "$reachable" -gt 0 && "$mlkem" -eq "$reachable" ]]; then
        status="PASS"
    elif [[ "$mlkem" -gt 0 ]]; then
        status="PARTIAL"
    else
        status="FAIL"
    fi

    SUMMARY_TOTAL+=("$total")
    SUMMARY_MLKEM+=("$mlkem")
    SUMMARY_STATUS+=("$status")

    local detail
    detail=$(echo "$endpoints" | jq -r '
        sort_by(.spec.sourceNamespace, .spec.host)
        | .[]
        | "    \(.spec.sourceNamespace)\t\(.spec.host):\(.spec.port)\t\(.status.complianceStatus)\t\(.status.pqcReadiness // "-")\tMLKEM=\(.status.mlkemSupported)"
    ' 2>/dev/null)
    SUMMARY_DETAIL+=("$detail")

    echo ""
    echo -e "${BOLD}  Results: $op_name${NC}"
    echo -e "  Endpoints: $total | Compliant: $compliant | ML-KEM: $mlkem | Closed: $closed | Status: $status"
    if [[ -n "$detail" ]]; then
        echo "$detail" | while IFS=$'\t' read -r ns endpoint st pqc mk; do
            if [[ "$mk" == "MLKEM=true" ]]; then
                printf "  ${GREEN}%-30s %-50s %-12s %-12s %s${NC}\n" "$ns" "$endpoint" "$st" "$pqc" "$mk"
            elif [[ "$st" == "Closed" || "$st" == "Timeout" ]]; then
                printf "  ${YELLOW}%-30s %-50s %-12s %-12s %s${NC}\n" "$ns" "$endpoint" "$st" "$pqc" "$mk"
            else
                printf "  ${RED}%-30s %-50s %-12s %-12s %s${NC}\n" "$ns" "$endpoint" "$st" "$pqc" "$mk"
            fi
        done
    fi
}

# Main loop
for i in $(seq 0 $((operator_count - 1))); do
    op_name=$(yq -r ".operators[$i].name" "$OPERATORS_FILE")
    op_project=$(yq -r ".operators[$i].project" "$OPERATORS_FILE")
    op_catalog=$(yq -r ".operators[$i].catalog" "$OPERATORS_FILE")
    op_channel=$(yq -r ".operators[$i].channel" "$OPERATORS_FILE")

    if [[ -n "$ONLY_OPERATOR" && "$op_name" != "$ONLY_OPERATOR" ]]; then
        continue
    fi

    echo ""
    echo -e "${BOLD}━━━ [$((i + 1))/$operator_count] $op_project ($op_name) ━━━${NC}"

    SUMMARY_NAMES+=("$op_name")
    results_dir="$RESULTS_BASE/$op_name/$TIMESTAMP"
    mkdir -p "$results_dir"

    # Check if already installed
    if is_operator_installed "$op_name"; then
        log_info "Already installed, scanning in-place..."
        collect_endpoint_data "$op_name" "$i" "$results_dir"
        continue
    fi

    # Check if installable
    if [[ "$op_catalog" == "null" ]]; then
        log_warn "Not available in any catalog, skipping"
        SUMMARY_TOTAL+=("-")
        SUMMARY_MLKEM+=("-")
        SUMMARY_STATUS+=("N/A")
        SUMMARY_DETAIL+=("")
        continue
    fi

    # Install → scan → teardown
    if ! install_operator "$op_name" "$op_channel" "$op_catalog"; then
        log_error "Failed to install $op_name"
        SUMMARY_TOTAL+=("0")
        SUMMARY_MLKEM+=("0")
        SUMMARY_STATUS+=("ERROR")
        SUMMARY_DETAIL+=("")
        continue
    fi

    log_info "Waiting ${SCAN_WAIT}s for tls-compliance-operator to discover endpoints..."
    sleep "$SCAN_WAIT"

    collect_endpoint_data "$op_name" "$i" "$results_dir"

    if [[ "$SKIP_TEARDOWN" == "false" ]]; then
        uninstall_operator "$op_name"
        ns_count_cleanup=$(yq ".operators[$i].namespaces | length" "$OPERATORS_FILE")
        for j in $(seq 0 $((ns_count_cleanup - 1))); do
            cleanup_stale_reports "$(yq -r ".operators[$i].namespaces[$j]" "$OPERATORS_FILE")"
        done
    fi
done

# Final summary table
echo ""
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  ML-KEM COMPLIANCE SUMMARY${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "  %-40s %8s %8s %8s\n" "OPERATOR" "TOTAL" "ML-KEM" "STATUS"
printf "  %-40s %8s %8s %8s\n" "--------" "-----" "------" "------"

for idx in "${!SUMMARY_NAMES[@]}"; do
    local_name="${SUMMARY_NAMES[$idx]}"
    local_total="${SUMMARY_TOTAL[$idx]}"
    local_mlkem="${SUMMARY_MLKEM[$idx]}"
    local_status="${SUMMARY_STATUS[$idx]}"

    color="$NC"
    case "$local_status" in
        PASS)    color="$GREEN" ;;
        PARTIAL) color="$YELLOW" ;;
        FAIL)    color="$RED" ;;
        N/A)     color="$YELLOW" ;;
        ERROR)   color="$RED" ;;
    esac

    printf "  ${color}%-40s %8s %8s %8s${NC}\n" "$local_name" "$local_total" "$local_mlkem" "$local_status"
done

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_duration
