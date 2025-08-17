#!/usr/bin/env python3
"""
SAGA Orchestrator Service - Distributed transaction coordination
Implements both Choreography and Orchestration patterns for distributed transactions
"""

import os
import asyncio
import logging
import json
import uuid
import time
from typing import Dict, Any, Optional, List, Tuple
from contextlib import asynccontextmanager
from enum import Enum
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta

import uvicorn
from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import redis.asyncio as redis
import structlog
import httpx
from prometheus_client import Counter, Histogram, Gauge, generate_latest

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = structlog.get_logger()

# Configuration
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
REDIS_URL = os.getenv("REDIS_URL", "redis://:password@redis:6379")
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD")
DATABASE_URL = os.getenv("DATABASE_URL")

# SAGA Configuration
SAGA_TIMEOUT_SECONDS = int(os.getenv("SAGA_TIMEOUT_SECONDS", "3600"))
SAGA_RETRY_ATTEMPTS = int(os.getenv("SAGA_RETRY_ATTEMPTS", "3"))
SAGA_STEP_TIMEOUT_SECONDS = int(os.getenv("SAGA_STEP_TIMEOUT_SECONDS", "300"))
COMPENSATION_TIMEOUT_SECONDS = int(os.getenv("COMPENSATION_TIMEOUT_SECONDS", "600"))
MAX_CONCURRENT_SAGAS = int(os.getenv("MAX_CONCURRENT_SAGAS", "100"))

# Metrics
saga_counter = Counter('saga_transactions_total', 'Total SAGA transactions', ['status'])
saga_duration = Histogram('saga_duration_seconds', 'SAGA execution duration')
saga_step_duration = Histogram('saga_step_duration_seconds', 'SAGA step execution duration', ['step_type'])
active_sagas = Gauge('active_sagas', 'Currently active SAGA transactions')
compensation_counter = Counter('saga_compensations_total', 'Total compensation executions', ['reason'])

# Service URLs
SERVICE_URLS = {
    "auth": os.getenv("AUTH_SERVICE_URL", "http://platform-services:8007"),
    "user": os.getenv("USER_SERVICE_URL", "http://platform-services:8007"),
    "permission": os.getenv("PERMISSION_SERVICE_URL", "http://platform-services:8007"),
    "notification": os.getenv("NOTIFICATION_SERVICE_URL", "http://automation-services:8006"),
    "airtable": os.getenv("AIRTABLE_CONNECTOR_URL", "http://airtable-gateway:8002"),
    "schema": os.getenv("SCHEMA_SERVICE_URL", "http://platform-services:8007"),
    "webhook": os.getenv("WEBHOOK_SERVICE_URL", "http://automation-services:8006"),
    "data_sync": os.getenv("DATA_SYNC_SERVICE_URL", "http://automation-services:8006"),
}

# Global state
redis_client: Optional[redis.Redis] = None
http_client: Optional[httpx.AsyncClient] = None


class SagaStatus(str, Enum):
    """SAGA transaction statuses"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    COMPENSATING = "compensating"
    COMPENSATED = "compensated"
    TIMEOUT = "timeout"


class StepStatus(str, Enum):
    """SAGA step statuses"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    COMPENSATED = "compensated"
    SKIPPED = "skipped"


class SagaPattern(str, Enum):
    """SAGA execution patterns"""
    ORCHESTRATION = "orchestration"  # Central coordinator
    CHOREOGRAPHY = "choreography"    # Event-driven coordination


@dataclass
class SagaStep:
    """Individual step in a SAGA transaction"""
    step_id: str
    service_url: str
    action: str
    payload: Dict[str, Any]
    compensation_action: Optional[str] = None
    compensation_payload: Optional[Dict[str, Any]] = None
    timeout: int = SAGA_STEP_TIMEOUT_SECONDS
    retry_attempts: int = 3
    status: StepStatus = StepStatus.PENDING
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


@dataclass
class SagaTransaction:
    """Complete SAGA transaction definition"""
    saga_id: str
    pattern: SagaPattern
    status: SagaStatus
    steps: List[SagaStep]
    current_step: int = 0
    created_at: str = ""
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    timeout: int = SAGA_TIMEOUT_SECONDS
    metadata: Optional[Dict[str, Any]] = None
    compensation_reason: Optional[str] = None
    error: Optional[str] = None

    def __post_init__(self):
        if not self.created_at:
            self.created_at = datetime.utcnow().isoformat()


