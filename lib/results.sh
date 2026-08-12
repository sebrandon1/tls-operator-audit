#!/bin/bash

generate_reports() {
    local results_dir="$1"
    local json_file="${results_dir}/report.json"

    if [[ ! -f "$json_file" ]]; then
        log_warn "No JSON report found, skipping additional format generation."
        return
    fi

    generate_markdown "$json_file" "${results_dir}/report.md"
    generate_junit "$json_file" "${results_dir}/report.xml"
    generate_html "$json_file" "${results_dir}/report.html"
}

generate_markdown() {
    local json_file="$1"
    local md_file="$2"

    log_info "Generating Markdown report..."

    {
        jq -r --arg warning "${CERT_EXPIRY_WARNING_DAYS:-30}" --arg critical "${CERT_EXPIRY_CRITICAL_DAYS:-7}" '
            def items: if type == "object" and has("items") then .items else . end;
            "# TLS Compliance Audit Report\n",
            "| Host | Port | Namespace | Status | TLS 1.2 | TLS 1.3 | Cipher Grade | ML-KEM | PQC Readiness |",
            "|------|------|-----------|--------|---------|---------|--------------|--------|---------------|",
            (items[] |
            "| \(.spec.host // "-") | \(.spec.port // "-") | \(.spec.sourceNamespace // "-") | \(.status.complianceStatus // "-") | \(.status.tlsVersions.tls12 // false) | \(.status.tlsVersions.tls13 // false) | \(.status.overallCipherGrade // "-") | \(.status.mlkemSupported // false) | \(.status.pqcReadiness // "-") |"),
            (
                [items[] | select(.status.daysUntilExpiry != null and .status.daysUntilExpiry > 0 and .status.daysUntilExpiry <= ($warning | tonumber))]
                | sort_by(.status.daysUntilExpiry)
                | if length > 0 then
                    "\n## ⚠️ Certificate Expiry Warnings\n\n",
                    "| Host | Port | Days Until Expiry | Severity |",
                    "|------|------|-------------------|----------|",
                    (.[] | "| \(.spec.host) | \(.spec.port) | \(.status.daysUntilExpiry) | \(if .status.daysUntilExpiry <= ($critical | tonumber) then "🔴 Critical" else "🟡 Warning" end) |")
                  else empty end
            )
        ' "$json_file" 2>/dev/null
    } > "$md_file" 2>/dev/null || {
        jq -r '
            "# TLS Compliance Audit Report\n",
            "| Host | Port | Namespace | Status | Cipher Grade | ML-KEM | PQC Readiness |",
            "|------|------|-----------|--------|--------------|--------|---------------|",
            (.[] |
            "| \(.spec.host // "-") | \(.spec.port // "-") | \(.spec.sourceNamespace // "-") | \(.status.complianceStatus // "-") | \(.status.overallCipherGrade // "-") | \(.status.mlkemSupported // false) | \(.status.pqcReadiness // "-") |")
        ' "$json_file" > "$md_file" 2>/dev/null || {
            echo "# TLS Compliance Audit Report" > "$md_file"
            echo "" >> "$md_file"
            echo "Failed to parse JSON report." >> "$md_file"
        }
    }

    if [[ -s "$md_file" ]]; then
        log_success "Markdown report: ${md_file}"
    fi
}

