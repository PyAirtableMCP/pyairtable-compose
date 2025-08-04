"""FastAPI application factory for AI domain service"""
import time
from contextlib import asynccontextmanager
from typing import Dict, Any

from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from prometheus_client import Counter, Histogram, generate_latest
import uvicorn

from .config import get_settings
from .logging import setup_logging, get_logger
from ..database.connection import init_db, close_db
from ..utils.redis_client import init_redis, close_redis


# Metrics
REQUEST_COUNT = Counter(
    "ai_service_requests_total", 
    "Total requests", 
    ["method", "endpoint", "status"]
)
REQUEST_DURATION = Histogram(
    "ai_service_request_duration_seconds", 
    "Request duration"
)
LLM_REQUESTS = Counter(
    "llm_requests_total",
    "Total LLM requests",
    ["provider", "model"]
)
TOKEN_USAGE = Counter(
    "token_usage_total",
    "Total tokens used",
    ["provider", "model", "type"]
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan management"""
    logger = get_logger(__name__)
    settings = get_settings()
    
    # Startup
    logger.info("Starting AI domain service", version=settings.service_version)
    
    # Initialize dependencies
    await init_db()
    await init_redis()
    
    # Initialize AI services
    from ..services.llm.provider_manager import LLMProviderManager
    from ..services.models.model_manager import ModelManager
    from ..services.mcp.tool_registry import ToolRegistry
    
    provider_manager = LLMProviderManager()
    model_manager = ModelManager()
    tool_registry = ToolRegistry()
    
    # Store in app state
    app.state.provider_manager = provider_manager
    app.state.model_manager = model_manager
    app.state.tool_registry = tool_registry
    
    logger.info("AI domain service started successfully")
    
    yield
    
    # Shutdown
    logger.info("Shutting down AI domain service")
    await close_redis()
    await close_db()
    
    if hasattr(app.state, "provider_manager"):
        await app.state.provider_manager.close()
    if hasattr(app.state, "model_manager"):
        await app.state.model_manager.close()
    
    logger.info("AI domain service shutdown complete")


def create_app() -> FastAPI:
    """Create and configure FastAPI application"""
    settings = get_settings()
    
    # Setup logging
    setup_logging()
    logger = get_logger(__name__)
    
    # Create FastAPI app
    app = FastAPI(
        title="PyAirtable AI Domain Service",
        description="Consolidated AI service for LLM orchestration, model serving, and MCP tools",
        version=settings.service_version,
        lifespan=lifespan,
        debug=settings.debug,
    )
    
    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Configure appropriately for production
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Request middleware for metrics and logging
    @app.middleware("http")
    async def request_middleware(request: Request, call_next):
        start_time = time.time()
        
        # Process request
        response = await call_next(request)
        
        # Calculate duration
        duration = time.time() - start_time
        
        # Record metrics
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.url.path,
            status=response.status_code
        ).inc()
        REQUEST_DURATION.observe(duration)
        
        # Log request
        logger.info(
            "request_completed",
            method=request.method,
            path=request.url.path,
            status=response.status_code,
            duration_ms=duration * 1000,
            user_agent=request.headers.get("user-agent", "unknown")
        )
        
        return response
    
    # Global exception handler
    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        logger.error(
            "unhandled_exception",
            path=request.url.path,
            method=request.method,
            error=str(exc),
            exc_info=True
        )
        
        if isinstance(exc, HTTPException):
            return JSONResponse(
                status_code=exc.status_code,
                content={"detail": exc.detail}
            )
        
        return JSONResponse(
            status_code=500,
            content={
                "detail": "Internal server error",
                "error_id": f"err_{int(time.time())}"
            }
        )
    
    # Include routers
    from ..routers import health
    from ..routers.llm import chat, completions, embeddings
    from ..routers.mcp import tools
    from ..routers.models import models
    
    app.include_router(health.router, tags=["health"])
    app.include_router(chat.router, prefix="/api/v1/llm", tags=["llm", "chat"])
    app.include_router(completions.router, prefix="/api/v1/llm", tags=["llm", "completions"])
    app.include_router(embeddings.router, prefix="/api/v1/llm", tags=["llm", "embeddings"])
    app.include_router(tools.router, prefix="/api/v1/mcp", tags=["mcp", "tools"])
    app.include_router(models.router, prefix="/api/v1/models", tags=["models"])
    
    # Root endpoint
    @app.get("/")
    async def root():
        return {
            "service": settings.service_name,
            "version": settings.service_version,
            "description": "Consolidated AI service for LLM orchestration, model serving, and MCP tools",
            "features": [
                "Multi-provider LLM support",
                "Real-time chat completions",
                "Embedding generation",
                "Vector search",
                "MCP tool execution",
                "Model serving",
                "Cost tracking",
                "Performance monitoring"
            ],
            "providers": settings.available_providers
        }
    
    # Service info endpoint
    @app.get("/api/v1/info")
    async def service_info():
        return {
            "service": settings.service_name,
            "version": settings.service_version,
            "port": settings.port,
            "providers": settings.available_providers,
            "features": {
                "streaming": settings.enable_streaming,
                "function_calling": settings.enable_function_calling,
                "multi_modal": settings.enable_multi_modal,
                "cost_tracking": settings.enable_cost_tracking,
                "response_caching": settings.enable_response_caching
            },
            "limits": {
                "max_tokens": settings.max_tokens,
                "max_prompt_tokens": settings.max_prompt_tokens,
                "rate_limit_rpm": settings.rate_limit_requests_per_minute
            }
        }
    
    # Metrics endpoint
    @app.get("/metrics")
    async def metrics():
        return Response(
            generate_latest(),
            media_type="text/plain"
        )
    
    return app


def main():
    """Main entry point"""
    settings = get_settings()
    uvicorn.run(
        "src.core.app:create_app",
        factory=True,
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
        log_level=settings.log_level.lower(),
    )