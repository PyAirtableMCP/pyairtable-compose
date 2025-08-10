"""
Authentication System Optimizations
Adds refresh tokens, Redis caching, and performance improvements
"""

import jwt
import redis.asyncio as redis
from datetime import datetime, timedelta
from typing import Dict, Tuple, Optional
import json
import logging

logger = logging.getLogger(__name__)

class OptimizedAuthService:
    """Optimized authentication service with Redis caching and refresh tokens"""
    
    def __init__(self, redis_client, jwt_secret: str, jwt_algorithm: str = "HS256"):
        self.redis = redis_client
        self.jwt_secret = jwt_secret
        self.jwt_algorithm = jwt_algorithm
        
        # Token expiration times
        self.access_token_expires = timedelta(minutes=15)  # Short-lived access tokens
        self.refresh_token_expires = timedelta(days=7)     # Longer-lived refresh tokens
        self.session_expires = timedelta(hours=24)         # Session cache expiration
    
    def create_token_pair(self, user) -> Dict[str, str]:
        """Create access and refresh token pair"""
        now = datetime.utcnow()
        user_id = str(user.id)
        
        # Access token (short-lived)
        access_payload = {
            "sub": user_id,
            "email": user.email,
            "iat": now,
            "exp": now + self.access_token_expires,
            "type": "access"
        }
        
        # Refresh token (long-lived)
        refresh_payload = {
            "sub": user_id,
            "iat": now,
            "exp": now + self.refresh_token_expires,
            "type": "refresh"
        }
        
        access_token = jwt.encode(access_payload, self.jwt_secret, algorithm=self.jwt_algorithm)
        refresh_token = jwt.encode(refresh_payload, self.jwt_secret, algorithm=self.jwt_algorithm)
        
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": int(self.access_token_expires.total_seconds())
        }
    
    async def cache_user_session(self, user) -> None:
        """Cache user session data in Redis"""
        if not self.redis:
            return
        
        try:
            user_data = {
                "id": user.id,
                "email": user.email,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "is_active": user.is_active,
                "created_at": user.created_at.isoformat() if user.created_at else None
            }
            
            cache_key = f"user_session:{user.id}"
            await self.redis.setex(
                cache_key, 
                int(self.session_expires.total_seconds()), 
                json.dumps(user_data)
            )
            
            logger.debug(f"Cached user session: {user.email}")
            
        except Exception as e:
            logger.warning(f"Failed to cache user session: {e}")
    
    async def get_cached_user(self, user_id: int) -> Optional[Dict]:
        """Get user data from Redis cache"""
        if not self.redis:
            return None
        
        try:
            cache_key = f"user_session:{user_id}"
            cached_data = await self.redis.get(cache_key)
            
            if cached_data:
                user_data = json.loads(cached_data)
                logger.debug(f"Retrieved cached user: {user_data['email']}")
                return user_data
                
        except Exception as e:
            logger.warning(f"Failed to get cached user: {e}")
        
        return None
    
    async def invalidate_user_session(self, user_id: int) -> None:
        """Invalidate user session cache"""
        if not self.redis:
            return
        
        try:
            cache_key = f"user_session:{user_id}"
            await self.redis.delete(cache_key)
            logger.debug(f"Invalidated user session: {user_id}")
            
        except Exception as e:
            logger.warning(f"Failed to invalidate user session: {e}")
    
    async def refresh_access_token(self, refresh_token: str) -> Optional[Dict[str, str]]:
        """Refresh access token using refresh token"""
        try:
            # Decode refresh token
            payload = jwt.decode(refresh_token, self.jwt_secret, algorithms=[self.jwt_algorithm])
            
            if payload.get("type") != "refresh":
                raise jwt.InvalidTokenError("Invalid token type")
            
            user_id = int(payload.get("sub"))
            if not user_id:
                raise jwt.InvalidTokenError("Invalid token payload")
            
            # Check if user is still valid (from cache first, then DB if needed)
            cached_user = await self.get_cached_user(user_id)
            if cached_user and cached_user.get("is_active"):
                # Create new access token
                now = datetime.utcnow()
                access_payload = {
                    "sub": str(user_id),
                    "email": cached_user["email"],
                    "iat": now,
                    "exp": now + self.access_token_expires,
                    "type": "access"
                }
                
                new_access_token = jwt.encode(access_payload, self.jwt_secret, algorithm=self.jwt_algorithm)
                
                return {
                    "access_token": new_access_token,
                    "token_type": "bearer",
                    "expires_in": int(self.access_token_expires.total_seconds())
                }
            
            return None
            
        except jwt.ExpiredSignatureError:
            logger.warning("Refresh token expired")
            return None
        except jwt.JWTError as e:
            logger.warning(f"Invalid refresh token: {e}")
            return None
        except Exception as e:
            logger.error(f"Token refresh error: {e}")
            return None
    
    def get_performance_metrics(self) -> Dict[str, str]:
        """Get authentication system performance metrics"""
        return {
            "access_token_ttl": str(self.access_token_expires),
            "refresh_token_ttl": str(self.refresh_token_expires),
            "session_cache_ttl": str(self.session_expires),
            "caching_enabled": str(self.redis is not None)
        }


