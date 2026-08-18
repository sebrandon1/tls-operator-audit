#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/install.sh"

TLS_TEST_ALL="$REPO_DIR/tls-test-all.sh"
SCAN_AND_EXPORT="$REPO_DIR/scan-and-export.sh"
TLS_TEST_ALL_CONTENT=$(cat "$TLS_TEST_ALL")
SCAN_AND_EXPORT_CONTENT=$(cat "$SCAN_AND_EXPORT")

CSV_INSTALLED='{"items":[{"metadata":{"name":"cert-manager-operator.v1.16.1"},"status":{"phase":"Succeeded"},"spec":{"version":"1.16.1"}}]}'
CSV_EMPTY='{"items":[]}'

echo "=== Dry-run flag and planning ==="

test_tls_test_all_documents_dry_run() {
    assert_contains "tls-test-all.sh usage documents --dry-run" \
        "$TLS_TEST_ALL_CONTENT" \
        "--dry-run"

    assert_contains "tls-test-all.sh parses --dry-run" \
        "$TLS_TEST_ALL_CONTENT" \
        "--dry-run)        DRY_RUN=true"
}

test_scan_and_export_forwards_dry_run() {
    assert_contains "scan-and-export.sh usage documents --dry-run" \
        "$SCAN_AND_EXPORT_CONTENT" \
        "--dry-run"

    assert_contains "scan-and-export.sh forwards --dry-run to tls-test-all.sh" \
        "$SCAN_AND_EXPORT_CONTENT" \
        'scan_args+=(--dry-run)'

    assert_contains "scan-and-export.sh skips dashboard export on dry-run" \
        "$SCAN_AND_EXPORT_CONTENT" \
        "skipping dashboard export and index version check"
}

test_dry_run_skips_tco_precheck() {
    assert_contains "tls-test-all.sh skips precheck_tco on dry-run" \
        "$TLS_TEST_ALL_CONTENT" \
        'if [[ "$DRY_RUN" != "true" ]]; then'

    assert_contains "tls-test-all.sh exits after printing the plan" \
        "$TLS_TEST_ALL_CONTENT" \
        "print_dry_run_plan"
}

test_dry_run_exits_before_mutations() {
    local plan_exit_line
    plan_exit_line=$(grep -n 'print_dry_run_plan' "$TLS_TEST_ALL" | head -1 | cut -d: -f1)
    local install_line
    install_line=$(grep -n 'install_operator ' "$TLS_TEST_ALL" | head -1 | cut -d: -f1)
    local collect_line
    collect_line=$(grep -n 'collect_endpoint_data ' "$TLS_TEST_ALL" | head -1 | cut -d: -f1)
    local uninstall_line
    uninstall_line=$(grep -n 'uninstall_operator ' "$TLS_TEST_ALL" | head -1 | cut -d: -f1)

    if [[ "$plan_exit_line" -lt "$install_line" && "$plan_exit_line" -lt "$collect_line" && "$plan_exit_line" -lt "$uninstall_line" ]]; then
        echo "  PASS: dry-run plan runs before install/scan/teardown"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: dry-run plan should run before install/scan/teardown"
        FAIL=$((FAIL + 1))
    fi
}

test_plan_scan_in_place() {
    local result
    result=$(plan_operator_action "cert-manager-operator" "redhat-operators" "$CSV_INSTALLED" "false")
    assert_eq "installed operator is SCAN in-place" $'yes\tSCAN in-place' "$result"
}

test_plan_install_scan_teardown() {
    local result
    result=$(plan_operator_action "rhacs-operator" "redhat-operators" "$CSV_EMPTY" "false")
    assert_eq "missing operator is INSTALL → SCAN → TEARDOWN" $'no\tINSTALL → SCAN → TEARDOWN' "$result"
}

test_plan_skip_teardown() {
    local result
    result=$(plan_operator_action "rhacs-operator" "redhat-operators" "$CSV_EMPTY" "true")
    assert_eq "skip-teardown drops TEARDOWN from the action" $'no\tINSTALL → SCAN' "$result"
}

test_plan_catalog_null() {
    local result
    result=$(plan_operator_action "skupper-operator" "null" "$CSV_EMPTY" "false")
    assert_eq "null catalog is SKIP" $'no\tSKIP (catalog null)' "$result"
}

test_plan_empty_catalog() {
    local result
    result=$(plan_operator_action "missing-op" "" "$CSV_EMPTY" "false")
    assert_eq "empty catalog is SKIP" $'no\tSKIP (catalog null)' "$result"
}

test_help_accepts_dry_run() {
    local output
    output=$(bash "$TLS_TEST_ALL" --help)
    assert_contains "help text mentions --dry-run" "$output" "--dry-run"
}

test_tls_test_all_documents_dry_run
test_scan_and_export_forwards_dry_run
test_dry_run_skips_tco_precheck
test_dry_run_exits_before_mutations
test_plan_scan_in_place
test_plan_install_scan_teardown
test_plan_skip_teardown
test_plan_catalog_null
test_plan_empty_catalog
test_help_accepts_dry_run

print_test_summary
