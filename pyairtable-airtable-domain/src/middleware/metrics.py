"""Prometheus metrics middleware."""

import time
from typing import Callable

from fastapi import Request, Response
from prometheus_client import Counter, Histogram, Gauge
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

ACTIVE_REQUESTS = Gauge(
    "http_requests_active",
    "Number of active HTTP requests"
)

AIRTABLE_API_CALLS = Counter(
    "airtable_api_calls_total",
    "Total Airtable API calls",
    ["operation", "base_id", "table_id", "status"]
)

AIRTABLE_API_DURATION = Histogram(
    "airtable_api_duration_seconds",
    "Airtable API call duration in seconds",
    ["operation"]
)

CACHE_HITS = Counter(
    "cache_hits_total",
    "Total cache hits",
    ["cache_type"]
)

CACHE_MISSES = Counter(
    "cache_misses_total",
    "Total cache misses",
    ["cache_type"]
)

WORKFLOW_EXECUTIONS = Counter(
    "workflow_executions_total",
    "Total workflow executions",
    ["workflow_id", "status"]
)

BACKGROUND_TASKS = Gauge(
    "background_tasks_active",
    "Number of active background tasks"
)


class MetricsMiddleware(BaseHTTPMiddleware):
    """Middleware for collecting Prometheus metrics."""
    
    def __init__(self, app):
        super().__init__(app)
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Collect metrics for each request."""
        
        # Get endpoint pattern (remove dynamic parts)
        endpoint = self._get_endpoint_pattern(request)
        method = request.method.upper()
        
        # Start timing
        start_time = time.time()
        
        # Increment active requests
        ACTIVE_REQUESTS.inc()
        
        try:
            # Process request
            response = await call_next(request)
            
            # Record metrics
            status_code = str(response.status_code)
            process_time = time.time() - start_time
            
            REQUEST_COUNT.labels(
                method=method,
                endpoint=endpoint,
                status_code=status_code
            ).inc()
            
            REQUEST_DURATION.labels(
                method=method,
                endpoint=endpoint
            ).observe(process_time)
            
            return response
            
        except Exception as e:
            # Record error metrics
            process_time = time.time() - start_time
            
            REQUEST_COUNT.labels(
                method=method,
                endpoint=endpoint,
                status_code="500"
            ).inc()
            
            REQUEST_DURATION.labels(
                method=method,
                endpoint=endpoint
            ).observe(process_time)
            
            raise
        
        finally:
            # Decrement active requests
            ACTIVE_REQUESTS.dec()
    
    def _get_endpoint_pattern(self, request: Request) -> str:
        """Extract endpoint pattern from request path."""
        path = request.url.path
        
        # Replace UUIDs and IDs with placeholders
        import re
        
        # Replace UUIDs
        path = re.sub(
            r'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
            '/{id}',
            path
        )
        
        # Replace Airtable IDs (app*, tbl*, rec*, etc.)
        path = re.sub(r'/(app|tbl|rec|viw|fld)[a-zA-Z0-9]{14}', r'/{\1_id}', path)
        
        # Replace other common ID patterns
        path = re.sub(r'/\d+', '/{id}', path)
        
        return path


# Utility functions for manual metric recording

def record_airtable_call(
    operation: str,
    duration: float,
    base_id: str = "",
    table_id: str = "",
    status: str = "success"
):
    """Record Airtable API call metrics."""
    AIRTABLE_API_CALLS.labels(
        operation=operation,
        base_id=base_id or "unknown",
        table_id=table_id or "unknown",
        status=status
    ).inc()
    
    AIRTABLE_API_DURATION.labels(operation=operation).observe(duration)


def record_cache_hit(cache_type: str = "redis"):
    """Record cache hit."""
    CACHE_HITS.labels(cache_type=cache_type).inc()


def record_cache_miss(cache_type: str = "redis"):
    """Record cache miss."""
    CACHE_MISSES.labels(cache_type=cache_type).inc()


def record_workflow_execution(workflow_id: str, status: str):
    """Record workflow execution."""
    WORKFLOW_EXECUTIONS.labels(workflow_id=workflow_id, status=status).inc()


def increment_background_tasks():
    """Increment background task counter."""
    BACKGROUND_TASKS.inc()


def decrement_background_tasks():
    """Decrement background task counter."""
    BACKGROUND_TASKS.dec()