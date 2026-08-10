#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

TMPDIR_DISC=$(mktemp -d)
trap 'rm -rf "$TMPDIR_DISC"' EXIT

# ===========================================================================
echo "=== Issue #18: build_ns_filter ==="
# ===========================================================================

create_operators_yaml() {
    cat > "$TMPDIR_DISC/operators.yaml" <<'EOF'
operators:
  - name: cert-manager
    namespaces:
      - cert-manager
  - name: rhoai
    namespaces:
      - redhat-ods-operator
      - redhat-ods-applications
      - redhat-ods-monitoring
EOF
}

test_build_ns_filter_single() {
    create_operators_yaml
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/discovery.sh"
        build_ns_filter "'"$TMPDIR_DISC"'/operators.yaml" 0
    ' 2>/dev/null)

    assert_eq "single namespace filter" \
        '.spec.sourceNamespace == "cert-manager"' \
        "$output"
}

test_build_ns_filter_multiple() {
    create_operators_yaml
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/discovery.sh"
        build_ns_filter "'"$TMPDIR_DISC"'/operators.yaml" 1
    ' 2>/dev/null)

    assert_contains "multi-ns filter has first ns" "$output" '"redhat-ods-operator"'
    assert_contains "multi-ns filter has second ns" "$output" '"redhat-ods-applications"'
    assert_contains "multi-ns filter has third ns" "$output" '"redhat-ods-monitoring"'
    assert_contains "multi-ns filter uses or" "$output" " or "
}

test_build_ns_filter_empty() {
    cat > "$TMPDIR_DISC/empty-ns.yaml" <<'EOF'
operators:
  - name: empty-operator
    namespaces: []
EOF
    local output
    output=$(bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/discovery.sh"
        build_ns_filter "'"$TMPDIR_DISC"'/empty-ns.yaml" 0
    ' 2>/dev/null)

    assert_eq "empty namespace list returns empty filter" "" "$output"
}

test_build_ns_filter_single
test_build_ns_filter_multiple
test_build_ns_filter_empty

# ===========================================================================
echo ""
echo "=== Issue #19: is_operator_installed with cached CSV ==="
# ===========================================================================

MOCK_CSV_JSON='{
  "items": [
    {
      "metadata": {"name": "cert-manager-operator.v1.15.0", "namespace": "openshift-operators"},
      "status": {"phase": "Succeeded"},
      "spec": {"version": "1.15.0"}
    },
    {
      "metadata": {"name": "amq-streams.v2.9.0", "namespace": "openshift-operators"},
      "status": {"phase": "Succeeded"},
      "spec": {"version": "2.9.0"}
    },
    {
      "metadata": {"name": "failing-operator.v1.0.0", "namespace": "openshift-operators"},
      "status": {"phase": "InstallReady"},
      "spec": {"version": "1.0.0"}
    }
  ]
}'

test_is_installed_found() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/install.sh"
        is_operator_installed "cert-manager" '"'$MOCK_CSV_JSON'"'
    ' 2>/dev/null || exit_code=$?

    assert_exit_code "is_operator_installed finds matching CSV" "0" "$exit_code"
}

test_is_installed_not_found() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/install.sh"
        is_operator_installed "nonexistent-operator" '"'$MOCK_CSV_JSON'"'
    ' 2>/dev/null || exit_code=$?

    assert_eq "is_operator_installed rejects missing operator" "1" "$exit_code"
}

test_is_installed_ignores_non_succeeded() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/install.sh"
        is_operator_installed "failing-operator" '"'$MOCK_CSV_JSON'"'
    ' 2>/dev/null || exit_code=$?

    assert_eq "is_operator_installed ignores non-Succeeded phase" "1" "$exit_code"
}

test_is_installed_case_insensitive() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/install.sh"
        is_operator_installed "AMQ-Streams" '"'$MOCK_CSV_JSON'"'
    ' 2>/dev/null || exit_code=$?

    assert_exit_code "is_operator_installed is case-insensitive" "0" "$exit_code"
}

test_is_installed_empty_json() {
    local exit_code=0
    bash -c '
        set -euo pipefail
        source "'"$REPO_DIR"'/lib/common.sh"
        source "'"$REPO_DIR"'/lib/install.sh"
        is_operator_installed "anything" "{\"items\":[]}"
    ' 2>/dev/null || exit_code=$?

    assert_eq "is_operator_installed handles empty items" "1" "$exit_code"
}

test_is_installed_found
test_is_installed_not_found
test_is_installed_ignores_non_succeeded
test_is_installed_case_insensitive
test_is_installed_empty_json

print_test_summary
