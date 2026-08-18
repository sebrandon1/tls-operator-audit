#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

export JIRA_COMMENT_DELAY=0
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/jira.sh"

TLS_TEST_ALL="$REPO_DIR/tls-test-all.sh"
SCAN_AND_EXPORT="$REPO_DIR/scan-and-export.sh"
POST_LOG=$(mktemp)
trap 'rm -f "$POST_LOG"' EXIT

echo "=== Jira auto-comment ==="

test_scripts_document_flag() {
    assert_contains "tls-test-all.sh usage documents --update-jira" \
        "$(cat "$TLS_TEST_ALL")" \
        "--update-jira"

    assert_contains "scan-and-export.sh forwards --update-jira" \
        "$(cat "$SCAN_AND_EXPORT")" \
        'scan_args+=(--update-jira)'
}

test_help_mentions_update_jira() {
    local output
    output=$(bash "$TLS_TEST_ALL" --help)
    assert_contains "help mentions --update-jira" "$output" "--update-jira"
}

test_comment_body_contents() {
    local body
    body=$(build_jira_comment_body "rhacs-operator" "1.2.3" "PASS" "10" "10" \
        "2026-08-18T12:00:00Z" "4.22" "v1.1.9")
    assert_contains "comment includes operator name" "$body" "rhacs-operator"
    assert_contains "comment includes status" "$body" "PASS"
    assert_contains "comment includes endpoint counts" "$body" "10 / 10"
    assert_contains "comment links to dashboard operator page" "$body" \
        "https://sebrandon1.github.io/tls-operator-audit/operators/rhacs-operator.html"
    assert_not_contains "comment does not link to issues.redhat.com" "$body" "issues.redhat.com"
}

test_skip_empty_key() {
    : > "$POST_LOG"
    jira_http_post() {
        echo "CALLED" >> "$POST_LOG"
        printf '201'
    }
    post_result_to_jira "" "rhacs-operator" "1.0" "PASS" "1" "1" >/dev/null
    post_result_to_jira "null" "rhacs-operator" "1.0" "PASS" "1" "1" >/dev/null
    local content
    content=$(cat "$POST_LOG")
    assert_not_contains "empty key does not POST" "$content" "CALLED"
    assert_not_contains "null key does not POST" "$content" "CALLED"
}

test_dry_run_does_not_post() {
    : > "$POST_LOG"
    jira_http_post() {
        echo "CALLED" >> "$POST_LOG"
        printf '201'
    }
    local output
    DRY_RUN=true
    output=$(post_result_to_jira "CNF-25677" "cert-manager-operator" "1.16" "PASS" "4" "4")
    DRY_RUN=false
    assert_contains "dry-run prints the issue key" "$output" "CNF-25677"
    assert_contains "dry-run prints the comment" "$output" "cert-manager-operator"
    local content
    content=$(cat "$POST_LOG")
    assert_not_contains "dry-run does not call jira_http_post" "$content" "CALLED"
}

test_post_payload_and_url() {
    : > "$POST_LOG"
    jira_http_post() {
        printf '%s\n' "$1" >> "$POST_LOG"
        printf '%s\n' "$2" >> "$POST_LOG"
        printf '201'
    }
    export JIRA_TOKEN="test-token"
    export JIRA_BASE_URL="https://redhat.atlassian.net"
    post_result_to_jira "CNF-25677" "cert-manager-operator" "1.16" "PARTIAL" "8" "4" \
        "2026-08-18T12:00:00Z" "4.22" "v1.1.9" >/dev/null
    unset JIRA_TOKEN

    local content payload
    content=$(cat "$POST_LOG")
    assert_contains "POST URL uses Cloud REST API v2" "$content" \
        "https://redhat.atlassian.net/rest/api/2/issue/CNF-25677/comment"
    payload=$(sed -n '2p' "$POST_LOG")
    echo "$payload" | jq -e '.body | test("PARTIAL")' >/dev/null
    assert_eq "payload body includes status" "0" "$?"
}

test_http_error_does_not_fail() {
    jira_http_post() {
        printf '500'
    }
    local exit_code=0
    post_result_to_jira "CNF-1" "op" "1" "FAIL" "1" "0" >/dev/null || exit_code=$?
    assert_exit_code "HTTP 500 does not fail the scan" "0" "$exit_code"
}

test_missing_credentials() {
    local exit_code=0
    unset JIRA_TOKEN JIRA_EMAIL JIRA_API_TOKEN
    output=$(bash "$TLS_TEST_ALL" --update-jira 2>&1) || exit_code=$?
    assert_exit_code "tls-test-all.sh --update-jira fails without credentials" "1" "$exit_code"
    assert_contains "error mentions JIRA_TOKEN" "$output" "JIRA_TOKEN"
}

test_bearer_and_basic_auth_headers() {
    export JIRA_TOKEN="abc"
    local header
    header=$(jira_auth_header)
    assert_contains "Bearer header uses JIRA_TOKEN" "$header" "Bearer abc"
    unset JIRA_TOKEN

    export JIRA_EMAIL="user@example.com"
    export JIRA_API_TOKEN="tok"
    header=$(jira_auth_header)
    assert_contains "Basic header when email+token set" "$header" "Basic "
    unset JIRA_EMAIL JIRA_API_TOKEN
}

test_scripts_document_flag
test_help_mentions_update_jira
test_comment_body_contents
test_skip_empty_key
test_dry_run_does_not_post
test_post_payload_and_url
test_http_error_does_not_fail
test_missing_credentials
test_bearer_and_basic_auth_headers

print_test_summary
