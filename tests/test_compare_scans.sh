#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/compare.sh"

FIXTURES="$REPO_DIR/tests/fixtures/compare"
COMPARE="$REPO_DIR/compare-scans.sh"
BEFORE_TS="20260101-120000"
AFTER_TS="20260110-120000"

echo "=== compare-scans.sh ==="

test_help_and_usage() {
    local output
    output=$(bash "$COMPARE" --help)
    assert_contains "help documents timestamp input" "$output" "YYYYMMDD-HHMMSS"
    assert_contains "help documents --output-format" "$output" "--output-format"
}

test_invalid_format() {
    local exit_code=0
    bash "$COMPARE" "$BEFORE_TS" "$AFTER_TS" --results-dir "$FIXTURES" --output-format xml >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "rejects unknown output format" "1" "$exit_code"
}

test_missing_args() {
    local exit_code=0
    bash "$COMPARE" --results-dir "$FIXTURES" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "requires before and after" "1" "$exit_code"
}

test_operator_from_timestamp_path() {
    local name
    name=$(operator_from_report_path "$FIXTURES/op-a/${BEFORE_TS}/report.json")
    assert_eq "timestamped path yields operator name" "op-a" "$name"
}

test_list_by_timestamp() {
    local listing
    listing=$(list_report_files "$BEFORE_TS" "$FIXTURES")
    assert_contains "timestamp lists op-a" "$listing" "op-a"
    assert_contains "timestamp lists op-b" "$listing" "op-b"
    assert_not_contains "before timestamp does not list op-c" "$listing" "op-c"
}

test_normalize_array_and_list() {
    local array_count list_count
    array_count=$(normalize_report < "$FIXTURES/op-a/${BEFORE_TS}/report.json" | jq 'length')
    list_count=$(normalize_report < "$FIXTURES/op-b/${BEFORE_TS}/report.json" | jq 'length')
    assert_eq "array report has 3 endpoints" "3" "$array_count"
    assert_eq "List-wrapped report has 1 endpoint" "1" "$list_count"
}

test_compare_classifies_changes() {
    local before_json after_json diff
    before_json=$(load_run "$BEFORE_TS" "$FIXTURES")
    after_json=$(load_run "$AFTER_TS" "$FIXTURES")
    diff=$(compare_runs "$before_json" "$after_json")

    assert_eq "gained count" "1" "$(echo "$diff" | jq '.summary.gained')"
    assert_eq "lost count" "1" "$(echo "$diff" | jq '.summary.lost')"
    assert_eq "added count" "2" "$(echo "$diff" | jq '.summary.added')"
    assert_eq "removed count" "1" "$(echo "$diff" | jq '.summary.removed')"
    assert_eq "unchanged count" "1" "$(echo "$diff" | jq '.summary.unchanged')"

    local gained_ep lost_ep
    gained_ep=$(echo "$diff" | jq -r '.changes[] | select(.change == "gained") | .endpoint')
    lost_ep=$(echo "$diff" | jq -r '.changes[] | select(.change == "lost") | .endpoint')
    assert_eq "webhook gained ML-KEM" "op-a/webhook.example:443" "$gained_ep"
    assert_eq "metrics lost ML-KEM" "op-a/metrics.example:8443" "$lost_ep"

    echo "$diff" | jq -e '.changes[] | select(.change == "removed" and .endpoint == "op-a/gone.example:443")' >/dev/null
    assert_eq "gone.example is removed" "0" "$?"

    echo "$diff" | jq -e '.changes[] | select(.change == "added" and .endpoint == "op-a/new.example:443")' >/dev/null
    assert_eq "new.example is added" "0" "$?"

    echo "$diff" | jq -e '.changes[] | select(.change == "added" and .endpoint == "op-c/only-after.example:9443")' >/dev/null
    assert_eq "op-c endpoint is added" "0" "$?"

    echo "$diff" | jq -e '.changes[] | select(.change == "unchanged" and .endpoint == "op-b/stable.example:443")' >/dev/null
    assert_eq "List-wrapped endpoint is unchanged" "0" "$?"
}

test_cli_exits_one_on_regression() {
    local exit_code=0
    bash "$COMPARE" "$BEFORE_TS" "$AFTER_TS" --results-dir "$FIXTURES" --output-format json >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "CLI exits 1 when ML-KEM is lost" "1" "$exit_code"
}

test_cli_json_omits_unchanged() {
    local output exit_code=0
    output=$(bash "$COMPARE" "$BEFORE_TS" "$AFTER_TS" --results-dir "$FIXTURES" --output-format json 2>/dev/null) || exit_code=$?
    echo "$output" | jq -e '[.changes[].change] | index("unchanged") == null' >/dev/null
    assert_eq "JSON output omits unchanged rows" "0" "$?"
    echo "$output" | jq -e '.summary.lost == 1' >/dev/null
    assert_eq "JSON summary still counts lost" "0" "$?"
}

test_cli_csv() {
    local output exit_code=0
    output=$(bash "$COMPARE" "$BEFORE_TS" "$AFTER_TS" --results-dir "$FIXTURES" --output-format csv 2>/dev/null) || exit_code=$?
    assert_contains "CSV has header" "$output" "operator"
    assert_contains "CSV has lost row" "$output" "lost"
    assert_contains "CSV has gained row" "$output" "gained"
}

test_single_report_files() {
    local before_json after_json diff
    before_json=$(load_run "$FIXTURES/op-a/${BEFORE_TS}/report.json" "$FIXTURES")
    after_json=$(load_run "$FIXTURES/op-a/${AFTER_TS}/report.json" "$FIXTURES")
    diff=$(compare_runs "$before_json" "$after_json")
    assert_eq "single-file compare still detects lost" "1" "$(echo "$diff" | jq '.summary.lost')"
}

test_no_regression_exit_zero() {
    local exit_code=0
    bash "$COMPARE" \
        "$FIXTURES/op-b/${BEFORE_TS}/report.json" \
        "$FIXTURES/op-b/${AFTER_TS}/report.json" \
        --output-format json >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "unchanged run exits 0" "0" "$exit_code"
}

test_help_and_usage
test_invalid_format
test_missing_args
test_operator_from_timestamp_path
test_list_by_timestamp
test_normalize_array_and_list
test_compare_classifies_changes
test_cli_exits_one_on_regression
test_cli_json_omits_unchanged
test_cli_csv
test_single_report_files
test_no_regression_exit_zero

print_test_summary
