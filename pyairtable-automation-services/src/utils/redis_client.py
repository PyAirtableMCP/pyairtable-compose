import redis.asyncio as redis
from typing import Optional
from ..config import settings
import logging

logger = logging.getLogger(__name__)

# Global Redis client
_redis_client: Optional[redis.Redis] = None

async def init_redis() -> redis.Redis:
    """Initialize Redis connection"""
    global _redis_client
    
    try:
        _redis_client = redis.from_url(
            settings.redis_url,
            password=settings.redis_password,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5
        )
        
        # Test connection
        await _redis_client.ping()
        logger.info("Redis client initialized successfully")
        return _redis_client
        
    except Exception as e:
        logger.error(f"Failed to initialize Redis client: {str(e)}")
        raise

async def get_redis_client() -> redis.Redis:
    """Get Redis client instance"""
    global _redis_client
    
    if _redis_client is None:
        _redis_client = await init_redis()
    
    return _redis_client

async def close_redis():
    """Close Redis connection"""
    global _redis_client
    
    if _redis_client:
        await _redis_client.close()
        _redis_client = None
        logger.info("Redis client closed")

# Redis utility functions
async def cache_set(key: str, value: str, expire: int = 3600) -> bool:
    """Set cache value with expiration"""
    try:
        client = await get_redis_client()
        return await client.setex(key, expire, value)
    except Exception as e:
        logger.error(f"Redis cache set error: {str(e)}")
        return False

async def cache_get(key: str) -> Optional[str]:
    """Get cache value"""
    try:
        client = await get_redis_client()
        return await client.get(key)
    except Exception as e:
        logger.error(f"Redis cache get error: {str(e)}")
        return None

async def cache_delete(key: str) -> bool:
    """Delete cache key"""
    try:
        client = await get_redis_client()
        return bool(await client.delete(key))
    except Exception as e:
        logger.error(f"Redis cache delete error: {str(e)}")
        return False

async def publish_event(channel: str, message: str) -> bool:
    """Publish event to Redis channel"""
    try:
        client = await get_redis_client()
        return await client.publish(channel, message) > 0
    except Exception as e:
        logger.error(f"Redis publish error: {str(e)}")
        return False