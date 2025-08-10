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
        if hasattr(request.app.state, "redis") and request.app.state.redis is not None:
            await request.app.state.redis.ping()
            components["redis"] = "healthy"
        else:
            components["redis"] = "disabled"
    except Exception as e:
        logger.warning(f"Redis health check failed: {e}")
        components["redis"] = "unhealthy"
    
    # Check Database connection
    try:
        if hasattr(request.app.state, "postgres_repository") and request.app.state.postgres_repository is not None:
            # Test database connection with a simple query
            async with request.app.state.postgres_repository.pool.acquire() as conn:
                await conn.fetchval("SELECT 1")
            components["database"] = "healthy"
        elif hasattr(request.app.state, "event_store") and request.app.state.event_store is not None:
            # Test event store connection
            await request.app.state.event_store.read_all_events(max_count=1)
            components["database"] = "healthy"
        else:
            components["database"] = "disabled"
    except Exception as e:
        logger.warning(f"Database health check failed: {e}")
        components["database"] = "unhealthy"
    
    # Check Event Bus
    try:
        if hasattr(request.app.state, "event_bus") and request.app.state.event_bus is not None:
            if request.app.state.event_bus.running:
                components["event_bus"] = "healthy"
            else:
                components["event_bus"] = "stopped"
        else:
            components["event_bus"] = "disabled"
    except Exception as e:
        logger.warning(f"Event bus health check failed: {e}")
        components["event_bus"] = "unhealthy"
    
    # Check SAGA Orchestrator
    try:
        if hasattr(request.app.state, "saga_orchestrator") and request.app.state.saga_orchestrator is not None:
            components["saga_orchestrator"] = "healthy"
        else:
            components["saga_orchestrator"] = "disabled"
    except Exception as e:
        logger.warning(f"SAGA orchestrator health check failed: {e}")
        components["saga_orchestrator"] = "unhealthy"
    
    # Determine overall status
    # Service is healthy if critical components are working or gracefully disabled
    healthy_states = ["healthy", "unknown", "disabled", "stopped"]
    unhealthy_states = ["unhealthy"]
    
    critical_components = ["saga_orchestrator"]  # At least saga orchestrator should be working
    critical_healthy = all(
        components.get(comp) in healthy_states for comp in critical_components
    )
    
    # Service is healthy if no components are explicitly unhealthy and critical components are okay
    has_unhealthy = any(comp == "unhealthy" for comp in components.values())
    status = "healthy" if critical_healthy and not has_unhealthy else "degraded"
    
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
        # Check if service can handle requests (basic functionality test)
        service_functional = True
        
        # Optional Redis check - not required for basic functionality
        redis_available = False
        if hasattr(request.app.state, "redis") and request.app.state.redis is not None:
            try:
                await request.app.state.redis.ping()
                redis_available = True
            except Exception:
                logger.debug("Redis not available during readiness check")
        
        # The service can be ready even without Redis/PostgreSQL in degraded mode
        # as long as it can accept HTTP requests
        if service_functional:
            return {
                "status": "ready",
                "redis_available": str(redis_available).lower(),
                "mode": "full" if redis_available else "degraded"
            }
        else:
            raise HTTPException(status_code=503, detail="Service not ready")
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail=f"Service not ready: {str(e)}")


@router.get("/live")
async def liveness_check() -> Dict[str, str]:
    """Kubernetes liveness probe."""
    return {"status": "alive"}