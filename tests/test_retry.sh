#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"

echo "=== Issue #20: Retry logic with exponential backoff ==="

test_retry_function_exists() {
    if declare -f retry_with_backoff > /dev/null; then
        echo "  PASS: retry_with_backoff function exists"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: retry_with_backoff function not found"
        FAIL=$((FAIL + 1))
    fi
}

test_retry_succeeds_on_first_attempt() {
    local output
    output=$(retry_with_backoff echo "success")

    assert_contains "returns output on first attempt" \
        "$output" \
        "success"
}

test_retry_succeeds_after_failures() {
    local counter_file
    counter_file=$(mktemp)
    echo "0" > "$counter_file"

    # Helper script that fails twice then succeeds
    local test_script
    test_script=$(mktemp)
    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
counter_file="$1"
count=$(cat "$counter_file")
count=$((count + 1))
echo "$count" > "$counter_file"

if [[ $count -lt 3 ]]; then
    echo "Attempt $count failed" >&2
    exit 1
fi
echo "success on attempt $count"
EOF
    chmod +x "$test_script"

    local output
    if output=$(RETRY_MAX_ATTEMPTS=5 RETRY_INITIAL_BACKOFF=1 retry_with_backoff "$test_script" "$counter_file" 2>&1); then
        echo "  PASS: retry succeeds after 2 failures"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: retry should have succeeded after 2 failures"
        FAIL=$((FAIL + 1))
    fi

    rm -f "$counter_file" "$test_script"
}

test_retry_fails_after_max_attempts() {
    # Command that always fails - suppress all output to avoid confusing test output
    if RETRY_MAX_ATTEMPTS=2 RETRY_INITIAL_BACKOFF=1 retry_with_backoff false >/dev/null 2>&1; then
        echo "  FAIL: retry should fail after max attempts"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: retry fails after max attempts"
        PASS=$((PASS + 1))
    fi
}

test_retry_exponential_backoff() {
    local start_time end_time duration
    start_time=$(date +%s)

    # Command that fails 3 times: should wait 1s + 2s + 4s = 7s minimum
    # Suppress output to avoid confusing test results
    RETRY_MAX_ATTEMPTS=4 RETRY_INITIAL_BACKOFF=1 retry_with_backoff false >/dev/null 2>&1 || true

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Should take at least 7 seconds (1 + 2 + 4) but allow some tolerance
    if [[ $duration -ge 6 ]]; then
        echo "  PASS: exponential backoff working (took ${duration}s, expected ~7s)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: exponential backoff not working (took ${duration}s, expected ~7s)"
        FAIL=$((FAIL + 1))
    fi
}

test_tls_test_all_uses_retry() {
    local tls_test_all="$REPO_DIR/tls-test-all.sh"
    local retry_count
    retry_count=$(grep -c 'retry_with_backoff' "$tls_test_all" || echo "0")

    if [[ "$retry_count" -ge 4 ]]; then
        echo "  PASS: tls-test-all.sh uses retry logic (found $retry_count calls)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: tls-test-all.sh should use retry logic (at least 4 calls)"
        echo "    Found: $retry_count calls"
        FAIL=$((FAIL + 1))
    fi
}

test_lib_common_uses_retry() {
    local lib_common="$REPO_DIR/lib/common.sh"
    local retry_count
    retry_count=$(grep -c 'retry_with_backoff oc' "$lib_common" || echo "0")

    if [[ "$retry_count" -ge 1 ]]; then
        echo "  PASS: lib/common.sh uses retry logic (found $retry_count calls)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: lib/common.sh should use retry logic"
        echo "    Found: $retry_count calls"
        FAIL=$((FAIL + 1))
    fi
}

# Run all tests
test_retry_function_exists
test_retry_succeeds_on_first_attempt
test_retry_succeeds_after_failures
test_retry_fails_after_max_attempts
test_retry_exponential_backoff
test_tls_test_all_uses_retry
test_lib_common_uses_retry

print_test_summary
