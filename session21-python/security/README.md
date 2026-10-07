# Security (DevSecOps) notes

Where each security control lives in this project and how to run it locally.

| Layer | Tool | Where it runs | Gate |
| --- | --- | --- | --- |
| Secret scanning | gitleaks | `.github/workflows/security.yml` → `secret-scan` | fails on any finding |
| SAST (source code) | Bandit | `security.yml` → `sast` | fails on medium/high severity (`-ll`) |
| SCA (dependencies) | pip-audit | `security.yml` → `sca` | fails on any known vulnerability |
| IaC / config | Trivy `config` | `security.yml` → `iac-scan` | report only (`exit-code: 0`) |
| Container images | Trivy `image` | `.github/workflows/ci-cd.yml` → `build-scan-push` | fails on fixable HIGH/CRITICAL, **before** `docker push` |
| Runtime | non-root backend user (UID 10001), resource limits, probes | `backend/Dockerfile`, Helm chart | n/a |

The image scan sits between `docker build` and `docker push`, so a vulnerable image never
reaches GHCR and the `deploy` job (which `needs: build-scan-push`) is skipped.

## Run the same checks locally

```bash
gitleaks detect --source . --verbose                    # secrets in the git history
bandit -r backend/app -ll                               # SAST
pip-audit -r backend/requirements.txt --strict          # SCA
trivy config --severity HIGH,CRITICAL .                 # Terraform / Dockerfile / K8s misconfigurations
docker build -t taskboard-backend:scan ./backend
trivy image --severity HIGH,CRITICAL --ignore-unfixed taskboard-backend:scan
```

## Findings and decisions

| Finding | Decision |
| --- | --- |
| `starlette 0.41.3` (pulled in by `fastapi==0.115.6`): CVE-2025-62727, CVE-2026-48818, CVE-2026-54283, all HIGH | Fixed: `fastapi==0.142.3` + `prometheus-fastapi-instrumentator==8.1.0` (resolves `starlette 1.7.0`). See `troubleshooting/fixes/security-deps-fixes.patch`. |
| `nginx:1.27-alpine` base image last rebuilt April 2025 | Fixed: move to the maintained `nginx:1.30-alpine` (same patch). |
| `pytest` is in `requirements.txt`, so it ships in the runtime image | Follow-up: split into `requirements-dev.txt`. |
| Frontend nginx master process runs as root | Follow-up: switch to `nginxinc/nginx-unprivileged` (listens on 8080). |
| PostgreSQL password is a plain Helm value (`postgres.password`) | OK for the classroom; for production use an external secret store (AWS Secrets Manager + External Secrets Operator) or RDS IAM auth. |
| Trivy `config` reports missing `securityContext` (readOnlyRootFilesystem, runAsNonRoot) on the chart | Accepted for the demo, gate left in report-only mode. |

## Rules I follow

- Never commit `.env`, `terraform.tfvars`, kubeconfigs or cloud keys (`.gitignore` covers them).
  If a secret is pushed: **rotate it first**, then remove it from the code. Deleting the file
  does not remove it from git history.
- CI uses the short-lived `GITHUB_TOKEN` for GHCR, with `packages: write` only on the job that pushes.
- The cluster credential for the push-based deploy job lives in the `KUBE_CONFIG_DATA` repository secret.
  With GitOps (Argo CD pulls from Git) CI needs no cluster credentials at all.
