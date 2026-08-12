#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

OPERATORS_YAML="$REPO_DIR/operators.yaml"
INSTALL_OPERATOR_CODE=$(grep -A 50 "^install_operator()" "$REPO_DIR/lib/install.sh")

echo "=== OperatorGroup-scoped Installation Tests ==="

test_install_namespace_default() {
    local install_code="$INSTALL_OPERATOR_CODE"

    assert_contains "install_operator has default namespace parameter" \
        "$install_code" \
        'namespace="${4:-openshift-operators}"'
}

test_operatorgroup_creation_logic() {
    local install_code="$INSTALL_OPERATOR_CODE"

    assert_contains "checks if namespace is not openshift-operators" \
        "$install_code" \
        'if [[ "$namespace" != "openshift-operators" ]]'

    assert_contains "creates namespace" \
        "$install_code" \
        "oc create namespace"

    assert_contains "creates OperatorGroup" \
        "$install_code" \
        "kind: OperatorGroup"
}

test_operatorgroup_target_namespaces() {
    local install_code="$INSTALL_OPERATOR_CODE"

    assert_contains "OperatorGroup has targetNamespaces" \
        "$install_code" \
        "targetNamespaces:"
}

test_operators_yaml_documents_install_namespace() {
    assert_contains "operators.yaml documents install_namespace" \
        "$(cat "$OPERATORS_YAML")" \
        "install_namespace:"

    assert_contains "operators.yaml explains OperatorGroup creation" \
        "$(cat "$OPERATORS_YAML")" \
        "OperatorGroup-scoped installations:"
}

test_operators_yaml_has_examples() {
    local using_install_ns
    using_install_ns=$(grep -c "install_namespace: " "$OPERATORS_YAML" || echo "0")

    if [[ "$using_install_ns" -gt 0 ]]; then
        echo "  PASS: operators.yaml has $using_install_ns operator(s) using install_namespace"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: operators.yaml has no operators using install_namespace (expected at least 1 example)"
        FAIL=$((FAIL + 1))
    fi
}

test_operators_use_install_namespace() {
    local count
    count=$(yq -r '.operators[] | select(has("install_namespace")) | .name' "$OPERATORS_YAML" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$count" -eq 0 ]]; then
        echo "  SKIP: No operators with install_namespace to validate"
        return
    fi

    echo "  PASS: Found $count operator(s) with install_namespace"
    PASS=$((PASS + 1))
}

test_subscription_uses_install_namespace() {
    local install_code="$INSTALL_OPERATOR_CODE"

    assert_contains "Subscription is created in specified namespace" \
        "$install_code" \
        'namespace: ${namespace}'
}

# Run all tests
test_install_namespace_default
test_operatorgroup_creation_logic
test_operatorgroup_target_namespaces
test_operators_yaml_documents_install_namespace
test_operators_yaml_has_examples
test_operators_use_install_namespace
test_subscription_uses_install_namespace

print_test_summary
