import time
import random
import uuid
import datetime
from typing import List
from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException, status, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

from .config import settings
from .logging_config import setup_logging
from .models import Product, Order
from .schemas import (
    ProductResponse, OrderCreate, OrderCreateResponse,
    OrderStatusResponse, HealthResponse
)
from .database import get_db, init_db, SessionLocal
from .queue import enqueue_order, check_redis, get_queue_depth

logger = setup_logging(service_name=settings.SERVICE_NAME, log_level=settings.LOG_LEVEL)

# --- Required Prometheus Metrics (Section 6.2) ---
HTTP_REQUESTS_TOTAL = Counter(
    "http_requests_total",
    "Total HTTP requests received",
    ["method", "route", "status"]
)
HTTP_REQUEST_DURATION_SECONDS = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "route"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)
ORDERS_CREATED_TOTAL = Counter(
    "orders_created_total",
    "Total count of orders created"
)
ORDER_QUEUE_DEPTH = Gauge(
    "order_queue_depth",
    "Current depth of the orders:pending queue"
)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing ShopLite catalog-api...")
    init_db()
    yield
    logger.info("Shutting down catalog-api cleanly...")

app = FastAPI(
    title="ShopLite Catalog API",
    version="1.0.0",
    description="REST API for ShopLite E-Commerce Platform",
    lifespan=lifespan
)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request Metrics, Tracing, and Logging Middleware
@app.middleware("http")
async def telemetry_middleware(request: Request, call_next):
    start_time = time.time()
    trace_id = request.headers.get("X-Trace-Id", uuid.uuid4().hex)
    request.state.trace_id = trace_id

    route_path = request.url.path
    response = await call_next(request)
    duration = time.time() - start_time

    # Update Prometheus metrics (excluding /metrics, /healthz, /readyz to keep clean metrics)
    if route_path not in ["/metrics", "/healthz", "/readyz"]:
        HTTP_REQUESTS_TOTAL.labels(
            method=request.method,
            route=route_path,
            status=str(response.status_code)
        ).inc()
        HTTP_REQUEST_DURATION_SECONDS.labels(
            method=request.method,
            route=route_path
        ).observe(duration)

    response.headers["X-Trace-Id"] = trace_id
    return response

# --- Health & Observability Endpoints ---
@app.get("/healthz", tags=["Health"])
def liveness():
    """Liveness check indicating that the process is running (Requirement 1.2)."""
    return {"status": "healthy"}

@app.get("/readyz", response_model=HealthResponse, tags=["Health"])
def readiness(response: Response, db: Session = Depends(get_db)):
    """Readiness check verifying database and queue connectivity (Requirement 1.2)."""
    db_ok = False
    try:
        db.execute(text("SELECT 1"))
        db_ok = True
    except Exception as exc:
        logger.warning(f"Database readiness check failed: {exc}")

    queue_ok = check_redis()
    is_ready = db_ok and queue_ok

    if not is_ready:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return HealthResponse(
        status="ready" if is_ready else "degraded",
        database="connected" if db_ok else "unreachable",
        queue="connected" if queue_ok else "unreachable"
    )

@app.get("/metrics", tags=["Observability"])
def metrics():
    """Exposes Prometheus metrics required in Question 6."""
    ORDER_QUEUE_DEPTH.set(get_queue_depth())
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

# --- Product Catalog Endpoints ---
@app.get("/products", response_model=List[ProductResponse], tags=["Products"])
def get_products(db: Session = Depends(get_db)):
    """Return all products (Requirement 1.2)."""
    products = db.query(Product).order_by(Product.id.asc()).all()
    return products

@app.get("/products/{id}", response_model=ProductResponse, tags=["Products"])
def get_product_by_id(id: int, db: Session = Depends(get_db)):
    """
    Return a single product or 404 if it does not exist (Requirement 1.2).
    Applies CHAOS_LATENCY_MS delay to approximately 30% of requests if flag is active (Requirement 1.5).
    """
    # Fault Injection Flag: CHAOS_LATENCY_MS
    if settings.CHAOS_LATENCY_MS > 0 and random.random() < 0.30:
        logger.warning(f"[CHAOS] Injecting {settings.CHAOS_LATENCY_MS}ms latency on GET /products/{id}")
        time.sleep(settings.CHAOS_LATENCY_MS / 1000.0)

    product = db.query(Product).filter(Product.id == id).first()
    if not product:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Product #{id} does not exist."
        )
    return product

# --- Order Management Endpoints ---
@app.post("/orders", response_model=OrderCreateResponse, status_code=status.HTTP_201_CREATED, tags=["Orders"])
def create_order(order_in: OrderCreate, request: Request, db: Session = Depends(get_db)):
    """
    Accept { "product_id": 1, "quantity": 2 }, create a PENDING order, enqueue it,
    and return 201 with the order ID (Requirement 1.2).
    Applies CHAOS_ERROR_RATE returning HTTP 500 if active (Requirement 1.5).
    """
    # Fault Injection Flag: CHAOS_ERROR_RATE
    if settings.CHAOS_ERROR_RATE > 0.0 and random.random() < settings.CHAOS_ERROR_RATE:
        logger.error(f"[CHAOS] Injecting HTTP 500 error on POST /orders (Rate: {settings.CHAOS_ERROR_RATE})")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Chaos Injected: Synthetic database/upstream transaction failure."
        )

    product = db.query(Product).filter(Product.id == order_in.product_id).first()
    if not product:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Product #{order_in.product_id} not found."
        )

    new_order = Order(
        product_id=order_in.product_id,
        quantity=order_in.quantity,
        status="PENDING",
        created_at=datetime.datetime.utcnow()
    )
    db.add(new_order)
    db.commit()
    db.refresh(new_order)

    # Track Prometheus metric
    ORDERS_CREATED_TOTAL.inc()

    # Enqueue to Redis list 'orders:pending'
    trace_id = getattr(request.state, "trace_id", uuid.uuid4().hex)
    payload = {
        "order_id": new_order.id,
        "product_id": new_order.product_id,
        "quantity": new_order.quantity,
        "trace_id": trace_id,
        "enqueued_at": datetime.datetime.utcnow().isoformat()
    }
    enqueue_order(payload)

    logger.info(f"Order #{new_order.id} created and enqueued to orders:pending")
    return OrderCreateResponse(order_id=new_order.id)

@app.get("/orders/{id}", response_model=OrderStatusResponse, tags=["Orders"])
def get_order_status(id: int, db: Session = Depends(get_db)):
    """
    Return the order status: PENDING, PROCESSING, COMPLETED, or FAILED (Requirement 1.2).
    """
    order = db.query(Order).filter(Order.id == id).first()
    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Order #{id} not found."
        )
    return order
