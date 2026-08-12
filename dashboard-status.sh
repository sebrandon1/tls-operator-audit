#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0")

Print a summary of the current dashboard state: scan freshness, ML-KEM
compliance, per-operator status, and index version drift. No cluster
access required — reads from local data files only.

  -h, --help    Show this help
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage; exit 0
fi

SCAN_RESULTS="$SCRIPT_DIR/docs/_data/scan-results.json"
INDEX_VERSIONS="$SCRIPT_DIR/docs/_data/index-versions.json"
SCAN_HISTORY="$SCRIPT_DIR/docs/_data/scan-history.json"

for f in "$SCAN_RESULTS" "$INDEX_VERSIONS" "$SCAN_HISTORY"; do
    if [[ ! -f "$f" ]]; then
        log_error "Missing data file: $f"
        log_error "Run scan-and-export.sh first."
        exit 1
    fi
done

# ============================================================================
# Scan summary
# ============================================================================
scan_date=$(jq -r '.scan_date' "$SCAN_RESULTS")
cluster=$(jq -r '.cluster' "$SCAN_RESULTS")
ocp_version=$(jq -r '.ocp_version' "$SCAN_RESULTS")
tco_version=$(jq -r '.tco_version // "unknown"' "$SCAN_RESULTS")
total_ops=$(jq '.summary.total_operators' "$SCAN_RESULTS")
pass=$(jq '.summary.pass' "$SCAN_RESULTS")
partial=$(jq '.summary.partial' "$SCAN_RESULTS")
none=$(jq '.summary.none' "$SCAN_RESULTS")
error=$(jq '.summary.error' "$SCAN_RESULTS")
mlkem_pct=$(jq '.summary.mlkem_percent' "$SCAN_RESULTS")
mlkem_eps=$(jq '.summary.mlkem_endpoints' "$SCAN_RESULTS")
total_eps=$(jq '.summary.total_endpoints' "$SCAN_RESULTS")

# Scan age
scan_epoch=$(date -u -jf '%Y-%m-%dT%H:%M:%SZ' "$scan_date" '+%s' 2>/dev/null || date -d "$scan_date" '+%s' 2>/dev/null || echo "0")
now_epoch=$(date '+%s')
if [[ "$scan_epoch" -gt 0 ]]; then
    age_hours=$(( (now_epoch - scan_epoch) / 3600 ))
    if [[ "$age_hours" -lt 24 ]]; then
        scan_age="${age_hours}h ago"
    else
        scan_age="$(( age_hours / 24 ))d ago"
    fi
else
    scan_age="unknown"
fi

print_summary "Dashboard Status" \
    "Last scan" "$scan_date ($scan_age)" \
    "Cluster" "$cluster" \
    "OCP version" "$ocp_version" \
    "TCO version" "$tco_version" \
    "Operators" "$total_ops" \
    "ML-KEM" "${mlkem_pct}% ($mlkem_eps/$total_eps endpoints)" \
    "Pass" "$pass" \
    "Partial" "$partial" \
    "None" "$none" \
    "Error" "$error"

# ============================================================================
# Per-operator table
# ============================================================================
echo ""
printf "  %-45s %-12s %-8s %s\n" "OPERATOR" "VERSION" "STATUS" "ML-KEM"
printf "  %-45s %-12s %-8s %s\n" "--------" "-------" "------" "------"

jq -r '.operators[] | "\(.name)\t\(.version // "-")\t\(.status)\t\(.mlkem_endpoints)/\(.reachable_endpoints)"' "$SCAN_RESULTS" | \
while IFS=$'\t' read -r name ver status mlkem; do
    color="$NC"
    case "$status" in
        PASS)    color="$GREEN" ;;
        PARTIAL) color="$YELLOW" ;;
        FAIL|ERROR) color="$RED" ;;
    esac
    printf "  ${color}%-45s %-12s %-8s %s${NC}\n" "$name" "$ver" "$status" "$mlkem"
done

# ============================================================================
# Index version drift
# ============================================================================
echo ""
updates=$(jq '[.operators[] | select(.update_available)] | length' "$INDEX_VERSIONS")
checked=$(jq -r '.checked' "$INDEX_VERSIONS")

if [[ "$updates" -gt 0 ]]; then
    log_warn "$updates operator(s) have newer versions in the index (checked $checked):"
    jq -r '.operators[] | select(.update_available) | "  \(.name): scanned=\(.scanned_version) → index=\(.index_version)"' "$INDEX_VERSIONS"
else
    log_success "All operators at latest index versions (checked $checked)"
fi

# ============================================================================
# History
# ============================================================================
history_count=$(jq 'length' "$SCAN_HISTORY")
echo ""
log_info "Scan history: $history_count entries"
log_info "Dashboard: https://sebrandon1.github.io/tls-operator-audit/"
