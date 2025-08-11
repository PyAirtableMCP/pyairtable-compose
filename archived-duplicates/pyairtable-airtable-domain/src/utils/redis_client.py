"""Redis client utilities."""

import json
from typing import Any, Dict, List, Optional, Union

import redis.asyncio as aioredis
from redis.asyncio import ConnectionPool

from ..core.config import get_redis_settings
from ..core.logging import get_logger

logger = get_logger(__name__)

# Global Redis client instance
_redis_pool: Optional[ConnectionPool] = None
_redis_client: Optional[aioredis.Redis] = None


async def create_redis_pool() -> None:
    """Create Redis connection pool."""
    global _redis_pool, _redis_client
    
    if _redis_pool is not None:
        logger.warning("Redis pool already exists")
        return
    
    settings = get_redis_settings()
    
    _redis_pool = ConnectionPool.from_url(
        settings.url,
        max_connections=settings.max_connections,
        retry_on_timeout=settings.retry_on_timeout,
        socket_keepalive=settings.socket_keepalive,
        socket_keepalive_options=settings.socket_keepalive_options,
    )
    
    _redis_client = aioredis.Redis(connection_pool=_redis_pool)
    
    # Test connection
    await _redis_client.ping()
    
    logger.info(
        "Redis connection pool created",
        max_connections=settings.max_connections,
    )


async def close_redis_pool() -> None:
    """Close Redis connection pool."""
    global _redis_pool, _redis_client
    
    if _redis_client is not None:
        await _redis_client.aclose()
        _redis_client = None
    
    if _redis_pool is not None:
        await _redis_pool.aclose()
        _redis_pool = None
        logger.info("Redis connection pool closed")


def get_redis_client() -> aioredis.Redis:
    """Get Redis client."""
    if _redis_client is None:
        raise RuntimeError("Redis pool not initialized. Call create_redis_pool() first.")
    return _redis_client


class RedisCache:
    """Redis cache utility class."""
    
    def __init__(self, redis_client: Optional[aioredis.Redis] = None):
        self.redis = redis_client or get_redis_client()
    
    async def get(self, key: str) -> Optional[Any]:
        """Get value from cache."""
        try:
            data = await self.redis.get(key)
            if data:
                return json.loads(data)
        except Exception as e:
            logger.warning("Cache get error", key=key, error=str(e))
        return None
    
    async def set(
        self,
        key: str,
        value: Any,
        ttl: Optional[int] = None,
        nx: bool = False,
        xx: bool = False,
    ) -> bool:
        """Set value in cache."""
        try:
            data = json.dumps(value, default=str)
            
            if ttl:
                if nx or xx:
                    return await self.redis.set(key, data, ex=ttl, nx=nx, xx=xx)
                else:
                    return await self.redis.setex(key, ttl, data)
            else:
                if nx or xx:
                    return await self.redis.set(key, data, nx=nx, xx=xx)
                else:
                    return await self.redis.set(key, data)
        except Exception as e:
            logger.warning("Cache set error", key=key, error=str(e))
            return False
    
    async def delete(self, key: str) -> bool:
        """Delete key from cache."""
        try:
            return await self.redis.delete(key) > 0
        except Exception as e:
            logger.warning("Cache delete error", key=key, error=str(e))
            return False
    
    async def delete_pattern(self, pattern: str) -> int:
        """Delete keys matching pattern."""
        try:
            cursor = 0
            deleted_count = 0
            
            while True:
                cursor, keys = await self.redis.scan(cursor, match=pattern, count=100)
                if keys:
                    deleted_count += await self.redis.delete(*keys)
                if cursor == 0:
                    break
            
            return deleted_count
        except Exception as e:
            logger.warning("Cache pattern delete error", pattern=pattern, error=str(e))
            return 0
    
    async def exists(self, key: str) -> bool:
        """Check if key exists."""
        try:
            return await self.redis.exists(key) > 0
        except Exception as e:
            logger.warning("Cache exists error", key=key, error=str(e))
            return False
    
    async def expire(self, key: str, ttl: int) -> bool:
        """Set expiration for key."""
        try:
            return await self.redis.expire(key, ttl)
        except Exception as e:
            logger.warning("Cache expire error", key=key, error=str(e))
            return False
    
    async def increment(self, key: str, amount: int = 1) -> int:
        """Increment counter."""
        try:
            return await self.redis.incrby(key, amount)
        except Exception as e:
            logger.warning("Cache increment error", key=key, error=str(e))
            return 0
    
    async def decrement(self, key: str, amount: int = 1) -> int:
        """Decrement counter."""
        try:
            return await self.redis.decrby(key, amount)
        except Exception as e:
            logger.warning("Cache decrement error", key=key, error=str(e))
            return 0
    
    async def list_push(self, key: str, value: Any, left: bool = True) -> int:
        """Push value to list."""
        try:
            data = json.dumps(value, default=str)
            if left:
                return await self.redis.lpush(key, data)
            else:
                return await self.redis.rpush(key, data)
        except Exception as e:
            logger.warning("Cache list push error", key=key, error=str(e))
            return 0
    
    async def list_pop(self, key: str, left: bool = True) -> Optional[Any]:
        """Pop value from list."""
        try:
            if left:
                data = await self.redis.lpop(key)
            else:
                data = await self.redis.rpop(key)
            
            if data:
                return json.loads(data)
        except Exception as e:
            logger.warning("Cache list pop error", key=key, error=str(e))
        return None
    
    async def list_length(self, key: str) -> int:
        """Get list length."""
        try:
            return await self.redis.llen(key)
        except Exception as e:
            logger.warning("Cache list length error", key=key, error=str(e))
            return 0
    
    async def hash_set(self, key: str, field: str, value: Any) -> bool:
        """Set hash field."""
        try:
            data = json.dumps(value, default=str)
            return await self.redis.hset(key, field, data) > 0
        except Exception as e:
            logger.warning("Cache hash set error", key=key, field=field, error=str(e))
            return False
    
    async def hash_get(self, key: str, field: str) -> Optional[Any]:
        """Get hash field."""
        try:
            data = await self.redis.hget(key, field)
            if data:
                return json.loads(data)
        except Exception as e:
            logger.warning("Cache hash get error", key=key, field=field, error=str(e))
        return None
    
    async def hash_get_all(self, key: str) -> Dict[str, Any]:
        """Get all hash fields."""
        try:
            data = await self.redis.hgetall(key)
            return {
                field.decode(): json.loads(value.decode())
                for field, value in data.items()
            }
        except Exception as e:
            logger.warning("Cache hash get all error", key=key, error=str(e))
            return {}
    
    async def hash_delete(self, key: str, field: str) -> bool:
        """Delete hash field."""
        try:
            return await self.redis.hdel(key, field) > 0
        except Exception as e:
            logger.warning("Cache hash delete error", key=key, field=field, error=str(e))
            return False


# Global cache instance
cache = RedisCache()