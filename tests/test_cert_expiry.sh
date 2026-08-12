#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$REPO_DIR/lib/common.sh"
source "$REPO_DIR/lib/results.sh"

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

echo "=== Certificate expiry warnings ==="

test_markdown_includes_expiry_section() {
    cat > "$TMPDIR_TEST/report.json" <<'EOF'
[
  {
    "spec": {"host": "service1.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "daysUntilExpiry": 5,
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady",
      "tlsVersions": {"tls12": true, "tls13": true},
      "overallCipherGrade": "A"
    }
  },
  {
    "spec": {"host": "service2.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "daysUntilExpiry": 25,
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady",
      "tlsVersions": {"tls12": true, "tls13": true},
      "overallCipherGrade": "A"
    }
  },
  {
    "spec": {"host": "service3.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "daysUntilExpiry": null,
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady",
      "tlsVersions": {"tls12": true, "tls13": true},
      "overallCipherGrade": "A"
    }
  }
]
EOF

    generate_markdown "$TMPDIR_TEST/report.json" "$TMPDIR_TEST/report.md"

    assert_contains "Markdown includes expiry warnings section" \
        "$(cat "$TMPDIR_TEST/report.md")" \
        "Certificate Expiry Warnings"
}

test_markdown_shows_critical_cert() {
    cat > "$TMPDIR_TEST/report2.json" <<'EOF'
[
  {
    "spec": {"host": "critical.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "daysUntilExpiry": 3,
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady"
    }
  }
]
EOF

    generate_markdown "$TMPDIR_TEST/report2.json" "$TMPDIR_TEST/report2.md"

    assert_contains "Markdown shows critical cert" \
        "$(cat "$TMPDIR_TEST/report2.md")" \
        "Critical"

    assert_contains "Markdown shows days until expiry" \
        "$(cat "$TMPDIR_TEST/report2.md")" \
        "3"
}

test_markdown_no_warnings_for_valid_certs() {
    cat > "$TMPDIR_TEST/report3.json" <<'EOF'
[
  {
    "spec": {"host": "service.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {
      "complianceStatus": "Compliant",
      "daysUntilExpiry": 365,
      "mlkemSupported": true,
      "pqcReadiness": "PQCReady"
    }
  }
]
EOF

    generate_markdown "$TMPDIR_TEST/report3.json" "$TMPDIR_TEST/report3.md"

    local content
    content=$(cat "$TMPDIR_TEST/report3.md")

    if echo "$content" | grep -q "Certificate Expiry Warnings"; then
        echo "  FAIL: Markdown should not show warnings for certs expiring > 30 days"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: Markdown shows no warnings for valid certs"
        PASS=$((PASS + 1))
    fi
}

test_tls_test_all_checks_expiry() {
    local tls_test_all="$REPO_DIR/tls-test-all.sh"

    assert_contains "tls-test-all.sh checks for expiring certificates" \
        "$(cat "$tls_test_all")" \
        "daysUntilExpiry"
}

test_expiry_warnings_sorted_by_days() {
    cat > "$TMPDIR_TEST/report4.json" <<'EOF'
[
  {
    "spec": {"host": "service1.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {"complianceStatus": "Compliant", "daysUntilExpiry": 25}
  },
  {
    "spec": {"host": "service2.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {"complianceStatus": "Compliant", "daysUntilExpiry": 5}
  },
  {
    "spec": {"host": "service3.example.com", "port": 443, "sourceNamespace": "default"},
    "status": {"complianceStatus": "Compliant", "daysUntilExpiry": 15}
  }
]
EOF

    generate_markdown "$TMPDIR_TEST/report4.json" "$TMPDIR_TEST/report4.md"

    local content service2_line service3_line
    content=$(cat "$TMPDIR_TEST/report4.md")
    service2_line=$(echo "$content" | grep -n "service2.example.com" | head -1 | cut -d: -f1)
    service3_line=$(echo "$content" | grep -n "service3.example.com" | head -1 | cut -d: -f1)

    if [[ -n "$service2_line" && -n "$service3_line" && "$service2_line" -lt "$service3_line" ]]; then
        echo "  PASS: Expiry warnings sorted by days (most urgent first)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Expiry warnings should be sorted by days"
        echo "    service2 line: $service2_line"
        echo "    service3 line: $service3_line"
        FAIL=$((FAIL + 1))
    fi
}

# Run all tests
test_markdown_includes_expiry_section
test_markdown_shows_critical_cert
test_markdown_no_warnings_for_valid_certs
test_tls_test_all_checks_expiry
test_expiry_warnings_sorted_by_days

print_test_summary
