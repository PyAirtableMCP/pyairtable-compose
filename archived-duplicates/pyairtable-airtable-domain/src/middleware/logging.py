"""Request logging middleware."""

import time
from typing import Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from ..core.logging import get_logger, add_context, clear_context

logger = get_logger(__name__)


class LoggingMiddleware(BaseHTTPMiddleware):
    """Middleware for structured request/response logging."""
    
    def __init__(self, app):
        super().__init__(app)
        
        # Endpoints to skip logging (for noise reduction)
        self.skip_paths = {
            "/health",
            "/ready", 
            "/live",
            "/metrics",
        }
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Log request and response details."""
        
        # Skip logging for certain endpoints
        if request.url.path in self.skip_paths:
            return await call_next(request)
        
        # Extract request info
        start_time = time.time()
        request_id = getattr(request.state, "request_id", "unknown")
        user_id = getattr(request.state, "user_id", None)
        
        # Add context for this request
        add_context(
            request_id=request_id,
            method=request.method,
            path=request.url.path,
            user_id=user_id,
        )
        
        # Log request start
        logger.info(
            "Request started",
            method=request.method,
            path=request.url.path,
            query_params=str(request.query_params) if request.query_params else None,
            user_agent=request.headers.get("User-Agent"),
            client_host=self._get_client_ip(request),
        )
        
        try:
            # Process request
            response = await call_next(request)
            
            # Calculate response time
            process_time = time.time() - start_time
            
            # Log response
            logger.info(
                "Request completed",
                status_code=response.status_code,
                process_time_ms=round(process_time * 1000, 2),
                response_size=response.headers.get("content-length"),
            )
            
            # Add timing header
            response.headers["X-Process-Time"] = str(round(process_time * 1000, 2))
            
            return response
            
        except Exception as e:
            # Calculate response time
            process_time = time.time() - start_time
            
            # Log error
            logger.error(
                "Request failed",
                error=str(e),
                error_type=type(e).__name__,
                process_time_ms=round(process_time * 1000, 2),
                exc_info=True,
            )
            
            # Re-raise the exception
            raise
        
        finally:
            # Clear context
            clear_context()
    
    def _get_client_ip(self, request: Request) -> str:
        """Extract client IP address from request."""
        # Check for forwarded headers first (for load balancers/proxies)
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            # Take the first IP in the chain
            return forwarded_for.split(",")[0].strip()
        
        # Check other common headers
        real_ip = request.headers.get("X-Real-IP")
        if real_ip:
            return real_ip
        
        # Fall back to direct client
        if hasattr(request, "client") and request.client:
            return request.client.host
        
        return "unknown"