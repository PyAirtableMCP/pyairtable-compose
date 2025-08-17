"""
Production-ready monitoring middleware for PyAirtable services.
Provides Prometheus metrics, OpenTelemetry tracing, and health checks.
"""

import time
import logging
import traceback
from typing import Optional, Dict, Any, Callable
from functools import wraps
import os
import json

try:
    from prometheus_client import Counter, Histogram, Gauge, Info, start_http_server, generate_latest, CONTENT_TYPE_LATEST
    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    print("Warning: prometheus_client not available. Install with: pip install prometheus-client")

try:
    from opentelemetry import trace, metrics
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
    from opentelemetry.instrumentation.requests import RequestsInstrumentor
    from opentelemetry.instrumentation.urllib3 import URLLib3Instrumentor
    from opentelemetry.instrumentation.redis import RedisInstrumentor
    from opentelemetry.instrumentation.psycopg2 import Psycopg2Instrumentor
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.sdk.metrics import MeterProvider
    from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
    from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
    from opentelemetry.propagate import inject
    OTEL_AVAILABLE = True
except ImportError:
    OTEL_AVAILABLE = False
    print("Warning: OpenTelemetry not available. Install with: pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp")

logger = logging.getLogger(__name__)

class PyAirtableMonitoring:
    """
    Comprehensive monitoring solution for PyAirtable services.
    """
    
    def __init__(
        self,
        service_name: str,
        service_version: str = "1.0.0",
        enable_prometheus: bool = True,
        enable_otel: bool = True,
        prometheus_port: int = 8000,
        otel_endpoint: str = "http://otel-collector:4317",
    ):
        self.service_name = service_name
        self.service_version = service_version
        self.enable_prometheus = enable_prometheus and PROMETHEUS_AVAILABLE
        self.enable_otel = enable_otel and OTEL_AVAILABLE
        
        # Health check state
        self.health_checks: Dict[str, Callable] = {}
        self.is_ready = False
        self.startup_time = time.time()
        
        # Initialize monitoring systems
        if self.enable_prometheus:
            self._setup_prometheus()
        
        if self.enable_otel:
            self._setup_opentelemetry(otel_endpoint)
    
    def _setup_prometheus(self):
        """Setup Prometheus metrics."""
        # Service info
        self.service_info = Info('service_info', 'Information about the service')
        self.service_info.info({
            'version': self.service_version,
            'name': self.service_name,
            'python_version': os.sys.version
        })
        
        # HTTP Metrics
        self.http_requests_total = Counter(
            'http_requests_total',
            'Total HTTP requests',
            ['method', 'endpoint', 'status_code', 'service']
        )
        
        self.http_request_duration_seconds = Histogram(
            'http_request_duration_seconds',
            'HTTP request duration in seconds',
            ['method', 'endpoint', 'service']
        )
        
        self.http_request_size_bytes = Histogram(
            'http_request_size_bytes',
            'HTTP request size in bytes',
            ['method', 'endpoint', 'service']
        )
        
        self.http_response_size_bytes = Histogram(
            'http_response_size_bytes',
            'HTTP response size in bytes',
            ['method', 'endpoint', 'service']
        )
        
        # Application Metrics
        self.active_connections = Gauge(
            'active_connections_total',
            'Number of active connections',
            ['service', 'type']
        )
        
        self.database_operations_total = Counter(
            'database_operations_total',
            'Total database operations',
            ['operation', 'table', 'status', 'service']
        )
        
        self.cache_operations_total = Counter(
            'cache_operations_total',
            'Total cache operations',
            ['operation', 'status', 'service']
        )
        
        self.external_api_requests_total = Counter(
            'external_api_requests_total',
            'Total external API requests',
            ['api', 'endpoint', 'status_code', 'service']
        )
        
        self.queue_operations_total = Counter(
            'queue_operations_total',
            'Total queue operations',
            ['operation', 'queue', 'status', 'service']
        )
        
        # Business Metrics
        self.airtable_requests_total = Counter(
            'airtable_requests_total',
            'Total Airtable API requests',
            ['base_id', 'table_name', 'operation', 'status', 'service']
        )
        
        self.ai_processing_requests_total = Counter(
            'ai_processing_requests_total',
            'Total AI processing requests',
            ['model', 'operation', 'status', 'service']
        )
        
        self.saga_operations_total = Counter(
            'saga_operations_total',
            'Total SAGA operations',
            ['saga_type', 'step', 'status', 'service']
        )
        
        # Health Metrics
        self.health_check_status = Gauge(
            'health_check_status',
            'Health check status (1=healthy, 0=unhealthy)',
            ['check_name', 'service']
        )
        
        self.service_uptime_seconds = Gauge(
            'service_uptime_seconds',
            'Service uptime in seconds',
            ['service']
        )
        
        logger.info(f"Prometheus metrics initialized for {self.service_name}")
    
    def _setup_opentelemetry(self, otel_endpoint: str):
        """Setup OpenTelemetry tracing and metrics."""
        resource = Resource.create({
            SERVICE_NAME: self.service_name,
            SERVICE_VERSION: self.service_version,
            "deployment.environment": os.getenv("ENVIRONMENT", "development"),
            "service.namespace": "pyairtable"
        })
        
        # Setup tracing
        trace.set_tracer_provider(TracerProvider(resource=resource))
        tracer_provider = trace.get_tracer_provider()
        
        otlp_exporter = OTLPSpanExporter(endpoint=otel_endpoint)
        span_processor = BatchSpanProcessor(otlp_exporter)
        tracer_provider.add_span_processor(span_processor)
        
        self.tracer = trace.get_tracer(self.service_name, self.service_version)
        
        # Auto-instrument common libraries
        RequestsInstrumentor().instrument()
        URLLib3Instrumentor().instrument()
        RedisInstrumentor().instrument()
        Psycopg2Instrumentor().instrument()
        
        logger.info(f"OpenTelemetry initialized for {self.service_name}")
    
    def add_health_check(self, name: str, check_func: Callable[[], bool]):
        """Add a health check function."""
        self.health_checks[name] = check_func
    
    def mark_ready(self):
        """Mark the service as ready to serve traffic."""
        self.is_ready = True
        logger.info(f"Service {self.service_name} marked as ready")
    
    def get_health_status(self) -> Dict[str, Any]:
        """Get comprehensive health status."""
        status = {
            "service": self.service_name,
            "version": self.service_version,
            "status": "healthy" if self.is_ready else "starting",
            "timestamp": time.time(),
            "uptime_seconds": time.time() - self.startup_time,
            "checks": {}
        }
        
        overall_healthy = True
        
        for check_name, check_func in self.health_checks.items():
            try:
                is_healthy = check_func()
                status["checks"][check_name] = {
                    "status": "healthy" if is_healthy else "unhealthy",
                    "timestamp": time.time()
                }
                
                if not is_healthy:
                    overall_healthy = False
                
                # Update Prometheus metric
                if self.enable_prometheus:
                    self.health_check_status.labels(
                        check_name=check_name,
                        service=self.service_name
                    ).set(1 if is_healthy else 0)
                    
            except Exception as e:
                status["checks"][check_name] = {
                    "status": "error",
                    "error": str(e),
                    "timestamp": time.time()
                }
                overall_healthy = False
                
                if self.enable_prometheus:
                    self.health_check_status.labels(
                        check_name=check_name,
                        service=self.service_name
                    ).set(0)
        
        if not self.is_ready or not overall_healthy:
            status["status"] = "unhealthy"
        
        # Update uptime metric
        if self.enable_prometheus:
            self.service_uptime_seconds.labels(service=self.service_name).set(
                time.time() - self.startup_time
            )
        
        return status
    
    def instrument_http_request(self, func):
        """Decorator to instrument HTTP requests."""
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            method = kwargs.get('method', 'GET')
            endpoint = kwargs.get('endpoint', 'unknown')
            
            # Start OpenTelemetry span
            span = None
            if self.enable_otel:
                span = self.tracer.start_span(f"{method} {endpoint}")
                span.set_attribute("http.method", method)
                span.set_attribute("http.url", endpoint)
                span.set_attribute("service.name", self.service_name)
            
            try:
                result = func(*args, **kwargs)
                status_code = getattr(result, 'status_code', 200)
                
                # Record metrics
                if self.enable_prometheus:
                    self.http_requests_total.labels(
                        method=method,
                        endpoint=endpoint,
                        status_code=status_code,
                        service=self.service_name
                    ).inc()
                    
                    self.http_request_duration_seconds.labels(
                        method=method,
                        endpoint=endpoint,
                        service=self.service_name
                    ).observe(time.time() - start_time)
                
                # Update span
                if span:
                    span.set_attribute("http.status_code", status_code)
                    span.set_status(trace.Status(trace.StatusCode.OK))
                
                return result
                
            except Exception as e:
                status_code = 500
                
                # Record error metrics
                if self.enable_prometheus:
                    self.http_requests_total.labels(
                        method=method,
                        endpoint=endpoint,
                        status_code=status_code,
                        service=self.service_name
                    ).inc()
                
                # Update span with error
                if span:
                    span.set_attribute("http.status_code", status_code)
                    span.set_attribute("error", True)
                    span.set_attribute("error.message", str(e))
                    span.set_status(trace.Status(
                        trace.StatusCode.ERROR,
                        description=str(e)
                    ))
                
                raise
            
            finally:
                if span:
                    span.end()
        
        return wrapper
    
    def record_database_operation(self, operation: str, table: str, status: str):
        """Record database operation metrics."""
        if self.enable_prometheus:
            self.database_operations_total.labels(
                operation=operation,
                table=table,
                status=status,
                service=self.service_name
            ).inc()
    
    def record_cache_operation(self, operation: str, status: str):
        """Record cache operation metrics."""
        if self.enable_prometheus:
            self.cache_operations_total.labels(
                operation=operation,
                status=status,
                service=self.service_name
            ).inc()
    
    def record_external_api_request(self, api: str, endpoint: str, status_code: int):
        """Record external API request metrics."""
        if self.enable_prometheus:
            self.external_api_requests_total.labels(
                api=api,
                endpoint=endpoint,
                status_code=status_code,
                service=self.service_name
            ).inc()
    
    def record_airtable_request(self, base_id: str, table_name: str, operation: str, status: str):
        """Record Airtable-specific metrics."""
        if self.enable_prometheus:
            self.airtable_requests_total.labels(
                base_id=base_id,
                table_name=table_name,
                operation=operation,
                status=status,
                service=self.service_name
            ).inc()
    
    def get_metrics(self) -> str:
        """Get Prometheus metrics in text format."""
        if self.enable_prometheus:
            return generate_latest()
        return ""
    
    def create_span(self, name: str, **attributes):
        """Create a new OpenTelemetry span."""
        if self.enable_otel:
            span = self.tracer.start_span(name)
            for key, value in attributes.items():
                span.set_attribute(key, value)
            return span
        return None


