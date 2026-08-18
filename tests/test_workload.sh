#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/workload.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== Image reference parsing ==="

test_parse_tagged_image_with_digest() {
    local result
    result=$(parse_image_fields \
        "quay.io/jetstack/cert-manager-controller:v1.14.4" \
        "quay.io/jetstack/cert-manager-controller@sha256:deadbeefcafebabe")

    assert_eq "tagged image repository" \
        "quay.io/jetstack/cert-manager-controller" \
        "$(echo "$result" | jq -r '.image')"
    assert_eq "tagged image tag" \
        "v1.14.4" \
        "$(echo "$result" | jq -r '.tag')"
    assert_eq "tagged image digest from imageID" \
        "sha256:deadbeefcafebabe" \
        "$(echo "$result" | jq -r '.digest')"
}

test_parse_registry_port_image() {
    local result
    result=$(parse_image_fields \
        "image-registry.openshift-image-registry.svc:5000/ns/name:v1.2.3" \
        "image-registry.openshift-image-registry.svc:5000/ns/name@sha256:abc123")

    assert_eq "registry-port image repository" \
        "image-registry.openshift-image-registry.svc:5000/ns/name" \
        "$(echo "$result" | jq -r '.image')"
    assert_eq "registry-port image tag" \
        "v1.2.3" \
        "$(echo "$result" | jq -r '.tag')"
    assert_eq "registry-port image digest" \
        "sha256:abc123" \
        "$(echo "$result" | jq -r '.digest')"
}

test_parse_untagged_image() {
    local result
    result=$(parse_image_fields "nginx" "")

    assert_eq "untagged image repository" "nginx" "$(echo "$result" | jq -r '.image')"
    assert_eq "untagged image has empty tag" "" "$(echo "$result" | jq -r '.tag')"
    assert_eq "untagged image has empty digest" "" "$(echo "$result" | jq -r '.digest')"
}

test_parse_digest_only_image() {
    local result
    result=$(parse_image_fields \
        "quay.io/org/app@sha256:0123456789abcdef" \
        "")

    assert_eq "digest-only repository" \
        "quay.io/org/app" \
        "$(echo "$result" | jq -r '.image')"
    assert_eq "digest-only empty tag" "" "$(echo "$result" | jq -r '.tag')"
    assert_eq "digest-only digest from image" \
        "sha256:0123456789abcdef" \
        "$(echo "$result" | jq -r '.digest')"
}

test_parse_sha256_imageid_without_at() {
    local result
    result=$(parse_image_fields "nginx:1.25" "sha256:plaindigest")

    assert_eq "sha256-prefixed imageID digest" \
        "sha256:plaindigest" \
        "$(echo "$result" | jq -r '.digest')"
}

test_parse_tagged_image_with_digest
test_parse_registry_port_image
test_parse_untagged_image
test_parse_digest_only_image
test_parse_sha256_imageid_without_at

echo ""
echo "=== Workload join: Pod / Service / Route / Ingress ==="

