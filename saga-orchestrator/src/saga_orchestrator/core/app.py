"""FastAPI application setup for SAGA Orchestrator service."""

import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import make_asgi_app

from ..event_bus.redis_event_bus import RedisEventBus
from ..routers import health, sagas, events, transactions
from ..saga_engine.orchestrator import SagaOrchestrator
from ..saga_engine.event_store import PostgreSQLEventStore
from ..persistence.postgres_repository import PostgresSagaRepository
from ..patterns.choreography import ChoreographyCoordinator
from ..patterns.orchestration import OrchestrationController
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
        # Test and initialize Redis client with retry logic
        redis_client = None
        for attempt in range(3):
            try:
                redis_client = get_redis_client(settings)
                await redis_client.ping()
                app.state.redis = redis_client
                logger.info("Redis connection established successfully")
                break
            except Exception as e:
                logger.warning(f"Redis connection attempt {attempt + 1} failed: {e}")
                if attempt == 2:
                    logger.error("Redis connection failed after 3 attempts. Service will start but Redis-dependent features will be disabled.")
                    redis_client = None
                    break
                await asyncio.sleep(2 ** attempt)  # Exponential backoff
        
        # Initialize Event Store with error handling
        event_store = None
        try:
            event_store = PostgreSQLEventStore(str(settings.database_url))
            # Test the connection
            test_events = await event_store.read_all_events(max_count=1)
            app.state.event_store = event_store
            logger.info("Event store initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize event store: {e}")
            # Create a dummy event store for graceful degradation
            app.state.event_store = None
        
        # Initialize PostgreSQL Repository with retry logic
        postgres_repository = None
        for attempt in range(3):
            try:
                import asyncpg
                connection_pool = await asyncpg.create_pool(
                    str(settings.database_url),
                    min_size=1,
                    max_size=5,
                    command_timeout=10
                )
                postgres_repository = PostgresSagaRepository(connection_pool)
                app.state.postgres_repository = postgres_repository
                logger.info("PostgreSQL repository initialized successfully")
                break
            except Exception as e:
                logger.warning(f"PostgreSQL connection attempt {attempt + 1} failed: {e}")
                if attempt == 2:
                    logger.warning("PostgreSQL connection failed after 3 attempts. Falling back to Redis-only mode.")
                    postgres_repository = None
                    break
                await asyncio.sleep(2 ** attempt)
        
        # Initialize Event Bus only if Redis is available
        event_bus = None
        if redis_client:
            try:
                event_bus = RedisEventBus(redis_client)
                await event_bus.start()
                app.state.event_bus = event_bus
                logger.info("Redis event bus started successfully")
            except Exception as e:
                logger.error(f"Failed to start Redis event bus: {e}")
                app.state.event_bus = None
        else:
            logger.warning("Redis not available, event bus will be disabled")
        
        # Initialize SAGA Orchestrator with available components
        saga_orchestrator = None
        if event_store and event_bus:
            try:
                saga_orchestrator = SagaOrchestrator(
                    event_store=event_store,
                    event_bus=event_bus,
                    redis_client=redis_client,
                    settings=settings,
                    postgres_repository=postgres_repository
                )
                app.state.saga_orchestrator = saga_orchestrator
                logger.info("SAGA Orchestrator initialized successfully")
            except Exception as e:
                logger.error(f"Failed to initialize SAGA Orchestrator: {e}")
                app.state.saga_orchestrator = None
        else:
            logger.warning("SAGA Orchestrator disabled due to missing dependencies (event store or event bus)")
            app.state.saga_orchestrator = None
        
        # Initialize Choreography Coordinator only if dependencies are available
        choreography_coordinator = None
        if event_store and event_bus:
            try:
                choreography_coordinator = ChoreographyCoordinator(event_store, event_bus)
                await choreography_coordinator.start()
                app.state.choreography_coordinator = choreography_coordinator
                logger.info("Choreography Coordinator initialized successfully")
            except Exception as e:
                logger.error(f"Failed to initialize Choreography Coordinator: {e}")
                app.state.choreography_coordinator = None
        else:
            logger.warning("Choreography Coordinator disabled due to missing dependencies")
            app.state.choreography_coordinator = None
        
        # Initialize Orchestration Controller only if dependencies are available
        orchestration_controller = None
        if event_store and event_bus:
            try:
                service_registry = {
                    "auth-service": settings.auth_service_url,
                    "user-service": settings.user_service_url,
                    "permission-service": settings.permission_service_url,
                    "notification-service": settings.notification_service_url,
                    "airtable-connector": settings.airtable_connector_url,
                    "schema-service": settings.schema_service_url,
                    "webhook-service": settings.webhook_service_url,
                    "data-sync-service": settings.data_sync_service_url,
                }
                orchestration_controller = OrchestrationController(
                    event_store=event_store,
                    event_bus=event_bus,
                    service_registry=service_registry
                )
                await orchestration_controller.start()
                app.state.orchestration_controller = orchestration_controller
                logger.info("Orchestration Controller initialized successfully")
            except Exception as e:
                logger.error(f"Failed to initialize Orchestration Controller: {e}")
                app.state.orchestration_controller = None
        else:
            logger.warning("Orchestration Controller disabled due to missing dependencies")
            app.state.orchestration_controller = None
        
        # Start event subscriptions only if saga orchestrator is available
        if saga_orchestrator:
            try:
                await saga_orchestrator.start_event_subscriptions()
                logger.info("SAGA event subscriptions started successfully")
            except Exception as e:
                logger.error(f"Failed to start SAGA event subscriptions: {e}")
        
        logger.info("SAGA Orchestrator service started successfully")
        
        yield
        
    except Exception as e:
        logger.error(f"Failed to start SAGA Orchestrator service: {e}")
        raise
    finally:
        logger.info("Shutting down SAGA Orchestrator service...")
        
        # Cleanup resources
        if hasattr(app.state, "event_bus") and app.state.event_bus is not None:
            try:
                await app.state.event_bus.stop()
                logger.info("Event bus stopped")
            except Exception as e:
                logger.error(f"Error stopping event bus: {e}")
        
        if hasattr(app.state, "redis") and app.state.redis is not None:
            try:
                await app.state.redis.close()
                logger.info("Redis connection closed")
            except Exception as e:
                logger.error(f"Error closing Redis connection: {e}")
                
        if hasattr(app.state, "postgres_repository") and app.state.postgres_repository is not None:
            try:
                await app.state.postgres_repository.pool.close()
                logger.info("PostgreSQL connection pool closed")
            except Exception as e:
                logger.error(f"Error closing PostgreSQL connection pool: {e}")
        
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
    
    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Include routers
    app.include_router(health.router, prefix="/health", tags=["Health"])
    app.include_router(sagas.router, prefix="/sagas", tags=["SAGAs"])
    app.include_router(events.router, prefix="/events", tags=["Events"])
    app.include_router(transactions.router, prefix="/api/v1/saga/transaction", tags=["Transactions"])
    
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