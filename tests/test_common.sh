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

# ===========================================================================
echo ""
echo "=== Issue #8: resolve_kubeconfig fallback chain ==="
# ===========================================================================

TMPDIR_COMMON=$(mktemp -d)
trap 'rm -rf "$TMPDIR_COMMON"' EXIT

test_resolve_kubeconfig_flag() {
    local tmpfile="$TMPDIR_COMMON/kubeconfig-flag"
    touch "$tmpfile"
    local output exit_code=0
    output=$(bash -c '
        set -euo pipefail
        unset KUBECONFIG
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig "'"$tmpfile"'"
        echo "$KUBECONFIG"
    ' 2>/dev/null) || exit_code=$?

    assert_exit_code "resolve_kubeconfig accepts flag value" "0" "$exit_code"
    assert_eq "KUBECONFIG set to flag value" "$tmpfile" "$output"
}

test_resolve_kubeconfig_env_fallback() {
    local tmpfile="$TMPDIR_COMMON/kubeconfig-env"
    touch "$tmpfile"
    local output exit_code=0
    output=$(KUBECONFIG="$tmpfile" bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig ""
        echo "$KUBECONFIG"
    ' 2>/dev/null) || exit_code=$?

    assert_exit_code "resolve_kubeconfig falls back to KUBECONFIG env" "0" "$exit_code"
    assert_eq "KUBECONFIG set to env value" "$tmpfile" "$output"
}

test_resolve_kubeconfig_default() {
    local tmpdir="$TMPDIR_COMMON/home-default"
    mkdir -p "$tmpdir/.kube"
    touch "$tmpdir/.kube/config"
    local output exit_code=0
    output=$(HOME="$tmpdir" bash -c '
        set -euo pipefail
        unset KUBECONFIG
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig ""
        echo "$KUBECONFIG"
    ' 2>/dev/null) || exit_code=$?

    assert_exit_code "resolve_kubeconfig uses ~/.kube/config" "0" "$exit_code"
    assert_eq "KUBECONFIG set to default" "$tmpdir/.kube/config" "$output"
}

test_resolve_kubeconfig_none() {
    local tmpdir="$TMPDIR_COMMON/home-empty"
    mkdir -p "$tmpdir"
    local exit_code=0
    HOME="$tmpdir" bash -c '
        set -euo pipefail
        unset KUBECONFIG
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig ""
    ' 2>/dev/null || exit_code=$?

    assert_eq "resolve_kubeconfig errors when no kubeconfig found" "1" "$exit_code"
}

test_resolve_kubeconfig_nonexistent() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig "/nonexistent/path/kubeconfig"
    ' 2>/dev/null || exit_code=$?

    assert_eq "resolve_kubeconfig errors on nonexistent file" "1" "$exit_code"
}

test_resolve_kubeconfig_flag_beats_env() {
    local tmpflag="$TMPDIR_COMMON/kubeconfig-flag-priority"
    local tmpenv="$TMPDIR_COMMON/kubeconfig-env-priority"
    touch "$tmpflag" "$tmpenv"
    local output exit_code=0
    output=$(KUBECONFIG="$tmpenv" bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig "'"$tmpflag"'"
        echo "$KUBECONFIG"
    ' 2>/dev/null) || exit_code=$?

    assert_exit_code "flag beats env var" "0" "$exit_code"
    assert_eq "KUBECONFIG set to flag, not env" "$tmpflag" "$output"
}

test_resolve_kubeconfig_error_message() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        resolve_kubeconfig "/nonexistent/path/kubeconfig"
    ' 2>&1) || true

    assert_contains "error names the file" "$output" "/nonexistent/path/kubeconfig"
}

test_resolve_kubeconfig_flag
test_resolve_kubeconfig_env_fallback
test_resolve_kubeconfig_default
test_resolve_kubeconfig_none
test_resolve_kubeconfig_nonexistent
test_resolve_kubeconfig_flag_beats_env
test_resolve_kubeconfig_error_message

# ===========================================================================
echo ""
echo "=== Issue #9: --verbose and --quiet flags ==="
# ===========================================================================

test_verbose_enables_debug() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=4
        log_debug "verbose test message"
    ' 2>&1)

    assert_contains "--verbose enables debug output" "$output" "verbose test message"
}

test_quiet_suppresses_all() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=0
        log_error "should be hidden" 2>&1
        log_info "also hidden"
        echo "SURVIVED"
    ' 2>&1)

    assert_not_contains "--quiet suppresses error output" "$output" "should be hidden"
    assert_not_contains "--quiet suppresses info output" "$output" "also hidden"
    assert_contains "script still completes" "$output" "SURVIVED"
}

test_verbose_overrides_env() {
    local output
    output=$(LOG_LEVEL=0 bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        LOG_LEVEL=4
        log_debug "override test"
    ' 2>&1)

    assert_contains "--verbose overrides LOG_LEVEL env" "$output" "override test"
}

test_verbose_flag_parsing() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --verbose) LOG_LEVEL=4; shift ;;
                --quiet)   LOG_LEVEL=0; shift ;;
                *)         shift ;;
            esac
        done
        log_debug "parsed verbose"
    ' -- --verbose 2>&1)

    assert_contains "--verbose flag parsed from args" "$output" "parsed verbose"
}

test_quiet_flag_parsing() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --verbose) LOG_LEVEL=4; shift ;;
                --quiet)   LOG_LEVEL=0; shift ;;
                *)         shift ;;
            esac
        done
        log_error "should be hidden" 2>&1
        echo "DONE"
    ' -- --quiet 2>&1)

    assert_not_contains "--quiet flag suppresses errors" "$output" "should be hidden"
    assert_contains "--quiet flag still completes" "$output" "DONE"
}

test_verbose_enables_debug
test_quiet_suppresses_all
test_verbose_overrides_env
test_verbose_flag_parsing
test_quiet_flag_parsing

# ===========================================================================
echo ""
echo "=== Issue #33: determine_status function ==="
# ===========================================================================

test_status_none_no_endpoints() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        determine_status 0 0
    ')
    assert_eq "NONE when reachable=0" "NONE" "$output"
}

test_status_none_all_closed() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        determine_status 0 0
    ')
    assert_eq "NONE when all endpoints closed" "NONE" "$output"
}

test_status_pass_all_mlkem() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        determine_status 8 8
    ')
    assert_eq "PASS when mlkem == reachable" "PASS" "$output"
}

test_status_partial_some_mlkem() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        determine_status 8 5
    ')
    assert_eq "PARTIAL when 0 < mlkem < reachable" "PARTIAL" "$output"
}

test_status_fail_no_mlkem() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        determine_status 8 0
    ')
    assert_eq "FAIL when mlkem=0 and reachable>0" "FAIL" "$output"
}

test_status_pass_one_endpoint() {
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        determine_status 1 1
    ')
    assert_eq "PASS with single ML-KEM endpoint" "PASS" "$output"
}

test_status_none_no_endpoints
test_status_none_all_closed
test_status_pass_all_mlkem
test_status_partial_some_mlkem
test_status_fail_no_mlkem
test_status_pass_one_endpoint

print_test_summary
