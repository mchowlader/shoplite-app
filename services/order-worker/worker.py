import os
import sys
import json
import time
import signal
import random
import logging
import datetime
import uuid
import redis
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from prometheus_client import start_http_server, Counter, Histogram

# --- Environment & Configuration ---
SERVICE_NAME = "order-worker"
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
REDIS_QUEUE_NAME = os.getenv("REDIS_QUEUE_NAME", "orders:pending")

DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres123")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "shoplite_db")
DATABASE_URL = f"postgresql://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

METRICS_PORT = int(os.getenv("METRICS_PORT", "9101"))

# Chaos Flags (Section 1.5)
CHAOS_MEMORY_LEAK = os.getenv("CHAOS_MEMORY_LEAK", "false").lower() in ["true", "1"]
CHAOS_SLOW_DB = os.getenv("CHAOS_SLOW_DB", "false").lower() in ["true", "1"]

# Simulated memory leak storage
memory_leak_reservoir = []

# --- JSON Structured Logging (Section 1.4c) ---
def log_json(level: str, message: str, trace_id: str = None):
    log_record = {
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "level": level,
        "service": SERVICE_NAME,
        "message": message,
        "trace_id": trace_id or uuid.uuid4().hex
    }
    print(json.dumps(log_record), flush=True)

# --- Required Prometheus Metrics (Section 6.2) ---
ORDERS_PROCESSED_TOTAL = Counter(
    "orders_processed_total",
    "Total orders processed by order-worker",
    ["result"]
)
ORDER_PROCESSING_SECONDS = Histogram(
    "order_processing_seconds",
    "Time taken by order-worker to process an order",
    buckets=[0.5, 1.0, 1.5, 2.0, 3.0, 5.0]
)

# Graceful Shutdown Handlers (Section 1.4c)
running = True

def handle_sigterm(signum, frame):
    global running
    log_json("INFO", f"Received termination signal ({signum}). Initiating graceful shutdown...")
    running = False

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)

def get_db_session():
    engine = create_engine(DATABASE_URL, pool_size=5, max_overflow=10, pool_pre_ping=True)
    Session = sessionmaker(bind=engine)
    return Session()

def process_order(session, order_data: dict):
    """
    Consumes queued order, simulates processing for 1-2 seconds, and updates order status.
    Implements CHAOS_MEMORY_LEAK and CHAOS_SLOW_DB if active.
    """
    start_time = time.time()
    order_id = order_data.get("order_id")
    trace_id = order_data.get("trace_id", uuid.uuid4().hex)

    log_json("INFO", f"Picked up Order #{order_id} from {REDIS_QUEUE_NAME}. Setting status to PROCESSING.", trace_id)

    try:
        # Step 1: Set status to PROCESSING
        session.execute(
            text("UPDATE orders SET status = 'PROCESSING' WHERE id = :oid"),
            {"oid": order_id}
        )
        session.commit()

        # Step 2: Simulate processing work for 1-2 seconds (Requirement 1.1)
        simulated_delay = random.uniform(1.0, 2.0)
        time.sleep(simulated_delay)

        # Fault Injection Flag: CHAOS_MEMORY_LEAK (Section 1.5)
        if CHAOS_MEMORY_LEAK:
            # Append 10MB of data per order to simulate heap exhaustion / OOMKilled
            leak_block = bytearray(10 * 1024 * 1024)
            memory_leak_reservoir.append(leak_block)
            log_json("WARNING", f"[CHAOS] Retained 10MB memory leak for Order #{order_id}. Total leaked blocks: {len(memory_leak_reservoir)}", trace_id)

        # Fault Injection Flag: CHAOS_SLOW_DB (Section 1.5)
        if CHAOS_SLOW_DB:
            log_json("WARNING", f"[CHAOS] Executing pg_sleep(2) before updating Order #{order_id}", trace_id)
            session.execute(text("SELECT pg_sleep(2)"))

        # Step 3: Update status to COMPLETED and set completed_at
        session.execute(
            text("UPDATE orders SET status = 'COMPLETED', completed_at = NOW() WHERE id = :oid"),
            {"oid": order_id}
        )
        session.commit()

        duration = time.time() - start_time
        ORDER_PROCESSING_SECONDS.observe(duration)
        ORDERS_PROCESSED_TOTAL.labels(result="completed").inc()
        log_json("INFO", f"Order #{order_id} successfully marked COMPLETED in {duration:.2f}s.", trace_id)

    except Exception as exc:
        session.rollback()
        log_json("ERROR", f"Failed to process Order #{order_id}: {exc}", trace_id)
        try:
            session.execute(
                text("UPDATE orders SET status = 'FAILED', completed_at = NOW() WHERE id = :oid"),
                {"oid": order_id}
            )
            session.commit()
        except Exception:
            pass
        ORDERS_PROCESSED_TOTAL.labels(result="failed").inc()

def run_worker():
    global running
    log_json("INFO", f"Starting ShopLite order-worker on queue '{REDIS_QUEUE_NAME}'")

    # Start Prometheus Exporter on port 9101
    try:
        start_http_server(METRICS_PORT)
        log_json("INFO", f"Prometheus worker metrics exporter running on port :{METRICS_PORT}/metrics")
    except Exception as e:
        log_json("WARNING", f"Prometheus metrics port binding issue: {e}")

    # Redis Connection
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

    db_session = None
    try:
        db_session = get_db_session()
        log_json("INFO", "Worker database session established.")
    except Exception as e:
        log_json("ERROR", f"Initial database connection error: {e}")

    while running:
        try:
            # Blocking pop with 2s timeout to ensure SIGTERM can cleanly interrupt loop
            item = r.brpop(REDIS_QUEUE_NAME, timeout=2)
            if item:
                _, raw_payload = item
                order_payload = json.loads(raw_payload)
                if not db_session:
                    db_session = get_db_session()
                process_order(db_session, order_payload)
        except redis.ConnectionError:
            log_json("WARNING", "Redis connection interrupted. Retrying in 2 seconds...")
            time.sleep(2)
        except Exception as loop_err:
            log_json("ERROR", f"Unexpected worker error: {loop_err}")
            time.sleep(1)

    if db_session:
        db_session.close()
    log_json("INFO", "order-worker shutdown completed cleanly. Exiting.")

if __name__ == "__main__":
    run_worker()