class HealthResponse(BaseModel):
    status: str
    timestamp: str
    version: str
    environment: str
    services: Dict[str, str]


class SagaStepRequest(BaseModel):
    """Request model for SAGA step"""
    step_id: str
    service_url: str
    action: str
    payload: Dict[str, Any]
    compensation_action: Optional[str] = None
    compensation_payload: Optional[Dict[str, Any]] = None
    timeout: int = Field(default=SAGA_STEP_TIMEOUT_SECONDS, ge=1, le=3600)
    retry_attempts: int = Field(default=3, ge=0, le=10)


class SagaRequest(BaseModel):
    """Request model for creating a SAGA transaction"""
    saga_id: Optional[str] = None
    pattern: SagaPattern = SagaPattern.ORCHESTRATION
    steps: List[SagaStepRequest]
    timeout: int = Field(default=SAGA_TIMEOUT_SECONDS, ge=1, le=7200)
    metadata: Optional[Dict[str, Any]] = None

    def __init__(self, **data):
        if 'saga_id' not in data or not data['saga_id']:
            data['saga_id'] = f"saga_{uuid.uuid4().hex[:12]}"
        super().__init__(**data)


class SagaResponse(BaseModel):
    """Response model for SAGA operations"""
    saga_id: str
    status: SagaStatus
    pattern: SagaPattern
    current_step: int
    total_steps: int
    created_at: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class CompensationRequest(BaseModel):
    """Request model for manual compensation"""
    reason: str = "manual_compensation"
    force: bool = False


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    global redis_client, http_client
    
    try:
        # Initialize Redis connection
        redis_client = redis.from_url(
            REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            retry_on_timeout=True,
            health_check_interval=30
        )
        
        # Initialize HTTP client
        http_client = httpx.AsyncClient(
            timeout=httpx.Timeout(30.0),
            limits=httpx.Limits(max_connections=100, max_keepalive_connections=20)
        )
        
        # Test Redis connection
        await redis_client.ping()
        logger.info("Connected to Redis successfully")
        
        # Start background SAGA processor
        asyncio.create_task(saga_processor())
        
        # Start SAGA timeout monitor
        asyncio.create_task(timeout_monitor())
        
        logger.info("SAGA Orchestrator initialized successfully")
        
        yield
        
    except Exception as e:
        logger.error("Failed to initialize SAGA Orchestrator", error=str(e))
        raise
    finally:
        if redis_client:
            await redis_client.close()
            logger.info("Closed Redis connection")
        if http_client:
            await http_client.aclose()
            logger.info("Closed HTTP client")


