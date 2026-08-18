# tls-operator-audit

[![ML-KEM Compliance](https://img.shields.io/endpoint?url=https%3A%2F%2Fsebrandon1.github.io%2Ftls-operator-audit%2Fbadges%2Fmlkem.json)](https://sebrandon1.github.io/tls-operator-audit/)

Audit OCP operators for ML-KEM/PQC and TLS compliance using the [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator).

Installs each operator one at a time, scans its TLS endpoints for ML-KEM support, collects results, and tears down before moving to the next. Tracked under [OCPSTRAT-3491](https://redhat.atlassian.net/browse/OCPSTRAT-3491) / [OCPSTRAT-3303](https://redhat.atlassian.net/browse/OCPSTRAT-3303).

## Results

View the full interactive dashboard at **[sebrandon1.github.io/tls-operator-audit](https://sebrandon1.github.io/tls-operator-audit/)**.

The dashboard shows per-operator ML-KEM compliance status with drill-down into individual TLS endpoints, cipher suites, certificate details, and scan history.

## Prerequisites

- `oc` CLI with cluster-admin access
- `jq` for JSON processing
- `yq` for YAML processing (v4+)
- [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator) deployed on the target cluster

## Scripts

### `tls-test-all.sh` — Full test runner (install, scan, teardown)

Iterates through `operators.yaml`, installing each operator one at a time, waiting for the tls-compliance-operator to discover its endpoints, collecting ML-KEM results, then tearing down.

```bash
./tls-test-all.sh --kubeconfig ~/kubeconfig

# Test a single operator
./tls-test-all.sh --kubeconfig ~/kubeconfig --only rhacs-operator

# Keep operators installed after scanning
./tls-test-all.sh --kubeconfig ~/kubeconfig --skip-teardown

# Preview install/scan/teardown without changing the cluster
./tls-test-all.sh --kubeconfig ~/kubeconfig --dry-run

# Machine-readable consolidated summary (json, csv, or markdown)
./tls-test-all.sh --kubeconfig ~/kubeconfig --quiet --output-format json
```

### `tls-mlkem-report.sh` — Quick report from existing data

Queries existing TLSComplianceReport CRs on the cluster (no new scan). Useful for checking operators that are already installed.

```bash
./tls-mlkem-report.sh --kubeconfig ~/kubeconfig

# Report on all namespaces, not just listed operators
./tls-mlkem-report.sh --kubeconfig ~/kubeconfig --all-namespaces

# Machine-readable consolidated summary
./tls-mlkem-report.sh --kubeconfig ~/kubeconfig --output-format csv
```

### `tls-audit.sh` — Single operator scan via run-once Job

Deploys a scoped run-once scan Job for a specific operator. Produces JSON, Markdown, and JUnit reports.

```bash
./tls-audit.sh --operator cert-manager-operator --kubeconfig ~/kubeconfig
./tls-audit.sh --list-operators --kubeconfig ~/kubeconfig
```

### `export-dashboard.sh` — Generate dashboard data from local results

Reads the `results/` directory and generates the JSON data files, badge, and operator pages for the GitHub Pages dashboard.

```bash
./export-dashboard.sh --cluster cnfdt16 --ocp-version 5.0
```

## Operator Configuration

Target operators are defined in `operators.yaml`. Each operator entry supports:

- `name`: Operator name (used to match CSV and subscription)
- `catalog`: OLM catalog source (e.g., `redhat-operators`)
- `channel`: OLM subscription channel
- `namespaces`: List of namespaces to scan for TLS endpoints
- `install_namespace`: (Optional) Namespace to install into for OwnNamespace mode operators

### OperatorGroup-Scoped Installations

Some operators require **OwnNamespace** install mode and cannot be installed in the default `openshift-operators` namespace. For these operators, specify `install_namespace` to:

1. Create a dedicated namespace
2. Create an OperatorGroup with `targetNamespaces: [namespace]`
3. Install the subscription in that namespace

Example:
```yaml
- name: sandboxed-containers-operator
  catalog: redhat-operators
  channel: stable
  install_namespace: openshift-sandboxed-containers-operator
  namespaces:
    - openshift-sandboxed-containers-operator
```

This is handled automatically by `tls-test-all.sh` during installation.

## Output

Results are saved to `results/<operator-name>/<timestamp>/`:

- `report.json` — Full scan results (TLSComplianceReport CRs)
- `report.md` — Markdown summary table
- `report.xml` — JUnit XML for CI integration

## Related

- [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator) — The scanner that probes TLS endpoints
- [OCPSTRAT-3491](https://redhat.atlassian.net/browse/OCPSTRAT-3491) — PQC ML-KEM Testing for Telco Operators
- [OCPSTRAT-3303](https://redhat.atlassian.net/browse/OCPSTRAT-3303) — PQC ML-KEM Testing - Platform Agnostic & Rolling Streams
- [CNF-25677](https://redhat.atlassian.net/browse/CNF-25677) — Central TLS Profile Consistency - CurvePreference in 5.1
