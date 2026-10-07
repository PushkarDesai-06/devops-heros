# notes-chart

Helm chart for the session 15 mini project. It deploys a "Notes" web app (nginx stands in for the app)
as a Deployment, a NodePort Service and a ConfigMap whose keys are injected as environment variables.

## Files

| File | Purpose |
|------|---------|
| `Chart.yaml` | Chart metadata: `notes-chart` version `0.1.0`, appVersion `1.0` |
| `values.yaml` | Development defaults: 1 replica, `nginx:1.24`, `environment: development` |
| `values-prod.yaml` | Production overrides: 3 replicas, `nginx:1.25`, `environment: production` |
| `templates/configmap.yaml` | `<release>-config` with `APP_NAME` and `ENVIRONMENT` |
| `templates/deployment.yaml` | `<release>-deploy`, loads the ConfigMap with `envFrom` |
| `templates/service.yaml` | `<release>-svc`, NodePort `{{ .Values.service.nodePort }}` (30090) |
| `templates/NOTES.txt` | Printed after install/upgrade: replicas, image and how to get the URL |

## Values

| Key | Default (`values.yaml`) | Prod (`values-prod.yaml`) |
|-----|-------------------------|---------------------------|
| `replicaCount` | `1` | `3` |
| `image.repository` | `nginx` | `nginx` |
| `image.tag` | `"1.24"` | `"1.25"` |
| `service.port` | `80` | `80` |
| `service.nodePort` | `30090` | `30090` |
| `app.name` | `notes-app` | `notes-app` |
| `app.environment` | `development` | `production` |

## Usage

Run from `session-15-helm/mini-project/`:

```bash
helm lint notes-chart
helm template notes-dev notes-chart                          # preview the YAML
helm install notes-dev notes-chart                           # revision 1 (dev values)
helm upgrade notes-dev notes-chart -f notes-chart/values-prod.yaml   # revision 2 (prod values)
helm history notes-dev
helm rollback notes-dev 2                                    # back to a known good revision
helm uninstall notes-dev
```

Open the app at `http://$(minikube ip):30090`.

Note: `helm upgrade` without `-f values-prod.yaml` (or `--reuse-values`) starts again from `values.yaml`,
so any production overrides are dropped for that revision.
