"""SAGA transaction endpoints for REST API compatibility."""

import logging
from datetime import datetime, timezone
from typing import List, Optional, Dict, Any, Union

from fastapi import APIRouter, Depends, HTTPException, Request, Query, Path, Body
from pydantic import BaseModel, Field

from ..models.sagas import SagaInstance, SagaStatus, SagaStep
from ..saga_engine.orchestrator import SagaOrchestrator
from ..services.saga_definitions import UserOnboardingSaga, AirtableIntegrationSaga

logger = logging.getLogger(__name__)
router = APIRouter()


class TransactionCreateRequest(BaseModel):
    """Request to create a new SAGA transaction."""
    transaction_type: str = Field(..., description="Type of transaction (saga_type)")
    input_data: Dict[str, Any] = Field(..., description="Input data for the transaction")
    correlation_id: Optional[str] = Field(None, description="Correlation ID for tracking")
    tenant_id: Optional[str] = Field(None, description="Tenant ID for multi-tenancy")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Additional metadata")


class TransactionUpdateRequest(BaseModel):
    """Request to update a SAGA transaction."""
    status: Optional[str] = Field(None, description="New status")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Updated metadata")
    notes: Optional[str] = Field(None, description="Additional notes")


class TransactionResponse(BaseModel):
    """Response for transaction operations."""
    transaction_id: str
    transaction_type: str
    status: str
    current_step: int
    total_steps: int
    input_data: Dict[str, Any]
    output_data: Dict[str, Any]
    correlation_id: Optional[str] = None
    tenant_id: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    error_message: Optional[str] = None
    steps: List[Dict[str, Any]]


class TransactionListResponse(BaseModel):
    """Response for listing transactions."""
    transactions: List[TransactionResponse]
    total: int
    page: int
    page_size: int


class StepExecutionRequest(BaseModel):
    """Request to execute a specific step."""
    force: bool = Field(False, description="Force execute step even if not next")
    input_override: Optional[Dict[str, Any]] = Field(None, description="Override step input")


class CompensationRequest(BaseModel):
    """Request to trigger compensation."""
    reason: str = Field(..., description="Reason for compensation")
    force_complete: bool = Field(False, description="Force complete compensation")


def get_saga_orchestrator(request: Request) -> SagaOrchestrator:
    """Get SAGA orchestrator from app state."""
    if not hasattr(request.app.state, "saga_orchestrator"):
        raise HTTPException(status_code=500, detail="SAGA orchestrator not initialized")
    return request.app.state.saga_orchestrator


def _convert_saga_to_transaction_response(saga: SagaInstance) -> TransactionResponse:
    """Convert SagaInstance to TransactionResponse."""
    return TransactionResponse(
        transaction_id=saga.id,
        transaction_type=saga.type,
        status=saga.status.value if hasattr(saga.status, 'value') else str(saga.status),
        current_step=saga.current_step,
        total_steps=len(saga.steps),
        input_data=saga.input_data,
        output_data=saga.output_data,
        correlation_id=saga.correlation_id,
        tenant_id=saga.tenant_id,
        started_at=saga.started_at,
        completed_at=saga.completed_at,
        error_message=saga.error_message,
        steps=[{
            "id": step.id,
            "name": step.name,
            "service": step.service,
            "status": step.status,
            "started_at": step.started_at,
            "completed_at": step.completed_at,
            "error_message": step.error_message,
            "result": step.result
        } for step in saga.steps]
    )


@router.post("", response_model=TransactionResponse, status_code=201)
async def create_transaction(
    request: TransactionCreateRequest,
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> TransactionResponse:
    """Start a new SAGA transaction.
    
    This endpoint creates and starts a new SAGA transaction of the specified type.
    The transaction will begin processing immediately upon creation.
    
    **Transaction Types:**
    - `user_onboarding`: Complete user registration and setup process
    - `airtable_integration`: Connect and configure Airtable base integration
    
    **Example Request:**
    ```json
    {
        "transaction_type": "user_onboarding",
        "input_data": {
            "user_id": "123",
            "email": "user@example.com",
            "first_name": "John",
            "tenant_id": "tenant_1"
        },
        "correlation_id": "onboarding_123"
    }
    ```
    """
    try:
        logger.info(f"Creating transaction of type: {request.transaction_type}")
        
        # Validate transaction type and create steps
        if request.transaction_type == "user_onboarding":
            steps = UserOnboardingSaga.create_steps(request.input_data)
        elif request.transaction_type == "airtable_integration":
            steps = AirtableIntegrationSaga.create_steps(request.input_data)
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown transaction type: {request.transaction_type}. "
                       f"Available types: user_onboarding, airtable_integration"
            )
        
        # Start SAGA transaction
        saga_id = await orchestrator.start_saga(
            saga_type=request.transaction_type,
            steps=steps,
            input_data=request.input_data,
            correlation_id=request.correlation_id,
            tenant_id=request.tenant_id
        )
        
        # Get created saga to return full response
        saga = await orchestrator.get_saga(saga_id)
        if not saga:
            raise HTTPException(status_code=500, detail="Failed to retrieve created transaction")
        
        logger.info(f"Transaction {saga_id} created successfully")
        return _convert_saga_to_transaction_response(saga)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to create transaction: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create transaction: {str(e)}")


