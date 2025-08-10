"""Redis client management and utilities."""

from typing import Any, Optional

from redis.asyncio import Redis

from ..core.config import get_settings
from ..core.logging import get_logger

# Global Redis instances
redis_pool: Optional[Redis] = None
logger = get_logger(__name__)


async def create_redis_pool() -> None:
    """Create Redis connection pool."""
    global redis_pool
    
    settings = get_settings()
    
    redis_pool = Redis.from_url(
        settings.redis.url,
        password=settings.redis.password,
        max_connections=settings.redis.max_connections,
        retry_on_timeout=settings.redis.retry_on_timeout,
        decode_responses=True,
    )
    
    # Test connection
    await redis_pool.ping()
    logger.info("Redis connection pool created")


async def close_redis_pool() -> None:
    """Close Redis connection pool."""
    global redis_pool
    
    if redis_pool:
        await redis_pool.close()
        redis_pool = None
        logger.info("Redis connection pool closed")


def get_redis_client() -> Redis:
    """Get Redis client."""
    if redis_pool is None:
        raise RuntimeError("Redis pool not initialized")
    return redis_pool


class RedisCache:
    """Redis-based cache utility."""
    
    def __init__(self, prefix: str = "automation"):
        self.prefix = prefix
        self.client = get_redis_client()
    
    def _make_key(self, key: str) -> str:
        """Create prefixed cache key."""
        return f"{self.prefix}:{key}"
    
    async def get(self, key: str) -> Optional[str]:
        """Get value from cache."""
        try:
            return await self.client.get(self._make_key(key))
        except Exception as e:
            logger.error("Redis get error", key=key, error=str(e))
            return None
    
    async def set(
        self, 
        key: str, 
        value: str, 
        expire: Optional[int] = None
    ) -> bool:
        """Set value in cache."""
        try:
            return await self.client.set(
                self._make_key(key),
                value,
                ex=expire
            )
        except Exception as e:
            logger.error("Redis set error", key=key, error=str(e))
            return False
    
    async def delete(self, key: str) -> bool:
        """Delete value from cache."""
        try:
            result = await self.client.delete(self._make_key(key))
            return result > 0
        except Exception as e:
            logger.error("Redis delete error", key=key, error=str(e))
            return False
    
    async def exists(self, key: str) -> bool:
        """Check if key exists in cache."""
        try:
            return await self.client.exists(self._make_key(key)) > 0
        except Exception as e:
            logger.error("Redis exists error", key=key, error=str(e))
            return False
    
    async def expire(self, key: str, seconds: int) -> bool:
        """Set expiration for key."""
        try:
            return await self.client.expire(self._make_key(key), seconds)
        except Exception as e:
            logger.error("Redis expire error", key=key, error=str(e))
            return False
    
    async def incr(self, key: str, amount: int = 1) -> Optional[int]:
        """Increment counter."""
        try:
            return await self.client.incr(self._make_key(key), amount)
        except Exception as e:
            logger.error("Redis incr error", key=key, error=str(e))
            return None
    
    async def decr(self, key: str, amount: int = 1) -> Optional[int]:
        """Decrement counter."""
        try:
            return await self.client.decr(self._make_key(key), amount)
        except Exception as e:
            logger.error("Redis decr error", key=key, error=str(e))
            return None