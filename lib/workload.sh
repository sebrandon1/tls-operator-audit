#!/bin/bash

# Enrich TLSComplianceReport JSON with backing-pod and container image identity.
# Assumes lib/common.sh is already sourced (log_* helpers).

_workload_jq_defs() {
    cat <<'JQ'
def digest_from($s):
  if ($s | type) != "string" or $s == "" then ""
  elif $s | contains("@") then ($s | split("@")[-1])
  elif ($s | startswith("sha256:")) then $s
  else ""
  end;

def strip_digest($s):
  if ($s | type) != "string" then ""
  elif $s | contains("@") then ($s | split("@")[0])
  else $s
  end;

def tag_from($ref):
  (strip_digest($ref)) as $nodigest |
  ($nodigest | split("/")[-1]) as $last |
  if ($last | contains(":")) then ($last | split(":")[1:] | join(":"))
  else ""
  end;

def repository_from($ref):
  (strip_digest($ref)) as $nodigest |
  ($nodigest | split("/")[-1]) as $last |
  if ($last | contains(":")) then
    ($nodigest | rindex(":")) as $idx |
    $nodigest[0:$idx]
  else
    $nodigest
  end;
JQ
}

_workload_parse_jq() {
    _workload_jq_defs
    cat <<'JQ'

{
  image: repository_from($image),
  tag: tag_from($image),
  digest: (
    (digest_from($imageID)) as $d |
    if $d != "" then $d else digest_from($image) end
  )
}
JQ
}