write_cluster_fixture() {
    cat > "$TMPDIR_TEST/cluster.json" <<'EOF'
{
  "kind": "List",
  "items": [
    {
      "kind": "Pod",
      "metadata": {"name": "webhook-abc", "namespace": "cert-manager"},
      "spec": {
        "containers": [
          {"name": "webhook", "image": "quay.io/jetstack/cert-manager-webhook:v1.14.4"}
        ]
      },
      "status": {
        "containerStatuses": [
          {
            "name": "webhook",
            "image": "quay.io/jetstack/cert-manager-webhook:v1.14.4",
            "imageID": "quay.io/jetstack/cert-manager-webhook@sha256:aaa111"
          },
          {
            "name": "kube-rbac-proxy",
            "image": "registry.redhat.io/openshift4/ose-kube-rbac-proxy:v4.18",
            "imageID": "registry.redhat.io/openshift4/ose-kube-rbac-proxy@sha256:bbb222"
          }
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "pending-pod", "namespace": "cert-manager"},
      "spec": {
        "containers": [
          {"name": "app", "image": "localhost:5000/custom/app:dev"}
        ]
      },
      "status": {}
    },
    {
      "kind": "Pod",
      "metadata": {"name": "route-backend", "namespace": "openshift-operators"},
      "status": {
        "containerStatuses": [
          {
            "name": "server",
            "image": "quay.io/skupper/grant-server:1.0",
            "imageID": "quay.io/skupper/grant-server@sha256:ccc333"
          }
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "ingress-backend", "namespace": "app-ns"},
      "status": {
        "containerStatuses": [
          {
            "name": "nginx",
            "image": "nginx:1.25",
            "imageID": "docker.io/library/nginx@sha256:ddd444"
          }
        ]
      }
    },
    {
      "kind": "Endpoints",
      "metadata": {"name": "cert-manager-webhook", "namespace": "cert-manager"},
      "subsets": [
        {
          "addresses": [
            {
              "ip": "10.1.2.3",
              "targetRef": {"kind": "Pod", "name": "webhook-abc", "namespace": "cert-manager"}
            }
          ],
          "notReadyAddresses": [
            {
              "ip": "10.1.2.4",
              "targetRef": {"kind": "Pod", "name": "pending-pod", "namespace": "cert-manager"}
            }
          ]
        }
      ]
    },
    {
      "kind": "Endpoints",
      "metadata": {"name": "grant-server", "namespace": "openshift-operators"},
      "subsets": [
        {
          "addresses": [
            {
              "ip": "10.9.8.7",
              "targetRef": {"kind": "Pod", "name": "route-backend"}
            }
          ]
        }
      ]
    },
    {
      "kind": "Endpoints",
      "metadata": {"name": "web", "namespace": "app-ns"},
      "subsets": [
        {
          "addresses": [
            {
              "ip": "10.0.0.9",
              "targetRef": {"kind": "Pod", "name": "ingress-backend", "namespace": "app-ns"}
            }
          ]
        }
      ]
    },
    {
      "kind": "Route",
      "metadata": {"name": "grant-https", "namespace": "openshift-operators"},
      "spec": {
        "to": {"kind": "Service", "name": "grant-server"},
        "alternateBackends": []
      }
    },
    {
      "kind": "Ingress",
      "metadata": {"name": "web-ing", "namespace": "app-ns"},
      "spec": {
        "rules": [
          {
            "http": {
              "paths": [
                {
                  "backend": {
                    "service": {"name": "web", "port": {"number": 443}}
                  }
                }
              ]
            }
          }
        ]
      }
    }
  ]
}
EOF
}

write_reports_fixture() {
    cat > "$TMPDIR_TEST/reports.json" <<'EOF'
[
  {
    "spec": {
      "host": "10.1.2.3",
      "port": 8443,
      "sourceKind": "Pod",
      "sourceName": "webhook-abc",
      "sourceNamespace": "cert-manager"
    },
    "status": {"complianceStatus": "Compliant"}
  },
  {
    "spec": {
      "host": "cert-manager-webhook.cert-manager",
      "port": 443,
      "sourceKind": "Service",
      "sourceName": "cert-manager-webhook",
      "sourceNamespace": "cert-manager"
    },
    "status": {"complianceStatus": "Compliant"}
  },
  {
    "spec": {
      "host": "grant.apps.example.com",
      "port": 443,
      "sourceKind": "Route",
      "sourceName": "grant-https",
      "sourceNamespace": "openshift-operators"
    },
    "status": {"complianceStatus": "Compliant"}
  },
  {
    "spec": {
      "host": "web.example.com",
      "port": 443,
      "sourceKind": "Ingress",
      "sourceName": "web-ing",
      "sourceNamespace": "app-ns"
    },
    "status": {"complianceStatus": "Compliant"}
  },
  {
    "spec": {
      "host": "missing.svc",
      "port": 443,
      "sourceKind": "Service",
      "sourceName": "no-such-service",
      "sourceNamespace": "cert-manager"
    },
    "status": {"complianceStatus": "Closed"}
  }
]
EOF
}

test_join_pod_source() {
    write_cluster_fixture
    write_reports_fixture

    local out
    out=$(join_workload_json "$TMPDIR_TEST/reports.json" "$TMPDIR_TEST/cluster.json")

    local pod_name containers image tag digest proxy
    pod_name=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].name')
    containers=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].containers | length')
    image=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].containers[0].image')
    tag=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].containers[0].tag')
    digest=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].containers[0].digest')
    proxy=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].containers[1].name')

    assert_eq "Pod source resolves pod name" "webhook-abc" "$pod_name"
    assert_eq "Pod source lists all containers" "2" "$containers"
    assert_eq "Pod source image repository" "quay.io/jetstack/cert-manager-webhook" "$image"
    assert_eq "Pod source image tag" "v1.14.4" "$tag"
    assert_eq "Pod source image digest" "sha256:aaa111" "$digest"
    assert_eq "Pod source includes sidecar container" "kube-rbac-proxy" "$proxy"
}

