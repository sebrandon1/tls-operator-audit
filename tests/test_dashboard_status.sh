#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

DASHBOARD_FIXTURES="$SCRIPT_DIR/fixtures/dashboard"
INDEX_FIXTURES="$SCRIPT_DIR/fixtures/index-versions"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== dashboard-status.sh ==="

setup_dashboard_workdir() {
    local name="$1"
    local dir="$TMPDIR_TEST/$name"
    mkdir -p "$dir/lib" "$dir/docs/_data"
    cp "$REPO_DIR/lib/common.sh" "$dir/lib/"
    cp "$REPO_DIR/dashboard-status.sh" "$dir/"
    cp "$DASHBOARD_FIXTURES/scan-results.json" "$dir/docs/_data/"
    cp "$DASHBOARD_FIXTURES/index-versions.json" "$dir/docs/_data/"
    cp "$DASHBOARD_FIXTURES/scan-history.json" "$dir/docs/_data/"
    printf '%s\n' "$dir"
}

test_dashboard_help() {
    local output
    output=$(bash "$REPO_DIR/dashboard-status.sh" --help)
    assert_contains "help mentions local data files" "$output" "No cluster"
}

test_dashboard_summary_from_fixtures() {
    local dir output
    dir=$(setup_dashboard_workdir status-summary)
    output=$(bash "$dir/dashboard-status.sh")

    assert_contains "prints cluster" "$output" "test-cluster"
    assert_contains "prints OCP version" "$output" "4.19.0"
    assert_contains "prints TCO version" "$output" "v1.1.9"
    assert_contains "prints ML-KEM percent" "$output" "70.0%"
    assert_contains "prints endpoint counts" "$output" "7/10"
    assert_contains "prints pass count" "$output" "Pass"
    assert_contains "lists pass-op" "$output" "pass-op"
    assert_contains "lists partial-op" "$output" "partial-op"
    assert_contains "lists fail-op" "$output" "fail-op"
    assert_contains "shows PASS status" "$output" "PASS"
    assert_contains "shows PARTIAL status" "$output" "PARTIAL"
    assert_contains "shows ERROR status" "$output" "ERROR"
}

test_dashboard_index_drift() {
    local dir output
    dir=$(setup_dashboard_workdir status-drift)
    output=$(bash "$dir/dashboard-status.sh")

    assert_contains "warns when updates are available" "$output" "1 operator(s) have newer versions"
    assert_contains "shows scanned to index drift" "$output" "scanned=2.0.0 → index=2.1.0"
    assert_contains "prints history entry count" "$output" "Scan history: 2 entries"
    assert_contains "prints dashboard URL" "$output" "https://sebrandon1.github.io/tls-operator-audit/"
}

test_dashboard_no_drift() {
    local dir output
    dir=$(setup_dashboard_workdir status-no-drift)
    jq '.operators[].update_available = false' \
        "$dir/docs/_data/index-versions.json" > "$dir/docs/_data/index-versions.tmp"
    mv "$dir/docs/_data/index-versions.tmp" "$dir/docs/_data/index-versions.json"

    output=$(bash "$dir/dashboard-status.sh")
    assert_contains "reports all operators current" "$output" "All operators at latest index versions"
}

test_dashboard_missing_data_file() {
    local dir exit_code
    dir=$(setup_dashboard_workdir status-missing)
    rm -f "$dir/docs/_data/scan-history.json"

    exit_code=0
    bash "$dir/dashboard-status.sh" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "exits when a data file is missing" "1" "$exit_code"
}

setup_index_workdir() {
    local name="$1"
    local dir="$TMPDIR_TEST/$name"
    mkdir -p "$dir/lib" "$dir/docs/_data" "$dir/bin"
    cp "$REPO_DIR/lib/common.sh" "$dir/lib/"
    cp "$REPO_DIR/check-index-versions.sh" "$dir/"
    cp "$INDEX_FIXTURES/operators.yaml" "$dir/operators.yaml"
    cp "$INDEX_FIXTURES/scan-results.json" "$dir/docs/_data/scan-results.json"
    cp "$INDEX_FIXTURES/existing-tracker.json" "$dir/docs/_data/index-versions.json"
    cp "$INDEX_FIXTURES/mock-oc" "$dir/bin/oc"
    chmod +x "$dir/bin/oc"
    : > "$dir/kubeconfig"
    printf '%s\n' "$dir"
}

run_index_check() {
    local dir="$1"
    shift
    PATH="$dir/bin:$PATH" bash "$dir/check-index-versions.sh" \
        --kubeconfig "$dir/kubeconfig" \
        --operators "$dir/operators.yaml" \
        "$@"
}

test_index_help_and_unknown_option() {
    local output exit_code
    output=$(bash "$REPO_DIR/check-index-versions.sh" --help)
    assert_contains "help documents --operators" "$output" "--operators"

    exit_code=0
    bash "$REPO_DIR/check-index-versions.sh" --not-a-flag >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "rejects unknown option" "1" "$exit_code"
}

