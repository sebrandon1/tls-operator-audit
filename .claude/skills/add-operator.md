---
name: add-operator
description: Add a new operator to the tracking list with Jira lookup and install config
allowed-tools: [Bash, Read, Edit, AskUserQuestion, mcp__mcp-atlassian__jira_search]
---

# Add Operator

Add a new operator to `operators.yaml` for TLS/ML-KEM compliance tracking.

## Step 1: Identify the Operator

Ask the user for the operator name (the OLM package name). If they give a display name, search for it:

```bash
oc get packagemanifest -n openshift-marketplace 2>/dev/null | grep -i "<name>"
```

## Step 2: Get Package Details

```bash
oc get packagemanifest <name> -n openshift-marketplace -o json | jq '{
  name: .metadata.name,
  catalog: .status.catalogSource,
  defaultChannel: .status.defaultChannel,
  channels: [.status.channels[] | {name: .name, version: .currentCSVDesc.version}],
  installModes: [.status.channels[0].currentCSVDesc.installModes[] | select(.supported) | .type]
}'
```

## Step 3: Determine Install Mode

Check the supported install modes from Step 2:
- If `AllNamespaces` is supported → no `install_namespace` needed (installs to `openshift-operators`)
- If only `OwnNamespace` or `SingleNamespace` → set `install_namespace` to the operator's conventional namespace

For the namespace, check if the operator creates one on install:
```bash
oc get packagemanifest <name> -n openshift-marketplace -o json | jq -r '.status.channels[0].currentCSVDesc.annotations["operatorframework.io/suggested-namespace"] // empty'
```

If no suggested namespace, use a reasonable default like `openshift-<name>`.

## Step 4: Find Jira Ticket

Search Jira for a PQC/TLS compliance epic for this operator:

```
project = CNF AND (summary ~ "<name>" OR summary ~ "<display-name>") AND (summary ~ "PQC" OR summary ~ "TLS" OR summary ~ "ML-KEM" OR summary ~ "Central TLS")
```

Also check OCPSTRAT project. If no ticket exists, use an empty string.

## Step 5: Determine Namespaces to Monitor

The `namespaces` list controls which TLS compliance reports are collected for this operator. Include:
- The install namespace (e.g., `openshift-operators` or the custom namespace)
- Any additional namespaces the operator creates for its workloads

Check the operator's CSV for related namespaces:
```bash
oc get packagemanifest <name> -n openshift-marketplace -o json | jq -r '.status.channels[0].currentCSVDesc.annotations["olm.targetNamespaces"] // empty'
```

## Step 6: Add to operators.yaml

Append the new entry to `operators.yaml` following the existing format:

```yaml
  - name: <package-name>
    jira: <JIRA-ID>
    project: <display-name>
    catalog: <catalog-source>
    channel: <channel>
    install_namespace: <namespace>  # only if OwnNamespace mode required
    namespaces:
      - <namespace1>
      - <namespace2>
```

## Step 7: Generate Operator Page Stub

```bash
cat > docs/operators/<name>.md <<EOF
---
layout: operator
operator: <name>
title: "<name>"
---
EOF
```

## Step 8: Verify

Run a targeted scan and export:

```bash
bash scan-and-export.sh --kubeconfig <path> --only <name>
```

Then commit the dashboard data files listed in `/scan-operators`.