test_join_service_source() {
    write_cluster_fixture
    write_reports_fixture

    local out
    out=$(join_workload_json "$TMPDIR_TEST/reports.json" "$TMPDIR_TEST/cluster.json")

    local pod_count names pending_image
    pod_count=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Service" and .spec.sourceName == "cert-manager-webhook") | .workload.pods | length')
    names=$(echo "$out" | jq -r '[.[] | select(.spec.sourceKind == "Service" and .spec.sourceName == "cert-manager-webhook") | .workload.pods[].name] | sort | join(",")')
    pending_image=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Service" and .spec.sourceName == "cert-manager-webhook") | .workload.pods[] | select(.name == "pending-pod") | .containers[0].image')

    assert_eq "Service source resolves ready and not-ready pods" "2" "$pod_count"
    assert_eq "Service source pod names" "pending-pod,webhook-abc" "$names"
    assert_eq "pending pod falls back to spec image with registry port" \
        "localhost:5000/custom/app" "$pending_image"
}

test_join_route_source() {
    write_cluster_fixture
    write_reports_fixture

    local out
    out=$(join_workload_json "$TMPDIR_TEST/reports.json" "$TMPDIR_TEST/cluster.json")

    local pod digest
    pod=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Route") | .workload.pods[0].name')
    digest=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Route") | .workload.pods[0].containers[0].digest')

    assert_eq "Route source follows Service to pod" "route-backend" "$pod"
    assert_eq "Route source pod digest" "sha256:ccc333" "$digest"
}

test_join_ingress_source() {
    write_cluster_fixture
    write_reports_fixture

    local out
    out=$(join_workload_json "$TMPDIR_TEST/reports.json" "$TMPDIR_TEST/cluster.json")

    local pod tag
    pod=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Ingress") | .workload.pods[0].name')
    tag=$(echo "$out" | jq -r '.[] | select(.spec.sourceKind == "Ingress") | .workload.pods[0].containers[0].tag')

    assert_eq "Ingress source follows backend Service to pod" "ingress-backend" "$pod"
    assert_eq "Ingress source image tag" "1.25" "$tag"
}

test_join_missing_endpoints() {
    write_cluster_fixture
    write_reports_fixture

    local out
    out=$(join_workload_json "$TMPDIR_TEST/reports.json" "$TMPDIR_TEST/cluster.json")

    local pods
    pods=$(echo "$out" | jq -r '.[] | select(.spec.sourceName == "no-such-service") | .workload.pods | length')
    assert_eq "missing Service endpoints yields empty pods" "0" "$pods"
}

test_join_preserves_items_wrapper() {
    write_cluster_fixture
    jq '{items: .}' "$TMPDIR_TEST/reports.json" > "$TMPDIR_TEST/wrapped.json"

    local out
    out=$(join_workload_json "$TMPDIR_TEST/wrapped.json" "$TMPDIR_TEST/cluster.json")

    local has_items pod
    has_items=$(echo "$out" | jq 'has("items")')
    pod=$(echo "$out" | jq -r '.items[] | select(.spec.sourceKind == "Pod") | .workload.pods[0].name')

    assert_eq "items wrapper is preserved" "true" "$has_items"
    assert_eq "wrapped Pod source still resolves" "webhook-abc" "$pod"
}

test_join_empty_cluster() {
    write_reports_fixture
    echo '{"kind":"List","items":[]}' > "$TMPDIR_TEST/empty-cluster.json"

    local out
    out=$(join_workload_json "$TMPDIR_TEST/reports.json" "$TMPDIR_TEST/empty-cluster.json")

    local all_empty
    all_empty=$(echo "$out" | jq '[.[].workload.pods | length] | add')
    assert_eq "empty cluster yields no pods" "0" "$all_empty"
}

test_join_pod_source
test_join_service_source
test_join_route_source
test_join_ingress_source
test_join_missing_endpoints
test_join_preserves_items_wrapper
test_join_empty_cluster

echo ""
echo "=== enrich_report_file guards ==="

test_enrich_missing_file_is_nonfatal() {
    local rc=0
    enrich_report_file "$TMPDIR_TEST/does-not-exist.json" || rc=$?
    assert_eq "enrich_report_file missing file returns 0" "0" "$rc"
}

