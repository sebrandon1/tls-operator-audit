#!/bin/bash

is_operator_installed() {
    local name="$1"
    local csv_json="$2"
    local count
    count=$(echo "$csv_json" | jq -r --arg name "$name" '
        [.items[]
        | select(.status.phase == "Succeeded")
        | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
        | length')
    [[ "$count" -gt 0 ]]
}

get_operator_version() {
    local name="$1"
    local csv_json="$2"
    echo "$csv_json" | jq -r --arg name "$name" '
        [.items[]
        | select(.status.phase == "Succeeded")
        | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
        | .[0].spec.version // "unknown"'
}

install_operator() {
    local name="$1"
    local channel="$2"
    local source="$3"
    local namespace="${4:-openshift-operators}"

    log_info "Installing $name (channel: $channel, source: $source, namespace: $namespace)..."

    # Create namespace and OperatorGroup if installing outside openshift-operators
    if [[ "$namespace" != "openshift-operators" ]]; then
        oc create namespace "$namespace" --dry-run=client -o yaml 2>/dev/null | oc apply -f - >/dev/null 2>&1 || true

        # Create OperatorGroup for OwnNamespace mode (only if one doesn't exist)
        local existing_og
        existing_og=$(oc get operatorgroup -n "$namespace" -o name 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$existing_og" -eq 0 ]]; then
            oc apply -f - >/dev/null <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${name}-og
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF
        fi
    fi

    oc apply -f - >/dev/null <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${name}
  namespace: ${namespace}
spec:
  channel: ${channel}
  name: ${name}
  source: ${source}
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

    wait_for_csv "$name" "$namespace" 300
}

wait_for_csv() {
    local name="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    local elapsed=0
    local interval=10

    log_info "Waiting for CSV to reach Succeeded (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        local phase
        phase=$(oc get csv -n "$namespace" -o json 2>/dev/null | jq -r --arg name "$name" '
            [.items[]
            | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
            | .[0].status.phase // "Pending"')

        if [[ "$phase" == "Succeeded" ]]; then
            log_success "CSV ready: $name"
            wait_for_operator_pods "$name" "$namespace"
            return 0
        fi

        log_debug "CSV phase: $phase (${elapsed}s/${timeout}s)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_error "Timed out waiting for CSV: $name"
    return 1
}

wait_for_operator_pods() {
    local name="$1"
    local namespace="$2"
    local timeout=120
    local elapsed=0
    local interval=10

    log_info "Waiting for $name pods to be ready..."

    while [[ $elapsed -lt $timeout ]]; do
        local pods_json
        pods_json=$(oc get pods -n "$namespace" -o json 2>/dev/null || echo '{"items":[]}')

        local not_ready
        not_ready=$(echo "$pods_json" | jq -r --arg name "$name" '
            [.items[]
            | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))
            | select(.status.phase != "Running" and .status.phase != "Succeeded")]
            | length')

        if [[ "$not_ready" -eq 0 ]]; then
            local pod_count
            pod_count=$(echo "$pods_json" | jq -r --arg name "$name" '
                [.items[]
                | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
                | length')
            if [[ "$pod_count" -gt 0 ]]; then
                log_success "$pod_count pods ready for $name"
                return 0
            fi
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_warn "Some $name pods may not be ready yet, proceeding anyway"
}

uninstall_operator() {
    local name="$1"
    local namespace="${2:-openshift-operators}"

    log_info "Uninstalling $name..."

    oc delete subscription "$name" -n "$namespace" --ignore-not-found=true 2>/dev/null || true

    local csvs
    csvs=$(oc get csv -n "$namespace" -o json 2>/dev/null | jq -r --arg name "$name" '
        .items[]
        | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))
        | .metadata.name')

    if [[ -n "$csvs" ]]; then
        echo "$csvs" | while read -r csv; do
            oc delete csv "$csv" -n "$namespace" 2>/dev/null || true
        done
    fi

    log_info "Waiting for $name pods to terminate..."
    local timeout=120
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local pod_count
        pod_count=$(oc get pods -n "$namespace" -o json 2>/dev/null | jq -r --arg name "$name" '
            [.items[]
            | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
            | length')
        if [[ "$pod_count" -eq 0 ]]; then
            log_success "All $name pods terminated"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_warn "Some $name pods still running after ${timeout}s, proceeding"
}

