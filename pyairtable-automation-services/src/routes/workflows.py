from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel
import json

from ..database import get_db
from ..models.workflows import Workflow as WorkflowModel, WorkflowStatus
from ..models.executions import WorkflowExecution as ExecutionModel, ExecutionStatus
from ..services.workflow_service import WorkflowService
from ..utils.auth import verify_api_key

router = APIRouter()

# Pydantic models for API
class WorkflowCreate(BaseModel):
    name: str
    description: Optional[str] = None
    workflow_config: dict
    trigger_config: Optional[dict] = None
    cron_schedule: Optional[str] = None
    is_scheduled: bool = False
    trigger_on_file_upload: bool = False
    trigger_file_extensions: Optional[str] = None
    timeout_seconds: int = 300

class WorkflowUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    workflow_config: Optional[dict] = None
    trigger_config: Optional[dict] = None
    cron_schedule: Optional[str] = None
    is_scheduled: Optional[bool] = None
    trigger_on_file_upload: Optional[bool] = None
    trigger_file_extensions: Optional[str] = None
    timeout_seconds: Optional[int] = None
    is_enabled: Optional[bool] = None

class WorkflowResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]
    workflow_config: dict
    trigger_config: Optional[dict]
    cron_schedule: Optional[str]
    is_scheduled: bool
    trigger_on_file_upload: bool
    trigger_file_extensions: Optional[str]
    status: str
    is_enabled: bool
    total_executions: int
    successful_executions: int
    failed_executions: int
    last_execution_at: Optional[str]
    created_at: str
    updated_at: str

class ExecutionResponse(BaseModel):
    id: int
    workflow_id: int
    trigger_type: str
    trigger_data: Optional[dict]
    status: str
    result_data: Optional[dict]
    error_message: Optional[str]
    retry_count: int
    execution_time_ms: Optional[int]
    created_at: str
    started_at: Optional[str]
    completed_at: Optional[str]

class TriggerWorkflowRequest(BaseModel):
    trigger_data: Optional[dict] = None

