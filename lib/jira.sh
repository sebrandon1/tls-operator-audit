#!/bin/bash

# ============================================================================
# JIRA SCAN RESULT COMMENTS
# ============================================================================

JIRA_BASE_URL="${JIRA_BASE_URL:-https://redhat.atlassian.net}"
DASHBOARD_BASE_URL="${DASHBOARD_BASE_URL:-https://sebrandon1.github.io/tls-operator-audit}"
JIRA_COMMENT_DELAY="${JIRA_COMMENT_DELAY:-1}"

jira_credentials_configured() {
    if [[ -n "${JIRA_TOKEN:-}" ]]; then
        return 0
    fi
    if [[ -n "${JIRA_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then
        return 0
    fi
    return 1
}

require_jira_credentials() {
    if ! jira_credentials_configured; then
        log_error "--update-jira requires JIRA_TOKEN, or JIRA_EMAIL and JIRA_API_TOKEN"
        exit 1
    fi
}

jira_auth_header() {
    if [[ -n "${JIRA_TOKEN:-}" ]]; then
        printf 'Authorization: Bearer %s' "$JIRA_TOKEN"
        return
    fi
    local encoded
    encoded=$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_API_TOKEN" | base64 | tr -d '\n')
    printf 'Authorization: Basic %s' "$encoded"
}

build_jira_comment_body() {
    local operator_name="$1"
    local version="$2"
    local status="$3"
    local total="$4"
    local mlkem="$5"
    local scan_time="$6"
    local ocp="$7"
    local tco="$8"
    local dashboard_url="${DASHBOARD_BASE_URL}/operators/${operator_name}.html"

    cat <<EOF
h3. ${operator_name} TLS/ML-KEM scan results

||Field||Value||
|Status|${status}|
|Operator version|${version}|
|Endpoints (total / ML-KEM)|${total} / ${mlkem}|
|Scan time|${scan_time}|
|OCP version|${ocp}|
|tls-compliance-operator|${tco}|
|Dashboard|[${operator_name}|${dashboard_url}]|

----
_Automated by tls-operator-audit_
EOF
}

# POST a Jira comment. Override in tests.
# Args: url payload response_file
# Prints: HTTP status code
jira_http_post() {
    local url="$1"
    local payload="$2"
    local resp_file="$3"

    curl -sS -o "$resp_file" -w "%{http_code}" \
        -X POST "$url" \
        -H "$(jira_auth_header)" \
        -H "Content-Type: application/json" \
        -d "$payload"
}

# Post scan results as a Jira comment. Empty key → skip. HTTP errors → warn, do not fail.
# Args: issue_key operator_name version status total mlkem [scan_time ocp tco]
post_result_to_jira() {
    local issue_key="$1"
    local operator_name="$2"
    local version="${3:-}"
    local status="${4:-}"
    local total="${5:-}"
    local mlkem="${6:-}"
    local scan_time="${7:-}"
    local ocp="${8:-}"
    local tco="${9:-}"

    if [[ -z "$issue_key" || "$issue_key" == "null" ]]; then
        log_debug "No Jira key for $operator_name, skipping comment"
        return 0
    fi

    if [[ -z "$scan_time" ]]; then
        scan_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    fi

    local body
    body=$(build_jira_comment_body "$operator_name" "$version" "$status" "$total" "$mlkem" "$scan_time" "$ocp" "$tco")

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo ""
        echo "[DRY RUN] Would comment on ${issue_key}:"
        echo "$body"
        echo ""
        return 0
    fi

    local payload url resp_file http_code
    payload=$(jq -nc --arg body "$body" '{body: $body}')
    url="${JIRA_BASE_URL%/}/rest/api/2/issue/${issue_key}/comment"
    resp_file=$(mktemp)

    http_code=$(jira_http_post "$url" "$payload" "$resp_file") || {
        log_warn "Failed to post Jira comment to ${issue_key}"
        rm -f "$resp_file"
        return 0
    }

    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        log_warn "Jira comment on ${issue_key} failed (HTTP ${http_code})"
        rm -f "$resp_file"
        return 0
    fi

    rm -f "$resp_file"
    log_success "Posted scan results to ${issue_key}"

    if [[ "${JIRA_COMMENT_DELAY}" != "0" ]]; then
        sleep "$JIRA_COMMENT_DELAY"
    fi
}