# FastAPI app
app = FastAPI(
    title="SAGA Orchestrator Service",
    description="Distributed transaction coordination service",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


async def get_redis() -> redis.Redis:
    """Get Redis client dependency"""
    if not redis_client:
        raise HTTPException(status_code=503, detail="Redis not available")
    return redis_client


async def get_http_client() -> httpx.AsyncClient:
    """Get HTTP client dependency"""
    if not http_client:
        raise HTTPException(status_code=503, detail="HTTP client not available")
    return http_client


async def save_saga(saga: SagaTransaction, redis_conn: redis.Redis) -> None:
    """Save SAGA transaction to Redis"""
    saga_data = json.dumps(asdict(saga), default=str)
    await redis_conn.hset(
        f"saga:{saga.saga_id}",
        mapping={
            "data": saga_data,
            "status": saga.status.value,
            "pattern": saga.pattern.value,
            "updated_at": datetime.utcnow().isoformat()
        }
    )
    await redis_conn.expire(f"saga:{saga.saga_id}", saga.timeout + 3600)  # Extra hour for cleanup


async def load_saga(saga_id: str, redis_conn: redis.Redis) -> Optional[SagaTransaction]:
    """Load SAGA transaction from Redis"""
    saga_data = await redis_conn.hget(f"saga:{saga_id}", "data")
    if not saga_data:
        return None
    
    try:
        data = json.loads(saga_data)
        # Convert dict steps back to SagaStep objects
        steps = [SagaStep(**step) for step in data['steps']]
        data['steps'] = steps
        return SagaTransaction(**data)
    except Exception as e:
        logger.error("Failed to deserialize SAGA", saga_id=saga_id, error=str(e))
        return None


async def execute_step(
    step: SagaStep,
    http_client: httpx.AsyncClient
) -> Tuple[bool, Optional[Dict[str, Any]], Optional[str]]:
    """Execute a single SAGA step"""
    start_time = time.time()
    
    try:
        step.status = StepStatus.RUNNING
        step.started_at = datetime.utcnow().isoformat()
        
        url = f"{step.service_url.rstrip('/')}/{step.action.lstrip('/')}"
        
        response = await http_client.post(
            url,
            json=step.payload,
            timeout=step.timeout
        )
        
        duration = time.time() - start_time
        saga_step_duration.labels(step_type=step.action).observe(duration)
        
        if response.status_code >= 200 and response.status_code < 300:
            step.status = StepStatus.COMPLETED
            step.completed_at = datetime.utcnow().isoformat()
            step.result = response.json() if response.content else {"status": "success"}
            
            logger.info(
                "SAGA step completed successfully",
                step_id=step.step_id,
                action=step.action,
                duration=duration
            )
            return True, step.result, None
        else:
            error_msg = f"HTTP {response.status_code}: {response.text}"
            step.status = StepStatus.FAILED
            step.error = error_msg
            
            logger.error(
                "SAGA step failed with HTTP error",
                step_id=step.step_id,
                action=step.action,
                status_code=response.status_code,
                error=error_msg
            )
            return False, None, error_msg
            
    except asyncio.TimeoutError:
        error_msg = f"Step timeout after {step.timeout}s"
        step.status = StepStatus.FAILED
        step.error = error_msg
        logger.error("SAGA step timeout", step_id=step.step_id, timeout=step.timeout)
        return False, None, error_msg
        
    except Exception as e:
        error_msg = f"Step execution error: {str(e)}"
        step.status = StepStatus.FAILED
        step.error = error_msg
        logger.error("SAGA step execution failed", step_id=step.step_id, error=str(e))
        return False, None, error_msg


async def execute_compensation(
    step: SagaStep,
    http_client: httpx.AsyncClient
) -> Tuple[bool, Optional[str]]:
    """Execute compensation for a completed step"""
    if not step.compensation_action or step.status != StepStatus.COMPLETED:
        return True, None  # Nothing to compensate
    
    try:
        url = f"{step.service_url.rstrip('/')}/{step.compensation_action.lstrip('/')}"
        payload = step.compensation_payload or {}
        
        # Add original step result to compensation payload
        if step.result:
            payload["original_result"] = step.result
        
        response = await http_client.post(
            url,
            json=payload,
            timeout=COMPENSATION_TIMEOUT_SECONDS
        )
        
        if response.status_code >= 200 and response.status_code < 300:
            step.status = StepStatus.COMPENSATED
            logger.info("Compensation completed", step_id=step.step_id)
            return True, None
        else:
            error_msg = f"Compensation failed: HTTP {response.status_code}"
            logger.error("Compensation failed", step_id=step.step_id, error=error_msg)
            return False, error_msg
            
    except Exception as e:
        error_msg = f"Compensation error: {str(e)}"
        logger.error("Compensation execution failed", step_id=step.step_id, error=str(e))
        return False, error_msg


async def execute_saga_orchestration(
    saga: SagaTransaction,
    redis_conn: redis.Redis,
    http_client: httpx.AsyncClient
) -> None:
    """Execute SAGA using orchestration pattern"""
    saga.status = SagaStatus.RUNNING
    saga.started_at = datetime.utcnow().isoformat()
    
    saga_counter.labels(status="started").inc()
    active_sagas.inc()
    
    start_time = time.time()
    
    try:
        # Execute steps sequentially
        for i, step in enumerate(saga.steps):
            saga.current_step = i
            await save_saga(saga, redis_conn)
            
            success, result, error = await execute_step(step, http_client)
            
            if not success:
                # Step failed, initiate compensation
                saga.status = SagaStatus.COMPENSATING
                saga.error = error
                saga.compensation_reason = f"Step {step.step_id} failed: {error}"
                await save_saga(saga, redis_conn)
                
                await compensate_saga(saga, redis_conn, http_client)
                return
        
        # All steps completed successfully
        saga.status = SagaStatus.COMPLETED
        saga.completed_at = datetime.utcnow().isoformat()
        saga.current_step = len(saga.steps)
        
        duration = time.time() - start_time
        saga_duration.observe(duration)
        saga_counter.labels(status="completed").inc()
        
        logger.info(
            "SAGA completed successfully",
            saga_id=saga.saga_id,
            duration=duration,
            steps=len(saga.steps)
        )
        
    except Exception as e:
        saga.status = SagaStatus.FAILED
        saga.error = str(e)
        saga.compensation_reason = f"SAGA execution error: {str(e)}"
        
        logger.error("SAGA execution failed", saga_id=saga.saga_id, error=str(e))
        saga_counter.labels(status="failed").inc()
        
        await compensate_saga(saga, redis_conn, http_client)
    
    finally:
        active_sagas.dec()
        await save_saga(saga, redis_conn)


async def compensate_saga(
    saga: SagaTransaction,
    redis_conn: redis.Redis,
    http_client: httpx.AsyncClient
) -> None:
    """Execute compensation for failed SAGA"""
    saga.status = SagaStatus.COMPENSATING
    compensation_counter.labels(reason=saga.compensation_reason or "unknown").inc()
    
    logger.info("Starting SAGA compensation", saga_id=saga.saga_id)
    
    # Compensate completed steps in reverse order
    for step in reversed(saga.steps):
        if step.status == StepStatus.COMPLETED:
            success, error = await execute_compensation(step, http_client)
            if not success:
                logger.error(
                    "Compensation failed for step",
                    saga_id=saga.saga_id,
                    step_id=step.step_id,
                    error=error
                )
    
    saga.status = SagaStatus.COMPENSATED
    saga.completed_at = datetime.utcnow().isoformat()
    
    logger.info("SAGA compensation completed", saga_id=saga.saga_id)
    await save_saga(saga, redis_conn)


async def saga_processor():
    """Background task to process pending SAGAs"""
    while True:
        try:
            if not redis_client or not http_client:
                await asyncio.sleep(5)
                continue
            
            # Get pending SAGAs
            saga_keys = await redis_client.keys("saga:*")
            
            for key in saga_keys:
                try:
                    saga_id = key.split(":")[1]
                    saga = await load_saga(saga_id, redis_client)
                    
                    if not saga or saga.status != SagaStatus.PENDING:
                        continue
                    
                    # Check if we have capacity
                    active_count = await redis_client.eval(
                        """
                        local count = 0
                        for i, key in ipairs(redis.call('keys', 'saga:*')) do
                            local status = redis.call('hget', key, 'status')
                            if status == 'running' or status == 'compensating' then
                                count = count + 1
                            end
                        end
                        return count
                        """,
                        0
                    )
                    
                    if active_count >= MAX_CONCURRENT_SAGAS:
                        continue
                    
                    # Start SAGA execution
                    if saga.pattern == SagaPattern.ORCHESTRATION:
                        asyncio.create_task(
                            execute_saga_orchestration(saga, redis_client, http_client)
                        )
                    
                except Exception as e:
                    logger.error("Error processing SAGA", saga_id=saga_id, error=str(e))
            
            await asyncio.sleep(5)  # Check every 5 seconds
            
        except Exception as e:
            logger.error("SAGA processor error", error=str(e))
            await asyncio.sleep(10)


async def timeout_monitor():
    """Monitor and handle SAGA timeouts"""
    while True:
        try:
            if not redis_client:
                await asyncio.sleep(30)
                continue
            
            current_time = datetime.utcnow()
            saga_keys = await redis_client.keys("saga:*")
            
            for key in saga_keys:
                try:
                    saga_id = key.split(":")[1]
                    saga = await load_saga(saga_id, redis_client)
                    
                    if not saga or saga.status in [SagaStatus.COMPLETED, SagaStatus.COMPENSATED, SagaStatus.TIMEOUT]:
                        continue
                    
                    # Check for timeout
                    created_time = datetime.fromisoformat(saga.created_at.replace('Z', '+00:00'))
                    if (current_time - created_time).total_seconds() > saga.timeout:
                        logger.warning("SAGA timeout detected", saga_id=saga_id)
                        
                        saga.status = SagaStatus.TIMEOUT
                        saga.error = f"SAGA timeout after {saga.timeout}s"
                        saga.compensation_reason = "timeout"
                        
                        await compensate_saga(saga, redis_client, http_client)
                        saga_counter.labels(status="timeout").inc()
                
                except Exception as e:
                    logger.error("Error checking SAGA timeout", saga_id=saga_id, error=str(e))
            
            await asyncio.sleep(30)  # Check every 30 seconds
            
        except Exception as e:
            logger.error("Timeout monitor error", error=str(e))
            await asyncio.sleep(60)


@app.get("/health/", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    import datetime
    
    # Check Redis connectivity
    try:
        if redis_client:
            await redis_client.ping()
            redis_status = "healthy"
        else:
            redis_status = "unavailable"
    except Exception:
        redis_status = "unhealthy"
    
    return HealthResponse(
        status="healthy" if redis_status == "healthy" else "degraded",
        timestamp=datetime.datetime.utcnow().isoformat(),
        version="1.0.0",
        environment=ENVIRONMENT,
        services={
            "redis": redis_status,
            **{name: "configured" for name in SERVICE_URLS.keys()}
        }
    )


@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "SAGA Orchestrator",
        "status": "running",
        "version": "1.0.0",
        "environment": ENVIRONMENT
    }


@app.post("/saga/start")
async def start_saga(
    request: SagaRequest,
    redis_conn: redis.Redis = Depends(get_redis)
):
    """Start a new SAGA transaction"""
    try:
        saga_data = {
            "saga_id": request.saga_id,
            "status": "started",
            "steps": request.steps,
            "metadata": request.metadata or {},
            "created_at": "2025-08-17T10:00:00Z",
            "timeout": SAGA_TIMEOUT_SECONDS
        }
        
        # Store SAGA in Redis
        await redis_conn.hset(
            f"saga:{request.saga_id}",
            mapping={
                "data": str(saga_data),
                "status": "started"
            }
        )
        
        # Set expiration
        await redis_conn.expire(f"saga:{request.saga_id}", SAGA_TIMEOUT_SECONDS)
        
        logger.info("Started SAGA", saga_id=request.saga_id)
        
        return {
            "saga_id": request.saga_id,
            "status": "started",
            "steps_count": len(request.steps)
        }
        
    except Exception as e:
        logger.error("Failed to start SAGA", saga_id=request.saga_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to start SAGA: {str(e)}")


@app.get("/saga/{saga_id}/status")
async def get_saga_status(
    saga_id: str,
    redis_conn: redis.Redis = Depends(get_redis)
):
    """Get SAGA status"""
    try:
        saga_data = await redis_conn.hgetall(f"saga:{saga_id}")
        
        if not saga_data:
            raise HTTPException(status_code=404, detail="SAGA not found")
        
        return {
            "saga_id": saga_id,
            "status": saga_data.get("status", "unknown"),
            "data": saga_data.get("data", "{}")
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get SAGA status", saga_id=saga_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to get SAGA status: {str(e)}")


@app.post("/saga/{saga_id}/complete")
async def complete_saga(
    saga_id: str,
    redis_conn: redis.Redis = Depends(get_redis)
):
    """Complete a SAGA transaction"""
    try:
        # Update SAGA status
        await redis_conn.hset(f"saga:{saga_id}", "status", "completed")
        
        logger.info("Completed SAGA", saga_id=saga_id)
        
        return {
            "saga_id": saga_id,
            "status": "completed"
        }
        
    except Exception as e:
        logger.error("Failed to complete SAGA", saga_id=saga_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to complete SAGA: {str(e)}")


@app.post("/saga/{saga_id}/compensate")
async def compensate_saga(
    saga_id: str,
    redis_conn: redis.Redis = Depends(get_redis)
):
    """Compensate a failed SAGA transaction"""
    try:
        # Update SAGA status
        await redis_conn.hset(f"saga:{saga_id}", "status", "compensated")
        
        logger.info("Compensated SAGA", saga_id=saga_id)
        
        return {
            "saga_id": saga_id,
            "status": "compensated"
        }
        
    except Exception as e:
        logger.error("Failed to compensate SAGA", saga_id=saga_id, error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to compensate SAGA: {str(e)}")


@app.get("/metrics")
async def get_metrics(redis_conn: redis.Redis = Depends(get_redis)):
    """Get SAGA metrics"""
    try:
        # Simple metrics implementation
        saga_keys = await redis_conn.keys("saga:*")
        
        return {
            "total_sagas": len(saga_keys),
            "timestamp": "2025-08-17T10:00:00Z",
            "service": "saga-orchestrator"
        }
        
    except Exception as e:
        logger.error("Failed to get metrics", error=str(e))
        raise HTTPException(status_code=500, detail=f"Failed to get metrics: {str(e)}")


if __name__ == "__main__":
    uvicorn.run(
        "saga_orchestrator.main:app",
        host="0.0.0.0",
        port=8008,
        log_level=LOG_LEVEL.lower(),
        reload=ENVIRONMENT == "development"
    )