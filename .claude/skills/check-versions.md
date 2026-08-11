---
name: check-versions
description: Check catalog indexes for new operator versions and update the tracker
allowed-tools: [Bash, Read]
---

# Check Index Versions

Quick check of catalog indexes for new operator versions. Compares index versions against last-scanned versions and updates the tracker JSON.

## Prerequisites

Determine the kubeconfig path. Check `$KUBECONFIG`, then `~/Downloads/*kubeconfig*`, then ask.

## Run

```bash
bash check-index-versions.sh --kubeconfig <path> --verbose
```

## After

If any operators show "UPDATE AVAILABLE":
1. List which operators have updates and the version delta
2. Suggest running `/scan-operators` to re-scan with the new versions

Commit and push the updated tracker if versions changed:

```bash
git add docs/_data/index-versions.json
git commit -m "Update index versions: <summary of changes>"
git push
```

If no changes, report that all operators are at the latest index versions and skip the commit.