@router.post("", response_model=WorkflowResponse)
async def create_workflow(
    workflow: WorkflowCreate,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Create a new workflow"""
    workflow_service = WorkflowService(db)
    
    try:
        workflow_record = workflow_service.create_workflow(
            name=workflow.name,
            description=workflow.description,
            workflow_config=workflow.workflow_config,
            trigger_config=workflow.trigger_config,
            cron_schedule=workflow.cron_schedule,
            is_scheduled=workflow.is_scheduled,
            trigger_on_file_upload=workflow.trigger_on_file_upload,
            trigger_file_extensions=workflow.trigger_file_extensions,
            timeout_seconds=workflow.timeout_seconds
        )
        
        return _workflow_to_response(workflow_record)
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create workflow: {str(e)}")

@router.get("", response_model=List[WorkflowResponse])
async def list_workflows(
    status: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """List workflows with optional filtering"""
    workflow_service = WorkflowService(db)
    workflows = workflow_service.list_workflows(status=status, limit=limit, offset=offset)
    
    return [_workflow_to_response(w) for w in workflows]

@router.get("/{workflow_id}", response_model=WorkflowResponse)
async def get_workflow(
    workflow_id: int,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get workflow details"""
    workflow_service = WorkflowService(db)
    workflow = workflow_service.get_workflow(workflow_id)
    
    if not workflow:
        raise HTTPException(status_code=404, detail="Workflow not found")
    
    return _workflow_to_response(workflow)

@router.put("/{workflow_id}", response_model=WorkflowResponse)
async def update_workflow(
    workflow_id: int,
    workflow_update: WorkflowUpdate,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Update a workflow"""
    workflow_service = WorkflowService(db)
    
    try:
        workflow = workflow_service.update_workflow(workflow_id, workflow_update.dict(exclude_unset=True))
        
        if not workflow:
            raise HTTPException(status_code=404, detail="Workflow not found")
        
        return _workflow_to_response(workflow)
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update workflow: {str(e)}")

@router.delete("/{workflow_id}")
async def delete_workflow(
    workflow_id: int,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Delete a workflow"""
    workflow_service = WorkflowService(db)
    
    if not workflow_service.delete_workflow(workflow_id):
        raise HTTPException(status_code=404, detail="Workflow not found")
    
    return {"message": "Workflow deleted successfully", "workflow_id": workflow_id}

@router.post("/{workflow_id}/trigger")
async def trigger_workflow(
    workflow_id: int,
    background_tasks: BackgroundTasks,
    request: TriggerWorkflowRequest = TriggerWorkflowRequest(),
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Manually trigger a workflow execution"""
    workflow_service = WorkflowService(db)
    workflow = workflow_service.get_workflow(workflow_id)
    
    if not workflow:
        raise HTTPException(status_code=404, detail="Workflow not found")
    
    if not workflow.is_executable:
        raise HTTPException(
            status_code=400,
            detail=f"Workflow cannot be executed (status: {workflow.status.value}, enabled: {workflow.is_enabled})"
        )
    
    try:
        execution = workflow_service.create_execution(
            workflow_id=workflow_id,
            trigger_type="manual",
            trigger_data=request.trigger_data
        )
        
        # Schedule background execution
        background_tasks.add_task(
            workflow_service.execute_workflow_async,
            execution.id
        )
        
        return {
            "message": "Workflow execution started",
            "execution_id": execution.id,
            "workflow_id": workflow_id
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to trigger workflow: {str(e)}")

@router.get("/{workflow_id}/executions", response_model=List[ExecutionResponse])
async def get_workflow_executions(
    workflow_id: int,
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """Get executions for a specific workflow"""
    workflow_service = WorkflowService(db)
    executions = workflow_service.get_workflow_executions(
        workflow_id=workflow_id,
        status=status,
        limit=limit,
        offset=offset
    )
    
    return [_execution_to_response(e) for e in executions]

# Add executions endpoint at root level for backward compatibility
@router.get("/executions", response_model=List[ExecutionResponse])
async def list_executions(
    workflow_id: Optional[int] = None,
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
    api_key: str = Depends(verify_api_key)
):
    """List workflow executions with optional filtering"""
    workflow_service = WorkflowService(db)
    executions = workflow_service.list_executions(
        workflow_id=workflow_id,
        status=status,
        limit=limit,
        offset=offset
    )
    
    return [_execution_to_response(e) for e in executions]

def _workflow_to_response(workflow: WorkflowModel) -> WorkflowResponse:
    """Convert workflow model to response"""
    return WorkflowResponse(
        id=workflow.id,
        name=workflow.name,
        description=workflow.description,
        workflow_config=json.loads(workflow.workflow_config) if workflow.workflow_config else {},
        trigger_config=json.loads(workflow.trigger_config) if workflow.trigger_config else None,
        cron_schedule=workflow.cron_schedule,
        is_scheduled=workflow.is_scheduled,
        trigger_on_file_upload=workflow.trigger_on_file_upload,
        trigger_file_extensions=workflow.trigger_file_extensions,
        status=workflow.status.value,
        is_enabled=workflow.is_enabled,
        total_executions=workflow.total_executions,
        successful_executions=workflow.successful_executions,
        failed_executions=workflow.failed_executions,
        last_execution_at=workflow.last_execution_at.isoformat() if workflow.last_execution_at else None,
        created_at=workflow.created_at.isoformat(),
        updated_at=workflow.updated_at.isoformat()
    )

def _execution_to_response(execution: ExecutionModel) -> ExecutionResponse:
    """Convert execution model to response"""
    return ExecutionResponse(
        id=execution.id,
        workflow_id=execution.workflow_id,
        trigger_type=execution.trigger_type,
        trigger_data=json.loads(execution.trigger_data) if execution.trigger_data else None,
        status=execution.status.value,
        result_data=json.loads(execution.result_data) if execution.result_data else None,
        error_message=execution.error_message,
        retry_count=execution.retry_count,
        execution_time_ms=execution.execution_time_ms,
        created_at=execution.created_at.isoformat(),
        started_at=execution.started_at.isoformat() if execution.started_at else None,
        completed_at=execution.completed_at.isoformat() if execution.completed_at else None
    )