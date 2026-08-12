#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TLS_TEST_ALL="$REPO_DIR/tls-test-all.sh"
TLS_TEST_ALL_CONTENT=$(cat "$TLS_TEST_ALL")

echo "=== Issue #6: tls-test-all.sh generates MD/JUnit reports ==="

test_tls_test_all_sources_results_lib() {
    assert_contains "tls-test-all.sh sources lib/results.sh" \
        "$TLS_TEST_ALL_CONTENT" \
        'source "$SCRIPT_DIR/lib/results.sh"'
}

test_tls_test_all_calls_generate_reports() {
    assert_contains "tls-test-all.sh calls generate_reports" \
        "$TLS_TEST_ALL_CONTENT" \
        'generate_reports "$results_dir"'
}

test_generate_reports_call_after_json_write() {
    local json_line generate_line
    json_line=$(grep -n 'echo "$endpoints" > "$results_dir/report.json"' "$TLS_TEST_ALL" | cut -d: -f1)
    generate_line=$(grep -n 'generate_reports "$results_dir"' "$TLS_TEST_ALL" | cut -d: -f1)

    if [[ -n "$json_line" && -n "$generate_line" && "$generate_line" -gt "$json_line" ]]; then
        echo "  PASS: generate_reports called after writing report.json"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: generate_reports should be called after writing report.json"
        echo "    JSON write line: $json_line"
        echo "    generate_reports line: $generate_line"
        FAIL=$((FAIL + 1))
    fi
}

# Run all tests
test_tls_test_all_sources_results_lib
test_tls_test_all_calls_generate_reports
test_generate_reports_call_after_json_write

print_test_summary
