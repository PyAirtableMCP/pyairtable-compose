from sqlalchemy import Column, Integer, String, DateTime, Text, Enum, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from enum import Enum as PyEnum
from datetime import datetime

Base = declarative_base()

class WorkflowStatus(PyEnum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    PAUSED = "paused"
    DELETED = "deleted"

class Workflow(Base):
    __tablename__ = "workflows"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    
    # Workflow definition
    workflow_config = Column(Text, nullable=False)  # JSON workflow definition
    trigger_config = Column(Text, nullable=True)   # JSON trigger configuration
    
    # Scheduling
    cron_schedule = Column(String(100), nullable=True)  # Cron expression
    is_scheduled = Column(Boolean, default=False)
    
    # File integration triggers
    trigger_on_file_upload = Column(Boolean, default=False)
    trigger_file_extensions = Column(String(255), nullable=True)  # Comma-separated extensions
    
    # Status and control
    status = Column(Enum(WorkflowStatus), default=WorkflowStatus.ACTIVE, nullable=False)
    is_enabled = Column(Boolean, default=True)
    
    # Execution settings
    max_retries = Column(Integer, default=3)
    timeout_seconds = Column(Integer, default=300)  # 5 minutes default
    
    # Statistics
    total_executions = Column(Integer, default=0)
    successful_executions = Column(Integer, default=0)
    failed_executions = Column(Integer, default=0)
    last_execution_at = Column(DateTime(timezone=True), nullable=True)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    
    def __repr__(self):
        return f"<Workflow(id={self.id}, name='{self.name}', status='{self.status.value}')>"
    
    @property
    def is_executable(self) -> bool:
        """Check if workflow can be executed"""
        return (
            self.status == WorkflowStatus.ACTIVE and 
            self.is_enabled and 
            self.deleted_at is None
        )
    
    @property
    def should_trigger_on_file(self, file_extension: str) -> bool:
        """Check if workflow should trigger on file upload"""
        if not self.trigger_on_file_upload or not self.is_executable:
            return False
            
        if not self.trigger_file_extensions:
            return True  # Trigger on all files
            
        allowed_extensions = [ext.strip().lower() for ext in self.trigger_file_extensions.split(',')]
        return file_extension.lower() in allowed_extensions