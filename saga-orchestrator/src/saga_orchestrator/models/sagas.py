"""SAGA models for orchestrator."""

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Dict, Any, List, Optional

from pydantic import BaseModel, Field


class SagaStatus(str, Enum):
    """SAGA execution status."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    COMPENSATING = "compensating"
    FAILED = "failed"
    COMPENSATED = "compensated"


class SagaStep(BaseModel):
    """Individual step in a SAGA."""
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str
    service: str
    command: Dict[str, Any]
    compensation_command: Optional[Dict[str, Any]] = None
    timeout_seconds: int = 300
    retry_attempts: int = 3
    status: str = "pending"
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    error_message: Optional[str] = None
    result: Optional[Dict[str, Any]] = None


class SagaInstance(BaseModel):
    """SAGA orchestrator instance."""
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: str
    status: SagaStatus = SagaStatus.PENDING
    steps: List[SagaStep]
    current_step: int = 0
    input_data: Dict[str, Any] = Field(default_factory=dict)
    output_data: Dict[str, Any] = Field(default_factory=dict)
    error_message: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    correlation_id: Optional[str] = None
    tenant_id: Optional[str] = None
    
    def get_current_step(self) -> Optional[SagaStep]:
        """Get the current step being executed."""
        if 0 <= self.current_step < len(self.steps):
            return self.steps[self.current_step]
        return None
    
    def is_completed(self) -> bool:
        """Check if SAGA is completed (successfully or with compensation)."""
        return self.status in [SagaStatus.COMPLETED, SagaStatus.COMPENSATED]
    
    def is_failed(self) -> bool:
        """Check if SAGA has failed."""
        return self.status == SagaStatus.FAILED
    
    def get_completed_steps(self) -> List[SagaStep]:
        """Get all completed steps that may need compensation."""
        return [step for step in self.steps if step.status == "completed"]


class SagaDefinition(BaseModel):
    """Template for creating SAGA instances."""
    name: str
    description: str
    steps: List[SagaStep]
    timeout_seconds: int = 3600
    
    def create_instance(
        self, 
        input_data: Dict[str, Any],
        correlation_id: Optional[str] = None,
        tenant_id: Optional[str] = None
    ) -> SagaInstance:
        """Create a new SAGA instance from this definition."""
        return SagaInstance(
            type=self.name,
            steps=self.steps.copy(),
            input_data=input_data,
            correlation_id=correlation_id or str(uuid.uuid4()),
            tenant_id=tenant_id,
            started_at=datetime.now(timezone.utc)
        )