"""Metrics middleware for Prometheus monitoring."""

import time
from typing import Callable

from fastapi import Request, Response
from prometheus_client import Counter, Histogram
from starlette.middleware.base import BaseHTTPMiddleware

# Prometheus metrics
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status_code"]
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"]
)

ACTIVE_REQUESTS = Counter(
    "http_requests_active",
    "Currently active HTTP requests"
)


class MetricsMiddleware(BaseHTTPMiddleware):
    """Middleware for collecting HTTP metrics."""
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Collect metrics for request."""
        start_time = time.time()
        
        # Increment active requests
        ACTIVE_REQUESTS.inc()
        
        try:
            # Process request
            response = await call_next(request)
            
            # Record metrics
            self._record_metrics(request, response, start_time)
            
            return response
        finally:
            # Decrement active requests
            ACTIVE_REQUESTS.dec()
    
    def _record_metrics(self, request: Request, response: Response, start_time: float) -> None:
        """Record request metrics."""
        duration = time.time() - start_time
        method = request.method
        endpoint = self._get_endpoint_pattern(request)
        status_code = str(response.status_code)
        
        # Record metrics
        REQUEST_COUNT.labels(
            method=method,
            endpoint=endpoint,
            status_code=status_code
        ).inc()
        
        REQUEST_DURATION.labels(
            method=method,
            endpoint=endpoint
        ).observe(duration)
    
    def _get_endpoint_pattern(self, request: Request) -> str:
        """Get endpoint pattern for metrics grouping."""
        path = request.url.path
        
        # Group similar endpoints
        if path.startswith("/api/v1/workflows/"):
            if path.endswith("/execute"):
                return "/api/v1/workflows/{id}/execute"
            elif path.count("/") > 3:
                return "/api/v1/workflows/{id}"
            return "/api/v1/workflows"
        
        if path.startswith("/api/v1/notifications/"):
            if path.count("/") > 3:
                return "/api/v1/notifications/{id}"
            return "/api/v1/notifications"
        
        if path.startswith("/api/v1/webhooks/"):
            if path.count("/") > 3:
                return "/api/v1/webhooks/{id}"
            return "/api/v1/webhooks"
        
        if path.startswith("/api/v1/automation/"):
            return "/api/v1/automation"
        
        return path