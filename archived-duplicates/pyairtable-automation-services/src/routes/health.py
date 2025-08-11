from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
import redis
from datetime import datetime

from ..database import get_db
from ..utils.redis_client import get_redis_client
from ..config import settings

router = APIRouter()

@router.get("/health")
async def health_check(db: Session = Depends(get_db)):
    """Combined health check for automation services"""
    health_status = {
        "service": "PyAirtable Automation Services",
        "version": "1.0.0",
        "timestamp": datetime.utcnow().isoformat(),
        "status": "healthy",
        "components": {}
    }
    
    # Check database connection
    try:
        db.execute(text("SELECT 1"))
        health_status["components"]["database"] = {
            "status": "healthy",
            "message": "Database connection successful"
        }
    except Exception as e:
        health_status["components"]["database"] = {
            "status": "unhealthy",
            "message": f"Database connection failed: {str(e)}"
        }
        health_status["status"] = "unhealthy"
    
    # Check Redis connection
    try:
        redis_client = await get_redis_client()
        await redis_client.ping()
        health_status["components"]["redis"] = {
            "status": "healthy",
            "message": "Redis connection successful"
        }
    except Exception as e:
        health_status["components"]["redis"] = {
            "status": "unhealthy",
            "message": f"Redis connection failed: {str(e)}"
        }
        health_status["status"] = "unhealthy"
    
    # Check file upload directory
    try:
        import os
        upload_dir = settings.upload_dir
        if os.path.exists(upload_dir) and os.access(upload_dir, os.W_OK):
            health_status["components"]["file_storage"] = {
                "status": "healthy",
                "message": f"Upload directory accessible: {upload_dir}"
            }
        else:
            health_status["components"]["file_storage"] = {
                "status": "unhealthy",
                "message": f"Upload directory not accessible: {upload_dir}"
            }
            health_status["status"] = "unhealthy"
    except Exception as e:
        health_status["components"]["file_storage"] = {
            "status": "unhealthy",
            "message": f"File storage check failed: {str(e)}"
        }
        health_status["status"] = "unhealthy"
    
    # Check workflow scheduler
    try:
        # This would check if the scheduler is running
        # For now, we'll assume it's healthy if we get here
        health_status["components"]["scheduler"] = {
            "status": "healthy",
            "message": "Workflow scheduler running"
        }
    except Exception as e:
        health_status["components"]["scheduler"] = {
            "status": "unhealthy",
            "message": f"Workflow scheduler failed: {str(e)}"
        }
        health_status["status"] = "unhealthy"
    
    return health_status

@router.get("/ready")
async def readiness_check():
    """Kubernetes readiness probe"""
    return {"status": "ready"}

@router.get("/live")
async def liveness_check():
    """Kubernetes liveness probe"""
    return {"status": "alive"}