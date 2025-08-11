"""Health check endpoints."""

from datetime import datetime
from typing import Dict, Any

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.config import get_settings
from ..core.logging import get_logger
from ..database.connection import get_session
from ..utils.redis_client import get_redis_client

router = APIRouter()
logger = get_logger(__name__)


@router.get("/health")
async def health_check() -> Dict[str, Any]:
    """Basic health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "automation-domain"
    }


@router.get("/health/detailed")
async def detailed_health_check(
    db: AsyncSession = Depends(get_session)
) -> Dict[str, Any]:
    """Detailed health check with dependency validation."""
    settings = get_settings()
    health_data = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "automation-domain",
        "version": settings.service_version,
        "environment": settings.environment,
        "checks": {}
    }
    
    # Database check
    try:
        await db.execute("SELECT 1")
        health_data["checks"]["database"] = {"status": "healthy"}
    except Exception as e:
        logger.error("Database health check failed", error=str(e))
        health_data["checks"]["database"] = {
            "status": "unhealthy",
            "error": str(e)
        }
        health_data["status"] = "unhealthy"
    
    # Redis check
    try:
        redis_client = get_redis_client()
        await redis_client.ping()
        health_data["checks"]["redis"] = {"status": "healthy"}
    except Exception as e:
        logger.error("Redis health check failed", error=str(e))
        health_data["checks"]["redis"] = {
            "status": "unhealthy",
            "error": str(e)
        }
        health_data["status"] = "unhealthy"
    
    # Celery check (basic)
    try:
        from ..workers.celery_app import get_celery_app
        celery_app = get_celery_app()
        # Simple check - if app exists and has config
        if celery_app and celery_app.conf:
            health_data["checks"]["celery"] = {"status": "healthy"}
        else:
            health_data["checks"]["celery"] = {
                "status": "unhealthy",
                "error": "Celery app not properly configured"
            }
            health_data["status"] = "unhealthy"
    except Exception as e:
        logger.error("Celery health check failed", error=str(e))
        health_data["checks"]["celery"] = {
            "status": "unhealthy",
            "error": str(e)
        }
        health_data["status"] = "unhealthy"
    
    if health_data["status"] == "unhealthy":
        raise HTTPException(status_code=503, detail=health_data)
    
    return health_data


@router.get("/ready")
async def readiness_check() -> Dict[str, Any]:
    """Readiness check for Kubernetes."""
    # This endpoint should return 200 when the service is ready to handle traffic
    return {
        "status": "ready",
        "timestamp": datetime.utcnow().isoformat()
    }


@router.get("/live")
async def liveness_check() -> Dict[str, Any]:
    """Liveness check for Kubernetes."""
    # This endpoint should return 200 when the service is alive
    return {
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat()
    }