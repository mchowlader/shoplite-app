#!/usr/bin/env bash
# ==============================================================================
# ShopLite Automated Smoke Test Harness (Question 2.c)
# Starts stack (unless SKIP_COMPOSE_UP=1), waits for /readyz, checks web,
# places an order, and polls until COMPLETED. Exits non-zero on any failure.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BASE_URL="${API_URL:-http://localhost:8000}"
WEB_URL="${WEB_URL:-http://localhost:80}"
MAX_READY_RETRIES=30
RETRY_INTERVAL=2

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}     ShopLite Containerized Stack Smoke Test Runner   ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo -e "Target API Base URL: ${YELLOW}${BASE_URL}${NC}"
echo -e "Target Web Base URL: ${YELLOW}${WEB_URL}${NC}\n"

# Step 0: Ensure application stack is started when invoked standalone (Requirement 2.c)
if [ "${SKIP_COMPOSE_UP:-0}" != "1" ]; then
    echo "Step 0: Starting application stack via docker compose..."
    (cd "${REPO_ROOT}" && docker compose up -d --build)
fi

# Step 1: Wait for /readyz (Verifying PostgreSQL and Redis Connectivity)
echo -n "Step 1: Waiting for /readyz to return HTTP 200 ... "
READY=false
for ((i=1; i<=MAX_READY_RETRIES; i++)); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/readyz" || true)
    if [ "${HTTP_CODE}" = "200" ]; then
        READY=true
        break
    fi
    sleep "${RETRY_INTERVAL}"
done

if [ "${READY}" = true ]; then
    echo -e "${GREEN}[PASS]${NC} (PostgreSQL & Redis connected)"
else
    echo -e "${RED}[FAIL]${NC} (Timeout waiting for /readyz)"
    curl -s "${BASE_URL}/readyz" || true
    exit 1
fi

# Step 2: Check Frontend Web UI availability
echo -n "Step 2: Checking Frontend Web UI (${WEB_URL}/) ... "
WEB_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${WEB_URL}/" || true)
if [ "${WEB_CODE}" = "200" ]; then
    echo -e "${GREEN}[PASS]${NC} (HTTP 200)"
else
    echo -e "${RED}[FAIL]${NC} (Expected HTTP 200 on ${WEB_URL}/, got ${WEB_CODE})"
    exit 1
fi

# Step 3: Verify Product Catalog Listing (At least 10 products)
echo -n "Step 3: Checking GET /products catalog seeding ... "
PRODUCTS_JSON=$(curl -sf "${BASE_URL}/products")
PRODUCT_COUNT=$(echo "${PRODUCTS_JSON}" | grep -o '"id":' | wc -l | tr -d ' ' || true)

if [ "${PRODUCT_COUNT}" -ge 10 ]; then
    echo -e "${GREEN}[PASS]${NC} (Found ${PRODUCT_COUNT} products)"
else
    echo -e "${RED}[FAIL]${NC} (Expected >= 10 products, found ${PRODUCT_COUNT})"
    exit 1
fi

# Step 4: Place a New Order (POST /orders)
echo -n "Step 4: Placing test order (POST /orders) ... "
ORDER_PAYLOAD='{"product_id": 1, "quantity": 1}'
ORDER_RESPONSE=$(curl -sf -X POST "${BASE_URL}/orders" \
    -H "Content-Type: application/json" \
    -d "${ORDER_PAYLOAD}")

ORDER_ID=$(echo "${ORDER_RESPONSE}" | grep -o '"order_id":[0-9]*' | cut -d: -f2 || true)

if [ -n "${ORDER_ID}" ] && [ "${ORDER_ID}" -gt 0 ]; then
    echo -e "${GREEN}[PASS]${NC} (Created Order #${ORDER_ID})"
else
    echo -e "${RED}[FAIL]${NC} (Failed to create order. Response: ${ORDER_RESPONSE})"
    exit 1
fi

# Step 5: Poll Order until COMPLETED (Proves order-worker processing)
echo -n "Step 5: Polling Order #${ORDER_ID} until status is COMPLETED ... "
COMPLETED=false
CURRENT_STATUS="PENDING"

for ((attempt=1; attempt<=20; attempt++)); do
    STATUS_JSON=$(curl -s "${BASE_URL}/orders/${ORDER_ID}" || true)
    CURRENT_STATUS=$(echo "${STATUS_JSON}" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)

    if [ "${CURRENT_STATUS}" = "COMPLETED" ]; then
        COMPLETED=true
        break
    fi
    sleep 1
done

if [ "${COMPLETED}" = true ]; then
    echo -e "${GREEN}[PASS]${NC} (Order #${ORDER_ID} marked COMPLETED)"
else
    echo -e "${RED}[FAIL]${NC} (Order status is '${CURRENT_STATUS}', expected 'COMPLETED' within 20s)"
    exit 1
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}ALL SMOKE TESTS PASSED! End-to-end container stack verified.${NC}"
echo -e "${BLUE}======================================================${NC}\n"
exit 0
