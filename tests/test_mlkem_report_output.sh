#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TLS_MLKEM_REPORT="$REPO_DIR/tls-mlkem-report.sh"
TLS_MLKEM_REPORT_CONTENT=$(cat "$TLS_MLKEM_REPORT")

echo "=== Issue #21: tls-mlkem-report.sh file output ==="

test_tls_mlkem_report_sources_results_lib() {
    assert_contains "tls-mlkem-report.sh sources lib/results.sh" \
        "$TLS_MLKEM_REPORT_CONTENT" \
        'source "$SCRIPT_DIR/lib/results.sh"'
}

test_tls_mlkem_report_has_output_dir_flag() {
    assert_contains "tls-mlkem-report.sh has --output-dir flag" \
        "$TLS_MLKEM_REPORT_CONTENT" \
        '--output-dir'
}

test_tls_mlkem_report_has_output_dir_variable() {
    assert_contains "tls-mlkem-report.sh defines OUTPUT_DIR variable" \
        "$TLS_MLKEM_REPORT_CONTENT" \
        'OUTPUT_DIR='
}

test_tls_mlkem_report_calls_generate_reports() {
    local generate_count
    generate_count=$(grep -c 'generate_reports' <<< "$TLS_MLKEM_REPORT_CONTENT" || echo "0")

    if [[ "$generate_count" -ge 1 ]]; then
        echo "  PASS: tls-mlkem-report.sh calls generate_reports (found $generate_count calls)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: tls-mlkem-report.sh should call generate_reports"
        echo "    Found: $generate_count calls"
        FAIL=$((FAIL + 1))
    fi
}

test_tls_mlkem_report_has_save_helper() {
    assert_contains "tls-mlkem-report.sh has save_and_generate_reports helper" \
        "$TLS_MLKEM_REPORT_CONTENT" \
        'save_and_generate_reports()'
}

test_tls_mlkem_report_saves_json() {
    local json_write_count
    json_write_count=$(grep -c '> "$results_dir/report.json"' <<< "$TLS_MLKEM_REPORT_CONTENT" || echo "0")

    if [[ "$json_write_count" -ge 1 ]]; then
        echo "  PASS: tls-mlkem-report.sh saves JSON reports (found $json_write_count calls)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: tls-mlkem-report.sh should save JSON"
        echo "    Found: $json_write_count writes"
        FAIL=$((FAIL + 1))
    fi
}

# Run all tests
test_tls_mlkem_report_sources_results_lib
test_tls_mlkem_report_has_output_dir_flag
test_tls_mlkem_report_has_output_dir_variable
test_tls_mlkem_report_calls_generate_reports
test_tls_mlkem_report_has_save_helper
test_tls_mlkem_report_saves_json

print_test_summary