generate_junit() {
    local json_file="$1"
    local xml_file="$2"

    log_info "Generating JUnit report..."

    jq -r '
        def items: if type == "object" and has("items") then .items else . end;
        def count_status(s): [items[] | select(.status.complianceStatus == s)] | length;
        def total: [items[]] | length;
        def mlkem_failures: [items[] | select(.status.mlkemSupported != true)] | length;

        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<testsuites>",
        "  <testsuite name=\"TLS Compliance\" tests=\"\(total)\" failures=\"\(count_status("NonCompliant") + count_status("NoTLS") + count_status("PlaintextHTTP"))\" errors=\"0\">",
        (items[] |
            "    <testcase name=\"\(.spec.host // "unknown"):\(.spec.port // "0") (\(.spec.sourceNamespace // "unknown"))\" classname=\"tls-compliance\">" +
            "\n      <properties><property name=\"mlkemSupported\" value=\"\(.status.mlkemSupported // false)\"/><property name=\"pqcReadiness\" value=\"\(.status.pqcReadiness // "Unknown")\"/></properties>" +
            (if .status.complianceStatus == "NonCompliant" or .status.complianceStatus == "NoTLS" or .status.complianceStatus == "PlaintextHTTP" then
                "\n      <failure message=\"\(.status.complianceStatus)\">\(.status.complianceStatus): \(.spec.host // "unknown"):\(.spec.port // "0")</failure>"
            else "" end) +
            "\n    </testcase>"
        ),
        "  </testsuite>",
        "  <testsuite name=\"ML-KEM PQC Compliance\" tests=\"\(total)\" failures=\"\(mlkem_failures)\" errors=\"0\">",
        (items[] |
            "    <testcase name=\"mlkem:\(.spec.host // "unknown"):\(.spec.port // "0") (\(.spec.sourceNamespace // "unknown"))\" classname=\"pqc-compliance\">" +
            (if .status.mlkemSupported != true then
                "\n      <failure message=\"ML-KEM not supported\">Endpoint \(.spec.host // "unknown"):\(.spec.port // "0") does not support ML-KEM (mlkemSupported=\(.status.mlkemSupported // false), pqcReadiness=\(.status.pqcReadiness // "Unknown"))</failure>"
            else "" end) +
            "\n    </testcase>"
        ),
        "  </testsuite>",
        "</testsuites>"
    ' "$json_file" > "$xml_file" 2>/dev/null || {
        cat > "$xml_file" <<XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="TLS Compliance Audit" tests="0" failures="0" errors="1">
    <testcase name="report-parse" classname="tls-compliance">
      <error message="Failed to parse JSON report"/>
    </testcase>
  </testsuite>
</testsuites>
XMLEOF
    }

    if [[ -s "$xml_file" ]]; then
        log_success "JUnit report: ${xml_file}"
    fi
}

