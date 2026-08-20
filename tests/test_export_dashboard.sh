#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

FIXTURES="$SCRIPT_DIR/fixtures/export"
EXPORT="$REPO_DIR/export-dashboard.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== export-dashboard.sh ==="

setup_workdir() {
    local name="$1"
    local dir="$TMPDIR_TEST/$name"
    mkdir -p "$dir/lib" "$dir/docs/_data" "$dir/docs/badges" "$dir/docs/operators"
    cp "$REPO_DIR/lib/common.sh" "$dir/lib/"
    cp "$EXPORT" "$dir/"
    cp "$FIXTURES/operators.yaml" "$dir/operators.yaml"
    printf '%s\n' "$dir"
}

run_export() {
    local dir="$1"
    shift
    bash "$dir/export-dashboard.sh" \
        --results-dir "$FIXTURES/results" \
        --cluster test-cluster \
        --ocp-version 4.19.0 \
        --tco-version v1.1.9 \
        "$@"
}

jq_field() {
    jq -r "$1" "$2"
}

test_help_and_unknown_option() {
    local output exit_code

    output=$(bash "$EXPORT" --help)
    assert_contains "help documents --results-dir" "$output" "--results-dir"
    assert_contains "help documents --scan-mode" "$output" "--scan-mode"

    exit_code=0
    bash "$EXPORT" --not-a-flag >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "rejects unknown option" "1" "$exit_code"
}

test_missing_operators_yaml() {
    local dir exit_code
    dir=$(setup_workdir missing-yaml)
    rm -f "$dir/operators.yaml"

    exit_code=0
    bash "$dir/export-dashboard.sh" \
        --results-dir "$FIXTURES/results" \
        --cluster test-cluster \
        --ocp-version 4.19.0 \
        --quiet >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "exits when operators.yaml is missing" "1" "$exit_code"
}

test_writes_valid_scan_results() {
    local dir results
    dir=$(setup_workdir scan-results)
    run_export "$dir" --quiet >/dev/null

    results="$dir/docs/_data/scan-results.json"
    if jq empty "$results" 2>/dev/null; then
        echo "  PASS: scan-results.json is valid JSON"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scan-results.json is not valid JSON"
        FAIL=$((FAIL + 1))
    fi

    assert_eq "scan-results has required top-level fields" "true" \
        "$(jq 'has("scan_date") and has("summary") and has("operators")' "$results")"
    assert_eq "cluster metadata is recorded" "test-cluster" \
        "$(jq_field '.cluster' "$results")"
    assert_eq "OCP version metadata is recorded" "4.19.0" \
        "$(jq_field '.ocp_version' "$results")"
    assert_eq "TCO version metadata is recorded" "v1.1.9" \
        "$(jq_field '.tco_version' "$results")"
}

test_summary_and_operator_status() {
    local dir results
    dir=$(setup_workdir statuses)
    run_export "$dir" --quiet >/dev/null
    results="$dir/docs/_data/scan-results.json"

    assert_eq "total operators" "5" "$(jq_field '.summary.total_operators' "$results")"
    assert_eq "PASS count" "1" "$(jq_field '.summary.pass' "$results")"
    assert_eq "PARTIAL count" "1" "$(jq_field '.summary.partial' "$results")"
    assert_eq "NONE count" "1" "$(jq_field '.summary.none' "$results")"
    assert_eq "ERROR count includes FAIL and missing reports" "2" \
        "$(jq_field '.summary.error' "$results")"
    assert_eq "reachable endpoint total" "6" "$(jq_field '.summary.total_endpoints' "$results")"
    assert_eq "ML-KEM endpoint total" "3" "$(jq_field '.summary.mlkem_endpoints' "$results")"
    assert_eq "overall ML-KEM percent" "50.0" "$(jq_field '.summary.mlkem_percent' "$results")"

    assert_eq "pass-op status" "PASS" \
        "$(jq -r '.operators[] | select(.name=="pass-op") | .status' "$results")"
    assert_eq "partial-op status" "PARTIAL" \
        "$(jq -r '.operators[] | select(.name=="partial-op") | .status' "$results")"
    assert_eq "none-op status" "NONE" \
        "$(jq -r '.operators[] | select(.name=="none-op") | .status' "$results")"
    assert_eq "fail-op status" "FAIL" \
        "$(jq -r '.operators[] | select(.name=="fail-op") | .status' "$results")"
    assert_eq "missing-op status" "ERROR" \
        "$(jq -r '.operators[] | select(.name=="missing-op") | .status' "$results")"
}

