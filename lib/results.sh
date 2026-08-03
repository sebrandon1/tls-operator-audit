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
}

generate_markdown() {
    local json_file="$1"
    local md_file="$2"

    log_info "Generating Markdown report..."

    jq -r '
        "# TLS Compliance Audit Report\n",
        "| Host | Port | Namespace | Status | TLS 1.2 | TLS 1.3 | Cipher Grade | ML-KEM | PQC Readiness |",
        "|------|------|-----------|--------|---------|---------|--------------|--------|---------------|",
        ((.items // [])[] |
        "| \(.spec.host // "-") | \(.spec.port // "-") | \(.spec.sourceNamespace // "-") | \(.status.complianceStatus // "-") | \(.status.tlsVersions.tls12 // false) | \(.status.tlsVersions.tls13 // false) | \(.status.overallCipherGrade // "-") | \(.status.mlkemSupported // false) | \(.status.pqcReadiness // "-") |")
    ' "$json_file" > "$md_file" 2>/dev/null || {
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

cleanup_reports() {
    local namespace="$1"

    log_info "Cleaning up TLSComplianceReport CRs for namespace '$namespace'..."

    local report_names
    report_names=$(oc get tlscompliancereports -o json 2>/dev/null | \
        jq -r --arg ns "$namespace" '.items[] | select(.spec.sourceNamespace == $ns) | .metadata.name' 2>/dev/null || true)

    if [[ -z "$report_names" ]]; then
        log_debug "No TLSComplianceReport CRs found for namespace '$namespace'."
        return
    fi

    local count
    count=$(echo "$report_names" | wc -l | tr -d ' ')

    echo "$report_names" | xargs -r oc delete tlscompliancereport 2>/dev/null || true
    log_success "Deleted $count TLSComplianceReport CRs"
}