@router.get("/{transaction_id}", response_model=TransactionResponse)
async def get_transaction_status(
    transaction_id: str = Path(..., description="The transaction ID"),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> TransactionResponse:
    """Get the status and details of a specific SAGA transaction.
    
    Returns comprehensive information about the transaction including:
    - Current status and step
    - Input and output data
    - Step execution details
    - Error information if any
    
    **Transaction Statuses:**
    - `PENDING`: Transaction created but not yet started
    - `RUNNING`: Transaction is currently executing steps
    - `COMPLETED`: All steps completed successfully
    - `COMPENSATING`: Transaction failed, running compensation
    - `COMPENSATED`: Compensation completed
    """
    try:
        saga = await orchestrator.get_saga(transaction_id)
        if not saga:
            raise HTTPException(
                status_code=404,
                detail=f"Transaction {transaction_id} not found"
            )
        
        return _convert_saga_to_transaction_response(saga)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get transaction {transaction_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve transaction: {str(e)}")


@router.put("/{transaction_id}", response_model=TransactionResponse)
async def update_transaction(
    transaction_id: str = Path(..., description="The transaction ID"),
    update_request: TransactionUpdateRequest = Body(...),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> TransactionResponse:
    """Update a SAGA transaction's metadata or status.
    
    This endpoint allows updating transaction metadata and notes.
    Status changes are limited to specific transitions for safety.
    
    **Allowed Status Transitions:**
    - Any status -> CANCELLED (triggers compensation)
    - PENDING -> RUNNING (manual start)
    
    **Example Request:**
    ```json
    {
        "metadata": {
            "priority": "high",
            "updated_by": "admin"
        },
        "notes": "Updated priority due to business requirements"
    }
    ```
    """
    try:
        saga = await orchestrator.get_saga(transaction_id)
        if not saga:
            raise HTTPException(
                status_code=404,
                detail=f"Transaction {transaction_id} not found"
            )
        
        # Update metadata if provided
        if update_request.metadata:
            if not hasattr(saga, 'metadata'):
                saga.metadata = {}
            saga.metadata.update(update_request.metadata)
        
        # Handle status updates
        if update_request.status:
            current_status = saga.status.value if hasattr(saga.status, 'value') else str(saga.status)
            
            if update_request.status.upper() == "CANCELLED":
                if current_status in ["PENDING", "RUNNING"]:
                    await orchestrator._start_compensation(saga)
                    logger.info(f"Transaction {transaction_id} cancellation initiated")
                else:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Cannot cancel transaction in status: {current_status}"
                    )
            elif update_request.status.upper() == "RUNNING" and current_status == "PENDING":
                # Manual start of pending transaction
                await orchestrator._process_next_step(saga)
                logger.info(f"Transaction {transaction_id} manually started")
            else:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid status transition from {current_status} to {update_request.status}"
                )
        
        # Persist changes
        await orchestrator._persist_saga(saga)
        
        logger.info(f"Transaction {transaction_id} updated successfully")
        return _convert_saga_to_transaction_response(saga)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to update transaction {transaction_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to update transaction: {str(e)}")


@router.post("/{transaction_id}/compensate", response_model=Dict[str, Any])
async def trigger_compensation(
    transaction_id: str = Path(..., description="The transaction ID"),
    compensation_request: CompensationRequest = Body(...),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> Dict[str, Any]:
    """Trigger compensation for a SAGA transaction.
    
    This endpoint manually triggers the compensation process for a transaction,
    rolling back any completed steps in reverse order.
    
    **Use Cases:**
    - Manual rollback due to business logic changes
    - Recovery from partial failures
    - Testing compensation flows
    
    **Example Request:**
    ```json
    {
        "reason": "Business requirement changed",
        "force_complete": false
    }
    ```
    """
    try:
        saga = await orchestrator.get_saga(transaction_id)
        if not saga:
            raise HTTPException(
                status_code=404,
                detail=f"Transaction {transaction_id} not found"
            )
        
        current_status = saga.status.value if hasattr(saga.status, 'value') else str(saga.status)
        
        # Check if compensation is possible
        if current_status in ["COMPLETED", "RUNNING", "PENDING"]:
            # Add compensation reason to metadata
            if not hasattr(saga, 'metadata'):
                saga.metadata = {}
            saga.metadata['compensation_reason'] = compensation_request.reason
            saga.metadata['compensation_triggered_at'] = datetime.now(timezone.utc).isoformat()
            
            # Start compensation
            await orchestrator._start_compensation(saga)
            
            completed_steps = sum(1 for step in saga.steps if step.status == "completed")
            
            logger.info(f"Compensation triggered for transaction {transaction_id}, "
                       f"will compensate {completed_steps} steps")
            
            return {
                "status": "compensation_started",
                "message": "Compensation process initiated",
                "reason": compensation_request.reason,
                "steps_to_compensate": completed_steps,
                "transaction_id": transaction_id
            }
            
        elif current_status == "COMPENSATING":
            return {
                "status": "already_compensating",
                "message": "Compensation already in progress",
                "transaction_id": transaction_id
            }
            
        elif current_status == "COMPENSATED":
            if compensation_request.force_complete:
                return {
                    "status": "already_compensated",
                    "message": "Transaction already compensated",
                    "transaction_id": transaction_id
                }
            else:
                raise HTTPException(
                    status_code=400,
                    detail="Transaction already compensated. Use force_complete=true to acknowledge."
                )
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot compensate transaction in status: {current_status}"
            )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to trigger compensation for transaction {transaction_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to trigger compensation: {str(e)}")


@router.get("", response_model=TransactionListResponse)
async def list_transactions(
    status: Optional[str] = Query(None, description="Filter by transaction status"),
    transaction_type: Optional[str] = Query(None, description="Filter by transaction type"),
    tenant_id: Optional[str] = Query(None, description="Filter by tenant ID"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(50, ge=1, le=1000, description="Number of transactions per page"),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> TransactionListResponse:
    """List SAGA transactions with filtering and pagination.
    
    Returns a paginated list of transactions with optional filtering by:
    - Status (PENDING, RUNNING, COMPLETED, COMPENSATING, COMPENSATED)
    - Transaction type (user_onboarding, airtable_integration)
    - Tenant ID (for multi-tenant filtering)
    
    **Example Response:**
    ```json
    {
        "transactions": [...],
        "total": 150,
        "page": 1,
        "page_size": 50
    }
    ```
    """
    try:
        # Convert status string to SagaStatus enum if provided
        status_filter = None
        if status:
            try:
                status_filter = SagaStatus[status.upper()]
            except KeyError:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid status: {status}. Valid statuses: "
                           f"{', '.join([s.value for s in SagaStatus])}"
                )
        
        # Get all sagas with basic filtering
        sagas = await orchestrator.list_sagas(
            status=status_filter,
            saga_type=transaction_type,
            limit=page_size * 10  # Get more to handle tenant filtering
        )
        
        # Apply tenant filtering if specified
        if tenant_id:
            sagas = [saga for saga in sagas if saga.tenant_id == tenant_id]
        
        # Calculate pagination
        total = len(sagas)
        start_idx = (page - 1) * page_size
        end_idx = start_idx + page_size
        paginated_sagas = sagas[start_idx:end_idx]
        
        # Convert to transaction responses
        transactions = [_convert_saga_to_transaction_response(saga) for saga in paginated_sagas]
        
        return TransactionListResponse(
            transactions=transactions,
            total=total,
            page=page,
            page_size=page_size
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to list transactions: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list transactions: {str(e)}")


@router.post("/{transaction_id}/step", response_model=Dict[str, Any])
async def execute_next_step(
    transaction_id: str = Path(..., description="The transaction ID"),
    step_request: StepExecutionRequest = Body(...),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> Dict[str, Any]:
    """Execute the next step in a SAGA transaction.
    
    This endpoint allows manual execution of the next step in a transaction.
    Useful for:
    - Manual step-by-step execution
    - Recovery from stuck transactions
    - Testing individual steps
    
    **Example Request:**
    ```json
    {
        "force": false,
        "input_override": {
            "custom_param": "value"
        }
    }
    ```
    """
    try:
        saga = await orchestrator.get_saga(transaction_id)
        if not saga:
            raise HTTPException(
                status_code=404,
                detail=f"Transaction {transaction_id} not found"
            )
        
        current_status = saga.status.value if hasattr(saga.status, 'value') else str(saga.status)
        
        # Check if step execution is possible
        if current_status not in ["PENDING", "RUNNING"] and not step_request.force:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot execute step for transaction in status: {current_status}. "
                       f"Use force=true to override."
            )
        
        # Check if there are more steps to execute
        if saga.current_step >= len(saga.steps):
            return {
                "status": "completed",
                "message": "All steps have been completed",
                "transaction_id": transaction_id,
                "total_steps": len(saga.steps)
            }
        
        # Get the next step
        next_step = saga.steps[saga.current_step]
        
        # Apply input overrides if provided
        if step_request.input_override:
            if not hasattr(saga, 'step_overrides'):
                saga.step_overrides = {}
            saga.step_overrides[next_step.id] = step_request.input_override
        
        # Execute the next step
        await orchestrator._process_next_step(saga)
        
        # Get updated saga state
        updated_saga = await orchestrator.get_saga(transaction_id)
        
        return {
            "status": "step_executed",
            "message": f"Step '{next_step.name}' execution initiated",
            "transaction_id": transaction_id,
            "step_id": next_step.id,
            "step_name": next_step.name,
            "step_service": next_step.service,
            "current_step": updated_saga.current_step if updated_saga else saga.current_step,
            "total_steps": len(saga.steps)
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to execute step for transaction {transaction_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to execute step: {str(e)}")


@router.get("/{transaction_id}/steps", response_model=List[Dict[str, Any]])
async def get_transaction_steps(
    transaction_id: str = Path(..., description="The transaction ID"),
    orchestrator: SagaOrchestrator = Depends(get_saga_orchestrator)
) -> List[Dict[str, Any]]:
    """Get detailed information about all steps in a SAGA transaction.
    
    Returns comprehensive details about each step including:
    - Execution status and timing
    - Input and output data
    - Error information
    - Compensation commands
    """
    try:
        saga = await orchestrator.get_saga(transaction_id)
        if not saga:
            raise HTTPException(
                status_code=404,
                detail=f"Transaction {transaction_id} not found"
            )
        
        steps_details = []
        for i, step in enumerate(saga.steps):
            step_detail = {
                "step_number": i + 1,
                "id": step.id,
                "name": step.name,
                "service": step.service,
                "status": step.status,
                "command": step.command,
                "compensation_command": step.compensation_command,
                "started_at": step.started_at,
                "completed_at": step.completed_at,
                "duration_ms": None,
                "result": step.result,
                "error_message": step.error_message,
                "is_current": i == saga.current_step,
                "can_compensate": step.status == "completed" and step.compensation_command is not None
            }
            
            # Calculate duration if both timestamps are available
            if step.started_at and step.completed_at:
                duration = step.completed_at - step.started_at
                step_detail["duration_ms"] = int(duration.total_seconds() * 1000)
            
            steps_details.append(step_detail)
        
        return steps_details
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get steps for transaction {transaction_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get transaction steps: {str(e)}")


@router.get("/types/available", response_model=Dict[str, Any])
async def get_available_transaction_types() -> Dict[str, Any]:
    """Get information about available SAGA transaction types.
    
    Returns metadata about all supported transaction types including:
    - Required and optional input fields
    - Description and use cases
    - Expected steps and duration
    """
    return {
        "transaction_types": [
            {
                "name": "user_onboarding",
                "display_name": "User Onboarding",
                "description": "Complete user registration and setup process including profile creation, workspace setup, and welcome notifications",
                "required_fields": ["user_id", "email", "first_name", "tenant_id"],
                "optional_fields": ["last_name", "company_name", "phone_number"],
                "estimated_duration_minutes": 5,
                "typical_steps": [
                    "Create user profile",
                    "Set up default workspace", 
                    "Configure permissions",
                    "Send welcome email",
                    "Initialize user preferences"
                ],
                "use_cases": [
                    "New user registration",
                    "User migration",
                    "Bulk user import"
                ]
            },
            {
                "name": "airtable_integration",
                "display_name": "Airtable Integration",
                "description": "Connect and configure Airtable base integration with schema sync and webhook setup",
                "required_fields": ["base_id", "api_key", "user_id", "tenant_id"],
                "optional_fields": ["webhook_url", "sync_frequency", "table_filters"],
                "estimated_duration_minutes": 10,
                "typical_steps": [
                    "Validate API credentials",
                    "Fetch base schema",
                    "Create local schema mapping",
                    "Set up webhook endpoints",
                    "Initialize data sync",
                    "Run validation sync"
                ],
                "use_cases": [
                    "New Airtable connection",
                    "Schema migration",
                    "Integration testing"
                ]
            }
        ],
        "patterns": {
            "orchestration": {
                "description": "Centralized control where the orchestrator manages all steps",
                "use_when": "Complex business logic, sequential dependencies, need for central monitoring"
            },
            "choreography": {
                "description": "Distributed coordination where services react to events",
                "use_when": "Simple workflows, loose coupling desired, high performance needed"
            }
        },
        "status_definitions": {
            "PENDING": "Transaction created but not yet started",
            "RUNNING": "Transaction is currently executing steps",
            "COMPLETED": "All steps completed successfully",
            "COMPENSATING": "Transaction failed, executing rollback steps",
            "COMPENSATED": "Rollback completed successfully"
        }
    }