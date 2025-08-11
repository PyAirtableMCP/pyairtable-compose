"""FastAPI application factory and configuration."""

from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import make_asgi_app

from .config import get_settings
from .logging import configure_logging, get_logger
from ..database.connection import create_database_pool, close_database_pool
from ..utils.redis_client import create_redis_pool, close_redis_pool
from ..middleware.auth import AuthenticationMiddleware
from ..middleware.logging import LoggingMiddleware
from ..middleware.metrics import MetricsMiddleware
from ..routers import (
    health,
    airtable,
    workflows,
    automation,
    business_logic,
    reports,
    dashboard,
)

logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan management."""
    settings = get_settings()
    
    # Configure logging
    configure_logging()
    logger.info("Starting Airtable Domain Service", version=settings.service_version)
    
    # Initialize database connection pool
    await create_database_pool()
    logger.info("Database connection pool initialized")
    
    # Initialize Redis connection pool
    await create_redis_pool()
    logger.info("Redis connection pool initialized")
    
    # Application is ready
    logger.info(
        "Application startup completed",
        service=settings.service_name,
        port=settings.port,
        environment=settings.environment
    )
    
    yield
    
    # Cleanup on shutdown
    logger.info("Starting application shutdown")
    
    # Close Redis connections
    await close_redis_pool()
    logger.info("Redis connections closed")
    
    # Close database connections
    await close_database_pool()
    logger.info("Database connections closed")
    
    logger.info("Application shutdown completed")


def create_application() -> FastAPI:
    """Create and configure FastAPI application."""
    settings = get_settings()
    
    app = FastAPI(
        title=settings.service_name,
        description=settings.description,
        version=settings.service_version,
        lifespan=lifespan,
        docs_url="/docs" if settings.is_development else None,
        redoc_url="/redoc" if settings.is_development else None,
        openapi_url="/openapi.json" if settings.is_development else None,
    )
    
    # Add middleware
    _configure_middleware(app, settings)
    
    # Add exception handlers
    _configure_exception_handlers(app)
    
    # Include routers
    _include_routers(app)
    
    # Add metrics endpoint if enabled
    if settings.observability.enable_metrics:
        metrics_app = make_asgi_app()
        app.mount("/metrics", metrics_app)
    
    return app


def _configure_middleware(app: FastAPI, settings) -> None:
    """Configure application middleware."""
    
    # Metrics middleware (should be first)
    if settings.observability.enable_metrics:
        app.add_middleware(MetricsMiddleware)
    
    # Logging middleware
    app.add_middleware(LoggingMiddleware)
    
    # Authentication middleware
    app.add_middleware(
        AuthenticationMiddleware,
        internal_api_key=settings.security.internal_api_key,
        jwt_secret_key=settings.security.jwt_secret_key,
        jwt_algorithm=settings.security.jwt_algorithm,
    )
    
    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=settings.cors_allow_credentials,
        allow_methods=settings.cors_allow_methods,
        allow_headers=settings.cors_allow_headers,
    )


def _configure_exception_handlers(app: FastAPI) -> None:
    """Configure global exception handlers."""
    
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        """Handle unexpected exceptions."""
        logger.error(
            "Unhandled exception occurred",
            exc_info=exc,
            path=request.url.path,
            method=request.method,
        )
        
        # Don't expose internal error details in production
        settings = get_settings()
        if settings.is_production:
            detail = "Internal server error"
        else:
            detail = str(exc)
        
        return JSONResponse(
            status_code=500,
            content={
                "error": "internal_server_error",
                "message": detail,
                "request_id": getattr(request.state, "request_id", None),
            }
        )
    
    @app.exception_handler(ValueError)
    async def value_error_handler(request: Request, exc: ValueError) -> JSONResponse:
        """Handle value errors as bad requests."""
        logger.warning(
            "Value error occurred",
            error=str(exc),
            path=request.url.path,
            method=request.method,
        )
        
        return JSONResponse(
            status_code=400,
            content={
                "error": "bad_request",
                "message": str(exc),
                "request_id": getattr(request.state, "request_id", None),
            }
        )


def _include_routers(app: FastAPI) -> None:
    """Include all API routers."""
    
    # Health check router (no prefix, always available)
    app.include_router(health.router, tags=["health"])
    
    # API v1 routers
    api_prefix = "/api/v1"
    
    # Airtable operations
    app.include_router(
        airtable.router,
        prefix=f"{api_prefix}/airtable",
        tags=["airtable"]
    )
    
    # Workflow management
    app.include_router(
        workflows.router,
        prefix=f"{api_prefix}/workflows",
        tags=["workflows"]
    )
    
    # Automation features
    app.include_router(
        automation.router,
        prefix=f"{api_prefix}/automation",
        tags=["automation"]
    )
    
    # Business logic operations
    app.include_router(
        business_logic.router,
        prefix=f"{api_prefix}/business-logic",
        tags=["business-logic"]
    )
    
    # Report generation
    app.include_router(
        reports.router,
        prefix=f"{api_prefix}/reports",
        tags=["reports"]
    )
    
    # Dashboard management
    app.include_router(
        dashboard.router,
        prefix=f"{api_prefix}/dashboards",
        tags=["dashboards"]
    )


# Create the application instance
app = create_application()


# Root endpoint
@app.get("/")
async def root():
    """Service information endpoint."""
    settings = get_settings()
    return {
        "service": settings.service_name,
        "version": settings.service_version,
        "description": settings.description,
        "environment": settings.environment,
        "status": "healthy"
    }


# Service info endpoint
@app.get("/info")
async def service_info():
    """Detailed service information endpoint."""
    settings = get_settings()
    return {
        "service": settings.service_name,
        "version": settings.service_version,
        "description": settings.description,
        "environment": settings.environment,
        "features": [
            "Airtable API Gateway",
            "Workflow Management",
            "Business Logic Engine",
            "Formula Evaluation & Validation",
            "Report Generation & Templates",
            "Dashboard & Real-time Analytics",
            "Automation & Scheduling",
            "Calculation Services",
            "Rule Engine",
            "Rate Limiting",
            "Response Caching",
            "Batch Operations",
            "Schema Introspection",
            "Real-time Processing",
            "Background Tasks",
        ],
        "endpoints": {
            "health": "/health",
            "metrics": "/metrics" if settings.observability.enable_metrics else None,
            "docs": "/docs" if settings.is_development else None,
            "airtable": "/api/v1/airtable",
            "workflows": "/api/v1/workflows",
            "automation": "/api/v1/automation",
            "business_logic": "/api/v1/business-logic",
            "reports": "/api/v1/reports",
            "dashboards": "/api/v1/dashboards",
        }
    }