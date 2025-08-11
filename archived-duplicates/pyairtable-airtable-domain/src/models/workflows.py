"""Workflow and automation data models."""

from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional
from uuid import UUID

from pydantic import BaseModel, Field, validator
from sqlalchemy import Column, String, Text, JSON, Integer, Boolean, DateTime, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from ..database.base import Base


# Enums

class WorkflowStatus(str, Enum):
    """Workflow status enumeration."""
    DRAFT = "draft"
    ACTIVE = "active"
    PAUSED = "paused"
    ARCHIVED = "archived"


class ExecutionStatus(str, Enum):
    """Execution status enumeration."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TriggerType(str, Enum):
    """Trigger type enumeration."""
    MANUAL = "manual"
    SCHEDULE = "schedule"
    WEBHOOK = "webhook"
    RECORD_CHANGE = "record_change"
    API_CALL = "api_call"


class ActionType(str, Enum):
    """Action type enumeration."""
    AIRTABLE_CREATE = "airtable_create"
    AIRTABLE_UPDATE = "airtable_update"
    AIRTABLE_DELETE = "airtable_delete"
    HTTP_REQUEST = "http_request"
    EMAIL_SEND = "email_send"
    TRANSFORM_DATA = "transform_data"
    CONDITIONAL_LOGIC = "conditional_logic"
    DELAY = "delay"


# SQLAlchemy Models

class Workflow(Base):
    """Workflow definition."""
    
    __tablename__ = "workflows"
    
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    status = Column(SQLEnum(WorkflowStatus), nullable=False, default=WorkflowStatus.DRAFT)
    trigger_config = Column(JSON, nullable=False)
    actions_config = Column(JSON, nullable=False)
    settings = Column(JSON, nullable=True)
    created_by = Column(String(255), nullable=True)
    last_execution_at = Column(DateTime(timezone=True), nullable=True)
    execution_count = Column(Integer, nullable=False, default=0)
    success_count = Column(Integer, nullable=False, default=0)
    failure_count = Column(Integer, nullable=False, default=0)
    is_active = Column(Boolean, default=True, nullable=False)


class WorkflowExecution(Base):
    """Workflow execution instance."""
    
    __tablename__ = "workflow_executions"
    
    workflow_id = Column(PGUUID(as_uuid=True), nullable=False, index=True)
    trigger_data = Column(JSON, nullable=True)
    status = Column(SQLEnum(ExecutionStatus), nullable=False, default=ExecutionStatus.PENDING)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    error_message = Column(Text, nullable=True)
    execution_log = Column(JSON, nullable=True)
    result_data = Column(JSON, nullable=True)
    triggered_by = Column(String(255), nullable=True)


class WorkflowStep(Base):
    """Individual workflow step execution."""
    
    __tablename__ = "workflow_steps"
    
    execution_id = Column(PGUUID(as_uuid=True), nullable=False, index=True)
    step_index = Column(Integer, nullable=False)
    step_name = Column(String(255), nullable=False)
    action_type = Column(SQLEnum(ActionType), nullable=False)
    status = Column(SQLEnum(ExecutionStatus), nullable=False, default=ExecutionStatus.PENDING)
    input_data = Column(JSON, nullable=True)
    output_data = Column(JSON, nullable=True)
    error_message = Column(Text, nullable=True)
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    duration_ms = Column(Integer, nullable=True)


class ScheduledTask(Base):
    """Scheduled task for workflow automation."""
    
    __tablename__ = "scheduled_tasks"
    
    workflow_id = Column(PGUUID(as_uuid=True), nullable=False, index=True)
    task_name = Column(String(255), nullable=False)
    cron_expression = Column(String(100), nullable=False)
    timezone = Column(String(50), nullable=False, default="UTC")
    next_run_at = Column(DateTime(timezone=True), nullable=False)
    last_run_at = Column(DateTime(timezone=True), nullable=True)
    is_active = Column(Boolean, default=True, nullable=False)
    max_retries = Column(Integer, nullable=False, default=3)
    retry_delay_seconds = Column(Integer, nullable=False, default=60)


# Pydantic Models

class TriggerConfig(BaseModel):
    """Workflow trigger configuration."""
    
    type: TriggerType
    settings: Dict[str, Any] = Field(default_factory=dict)
    
    class Config:
        from_attributes = True


class ActionConfig(BaseModel):
    """Workflow action configuration."""
    
    name: str = Field(..., description="Action name")
    type: ActionType = Field(..., description="Action type")
    settings: Dict[str, Any] = Field(default_factory=dict, description="Action settings")
    retry_on_failure: bool = Field(False, description="Retry on failure")
    max_retries: int = Field(3, description="Maximum retry attempts")
    
    class Config:
        from_attributes = True


class WorkflowSchema(BaseModel):
    """Workflow schema."""
    
    id: Optional[UUID] = None
    name: str = Field(..., description="Workflow name")
    description: Optional[str] = Field(None, description="Workflow description")
    status: WorkflowStatus = Field(WorkflowStatus.DRAFT, description="Workflow status")
    trigger: TriggerConfig = Field(..., description="Trigger configuration")
    actions: List[ActionConfig] = Field(..., description="Action configurations")
    settings: Optional[Dict[str, Any]] = Field(None, description="Workflow settings")
    created_by: Optional[str] = Field(None, description="Creator user ID")
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    
    @validator("actions")
    def validate_actions(cls, v):
        """Validate actions list."""
        if not v:
            raise ValueError("At least one action is required")
        return v
    
    class Config:
        from_attributes = True


class CreateWorkflowRequest(BaseModel):
    """Request to create a workflow."""
    
    name: str = Field(..., description="Workflow name")
    description: Optional[str] = Field(None, description="Workflow description")
    trigger: TriggerConfig = Field(..., description="Trigger configuration")
    actions: List[ActionConfig] = Field(..., description="Action configurations")
    settings: Optional[Dict[str, Any]] = Field(None, description="Workflow settings")


class UpdateWorkflowRequest(BaseModel):
    """Request to update a workflow."""
    
    name: Optional[str] = Field(None, description="Workflow name")
    description: Optional[str] = Field(None, description="Workflow description")
    status: Optional[WorkflowStatus] = Field(None, description="Workflow status")
    trigger: Optional[TriggerConfig] = Field(None, description="Trigger configuration")
    actions: Optional[List[ActionConfig]] = Field(None, description="Action configurations")
    settings: Optional[Dict[str, Any]] = Field(None, description="Workflow settings")


class ExecutionSchema(BaseModel):
    """Workflow execution schema."""
    
    id: UUID
    workflow_id: UUID
    status: ExecutionStatus
    trigger_data: Optional[Dict[str, Any]]
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    error_message: Optional[str]
    result_data: Optional[Dict[str, Any]]
    triggered_by: Optional[str]
    created_at: datetime
    
    class Config:
        from_attributes = True


class ExecuteWorkflowRequest(BaseModel):
    """Request to execute a workflow."""
    
    trigger_data: Optional[Dict[str, Any]] = Field(None, description="Trigger data")
    async_execution: bool = Field(True, description="Execute asynchronously")


class WorkflowStepSchema(BaseModel):
    """Workflow step schema."""
    
    id: UUID
    execution_id: UUID
    step_index: int
    step_name: str
    action_type: ActionType
    status: ExecutionStatus
    input_data: Optional[Dict[str, Any]]
    output_data: Optional[Dict[str, Any]]
    error_message: Optional[str]
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    duration_ms: Optional[int]
    
    class Config:
        from_attributes = True


class ScheduledTaskSchema(BaseModel):
    """Scheduled task schema."""
    
    id: UUID
    workflow_id: UUID
    task_name: str
    cron_expression: str
    timezone: str
    next_run_at: datetime
    last_run_at: Optional[datetime]
    is_active: bool
    max_retries: int
    retry_delay_seconds: int
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class CreateScheduledTaskRequest(BaseModel):
    """Request to create a scheduled task."""
    
    workflow_id: UUID = Field(..., description="Workflow ID")
    task_name: str = Field(..., description="Task name")
    cron_expression: str = Field(..., description="Cron expression")
    timezone: str = Field("UTC", description="Timezone")
    max_retries: int = Field(3, description="Maximum retry attempts")
    retry_delay_seconds: int = Field(60, description="Retry delay in seconds")