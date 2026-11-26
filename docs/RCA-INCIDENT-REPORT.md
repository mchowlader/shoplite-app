# Root Cause Analysis (RCA) — ShopLite Chaos Day Exercise (Question 8)

**Assessment Code:** `DEVOPS-CAP-601`  
**Service:** ShopLite (`catalog-api` + `order-worker`) in `shoplite` namespace  
**Note:** Replace timestamps, trace IDs, and screenshots below with your live Chaos Day exercise evidence after running the 15-minute load test (`scripts/load-test.py --url http://<ALB-DNS> --rps 25 --duration 900`).

---

## 1. Incident Timeline (UTC)

| Timestamp | Event | Telemetry Signal |
|---|---|---|
| `T+00:00` | Peer modifies `envs/prod/values.yaml` in `shoplite-gitops` and commits change; load test starts at 25 RPS. | Traffic Rate panel rises to ~25 req/s. |
| `T+05:00` | Alert fires in Prometheus/Alertmanager (`HighErrorRate` / `HighLatency` / `PodCrashLooping` / `QueueBacklog`). | Alertmanager notification fired with severity and runbook URL. |
| `T+06:30` | On-call investigates Grafana **ShopLite - Golden Signals** dashboard -> drills into **Loki** (`{namespace="shoplite"}`) -> jumps via `trace_id` to **Tempo**. | Correlation pinpoints failing span/component without reading pod env vars or Git diff. |
| `T+10:00` | Root cause confirmed from metrics, JSON logs, and Tempo span waterfall; faulty commit reverted in `shoplite-gitops`. | ArgoCD syncs production state back to clean baseline. |
| `T+12:00` | Error rate returns to 0%, p95 latency normalizes, queue drains, alerts resolve. | Recovery verified on Grafana Golden Signals dashboard. |

---

## 2. Detection

- **First Alert Triggered:** `<HighErrorRate | HighLatency | QueueBacklog | PodCrashLooping>`
- **Why It Triggered:** PromQL condition exceeded threshold across the evaluation window (`for: 5m` or `10m`) under sustained 25 RPS load.

---

## 3. Investigation Trail (`Dashboard -> Logs -> Trace`)

1. **Grafana Golden Signals Dashboard:** Checked `HTTP 5xx Error Rate`, `Latency (p50, p95, p99) per Route`, `Order Queue Depth`, `Orders Created vs Processed`, and `Pod Memory/CPU`.
2. **Loki Logs (`{namespace="shoplite"}`):** Filtered error/warning JSON logs (`level="ERROR"` or `level="WARNING"`) to extract `trace_id` and failing service (`catalog-api` or `order-worker`).
3. **Tempo Distributed Trace:** Followed `trace_id` from Loki Derived Field (or histogram Exemplar) to inspect the waterfall across `HTTP -> catalog-api -> redis -> order-worker -> postgresql` (`SQLAlchemy`/`psycopg2`).

---

## 4. Identified Root Cause & Recovery Time

- **Root Cause:** Fault injection enabled via `envs/prod/values.yaml` (`CHAOS_ERROR_RATE` / `CHAOS_LATENCY_MS` / `CHAOS_MEMORY_LEAK` / `CHAOS_SLOW_DB`), diagnosed strictly from observability signals before checking Git diff.
- **Recovery Action:** Reverted the peer commit in `shoplite-gitops` (`git revert <commit-sha> && git push`) and synchronized ArgoCD (`shoplite-prod`).
- **Recovery Time (TTR):** `<MM> minutes <SS> seconds`.

---

## 5. Preventive Measure

- Enforce GitOps pull-request review (`CODEOWNERS` + branch protection on `shoplite-gitops` `main`) and automated post-deploy Canary metric gates (`Argo Rollouts` `AnalysisTemplate`) so any commit degrading error rate (>1%) or p95 latency (>500ms) is blocked or automatically rolled back.
