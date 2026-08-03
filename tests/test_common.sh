#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# ===========================================================================
echo "=== Bug #1: Log functions under set -e ==="
# ===========================================================================

test_log_quiet_mode() {
    local output exit_code=0
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=0
        log_error "test error"
        log_warn "test warn"
        log_info "test info"
        log_success "test success"
        log_debug "test debug"
        echo "SURVIVED"
    ' 2>&1) || exit_code=$?

    assert_exit_code "log functions survive LOG_LEVEL=0" "0" "$exit_code"
    assert_contains "script completes successfully" "$output" "SURVIVED"
}

test_log_error_outputs() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=1
        log_error "visible error"
    ' 2>&1)

    assert_contains "log_error visible at level 1" "$output" "visible error"
}

test_log_info_suppressed() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=1
        log_info "should not appear"
        echo "DONE"
    ' 2>&1)

    assert_not_contains "log_info suppressed at level 1" "$output" "should not appear"
    assert_contains "script completes" "$output" "DONE"
}

test_log_debug_level4() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=4
        log_debug "debug msg"
    ' 2>&1)

    assert_contains "log_debug visible at level 4" "$output" "debug msg"
}

test_require_cmd_exit() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=0
        require_cmd nonexistent_cmd_xyz
    ' 2>/dev/null || exit_code=$?

    assert_eq "require_cmd exits on missing command" "1" "$exit_code"
}

test_log_quiet_mode
test_log_error_outputs
test_log_info_suppressed
test_log_debug_level4
test_require_cmd_exit

# ===========================================================================
echo ""
echo "=== Bug #10: require_arg guards ==="
# ===========================================================================

test_require_arg_valid() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        require_arg "--kubeconfig" "/path/to/file"
    ' 2>/dev/null || exit_code=$?

    assert_exit_code "require_arg accepts valid value" "0" "$exit_code"
}

test_require_arg_missing() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        require_arg "--kubeconfig"
    ' 2>/dev/null || exit_code=$?

    assert_eq "require_arg rejects missing value" "1" "$exit_code"
}

test_require_arg_flag_as_value() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        require_arg "--kubeconfig" "--operator"
    ' 2>/dev/null || exit_code=$?

    assert_eq "require_arg rejects flag-as-value" "1" "$exit_code"
}

test_require_arg_empty_value() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        require_arg "--kubeconfig" ""
    ' 2>/dev/null || exit_code=$?

    assert_eq "require_arg rejects empty value" "1" "$exit_code"
}

test_require_arg_error_message() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        require_arg "--kubeconfig"
    ' 2>&1) || true

    assert_contains "error message names the flag" "$output" "--kubeconfig"
}

test_require_arg_valid
test_require_arg_missing
test_require_arg_flag_as_value
test_require_arg_empty_value
test_require_arg_error_message

print_test_summary
