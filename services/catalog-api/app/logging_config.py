import json
import logging
import datetime
import uuid
from typing import Optional

class JSONLogFormatter(logging.Formatter):
    """
    Formats log records as single-line JSON adhering strictly to:
    { "timestamp": "...", "level": "...", "service": "...", "message": "...", "trace_id": "..." }
    """
    def __init__(self, service_name: str = "catalog-api"):
        super().__init__()
        self.service_name = service_name

    def format(self, record: logging.LogRecord) -> str:
        trace_id = getattr(record, "trace_id", None) or uuid.uuid4().hex
        log_obj = {
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "service": self.service_name,
            "message": record.getMessage(),
            "trace_id": str(trace_id)
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)

def setup_logging(service_name: str = "catalog-api", log_level: str = "INFO") -> logging.Logger:
    logger = logging.getLogger(service_name)
    logger.setLevel(log_level.upper())
    logger.handlers.clear()

    handler = logging.StreamHandler()
    handler.setFormatter(JSONLogFormatter(service_name=service_name))
    logger.addHandler(handler)
    logger.propagate = False
    return logger
