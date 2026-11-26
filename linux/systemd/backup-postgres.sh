#!/usr/bin/env bash
# ==============================================================================
# ShopLite: Automated PostgreSQL Backup Script (Question 3.3 & 4.g)
# Supports both Docker Compose (shoplite-postgres container) and Kubernetes
# (statefulset/shoplite-postgres in shoplite namespace).
# ==============================================================================
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/shoplite}"
CONTAINER_NAME="${CONTAINER_NAME:-shoplite-postgres}"
K8S_NAMESPACE="${K8S_NAMESPACE:-shoplite}"
K8S_STATEFULSET="${K8S_STATEFULSET:-statefulset/shoplite-postgres}"
DB_USER="${DB_USER:-postgres}"
K8S_DB_USER="${K8S_DB_USER:-shoplite_admin}"
DB_NAME="${DB_NAME:-shoplite_db}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"

notify_discord() {
    local status="$1"
    local message="$2"
    if [ -n "${DISCORD_WEBHOOK_URL}" ]; then
        local color=5763719
        [ "${status}" != "SUCCESS" ] && color=15548997
        local payload="{\"embeds\": [{\"title\": \"ShopLite DB Backup: ${status}\", \"description\": \"${message}\", \"color\": ${color}, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]}"
        curl -s -H "Content-Type: application/json" -X POST -d "${payload}" "${DISCORD_WEBHOOK_URL}" >/dev/null 2>&1 || true
    fi
}

trap 'notify_discord "CRITICAL_FAILURE" "PostgreSQL backup job failed unexpectedly! Check journalctl -u shoplite-backup.service."' ERR

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${DB_NAME}_${TIMESTAMP}.sql.gz"
TARGET="${BACKUP_DIR}/${FILENAME}"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
    echo "[INFO] Dumping PostgreSQL from Docker container '${CONTAINER_NAME}'..."
    docker exec "${CONTAINER_NAME}" pg_dump -U "${DB_USER}" "${DB_NAME}" | gzip -9 > "${TARGET}"
elif command -v kubectl &>/dev/null && [ -f /etc/kubernetes/admin.conf ] && KUBECONFIG=/etc/kubernetes/admin.conf kubectl get "${K8S_STATEFULSET}" -n "${K8S_NAMESPACE}" &>/dev/null; then
    echo "[INFO] Dumping PostgreSQL from Kubernetes ${K8S_STATEFULSET} in namespace '${K8S_NAMESPACE}'..."
    KUBECONFIG=/etc/kubernetes/admin.conf kubectl exec -n "${K8S_NAMESPACE}" "${K8S_STATEFULSET}" -- pg_dump -U "${K8S_DB_USER}" "${DB_NAME}" | gzip -9 > "${TARGET}"
else
    echo "[ERROR] No running ShopLite PostgreSQL target found (neither Docker '${CONTAINER_NAME}' nor K8s '${K8S_STATEFULSET}')." >&2
    exit 1
fi

chmod 600 "${TARGET}"
sha256sum "${TARGET}" > "${TARGET}.sha256"

DELETED_COUNT=$(find "${BACKUP_DIR}" -type f -name "${DB_NAME}_*.sql.gz*" -mtime +"${RETENTION_DAYS}" -delete -print | wc -l)
BACKUP_SIZE=$(du -h "${TARGET}" | cut -f1)

echo "[SUCCESS] Backup created: ${TARGET} (${BACKUP_SIZE}); pruned ${DELETED_COUNT} old file(s)."
notify_discord "SUCCESS" "Backup created: \`${FILENAME}\` (${BACKUP_SIZE}). Rotated ${DELETED_COUNT} old files."
