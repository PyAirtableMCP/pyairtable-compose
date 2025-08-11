"""Health check endpoints."""

from datetime import datetime
from typing import Dict, Any

from fastapi import APIRouter, Depends
from sqlalchemy import text

from ..database.connection import get_session
from ..utils.redis_client import get_redis_client
from ..core.config import get_settings

router = APIRouter()


@router.get("/health")
async def health_check():
    """Basic health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "pyairtable-airtable-domain",
        "version": "1.0.0"
    }


@router.get("/health/detailed")
async def detailed_health_check():
    """Detailed health check with dependency status."""
    settings = get_settings()
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": settings.service_name,
        "version": settings.service_version,
        "environment": settings.environment,
        "dependencies": {}
    }
    
    # Check database connection
    try:
        async with get_session() as session:
            result = await session.execute(text("SELECT 1"))
            health_status["dependencies"]["database"] = {
                "status": "healthy",
                "response_time_ms": 0  # Could measure this
            }
    except Exception as e:
        health_status["dependencies"]["database"] = {
            "status": "unhealthy",
            "error": str(e)
        }
        health_status["status"] = "unhealthy"
    
    # Check Redis connection
    try:
        redis = get_redis_client()
        await redis.ping()
        health_status["dependencies"]["redis"] = {
            "status": "healthy",
            "response_time_ms": 0  # Could measure this
        }
    except Exception as e:
        health_status["dependencies"]["redis"] = {
            "status": "unhealthy",
            "error": str(e)
        }
        health_status["status"] = "unhealthy"
    
    return health_status


@router.get("/ready")
async def readiness_check():
    """Kubernetes readiness probe endpoint."""
    try:
        # Check critical dependencies
        async with get_session() as session:
            await session.execute(text("SELECT 1"))
        
        redis = get_redis_client()
        await redis.ping()
        
        return {"status": "ready"}
    except Exception:
        from fastapi import HTTPException
        raise HTTPException(status_code=503, detail="Service not ready")


@router.get("/live")
async def liveness_check():
    """Kubernetes liveness probe endpoint."""
    return {"status": "alive"}