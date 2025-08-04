"""Redis client for caching and session management"""
import json
from typing import Optional, Any, Dict, List
import redis.asyncio as redis

from ..core.config import get_settings
from ..core.logging import get_logger


# Global Redis client
_redis_client: Optional[redis.Redis] = None
logger = get_logger(__name__)


async def init_redis() -> None:
    """Initialize Redis connection"""
    global _redis_client
    
    settings = get_settings()
    
    try:
        # Parse Redis URL
        _redis_client = redis.from_url(
            settings.redis_url,
            encoding="utf-8",
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True,
            health_check_interval=30
        )
        
        # Test connection
        await _redis_client.ping()
        
        logger.info("Redis connection initialized successfully")
        
    except Exception as e:
        logger.error(f"Failed to initialize Redis: {str(e)}")
        _redis_client = None
        # Don't raise exception - Redis is optional


async def close_redis() -> None:
    """Close Redis connection"""
    global _redis_client
    
    if _redis_client:
        await _redis_client.close()
        _redis_client = None
        logger.info("Redis connection closed")


async def get_redis_client() -> Optional[redis.Redis]:
    """Get Redis client"""
    return _redis_client


class RedisCache:
    """Redis-based cache manager"""
    
    def __init__(self, prefix: str = "ai_domain"):
        self.prefix = prefix
        self.logger = get_logger(f"{__name__}.{prefix}")
    
    def _make_key(self, key: str) -> str:
        """Create prefixed cache key"""
        return f"{self.prefix}:{key}"
    
    async def get(self, key: str) -> Optional[Any]:
        """Get value from cache"""
        client = await get_redis_client()
        if not client:
            return None
        
        try:
            value = await client.get(self._make_key(key))
            if value:
                return json.loads(value)
            return None
        except Exception as e:
            self.logger.warning(f"Cache get failed for key {key}: {str(e)}")
            return None
    
    async def set(
        self, 
        key: str, 
        value: Any, 
        ttl: Optional[int] = None
    ) -> bool:
        """Set value in cache"""
        client = await get_redis_client()
        if not client:
            return False
        
        try:
            serialized_value = json.dumps(value, default=str)
            if ttl:
                await client.setex(self._make_key(key), ttl, serialized_value)
            else:
                await client.set(self._make_key(key), serialized_value)
            return True
        except Exception as e:
            self.logger.warning(f"Cache set failed for key {key}: {str(e)}")
            return False
    
    async def delete(self, key: str) -> bool:
        """Delete value from cache"""
        client = await get_redis_client()
        if not client:
            return False
        
        try:
            result = await client.delete(self._make_key(key))
            return result > 0
        except Exception as e:
            self.logger.warning(f"Cache delete failed for key {key}: {str(e)}")
            return False
    
    async def exists(self, key: str) -> bool:
        """Check if key exists in cache"""
        client = await get_redis_client()
        if not client:
            return False
        
        try:
            result = await client.exists(self._make_key(key))
            return result > 0
        except Exception as e:
            self.logger.warning(f"Cache exists check failed for key {key}: {str(e)}")
            return False
    
    async def mget(self, keys: List[str]) -> Dict[str, Any]:
        """Get multiple values from cache"""
        client = await get_redis_client()
        if not client:
            return {}
        
        try:
            prefixed_keys = [self._make_key(key) for key in keys]
            values = await client.mget(prefixed_keys)
            
            result = {}
            for i, value in enumerate(values):
                if value:
                    try:
                        result[keys[i]] = json.loads(value)
                    except json.JSONDecodeError:
                        continue
            
            return result
        except Exception as e:
            self.logger.warning(f"Cache mget failed: {str(e)}")
            return {}
    
    async def mset(self, mapping: Dict[str, Any], ttl: Optional[int] = None) -> bool:
        """Set multiple values in cache"""
        client = await get_redis_client()
        if not client:
            return False
        
        try:
            # Prepare data
            redis_mapping = {}
            for key, value in mapping.items():
                redis_mapping[self._make_key(key)] = json.dumps(value, default=str)
            
            # Set values
            await client.mset(redis_mapping)
            
            # Set TTL if provided
            if ttl:
                for key in redis_mapping.keys():
                    await client.expire(key, ttl)
            
            return True
        except Exception as e:
            self.logger.warning(f"Cache mset failed: {str(e)}")
            return False
    
    async def increment(self, key: str, amount: int = 1) -> Optional[int]:
        """Increment a counter"""
        client = await get_redis_client()
        if not client:
            return None
        
        try:
            result = await client.incrby(self._make_key(key), amount)
            return result
        except Exception as e:
            self.logger.warning(f"Cache increment failed for key {key}: {str(e)}")
            return None
    
    async def expire(self, key: str, ttl: int) -> bool:
        """Set TTL for existing key"""
        client = await get_redis_client()
        if not client:
            return False
        
        try:
            result = await client.expire(self._make_key(key), ttl)
            return result
        except Exception as e:
            self.logger.warning(f"Cache expire failed for key {key}: {str(e)}")
            return False


class SessionManager:
    """Session management using Redis"""
    
    def __init__(self):
        self.cache = RedisCache("sessions")
        self.settings = get_settings()
    
    async def create_session(
        self, 
        session_id: str, 
        user_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """Create a new session"""
        session_data = {
            "session_id": session_id,
            "user_id": user_id,
            "created_at": str(datetime.utcnow()),
            "last_accessed": str(datetime.utcnow()),
            "message_count": 0,
            "token_count": 0,
            "cost": 0.0,
            "metadata": metadata or {}
        }
        
        return await self.cache.set(
            session_id, 
            session_data, 
            ttl=self.settings.session_ttl
        )
    
    async def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data"""
        return await self.cache.get(session_id)
    
    async def update_session(
        self, 
        session_id: str, 
        updates: Dict[str, Any]
    ) -> bool:
        """Update session data"""
        session = await self.get_session(session_id)
        if not session:
            return False
        
        session.update(updates)
        session["last_accessed"] = str(datetime.utcnow())
        
        return await self.cache.set(
            session_id, 
            session, 
            ttl=self.settings.session_ttl
        )
    
    async def delete_session(self, session_id: str) -> bool:
        """Delete session"""
        return await self.cache.delete(session_id)
    
    async def extend_session(self, session_id: str) -> bool:
        """Extend session TTL"""
        return await self.cache.expire(session_id, self.settings.session_ttl)


# Import datetime after other imports to avoid potential issues
from datetime import datetime