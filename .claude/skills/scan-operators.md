---
name: scan-operators
description: Run TLS compliance scans against all operators on an OCP cluster and export dashboard data
allowed-tools: [Bash, AskUserQuestion, Read]
---

# Scan Operators

Full pipeline: scan, export dashboard, check index versions.

## Run

Determine the kubeconfig path (check `$KUBECONFIG`, then `~/Downloads/*kubeconfig*`, then ask). Then:

```bash
bash scan-and-export.sh --kubeconfig <path>
```

Use `--only <name>` for a single operator, `--skip-scan` to re-export without scanning, `--verbose` for debug output.

## After

If the script reports changed data files, commit and push:

```bash
git add docs/_data/scan-results.json docs/_data/scan-history.json docs/_data/index-versions.json docs/badges/mlkem.json docs/operators/*.md
```

Commit with a message summarizing results (operator count, ML-KEM %, cluster, OCP version). Push directly to main — data-only updates don't need a PR.

## Troubleshooting

If the tls-compliance-operator is not running, the script will error. Install it:
```bash
kubectl --kubeconfig <path> apply -f https://github.com/sebrandon1/tls-compliance-operator/releases/latest/download/install.yaml
```

If operators fail to install (CSV timeout), check for orphaned Failed CSVs blocking OLM:
```bash
oc get csv -n openshift-operators -o json | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name'
```
Delete them and retry with `--only <name>`.
