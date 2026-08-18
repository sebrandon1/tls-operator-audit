#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/results.sh"

TLS_TEST_ALL="$REPO_DIR/tls-test-all.sh"
MLKEM_REPORT="$REPO_DIR/tls-mlkem-report.sh"

echo "=== --output-format consolidated summary ==="

test_scripts_document_flag() {
    assert_contains "tls-test-all.sh usage documents --output-format" \
        "$(cat "$TLS_TEST_ALL")" \
        "--output-format"

    assert_contains "tls-mlkem-report.sh usage documents --output-format" \
        "$(cat "$MLKEM_REPORT")" \
        "--output-format"
}

test_help_mentions_formats() {
    local output
    output=$(bash "$TLS_TEST_ALL" --help)
    assert_contains "tls-test-all help lists json, csv, or markdown" "$output" "json, csv, or markdown"

    output=$(bash "$MLKEM_REPORT" --help)
    assert_contains "tls-mlkem-report help lists json, csv, or markdown" "$output" "json, csv, or markdown"
}

test_invalid_format_fails() {
    local output exit_code=0
    output=$(bash "$TLS_TEST_ALL" --output-format xml 2>&1) || exit_code=$?
    assert_exit_code "tls-test-all.sh rejects unknown format" "1" "$exit_code"
    assert_contains "error names the invalid format" "$output" "xml"

    exit_code=0
    output=$(bash "$MLKEM_REPORT" --output-format yaml 2>&1) || exit_code=$?
    assert_exit_code "tls-mlkem-report.sh rejects unknown format" "1" "$exit_code"
    assert_contains "mlkem report error names the invalid format" "$output" "yaml"
}

test_validate_output_format_accepts_known() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        validate_output_format json
        validate_output_format csv
        validate_output_format markdown
    ' || exit_code=$?
    assert_exit_code "validate_output_format accepts json, csv, markdown" "0" "$exit_code"
}

setup_summary_arrays() {
    SUMMARY_NAMES=("rhacs-operator" "cert-manager-operator" "skupper-operator")
    SUMMARY_VERSIONS=("1.2.3" "1.16.1" "N/A")
    SUMMARY_TOTAL=("10" "4" "-")
    SUMMARY_MLKEM=("8" "4" "-")
    SUMMARY_STATUS=("PARTIAL" "PASS" "N/A")
}

test_summary_json() {
    setup_summary_arrays
    local output
    output=$(emit_mlkem_summary json)

    echo "$output" | jq -e '.operators | length == 3' >/dev/null
    assert_eq "JSON is valid with 3 operators" "0" "$?"

    local name status total
    name=$(echo "$output" | jq -r '.operators[0].name')
    status=$(echo "$output" | jq -r '.operators[0].status')
    total=$(echo "$output" | jq -r '.operators[0].total')
    assert_eq "JSON first operator name" "rhacs-operator" "$name"
    assert_eq "JSON first operator status" "PARTIAL" "$status"
    assert_eq "JSON numeric total" "10" "$total"

    local na_total
    na_total=$(echo "$output" | jq -r '.operators[2].total')
    assert_eq "JSON keeps non-numeric total as string" "-" "$na_total"
}

test_summary_csv() {
    setup_summary_arrays
    local output
    output=$(emit_mlkem_summary csv)
    local header
    header=$(echo "$output" | head -1)
    assert_contains "CSV header has operator" "$header" "operator"
    assert_contains "CSV header has status" "$header" "status"

    local row
    row=$(echo "$output" | sed -n '2p')
    assert_contains "CSV includes rhacs-operator" "$row" "rhacs-operator"
    assert_contains "CSV includes PARTIAL" "$row" "PARTIAL"
}

test_summary_markdown() {
    setup_summary_arrays
    local output
    output=$(emit_mlkem_summary markdown)
    assert_contains "markdown has header row" "$output" "| operator | version | total | mlkem | status |"
    assert_contains "markdown has separator" "$output" "| --- | --- | --- | --- | --- |"
    assert_contains "markdown includes PASS row" "$output" "cert-manager-operator"
}

test_empty_summary_json() {
    SUMMARY_NAMES=()
    SUMMARY_VERSIONS=()
    SUMMARY_TOTAL=()
    SUMMARY_MLKEM=()
    SUMMARY_STATUS=()
    local output
    output=$(emit_mlkem_summary json)
    echo "$output" | jq -e '.operators == []' >/dev/null
    assert_eq "empty summary emits empty operators array" "0" "$?"
}

test_namespace_rows_csv() {
    local rows='[{"namespace":"cert-manager","total":3,"compliant":3,"mlkem":2,"pqc_ready":2,"closed":0}]'
    local output
    output=$(emit_consolidated_output csv namespaces \
        "namespace total compliant mlkem pqc_ready closed" \
        "namespace total compliant mlkem pqc_ready closed" \
        "$rows")
    assert_contains "namespace CSV has header" "$output" "namespace"
    assert_contains "namespace CSV has cert-manager" "$output" "cert-manager"
}

test_scripts_document_flag
test_help_mentions_formats
test_invalid_format_fails
test_validate_output_format_accepts_known
test_summary_json
test_summary_csv
test_summary_markdown
test_empty_summary_json
test_namespace_rows_csv

print_test_summary
