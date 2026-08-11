---
name: check-versions
description: Check catalog indexes for new operator versions and update the tracker
allowed-tools: [Bash, Read]
---

# Check Index Versions

Quick check of catalog indexes for new operator versions.

## Run

```bash
bash check-index-versions.sh --kubeconfig <path> --verbose
```

Determine kubeconfig from `$KUBECONFIG`, `~/Downloads/*kubeconfig*`, or ask.

## After

If versions changed, commit and push:
```bash
git add docs/_data/index-versions.json && git commit -m "Update index versions" && git push
```

If operators show "UPDATE AVAILABLE", suggest running `/scan-operators` to re-scan.
