import json
import logging
from datetime import datetime, timezone
import uuid


def _current_otel_trace_id() -> str:
    """Return active 32-hex OpenTelemetry trace ID if valid, else empty string."""
    try:
        from opentelemetry import trace

        span = trace.get_current_span()
        ctx = span.get_span_context() if span else None
        if ctx and ctx.is_valid:
            return format(ctx.trace_id, "032x")
    except Exception:
        pass
    return ""


class JSONLogFormatter(logging.Formatter):
    """
    Formats log records as single-line JSON adhering strictly to:
    { "timestamp": "...", "level": "...", "service": "...", "message": "...", "trace_id": "..." }
    """

    def __init__(self, service_name: str = "catalog-api"):
        super().__init__()
        self.service_name = service_name

    def format(self, record: logging.LogRecord) -> str:
        trace_id = getattr(record, "trace_id", None) or _current_otel_trace_id() or uuid.uuid4().hex
        log_obj = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "service": self.service_name,
            "message": record.getMessage(),
            "trace_id": str(trace_id),
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)


def setup_logging(service_name: str = "catalog-api", log_level: str = "INFO") -> logging.Logger:
    """Configure single-line JSON logger writing to stdout."""
    logger = logging.getLogger(service_name)
    logger.setLevel(log_level.upper())
    logger.handlers.clear()

    handler = logging.StreamHandler()
    handler.setFormatter(JSONLogFormatter(service_name=service_name))
    logger.addHandler(handler)
    logger.propagate = False
    return logger
