#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

create_sample_report() {
    cat > "$TMPDIR_TEST/report.json" <<'ENDJSON'
{
  "items": [
    {
      "spec": {
        "host": "webhook.cert-manager",
        "port": 443,
        "sourceNamespace": "cert-manager"
      },
      "status": {
        "complianceStatus": "Compliant",
        "tlsVersions": {"tls12": true, "tls13": true},
        "overallCipherGrade": "A",
        "mlkemSupported": true,
        "pqcReadiness": "PQCReady"
      }
    },
    {
      "spec": {
        "host": "metrics.rhoai",
        "port": 8443,
        "sourceNamespace": "redhat-ods-operator"
      },
      "status": {
        "complianceStatus": "PlaintextHTTP",
        "tlsVersions": {"tls12": false, "tls13": false},
        "overallCipherGrade": "F",
        "mlkemSupported": false,
        "pqcReadiness": "NotReady"
      }
    }
  ]
}
ENDJSON
}

# ===========================================================================
echo "=== Bug #3: Markdown report includes ML-KEM/PQC columns ==="
# ===========================================================================

test_markdown_has_mlkem_column() {
    create_sample_report

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        generate_markdown "'"$TMPDIR_TEST"'/report.json" "'"$TMPDIR_TEST"'/report.md"
    ' 2>/dev/null

    local content
    content=$(cat "$TMPDIR_TEST/report.md")

    assert_contains "markdown header has ML-KEM column" "$content" "ML-KEM"
    assert_contains "markdown header has PQC Readiness column" "$content" "PQC Readiness"
    assert_contains "mlkemSupported=true appears" "$content" "true"
    assert_contains "PQCReady value appears" "$content" "PQCReady"
    assert_contains "mlkemSupported=false appears" "$content" "false"
    assert_contains "NotReady value appears" "$content" "NotReady"
}

test_markdown_has_mlkem_column

# ===========================================================================
echo ""
echo "=== Bug #4: JUnit report flags ML-KEM=false as failure ==="
# ===========================================================================

test_junit_has_mlkem_suite() {
    create_sample_report

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        generate_junit "'"$TMPDIR_TEST"'/report.json" "'"$TMPDIR_TEST"'/report.xml"
    ' 2>/dev/null

    local content
    content=$(cat "$TMPDIR_TEST/report.xml")

    assert_contains "JUnit has TLS Compliance suite" "$content" 'testsuite name="TLS Compliance"'
    assert_contains "JUnit has ML-KEM PQC Compliance suite" "$content" 'testsuite name="ML-KEM PQC Compliance"'
}

test_junit_mlkem_failure_count() {
    create_sample_report

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        generate_junit "'"$TMPDIR_TEST"'/report.json" "'"$TMPDIR_TEST"'/report.xml"
    ' 2>/dev/null

    local content
    content=$(cat "$TMPDIR_TEST/report.xml")

    assert_contains "ML-KEM suite has failures" "$content" 'ML-KEM PQC Compliance" tests="2" failures="1"'
}

test_junit_mlkem_failure_message() {
    create_sample_report

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        generate_junit "'"$TMPDIR_TEST"'/report.json" "'"$TMPDIR_TEST"'/report.xml"
    ' 2>/dev/null

    local content
    content=$(cat "$TMPDIR_TEST/report.xml")

    assert_contains "ML-KEM failure mentions endpoint" "$content" "metrics.rhoai"
    assert_contains "ML-KEM failure message" "$content" "ML-KEM not supported"
}

test_junit_tls_failure_preserved() {
    create_sample_report

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        generate_junit "'"$TMPDIR_TEST"'/report.json" "'"$TMPDIR_TEST"'/report.xml"
    ' 2>/dev/null

    local content
    content=$(cat "$TMPDIR_TEST/report.xml")

    assert_contains "TLS suite flags PlaintextHTTP" "$content" 'failure message="PlaintextHTTP"'
}

