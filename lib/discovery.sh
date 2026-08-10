#!/bin/bash

# ============================================================================
# TCO PRECHECK
# ============================================================================

precheck_tco() {
    log_info "Checking for tls-compliance-operator on cluster..."

    local deploy_json
    deploy_json=$(oc get deployment -A \
        -l app.kubernetes.io/name=tls-compliance-operator \
        -o json 2>/dev/null)

    local count
    count=$(echo "$deploy_json" | jq '.items | length')

    if [[ "$count" -eq 0 ]]; then
        log_error "tls-compliance-operator is not deployed on this cluster."
        log_error "Deploy it first: https://github.com/sebrandon1/tls-compliance-operator"
        exit 1
    fi

    TCO_IMAGE=$(echo "$deploy_json" | jq -r '.items[0].spec.template.spec.containers[0].image')
    TCO_NAMESPACE=$(echo "$deploy_json" | jq -r '.items[0].metadata.namespace')

    local ready
    ready=$(echo "$deploy_json" | jq -r '.items[0].status.readyReplicas // 0')
    if [[ "$ready" -eq 0 ]]; then
        log_warn "tls-compliance-operator deployment has 0 ready replicas"
    fi

    log_success "Found tls-compliance-operator in namespace '$TCO_NAMESPACE' (image: $TCO_IMAGE)"
}

# ============================================================================
# OPERATOR LISTING
# ============================================================================

list_operators() {
    log_info "Listing operators on cluster..."

    local csv_json
    csv_json=$(oc get csv -A -o json 2>/dev/null)

    local count
    count=$(echo "$csv_json" | jq '[.items[] | select(.status.phase == "Succeeded")] | length')

    if [[ "$count" -eq 0 ]]; then
        log_warn "No operators found in Succeeded phase."
        return
    fi

    printf "\n%-50s %-35s %-12s\n" "OPERATOR" "NAMESPACE" "VERSION"
    printf "%-50s %-35s %-12s\n" "--------" "---------" "-------"

    echo "$csv_json" | jq -r '
        .items[]
        | select(.status.phase == "Succeeded")
        | [.metadata.name, .metadata.namespace, (.spec.version // "unknown")]
        | @tsv' | sort | while IFS=$'\t' read -r name ns version; do
        printf "%-50s %-35s %-12s\n" "$name" "$ns" "$version"
    done

    echo ""
    log_info "Total: $count operators"
}

# ============================================================================
# OPERATOR DISCOVERY
# ============================================================================

discover_operator() {
    local search_name="$1"
    local search_version="${2:-}"

    log_info "Searching for operator matching '$search_name'..."

    local csv_json
    csv_json=$(oc get csv -A -o json 2>/dev/null)

    local matches
    matches=$(echo "$csv_json" | jq -r --arg name "$search_name" --arg version "$search_version" '
        [.items[]
        | select(.status.phase == "Succeeded")
        | . as $item
        | ($item.metadata.name | gsub("\\.[vV][0-9].*$"; "") | ascii_downcase) as $stripped
        | ($item.spec.displayName // "" | ascii_downcase) as $display
        | select(
            ($stripped | contains($name | ascii_downcase))
            or ($display | contains($name | ascii_downcase))
          )
        | select($version == "" or ($item.spec.version // "") == $version)
        | {
            csv_name: $item.metadata.name,
            namespace: $item.metadata.namespace,
            display: ($item.spec.displayName // $item.metadata.name),
            version: ($item.spec.version // "unknown")
          }
        ]')

    local match_count
    match_count=$(echo "$matches" | jq 'length')

    if [[ "$match_count" -eq 0 ]]; then
        log_error "No operator found matching '$search_name'"
        if [[ -n "$search_version" ]]; then
            log_error "  (with version filter: $search_version)"
        fi
        echo ""
        log_info "Available operators:"
        list_operators
        exit 1
    fi

    if [[ "$match_count" -gt 1 ]]; then
        log_error "Multiple operators match '$search_name'. Be more specific:"
        echo ""
        printf "  %-50s %-35s %-12s\n" "OPERATOR" "NAMESPACE" "VERSION"
        printf "  %-50s %-35s %-12s\n" "--------" "---------" "-------"
        echo "$matches" | jq -r '.[] | [.csv_name, .namespace, .version] | @tsv' | while IFS=$'\t' read -r name ns version; do
            printf "  %-50s %-35s %-12s\n" "$name" "$ns" "$version"
        done
        echo ""
        exit 1
    fi

    OPERATOR_CSV_NAME=$(echo "$matches" | jq -r '.[0].csv_name')
    OPERATOR_NAMESPACE=$(echo "$matches" | jq -r '.[0].namespace')
    OPERATOR_DISPLAY_NAME=$(echo "$matches" | jq -r '.[0].display')
    # shellcheck disable=SC2034
    OPERATOR_VERSION=$(echo "$matches" | jq -r '.[0].version')

    log_success "Found: $OPERATOR_DISPLAY_NAME ($OPERATOR_CSV_NAME) in namespace '$OPERATOR_NAMESPACE'"
}

discover_all_operators() {
    local csv_json
    csv_json=$(oc get csv -A -o json 2>/dev/null)

    # shellcheck disable=SC2034
    ALL_OPERATORS_LIST=$(echo "$csv_json" | jq -r '
        [.items[]
        | select(.status.phase == "Succeeded")
        | {
            csv_name: .metadata.name,
            namespace: .metadata.namespace,
            display: (.spec.displayName // .metadata.name),
            version: (.spec.version // "unknown")
          }
        ]')
}

# ============================================================================
# NAMESPACE FILTER
# ============================================================================

build_ns_filter() {
    local operators_file="$1"
    local index="$2"
    yq -r "(.operators[$index].namespaces // [])
        | map(\".spec.sourceNamespace == \\\"\" + . + \"\\\"\")
        | join(\" or \")" "$operators_file"
}
