---
name: dashboard-status
description: Quick summary of current dashboard state - scan freshness, compliance, version drift
allowed-tools: [Bash, Read]
---

# Dashboard Status

Read-only summary. No cluster access needed.

## Run

```bash
bash dashboard-status.sh
```

Report the output to the user. Highlight anything notable: scan age > 7 days, operators with updates available, or error-state operators.