# FastAPI middleware
def create_fastapi_middleware(monitoring: PyAirtableMonitoring):
    """Create FastAPI middleware for monitoring."""
    from fastapi import Request, Response
    from fastapi.middleware.base import BaseHTTPMiddleware
    
    class MonitoringMiddleware(BaseHTTPMiddleware):
        async def dispatch(self, request: Request, call_next):
            start_time = time.time()
            method = request.method
            path = request.url.path
            
            # Start span
            span = None
            if monitoring.enable_otel:
                span = monitoring.tracer.start_span(f"{method} {path}")
                span.set_attribute("http.method", method)
                span.set_attribute("http.url", str(request.url))
                span.set_attribute("http.scheme", request.url.scheme)
                span.set_attribute("http.host", request.url.hostname)
                span.set_attribute("service.name", monitoring.service_name)
            
            try:
                response = await call_next(request)
                status_code = response.status_code
                
                # Record metrics
                if monitoring.enable_prometheus:
                    monitoring.http_requests_total.labels(
                        method=method,
                        endpoint=path,
                        status_code=status_code,
                        service=monitoring.service_name
                    ).inc()
                    
                    monitoring.http_request_duration_seconds.labels(
                        method=method,
                        endpoint=path,
                        service=monitoring.service_name
                    ).observe(time.time() - start_time)
                
                # Update span
                if span:
                    span.set_attribute("http.status_code", status_code)
                    span.set_status(trace.Status(trace.StatusCode.OK))
                
                return response
                
            except Exception as e:
                status_code = 500
                
                # Record error metrics
                if monitoring.enable_prometheus:
                    monitoring.http_requests_total.labels(
                        method=method,
                        endpoint=path,
                        status_code=status_code,
                        service=monitoring.service_name
                    ).inc()
                
                # Update span with error
                if span:
                    span.set_attribute("http.status_code", status_code)
                    span.set_attribute("error", True)
                    span.set_attribute("error.message", str(e))
                    span.set_status(trace.Status(
                        trace.StatusCode.ERROR,
                        description=str(e)
                    ))
                
                raise
            
            finally:
                if span:
                    span.end()
    
    return MonitoringMiddleware


# Health check endpoints for FastAPI
def create_health_endpoints(monitoring: PyAirtableMonitoring):
    """Create health check endpoints for FastAPI."""
    from fastapi import APIRouter, Response
    from fastapi.responses import PlainTextResponse
    
    router = APIRouter()
    
    @router.get("/health")
    async def health():
        """Basic health check."""
        status = monitoring.get_health_status()
        if status["status"] == "healthy":
            return status
        else:
            return Response(
                content=json.dumps(status),
                status_code=503,
                media_type="application/json"
            )
    
    @router.get("/health/ready")
    async def ready():
        """Readiness check."""
        if monitoring.is_ready:
            return {"status": "ready", "service": monitoring.service_name}
        else:
            return Response(
                content=json.dumps({
                    "status": "not ready",
                    "service": monitoring.service_name
                }),
                status_code=503,
                media_type="application/json"
            )
    
    @router.get("/health/live")
    async def live():
        """Liveness check."""
        return {"status": "alive", "service": monitoring.service_name}
    
    @router.get("/metrics")
    async def metrics():
        """Prometheus metrics endpoint."""
        return PlainTextResponse(
            monitoring.get_metrics(),
            media_type="text/plain"
        )
    
    return router