test_uses_latest_report_and_metadata() {
    local dir results
    dir=$(setup_workdir latest-report)
    run_export "$dir" --quiet >/dev/null
    results="$dir/docs/_data/scan-results.json"

    assert_eq "uses latest pass-op version not older metadata" "1.2.0" \
        "$(jq -r '.operators[] | select(.name=="pass-op") | .version' "$results")"
    assert_eq "pass-op reachable endpoints from latest report" "2" \
        "$(jq -r '.operators[] | select(.name=="pass-op") | .reachable_endpoints' "$results")"
    assert_eq "pass-op closed endpoints" "1" \
        "$(jq -r '.operators[] | select(.name=="pass-op") | .closed_endpoints' "$results")"
    assert_eq "pass-op total endpoints" "3" \
        "$(jq -r '.operators[] | select(.name=="pass-op") | .total_endpoints' "$results")"
    assert_eq "pass-op ML-KEM endpoints" "2" \
        "$(jq -r '.operators[] | select(.name=="pass-op") | .mlkem_endpoints' "$results")"
    assert_eq "none-op version empty without metadata.json" "" \
        "$(jq -r '.operators[] | select(.name=="none-op") | .version' "$results")"
}

test_catalog_null_is_preinstalled() {
    local dir results
    dir=$(setup_workdir catalog-null)
    run_export "$dir" --quiet >/dev/null
    results="$dir/docs/_data/scan-results.json"

    assert_eq "catalog:null becomes pre-installed" "pre-installed" \
        "$(jq -r '.operators[] | select(.name=="missing-op") | .catalog' "$results")"
    assert_eq "jira is copied from operators.yaml" "TEST-5" \
        "$(jq -r '.operators[] | select(.name=="missing-op") | .jira' "$results")"
    assert_eq "project is copied from operators.yaml" "Missing Operator" \
        "$(jq -r '.operators[] | select(.name=="missing-op") | .project' "$results")"
}

test_coalesces_days_until_expiry() {
    local dir results_dir results
    dir=$(setup_workdir coalesce-expiry)
    results_dir="$dir/results/cli-op/20260115-120000"
    mkdir -p "$results_dir"
    cat > "$dir/operators.yaml" <<'EOF'
operators:
  - name: cli-op
    jira: TEST-8
    project: CLI Operator
    catalog: redhat-operators
    channel: stable
EOF
    cat > "$results_dir/report.json" <<'EOF'
[
  {
    "spec": {
      "host": "cli.example",
      "port": 443,
      "sourceKind": "Service",
      "sourceName": "cli",
      "sourceNamespace": "cli-op"
    },
    "status": {
      "complianceStatus": "Compliant",
      "mlkemSupported": true,
      "daysUntilExpiry": 12
    }
  },
  {
    "spec": {
      "host": "nested.example",
      "port": 443,
      "sourceKind": "Service",
      "sourceName": "nested",
      "sourceNamespace": "cli-op"
    },
    "status": {
      "complianceStatus": "Compliant",
      "mlkemSupported": true,
      "daysUntilExpiry": 99,
      "certificateInfo": {
        "daysUntilExpiry": 45
      }
    }
  }
]
EOF

    bash "$dir/export-dashboard.sh" \
        --results-dir "$dir/results" \
        --cluster test-cluster \
        --ocp-version 4.19.0 \
        --quiet >/dev/null
    results="$dir/docs/_data/scan-results.json"

    assert_eq "top-level daysUntilExpiry used when nested field is missing" "12" \
        "$(jq -r '.operators[] | select(.name=="cli-op") | .endpoints[] | select(.host=="cli.example") | .certificate_info.days_until_expiry' "$results")"
    assert_eq "nested certificateInfo.daysUntilExpiry wins when both are set" "45" \
        "$(jq -r '.operators[] | select(.name=="cli-op") | .endpoints[] | select(.host=="nested.example") | .certificate_info.days_until_expiry' "$results")"
}

test_endpoint_schema_mapping() {
    local dir results endpoint
    dir=$(setup_workdir endpoints)
    run_export "$dir" --quiet >/dev/null
    results="$dir/docs/_data/scan-results.json"

    endpoint=$(jq '.operators[] | select(.name=="pass-op") | .endpoints[] | select(.host=="webhook.pass.example")' "$results")
    assert_eq "endpoint port" "443" "$(echo "$endpoint" | jq -r '.port')"
    assert_eq "endpoint source kind" "Service" "$(echo "$endpoint" | jq -r '.source_kind')"
    assert_eq "endpoint source name" "pass-webhook" "$(echo "$endpoint" | jq -r '.source_name')"
    assert_eq "mlkem_supported mapped" "true" "$(echo "$endpoint" | jq -r '.mlkem_supported')"
    assert_eq "days_until_expiry mapped" "90" "$(echo "$endpoint" | jq -r '.certificate_info.days_until_expiry')"
    assert_eq "hostname_match mapped" "true" "$(echo "$endpoint" | jq -r '.certificate_info.hostname_match')"
    assert_eq "workload pods preserved" "pass-webhook-abc" \
        "$(echo "$endpoint" | jq -r '.workload.pods[0].name')"

    assert_eq "Timeout counts as closed" "2" \
        "$(jq -r '.operators[] | select(.name=="none-op") | .closed_endpoints' "$results")"
}

