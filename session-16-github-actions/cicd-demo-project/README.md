# Session 16 - CI/CD Demo Project (GitHub Actions)

A small Python command-line calculator with a complete **CI/CD pipeline** built on
GitHub Actions. It is based on the course example
[`10-final-cicd-pipeline`](../session-16-github-actions/10-final-cicd-pipeline/) and adds a
Dockerfile, a Docker job in CI and a separate CD workflow that publishes the image to
GitHub Container Registry and deploys it to a `staging` environment.

```text
git push ──► CI Pipeline (ci.yml)                                  CD Pipeline (cd.yml)
             Test ──┬──► Security Check ──┐                         (workflow_run: CI completed)
                    └──► Build ───────────┴──► Docker Build ──►    Publish Image ──► Deploy to Staging
                          └─ artifact: calculator-build             ghcr.io/...:sha-xxxxxxx   environment: staging
             └─ artifact: test-report
```

## Project structure

```text
cicd-demo-project/
├── .github/workflows/
│   ├── ci.yml            # CI: test -> security-check + build -> docker build & smoke test
│   └── cd.yml            # CD: publish image to GHCR -> deploy to staging
├── app/
│   ├── __init__.py
│   └── calculator.py     # application source code
├── tests/
│   └── test_calculator.py
├── build.sh              # creates build/ (the build artifact)
├── Dockerfile            # python:3.13-slim, non-root user
├── .dockerignore
├── requirements.txt      # pytest
└── README.md
```

## Run locally

```bash
cd session-16-github-actions/cicd-demo-project

# 1. virtual environment + dependencies
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 2. run the app (interactive; type q to quit)
python3 app/calculator.py
printf '10 + 5\n20 / 0\nq\n' | python3 app/calculator.py     # non-interactive

# 3. run the tests
.venv/bin/pytest -v

# 4. build the artifact
./build.sh            # -> build/calculator.py, build/build-info.txt

# 5. Docker image
docker build -t session16-calculator:local .
docker run -it --rm session16-calculator:local
printf '10 + 5\n7 * 6\nq\n' | docker run -i --rm session16-calculator:local
```

## Activate the pipelines on GitHub

GitHub **only** reads workflow files from `.github/workflows/` at the **root** of the
repository. The copies in this folder are the reference versions, so copy them to the
root of `devops-student/devops-heros`:

```bash
# from the repository root
mkdir -p .github/workflows
cp session-16-github-actions/cicd-demo-project/.github/workflows/ci.yml .github/workflows/ci.yml
cp session-16-github-actions/cicd-demo-project/.github/workflows/cd.yml .github/workflows/cd.yml
```

Both workflows already use `working-directory` / `APP_DIR` pointing at this folder, and
CI uses `paths:` filters so it only runs when this project (or `ci.yml`) changes.

Create the secret used by the CD pipeline (any dummy value works for the demo):

```bash
gh secret set DEPLOY_TOKEN --repo devops-student/devops-heros    # prompts: "? Paste your secret:"
# non-interactive alternative (value ends up in shell history):
# gh secret set DEPLOY_TOKEN --repo devops-student/devops-heros --body "demo-deploy-token-s16"
gh secret list --repo devops-student/devops-heros
```

Then commit and push:

```bash
git add .github/workflows/ci.yml .github/workflows/cd.yml session-16-github-actions/cicd-demo-project
git commit -m "ci: add CI/CD pipeline for session 16 calculator"
git push origin main

gh run list --workflow ci.yml --limit 3
gh run watch                  # pick the running CI run
gh run list --workflow cd.yml --limit 3
gh run download <ci-run-id> -n calculator-build -D /tmp/calculator-build
```

## Pipeline reference

### CI - `.github/workflows/ci.yml` ("CI Pipeline")

| Job | `needs` | What it does | Output |
|-----|---------|--------------|--------|
| `test` - Test Application | - | checkout, Python 3.12, `pip install`, `pytest -v --junitxml` | artifact `test-report` |
| `security-check` - Security Check | `test` | fails if `.env`, `*.pem`, `*.key` files are committed | - |
| `build` - Build Application | `test` | `./build.sh`, prints `build-info.txt` | artifact `calculator-build` |
| `docker` - Docker Build & Smoke Test | `build`, `security-check` | `docker build`, pipes `10 + 5` / `8 * 4` into the container and checks the result | - |

Triggers: `push` and `pull_request` to `main` (path-filtered) and `workflow_dispatch`.

### CD - `.github/workflows/cd.yml` ("CD Pipeline")

| Job | `needs` | What it does |
|-----|---------|--------------|
| `publish` - Publish Docker Image | - (`if:` CI concluded `success`) | checks out the exact commit CI tested, logs in to `ghcr.io` with `GITHUB_TOKEN`, pushes `:sha-<short>` and `:latest` |
| `deploy` - Deploy to Staging | `publish` | `environment: staging`, checks `DEPLOY_TOKEN`, pulls the image, runs a smoke test, writes a job summary |

Trigger: `workflow_run` on "CI Pipeline" `completed` for `main`, plus `workflow_dispatch`.
`concurrency: cd-staging` makes deployments queue instead of overlapping.

### Secrets

| Secret | Type | Used in |
|--------|------|---------|
| `GITHUB_TOKEN` | automatic, per run | `cd.yml` - `docker login ghcr.io` (needs `permissions: packages: write`) |
| `DEPLOY_TOKEN` | repository secret (you create it) | `cd.yml` - `deploy` job, "Check deploy secret" step |

Secrets are passed to steps through `env:` and are never echoed; GitHub masks them as
`***` if they ever appear in a log.

## Failure scenario

Break `add()` in `app/calculator.py` (`return a + b + 1`) and push. `test` fails, so
`build`, `security-check` and `docker` are **skipped** (they `needs: test`), and CD's
`publish` job is skipped because `workflow_run.conclusion` is `failure`. Nothing broken
reaches the registry or staging. Revert the change and push again to get a green run.
