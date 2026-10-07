# Session 20 - Monitoring, Observability & GitOps

This session covers how we **watch** a running system (monitoring), how we **understand** it
when something goes wrong (observability), and how we **deploy** to Kubernetes by changing Git
instead of running `kubectl` by hand (GitOps with Argo CD).

The homework write-up with commands and expected-output screenshots is in
[`submission.md`](submission.md).

## Folder map

| Folder | Topic | What is inside |
|---|---|---|
| [`01-monitoring-vs-observability`](01-monitoring-vs-observability/) | Concepts | Monitoring vs observability, car analogy |
| [`02-metrics-logs-traces`](02-metrics-logs-traces/) | Three pillars | Notes + `k8s-demo/` (busybox `session20-demo` that writes logs) |
| [`03-prometheus`](03-prometheus/) | Metrics | Prometheus v3.5.0 via Docker Compose, scrapes itself |
| [`04-grafana`](04-grafana/) | Dashboards | Prometheus + Grafana 12.1.1 via Docker Compose |
| [`05-introduction-to-gitops`](05-introduction-to-gitops/) | GitOps | Desired vs actual state, `session20-app` manifests |
| [`06-git-as-source-of-truth`](06-git-as-source-of-truth/) | GitOps | Example GitOps repo (`session20-gitops-app`) |
| [`07-argocd`](07-argocd/) | Argo CD | Install Argo CD, `session20-app` Application, auto-sync, self-heal |
| [`08-mini-project`](08-mini-project/) | Mini project | Namespace + Deployment + Service + Argo CD Application (`session20-mini`) |
| [`09-monitoring-demo`](09-monitoring-demo/) | Monitoring demo | Prometheus + node-exporter + Grafana, alert rules, provisioned dashboard |

---

## Part 1 - Monitoring

Monitoring answers **"Is the system healthy right now?"** using signals we decided to collect in advance.

| What we monitor | Example signal (PromQL / command) | Typical alert |
|---|---|---|
| Metrics | `up`, `prometheus_http_requests_total` | - |
| CPU utilization | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)` | CPU > 80% for 1m |
| Memory utilization | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | Memory > 85% for 1m |
| Application health | `up{job="..."}` (1 = scrape succeeded), Kubernetes readiness | Target down for 30s |
| Logs | `kubectl logs`, `docker compose logs` | error rate > threshold |
| Alerts | Prometheus rules in [`09-monitoring-demo/alert-rules.yml`](09-monitoring-demo/alert-rules.yml) | inactive -> pending -> firing |

Alert lifecycle in Prometheus:

```text
condition false            condition true             condition still true after `for:`
   INACTIVE  ------------->   PENDING   ------------------------->   FIRING  ---> Alertmanager
      ^                          |                                      |
      +------ condition false ---+--------------------------------------+
```

---

## Part 2 - Observability

Observability answers **"Why is the system behaving this way?"** - it lets us ask new questions
about a system from the data it already emits, without shipping new code first.

### The three pillars

| Pillar | What it is | Answers | Example | Common tools |
|---|---|---|---|---|
| **Metrics** | Numbers sampled over time, with labels | How much? How often? | `http_requests_total{code="500"} 42` | Prometheus, Grafana, Datadog, CloudWatch |
| **Logs** | Timestamped text/JSON events | What happened? | `2026-10-03 10:42 ERROR Database timeout` | Loki, Elasticsearch/OpenSearch (ELK/EFK), Fluent Bit, Fluentd |
| **Traces** | One request followed across services as spans | Where did the time go? | `API 20ms -> Orders 80ms -> DB 600ms` | OpenTelemetry, Jaeger, Grafana Tempo, Zipkin |

How they work together during an incident:

```text
Metric alert:  p95 latency > 1s           (something is wrong)
      |
Trace:         checkout -> payment -> DB  (DB span = 850ms, so the DB is slow)
      |