generate_html() {
    local json_file="$1"
    local html_file="$2"

    log_info "Generating HTML report..."

    cat > "$html_file" << 'HTML_HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TLS Compliance Audit Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 2rem;
            color: #2d3748;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            text-align: center;
        }
        h1 { font-size: 2rem; margin-bottom: 0.5rem; }
        .timestamp { opacity: 0.9; font-size: 0.9rem; }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1.5rem;
            padding: 2rem;
            background: #f7fafc;
        }
        .stat-card {
            background: white;
            padding: 1.5rem;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        .stat-value {
            font-size: 2.5rem;
            font-weight: bold;
            margin-bottom: 0.5rem;
        }
        .stat-label {
            color: #718096;
            font-size: 0.875rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .stat-value.success { color: #38a169; }
        .stat-value.warning { color: #d69e2e; }
        .stat-value.danger { color: #e53e3e; }
        .stat-value.info { color: #3182ce; }
        .content { padding: 2rem; }
        h2 {
            font-size: 1.5rem;
            margin-bottom: 1.5rem;
            color: #2d3748;
            border-bottom: 2px solid #e2e8f0;
            padding-bottom: 0.5rem;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 2rem;
            font-size: 0.875rem;
        }
        th, td {
            padding: 0.75rem;
            text-align: left;
            border-bottom: 1px solid #e2e8f0;
        }
        th {
            background: #f7fafc;
            font-weight: 600;
            color: #4a5568;
            position: sticky;
            top: 0;
        }
        tr:hover { background: #f7fafc; }
        .badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 9999px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.025em;
        }
        .badge-success { background: #c6f6d5; color: #22543d; }
        .badge-warning { background: #fef5e7; color: #744210; }
        .badge-danger { background: #fed7d7; color: #742a2a; }
        .badge-info { background: #bee3f8; color: #2c5282; }
        .badge-gray { background: #e2e8f0; color: #4a5568; }
        .mlkem-true { color: #38a169; font-weight: 600; }
        .mlkem-false { color: #e53e3e; }
        .grade-a { background: #c6f6d5; color: #22543d; font-weight: 600; }
        .grade-b { background: #fef5e7; color: #744210; font-weight: 600; }
        .grade-c, .grade-d, .grade-f { background: #fed7d7; color: #742a2a; font-weight: 600; }
        .expiry-warning {
            background: #fef5e7;
            border-left: 4px solid #d69e2e;
            padding: 1.5rem;
            margin-bottom: 2rem;
            border-radius: 4px;
        }
        .expiry-critical {
            background: #fed7d7;
            border-left: 4px solid #e53e3e;
            padding: 1.5rem;
            margin-bottom: 2rem;
            border-radius: 4px;
        }
        .expiry-warning h3, .expiry-critical h3 {
            margin-bottom: 1rem;
            font-size: 1.125rem;
        }
        footer {
            text-align: center;
            padding: 1.5rem;
            background: #f7fafc;
            color: #718096;
            font-size: 0.875rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔒 TLS Compliance Audit Report</h1>
            <div class="timestamp">Generated: <script>document.write(new Date().toLocaleString())</script></div>
        </header>
HTML_HEADER

    jq -r --arg warning "${CERT_EXPIRY_WARNING_DAYS:-30}" --arg critical "${CERT_EXPIRY_CRITICAL_DAYS:-7}" '
        def items: if type == "object" and has("items") then .items else . end;

        items as $all_items |
        ($warning | tonumber) as $warn_days |
        ($critical | tonumber) as $crit_days |

        ($all_items | length) as $total |
        ([$all_items[] | select(.status.complianceStatus == "Compliant")] | length) as $compliant |
        ([$all_items[] | select(.status.mlkemSupported == true)] | length) as $mlkem |
        ([$all_items[] | select(.status.daysUntilExpiry != null and .status.daysUntilExpiry > 0 and .status.daysUntilExpiry <= $warn_days)] | sort_by(.status.daysUntilExpiry)) as $expiring |
        ([$expiring[] | select(.status.daysUntilExpiry <= $crit_days)]) as $expiring_critical |

        "        <div class=\"summary\">",
        "            <div class=\"stat-card\">",
        "                <div class=\"stat-value info\">\($total)</div>",
        "                <div class=\"stat-label\">Total Endpoints</div>",
        "            </div>",
        "            <div class=\"stat-card\">",
        "                <div class=\"stat-value success\">\($compliant)</div>",
        "                <div class=\"stat-label\">Compliant</div>",
        "            </div>",
        "            <div class=\"stat-card\">",
        "                <div class=\"stat-value \(if $mlkem > 0 then "success" else "warning" end)\">\($mlkem)</div>",
        "                <div class=\"stat-label\">ML-KEM Support</div>",
        "            </div>",
        "            <div class=\"stat-card\">",
        "                <div class=\"stat-value \(if ($expiring | length) > 0 then "danger" else "success" end)\">\($expiring | length)</div>",
        "                <div class=\"stat-label\">Expiring Certs</div>",
        "            </div>",
        "        </div>",

        (if ($expiring_critical | length) > 0 then
            "        <div class=\"content\">",
            "            <div class=\"expiry-critical\">",
            "                <h3>🔴 Critical: Certificates Expiring Within \($crit_days) Days</h3>",
            "                <ul>",
            ($expiring_critical[] | "                    <li><strong>\(.spec.host):\(.spec.port)</strong> - Expires in <strong>\(.status.daysUntilExpiry) days</strong></li>"),
            "                </ul>",
            "            </div>"
        elif ($expiring | length) > 0 then
            "        <div class=\"content\">",
            "            <div class=\"expiry-warning\">",
            "                <h3>⚠️ Certificates Expiring Within \($warn_days) Days</h3>",
            "                <ul>",
            ($expiring[] | "                    <li><strong>\(.spec.host):\(.spec.port)</strong> - Expires in <strong>\(.status.daysUntilExpiry) days</strong></li>"),
            "                </ul>",
            "            </div>"
        else
            "        <div class=\"content\">"
        end),

        "            <h2>Endpoint Details</h2>",
        "            <table>",
        "                <thead>",
        "                    <tr>",
        "                        <th>Host</th>",
        "                        <th>Port</th>",
        "                        <th>Namespace</th>",
        "                        <th>Status</th>",
        "                        <th>TLS 1.2</th>",
        "                        <th>TLS 1.3</th>",
        "                        <th>Grade</th>",
        "                        <th>ML-KEM</th>",
        "                        <th>PQC Ready</th>",
        "                    </tr>",
        "                </thead>",
        "                <tbody>",
        ($all_items[] |
            "                    <tr>",
            "                        <td>\(.spec.host // "unknown")</td>",
            "                        <td>\(.spec.port // "-")</td>",
            "                        <td>\(.spec.sourceNamespace // "unknown")</td>",
            "                        <td><span class=\"badge badge-\(
                if .status.complianceStatus == "Compliant" then "success"
                elif .status.complianceStatus == "Closed" or .status.complianceStatus == "Timeout" then "warning"
                elif .status.complianceStatus == "NonCompliant" or .status.complianceStatus == "NoTLS" then "danger"
                else "gray" end
            )\">\(.status.complianceStatus // "Unknown")</span></td>",
            "                        <td>\(if .status.tlsVersions.tls12 then "✓" else "✗" end)</td>",
            "                        <td>\(if .status.tlsVersions.tls13 then "✓" else "✗" end)</td>",
            "                        <td><span class=\"badge grade-\(.status.overallCipherGrade // "gray" | ascii_downcase)\">\(.status.overallCipherGrade // "-")</span></td>",
            "                        <td class=\"mlkem-\(.status.mlkemSupported // false)\">\(if .status.mlkemSupported then "✓ Yes" else "✗ No" end)</td>",
            "                        <td>\(.status.pqcReadiness // "Unknown")</td>",
            "                    </tr>"
        ),
        "                </tbody>",
        "            </table>",
        "        </div>",
        "        <footer>",
        "            Generated by tls-compliance-operator audit",
        "        </footer>",
        "    </div>",
        "</body>",
        "</html>"
    ' "$json_file" >> "$html_file" 2>/dev/null || {
        cat >> "$html_file" <<'HTML_ERROR'
        <div class="content">
            <div class="expiry-critical">
                <h3>Error</h3>
                <p>Failed to parse JSON report.</p>
            </div>
        </div>
        <footer>Generated by tls-compliance-operator audit</footer>
    </div>
</body>
</html>
HTML_ERROR
    }

    if [[ -s "$html_file" ]]; then
        log_success "HTML report: ${html_file}"
    fi
}

print_scan_summary() {
    local results_dir="$1"
    local operator_name="$2"
    local operator_namespace="$3"
    local exit_code="$4"
    local json_file="${results_dir}/report.json"

    local total=0 compliant=0 non_compliant=0 warning=0 other=0
    local rate="N/A"

    if [[ -f "$json_file" ]]; then
        local stats
        stats=$(jq '
            def items: if type == "object" and has("items") then .items else . end;
            {
                total: ([items[]] | length),
                compliant: ([items[] | select(.status.complianceStatus == "Compliant")] | length),
                non_compliant: ([items[] | select(.status.complianceStatus == "NonCompliant" or .status.complianceStatus == "NoTLS" or .status.complianceStatus == "PlaintextHTTP")] | length),
                warning: ([items[] | select(.status.complianceStatus == "Warning")] | length)
            }
        ' "$json_file" 2>/dev/null || echo '{"total":0,"compliant":0,"non_compliant":0,"warning":0}')

        total=$(echo "$stats" | jq '.total')
        compliant=$(echo "$stats" | jq '.compliant')
        non_compliant=$(echo "$stats" | jq '.non_compliant')
        warning=$(echo "$stats" | jq '.warning')
        other=$((total - compliant - non_compliant - warning))

        if [[ "$total" -gt 0 ]]; then
            rate=$(awk "BEGIN {printf \"%.1f%%\", ($compliant/$total)*100}")
        fi
    fi

    local exit_desc
    case "$exit_code" in
        0) exit_desc="${GREEN}0 (all endpoints compliant)${NC}" ;;
        1) exit_desc="${RED}1 (non-compliant endpoints found)${NC}" ;;
        2) exit_desc="${RED}2 (scan error)${NC}" ;;
        *) exit_desc="${YELLOW}${exit_code} (unknown)${NC}" ;;
    esac

    local rate_colored
    if [[ "$total" -gt 0 ]]; then
        local pct
        pct=$(awk "BEGIN {printf \"%d\", ($compliant/$total)*100}")
        if [[ "$pct" -eq 100 ]]; then
            rate_colored="${GREEN}${rate}${NC}"
        elif [[ "$pct" -ge 80 ]]; then
            rate_colored="${YELLOW}${rate}${NC}"
        else
            rate_colored="${RED}${rate}${NC}"
        fi
    else
        rate_colored="$rate"
    fi

    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  TLS COMPLIANCE AUDIT: ${operator_name}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    printf "  %-25s %s\n" "Namespace:" "$operator_namespace"
    printf "  %-25s %s\n" "Total Endpoints:" "$total"
    printf "  %-25s %s\n" "Compliant:" "$compliant"
    printf "  %-25s %s\n" "Non-Compliant:" "$non_compliant"
    if [[ "$warning" -gt 0 ]]; then
        printf "  %-25s %s\n" "Warning:" "$warning"
    fi
    if [[ "$other" -gt 0 ]]; then
        printf "  %-25s %s\n" "Other:" "$other"
    fi
    echo -e "  $(printf '%-25s' "Compliance Rate:") ${rate_colored}"
    printf "  %-25s %s\n" "Results:" "$results_dir/"
    echo -e "  $(printf '%-25s' "Exit Code:") ${exit_desc}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

