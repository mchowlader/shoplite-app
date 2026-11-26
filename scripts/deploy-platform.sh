#!/usr/bin/env bash
# ==============================================================================
# ShopLite: One-Command Control-Plane Platform Bootstrapper (ArgoCD + LGTM Stack)
# Run on Kubernetes Control-Plane node (via AWS SSM StartSession or SSH):
#   ~/shoplite-app/scripts/deploy-platform.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
GITOPS_REPO_DIR="${GITOPS_REPO_DIR:-$(dirname "${APP_REPO_DIR}")/shoplite-gitops}"
WAIT_FOR_PODS="${WAIT_FOR_PODS:-true}"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -f /opt/shoplite/alb-dns.txt ] && [ -z "${GRAFANA_DOMAIN:-}" ]; then
  export GRAFANA_DOMAIN
  GRAFANA_DOMAIN="$(tr -d '[:space:]' < /opt/shoplite/alb-dns.txt)"
fi

echo -e "${BLUE}[1/4] Registering ArgoCD Applications from ${GITOPS_REPO_DIR}...${NC}"
if [ -d "${GITOPS_REPO_DIR}/apps/argocd-applications" ]; then
  kubectl apply -f "${GITOPS_REPO_DIR}/apps/argocd-applications/"
else
  echo -e "${YELLOW}[WARN] ${GITOPS_REPO_DIR}/apps/argocd-applications not found; cloning repository...${NC}"
  git clone https://github.com/mchowlader/shoplite-gitops.git "${GITOPS_REPO_DIR}"
  kubectl apply -f "${GITOPS_REPO_DIR}/apps/argocd-applications/"
fi

echo -e "${BLUE}[2/4] Deploying Full LGTM Observability Stack (Prometheus, Loki, Promtail, Tempo, Grafana, Alertmanager)...${NC}"
"${APP_REPO_DIR}/monitoring/deploy-observability.sh"

echo -e "${BLUE}[3/4] Waiting for ShopLite dev deployment rollout...${NC}"
if [ "${WAIT_FOR_PODS}" = "true" ]; then
  kubectl wait --for=condition=Ready pods --all -n shoplite-dev --timeout=240s || true
fi

echo -e "${BLUE}[4/4] Cluster Summary & Endpoints:${NC}"
kubectl get pods -n shoplite-dev -o wide || true
kubectl get pods -n monitoring -o wide || true

ALB_HOST="${GRAFANA_DOMAIN:-<ALB-DNS>}"
ARGOCD_PASS="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '<pending>')"

echo ""
echo -e "${GREEN}===================================================================${NC}"
echo -e "  ShopLite Storefront : http://${ALB_HOST}/"
echo -e "  ShopLite API        : http://${ALB_HOST}/api/products"
echo -e "  Grafana UI          : http://${ALB_HOST}/grafana/  (admin / admin)"
echo -e "  ArgoCD Admin Pass   : ${ARGOCD_PASS}"
echo -e "  ArgoCD Port-Forward : kubectl port-forward -n argocd svc/argocd-server 8080:80"
echo -e "${GREEN}===================================================================${NC}"