class ConnectionPoolManager:
    """Optimized database connection pool manager"""
    
    @staticmethod
    def get_optimized_pool_settings() -> Dict[str, int]:
        """Get optimized connection pool settings for different environments"""
        return {
            "pool_size": 10,           # Base pool size
            "max_overflow": 20,        # Additional connections under load
            "pool_timeout": 30,        # Seconds to wait for connection
            "pool_recycle": 3600,      # Recycle connections every hour
            "pool_pre_ping": True      # Validate connections before use
        }
    
    @staticmethod
    def get_redis_pool_settings() -> Dict[str, int]:
        """Get optimized Redis connection pool settings"""
        return {
            "max_connections": 50,      # Max Redis connections
            "retry_on_timeout": True,   # Retry on timeout
            "socket_keepalive": True,   # Keep connections alive
            "health_check_interval": 30 # Health check interval
        }


# Performance monitoring utilities
class AuthPerformanceMonitor:
    """Monitor authentication system performance"""
    
    def __init__(self, redis_client=None):
        self.redis = redis_client
        self.metrics_key = "auth_performance_metrics"
    
    async def track_auth_event(self, event_type: str, response_time: float, success: bool):
        """Track authentication events for performance monitoring"""
        if not self.redis:
            return
        
        try:
            timestamp = datetime.utcnow().isoformat()
            metric_data = {
                "event_type": event_type,
                "response_time": response_time,
                "success": success,
                "timestamp": timestamp
            }
            
            # Store in Redis with expiration
            await self.redis.lpush(self.metrics_key, json.dumps(metric_data))
            await self.redis.expire(self.metrics_key, 86400)  # Keep for 24 hours
            
        except Exception as e:
            logger.warning(f"Failed to track auth event: {e}")
    
    async def get_performance_stats(self) -> Dict:
        """Get authentication performance statistics"""
        if not self.redis:
            return {"error": "Redis not available"}
        
        try:
            # Get recent metrics
            metrics_data = await self.redis.lrange(self.metrics_key, 0, 1000)
            
            if not metrics_data:
                return {"message": "No metrics available"}
            
            # Parse and analyze metrics
            total_events = len(metrics_data)
            successful_events = 0
            total_response_time = 0
            
            event_types = {}
            
            for metric_json in metrics_data:
                try:
                    metric = json.loads(metric_json)
                    event_type = metric["event_type"]
                    response_time = metric["response_time"]
                    success = metric["success"]
                    
                    if success:
                        successful_events += 1
                    
                    total_response_time += response_time
                    
                    if event_type not in event_types:
                        event_types[event_type] = {"count": 0, "avg_time": 0, "success_rate": 0}
                    
                    event_types[event_type]["count"] += 1
                    
                except json.JSONDecodeError:
                    continue
            
            # Calculate statistics
            success_rate = (successful_events / total_events * 100) if total_events > 0 else 0
            avg_response_time = total_response_time / total_events if total_events > 0 else 0
            
            return {
                "total_events": total_events,
                "success_rate": round(success_rate, 2),
                "avg_response_time": round(avg_response_time, 3),
                "event_breakdown": event_types
            }
            
        except Exception as e:
            return {"error": f"Failed to get stats: {e}"}