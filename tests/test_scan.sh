#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/scan.sh"

echo "=== Unique scan Job and RBAC names ==="

assert_dns1123() {
    local desc="$1" name="$2"
    if [[ ${#name} -le 63 && "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
        echo "  PASS: $desc ($name)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    name: '$name' (len=${#name})"
        FAIL=$((FAIL + 1))
    fi
}

test_scan_resource_id_differs_by_namespace() {
    local a b
    a=$(scan_resource_id "openshift-operators" "123")
    b=$(scan_resource_id "cert-manager" "123")
    if [[ "$a" != "$b" ]]; then
        echo "  PASS: different namespaces produce different scan ids"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scan ids should differ by namespace (got '$a')"
        FAIL=$((FAIL + 1))
    fi
}

test_scan_resource_id_differs_by_pid() {
    local a b
    a=$(scan_resource_id "openshift-operators" "123")
    b=$(scan_resource_id "openshift-operators" "456")
    if [[ "$a" != "$b" ]]; then
        echo "  PASS: different pids produce different scan ids"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: scan ids should differ by pid (got '$a')"
        FAIL=$((FAIL + 1))
    fi
}

test_scan_resource_id_sanitizes_and_truncates() {
    local id
    id=$(scan_resource_id "OpenShift_Operators.Extra.Long.Name.That.Exceeds" "99")
    assert_dns1123 "scan id is DNS-1123" "$id"
    assert_eq "uppercase and punctuation are sanitized" "openshift-operators-99" "$id"
}

test_init_scan_resource_names_are_unique_and_valid() {
    init_scan_resource_names "cert-manager" "2222"
    local ns_a="$SCAN_NAMESPACE" job_a="$JOB_NAME" role_a="$ROLE_NAME" bind_a="$BINDING_NAME"

    init_scan_resource_names "metallb-system" "2222"
    local ns_b="$SCAN_NAMESPACE" job_b="$JOB_NAME" role_b="$ROLE_NAME" bind_b="$BINDING_NAME"

    if [[ "$ns_a" != "$ns_b" && "$job_a" != "$job_b" && "$role_a" != "$role_b" && "$bind_a" != "$bind_b" ]]; then
        echo "  PASS: concurrent scans get unique namespace, Job, ClusterRole, and binding"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: resource names collided across namespaces"
        echo "    a: $ns_a $job_a $role_a $bind_a"
        echo "    b: $ns_b $job_b $role_b $bind_b"
        FAIL=$((FAIL + 1))
    fi

    assert_dns1123 "SCAN_NAMESPACE" "$ns_a"
    assert_dns1123 "JOB_NAME" "$job_a"
    assert_dns1123 "ROLE_NAME" "$role_a"
    assert_dns1123 "BINDING_NAME" "$bind_a"

    assert_contains "Job name includes scan id" "$job_a" "tls-audit-scan-cert-manager-2222"
    assert_contains "namespace includes scan id" "$ns_a" "tls-audit-cert-manager-2222"
}

test_run_scan_initializes_names_before_trap() {
    local content init_line trap_line
    content=$(cat "$REPO_DIR/lib/scan.sh")
    init_line=$(awk '/^run_scan\(\)/{p=1} p && /init_scan_resource_names/{print NR; exit}' "$REPO_DIR/lib/scan.sh")
    trap_line=$(awk '/^run_scan\(\)/{p=1} p && /trap scan_cleanup/{print NR; exit}' "$REPO_DIR/lib/scan.sh")
    if [[ -n "$init_line" && -n "$trap_line" && "$init_line" -lt "$trap_line" ]]; then
        echo "  PASS: unique names are set before the cleanup trap"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: init_scan_resource_names should run before trap scan_cleanup"
        echo "    init_line=$init_line trap_line=$trap_line"
        FAIL=$((FAIL + 1))
    fi
    assert_contains "run_scan calls init_scan_resource_names" "$content" 'init_scan_resource_names "$target_namespace"'
}

test_scan_resource_id_differs_by_namespace
test_scan_resource_id_differs_by_pid
test_scan_resource_id_sanitizes_and_truncates
test_init_scan_resource_names_are_unique_and_valid
test_run_scan_initializes_names_before_trap

print_test_summary