Logs (DB pod): "slow query ... 840ms"     (here is the exact reason)
```

### Why observability is required

- Microservices and containers fail in ways nobody predicted; fixed dashboards only cover **known** failures.
- Pods are short-lived: when a pod is replaced, its local state is gone unless metrics/logs were shipped out.
- It reduces **MTTR** (mean time to recovery): engineers go from "it is slow" to "this query is slow" quickly.
- It supports SLOs/SLAs, capacity planning and safe deployments (did the new version make things worse?).

### Monitoring vs observability

| Monitoring | Observability |
|---|---|
| Is something wrong? | Why is it wrong? |
| Known failure modes, predefined dashboards and alerts | Unknown problems, ad-hoc questions |
| Mostly metrics | Metrics + logs + traces, correlated |
| Example: "CPU 92%" | Example: "CPU is high because pod X is retrying a failing call to Y" |

They are not competitors: monitoring is one thing you do with observable systems.

### Kubernetes observability

| Layer | Metrics | Logs | Health / events |
|---|---|---|---|
| Node | node-exporter, `kubectl top nodes` (metrics-server) | kubelet / container runtime logs | `kubectl describe node` |
| Pod / container | cAdvisor (in kubelet), `kubectl top pods` | `kubectl logs <pod>` / `deployment/<name>` | liveness/readiness probes, `kubectl describe pod` |
| Kubernetes objects | kube-state-metrics (desired vs available replicas, restarts) | API server audit logs | `kubectl get events` |
| Application | `/metrics` endpoint scraped by Prometheus | stdout/stderr collected by Fluent Bit -> Loki/ES | traces via OpenTelemetry SDK + Collector |

Common production stack: **kube-prometheus-stack** (Prometheus Operator, Alertmanager, Grafana,
node-exporter, kube-state-metrics) + **Loki** for logs + **Tempo/Jaeger** for traces, all collected
with **OpenTelemetry** where possible.

Note: `kubectl top` only works after **metrics-server** is installed. It keeps only the latest values;
for history you still need Prometheus.

---

## Part 3 - GitOps

| Idea | Meaning |
|---|---|
| **GitOps** | Operating infrastructure and apps by changing a Git repository; an agent in the cluster applies the change |
| **Git as the source of truth** | The repository holds the desired state; every change has an author, a diff, a review and can be reverted |
| **Declarative configuration** | We describe *what* we want (`replicas: 3`), not the steps to get there |
| **Continuous reconciliation** | A controller (Argo CD) keeps comparing desired (Git) vs actual (cluster) and fixes drift |
| **Pull-based deploys** | The cluster pulls from Git; CI does not need cluster credentials |

### GitOps workflow

```text
Developer --> git commit / pull request --> Git repo (desired state)
                                                  |
                                    Argo CD polls (~3 min) or webhook
                                                  |
                                                  v
                                Compare desired vs live  --> OutOfSync?
                                                  |
                                     sync (kubectl apply equivalent)
                                                  |
                                                  v
                                      Kubernetes (actual state)
                                                  |
                    someone runs `kubectl scale` --> drift --> selfHeal reverts it
```

### Kubernetes + GitOps with Argo CD

The Argo CD `Application` (see [`07-argocd/app/argocd-application.yaml`](07-argocd/app/argocd-application.yaml)) says:

| Field | Value in this session | Meaning |
|---|---|---|
| `source.repoURL` | `https://github.com/Nency-Ravaliya/gitops-demo.git` | Repo to watch |
| `source.path` | `app` | Folder with the manifests |
| `destination.namespace` | `session20` | Where to deploy |
| `syncPolicy.automated.prune` | `true` | Delete resources removed from Git |
| `syncPolicy.automated.selfHeal` | `true` | Undo manual changes in the cluster |
| `syncOptions: CreateNamespace=true` | - | Create `session20` if missing |

## Quick start

```bash
# Monitoring demo
cd 09-monitoring-demo && docker compose up -d      # http://localhost:9090, http://localhost:3000

# Kubernetes logs/metrics
kind create cluster --name session20
kubectl apply -f 02-metrics-logs-traces/k8s-demo/

# GitOps
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f 07-argocd/app/argocd-application.yaml
```
