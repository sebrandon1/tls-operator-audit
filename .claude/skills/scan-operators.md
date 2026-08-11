---
name: scan-operators
description: Run TLS compliance scans against all operators on an OCP cluster and export dashboard data
allowed-tools: [Bash, AskUserQuestion, Read]
---

# Scan Operators

Run TLS/ML-KEM compliance scans against operators defined in `operators.yaml`, export results to the dashboard, check index versions, and commit the updated data.

## Prerequisites

1. Determine the kubeconfig path. Check `$KUBECONFIG`, then `~/Downloads/*kubeconfig*`, then ask.
2. Verify cluster connectivity: `oc --kubeconfig <path> whoami`
3. Verify tls-compliance-operator is running:
   ```bash
   oc --kubeconfig <path> get pods -n tls-compliance-operator-system
   ```
   If not running or crashlooping, install the latest release:
   ```bash
   gh release view --repo sebrandon1/tls-compliance-operator --json tagName -q .tagName
   kubectl --kubeconfig <path> apply -f https://github.com/sebrandon1/tls-compliance-operator/releases/latest/download/install.yaml
   ```

## Step 1: Check for Index Version Updates

Run the index version checker first to see if any operators have newer versions available:

```bash
bash check-index-versions.sh --kubeconfig <path>
```

If updates are available, inform the user and ask whether to proceed with scanning (the installed versions will be scanned regardless).

## Step 2: Gather Cluster Info

```bash
OCP_VERSION=$(oc --kubeconfig <path> version -o json | jq -r '.openshiftVersion // "unknown"')
TCO_IMAGE=$(oc --kubeconfig <path> get deploy -n tls-compliance-operator-system tls-compliance-operator-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}')
TCO_VERSION=$(echo "$TCO_IMAGE" | sed 's/.*://')
CLUSTER=$(oc --kubeconfig <path> whoami --show-server | sed 's|https://api\.||;s|\..*||')
```

Report: cluster name, OCP version, TCO version.

## Step 3: Run the Scan

```bash
bash tls-test-all.sh --kubeconfig <path> --skip-teardown
```

This installs (if needed), scans, and collects results for each operator. Pass `--skip-teardown` to leave operators installed for future scans. The scan takes 2-5 minutes per operator that needs installing, ~20 seconds per already-installed operator.

If specific operators fail to install (CSV timeout), check for:
- Orphaned Failed CSVs blocking OLM resolution: `oc get csv -n openshift-operators -o json | jq '.items[] | select(.status.phase == "Failed") | .metadata.name'`
- Delete them and retry the failed operator with `--only <name>`

## Step 4: Export Dashboard Data

```bash
bash export-dashboard.sh \
  --results-dir results \
  --cluster "$CLUSTER" \
  --ocp-version "$OCP_VERSION" \
  --tco-version "$TCO_VERSION" \
  --scan-mode all-operators \
  --scan-kubeconfig "<path>"
```

## Step 5: Update Index Version Tracker

```bash
bash check-index-versions.sh --kubeconfig <path>
```

## Step 6: Commit and Push

Stage the updated data files and commit:

```bash
git add docs/_data/scan-results.json docs/_data/scan-history.json docs/_data/index-versions.json docs/badges/mlkem.json docs/operators/*.md
```

Commit with a message summarizing the scan results (operator count, ML-KEM percentage, cluster, OCP version, TCO version).

Push to main (data-only updates don't need a PR).

## Step 7: Report Summary

Present the final results:
- Total operators scanned
- ML-KEM compliance percentage
- Any operators that failed to scan
- Any operators with newer index versions available
- Link to the dashboard: https://sebrandon1.github.io/tls-operator-audit/
