#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/results.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== HTML report generation ==="

test_html_report_created() {
    cat > "$TMPDIR_TEST/report.json" <<'EOF'
[
  {
    "spec": {"host": "service.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady",
      "tlsVersions": {"tls12": true, "tls13": true},
      "overallCipherGrade": "A"
    }
  }
]
EOF

    generate_html "$TMPDIR_TEST/report.json" "$TMPDIR_TEST/report.html"

    if [[ -f "$TMPDIR_TEST/report.html" && -s "$TMPDIR_TEST/report.html" ]]; then
        echo "  PASS: HTML report file created"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: HTML report file not created"
        FAIL=$((FAIL + 1))
    fi
}

test_html_has_doctype() {
    assert_contains "HTML has DOCTYPE declaration" \
        "$(cat "$TMPDIR_TEST/report.html")" \
        "<!DOCTYPE html>"
}

test_html_has_title() {
    assert_contains "HTML has title" \
        "$(cat "$TMPDIR_TEST/report.html")" \
        "<title>TLS Compliance Audit Report</title>"
}

test_html_has_css_styling() {
    assert_contains "HTML has CSS styling" \
        "$(cat "$TMPDIR_TEST/report.html")" \
        "<style>"
}

test_html_has_summary_section() {
    assert_contains "HTML has summary section" \
        "$(cat "$TMPDIR_TEST/report.html")" \
        "summary"
}

test_html_has_endpoint_table() {
    local content
    content=$(cat "$TMPDIR_TEST/report.html")

    assert_contains "HTML has endpoint table" \
        "$content" \
        "<table>"

    assert_contains "HTML table has headers" \
        "$content" \
        "<th>Host</th>"
}

test_html_shows_mlkem_support() {
    assert_contains "HTML shows ML-KEM support" \
        "$(cat "$TMPDIR_TEST/report.html")" \
        "ML-KEM"
}

test_html_shows_compliance_badge() {
    assert_contains "HTML shows compliance badge" \
        "$(cat "$TMPDIR_TEST/report.html")" \
        "badge"
}

test_html_expiry_warnings() {
    cat > "$TMPDIR_TEST/report2.json" <<'EOF'
[
  {
    "spec": {"host": "expiring.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "daysUntilExpiry": 5,
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady"
    }
  }
]
EOF

    generate_html "$TMPDIR_TEST/report2.json" "$TMPDIR_TEST/report2.html"

    assert_contains "HTML shows expiry warning" \
        "$(cat "$TMPDIR_TEST/report2.html")" \
        "Expiring"
}

test_html_multiple_endpoints() {
    cat > "$TMPDIR_TEST/report3.json" <<'EOF'
[
  {
    "spec": {"host": "service1.example.com", "port": 443, "sourceNamespace": "ns1"},
    "status": {"complianceStatus": "Compliant", "mlkemSupported": true}
  },
  {
    "spec": {"host": "service2.example.com", "port": 8443, "sourceNamespace": "ns2"},
    "status": {"complianceStatus": "NonCompliant", "mlkemSupported": false}
  }
]
EOF

    generate_html "$TMPDIR_TEST/report3.json" "$TMPDIR_TEST/report3.html"

    local content
    content=$(cat "$TMPDIR_TEST/report3.html")

    assert_contains "HTML shows first endpoint" \
        "$content" \
        "service1.example.com"

    assert_contains "HTML shows second endpoint" \
        "$content" \
        "service2.example.com"
}

test_generate_reports_creates_html() {
    cat > "$TMPDIR_TEST/report4.json" <<'EOF'
[
  {
    "spec": {"host": "test.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {"complianceStatus": "Compliant"}
  }
]
EOF

    generate_reports "$TMPDIR_TEST"

    if [[ -f "$TMPDIR_TEST/report.html" && -s "$TMPDIR_TEST/report.html" ]]; then
        echo "  PASS: generate_reports creates HTML file"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: generate_reports should create HTML file"
        FAIL=$((FAIL + 1))
    fi
}

# Run all tests
test_html_report_created
test_html_has_doctype
test_html_has_title
test_html_has_css_styling
test_html_has_summary_section
test_html_has_endpoint_table
test_html_shows_mlkem_support
test_html_shows_compliance_badge
test_html_expiry_warnings
test_html_multiple_endpoints
test_generate_reports_creates_html

print_test_summary
