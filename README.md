# tls-operator-audit

Audit OCP operators for TLS compliance using the [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator).

Discovers operators via cluster CSVs, deploys a scoped run-once scan Job, and produces structured results in JSON, Markdown, and JUnit formats.

## Prerequisites

- `oc` CLI authenticated to an OpenShift cluster
- `jq` for JSON processing
- `tls-compliance-operator` deployed on the target cluster

## Usage

```bash
# Audit a specific operator
./tls-audit.sh --operator cert-manager-operator --kubeconfig ~/kubeconfig

# List all available operators
./tls-audit.sh --list-operators --kubeconfig ~/kubeconfig

# Audit with version filter
./tls-audit.sh --operator cert-manager --version 1.15.0 --kubeconfig ~/kubeconfig

# Audit every operator on the cluster
./tls-audit.sh --all-operators --kubeconfig ~/kubeconfig
```

## Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--kubeconfig <path>` | Yes | Path to kubeconfig file |
| `--operator <name>` | Yes* | Operator name (fuzzy match against CSVs) |
| `--version <ver>` | No | Filter CSV match by version |
| `--list-operators` | No | List all Succeeded CSVs and exit |
| `--all-operators` | No | Scan every operator, one by one |
| `--output-dir <dir>` | No | Results directory (default: `results`) |
| `--keep-reports` | No | Don't delete TLSComplianceReport CRs after scan |

\* Required unless `--list-operators` or `--all-operators` is used.

## How It Works

1. **Precheck** — Finds the tls-compliance-operator Deployment on the cluster and extracts its container image
2. **Discover** — Queries CSVs to resolve the target operator's namespace (fuzzy matching on name and display name)
3. **Scan** — Deploys a run-once Job scoped to the operator's namespace using `--include-namespaces`
4. **Collect** — Copies JSON results from the Job pod, generates Markdown and JUnit reports
5. **Cleanup** — Removes the Job, RBAC, scan namespace, and optionally TLSComplianceReport CRs

## Output

Results are saved to `results/<operator-name>/<timestamp>/`:

- `report.json` — Full scan results
- `report.md` — Markdown summary table
- `report.xml` — JUnit XML for CI integration

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All endpoints compliant |
| 1 | Non-compliant endpoints found |
| 2 | Scan error |

## Related

- [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator)
- [CNF-25677](https://redhat.atlassian.net/browse/CNF-25677) — Central TLS Profile Consistency
- [OCPSTRAT-3491](https://redhat.atlassian.net/browse/OCPSTRAT-3491) — PQC ML-KEM Testing for Telco Operators
