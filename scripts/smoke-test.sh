#!/usr/bin/env bash
# ==============================================================================
# ShopLite Automated Smoke Test Harness
# Question 2.c: Automated Verification of Containerized Stack
# ==============================================================================

set -uo pipefail

BASE_URL="${API_URL:-http://localhost:8000}"
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
echo -e "Target API Base URL: ${YELLOW}${BASE_URL}${NC}\n"

# ------------------------------------------------------------------------------
# Step 1: Wait for /readyz (Verifying PostgreSQL and Redis Connectivity)
# ------------------------------------------------------------------------------
echo -n "Step 1: Waiting for /readyz to return HTTP 200 ... "
READY=false
for ((i=1; i<=MAX_READY_RETRIES; i++)); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/readyz" || true)
    if [ "$HTTP_CODE" -eq 200 ]; then
        READY=true
        break
    fi
    sleep "$RETRY_INTERVAL"
done

if [ "$READY" = true ]; then
    echo -e "${GREEN}[PASS]${NC} (PostgreSQL & Redis connected successfully)"
else
    echo -e "${RED}[FAIL]${NC} (Timeout waiting for /readyz after $((MAX_READY_RETRIES * RETRY_INTERVAL))s)"
    curl -s "${BASE_URL}/readyz" || true
    echo ""
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 2: Verify Product Catalog Listing (At least 10 products)
# ------------------------------------------------------------------------------
echo -n "Step 2: Checking GET /products catalog seeding ... "
PRODUCTS_JSON=$(curl -s "${BASE_URL}/products")
PRODUCT_COUNT=$(echo "$PRODUCTS_JSON" | grep -o '"id":' | wc -l || true)

if [ "$PRODUCT_COUNT" -ge 10 ]; then
    echo -e "${GREEN}[PASS]${NC} (Found ${PRODUCT_COUNT} products in database)"
else
    echo -e "${RED}[FAIL]${NC} (Expected at least 10 products, found ${PRODUCT_COUNT})"
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 3: Place a New Order (POST /orders)
# ------------------------------------------------------------------------------
echo -n "Step 3: Placing test order (POST /orders) ... "
ORDER_PAYLOAD='{"product_id": 1, "quantity": 1}'
ORDER_RESPONSE=$(curl -s -X POST "${BASE_URL}/orders" \
    -H "Content-Type: application/json" \
    -d "$ORDER_PAYLOAD")

ORDER_ID=$(echo "$ORDER_RESPONSE" | grep -o '"order_id":[0-9]*' | cut -d: -f2 || true)

if [ -n "$ORDER_ID" ] && [ "$ORDER_ID" -gt 0 ]; then
    echo -e "${GREEN}[PASS]${NC} (Created Order #${ORDER_ID} in PENDING state)"
else
    echo -e "${RED}[FAIL]${NC} (Failed to create order. Response: ${ORDER_RESPONSE})"
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 4: Poll Order until COMPLETED (Proves order-worker processing)
# ------------------------------------------------------------------------------
echo -n "Step 4: Polling Order #${ORDER_ID} until status is COMPLETED ... "
COMPLETED=false
CURRENT_STATUS="PENDING"

for ((attempt=1; attempt<=15; attempt++)); do
    STATUS_JSON=$(curl -s "${BASE_URL}/orders/${ORDER_ID}" || true)
    CURRENT_STATUS=$(echo "$STATUS_JSON" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)

    if [ "$CURRENT_STATUS" = "COMPLETED" ]; then
        COMPLETED=true
        break
    fi
    sleep 1
done

if [ "$COMPLETED" = true ]; then
    echo -e "${GREEN}[PASS]${NC} (Order #${ORDER_ID} processed and marked COMPLETED by worker)"
else
    echo -e "${RED}[FAIL]${NC} (Order status is '${CURRENT_STATUS}', expected 'COMPLETED' within 15s)"
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 5: Summary
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}✅ ALL SMOKE TESTS PASSED! End-to-end container stack verified.${NC}"
echo -e "${BLUE}======================================================${NC}\n"
exit 0