test_history_append_and_dedup() {
    local dir history
    dir=$(setup_workdir history)
    run_export "$dir" --quiet >/dev/null
    run_export "$dir" --quiet >/dev/null

    history="$dir/docs/_data/scan-history.json"
    assert_eq "second run with same scan_date+cluster does not duplicate" "1" \
        "$(jq 'length' "$history")"

    run_export "$dir" --cluster other-cluster --quiet >/dev/null
    assert_eq "different cluster appends a second history entry" "2" \
        "$(jq 'length' "$history")"

    assert_eq "history operators omit full endpoint arrays" "true" \
        "$(jq '[.[0].operators[] | has("endpoints")] | all | not' "$history")"
    assert_eq "history keeps operator status" "PASS" \
        "$(jq -r '.[0].operators[] | select(.name=="pass-op") | .status' "$history")"
}

test_scan_settings_in_history() {
    local dir history
    dir=$(setup_workdir scan-settings)
    run_export "$dir" --scan-mode operators-yaml --scan-operator pass-op --scan-keep-reports --quiet >/dev/null

    history="$dir/docs/_data/scan-history.json"
    assert_eq "scan_settings.mode recorded" "operators-yaml" \
        "$(jq -r '.[0].scan_settings.mode' "$history")"
    assert_eq "scan_settings.operator recorded" "pass-op" \
        "$(jq -r '.[0].scan_settings.operator' "$history")"
    assert_eq "scan_settings.keep_reports recorded" "true" \
        "$(jq -r '.[0].scan_settings.keep_reports' "$history")"

    dir=$(setup_workdir no-scan-settings)
    run_export "$dir" --quiet >/dev/null
    assert_eq "scan_settings omitted when flags not set" "false" \
        "$(jq '.[0] | has("scan_settings")' "$dir/docs/_data/scan-history.json")"
}

test_badge_generation() {
    local dir color message

    dir=$(setup_workdir badge-yellow)
    run_export "$dir" --quiet >/dev/null
    color=$(jq -r '.color' "$dir/docs/badges/mlkem.json")
    message=$(jq -r '.message' "$dir/docs/badges/mlkem.json")
    assert_eq "50% ML-KEM badge is yellow" "yellow" "$color"
    assert_eq "badge message is percent" "50.0%" "$message"
    assert_eq "badge schemaVersion" "1" "$(jq -r '.schemaVersion' "$dir/docs/badges/mlkem.json")"
    assert_eq "badge label" "ML-KEM Compliance" "$(jq -r '.label' "$dir/docs/badges/mlkem.json")"

    dir=$(setup_workdir badge-green)
    cat > "$dir/operators.yaml" <<'EOF'
operators:
  - name: pass-op
    jira: TEST-1
    project: Pass Operator
    catalog: redhat-operators
    channel: stable
EOF
    run_export "$dir" --quiet >/dev/null
    assert_eq "100% ML-KEM badge is green" "green" \
        "$(jq -r '.color' "$dir/docs/badges/mlkem.json")"

    dir=$(setup_workdir badge-red)
    cat > "$dir/operators.yaml" <<'EOF'
operators:
  - name: fail-op
    jira: TEST-4
    project: Fail Operator
    catalog: certified-operators
    channel: stable
EOF
    run_export "$dir" --quiet >/dev/null
    assert_eq "0% ML-KEM badge is red" "red" \
        "$(jq -r '.color' "$dir/docs/badges/mlkem.json")"
}

test_operator_stubs() {
    local dir
    dir=$(setup_workdir stubs)
    mkdir -p "$dir/docs/operators"
    cat > "$dir/docs/operators/pass-op.md" <<'EOF'
---
layout: operator
operator: pass-op
title: "existing stub"
---
keep-me
EOF

    run_export "$dir" --quiet >/dev/null

    assert_contains "existing stub is not overwritten" \
        "$(cat "$dir/docs/operators/pass-op.md")" "keep-me"
    assert_contains "missing-op stub is created" \
        "$(cat "$dir/docs/operators/missing-op.md")" "operator: missing-op"
    assert_eq "stub count matches operators.yaml" "5" \
        "$(find "$dir/docs/operators" -name '*.md' | wc -l | tr -d ' ')"

    run_export "$dir" --quiet >/dev/null
    assert_eq "second run does not add extra stubs" "5" \
        "$(find "$dir/docs/operators" -name '*.md' | wc -l | tr -d ' ')"
}

test_help_and_unknown_option
test_missing_operators_yaml
test_writes_valid_scan_results
test_summary_and_operator_status
test_uses_latest_report_and_metadata
test_catalog_null_is_preinstalled
test_coalesces_days_until_expiry
test_endpoint_schema_mapping
test_history_append_and_dedup
test_scan_settings_in_history
test_badge_generation
test_operator_stubs

print_test_summary
