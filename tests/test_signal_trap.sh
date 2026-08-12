#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TLS_TEST_ALL="$REPO_DIR/tls-test-all.sh"
TLS_TEST_ALL_CONTENT=$(cat "$TLS_TEST_ALL")

echo "=== Signal trap for graceful cleanup ==="

test_signal_trap_function_defined() {
    assert_contains "tls-test-all.sh defines cleanup_on_interrupt" \
        "$TLS_TEST_ALL_CONTENT" \
        "cleanup_on_interrupt"
}

test_trap_set_for_int_and_term() {
    assert_contains "trap set for INT and TERM signals" \
        "$TLS_TEST_ALL_CONTENT" \
        "trap cleanup_on_interrupt INT TERM"
}

test_current_operator_tracking() {
    assert_contains "tracks current operator" \
        "$TLS_TEST_ALL_CONTENT" \
        "CURRENT_OPERATOR="

    assert_contains "tracks whether operator was installed by script" \
        "$TLS_TEST_ALL_CONTENT" \
        "WAS_INSTALLED_BY_SCRIPT="
}

test_cleanup_uninstalls_operator() {
    assert_contains "cleanup calls uninstall_operator" \
        "$TLS_TEST_ALL_CONTENT" \
        'uninstall_operator "$CURRENT_OPERATOR"'
}

test_cleanup_prints_partial_summary() {
    assert_contains "cleanup prints partial summary" \
        "$TLS_TEST_ALL_CONTENT" \
        "PARTIAL ML-KEM COMPLIANCE SUMMARY (INTERRUPTED)"
}

test_cleanup_exits_with_130() {
    assert_contains "cleanup exits with 130 (128 + SIGINT)" \
        "$TLS_TEST_ALL_CONTENT" \
        "exit 130"
}

test_operator_marked_as_installed() {
    assert_contains "operator marked as installed after install_operator" \
        "$TLS_TEST_ALL_CONTENT" \
        "WAS_INSTALLED_BY_SCRIPT=true"
}

test_tracking_reset_after_teardown() {
    if echo "$TLS_TEST_ALL_CONTENT" | grep -A 10 "uninstall_operator" | grep -q "WAS_INSTALLED_BY_SCRIPT=false"; then
        echo "  PASS: Tracking reset after teardown"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Should reset WAS_INSTALLED_BY_SCRIPT after teardown"
        FAIL=$((FAIL + 1))
    fi

    assert_contains "current operator reset" \
        "$TLS_TEST_ALL_CONTENT" \
        'CURRENT_OPERATOR=""'
}

# Run all tests
test_signal_trap_function_defined
test_trap_set_for_int_and_term
test_current_operator_tracking
test_cleanup_uninstalls_operator
test_cleanup_prints_partial_summary
test_cleanup_exits_with_130
test_operator_marked_as_installed
test_tracking_reset_after_teardown

print_test_summary
