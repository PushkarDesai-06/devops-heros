# 09 - Monitoring Demo (Prometheus + node-exporter + Grafana + Alerts)

This folder extends `03-prometheus` and `04-grafana` into one stack that shows
the monitoring signals from the assignment:

| Signal             | Where it comes from                                                                     |
| ------------------ | --------------------------------------------------------------------------------------- |
| Metrics            | Prometheus scrapes `prometheus`, `node-exporter` and `grafana` every 5s                 |
| CPU utilization    | `node_cpu_seconds_total` from node-exporter                                             |
| Memory utilization | `node_memory_MemAvailable_bytes` / `node_memory_MemTotal_bytes`                         |
| Application health | the `up` metric (1 = target answered the scrape, 0 = it did not)                        |
| Alerts             | [`alert-rules.yml`](alert-rules.yml): `InstanceDown`, `HighCPUUsage`, `HighMemoryUsage` |
| Dashboard          | Grafana, provisioned automatically from [`grafana/`](grafana/)                          |

```text
node-exporter:9100 --+
prometheus:9090 -----+--> Prometheus (scrape + evaluate alert-rules.yml) --> Grafana :3000
grafana:3000 --------+
```

## Files

| File                                              | Purpose                                                                 |
| ------------------------------------------------- | ----------------------------------------------------------------------- |
| `docker-compose.yml`                              | node-exporter v1.9.1, Prometheus v3.5.0, Grafana 12.1.1                 |
| `prometheus.yml`                                  | scrape jobs + `rule_files:` entry that **must** point at the rules file |
| `alert-rules.yml`                                 | alerting rules (group `session20-alerts`)                               |
| `grafana/provisioning/datasources/prometheus.yml` | Prometheus data source (`http://prometheus:9090`)                       |
| `grafana/provisioning/dashboards/dashboards.yml`  | tells Grafana to load dashboards from `/var/lib/grafana/dashboards`     |
| `grafana/dashboards/session20-overview.json`      | "Session 20 - Monitoring overview" dashboard                            |

> Prometheus only evaluates rules listed under `rule_files:` in `prometheus.yml`.
> Creating `alert-rules.yml` alone is not enough; it must be referenced and mounted.

## Run

```bash
# stop the earlier stacks first (same container names / ports)
(cd ../04-grafana && docker compose down)

docker compose up -d
docker compose ps

# validate config + rules with promtool (shipped inside the Prometheus image)
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
```

Open:

| URL                           | What to look at                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| http://localhost:9090/targets | 3 scrape pools, all `UP`                                                             |
| http://localhost:9090/query   | PromQL queries below                                                                 |
| http://localhost:9090/alerts  | rule states: inactive / pending / firing                                             |
| http://localhost:3000         | Grafana (admin / admin) > Dashboards > Session 20 > Session 20 - Monitoring overview |

## Useful PromQL

```promql
# health of every target
up

# CPU utilization (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)

# memory utilization (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
```

## Alert demo (Pending -> Firing)

```bash
docker compose stop node-exporter      # up{job="node-exporter"} becomes 0
# /alerts: InstanceDown is PENDING for 30s (the `for:` duration), then FIRING
curl -s localhost:9090/api/v1/alerts | jq '.data.alerts[] | {alert: .labels.alertname, state, activeAt}'

docker compose start node-exporter     # alert resolves (back to inactive)))
```

## Stop

```bash
docker compose down
```