test_index_missing_kubeconfig() {
    local dir exit_code
    dir=$(setup_index_workdir index-no-kube)
    rm -f "$dir/kubeconfig"

    exit_code=0
    PATH="$dir/bin:$PATH" bash "$dir/check-index-versions.sh" \
        --kubeconfig "$dir/kubeconfig" \
        --operators "$dir/operators.yaml" \
        --quiet >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "exits when kubeconfig is missing" "1" "$exit_code"
}

test_index_version_comparison() {
    local dir tracker
    dir=$(setup_index_workdir index-compare)
    run_index_check "$dir" --quiet >/dev/null

    tracker="$dir/docs/_data/index-versions.json"
    assert_eq "tracker is valid JSON" "true" "$(jq 'has("checked") and has("operators")' "$tracker")"
    assert_eq "operator count" "7" "$(jq '.operators | length' "$tracker")"

    assert_eq "current-op has no update" "false" \
        "$(jq -r '.operators[] | select(.name=="current-op") | .update_available' "$tracker")"
    assert_eq "current-op index version" "1.0.0" \
        "$(jq -r '.operators[] | select(.name=="current-op") | .index_version' "$tracker")"

    assert_eq "stale-op flags update" "true" \
        "$(jq -r '.operators[] | select(.name=="stale-op") | .update_available' "$tracker")"
    assert_eq "stale-op index version" "2.0.0" \
        "$(jq -r '.operators[] | select(.name=="stale-op") | .index_version' "$tracker")"
    assert_eq "stale-op scanned version" "1.5.0" \
        "$(jq -r '.operators[] | select(.name=="stale-op") | .scanned_version' "$tracker")"
    assert_eq "stale-op records version_changed" "true" \
        "$(jq -r '.operators[] | select(.name=="stale-op") | .version_changed' "$tracker")"
    assert_eq "stale-op prev index version" "1.9.0" \
        "$(jq -r '.operators[] | select(.name=="stale-op") | .prev_index_version' "$tracker")"
}

test_index_missing_packagemanifest() {
    local dir tracker
    dir=$(setup_index_workdir index-missing-pkg)
    run_index_check "$dir" --quiet >/dev/null
    tracker="$dir/docs/_data/index-versions.json"

    assert_eq "missing packagemanifest records error" "not found in catalog" \
        "$(jq -r '.operators[] | select(.name=="missing-pkg") | .error' "$tracker")"
    assert_eq "missing packagemanifest is not an update" "false" \
        "$(jq -r '.operators[] | select(.name=="missing-pkg") | .update_available' "$tracker")"
}

test_index_preinstalled_from_csv() {
    local dir tracker
    dir=$(setup_index_workdir index-preinstalled)
    run_index_check "$dir" --quiet >/dev/null
    tracker="$dir/docs/_data/index-versions.json"

    assert_eq "catalog:null becomes pre-installed" "pre-installed" \
        "$(jq -r '.operators[] | select(.name=="preinstalled-op") | .catalog' "$tracker")"
    assert_eq "pre-installed version comes from Succeeded CSV" "1.8.2" \
        "$(jq -r '.operators[] | select(.name=="preinstalled-op") | .index_version' "$tracker")"
    assert_eq "pre-installed flags update vs scanned version" "true" \
        "$(jq -r '.operators[] | select(.name=="preinstalled-op") | .update_available' "$tracker")"
}

test_index_catalog_urls() {
    local dir tracker
    dir=$(setup_index_workdir index-urls)
    run_index_check "$dir" --quiet >/dev/null
    tracker="$dir/docs/_data/index-versions.json"

    assert_contains "redhat catalog URL" \
        "$(jq -r '.operators[] | select(.name=="current-op") | .catalog_url' "$tracker")" \
        "redhat-operator-index"
    assert_contains "certified catalog URL" \
        "$(jq -r '.operators[] | select(.name=="certified-op") | .catalog_url' "$tracker")" \
        "certified-operator-index"
    assert_contains "community catalog URL" \
        "$(jq -r '.operators[] | select(.name=="community-op") | .catalog_url' "$tracker")" \
        "community-operator-index"
    assert_eq "unknown catalog image has empty URL" "" \
        "$(jq -r '.operators[] | select(.name=="custom-op") | .catalog_url' "$tracker")"
}

test_index_summary_lists_updates() {
    local dir output
    dir=$(setup_index_workdir index-summary)
    output=$(run_index_check "$dir")

    assert_contains "summary title" "$output" "Index Version Check"
    assert_contains "lists stale-op update" "$output" "stale-op: scanned=1.5.0 → index=2.0.0"
}

test_dashboard_help
test_dashboard_summary_from_fixtures
test_dashboard_index_drift
test_dashboard_no_drift
test_dashboard_missing_data_file

echo ""
echo "=== check-index-versions.sh ==="

test_index_help_and_unknown_option
test_index_missing_kubeconfig
test_index_version_comparison
test_index_missing_packagemanifest
test_index_preinstalled_from_csv
test_index_catalog_urls
test_index_summary_lists_updates

print_test_summary
