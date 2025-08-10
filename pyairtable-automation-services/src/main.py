import logging
import sys
import os
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Initialize OpenTelemetry (optional, fallback gracefully if not available)
tracer = None
try:
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
    from opentelemetry.instrumentation.redis import RedisInstrumentor
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.sdk.resources import Resource
    
    # Configure resource
    resource = Resource.create({
        "service.name": "automation-services",
        "service.version": "1.0.0",
        "service.port": "8006",
        "service.type": "automation-services",
        "service.layer": "workflow-processing"
    })
    
    # Set up tracer provider
    trace.set_tracer_provider(TracerProvider(resource=resource))
    tracer = trace.get_tracer(__name__)
    
    # Configure OTLP exporter if endpoint is available
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if otlp_endpoint:
        otlp_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
        span_processor = BatchSpanProcessor(otlp_exporter)
        trace.get_tracer_provider().add_span_processor(span_processor)
    
    logging.info("OpenTelemetry initialized for automation-services")
except ImportError as e:
    logging.warning(f"OpenTelemetry not available, skipping telemetry setup: {e}")
except Exception as e:
    logging.warning(f"OpenTelemetry initialization failed: {e}")

from .config import Settings
from .database import Base, get_database_url, create_tables
from .routes import files, workflows, health, templates
from .services.scheduler import WorkflowScheduler
from .utils.redis_client import init_redis

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

settings = Settings()

# Global scheduler instance
scheduler = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    global scheduler
    
    # Startup
    logger.info("Starting PyAirtable Automation Services...")
    
    # Initialize database
    try:
        create_tables()
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.error(f"Database initialization failed: {str(e)}")
        raise
    
    # Initialize Redis (with retry logic)
    redis_retry_count = 0
    max_redis_retries = 5
    while redis_retry_count < max_redis_retries:
        try:
            await init_redis()
            logger.info("Redis initialized successfully")
            break
        except Exception as e:
            redis_retry_count += 1
            logger.warning(f"Redis initialization attempt {redis_retry_count} failed: {str(e)}")
            if redis_retry_count >= max_redis_retries:
                logger.error("Failed to initialize Redis after maximum retries")
                raise
            await asyncio.sleep(2)  # Wait before retry
    
    # Start workflow scheduler
    try:
        scheduler = WorkflowScheduler()
        await scheduler.start()
        logger.info("Workflow scheduler started successfully")
    except Exception as e:
        logger.error(f"Failed to start workflow scheduler: {str(e)}")
        raise
    
    yield
    
    # Shutdown
    logger.info("Shutting down PyAirtable Automation Services...")
    
    # Stop workflow scheduler
    if scheduler:
        try:
            await scheduler.stop()
            logger.info("Workflow scheduler stopped")
        except Exception as e:
            logger.error(f"Error stopping scheduler: {str(e)}")
    
    # Close Redis connections
    try:
        from .utils.redis_client import close_redis
        await close_redis()
        logger.info("Redis connections closed")
    except Exception as e:
        logger.error(f"Error closing Redis connections: {str(e)}")
    
    logger.info("Graceful shutdown completed")

# Create FastAPI app
app = FastAPI(
    title="PyAirtable Automation Services",
    description="Unified file processing and workflow automation service",
    version="1.0.0",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(files.router, prefix="/api/v1/files", tags=["files"])
app.include_router(workflows.router, prefix="/api/v1/workflows", tags=["workflows"])
app.include_router(templates.router, prefix="/api/v1/templates", tags=["templates"])
app.include_router(health.router, tags=["health"])

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "PyAirtable Automation Services",
        "version": "1.0.0",
        "description": "Unified file processing and workflow automation",
        "endpoints": {
            "files": "/api/v1/files",
            "file_upload": "/api/v1/files/upload",
            "multiple_upload": "/api/v1/files/upload-multiple", 
            "file_download": "/api/v1/files/{file_id}/download",
            "file_convert": "/api/v1/files/{file_id}/convert",
            "image_optimize": "/api/v1/files/{file_id}/optimize-image",
            "image_resize": "/api/v1/files/{file_id}/resize-image",
            "workflows": "/api/v1/workflows", 
            "executions": "/api/v1/workflows/executions",
            "templates": "/api/v1/templates",
            "health": "/health"
        },
        "features": [
            "Single and multiple file upload",
            "File download with secure paths", 
            "Virus scanning (placeholder)",
            "Image processing (thumbnails, resize, optimize)",
            "Document conversion (PDF, Office formats)",
            "Content extraction and indexing",
            "Workflow automation triggers",
            "File type validation and security"
        ]
    }

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Global exception in {request.url}: {str(exc)}", exc_info=True)
    
    # Don't wrap HTTPException in another HTTPException
    if isinstance(exc, HTTPException):
        return exc
    
    return HTTPException(
        status_code=500,
        detail={
            "error": "Internal server error",
            "message": "An unexpected error occurred",
            "service": "automation-services"
        }
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=settings.port,
        reload=settings.debug
    )