#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/discovery.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Query existing TLSComplianceReport CRs to assess ML-KEM/PQC compliance
for operators listed in operators.yaml. Requires tls-compliance-operator
to be running on the cluster (no new scan is deployed).

Options:
  --kubeconfig <path>     Path to kubeconfig (default: \$KUBECONFIG or ~/.kube/config)
  --operators <file>      Operators list file (default: operators.yaml)
  --all-namespaces        Report on all namespaces, not just listed operators
  --verbose               Enable debug output
  --quiet                 Suppress all output except errors
  -h, --help              Show this help
EOF
}

KUBECONFIG_PATH=""
OPERATORS_FILE="$SCRIPT_DIR/operators.yaml"
ALL_NAMESPACES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kubeconfig)     require_arg "$1" "${2:-}"; KUBECONFIG_PATH="$2"; shift 2 ;;
        --operators)      require_arg "$1" "${2:-}"; OPERATORS_FILE="$2"; shift 2 ;;
        --all-namespaces) ALL_NAMESPACES=true; shift ;;
        --verbose)        LOG_LEVEL=4; shift ;;
        --quiet)          LOG_LEVEL=0; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                log_error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

require_cmd oc jq
resolve_kubeconfig "$KUBECONFIG_PATH"

log_info "Connecting to cluster..."
require_cluster
log_success "Connected to $(oc whoami --show-server 2>/dev/null || echo 'cluster')"

precheck_tco

log_info "Fetching TLSComplianceReport data..."
ALL_REPORTS=$(oc get tlscompliancereports -o json 2>/dev/null)

report_count=$(echo "$ALL_REPORTS" | jq '.items | length')
log_info "Found $report_count TLSComplianceReport CRs on cluster"

if [[ "$ALL_NAMESPACES" == "true" ]]; then
    echo ""
    echo -e "${BOLD}ML-KEM COMPLIANCE REPORT (ALL NAMESPACES)${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "%-45s %6s %10s %8s %10s %8s\n" "NAMESPACE" "TOTAL" "COMPLIANT" "ML-KEM" "PQC READY" "CLOSED"
    printf "%-45s %6s %10s %8s %10s %8s\n" "---------" "-----" "---------" "------" "---------" "------"

    echo "$ALL_REPORTS" | jq -r '
      [.items[] | {
        ns: .spec.sourceNamespace,
        status: .status.complianceStatus,
        pqc: .status.pqcReadiness,
        mlkem: .status.mlkemSupported
      }]
      | group_by(.ns)
      | map({
        ns: .[0].ns,
        total: length,
        compliant: ([.[] | select(.status == "Compliant")] | length),
        mlkem: ([.[] | select(.mlkem == true)] | length),
        pqc_ready: ([.[] | select(.pqc == "PQCReady")] | length),
        closed: ([.[] | select(.status == "Closed" or .status == "Timeout")] | length)
      })
      | sort_by(.ns)
      | .[]
      | "\(.ns)\t\(.total)\t\(.compliant)\t\(.mlkem)\t\(.pqc_ready)\t\(.closed)"
    ' | while IFS=$'\t' read -r ns total compliant mlkem pqc closed; do
        if [[ "$mlkem" -eq "$total" && "$total" -gt 0 ]]; then
            color="$GREEN"
        elif [[ "$mlkem" -gt 0 ]]; then
            color="$YELLOW"
        else
            color="$RED"
        fi
        printf "${color}%-45s %6s %10s %8s %10s %8s${NC}\n" "$ns" "$total" "$compliant" "$mlkem" "$pqc" "$closed"
    done

    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi

if [[ ! -f "$OPERATORS_FILE" ]]; then
    log_error "Operators file not found: $OPERATORS_FILE"
    exit 1
fi

require_cmd yq

operator_count=$(yq '.operators | length' "$OPERATORS_FILE")
log_info "Checking $operator_count operators from $(basename "$OPERATORS_FILE")..."

echo ""
echo -e "${BOLD}ML-KEM COMPLIANCE REPORT — TARGET OPERATORS${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
printf "%-35s %-12s %6s %10s %8s %10s %7s\n" "OPERATOR" "INSTALLED" "TOTAL" "COMPLIANT" "ML-KEM" "PQC READY" "STATUS"
printf "%-35s %-12s %6s %10s %8s %10s %7s\n" "--------" "---------" "-----" "---------" "------" "---------" "------"

has_failure=false