test_junit_properties() {
    create_sample_report

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        generate_junit "'"$TMPDIR_TEST"'/report.json" "'"$TMPDIR_TEST"'/report.xml"
    ' 2>/dev/null

    local content
    content=$(cat "$TMPDIR_TEST/report.xml")

    assert_contains "mlkemSupported property present" "$content" 'property name="mlkemSupported"'
    assert_contains "pqcReadiness property present" "$content" 'property name="pqcReadiness"'
}

test_junit_has_mlkem_suite
test_junit_mlkem_failure_count
test_junit_mlkem_failure_message
test_junit_tls_failure_preserved
test_junit_properties

test_prune_results_keeps_latest() {
    local base_dir="$TMPDIR_TEST/prune-test-1"
    mkdir -p "$base_dir/my-operator"

    mkdir -p "$base_dir/my-operator/20260101-100000"
    mkdir -p "$base_dir/my-operator/20260102-100000"
    mkdir -p "$base_dir/my-operator/20260103-100000"
    mkdir -p "$base_dir/my-operator/20260104-100000"
    mkdir -p "$base_dir/my-operator/20260105-100000"

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        prune_results "'"$base_dir"'" "my-operator" 3 false
    ' 2>/dev/null

    local remaining
    remaining=$(find "$base_dir/my-operator" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    assert_eq "prune keeps 3 of 5" "3" "$remaining"

    local kept
    kept=$(find "$base_dir/my-operator" -mindepth 1 -maxdepth 1 -type d | sort)
    assert_contains "oldest dirs removed" "$kept" "20260104-100000"
    assert_contains "oldest dirs removed" "$kept" "20260105-100000"
    assert_not_contains "newest dirs kept" "$kept" "20260101-100000"
}

test_prune_results_no_delete_when_under_limit() {
    local base_dir="$TMPDIR_TEST/prune-test-2"
    mkdir -p "$base_dir/my-operator"

    mkdir -p "$base_dir/my-operator/20260101-100000"
    mkdir -p "$base_dir/my-operator/20260102-100000"

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        prune_results "'"$base_dir"'" "my-operator" 5 false
    ' 2>/dev/null

    local remaining
    remaining=$(find "$base_dir/my-operator" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    assert_eq "no delete when under limit" "2" "$remaining"
}

test_prune_results_dry_run_no_delete() {
    local base_dir="$TMPDIR_TEST/prune-test-3"
    mkdir -p "$base_dir/my-operator"

    mkdir -p "$base_dir/my-operator/20260101-100000"
    mkdir -p "$base_dir/my-operator/20260102-100000"
    mkdir -p "$base_dir/my-operator/20260103-100000"

    local dir_count_before
    dir_count_before=$(find "$base_dir/my-operator" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        prune_results "'"$base_dir"'" "my-operator" 1 true
    ' 2>/dev/null

    local dir_count_after
    dir_count_after=$(find "$base_dir/my-operator" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    assert_eq "dry-run does not delete" "$dir_count_before" "$dir_count_after"
}

test_prune_results_no_operator_dir() {
    local base_dir="$TMPDIR_TEST/prune-test-4"

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        prune_results "'"$base_dir"'" "nonexistent-operator" 5 false
    ' 2>/dev/null

    assert_eq "no error when operator dir missing" "0" "$?"
}

test_prune_results_default_retention() {
    local base_dir="$TMPDIR_TEST/prune-test-5"
    mkdir -p "$base_dir/my-operator"

    mkdir -p "$base_dir/my-operator/20260101-100000"
    mkdir -p "$base_dir/my-operator/20260102-100000"
    mkdir -p "$base_dir/my-operator/20260103-100000"

    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/results.sh"
        prune_results "'"$base_dir"'" "my-operator" 2 false
    ' 2>/dev/null

    local remaining
    remaining=$(find "$base_dir/my-operator" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    assert_eq "prune with retention=2" "2" "$remaining"
}

test_prune_results_keeps_latest
test_prune_results_no_delete_when_under_limit
test_prune_results_dry_run_no_delete
test_prune_results_no_operator_dir
test_prune_results_default_retention

print_test_summary
