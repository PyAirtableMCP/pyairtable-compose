"""
Security Headers Middleware
Enterprise-grade security headers implementation for all Python services
"""

import os
from typing import Callable, Optional
from fastapi import FastAPI, Request, Response
from fastapi.middleware.base import BaseHTTPMiddleware
import logging

logger = logging.getLogger(__name__)

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    Comprehensive security headers middleware following OWASP recommendations
    """
    
    def __init__(
        self, 
        app: FastAPI,
        environment: str = "production",
        csp_policy: Optional[str] = None,
        additional_headers: Optional[dict] = None
    ):
        super().__init__(app)
        self.environment = environment
        self.is_production = environment.lower() == "production"
        self.csp_policy = csp_policy or self._get_default_csp_policy()
        self.additional_headers = additional_headers or {}
        
    def _get_default_csp_policy(self) -> str:
        """
        Generate Content Security Policy based on environment
        """
        if self.is_production:
            # Strict CSP for production
            return (
                "default-src 'self'; "
                "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; "
                "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
                "img-src 'self' data: https:; "
                "font-src 'self' https://fonts.gstatic.com; "
                "connect-src 'self' wss: https:; "
                "media-src 'self'; "
                "object-src 'none'; "
                "base-uri 'self'; "
                "form-action 'self'; "
                "frame-ancestors 'none'; "
                "upgrade-insecure-requests"
            )
        else:
            # Relaxed CSP for development
            return (
                "default-src 'self' 'unsafe-inline' 'unsafe-eval'; "
                "script-src 'self' 'unsafe-inline' 'unsafe-eval' localhost:* http:; "
                "style-src 'self' 'unsafe-inline' 'unsafe-eval'; "
                "img-src 'self' data: blob: http:; "
                "font-src 'self' data:; "
                "connect-src 'self' ws: wss: http: https:; "
                "media-src 'self' blob:; "
                "object-src 'none'; "
                "base-uri 'self'"
            )
    
    def _get_security_headers(self) -> dict:
        """
        Get comprehensive security headers
        """
        headers = {
            # Content Security Policy
            "Content-Security-Policy": self.csp_policy,
            
            # XSS Protection
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "X-XSS-Protection": "1; mode=block",
            
            # HSTS (only for HTTPS)
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains; preload" if self.is_production else "max-age=31536000",
            
            # Referrer Policy
            "Referrer-Policy": "strict-origin-when-cross-origin",
            
            # Permissions Policy (Feature Policy successor)
            "Permissions-Policy": (
                "geolocation=(), "
                "microphone=(), "
                "camera=(), "
                "payment=(), "
                "usb=(), "
                "magnetometer=(), "
                "gyroscope=(), "
                "speaker=(), "
                "fullscreen=(self), "
                "sync-xhr=()"
            ),
            
            # Cache Control for sensitive endpoints
            "Cache-Control": "no-cache, no-store, must-revalidate, private",
            "Pragma": "no-cache",
            "Expires": "0",
            
            # Cross-Origin policies
            "Cross-Origin-Embedder-Policy": "require-corp" if self.is_production else "unsafe-none",
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Resource-Policy": "same-origin",
            
            # Server information hiding
            "Server": "PyAirtable-Security",
            "X-Powered-By": "",
            
            # Additional security headers
            "X-Download-Options": "noopen",
            "X-Permitted-Cross-Domain-Policies": "none",
            "X-DNS-Prefetch-Control": "off",
        }
        
        # Remove HSTS for non-HTTPS environments
        if not self.is_production or os.getenv("DISABLE_HSTS", "false").lower() == "true":
            headers.pop("Strict-Transport-Security", None)
            
        # Add any additional headers
        headers.update(self.additional_headers)
        
        return headers
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        Apply security headers to all responses
        """
        try:
            # Process the request
            response = await call_next(request)
            
            # Apply security headers
            security_headers = self._get_security_headers()
            
            for header_name, header_value in security_headers.items():
                if header_value:  # Only add non-empty headers
                    response.headers[header_name] = header_value
            
            # Log security headers application (debug level)
            logger.debug(f"Applied {len(security_headers)} security headers to {request.url.path}")
            
            return response
            
        except Exception as e:
            logger.error(f"SecurityHeadersMiddleware error: {str(e)}")
            # Don't let middleware errors break the request
            return await call_next(request)

