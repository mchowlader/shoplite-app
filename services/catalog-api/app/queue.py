import json
import logging
import redis
from .config import settings

logger = logging.getLogger("catalog-api")

try:
    redis_client = redis.Redis(
        host=settings.REDIS_HOST,
        port=settings.REDIS_PORT,
        db=settings.REDIS_DB,
        socket_timeout=3,
        decode_responses=True
    )
except Exception as e:
    logger.error(f"Failed to create Redis connection: {e}")
    redis_client = None

def enqueue_order(order_payload: dict) -> bool:
    """
    Pushes an order into the Redis list 'orders:pending' (Requirement 1.1).
    """
    if not redis_client:
        logger.error("Redis client unavailable.")
        return False
    try:
        data = json.dumps(order_payload)
        redis_client.lpush(settings.REDIS_QUEUE_NAME, data)
        return True
    except Exception as exc:
        logger.error(f"Failed to enqueue order to Redis list {settings.REDIS_QUEUE_NAME}: {exc}")
        return False

def check_redis() -> bool:
    """
    Verifies that the Redis queue broker is responsive.
    """
    if not redis_client:
        return False
    try:
        return bool(redis_client.ping())
    except Exception:
        return False

def get_queue_depth() -> int:
    """
    Returns the current depth of Redis list 'orders:pending' for Prometheus gauge.
    """
    if not redis_client:
        return 0
    try:
        return redis_client.llen(settings.REDIS_QUEUE_NAME)
    except Exception:
        return 0