_workload_join_jq() {
    _workload_jq_defs
    cat <<'JQ'

def report_items($raw):
  if ($raw | type == "object") and ($raw | has("items")) then $raw.items
  elif ($raw | type == "array") then $raw
  else [$raw]
  end;

def cluster_items($cluster):
  if $cluster == null then []
  elif ($cluster | type == "object") and ($cluster | has("items")) then $cluster.items
  elif ($cluster | type == "array") then $cluster
  else []
  end;

def containers_of($pod):
  if ($pod.status.containerStatuses // [] | length) > 0 then
    [$pod.status.containerStatuses[] | {
      name: (.name // ""),
      image: repository_from(.image // ""),
      tag: tag_from(.image // ""),
      digest: (
        (digest_from(.imageID // "")) as $d |
        if $d != "" then $d else digest_from(.image // "") end
      )
    }]
  else
    [($pod.spec.containers // [])[] | {
      name: (.name // ""),
      image: repository_from(.image // ""),
      tag: tag_from(.image // ""),
      digest: digest_from(.image // "")
    }]
  end;

def workload_pods($refs; $pod_index):
  [
    $refs[] |
    $pod_index["\(.namespace)/\(.name)"] |
    select(. != null) |
    {
      name: .metadata.name,
      namespace: .metadata.namespace,
      containers: containers_of(.)
    }
  ] | unique_by([.namespace, .name]) | sort_by(.namespace, .name);

def pods_for_service($ns; $name; $ep_index):
  ($ep_index["\($ns)/\($name)"] // null) as $e |
  if $e == null then []
  else
    [
      (($e.subsets // [])[]) |
      ((.addresses // []) + (.notReadyAddresses // []))[] |
      select((.targetRef.kind == "Pod") and ((.targetRef.name // "") != "")) |
      {name: .targetRef.name, namespace: (.targetRef.namespace // $ns)}
    ] | unique_by([.namespace, .name])
  end;

def route_services($ns; $name; $routes):
  [
    $routes[] |
    select(.metadata.namespace == $ns and .metadata.name == $name) |
    (([.spec.to] + (.spec.alternateBackends // []))[] |
      select((.kind == "Service" or .kind == null or .kind == "") and ((.name // "") != "")) |
      {namespace: $ns, name: .name})
  ];

def ingress_services($ns; $name; $ingresses):
  [
    $ingresses[] |
    select(.metadata.namespace == $ns and .metadata.name == $name) |
    (
      ([.spec.defaultBackend] | map(select(. != null))) +
      [((.spec.rules // [])[]) | ((.http.paths // [])[]) | .backend]
    )[] |
    if .service.name then {namespace: $ns, name: .service.name}
    elif .serviceName then {namespace: $ns, name: .serviceName}
    else empty
    end
  ] | unique_by([.namespace, .name]);

.[0] as $raw |
.[1] as $cluster |

(cluster_items($cluster)) as $objects |

($objects | map(select(.kind == "Pod" or .kind == "pod"))) as $pods |
($objects | map(select(.kind == "Endpoints"))) as $endpoints |
($objects | map(select(.kind == "Route"))) as $routes |
($objects | map(select(.kind == "Ingress"))) as $ingresses |

(reduce $pods[] as $p ({}; . + {("\($p.metadata.namespace)/\($p.metadata.name)"): $p})) as $pod_index |
(reduce $endpoints[] as $e ({}; . + {("\($e.metadata.namespace)/\($e.metadata.name)"): $e})) as $ep_index |

(report_items($raw) | map(
  . as $item |
  ($item.spec.sourceKind // "") as $kind |
  ($item.spec.sourceName // "") as $name |
  ($item.spec.sourceNamespace // "") as $ns |
  (
    if $kind == "Pod" then
      [{namespace: $ns, name: $name}]
    elif $kind == "Service" then
      pods_for_service($ns; $name; $ep_index)
    elif $kind == "Route" then
      [route_services($ns; $name; $routes)[] | pods_for_service(.namespace; .name; $ep_index)[]]
    elif $kind == "Ingress" then
      [ingress_services($ns; $name; $ingresses)[] | pods_for_service(.namespace; .name; $ep_index)[]]
    else
      []
    end
  ) as $refs |
  $item + {workload: {pods: workload_pods($refs; $pod_index)}}
)) as $enriched |

if ($raw | type == "object") and ($raw | has("items")) then
  $raw + {items: $enriched}
else
  $enriched
end
JQ
}

# Parse an image reference into {image, tag, digest} JSON.
# Args: image [imageID]
parse_image_fields() {
    local image="${1:-}"
    local image_id="${2:-}"
    jq -n --arg image "$image" --arg imageID "$image_id" -f <(_workload_parse_jq)
}

# Join TLS report JSON with cluster objects (pods/endpoints/routes/ingresses).
# Args: reports_file cluster_file
# Writes enriched JSON to stdout.
join_workload_json() {
    local reports_file="$1"
    local cluster_file="$2"
    jq -s -f <(_workload_join_jq) "$reports_file" "$cluster_file"
}

_fetch_namespace_workload_objects() {
    local ns="$1"
    local tmp
    tmp=$(mktemp -d)

    if ! oc get pods -n "$ns" -o json > "$tmp/pods.json" 2>/dev/null || ! jq empty "$tmp/pods.json" 2>/dev/null; then
        echo '{"items":[]}' > "$tmp/pods.json"
    fi
    if ! oc get endpoints -n "$ns" -o json > "$tmp/endpoints.json" 2>/dev/null || ! jq empty "$tmp/endpoints.json" 2>/dev/null; then
        echo '{"items":[]}' > "$tmp/endpoints.json"
    fi
    if ! oc get routes.route.openshift.io -n "$ns" -o json > "$tmp/routes.json" 2>/dev/null || ! jq empty "$tmp/routes.json" 2>/dev/null; then
        echo '{"items":[]}' > "$tmp/routes.json"
    fi
    if ! oc get ingresses.networking.k8s.io -n "$ns" -o json > "$tmp/ingresses.json" 2>/dev/null || ! jq empty "$tmp/ingresses.json" 2>/dev/null; then
        echo '{"items":[]}' > "$tmp/ingresses.json"
    fi

    jq -n \
        --slurpfile pods "$tmp/pods.json" \
        --slurpfile eps "$tmp/endpoints.json" \
        --slurpfile routes "$tmp/routes.json" \
        --slurpfile ings "$tmp/ingresses.json" \
        '{
            kind: "List",
            items: (
                (($pods[0].items // []) | map(.kind = (.kind // "Pod"))) +
                (($eps[0].items // []) | map(.kind = (.kind // "Endpoints"))) +
                (($routes[0].items // []) | map(.kind = (.kind // "Route"))) +
                (($ings[0].items // []) | map(.kind = (.kind // "Ingress")))
            )
        }'

    rm -rf "$tmp"
}

# Enrich a report.json file in place with workload (pod/image) details.
# Missing cluster objects or oc failures are non-fatal.
enrich_report_file() {
    local report_file="${1:-}"

    if [[ -z "$report_file" || ! -f "$report_file" ]]; then
        log_warn "No report file to enrich: ${report_file:-<empty>}"
        return 0
    fi

    if ! command -v oc >/dev/null 2>&1; then
        log_warn "oc not available, skipping workload enrichment"
        return 0
    fi

    local ns_list
    ns_list=$(jq -r '
        def items: if type == "object" and has("items") then .items elif type == "array" then . else [.] end;
        [items[] | .spec.sourceNamespace // empty | select(. != "")] | unique[]
    ' "$report_file" 2>/dev/null || true)

    local tmpdir
    tmpdir=$(mktemp -d)
    local cluster_file="$tmpdir/cluster.json"
    local ns_files=()

    if [[ -z "$ns_list" ]]; then
        echo '{"kind":"List","items":[]}' > "$cluster_file"
    else
        while IFS= read -r ns; do
            [[ -z "$ns" ]] && continue
            local ns_file="$tmpdir/ns-${ns}.json"
            if ! _fetch_namespace_workload_objects "$ns" > "$ns_file"; then
                echo '{"kind":"List","items":[]}' > "$ns_file"
            fi
            ns_files+=("$ns_file")
        done <<< "$ns_list"

        if [[ ${#ns_files[@]} -eq 0 ]]; then
            echo '{"kind":"List","items":[]}' > "$cluster_file"
        elif ! jq -s '{kind:"List", items: [.[].items[]]}' "${ns_files[@]}" > "$cluster_file"; then
            echo '{"kind":"List","items":[]}' > "$cluster_file"
        fi
    fi

    local enriched_file="$tmpdir/enriched.json"
    if join_workload_json "$report_file" "$cluster_file" > "$enriched_file" && [[ -s "$enriched_file" ]]; then
        mv "$enriched_file" "$report_file"
        log_info "Enriched report with workload (pod/image) details"
    else
        log_warn "Workload enrichment failed, leaving report unchanged"
    fi

    rm -rf "$tmpdir"
    return 0
}