class APISecurityMiddleware(BaseHTTPMiddleware):
    """
    API-specific security middleware
    """
    
    def __init__(self, app: FastAPI, max_request_size: int = 10 * 1024 * 1024):  # 10MB default
        super().__init__(app)
        self.max_request_size = max_request_size
        
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        Apply API security checks
        """
        try:
            # Check request size
            if hasattr(request, 'headers'):
                content_length = request.headers.get('content-length')
                if content_length:
                    if int(content_length) > self.max_request_size:
                        return Response(
                            content="Request entity too large",
                            status_code=413,
                            headers={"Content-Type": "text/plain"}
                        )
            
            # Check for suspicious patterns in URL
            suspicious_patterns = [
                '../', '..\\', '/etc/', '/proc/', '/sys/', '/var/log/',
                'union select', 'drop table', 'insert into', 'delete from',
                '<script', 'javascript:', 'vbscript:', 'onload=', 'onerror='
            ]
            
            url_path = str(request.url.path).lower()
            for pattern in suspicious_patterns:
                if pattern in url_path:
                    logger.warning(f"Suspicious URL pattern detected: {pattern} in {request.url.path}")
                    return Response(
                        content="Forbidden - Suspicious request pattern",
                        status_code=403,
                        headers={"Content-Type": "text/plain"}
                    )
            
            # Process the request
            response = await call_next(request)
            
            # Add API-specific headers
            if request.url.path.startswith('/api/'):
                response.headers["X-API-Version"] = "1.0"
                response.headers["X-Content-Type-Options"] = "nosniff"
                
            return response
            
        except Exception as e:
            logger.error(f"APISecurityMiddleware error: {str(e)}")
            return await call_next(request)

def add_security_middleware(
    app: FastAPI, 
    environment: str = None,
    custom_csp: str = None,
    max_request_size: int = 10 * 1024 * 1024
) -> None:
    """
    Add comprehensive security middleware to FastAPI app
    
    Args:
        app: FastAPI application instance
        environment: Environment name (production, staging, development)
        custom_csp: Custom Content Security Policy
        max_request_size: Maximum request size in bytes
    """
    env = environment or os.getenv("ENVIRONMENT", "development")
    
    # Add API security middleware first
    app.add_middleware(APISecurityMiddleware, max_request_size=max_request_size)
    
    # Add security headers middleware
    app.add_middleware(
        SecurityHeadersMiddleware,
        environment=env,
        csp_policy=custom_csp
    )
    
    logger.info(f"Security middleware added for environment: {env}")

# Rate limiting middleware using Redis
class RateLimitMiddleware(BaseHTTPMiddleware):
    """
    Redis-based rate limiting middleware
    """
    
    def __init__(
        self,
        app: FastAPI,
        redis_client,
        default_rate_limit: int = 100,  # requests per minute
        auth_rate_limit: int = 5,       # login attempts per minute
        window_size: int = 60           # seconds
    ):
        super().__init__(app)
        self.redis_client = redis_client
        self.default_rate_limit = default_rate_limit
        self.auth_rate_limit = auth_rate_limit
        self.window_size = window_size
        
    def _get_client_id(self, request: Request) -> str:
        """Get client identifier for rate limiting"""
        # Try to get real IP from headers
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()
        
        real_ip = request.headers.get("X-Real-IP")
        if real_ip:
            return real_ip.strip()
            
        # Fallback to client host
        return request.client.host if request.client else "unknown"
    
    def _get_rate_limit(self, request: Request) -> int:
        """Get rate limit based on endpoint"""
        path = request.url.path
        
        # Stricter limits for authentication endpoints
        if any(auth_path in path for auth_path in ['/auth/', '/login', '/register']):
            return self.auth_rate_limit
            
        return self.default_rate_limit
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Apply rate limiting"""
        if not self.redis_client:
            return await call_next(request)
            
        try:
            client_id = self._get_client_id(request)
            rate_limit = self._get_rate_limit(request)
            
            # Create Redis key
            key = f"rate_limit:{client_id}:{request.url.path}"
            
            # Get current count
            try:
                current_count = await self.redis_client.get(key)
                current_count = int(current_count) if current_count else 0
                
                if current_count >= rate_limit:
                    # Rate limit exceeded
                    ttl = await self.redis_client.ttl(key)
                    retry_after = max(ttl, 60)  # At least 1 minute
                    
                    logger.warning(f"Rate limit exceeded for {client_id} on {request.url.path}")
                    
                    return Response(
                        content="Rate limit exceeded",
                        status_code=429,
                        headers={
                            "Retry-After": str(retry_after),
                            "X-RateLimit-Limit": str(rate_limit),
                            "X-RateLimit-Remaining": "0",
                            "X-RateLimit-Reset": str(retry_after)
                        }
                    )
                
                # Increment counter
                pipe = self.redis_client.pipeline()
                pipe.incr(key)
                pipe.expire(key, self.window_size)
                await pipe.execute()
                
                # Process request
                response = await call_next(request)
                
                # Add rate limit headers
                remaining = max(0, rate_limit - (current_count + 1))
                response.headers["X-RateLimit-Limit"] = str(rate_limit)
                response.headers["X-RateLimit-Remaining"] = str(remaining)
                response.headers["X-RateLimit-Reset"] = str(self.window_size)
                
                return response
                
            except Exception as redis_error:
                logger.error(f"Redis error in rate limiting: {str(redis_error)}")
                # Don't block requests on Redis errors
                return await call_next(request)
                
        except Exception as e:
            logger.error(f"RateLimitMiddleware error: {str(e)}")
            return await call_next(request)

def add_rate_limiting(
    app: FastAPI,
    redis_client,
    default_rate_limit: int = 100,
    auth_rate_limit: int = 5
) -> None:
    """
    Add rate limiting middleware to FastAPI app
    """
    app.add_middleware(
        RateLimitMiddleware,
        redis_client=redis_client,
        default_rate_limit=default_rate_limit,
        auth_rate_limit=auth_rate_limit
    )
    
    logger.info("Rate limiting middleware added")