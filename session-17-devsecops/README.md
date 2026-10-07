# Session 17 – Complete CI/CD & DevSecOps Pipeline

A Flask app (`demo/`) shipped through a GitHub Actions pipeline in which every security check can **stop** the
delivery: SAST, SCA, secret scanning, container image scanning, and an explicit security gate. Only an image that
passed all of them is pushed to GHCR and deployed to Kubernetes.

```text
Code → Build → Unit Test → SAST → SCA → Secret Scan → Docker Build → Image Scan → Security Gate → Push (GHCR) → Deploy (K8s)
```

The write-up with expected outputs and screenshots is in [submission.md](submission.md).

## Layout

| Path | What it is |
| --- | --- |
| [demo/app/](demo/app/) | Flask application (dashboard + JSON API on port 5001) |
| [demo/tests/test_app.py](demo/tests/test_app.py) | 8 pytest unit tests |
| [demo/Dockerfile](demo/Dockerfile) | Course Dockerfile (root user, dev server with `debug=True`) |
| [demo/Dockerfile.secure](demo/Dockerfile.secure) | Hardened image used by the pipeline: patched OS packages, non-root uid 10001, gunicorn |
| [demo/requirements-prod.txt](demo/requirements-prod.txt) | Runtime deps baked into the image (Flask + gunicorn) – what SCA audits |
| [demo/.github/workflows/session17-devsecops.yml](demo/.github/workflows/session17-devsecops.yml) | The complete gated pipeline |
| [demo/.github/workflows/devsecops.yml](demo/.github/workflows/devsecops.yml) | Course starter workflow (kept for reference) |
| [demo/bandit.yaml](demo/bandit.yaml) | SAST config (Bandit) |
| [demo/.gitleaks.toml](demo/.gitleaks.toml) | Secret scanning config (gitleaks, default rules + allowlist) |
| [demo/trivy.yaml](demo/trivy.yaml), [demo/.trivyignore](demo/.trivyignore) | Image scan policy (HIGH/CRITICAL, fixed only, exit code 1) and accepted-risk list |
| [demo/.dockerignore](demo/.dockerignore) | Keeps tests, `.git`, coverage data and `.env` files out of the build context |
| [demo/k8s-secure/deployment.yaml](demo/k8s-secure/deployment.yaml) | Deployment for the GHCR image (probes, limits, non-root, read-only FS) |
| [demo/k8s/service.yaml](demo/k8s/service.yaml) | NodePort service `session17-python` (80 → 5001, nodePort 30001) |
| `02-…` to `08-…` | Topic notes: registry, K8s deploy, SAST, SCA, secrets, image scanning, gates |

## Tools and gates

| Stage | Tool | Job | Blocks the pipeline when |
| --- | --- | --- | --- |
| Build + unit test | pytest, pytest-cov | `Unit Tests` | a test fails or coverage < 60 % |
| SAST | CodeQL | `SAST - CodeQL + Bandit` | (reports to the Security tab, does not block) |
| SAST | Bandit | same job | a HIGH-severity + HIGH-confidence finding |
| SCA | pip-audit | `SCA - pip-audit` | any known vulnerability in `requirements-prod.txt` |
| Secret scan | gitleaks | `Secret Scan - gitleaks` | any secret in the pushed commits |
| Docker build + image scan | docker, Trivy | `Build & Scan Image` | build fails, or a fixable HIGH/CRITICAL CVE in the image |
| Security gate | bash | `Security Gate` | any of the jobs above is not `success` (runs with `if: always()`) |
| Registry | GHCR | `Push Image to GHCR` | – (only after the gate, only on push to `main`) |
| Deploy | kind + kubectl | `Deploy to Kubernetes` | rollout does not finish in 120 s or the smoke test fails |

The image that Trivy scanned is saved as an artifact and that exact image is pushed. It is never rebuilt after
the scan.

## Run it locally

```bash
cd session-17-devsecops/demo
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt bandit==1.8.6 pip-audit==2.9.0

python3 -m pytest -v --cov=app --cov-report=term-missing --cov-fail-under=60   # build + unit tests
bandit -r app -c bandit.yaml -ll                                               # SAST
pip-audit -r requirements-prod.txt                                             # SCA
gitleaks dir --redact -v .                                                     # secret scan
docker build -f Dockerfile.secure -t session17-python:local .                  # docker build
trivy image --config trivy.yaml session17-python:local                         # image scan + gate
```

## Enable the pipeline

GitHub only runs workflows from the repository root. Copy the workflow once:

```bash
mkdir -p .github/workflows
cp session-17-devsecops/demo/.github/workflows/session17-devsecops.yml .github/workflows/
git add .github/workflows/session17-devsecops.yml && git commit -m "ci: add session 17 devsecops pipeline" && git push
```

No extra secrets are needed. `GITHUB_TOKEN` is used to push to GHCR (`packages: write`), to create the image pull
secret in kind (`packages: read`), and by gitleaks. The workflow triggers only on changes under
`session-17-devsecops/demo/**` or the workflow file itself.

The image is published as `ghcr.io/devops-student/session17-python:<commit-sha>` (plus `:latest`).

## Deploy to minikube

A GitHub-hosted runner cannot reach minikube on a laptop. CI deploys to a temporary kind cluster to prove the
manifests work, and the same manifests are applied to minikube by hand:

```bash
kubectl create secret docker-registry ghcr-pull --docker-server=ghcr.io \
  --docker-username=devops-student --docker-password=$GHCR_TOKEN     # PAT with read:packages
SHA=<commit sha that passed the gate>
sed "s|__IMAGE_TAG__|$SHA|g" k8s-secure/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/session17-python --timeout=120s
kubectl port-forward service/session17-python 8080:80
curl localhost:8080/health
```

(fish shell: `set SHA <sha>` instead of `SHA=<sha>`.)

## Known findings / follow-ups

- **Bandit B201 / CodeQL `py/flask-debug`**: `app/app.py` calls `app.run(debug=True)`. The pipeline image never
  runs that line, because gunicorn imports `app.app:app`. The proper fix is
  `app.run(host="0.0.0.0", port=5001, debug=os.getenv("FLASK_DEBUG") == "1")`.
- `datetime.utcnow()` is deprecated (6 warnings in pytest). Replace it with `datetime.now(datetime.UTC)`.
- The course folder contains a file named `.dockerignore  │`, which Docker does not read. A real
  [demo/.dockerignore](demo/.dockerignore) was added.
