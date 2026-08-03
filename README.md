# tls-operator-audit

Audit OCP operators for ML-KEM/PQC and TLS compliance using the [tls-compliance-operator](https://github.com/sebrandon1/tls-compliance-operator).

Installs each operator one at a time, scans its TLS endpoints for ML-KEM support, collects results, and tears down before moving to the next. Tracked under [OCPSTRAT-3491](https://redhat.atlassian.net/browse/OCPSTRAT-3491) / [OCPSTRAT-3303](https://redhat.atlassian.net/browse/OCPSTRAT-3303).

## Results

Tested on OCP 5.0 cluster (cnfdt16) on 2026-08-03. Operators sourced from `redhat-operator-index:v5.0` and `redhat-operator-index:v4.22` (fallback for operators not yet in the 5.0 index).

| Operator | Jira | Source | Endpoints | ML-KEM | Status |
|----------|------|--------|-----------|--------|--------|
| cert-manager-operator | [CNF-25677](https://redhat.atlassian.net/browse/CNF-25677) | pre-installed | 3 reachable (1 Closed) | 3/3 | **PASS** |
| compliance-operator | [CMP-4503](https://redhat.atlassian.net/browse/CMP-4503) | pre-installed | 2 reachable (6 Closed) | 2/2 | **PASS** |
| openshift-pipelines-operator-rh | [SRVKP-11858](https://redhat.atlassian.net/browse/SRVKP-11858) | v5.0 | 1 | 1/1 | **PASS** |
| rhacs-operator | [ROX-33132](https://redhat.atlassian.net/browse/ROX-33132) | v5.0 | 1 | 1/1 | **PASS** |
| servicemeshoperator3 | [OSSM-13756](https://redhat.atlassian.net/browse/OSSM-13756) | v5.0 | 1 | 1/1 | **PASS** |
| skupper-operator | [CONNLINK-1122](https://redhat.atlassian.net/browse/CONNLINK-1122) | v5.0 | 2 | 2/2 | **PASS** |
| openshift-external-secrets-operator | [ESO-537](https://redhat.atlassian.net/browse/ESO-537) | v5.0 | 1 | 1/1 | **PASS** |
| file-integrity-operator | [CMP-4504](https://redhat.atlassian.net/browse/CMP-4504) | v4.22 | 0 | - | **NONE** |
| security-profiles-operator | [CMP-4505](https://redhat.atlassian.net/browse/CMP-4505) | v4.22 | 1 | 1/1 | **PASS** |
| openshift-gitops-operator | [GITOPS-10309](https://redhat.atlassian.net/browse/GITOPS-10309) | v4.22 | 4 reachable (3 stale) | 4/4 | **PASS** |
| rhods-operator | [RHOAIENG-72334](https://redhat.atlassian.net/browse/RHOAIENG-72334) | v4.18 only | 2 | 1/2 | **PARTIAL** |
| sandboxed-containers-operator | [KATA-5144](https://redhat.atlassian.net/browse/KATA-5144) | v4.22 | - | - | **ERROR** |
| trustee-operator | [TRUSTEE-80](https://redhat.atlassian.net/browse/TRUSTEE-80) | v4.22 | - | - | **ERROR** |
| openshift-zero-trust-workload-identity-manager | [SPIRE-568](https://redhat.atlassian.net/browse/SPIRE-568) | v4.22 | - | - | **ERROR** |

### Key Findings

- **10 PASS** — All reachable TLS endpoints offer ML-KEM key exchange
- **1 PARTIAL** — `rhods-operator` has a metrics endpoint (`redhat-ods-operator-controller-manager-metrics-service:8443`) serving PlaintextHTTP instead of TLS
- **1 NONE** — `file-integrity-operator` exposes no TLS-serving endpoints (controller only)
- **3 ERROR** — `sandboxed-containers-operator`, `trustee-operator`, and `openshift-zero-trust-workload-identity-manager` won't install on OCP 5.0 from either v4.22 or v4.18 catalog indexes (likely need native 5.0 builds)

### Notes

- "Closed" endpoints are services whose backing pods are not running (e.g., compliance-operator scan ResultServers that only exist during active scans). These are excluded from pass/fail evaluation.
- Operators installed via AllNamespaces mode run in `openshift-operators`. The test runner installs one operator at a time and cleans up between each to avoid cross-contamination.
- The v4.22 fallback catalog (`redhat-operators-v422`) was added as a separate CatalogSource to avoid overlapping with the v5.0 index.

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
```

### `tls-mlkem-report.sh` — Quick report from existing data

Queries existing TLSComplianceReport CRs on the cluster (no new scan). Useful for checking operators that are already installed.

```bash
./tls-mlkem-report.sh --kubeconfig ~/kubeconfig

# Report on all namespaces, not just listed operators
./tls-mlkem-report.sh --kubeconfig ~/kubeconfig --all-namespaces
```

### `tls-audit.sh` — Single operator scan via run-once Job

Deploys a scoped run-once scan Job for a specific operator. Produces JSON, Markdown, and JUnit reports.

```bash
./tls-audit.sh --operator cert-manager-operator --kubeconfig ~/kubeconfig
./tls-audit.sh --list-operators --kubeconfig ~/kubeconfig
```

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
