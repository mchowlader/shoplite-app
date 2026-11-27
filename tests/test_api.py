import os
import sys
import tempfile
from unittest.mock import patch

# Ensure tests use an isolated writable SQLite database path across Windows/Linux/non-root containers
_TEST_DB = os.path.join(tempfile.gettempdir(), "shoplite_test.db")
os.environ.setdefault("DATABASE_URL", f"sqlite:///{_TEST_DB}")

from fastapi.testclient import TestClient  # noqa: E402

# Add catalog-api to Python module path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "services", "catalog-api")))

from app.main import app  # noqa: E402
from app.database import init_db  # noqa: E402
from app.config import settings  # noqa: E402

init_db()
client = TestClient(app)


def test_healthz_liveness():
    """Test 1: Liveness probe /healthz returns 200 OK (Requirement 1.2)."""
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_get_products_list():
    """Test 2: GET /products returns 200 OK and seeded catalog (Requirement 1.1 & 1.2)."""
    response = client.get("/products")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 10, "Database must seed at least 10 products as required."


def test_get_single_product():
    """Test 3: GET /products/{id} returns single product (Requirement 1.2)."""
    response = client.get("/products/1")
    assert response.status_code == 200
    product = response.json()
    assert product["id"] == 1
    assert "name" in product
    assert "price" in product


def test_get_nonexistent_product_returns_404():
    """Test 4: GET /products/{id} returns 404 if item does not exist (Requirement 1.2)."""
    response = client.get("/products/99999")
    assert response.status_code == 404
    assert "detail" in response.json()


def test_api_prefix_ingress_compatibility():
    """Test 5: /api prefix requests are handled seamlessly for Ingress routing (Requirement 5.1)."""
    response = client.get("/api/products")
    assert response.status_code == 200
    assert len(response.json()) >= 10


def test_create_order_valid():
    """Test 6: POST /orders creates order and returns 201 with order_id (Requirement 1.2)."""
    with patch("app.main.enqueue_order", return_value=True):
        response = client.post("/orders", json={"product_id": 1, "quantity": 2})
    assert response.status_code == 201
    data = response.json()
    assert "order_id" in data
    assert data["order_id"] > 0


def test_create_order_queue_unavailable_returns_503():
    """Test 7: POST /orders returns 503 when Redis enqueue fails instead of dropping orders."""
    with patch("app.main.enqueue_order", return_value=False):
        response = client.post("/orders", json={"product_id": 1, "quantity": 1})
    assert response.status_code == 503


def test_create_order_invalid_quantity_validation():
    """Test 8: POST /orders rejects non-positive quantity with 422 Unprocessable Entity."""
    response = client.post("/orders", json={"product_id": 1, "quantity": -3})
    assert response.status_code == 422


def test_get_order_status():
    """Test 9: GET /orders/{id} returns order status (Requirement 1.2)."""
    with patch("app.main.enqueue_order", return_value=True):
        create_res = client.post("/orders", json={"product_id": 2, "quantity": 1})
    order_id = create_res.json()["order_id"]

    status_res = client.get(f"/orders/{order_id}")
    assert status_res.status_code == 200
    order_data = status_res.json()
    assert order_data["id"] == order_id
    assert order_data["status"] in ["PENDING", "PROCESSING", "COMPLETED", "FAILED"]


def test_metrics_and_chaos_error_rate():
    """Test 10: /metrics exposes required counters and CHAOS_ERROR_RATE triggers 500."""
    client.get("/products")
    metrics_res = client.get("/metrics")
    assert metrics_res.status_code == 200
    assert "application/openmetrics-text" in metrics_res.headers.get("content-type", "")
    body = metrics_res.text
    assert "http_requests_total" in body
    assert "http_request_duration_seconds" in body
    assert "orders_created_total" in body
    assert "order_queue_depth" in body
    assert '# {TraceID="' in body

    original = settings.CHAOS_ERROR_RATE
    settings.CHAOS_ERROR_RATE = 1.0
    try:
        err_res = client.post("/orders", json={"product_id": 1, "quantity": 1})
        assert err_res.status_code == 500
    finally:
        settings.CHAOS_ERROR_RATE = original
