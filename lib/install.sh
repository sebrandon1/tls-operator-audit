#!/bin/bash

INSTALL_NAMESPACE="openshift-operators"

is_operator_installed() {
    local name="$1"
    local count
    count=$(oc get csv -A -o json 2>/dev/null | jq -r --arg name "$name" '
        [.items[]
        | select(.status.phase == "Succeeded")
        | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
        | length')
    [[ "$count" -gt 0 ]]
}

install_operator() {
    local name="$1"
    local channel="$2"
    local source="$3"

    log_info "Installing $name (channel: $channel, source: $source)..."

    oc apply -f - >/dev/null <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${name}
  namespace: ${INSTALL_NAMESPACE}
spec:
  channel: ${channel}
  name: ${name}
  source: ${source}
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

    wait_for_csv "$name" 300
}

wait_for_csv() {
    local name="$1"
    local timeout="${2:-300}"
    local elapsed=0
    local interval=10

    log_info "Waiting for CSV to reach Succeeded (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        local phase
        phase=$(oc get csv -n "${INSTALL_NAMESPACE}" -o json 2>/dev/null | jq -r --arg name "$name" '
            [.items[]
            | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))]
            | .[0].status.phase // "Pending"')

        if [[ "$phase" == "Succeeded" ]]; then
            log_success "CSV ready: $name"
            wait_for_operator_pods "$name"
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
    local timeout=120
    local elapsed=0
    local interval=10

    log_info "Waiting for operator pods to be ready..."

    while [[ $elapsed -lt $timeout ]]; do
        local not_ready
        not_ready=$(oc get pods -n "${INSTALL_NAMESPACE}" -o json 2>/dev/null | jq '
            [.items[]
            | select(.status.phase != "Running" and .status.phase != "Succeeded")]
            | length')

        if [[ "$not_ready" -eq 0 ]]; then
            local pod_count
            pod_count=$(oc get pods -n "${INSTALL_NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$pod_count" -gt 0 ]]; then
                log_success "All $pod_count pods ready in ${INSTALL_NAMESPACE}"
                return 0
            fi
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_warn "Some pods may not be ready yet, proceeding anyway"
}

uninstall_operator() {
    local name="$1"

    log_info "Uninstalling $name..."

    oc delete subscription "$name" -n "${INSTALL_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true

    local csvs
    csvs=$(oc get csv -n "${INSTALL_NAMESPACE}" -o json 2>/dev/null | jq -r --arg name "$name" '
        .items[]
        | select(.metadata.name | ascii_downcase | contains($name | ascii_downcase))
        | .metadata.name')

    if [[ -n "$csvs" ]]; then
        echo "$csvs" | while read -r csv; do
            oc delete csv "$csv" -n "${INSTALL_NAMESPACE}" 2>/dev/null || true
        done
    fi

    log_info "Waiting for pods to terminate..."
    local timeout=120
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local pod_count
        pod_count=$(oc get pods -n "${INSTALL_NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$pod_count" -eq 0 ]]; then
            log_success "All pods terminated in ${INSTALL_NAMESPACE}"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_warn "Some pods still running after ${timeout}s, proceeding"
}

cleanup_stale_reports() {
    local namespace="$1"
    local stale
    stale=$(oc get tlscompliancereports -o json 2>/dev/null | \
        jq -r --arg ns "$namespace" '.items[] | select(.spec.sourceNamespace == $ns) | .metadata.name' 2>/dev/null) || true
    if [[ -n "$stale" ]]; then
        local count
        count=$(echo "$stale" | wc -l | tr -d ' ')
        while IFS= read -r cr_name; do
            [[ -z "$cr_name" ]] && continue
            oc delete tlscompliancereport "$cr_name" >/dev/null 2>&1 || true
        done <<< "$stale"
        log_info "Cleaned up $count stale CRs from $namespace"
    fi
}
