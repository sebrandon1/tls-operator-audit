# CLAUDE.md

Scan OpenShift operators for ML-KEM/TLS compliance and publish the GitHub Pages dashboard.

Read [README.md](README.md) for humans. Agent workflows live in `.claude/skills/`. Do not invent flags — run `--help`.

## Commands

```bash
bash scan-and-export.sh --kubeconfig <path>                 # scan + export + index check
bash scan-and-export.sh --kubeconfig <path> --only <name>   # one operator from operators.yaml
bash scan-and-export.sh --kubeconfig <path> --dry-run       # no cluster or dashboard changes
bash scan-and-export.sh --kubeconfig <path> --skip-scan     # rebuild docs/ from results/
bash compare-scans.sh <YYYYMMDD-HHMMSS> <YYYYMMDD-HHMMSS>   # exit 1 if ML-KEM was lost
bash dashboard-status.sh                                    # local summary, no cluster
bash tests/run_tests.sh
```

`scan-and-export.sh` leaves operators installed. `tls-test-all.sh` tears them down unless `--skip-teardown`.

`--update-jira` needs `JIRA_TOKEN`, or `JIRA_EMAIL` + `JIRA_API_TOKEN`.

## Layout

| Path | What |
| --- | --- |
| `operators.yaml` | Operators to install and scan |
| `lib/` | Shared bash |
| `results/<operator>/<YYYYMMDD-HHMMSS>/` | `report.json`, `.md`, `.xml`, `.html` |
| `docs/` | Jekyll dashboard |

Dashboard: https://sebrandon1.github.io/tls-operator-audit/

Data-only dashboard files under `docs/` can go straight to `main`. Code changes go through a PR.
