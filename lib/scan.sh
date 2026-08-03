#!/bin/bash

SCAN_NAMESPACE="tls-operator-audit-scan"
JOB_NAME="tls-audit-scan"
SA_NAME="tco-scanner"
ROLE_NAME="tco-audit-scanner-role"
BINDING_NAME="tco-audit-scanner-binding"

scan_cleanup() {
    log_info "Cleaning up scan resources..."
    oc delete job "${JOB_NAME}" -n "${SCAN_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
    oc delete clusterrolebinding "${BINDING_NAME}" --ignore-not-found=true 2>/dev/null || true
    oc delete clusterrole "${ROLE_NAME}" --ignore-not-found=true 2>/dev/null || true
    oc delete namespace "${SCAN_NAMESPACE}" --ignore-not-found=true 2>/dev/null || true
}

_SCAN_PREV_EXIT_TRAP=""
_SCAN_PREV_INT_TRAP=""
_SCAN_PREV_TERM_TRAP=""

_scan_finish() {
    scan_cleanup
    # shellcheck disable=SC2064
    eval "${_SCAN_PREV_EXIT_TRAP:-trap - EXIT}"
    # shellcheck disable=SC2064
    eval "${_SCAN_PREV_INT_TRAP:-trap - INT}"
    # shellcheck disable=SC2064
    eval "${_SCAN_PREV_TERM_TRAP:-trap - TERM}"
}

run_scan() {
    local target_namespace="$1"
    local results_dir="$2"
    local image="$3"

    _SCAN_PREV_EXIT_TRAP=$(trap -p EXIT || true)
    _SCAN_PREV_INT_TRAP=$(trap -p INT || true)
    _SCAN_PREV_TERM_TRAP=$(trap -p TERM || true)
    trap scan_cleanup EXIT INT TERM

    log_info "Creating scan namespace and RBAC..."
    oc create namespace "${SCAN_NAMESPACE}" --dry-run=client -o yaml | oc apply -f - >/dev/null
    oc create serviceaccount "${SA_NAME}" -n "${SCAN_NAMESPACE}" --dry-run=client -o yaml | oc apply -f - >/dev/null

    oc apply -f - >/dev/null <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${ROLE_NAME}
rules:
  - apiGroups: [""]
    resources: [events]
    verbs: [create, patch]
  - apiGroups: [""]
    resources: [pods, services]
    verbs: [get, list, watch]
  - apiGroups: [config.openshift.io]
    resources: [apiservers]
    verbs: [get, list, watch]
  - apiGroups: [discovery.k8s.io]
    resources: [endpointslices]
    verbs: [get, list, watch]
  - apiGroups: [gateway.networking.k8s.io]
    resources: [gateways, httproutes, tlsroutes]
    verbs: [get, list, watch]
  - apiGroups: [machineconfiguration.openshift.io]
    resources: [kubeletconfigs]
    verbs: [get, list, watch]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses]
    verbs: [get, list, watch]
  - apiGroups: [operator.openshift.io]
    resources: [ingresscontrollers]
    verbs: [get, list, watch]
  - apiGroups: [route.openshift.io]
    resources: [routes]
    verbs: [get, list, watch]
  - apiGroups: [security.telco.openshift.io]
    resources: [tlscompliancereports]
    verbs: [create, delete, get, list, patch, update, watch]
  - apiGroups: [security.telco.openshift.io]
    resources: [tlscompliancereports/finalizers]
    verbs: [update]
  - apiGroups: [security.telco.openshift.io]
    resources: [tlscompliancereports/status, tlscompliancetargets/status]
    verbs: [get, patch, update]
  - apiGroups: [security.telco.openshift.io]
    resources: [tlscompliancetargets]
    verbs: [get, list, watch]
EOF

    oc create clusterrolebinding "${BINDING_NAME}" \
        --clusterrole="${ROLE_NAME}" \
        --serviceaccount="${SCAN_NAMESPACE}:${SA_NAME}" \
        --dry-run=client -o yaml | oc apply -f - >/dev/null

    log_info "Deploying scan Job (image: ${image}, namespace scope: ${target_namespace})..."
    oc apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${SCAN_NAMESPACE}
spec:
  backoffLimit: 0
  template:
    spec:
      serviceAccountName: ${SA_NAME}
      restartPolicy: Never
      containers:
        - name: scanner
          image: ${image}
          imagePullPolicy: Always
          args:
            - --run-once
            - --output-format=json
            - --output-file=/results/report.json
            - --include-namespaces=${target_namespace}
          volumeMounts:
            - name: results
              mountPath: /results
      volumes:
        - name: results
          emptyDir: {}
EOF

    log_info "Waiting for scan to complete (timeout: 600s)..."
    local wait_failed=false
    if ! oc wait --for=condition=complete "job/${JOB_NAME}" \
        -n "${SCAN_NAMESPACE}" --timeout=600s 2>/dev/null; then
        wait_failed=true
    fi

    local pod
    pod=$(oc get pods -n "${SCAN_NAMESPACE}" \
        -l "job-name=${JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ "${wait_failed}" == "true" ]]; then
        local failed
        failed=$(oc get job "${JOB_NAME}" -n "${SCAN_NAMESPACE}" \
            -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        failed="${failed:-0}"

        if [[ -n "${pod}" ]]; then
            log_warn "Job logs:"
            oc logs "${pod}" -n "${SCAN_NAMESPACE}" --tail=50 2>/dev/null || true
        fi

        if [[ "${failed}" -gt 0 ]]; then
            log_info "Scan completed with non-compliant endpoints (exit code 1)."
        else
            log_error "Scan timed out or failed to start."
            SCAN_EXIT_CODE=2
            _scan_finish
            return
        fi
    fi

    SCAN_EXIT_CODE=0
    if [[ -n "${pod}" ]]; then
        SCAN_EXIT_CODE=$(oc get pod "${pod}" -n "${SCAN_NAMESPACE}" \
            -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "2")
        if [[ -z "${SCAN_EXIT_CODE}" ]]; then
            log_error "Container did not terminate."
            SCAN_EXIT_CODE=2
            _scan_finish
            return
        fi
        oc cp "${SCAN_NAMESPACE}/${pod}:/results/report.json" "${results_dir}/report.json" 2>/dev/null || true
    fi

    if [[ -f "${results_dir}/report.json" ]]; then
        log_success "Scan results saved to ${results_dir}/report.json"
    else
        log_warn "Could not retrieve results file from scan pod."
    fi

    _scan_finish
}
