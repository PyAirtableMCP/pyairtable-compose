"""SAGA management endpoints."""

import logging
from typing import List, Optional, Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Request, Query
from pydantic import BaseModel

from ..models.sagas import SagaInstance, SagaStatus, SagaStep
from ..saga_engine.orchestrator import SagaOrchestrator
from ..services.saga_definitions import UserOnboardingSaga, AirtableIntegrationSaga

logger = logging.getLogger(__name__)
router = APIRouter()


class StartSagaRequest(BaseModel):
    """Request to start a new SAGA."""
    saga_type: str
    input_data: Dict[str, Any]
    correlation_id: Optional[str] = None
    tenant_id: Optional[str] = None


class StartSagaResponse(BaseModel):
    """Response for starting a SAGA."""
    saga_id: str
    status: str
    message: str


class SagaListResponse(BaseModel):
    """Response for listing SAGAs."""
    sagas: List[SagaInstance]
    total: int


def get_saga_orchestrator(request: Request) -> SagaOrchestrator:
    """Get SAGA orchestrator from app state."""
    if not hasattr(request.app.state, "saga_orchestrator"):
        raise HTTPException(status_code=500, detail="SAGA orchestrator not initialized")
    return request.app.state.saga_orchestrator


@router.post("/start", response_model=StartSagaResponse)
async def start_saga(
    request: StartSagaRequest,
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> StartSagaResponse:
    """Start a new SAGA instance."""
    try:
        # Get steps based on SAGA type
        if request.saga_type == "user_onboarding":
            steps = UserOnboardingSaga.create_steps(request.input_data)
        elif request.saga_type == "airtable_integration":
            steps = AirtableIntegrationSaga.create_steps(request.input_data)
        else:
            raise HTTPException(
                status_code=400, 
                detail=f"Unknown SAGA type: {request.saga_type}"
            )
        
        # Start SAGA
        saga_id = await orchestrator.start_saga(
            saga_type=request.saga_type,
            steps=steps,
            input_data=request.input_data,
            correlation_id=request.correlation_id,
            tenant_id=request.tenant_id
        )
        
        return StartSagaResponse(
            saga_id=saga_id,
            status="started",
            message=f"SAGA {request.saga_type} started successfully"
        )
        
    except Exception as e:
        logger.error(f"Failed to start SAGA: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/", response_model=SagaListResponse)
async def list_sagas(
    status: Optional[SagaStatus] = Query(None, description="Filter by status"),
    saga_type: Optional[str] = Query(None, description="Filter by SAGA type"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum number of SAGAs to return"),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> SagaListResponse:
    """List SAGA instances with optional filtering."""
    try:
        sagas = await orchestrator.list_sagas(
            status=status,
            saga_type=saga_type,
            limit=limit
        )
        
        return SagaListResponse(
            sagas=sagas,
            total=len(sagas)
        )
        
    except Exception as e:
        logger.error(f"Failed to list SAGAs: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{saga_id}", response_model=SagaInstance)
async def get_saga(
    saga_id: str,
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> SagaInstance:
    """Get a specific SAGA instance by ID."""
    try:
        saga = await orchestrator.get_saga(saga_id)
        if not saga:
            raise HTTPException(status_code=404, detail="SAGA not found")
        
        return saga
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get SAGA {saga_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{saga_id}/cancel")
async def cancel_saga(
    saga_id: str,
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> Dict[str, str]:
    """Cancel a running SAGA (triggers compensation)."""
    try:
        saga = await orchestrator.get_saga(saga_id)
        if not saga:
            raise HTTPException(status_code=404, detail="SAGA not found")
        
        if saga.status not in [SagaStatus.PENDING, SagaStatus.RUNNING]:
            raise HTTPException(
                status_code=400, 
                detail=f"Cannot cancel SAGA in status: {saga.status}"
            )
        
        # Trigger compensation by marking as failed
        await orchestrator._start_compensation(saga)
        
        return {"status": "cancelled", "message": "SAGA cancellation initiated"}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to cancel SAGA {saga_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{saga_id}/steps", response_model=List[SagaStep])
async def get_saga_steps(
    saga_id: str,
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> List[SagaStep]:
    """Get all steps for a SAGA instance."""
    try:
        saga = await orchestrator.get_saga(saga_id)
        if not saga:
            raise HTTPException(status_code=404, detail="SAGA not found")
        
        return saga.steps
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get SAGA steps for {saga_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/types/available")
async def get_available_saga_types() -> Dict[str, Any]:
    """Get available SAGA types and their descriptions."""
    return {
        "saga_types": [
            {
                "name": "user_onboarding",
                "description": "Onboard new users with profile creation, workspace setup, and welcome notifications",
                "required_fields": ["user_id", "email", "first_name", "tenant_id"],
                "optional_fields": ["last_name", "company_name"]
            },
            {
                "name": "airtable_integration",
                "description": "Connect and configure Airtable base integration",
                "required_fields": ["base_id", "api_key", "user_id", "tenant_id"],
                "optional_fields": ["webhook_url"]
            }
        ]
    }