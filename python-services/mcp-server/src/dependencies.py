"""Dependencies for MCP Server"""
import logging
from typing import Optional
from functools import lru_cache

import jwt
from redis import asyncio as aioredis
from fastapi import HTTPException, Depends, Request, Header
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from .config import get_settings
from .models.enhanced_mcp import AuthContext
from .services.enhanced_tool_executor import EnhancedToolExecutor

logger = logging.getLogger(__name__)
security = HTTPBearer(auto_error=False)

# Global instances
_redis_client: Optional[aioredis.Redis] = None
_tool_executor: Optional[EnhancedToolExecutor] = None


@lru_cache()
def get_redis_client() -> Optional[aioredis.Redis]:
    """Get Redis client instance"""
    global _redis_client
    if _redis_client is None:
        try:
            settings = get_settings()
            _redis_client = aioredis.from_url(
                settings.redis_url,
                decode_responses=True,
                retry_on_timeout=True,
                socket_keepalive=True
            )
        except Exception as e:
            logger.warning(f"Redis client initialization failed: {e}")
            _redis_client = None
    
    return _redis_client


async def get_tool_executor() -> EnhancedToolExecutor:
    """Get tool executor instance"""
    global _tool_executor
    if _tool_executor is None:
        _tool_executor = EnhancedToolExecutor()
        await _tool_executor.initialize()
    
    return _tool_executor


async def get_current_user_optional(
    request: Request,
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    x_user_id: Optional[str] = Header(None),
    x_session_id: Optional[str] = Header(None)
) -> Optional[AuthContext]:
    """Get current user context if authentication is provided"""
    settings = get_settings()
    
    try:
        # If no credentials provided, return None (anonymous access)
        if not credentials and not x_user_id:
            return None
        
        # If JWT token is provided
        if credentials:
            token = credentials.credentials
            
            # Decode JWT token if secret is available
            if settings.jwt_secret:
                try:
                    payload = jwt.decode(
                        token,
                        settings.jwt_secret,
                        algorithms=[settings.jwt_algorithm]
                    )
                    
                    return AuthContext(
                        user_id=payload.get("user_id", payload.get("sub", "unknown")),
                        session_id=payload.get("session_id", x_session_id or "unknown"),
                        tenant_id=payload.get("tenant_id"),
                        permissions=payload.get("permissions", []),
                        token_expiry=payload.get("exp")
                    )
                    
                except jwt.InvalidTokenError as e:
                    logger.warning(f"Invalid JWT token: {e}")
                    return None
            else:
                # If no JWT secret, create basic auth context from headers
                return AuthContext(
                    user_id=x_user_id or "anonymous",
                    session_id=x_session_id or "unknown",
                    permissions=[]
                )
        
        # If only headers provided
        elif x_user_id:
            return AuthContext(
                user_id=x_user_id,
                session_id=x_session_id or "unknown",
                permissions=[]
            )
        
        return None
        
    except Exception as e:
        logger.error(f"Authentication error: {e}")
        return None


async def get_current_user(
    auth_context: Optional[AuthContext] = Depends(get_current_user_optional)
) -> AuthContext:
    """Get current user context (required)"""
    if not auth_context:
        raise HTTPException(
            status_code=401,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"}
        )
    
    return auth_context


async def validate_rate_limit(
    request: Request,
    auth_context: Optional[AuthContext] = Depends(get_current_user_optional),
    redis_client: Optional[aioredis.Redis] = Depends(get_redis_client)
) -> None:
    """Validate rate limits for the current user/IP"""
    if not redis_client:
        return  # Skip rate limiting if Redis is not available
    
    settings = get_settings()
    
    # Determine the identifier for rate limiting
    identifier = auth_context.user_id if auth_context else request.client.host
    rate_limit_key = f"rate_limit:{identifier}"
    
    try:
        # Get current request count
        current_count = await redis_client.get(rate_limit_key)
        
        if current_count is None:
            # First request in the window
            await redis_client.setex(rate_limit_key, settings.rate_limit_window, 1)
        else:
            count = int(current_count)
            if count >= settings.rate_limit_requests:
                raise HTTPException(
                    status_code=429,
                    detail=f"Rate limit exceeded. Max {settings.rate_limit_requests} requests per {settings.rate_limit_window} seconds",
                    headers={
                        "Retry-After": str(settings.rate_limit_window),
                        "X-RateLimit-Limit": str(settings.rate_limit_requests),
                        "X-RateLimit-Remaining": "0"
                    }
                )
            else:
                # Increment the counter
                await redis_client.incr(rate_limit_key)
                remaining = settings.rate_limit_requests - count - 1
                
                # Add rate limit headers to the response (this would be done in middleware)
                request.state.rate_limit_remaining = remaining
                
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Rate limiting error: {e}")
        # Don't block requests if rate limiting fails