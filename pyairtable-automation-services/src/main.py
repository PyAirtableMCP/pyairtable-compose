import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from .config import Settings
from .database import Base, get_database_url
from .routes import files, workflows, health
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
    engine = create_engine(get_database_url())
    Base.metadata.create_all(bind=engine)
    logger.info("Database initialized")
    
    # Initialize Redis
    await init_redis()
    logger.info("Redis initialized")
    
    # Start workflow scheduler
    scheduler = WorkflowScheduler()
    await scheduler.start()
    logger.info("Workflow scheduler started")
    
    yield
    
    # Shutdown
    logger.info("Shutting down PyAirtable Automation Services...")
    if scheduler:
        await scheduler.stop()
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
app.include_router(files.router, prefix="/files", tags=["files"])
app.include_router(workflows.router, prefix="/workflows", tags=["workflows"])
app.include_router(health.router, tags=["health"])

# Root endpoint
@app.get("/")
async def root():
    return {
        "service": "PyAirtable Automation Services",
        "version": "1.0.0",
        "description": "Unified file processing and workflow automation",
        "endpoints": {
            "files": "/files",
            "workflows": "/workflows", 
            "executions": "/executions",
            "health": "/health"
        }
    }

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Global exception: {str(exc)}", exc_info=True)
    return HTTPException(
        status_code=500,
        detail="Internal server error"
    )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=settings.port,
        reload=settings.debug
    )