# tls-operator-audit

[![ML-KEM Compliance](https://img.shields.io/endpoint?url=https%3A%2F%2Fsebrandon1.github.io%2Ftls-operator-audit%2Fbadges%2Fmlkem.json)](https://sebrandon1.github.io/tls-operator-audit/)

Audit OpenShift operators for ML-KEM/PQC TLS compliance using the [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator).

Operators in `operators.yaml` are scanned for ML-KEM on their TLS endpoints. Results feed the [dashboard](https://sebrandon1.github.io/tls-operator-audit/). Tracked under [OCPSTRAT-3491](https://redhat.atlassian.net/browse/OCPSTRAT-3491) / [OCPSTRAT-3303](https://redhat.atlassian.net/browse/OCPSTRAT-3303).

## Quick start

```bash
./scan-and-export.sh --kubeconfig ~/kubeconfig
```

Scans every listed operator, exports dashboard data, and checks catalog index versions. Operators are left installed (`--skip-teardown` is the default).

```bash
# One operator
./scan-and-export.sh --kubeconfig ~/kubeconfig --only rhacs-operator

# Preview without changing the cluster or dashboard
./scan-and-export.sh --kubeconfig ~/kubeconfig --dry-run

# Rebuild dashboard data from existing results/
./scan-and-export.sh --kubeconfig ~/kubeconfig --skip-scan
```

Run any script with `--help` for the full flag list.

## Prerequisites

- `oc` with cluster-admin access
- `jq`, `yq` (v4+), and `bc`
- [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator) on the target cluster
- `curl` when using `--update-jira`

## Scripts

| Script | Purpose |
| --- | --- |
| `scan-and-export.sh` | Full pipeline: scan, export dashboard, check index versions |
| `tls-test-all.sh` | Install / scan / tear down each operator (teardown is the default) |
| `tls-mlkem-report.sh` | Report from existing TLSComplianceReport CRs (no new scan) |
| `tls-audit.sh` | Scoped run-once scan Job for one operator (or `--list-operators`) |
| `compare-scans.sh` | Diff ML-KEM support between two `results/` runs |
| `export-dashboard.sh` | Build dashboard JSON, badge, and operator pages from `results/` |
| `check-index-versions.sh` | Compare scanned versions to catalog indexes |
| `dashboard-status.sh` | Local dashboard summary (no cluster needed) |

```bash
# Tear down after each operator
./tls-test-all.sh --kubeconfig ~/kubeconfig --only rhacs-operator

# Machine-readable summary (json, csv, or markdown)
./tls-test-all.sh --kubeconfig ~/kubeconfig --quiet --output-format json

# Diff two timestamped runs (exits 1 if any endpoint lost ML-KEM)
./compare-scans.sh 20260811-083813 20260817-152728

# Post a comment on each operator's Jira ticket
JIRA_TOKEN=... ./tls-test-all.sh --kubeconfig ~/kubeconfig --update-jira
```

`--update-jira` needs `JIRA_TOKEN` (Bearer) or `JIRA_EMAIL` + `JIRA_API_TOKEN` (Cloud Basic). Default `JIRA_BASE_URL` is `https://redhat.atlassian.net`. Combine with `--dry-run` to print comments without posting.

## Operator configuration

Operators live in `operators.yaml`:

- `name` — OLM package name (CSV / subscription match)
- `jira` — tracking issue (`--update-jira`)
- `project` — display name
- `catalog` / `channel` — OLM source (`null` if pre-installed)
- `namespaces` — namespaces to collect TLS reports from
- `install_namespace` — set for OwnNamespace operators (skips default `openshift-operators`)

When `install_namespace` is set, the runner creates the namespace, an OperatorGroup targeting it, and the subscription there:

```yaml
- name: sandboxed-containers-operator
  catalog: redhat-operators-v422
  channel: stable
  install_namespace: openshift-sandboxed-containers-operator
  namespaces:
    - openshift-sandboxed-containers-operator
```

## Output

Each run writes `results/<operator>/<YYYYMMDD-HHMMSS>/`:

- `report.json` — TLSComplianceReport CRs
- `report.md` — markdown table
- `report.xml` — JUnit XML
- `report.html` — HTML summary

Dashboard files are generated under `docs/` (`_data/`, `badges/`, `operators/`).

## Tests

```bash
bash tests/run_tests.sh
```

## Related

- [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator) — TLS endpoint scanner
- [OCPSTRAT-3491](https://redhat.atlassian.net/browse/OCPSTRAT-3491) — PQC ML-KEM Testing for Telco Operators
- [OCPSTRAT-3303](https://redhat.atlassian.net/browse/OCPSTRAT-3303) — PQC ML-KEM Testing - OCP Platform Agnostic & Rolling Streams Operators
- [CNF-25677](https://redhat.atlassian.net/browse/CNF-25677) — Central TLS Profile Consistency - CurvePreference in 5.1
