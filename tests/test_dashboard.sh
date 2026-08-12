#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== Dashboard Integration Tests ==="

test_dashboard_data_exists() {
    local scan_results="$REPO_DIR/docs/_data/scan-results.json"

    if [[ -f "$scan_results" ]]; then
        echo "  PASS: scan-results.json exists"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scan-results.json not found at $scan_results"
        FAIL=$((FAIL + 1))
    fi
}

test_dashboard_data_valid_json() {
    local scan_results="$REPO_DIR/docs/_data/scan-results.json"

    if [[ ! -f "$scan_results" ]]; then
        echo "  SKIP: scan-results.json does not exist"
        return
    fi

    if jq empty "$scan_results" 2>/dev/null; then
        echo "  PASS: scan-results.json is valid JSON"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scan-results.json is not valid JSON"
        FAIL=$((FAIL + 1))
    fi
}

test_dashboard_data_schema() {
    local scan_results="$REPO_DIR/docs/_data/scan-results.json"

    if [[ ! -f "$scan_results" ]]; then
        echo "  SKIP: scan-results.json does not exist"
        return
    fi

    local has_required
    has_required=$(jq 'has("scan_date") and has("summary") and has("operators")' "$scan_results" 2>/dev/null || echo "false")

    if [[ "$has_required" == "true" ]]; then
        echo "  PASS: scan-results.json has required top-level fields"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scan-results.json missing required fields (scan_date, summary, operators)"
        FAIL=$((FAIL + 1))
    fi

    local has_summary_fields
    has_summary_fields=$(jq '.summary | has("total_operators") and has("pass") and has("partial") and has("none") and has("error") and has("mlkem_percent")' "$scan_results" 2>/dev/null || echo "false")

    if [[ "$has_summary_fields" == "true" ]]; then
        echo "  PASS: summary has all required fields"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: summary missing required fields"
        FAIL=$((FAIL + 1))
    fi
}

test_export_js_exists() {
    local export_js="$REPO_DIR/docs/assets/js/export.js"

    if [[ -f "$export_js" ]]; then
        echo "  PASS: export.js exists"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: export.js not found at $export_js"
        FAIL=$((FAIL + 1))
    fi
}

test_export_js_has_required_functions() {
    local export_js="$REPO_DIR/docs/assets/js/export.js"

    if [[ ! -f "$export_js" ]]; then
        echo "  SKIP: export.js does not exist"
        return
    fi

    local required_functions=(
        "validateScanData"
        "exportOperatorsJSON"
        "exportOperatorsCSV"
        "exportOperatorJSON"
        "exportOperatorCSV"
        "csvEscape"
        "boolToYesNo"
        "downloadJSON"
        "downloadCSV"
        "downloadBlob"
    )

    local all_found=true
    for func in "${required_functions[@]}"; do
        if ! grep -q "function $func" "$export_js"; then
            echo "  FAIL: export.js missing required function: $func"
            FAIL=$((FAIL + 1))
            all_found=false
        fi
    done

    if [[ "$all_found" == "true" ]]; then
        echo "  PASS: export.js has all required functions"
        PASS=$((PASS + 1))
    fi
}

test_dashboard_includes_export_js() {
    local default_layout="$REPO_DIR/docs/_layouts/default.html"

    if grep -q "export.js" "$default_layout"; then
        echo "  PASS: default.html includes export.js script"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: default.html does not include export.js"
        FAIL=$((FAIL + 1))
    fi
}

test_dashboard_has_export_buttons() {
    local index_md="$REPO_DIR/docs/index.md"

    local has_csv=false has_json=false

    if grep -q "exportOperatorsCSV" "$index_md"; then
        has_csv=true
    fi

    if grep -q "exportOperatorsJSON" "$index_md"; then
        has_json=true
    fi

    if [[ "$has_csv" == "true" && "$has_json" == "true" ]]; then
        echo "  PASS: index.md has both CSV and JSON export buttons"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: index.md missing export buttons (CSV=$has_csv, JSON=$has_json)"
        FAIL=$((FAIL + 1))
    fi
}

test_operator_layout_has_export_buttons() {
    local operator_layout="$REPO_DIR/docs/_layouts/operator.html"

    local has_csv=false has_json=false

    if grep -q "exportOperatorCSV" "$operator_layout"; then
        has_csv=true
    fi

    if grep -q "exportOperatorJSON" "$operator_layout"; then
        has_json=true
    fi

    if [[ "$has_csv" == "true" && "$has_json" == "true" ]]; then
        echo "  PASS: operator.html has both CSV and JSON export buttons"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: operator.html missing export buttons (CSV=$has_csv, JSON=$has_json)"
        FAIL=$((FAIL + 1))
    fi
}

# Run all tests
test_dashboard_data_exists
test_dashboard_data_valid_json
test_dashboard_data_schema
test_export_js_exists
test_export_js_has_required_functions
test_dashboard_includes_export_js
test_dashboard_has_export_buttons
test_operator_layout_has_export_buttons

print_test_summary