test_enrich_missing_file_is_nonfatal

echo ""
echo "=== Scan hooks and dashboard wiring ==="

test_tls_test_all_sources_workload() {
    assert_contains "tls-test-all.sh sources lib/workload.sh" \
        "$(cat "$REPO_DIR/tls-test-all.sh")" \
        'source "$SCRIPT_DIR/lib/workload.sh"'
}

test_tls_test_all_enriches_before_generate() {
    local enrich_line generate_line json_line
    json_line=$(grep -n 'echo "$endpoints" > "$results_dir/report.json"' "$REPO_DIR/tls-test-all.sh" | cut -d: -f1)
    enrich_line=$(grep -n 'enrich_report_file "$results_dir/report.json"' "$REPO_DIR/tls-test-all.sh" | cut -d: -f1)
    generate_line=$(grep -n 'generate_reports "$results_dir"' "$REPO_DIR/tls-test-all.sh" | cut -d: -f1)

    if [[ -n "$json_line" && -n "$enrich_line" && -n "$generate_line" \
        && "$enrich_line" -gt "$json_line" && "$generate_line" -gt "$enrich_line" ]]; then
        echo "  PASS: tls-test-all.sh enriches after writing report.json and before generate_reports"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: enrich_report_file should run after JSON write and before generate_reports"
        echo "    JSON write: $json_line enrich: $enrich_line generate: $generate_line"
        FAIL=$((FAIL + 1))
    fi
}

test_mlkem_report_sources_workload() {
    assert_contains "tls-mlkem-report.sh sources lib/workload.sh" \
        "$(cat "$REPO_DIR/tls-mlkem-report.sh")" \
        'source "$SCRIPT_DIR/lib/workload.sh"'
}

test_mlkem_report_enriches() {
    assert_contains "tls-mlkem-report.sh calls enrich_report_file" \
        "$(cat "$REPO_DIR/tls-mlkem-report.sh")" \
        'enrich_report_file "$results_dir/report.json"'
}

test_tls_audit_sources_workload() {
    assert_contains "tls-audit.sh sources lib/workload.sh" \
        "$(cat "$REPO_DIR/tls-audit.sh")" \
        'source "$SCRIPT_DIR/lib/workload.sh"'
}

test_tls_audit_enriches() {
    assert_contains "tls-audit.sh calls enrich_report_file" \
        "$(cat "$REPO_DIR/tls-audit.sh")" \
        'enrich_report_file "${results_dir}/report.json"'
}

test_export_dashboard_maps_workload() {
    assert_contains "export-dashboard.sh maps workload field" \
        "$(cat "$REPO_DIR/export-dashboard.sh")" \
        'workload: (.workload // {pods: []})'
}

test_endpoint_table_has_workload_section() {
    local table
    table=$(cat "$REPO_DIR/docs/_includes/endpoint-table.html")
    assert_contains "endpoint table has Workload heading" "$table" "<h4>Workload</h4>"
    assert_contains "endpoint table shows Pod column" "$table" "<th>Pod</th>"
    assert_contains "endpoint table shows Image column" "$table" "<th>Image</th>"
    assert_contains "endpoint table shows Tag column" "$table" "<th>Tag</th>"
    assert_contains "endpoint table shows SHA column" "$table" "<th>SHA</th>"
    assert_contains "endpoint table guards on workload.pods.size" "$table" "ep.workload.pods.size > 0"
}

test_css_has_workload_styles() {
    local css
    css=$(cat "$REPO_DIR/docs/assets/css/style.css")
    assert_contains "CSS has detail-section-wide" "$css" ".detail-section-wide"
    assert_contains "CSS has image-digest" "$css" ".image-digest"
}

test_export_js_has_format_workload() {
    assert_contains "export.js defines formatWorkload" \
        "$(cat "$REPO_DIR/docs/assets/js/export.js")" \
        "function formatWorkload"
    assert_contains "export.js CSV includes Workload column" \
        "$(cat "$REPO_DIR/docs/assets/js/export.js")" \
        "'Workload'"
}

test_tls_test_all_sources_workload
test_tls_test_all_enriches_before_generate
test_mlkem_report_sources_workload
test_mlkem_report_enriches
test_tls_audit_sources_workload
test_tls_audit_enriches
test_export_dashboard_maps_workload
test_endpoint_table_has_workload_section
test_css_has_workload_styles
test_export_js_has_format_workload

print_test_summary
