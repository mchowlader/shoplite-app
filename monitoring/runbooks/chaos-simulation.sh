#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Chaos Engineering & Load Simulation Helper (Question 8)
# Usage: ./chaos-simulation.sh [memory|latency|queue|load|status|cleanup]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

NAMESPACE="shoplite"
BACKEND_TARGET="deployment/shoplite-backend"
WORKER_DEPLOY="shoplite-worker"
POSTGRES_STS="statefulset/shoplite-postgres"
REDIS_DEPLOY="deployment/shoplite-redis"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header()  { echo -e "${BLUE}===================================================================${NC}\n${CYAN}  $1${NC}\n${BLUE}===================================================================${NC}"; }
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

inject_memory_exhaustion() {
    log_header "Chaos Scenario 1: Memory Exhaustion Stress Job"
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: chaos-memory-bomb
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/component: chaos
spec:
  ttlSecondsAfterFinished: 120
  template:
    metadata:
      labels:
        app.kubernetes.io/component: chaos
    spec:
      restartPolicy: Never
      containers:
        - name: stress-memory
          image: polinux/stress:latest
          command: ["stress"]
          args: ["--vm", "2", "--vm-bytes", "512M", "--timeout", "90s"]
          resources:
            requests:
              memory: "128Mi"
            limits:
              memory: "600Mi"
EOF
    log_success "Job 'chaos-memory-bomb' started in '${NAMESPACE}'."
}

inject_database_latency() {
    log_header "Chaos Scenario 2: PostgreSQL Slow Query Injection"
    kubectl exec -i "${POSTGRES_STS}" -n "${NAMESPACE}" -- \
        psql -U shoplite_admin -d shoplite_db -c "SELECT pg_sleep(3.5);" >/dev/null 2>&1 &
    log_success "Injected pg_sleep(3.5) into ${POSTGRES_STS}."
}

inject_queue_backlog() {
    log_header "Chaos Scenario 3: Redis Queue Backlog (orders:pending)"
    kubectl scale "deployment/${WORKER_DEPLOY}" -n "${NAMESPACE}" --replicas=0
    for i in $(seq 1 60); do
        PAYLOAD="{\"order_id\":$i,\"product_id\":1,\"quantity\":1,\"trace_id\":\"0000000000000000000000000000000${i}\"}"
        kubectl exec -i "${REDIS_DEPLOY}" -n "${NAMESPACE}" -- redis-cli LPUSH orders:pending "${PAYLOAD}" >/dev/null 2>&1
    done
    DEPTH=$(kubectl exec -i "${REDIS_DEPLOY}" -n "${NAMESPACE}" -- redis-cli LLEN orders:pending | tr -d '\r')
    log_success "Queue 'orders:pending' depth is now: ${DEPTH} (Alert threshold > 50)."
}

run_load_test() {
    local target_url="${2:-}"
    if [ -z "${target_url}" ]; then
        echo "Usage: $0 load <ALB_URL> [RPS] [DURATION_SEC]"
        exit 1
    fi
    local rps="${3:-25}"
    local duration="${4:-900}"
    log_header "Running Q8 Load Test (${rps} RPS for ${duration}s) -> ${target_url}"
    python3 "${REPO_ROOT}/scripts/load-test.py" --url "${target_url}" --rps "${rps}" --duration "${duration}"
}

cleanup_chaos() {
    log_header "Recovery: Restoring Clean Production Baseline"
    kubectl delete job chaos-memory-bomb -n "${NAMESPACE}" --ignore-not-found=true
    kubectl scale "deployment/${WORKER_DEPLOY}" -n "${NAMESPACE}" --replicas=1
    kubectl exec -i "${REDIS_DEPLOY}" -n "${NAMESPACE}" -- redis-cli DEL orders:pending >/dev/null 2>&1 || true
    kubectl wait --namespace "${NAMESPACE}" --for=condition=ready pod --selector=app.kubernetes.io/part-of=shoplite --timeout=60s || true
    log_success "Namespace '${NAMESPACE}' restored."
}

show_status() {
    log_header "ShopLite Live Cluster Status"
    kubectl get pods -n "${NAMESPACE}" -o wide
    echo ""
    DEPTH=$(kubectl exec -i "${REDIS_DEPLOY}" -n "${NAMESPACE}" -- redis-cli LLEN orders:pending 2>/dev/null | tr -d '\r' || echo "N/A")
    echo -e "${CYAN}Redis orders:pending depth:${NC} ${DEPTH}"
    kubectl get events -n "${NAMESPACE}" --field-selector type=Warning --sort-by='.metadata.creationTimestamp' | tail -n 5 || true
}

ACTION="${1:-status}"
case "${ACTION}" in
    memory)  inject_memory_exhaustion ;;
    latency) inject_database_latency ;;
    queue)   inject_queue_backlog ;;
    load)    run_load_test "$@" ;;
    status)  show_status ;;
    cleanup) cleanup_chaos ;;
    *)       echo "Usage: $0 [memory|latency|queue|load <URL>|status|cleanup]"; exit 1 ;;
esac
