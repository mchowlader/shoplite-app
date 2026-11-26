import os
import json
import time
import signal
import random
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
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "shoplite_db")
DATABASE_URL = f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

METRICS_PORT = int(os.getenv("METRICS_PORT", "9101"))

# Chaos Flags (Section 1.5)
CHAOS_MEMORY_LEAK = os.getenv("CHAOS_MEMORY_LEAK", "false").lower() in ["true", "1"]
CHAOS_SLOW_DB = os.getenv("CHAOS_SLOW_DB", "false").lower() in ["true", "1"]

# Simulated memory leak storage
memory_leak_reservoir = []


# --- JSON Structured Logging (Section 1.4c) ---
def log_json(level: str, message: str, trace_id: str = None):
    """Emit structured single-line JSON log record to stdout."""
    log_record = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
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

# --- Shared SQLAlchemy Engine & Pool ---
engine = create_engine(
    DATABASE_URL,
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
    pool_recycle=300,
)
SessionLocal = sessionmaker(bind=engine)

# --- OpenTelemetry Distributed Tracing Setup (Grafana Tempo) ---
tracer = None
try:
    from opentelemetry import trace
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    from opentelemetry.instrumentation.redis import RedisInstrumentor

    OTEL_EXPORTER_OTLP_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
    ENVIRONMENT = os.getenv("APP_ENV", os.getenv("ENVIRONMENT", "production"))

    resource = Resource.create({
        "service.name": SERVICE_NAME,
        "deployment.environment": ENVIRONMENT
    })
    provider = TracerProvider(resource=resource)
    if OTEL_EXPORTER_OTLP_ENDPOINT:
        otlp_exporter = OTLPSpanExporter(endpoint=OTEL_EXPORTER_OTLP_ENDPOINT)
        provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
        log_json("INFO", f"OpenTelemetry OTLP Exporter registered for {OTEL_EXPORTER_OTLP_ENDPOINT}")
    trace.set_tracer_provider(provider)
    tracer = trace.get_tracer(SERVICE_NAME)
    SQLAlchemyInstrumentor().instrument(engine=engine)
    RedisInstrumentor().instrument()
except Exception as exc:
    log_json("WARNING", f"OpenTelemetry initialization skipped: {exc}")
    tracer = None

# Graceful Shutdown Handlers (Section 1.4c)
running = True


def handle_sigterm(signum, frame):
    """Set shutdown flag so the active order completes before exit."""
    global running
    log_json("INFO", f"Received termination signal ({signum}). Initiating graceful shutdown...")
    running = False


signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)


def _extract_context(traceparent: str):
    """Extract W3C traceparent context for distributed span linking."""
    if not traceparent:
        return None
    try:
        from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
        return TraceContextTextMapPropagator().extract(carrier={"traceparent": traceparent})
    except Exception:
        return None


def _run_step_span(name: str, fn):
    """Execute callable wrapped in a child OTel span when tracing is active."""
    if tracer:
        with tracer.start_as_current_span(name):
            return fn()
    return fn()


def process_order(order_data: dict):
    """
    Consume queued order, simulate 1-2s fulfillment, and update PostgreSQL order status.
    Propagates W3C traceparent context and applies CHAOS_MEMORY_LEAK / CHAOS_SLOW_DB flags.
    """
    start_time = time.time()
    order_id = order_data.get("order_id")
    traceparent = order_data.get("traceparent")
    trace_id = order_data.get("trace_id")
    if not trace_id and traceparent:
        parts = traceparent.split("-")
        if len(parts) >= 4:
            trace_id = parts[1]
    trace_id = trace_id or uuid.uuid4().hex

    context = _extract_context(traceparent)
    session = SessionLocal()
    try:
        if tracer:
            with tracer.start_as_current_span("order-worker.process_order", context=context) as span:
                span.set_attribute("order.id", int(order_id) if str(order_id).isdigit() else 0)
                span.set_attribute("messaging.system", "redis")
                span.set_attribute("messaging.destination", REDIS_QUEUE_NAME)
                _execute_order(session, order_id, trace_id, start_time)
        else:
            _execute_order(session, order_id, trace_id, start_time)
    finally:
        session.close()


def _execute_order(session, order_id: int, trace_id: str, start_time: float):
    """Run transactional PROCESSING -> fulfillment -> COMPLETED workflow."""
    log_json("INFO", f"Picked up Order #{order_id} from {REDIS_QUEUE_NAME}. Setting status to PROCESSING.", trace_id)
    try:
        def mark_processing():
            session.execute(text("UPDATE orders SET status = 'PROCESSING' WHERE id = :oid"), {"oid": order_id})
            session.commit()

        _run_step_span("db.mark_processing", mark_processing)

        def fulfill():
            time.sleep(random.uniform(1.0, 2.0))
            if CHAOS_MEMORY_LEAK:
                memory_leak_reservoir.append(bytearray(10 * 1024 * 1024))
                log_json(
                    "WARNING",
                    f"[CHAOS] Retained 10MB memory leak for Order #{order_id}. Blocks: {len(memory_leak_reservoir)}",
                    trace_id
                )

        _run_step_span("worker.fulfill_order", fulfill)

        if CHAOS_SLOW_DB:
            log_json("WARNING", f"[CHAOS] Executing pg_sleep(2) before updating Order #{order_id}", trace_id)
            _run_step_span("db.chaos_slow_sleep", lambda: session.execute(text("SELECT pg_sleep(2)")))

        def mark_completed():
            session.execute(
                text("UPDATE orders SET status = 'COMPLETED', completed_at = NOW() WHERE id = :oid"),
                {"oid": order_id}
            )
            session.commit()

        _run_step_span("db.mark_completed", mark_completed)

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
    """Main blocking BRPOP worker loop with graceful SIGTERM handling."""
    log_json("INFO", f"Starting ShopLite order-worker on queue '{REDIS_QUEUE_NAME}'")

    try:
        start_http_server(METRICS_PORT)
        log_json("INFO", f"Prometheus worker metrics exporter running on port :{METRICS_PORT}/metrics")
    except Exception as e:
        log_json("WARNING", f"Prometheus metrics port binding issue: {e}")

    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB, decode_responses=True)

    while running:
        try:
            item = r.brpop(REDIS_QUEUE_NAME, timeout=2)
            if item:
                _, raw_payload = item
                order_payload = json.loads(raw_payload)
                process_order(order_payload)
        except redis.ConnectionError:
            log_json("WARNING", "Redis connection interrupted. Retrying in 2 seconds...")
            time.sleep(2)
        except Exception as loop_err:
            log_json("ERROR", f"Unexpected worker error: {loop_err}")
            time.sleep(1)

    engine.dispose()
    log_json("INFO", "order-worker shutdown completed cleanly. Exiting.")


if __name__ == "__main__":
    run_worker()
