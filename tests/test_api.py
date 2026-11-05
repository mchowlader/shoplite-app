import os
import sys
import pytest
from fastapi.testclient import TestClient

# Add catalog-api to Python module path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "services", "catalog-api")))

from app.main import app
from app.database import init_db

# Initialize database schema and seeds before running test suite
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
    data = response.json()
    assert "detail" in data

def test_create_order_valid():
    """Test 5: POST /orders creates order and returns 201 with order_id (Requirement 1.2)."""
    payload = {"product_id": 1, "quantity": 2}
    response = client.post("/orders", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert "order_id" in data
    assert data["order_id"] > 0

def test_create_order_invalid_quantity_validation():
    """Test 6: POST /orders rejects non-positive quantity with 422 Unprocessable Entity."""
    invalid_payload = {"product_id": 1, "quantity": -3}
    response = client.post("/orders", json=invalid_payload)
    assert response.status_code == 422

def test_get_order_status():
    """Test 7: GET /orders/{id} returns order status (Requirement 1.2)."""
    # First create an order
    create_res = client.post("/orders", json={"product_id": 2, "quantity": 1})
    order_id = create_res.json()["order_id"]

    # Query its status
    status_res = client.get(f"/orders/{order_id}")
    assert status_res.status_code == 200
    order_data = status_res.json()
    assert order_data["id"] == order_id
    assert order_data["status"] in ["PENDING", "PROCESSING", "COMPLETED", "FAILED"]
