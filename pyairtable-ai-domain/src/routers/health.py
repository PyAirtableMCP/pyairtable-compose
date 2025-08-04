"""Health check endpoints"""
from datetime import datetime
from typing import Dict, Any

from fastapi import APIRouter, Request
from pydantic import BaseModel

from ..core.config import get_settings
from ..utils.redis_client import get_redis_client


router = APIRouter()


class HealthResponse(BaseModel):
    """Health check response model"""
    status: str
    service: str
    version: str
    timestamp: str
    checks: Dict[str, Any]


@router.get("/health", response_model=HealthResponse)
async def health_check(request: Request):
    """Health check endpoint"""
    settings = get_settings()
    checks = {}
    overall_status = "healthy"
    
    # Check Redis connection
    try:
        redis_client = await get_redis_client()
        if redis_client:
            await redis_client.ping()
            checks["redis"] = {"status": "healthy", "message": "Connected"}
        else:
            checks["redis"] = {"status": "unavailable", "message": "Not configured"}
    except Exception as e:
        checks["redis"] = {"status": "unhealthy", "error": str(e)}
        overall_status = "degraded"
    
    # Check database connection (if needed)
    checks["database"] = {"status": "not_checked", "message": "Database check not implemented"}
    
    # Check LLM providers
    if hasattr(request.app.state, "provider_manager"):
        try:
            provider_health = await request.app.state.provider_manager.get_provider_health()
            checks["llm_providers"] = provider_health
            
            # Check if any providers are unhealthy
            unhealthy_providers = [
                name for name, health in provider_health.items()
                if health.get("status") == "unhealthy"
            ]
            if unhealthy_providers:
                overall_status = "degraded"
        except Exception as e:
            checks["llm_providers"] = {"status": "error", "error": str(e)}
            overall_status = "degraded"
    else:
        checks["llm_providers"] = {"status": "not_initialized"}
    
    # Check model manager
    if hasattr(request.app.state, "model_manager"):
        try:
            model_health = await request.app.state.model_manager.health_check()
            checks["model_manager"] = model_health
        except Exception as e:
            checks["model_manager"] = {"status": "error", "error": str(e)}
            overall_status = "degraded"
    else:
        checks["model_manager"] = {"status": "not_initialized"}
    
    # Check tool registry
    if hasattr(request.app.state, "tool_registry"):
        try:
            tool_health = await request.app.state.tool_registry.health_check()
            checks["tool_registry"] = tool_health
        except Exception as e:
            checks["tool_registry"] = {"status": "error", "error": str(e)}
            overall_status = "degraded"
    else:
        checks["tool_registry"] = {"status": "not_initialized"}
    
    return HealthResponse(
        status=overall_status,
        service=settings.service_name,
        version=settings.service_version,
        timestamp=datetime.utcnow().isoformat(),
        checks=checks
    )


@router.get("/health/ready")
async def readiness_check(request: Request):
    """Readiness check for Kubernetes"""
    # Check critical dependencies
    critical_checks = []
    
    # Check if core services are initialized
    if not hasattr(request.app.state, "provider_manager"):
        critical_checks.append("LLM Provider Manager not initialized")
    
    if not hasattr(request.app.state, "model_manager"):
        critical_checks.append("Model Manager not initialized")
    
    if not hasattr(request.app.state, "tool_registry"):
        critical_checks.append("Tool Registry not initialized")
    
    if critical_checks:
        return {"ready": False, "issues": critical_checks}, 503
    
    return {"ready": True, "timestamp": datetime.utcnow().isoformat()}


@router.get("/health/live")
async def liveness_check():
    """Liveness check for Kubernetes"""
    return {
        "alive": True,
        "timestamp": datetime.utcnow().isoformat()
    }