"""Event models for SAGA Orchestrator."""

import uuid
from datetime import datetime, timezone
from enum import Enum
from typing import Dict, Any, Optional

from pydantic import BaseModel, Field


class EventType(str, Enum):
    """Event types for the SAGA orchestrator."""
    
    # Auth Events
    USER_REGISTERED = "user.registered"
    USER_AUTHENTICATED = "user.authenticated"
    USER_PROFILE_UPDATED = "user.profile_updated"
    
    # Airtable Events
    BASE_CONNECTED = "airtable.base_connected"
    SCHEMA_UPDATED = "airtable.schema_updated"
    DATA_SYNCED = "airtable.data_synced"
    WEBHOOK_RECEIVED = "airtable.webhook_received"
    
    # File Events
    FILE_UPLOADED = "file.uploaded"
    FILE_PROCESSED = "file.processed"
    CONTENT_EXTRACTED = "file.content_extracted"
    
    # Workflow Events
    WORKFLOW_STARTED = "workflow.started"
    WORKFLOW_STEP_COMPLETED = "workflow.step_completed"
    WORKFLOW_COMPLETED = "workflow.completed"
    WORKFLOW_FAILED = "workflow.failed"
    
    # AI Events
    CONVERSATION_STARTED = "ai.conversation_started"
    MESSAGE_PROCESSED = "ai.message_processed"
    MODEL_RESPONSE_GENERATED = "ai.response_generated"
    
    # System Events
    SERVICE_STARTED = "system.service_started"
    SERVICE_HEALTH_CHECK = "system.health_check"
    ERROR_OCCURRED = "system.error_occurred"
    
    # SAGA Events
    SAGA_STARTED = "saga.started"
    SAGA_STEP_STARTED = "saga.step_started"
    SAGA_STEP_COMPLETED = "saga.step_completed"
    SAGA_STEP_FAILED = "saga.step_failed"
    SAGA_COMPLETED = "saga.completed"
    SAGA_FAILED = "saga.failed"
    SAGA_COMPENSATING = "saga.compensating"
    SAGA_COMPENSATED = "saga.compensated"
    
    # Command Events
    COMMAND_ISSUED = "command.issued"
    COMMAND_COMPLETED = "command.completed"
    COMMAND_FAILED = "command.failed"
    COMPENSATION_COMMAND = "compensation.command"


class Event(BaseModel):
    """Base event class for event sourcing."""
    
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    type: EventType
    aggregate_id: str
    aggregate_type: str
    version: int
    data: Dict[str, Any]
    metadata: Dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    correlation_id: Optional[str] = None
    causation_id: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert event to dictionary for serialization."""
        return {
            'id': self.id,
            'type': self.type.value,
            'aggregate_id': self.aggregate_id,
            'aggregate_type': self.aggregate_type,
            'version': self.version,
            'data': self.data,
            'metadata': self.metadata,
            'timestamp': self.timestamp.isoformat(),
            'correlation_id': self.correlation_id,
            'causation_id': self.causation_id
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Event':
        """Create event from dictionary."""
        # Handle string timestamp
        if isinstance(data.get('timestamp'), str):
            data['timestamp'] = datetime.fromisoformat(data['timestamp'])
        
        return cls(
            id=data['id'],
            type=EventType(data['type']),
            aggregate_id=data['aggregate_id'],
            aggregate_type=data['aggregate_type'],
            version=data['version'],
            data=data['data'],
            metadata=data.get('metadata', {}),
            timestamp=data.get('timestamp', datetime.now(timezone.utc)),
            correlation_id=data.get('correlation_id'),
            causation_id=data.get('causation_id')
        )


class DomainEventAdapter(BaseModel):
    """Adapter to convert Go DDD events to SAGA events."""
    
    @staticmethod
    def from_go_event(go_event_data: Dict[str, Any]) -> Event:
        """Convert Go domain event to SAGA Event."""
        # Map Go event fields to SAGA event fields
        event_type_mapping = {
            "user.registered": EventType.USER_REGISTERED,
            "user.activated": EventType.USER_AUTHENTICATED,
            "user.updated": EventType.USER_PROFILE_UPDATED,
            "workspace.created": EventType.WORKFLOW_STARTED,
            "tenant.created": EventType.WORKFLOW_STARTED,
        }
        
        event_type = event_type_mapping.get(
            go_event_data.get("event_type", ""),
            EventType.WORKFLOW_STARTED
        )
        
        return Event(
            id=go_event_data.get("event_id", str(uuid.uuid4())),
            type=event_type,
            aggregate_id=go_event_data.get("aggregate_id", ""),
            aggregate_type=go_event_data.get("aggregate_type", ""),
            version=go_event_data.get("version", 1),
            data=go_event_data.get("payload", {}),
            metadata={
                "tenant_id": go_event_data.get("tenant_id"),
                "source": "go-domain-event"
            },
            timestamp=datetime.fromisoformat(go_event_data.get("occurred_at", datetime.now(timezone.utc).isoformat())),
            correlation_id=go_event_data.get("correlation_id")
        )