for i in $(seq 0 $((operator_count - 1))); do
    op_name=$(yq -r ".operators[$i].name" "$OPERATORS_FILE")
    ns_count=$(yq ".operators[$i].namespaces | length" "$OPERATORS_FILE")

    # Check if the operator is installed (has a matching CSV)
    csv_match=$(oc get csv -A -o json 2>/dev/null | jq -r --arg name "$op_name" '
        [.items[] | select(.status.phase == "Succeeded") |
         select((.metadata.name | ascii_downcase | contains($name | ascii_downcase))
            or (.spec.displayName // "" | ascii_downcase | contains($name | ascii_downcase)))]
        | length')

    if [[ "$csv_match" -eq 0 ]]; then
        printf "${YELLOW}%-35s %-12s %6s %10s %8s %10s %7s${NC}\n" \
            "$op_name" "NO" "-" "-" "-" "-" "N/A"
        continue
    fi

    # Collect stats across all namespaces for this operator
    ns_filter=""
    for j in $(seq 0 $((ns_count - 1))); do
        ns=$(yq -r ".operators[$i].namespaces[$j]" "$OPERATORS_FILE")
        if [[ -n "$ns_filter" ]]; then
            ns_filter="${ns_filter} or "
        fi
        ns_filter="${ns_filter}.spec.sourceNamespace == \"$ns\""
    done

    stats=$(echo "$ALL_REPORTS" | jq --argjson dummy 0 "
        [.items[] | select($ns_filter)]
        | {
            total: length,
            compliant: ([.[] | select(.status.complianceStatus == \"Compliant\")] | length),
            mlkem: ([.[] | select(.status.mlkemSupported == true)] | length),
            pqc_ready: ([.[] | select(.status.pqcReadiness == \"PQCReady\")] | length),
            closed: ([.[] | select(.status.complianceStatus == \"Closed\" or .status.complianceStatus == \"Timeout\")] | length)
        }")

    total=$(echo "$stats" | jq '.total')
    compliant=$(echo "$stats" | jq '.compliant')
    mlkem=$(echo "$stats" | jq '.mlkem')
    pqc=$(echo "$stats" | jq '.pqc_ready')
    closed=$(echo "$stats" | jq '.closed')

    reachable=$((total - closed))
    if [[ "$reachable" -gt 0 && "$mlkem" -eq "$reachable" ]]; then
        status="PASS"
        color="$GREEN"
    elif [[ "$total" -eq 0 ]]; then
        status="NONE"
        color="$YELLOW"
    elif [[ "$mlkem" -gt 0 ]]; then
        status="PARTIAL"
        color="$YELLOW"
        has_failure=true
    else
        status="FAIL"
        color="$RED"
        has_failure=true
    fi

    printf "${color}%-35s %-12s %6s %10s %8s %10s %7s${NC}\n" \
        "$op_name" "YES" "$total" "$compliant" "$mlkem" "$pqc" "$status"
done

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}Legend:${NC}"
echo "  TOTAL     = Total endpoints discovered by tls-compliance-operator"
echo "  COMPLIANT = Endpoints with TLS 1.2+ (TLS compliance)"
echo "  ML-KEM    = Endpoints offering ML-KEM key exchange (PQC)"
echo "  PQC READY = Endpoints classified as PQC Ready"
echo "  STATUS    = PASS (all reachable endpoints have ML-KEM) / PARTIAL / FAIL / N/A (not installed)"
echo ""

# Show detailed endpoint breakdown for installed operators
echo -e "${BOLD}DETAILED ENDPOINT BREAKDOWN (installed operators only)${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for i in $(seq 0 $((operator_count - 1))); do
    op_name=$(yq -r ".operators[$i].name" "$OPERATORS_FILE")
    ns_count=$(yq ".operators[$i].namespaces | length" "$OPERATORS_FILE")

    ns_filter=""
    for j in $(seq 0 $((ns_count - 1))); do
        ns=$(yq -r ".operators[$i].namespaces[$j]" "$OPERATORS_FILE")
        if [[ -n "$ns_filter" ]]; then
            ns_filter="${ns_filter} or "
        fi
        ns_filter="${ns_filter}.spec.sourceNamespace == \"$ns\""
    done

    endpoints=$(echo "$ALL_REPORTS" | jq -r "
        [.items[] | select($ns_filter)]
        | sort_by(.spec.sourceNamespace, .spec.host)
        | .[]
        | \"\(.spec.sourceNamespace)\t\(.spec.host):\(.spec.port)\t\(.status.complianceStatus)\t\(.status.pqcReadiness // \"-\")\tMLKEM=\(.status.mlkemSupported)\"
    " 2>/dev/null)

    if [[ -z "$endpoints" ]]; then
        continue
    fi

    echo ""
    echo -e "${BOLD}  $op_name${NC}"
    echo "$endpoints" | while IFS=$'\t' read -r ns endpoint status pqc mlkem; do
        if [[ "$mlkem" == "MLKEM=true" ]]; then
            color="$GREEN"
        elif [[ "$status" == "Closed" || "$status" == "Timeout" ]]; then
            color="$YELLOW"
        else
            color="$RED"
        fi
        printf "  ${color}  %-30s %-55s %-12s %-12s %s${NC}\n" "$ns" "$endpoint" "$status" "$pqc" "$mlkem"
    done
done

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ "$has_failure" == "true" ]]; then
    exit 1
fi
exit 0
