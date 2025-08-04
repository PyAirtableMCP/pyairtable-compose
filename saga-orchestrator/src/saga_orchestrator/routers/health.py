"""Health check endpoints for SAGA orchestrator."""

import logging
from typing import Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from ..core.config import get_settings

logger = logging.getLogger(__name__)
router = APIRouter()


class HealthResponse(BaseModel):
    """Health check response model."""
    status: str
    version: str
    timestamp: str
    components: Dict[str, Any]


@router.get("/", response_model=HealthResponse)
async def health_check(request: Request) -> HealthResponse:
    """Basic health check endpoint."""
    settings = get_settings()
    
    components = {
        "saga_orchestrator": "healthy",
        "redis": "unknown",
        "database": "unknown",
        "event_bus": "unknown"
    }
    
    # Check Redis connection
    try:
        if hasattr(request.app.state, "redis"):
            await request.app.state.redis.ping()
            components["redis"] = "healthy"
    except Exception as e:
        logger.warning(f"Redis health check failed: {e}")
        components["redis"] = "unhealthy"
    
    # Check Database connection
    try:
        if hasattr(request.app.state, "event_store"):
            # Simple check - this could be improved
            components["database"] = "healthy"
    except Exception as e:
        logger.warning(f"Database health check failed: {e}")
        components["database"] = "unhealthy"
    
    # Check Event Bus
    try:
        if hasattr(request.app.state, "event_bus"):
            components["event_bus"] = "healthy"
    except Exception as e:
        logger.warning(f"Event bus health check failed: {e}")
        components["event_bus"] = "unhealthy"
    
    # Determine overall status
    status = "healthy" if all(
        comp in ["healthy", "unknown"] for comp in components.values()
    ) else "unhealthy"
    
    from datetime import datetime
    return HealthResponse(
        status=status,
        version=settings.version,
        timestamp=datetime.utcnow().isoformat(),
        components=components
    )


@router.get("/ready")
async def readiness_check(request: Request) -> Dict[str, str]:
    """Kubernetes readiness probe."""
    try:
        # Check critical dependencies
        if hasattr(request.app.state, "redis"):
            await request.app.state.redis.ping()
        
        return {"status": "ready"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail="Service not ready")


@router.get("/live")
async def liveness_check() -> Dict[str, str]:
    """Kubernetes liveness probe."""
    return {"status": "alive"}