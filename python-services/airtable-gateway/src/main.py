"""
airtable-gateway - Airtable API integration gateway
"""
import os
import sys
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

# Initialize OpenTelemetry before importing other modules
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..', 'shared'))
try:
    from telemetry import initialize_telemetry
    
    # Initialize telemetry for Airtable Gateway (Port 8002)
    tracer = initialize_telemetry(
        service_name="airtable-gateway",
        service_version="1.0.0",
        service_tier="integration",
        otlp_endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"),
        resource_attributes={
            "service.port": "8002",
            "service.type": "airtable-gateway",
            "service.layer": "api-integration"
        }
    )
    
    logging.info("OpenTelemetry initialized for airtable-gateway")
except ImportError as e:
    logging.warning(f"OpenTelemetry initialization failed: {e}")
    tracer = None

from routes import health

# App lifespan
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print(f"Starting airtable-gateway...")
    from dependencies import get_redis_client
    # Initialize Redis connection
    await get_redis_client()
    yield
    # Shutdown
    print(f"Shutting down airtable-gateway...")
    from dependencies import close_redis_client
    await close_redis_client()

# Create FastAPI app
app = FastAPI(
    title="airtable-gateway",
    description="Airtable API integration gateway",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware - SECURITY FIX: Remove wildcard origins
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "https://localhost:3000,https://127.0.0.1:3000").split(","),
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-API-Key", "X-Requested-With"],
)

# Security middleware - Add comprehensive security headers and protections
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..', 'shared'))
try:
    from security import add_security_middleware, add_rate_limiting
    from dependencies import get_redis_client
    
    # Add security headers middleware
    add_security_middleware(
        app, 
        environment=os.getenv("ENVIRONMENT", "development"),
        max_request_size=10 * 1024 * 1024  # 10MB
    )
    
    # Add rate limiting if Redis is available
    redis_client = None
    try:
        import redis.asyncio as redis
        redis_url = os.getenv("REDIS_URL")
        if redis_url:
            redis_client = redis.from_url(redis_url)
            add_rate_limiting(app, redis_client, default_rate_limit=100, auth_rate_limit=5)
    except Exception as redis_error:
        logging.warning(f"Redis not available for rate limiting: {redis_error}")
        
    logging.info("Security middleware initialized for airtable-gateway")
except ImportError as e:
    logging.warning(f"Security middleware initialization failed: {e}")

# Authentication middleware
from middleware.auth import AuthMiddleware
from config import get_settings
settings = get_settings()
app.add_middleware(AuthMiddleware, internal_api_key=settings.internal_api_key)

# Secure exception handler - Prevent information disclosure
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    # Log the actual error for debugging
    logger.error(f"Unhandled exception on {request.url.path}: {str(exc)}")
    
    # Return generic error message to prevent information disclosure
    is_development = os.getenv("ENVIRONMENT", "development").lower() == "development"
    
    if is_development:
        # Show detailed errors in development
        return JSONResponse(
            status_code=500,
            content={
                "error": "Internal server error",
                "detail": str(exc),
                "path": str(request.url.path)
            }
        )
    else:
        # Generic error message in production
        return JSONResponse(
            status_code=500,
            content={"error": "Internal server error"},
            headers={"X-Request-ID": request.headers.get("X-Request-ID", "unknown")}
        )

# Include routers
from routes.airtable import router as airtable_router
app.include_router(health.router, tags=["health"])
app.include_router(airtable_router)

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "airtable-gateway",
        "version": "1.0.0",
        "description": "Airtable API integration gateway"
    }

# Service info endpoint
@app.get("/api/v1/info")
async def info():
    from config import get_settings
    settings = get_settings()
    return {
        "service": settings.service_name,
        "version": settings.service_version,
        "description": "Airtable API integration gateway",
        "port": settings.port,
        "features": [
            "Rate limiting",
            "Response caching",
            "Batch operations",
            "Schema introspection"
        ]
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8002"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=os.getenv("ENV", "production") == "development"
    )
