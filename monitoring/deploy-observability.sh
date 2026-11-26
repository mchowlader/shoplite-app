#!/usr/bin/env bash
# ==============================================================================
# ShopLite: One-Command Observability Deployment (Question 6 — LGTM Stack)
# Deploys kube-prometheus-stack, Loki, Promtail, Tempo, Grafana Dashboards,
# ServiceMonitors, Alert Rules, and Grafana Ingress into 'monitoring' namespace.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="monitoring"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

log_info "1/7 Creating namespace '${NAMESPACE}'..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

log_info "2/7 Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm repo update

log_info "3/7 Provisioning Grafana Datasource and Dashboard ConfigMaps..."
kubectl create configmap shoplite-grafana-datasources \
    --from-file=datasources.yaml="${SCRIPT_DIR}/grafana/datasources.yaml" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap shoplite-grafana-datasources -n "${NAMESPACE}" grafana_datasource="1" --overwrite

kubectl create configmap shoplite-golden-signals-dashboard \
    --from-file=shoplite-golden-signals.json="${SCRIPT_DIR}/dashboards/shoplite-golden-signals.json" \
    --namespace "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap shoplite-golden-signals-dashboard -n "${NAMESPACE}" grafana_dashboard="1" --overwrite

log_info "4/7 Deploying kube-prometheus-stack (Prometheus + Alertmanager + Grafana + Exporters)..."
HELM_EXTRA_ARGS=()
if [ -z "${GRAFANA_DOMAIN:-}" ] && [ -f /opt/shoplite/alb-dns.txt ]; then
    GRAFANA_DOMAIN="$(tr -d '[:space:]' < /opt/shoplite/alb-dns.txt)"
fi
if [ -n "${GRAFANA_DOMAIN:-}" ]; then
    log_info "Configuring Grafana server.domain=${GRAFANA_DOMAIN} for HTTP ALB /grafana/ subpath..."
    HELM_EXTRA_ARGS+=(--set-string "grafana.grafana\\.ini.server.domain=${GRAFANA_DOMAIN}")
fi
if [ -n "${ALERTMANAGER_WEBHOOK_URL:-}" ]; then
    HELM_EXTRA_ARGS+=(--set-string "alertmanager.config.receivers[0].webhook_configs[0].url=${ALERTMANAGER_WEBHOOK_URL}")
fi

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/prometheus/kube-prometheus-stack-values.yaml" \
    "${HELM_EXTRA_ARGS[@]}" \
    --wait --timeout 420s

log_info "5/7 Deploying Loki, Promtail, and Tempo..."
helm upgrade --install loki grafana/loki \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/loki/loki-values.yaml" \
    --wait --timeout 300s

helm upgrade --install promtail grafana/promtail \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/loki/promtail-values.yaml" \
    --wait --timeout 180s

helm upgrade --install tempo grafana/tempo \
    --namespace "${NAMESPACE}" \
    --values "${SCRIPT_DIR}/tempo/tempo-values.yaml" \
    --wait --timeout 180s

log_info "6/7 Applying ServiceMonitors, Alert Rules (PrometheusRule), and Grafana Ingress..."
kubectl apply -f "${SCRIPT_DIR}/prometheus/servicemonitors.yaml"
kubectl apply -f "${SCRIPT_DIR}/alert-rules/alerts.yaml"
kubectl apply -f "${SCRIPT_DIR}/grafana/grafana-ingress.yaml"

log_info "7/7 Verifying pods in '${NAMESPACE}'..."
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
DISPLAY_HOST="${GRAFANA_DOMAIN:-<ALB-DNS>}"
log_success "Full LGTM Observability Stack deployed in namespace '${NAMESPACE}'!"
echo -e "  Grafana via ALB: http://${DISPLAY_HOST}/grafana/  (User: ${YELLOW}admin${NC} / Password: ${YELLOW}admin${NC})"
echo -e "  Or port-forward: ${YELLOW}kubectl port-forward -n ${NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80${NC}"
