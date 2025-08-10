"""Monitoring and health check endpoints for MCP Server"""
import asyncio
import time
from typing import Dict, Any, List
from datetime import datetime, timedelta

import httpx
from fastapi import APIRouter, Depends, HTTPException
from redis import asyncio as aioredis

from ..config import get_settings
from ..dependencies import get_tool_executor, get_redis_client
from ..services.enhanced_tool_executor import EnhancedToolExecutor

router = APIRouter(prefix="/health", tags=["monitoring"])


@router.get("/")
async def health_check():
    """Basic health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service": "mcp-server",
        "version": "1.0.0"
    }


@router.get("/ready")
async def readiness_check(
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    redis_client: aioredis.Redis = Depends(get_redis_client)
):
    """Readiness check - verifies all dependencies are available"""
    checks = {}
    overall_status = "ready"
    
    # Check Redis connection
    try:
        if redis_client:
            await redis_client.ping()
            checks["redis"] = {"status": "healthy", "latency_ms": None}
        else:
            checks["redis"] = {"status": "disabled", "message": "Redis not configured"}
    except Exception as e:
        checks["redis"] = {"status": "unhealthy", "error": str(e)}
        overall_status = "not_ready"
    
    # Check Airtable Gateway connection
    settings = get_settings()
    try:
        start_time = time.time()
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{settings.airtable_gateway_url}/health")
            latency_ms = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                checks["airtable_gateway"] = {"status": "healthy", "latency_ms": latency_ms}
            else:
                checks["airtable_gateway"] = {"status": "unhealthy", "status_code": response.status_code}
                overall_status = "not_ready"
    except Exception as e:
        checks["airtable_gateway"] = {"status": "unhealthy", "error": str(e)}
        overall_status = "not_ready"
    
    # Check tool executor
    try:
        # Simple test to ensure executor is initialized
        metrics = await executor.get_metrics()
        checks["tool_executor"] = {"status": "healthy", "tools_loaded": len(metrics) if metrics else 0}
    except Exception as e:
        checks["tool_executor"] = {"status": "unhealthy", "error": str(e)}
        overall_status = "not_ready"
    
    return {
        "status": overall_status,
        "timestamp": datetime.utcnow().isoformat(),
        "checks": checks
    }


@router.get("/live")
async def liveness_check():
    """Liveness check - basic service availability"""
    try:
        # Simple check to ensure the service is responding
        current_time = datetime.utcnow()
        return {
            "status": "alive",
            "timestamp": current_time.isoformat(),
            "uptime_seconds": time.time()  # This would be more accurate with actual start time
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Service unavailable: {str(e)}")


@router.get("/detailed")
async def detailed_health_check(
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    redis_client: aioredis.Redis = Depends(get_redis_client)
):
    """Comprehensive health check with detailed information"""
    settings = get_settings()
    health_info = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "service_info": {
            "name": settings.service_name,
            "version": settings.service_version,
            "port": settings.port,
            "mode": settings.mcp_mode
        },
        "dependencies": {},
        "metrics": {},
        "configuration": {
            "caching_enabled": settings.enable_caching,
            "metrics_enabled": settings.enable_metrics,
            "tracing_enabled": settings.enable_tracing,
            "rate_limiting": {
                "requests_per_hour": settings.rate_limit_requests,
                "window_seconds": settings.rate_limit_window
            }
        }
    }
    
    overall_healthy = True
    
    # Redis health check
    if redis_client:
        try:
            start_time = time.time()
            await redis_client.ping()
            latency_ms = (time.time() - start_time) * 1000
            
            # Get Redis info
            info = await redis_client.info()
            health_info["dependencies"]["redis"] = {
                "status": "healthy",
                "latency_ms": round(latency_ms, 2),
                "version": info.get("redis_version"),
                "connected_clients": info.get("connected_clients"),
                "used_memory_human": info.get("used_memory_human"),
                "uptime_in_seconds": info.get("uptime_in_seconds")
            }
        except Exception as e:
            health_info["dependencies"]["redis"] = {
                "status": "unhealthy",
                "error": str(e)
            }
            overall_healthy = False
    else:
        health_info["dependencies"]["redis"] = {
            "status": "disabled",
            "message": "Redis not configured"
        }
    
    # Airtable Gateway health check
    try:
        start_time = time.time()
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(f"{settings.airtable_gateway_url}/health")
            latency_ms = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                health_info["dependencies"]["airtable_gateway"] = {
                    "status": "healthy",
                    "latency_ms": round(latency_ms, 2),
                    "url": settings.airtable_gateway_url
                }
            else:
                health_info["dependencies"]["airtable_gateway"] = {
                    "status": "unhealthy",
                    "status_code": response.status_code,
                    "url": settings.airtable_gateway_url
                }
                overall_healthy = False
    except Exception as e:
        health_info["dependencies"]["airtable_gateway"] = {
            "status": "unhealthy",
            "error": str(e),
            "url": settings.airtable_gateway_url
        }
        overall_healthy = False
    
    # LLM Orchestrator health check
    try:
        start_time = time.time()
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(f"{settings.llm_orchestrator_url}/health")
            latency_ms = (time.time() - start_time) * 1000
            
            if response.status_code == 200:
                health_info["dependencies"]["llm_orchestrator"] = {
                    "status": "healthy",
                    "latency_ms": round(latency_ms, 2),
                    "url": settings.llm_orchestrator_url
                }
            else:
                health_info["dependencies"]["llm_orchestrator"] = {
                    "status": "unhealthy",
                    "status_code": response.status_code,
                    "url": settings.llm_orchestrator_url
                }
                # Don't mark overall as unhealthy for LLM orchestrator
    except Exception as e:
        health_info["dependencies"]["llm_orchestrator"] = {
            "status": "unhealthy",
            "error": str(e),
            "url": settings.llm_orchestrator_url
        }
    
    # Get execution metrics
    try:
        metrics = await executor.get_metrics()
        
        # Aggregate metrics
        total_calls = sum(m.total_calls for m in metrics.values())
        total_successful = sum(m.successful_calls for m in metrics.values())
        total_failed = sum(m.failed_calls for m in metrics.values())
        
        health_info["metrics"] = {
            "total_tool_calls": total_calls,
            "successful_calls": total_successful,
            "failed_calls": total_failed,
            "success_rate": round((total_successful / total_calls * 100) if total_calls > 0 else 0, 2),
            "tools_with_metrics": len(metrics),
            "most_used_tool": max(metrics.keys(), key=lambda k: metrics[k].total_calls) if metrics else None
        }
        
        # Check for high error rates
        if total_calls > 0:
            error_rate = total_failed / total_calls
            if error_rate > 0.1:  # More than 10% errors
                health_info["warnings"] = health_info.get("warnings", [])
                health_info["warnings"].append(f"High error rate: {error_rate:.1%}")
        
    except Exception as e:
        health_info["metrics"] = {
            "status": "error",
            "error": str(e)
        }
    
    # Set overall status
    health_info["status"] = "healthy" if overall_healthy else "degraded"
    
    return health_info


@router.get("/performance")
async def performance_metrics(
    executor: EnhancedToolExecutor = Depends(get_tool_executor)
):
    """Get performance metrics for monitoring dashboards"""
    try:
        metrics = await executor.get_metrics()
        
        # Aggregate performance data
        performance_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "summary": {
                "total_tools": len(metrics),
                "total_calls": sum(m.total_calls for m in metrics.values()),
                "avg_response_time_ms": round(
                    sum(m.avg_duration_ms for m in metrics.values()) / len(metrics) if metrics else 0, 
                    2
                ),
                "overall_cache_hit_rate": round(
                    sum(m.cache_hit_rate for m in metrics.values()) / len(metrics) if metrics else 0,
                    2
                )
            },
            "by_tool": {}
        }
        
        # Detailed metrics by tool
        for tool_name, metric in metrics.items():
            performance_data["by_tool"][tool_name] = {
                "total_calls": metric.total_calls,
                "successful_calls": metric.successful_calls,
                "failed_calls": metric.failed_calls,
                "success_rate": round(
                    (metric.successful_calls / metric.total_calls * 100) if metric.total_calls > 0 else 0,
                    2
                ),
                "avg_duration_ms": round(metric.avg_duration_ms, 2),
                "cache_hit_rate": round(metric.cache_hit_rate, 2),
                "last_executed": metric.last_executed.isoformat() if metric.last_executed else None,
                "error_breakdown": metric.error_rates
            }
        
        return performance_data
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get performance metrics: {str(e)}")


@router.get("/cache/stats")
async def cache_statistics(
    redis_client: aioredis.Redis = Depends(get_redis_client)
):
    """Get cache statistics"""
    if not redis_client:
        return {"status": "disabled", "message": "Redis caching not configured"}
    
    try:
        # Get Redis info
        info = await redis_client.info()
        
        # Count cache keys
        cache_keys = await redis_client.keys("mcp:tool:*")
        
        # Get sample cache entries for analysis
        sample_size = min(10, len(cache_keys))
        sample_entries = []
        
        if cache_keys:
            sample_keys = cache_keys[:sample_size]
            for key in sample_keys:
                try:
                    entry_data = await redis_client.get(key)
                    ttl = await redis_client.ttl(key)
                    if entry_data:
                        # Parse basic info without full deserialization
                        sample_entries.append({
                            "key": key,
                            "ttl_seconds": ttl,
                            "size_bytes": len(entry_data.encode('utf-8')) if isinstance(entry_data, str) else len(str(entry_data))
                        })
                except Exception:
                    continue
        
        return {
            "status": "active",
            "timestamp": datetime.utcnow().isoformat(),
            "redis_info": {
                "version": info.get("redis_version"),
                "used_memory_human": info.get("used_memory_human"),
                "connected_clients": info.get("connected_clients"),
                "total_commands_processed": info.get("total_commands_processed")
            },
            "cache_stats": {
                "total_cache_keys": len(cache_keys),
                "mcp_cache_keys": len([k for k in cache_keys if k.startswith("mcp:tool:")]),
                "sample_entries": sample_entries
            }
        }
        
    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }


@router.post("/test/tool")
async def test_tool_execution(
    tool_name: str = "list_bases",
    executor: EnhancedToolExecutor = Depends(get_tool_executor)
):
    """Test tool execution for monitoring purposes"""
    from ..models.enhanced_mcp import ToolCall, AuthContext
    
    try:
        # Create a test tool call
        test_call = ToolCall(
            tool=tool_name,
            arguments={},
            auth_context=AuthContext(
                user_id="health_check",
                session_id="health_check_session",
                permissions=["read"]
            ),
            metadata={"test": True}
        )
        
        # Execute the tool
        start_time = time.time()
        result = await executor.execute(test_call)
        execution_time = (time.time() - start_time) * 1000
        
        return {
            "status": "success" if result.status.value == "completed" else "failed",
            "tool": tool_name,
            "execution_time_ms": round(execution_time, 2),
            "cache_hit": result.cache_hit,
            "result_preview": str(result.result)[:200] if result.result else None,
            "error": result.error.dict() if result.error else None,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        return {
            "status": "error",
            "tool": tool_name,
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }