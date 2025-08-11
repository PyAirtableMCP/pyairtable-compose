from sqlalchemy import Column, Integer, String, DateTime, Text, Enum, ForeignKey
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from enum import Enum as PyEnum
from datetime import datetime

Base = declarative_base()

class ExecutionStatus(PyEnum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    TIMEOUT = "timeout"

class WorkflowExecution(Base):
    __tablename__ = "workflow_executions"
    
    id = Column(Integer, primary_key=True, index=True)
    workflow_id = Column(Integer, ForeignKey("workflows.id"), nullable=False)
    
    # Execution context
    trigger_type = Column(String(50), nullable=False)  # 'manual', 'scheduled', 'file_upload'
    trigger_data = Column(Text, nullable=True)  # JSON context data (file_id, user_id, etc.)
    
    # Execution details
    status = Column(Enum(ExecutionStatus), default=ExecutionStatus.PENDING, nullable=False)
    execution_config = Column(Text, nullable=True)  # JSON execution parameters
    
    # Results and logs
    result_data = Column(Text, nullable=True)  # JSON execution results
    log_output = Column(Text, nullable=True)   # Execution logs
    error_message = Column(Text, nullable=True)
    
    # File associations
    input_file_ids = Column(Text, nullable=True)   # JSON array of input file IDs
    output_file_ids = Column(Text, nullable=True)  # JSON array of output file IDs
    
    # Execution metadata
    retry_count = Column(Integer, default=0)
    execution_time_ms = Column(Integer, nullable=True)  # Execution duration in milliseconds
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    started_at = Column(DateTime(timezone=True), nullable=True)
    completed_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    def __repr__(self):
        return f"<WorkflowExecution(id={self.id}, workflow_id={self.workflow_id}, status='{self.status.value}')>"
    
    @property
    def is_running(self) -> bool:
        """Check if execution is currently running"""
        return self.status in [ExecutionStatus.PENDING, ExecutionStatus.RUNNING]
    
    @property 
    def is_completed(self) -> bool:
        """Check if execution is completed (success or failure)"""
        return self.status in [
            ExecutionStatus.COMPLETED,
            ExecutionStatus.FAILED,
            ExecutionStatus.CANCELLED,
            ExecutionStatus.TIMEOUT
        ]
    
    @property
    def can_retry(self) -> bool:
        """Check if execution can be retried"""
        return (
            self.status == ExecutionStatus.FAILED and 
            self.retry_count < 3
        )
    
    def calculate_duration(self) -> int:
        """Calculate execution duration in milliseconds"""
        if self.started_at and self.completed_at:
            delta = self.completed_at - self.started_at
            return int(delta.total_seconds() * 1000)
        return 0