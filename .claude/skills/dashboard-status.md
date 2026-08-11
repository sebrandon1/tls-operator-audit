---
name: dashboard-status
description: Quick summary of current dashboard state - scan freshness, compliance, version drift
allowed-tools: [Bash, Read]
---

# Dashboard Status

Quick read-only summary of the current dashboard state without running any scans.

## Run

Read the data files and report:

```bash
# Scan results summary
jq '{
  scan_date: .scan_date,
  cluster: .cluster,
  ocp_version: .ocp_version,
  tco_version: .tco_version,
  total_operators: .summary.total_operators,
  pass: .summary.pass,
  partial: .summary.partial,
  none: .summary.none,
  error: .summary.error,
  mlkem_percent: .summary.mlkem_percent,
  mlkem_endpoints: "\(.summary.mlkem_endpoints)/\(.summary.total_endpoints)"
}' docs/_data/scan-results.json

# Per-operator status
jq -r '.operators[] | "\(.name)\t\(.version)\t\(.status)\t\(.mlkem_endpoints)/\(.reachable_endpoints)"' docs/_data/scan-results.json | column -t -s$'\t'

# Index version tracker
jq '{
  last_checked: .checked,
  updates_available: [.operators[] | select(.update_available)] | length,
  operators_with_updates: [.operators[] | select(.update_available) | .name]
}' docs/_data/index-versions.json

# Scan history count
jq 'length' docs/_data/scan-history.json
```

## Report

Present as a concise summary:
- **Scan age**: how old the last scan is (from scan_date)
- **ML-KEM compliance**: percentage and endpoint counts
- **Operator breakdown**: pass/partial/none/error counts
- **Version drift**: any operators with newer index versions
- **Scan history**: total number of historical scans
- **Dashboard link**: https://sebrandon1.github.io/tls-operator-audit/
