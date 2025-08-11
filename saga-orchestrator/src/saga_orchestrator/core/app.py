"""FastAPI application setup for SAGA Orchestrator service."""

import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import make_asgi_app

from ..event_bus.redis_event_bus import RedisEventBus
from ..routers import health, sagas, events
from ..saga_engine.orchestrator import SagaOrchestrator
from ..saga_engine.event_store import PostgreSQLEventStore
from ..utils.redis_client import get_redis_client
from .config import get_settings, setup_logging

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan manager."""
    settings = get_settings()
    setup_logging(settings)
    
    logger.info("Starting SAGA Orchestrator service...")
    
    try:
        # Initialize Redis client
        redis_client = get_redis_client(settings)
        app.state.redis = redis_client
        
        # Initialize Event Store
        event_store = PostgreSQLEventStore(str(settings.database_url))
        app.state.event_store = event_store
        
        # Initialize Event Bus
        event_bus = RedisEventBus(redis_client)
        await event_bus.start()
        app.state.event_bus = event_bus
        
        # Initialize SAGA Orchestrator
        saga_orchestrator = SagaOrchestrator(
            event_store=event_store,
            event_bus=event_bus,
            redis_client=redis_client,
            settings=settings
        )
        app.state.saga_orchestrator = saga_orchestrator
        
        # Start event subscriptions
        await saga_orchestrator.start_event_subscriptions()
        
        logger.info("SAGA Orchestrator service started successfully")
        
        yield
        
    except Exception as e:
        logger.error(f"Failed to start SAGA Orchestrator service: {e}")
        raise
    finally:
        logger.info("Shutting down SAGA Orchestrator service...")
        
        # Cleanup resources
        if hasattr(app.state, "event_bus"):
            await app.state.event_bus.stop()
        
        if hasattr(app.state, "redis"):
            await app.state.redis.close()
        
        logger.info("SAGA Orchestrator service stopped")


def create_app() -> FastAPI:
    """Create and configure FastAPI application."""
    settings = get_settings()
    
    app = FastAPI(
        title=settings.app_name,
        version=settings.version,
        description="Production-ready SAGA Orchestrator for distributed transactions",
        lifespan=lifespan,
        docs_url="/docs" if settings.debug else None,
        redoc_url="/redoc" if settings.debug else None,
    )
    
    # CORS middleware - Enhanced for service-to-service communication
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
        allow_headers=[
            "Accept",
            "Accept-Language",
            "Content-Language",
            "Content-Type",
            "Authorization",
            "X-API-Key",
            "X-Request-ID",
            "X-Correlation-ID",
            "X-Service-Name",
            "X-Trace-ID",
            "Cache-Control",
            "Pragma",
        ],
        expose_headers=[
            "X-Request-ID",
            "X-Correlation-ID",
            "X-RateLimit-Limit",
            "X-RateLimit-Remaining",
            "X-RateLimit-Reset",
        ],
        max_age=600,  # 10 minutes preflight cache
    )
    
    # Include routers
    app.include_router(health.router, prefix="/health", tags=["Health"])
    app.include_router(sagas.router, prefix="/sagas", tags=["SAGAs"])
    app.include_router(events.router, prefix="/events", tags=["Events"])
    
    # Add metrics endpoint if enabled
    if settings.enable_metrics:
        metrics_app = make_asgi_app()
        app.mount("/metrics", metrics_app)
    
    # Global exception handler
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        """Handle unexpected exceptions."""
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error", "error": str(exc)}
        )
    
    return app