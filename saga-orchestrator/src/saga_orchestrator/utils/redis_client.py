"""Redis client utility."""

import redis.asyncio as redis
from urllib.parse import urlparse

from ..core.config import Settings


def get_redis_client(settings: Settings) -> redis.Redis:
    """Create Redis client from settings."""
    parsed_url = urlparse(str(settings.redis_url))
    
    return redis.Redis(
        host=parsed_url.hostname or "localhost",
        port=parsed_url.port or 6379,
        password=settings.redis_password or parsed_url.password,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5,
        retry_on_timeout=True,
        health_check_interval=30
    )