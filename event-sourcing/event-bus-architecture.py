"""
PyAirtable Event Sourcing and SAGA Pattern Implementation
Production-ready event bus architecture with Apache Kafka
"""

import asyncio
import json
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from enum import Enum
from typing import Dict, List, Optional, Any, Type, Callable
import logging

from kafka import KafkaProducer, KafkaConsumer
from kafka.errors import KafkaError
import redis
from sqlalchemy import create_engine, Column, String, DateTime, Integer, JSON, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from pydantic import BaseModel, Field

# =============================================================================
# EVENT SOURCING FOUNDATION
# =============================================================================

class EventType(str, Enum):
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

@dataclass
class Event:
    """Base event class for event sourcing"""
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
        """Convert event to dictionary for serialization"""
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
        """Create event from dictionary"""
        return cls(
            id=data['id'],
            type=EventType(data['type']),
            aggregate_id=data['aggregate_id'],
            aggregate_type=data['aggregate_type'],
            version=data['version'],
            data=data['data'],
            metadata=data.get('metadata', {}),
            timestamp=datetime.fromisoformat(data['timestamp']),
            correlation_id=data.get('correlation_id'),
            causation_id=data.get('causation_id')
        )

# =============================================================================
# EVENT STORE IMPLEMENTATION
# =============================================================================

Base = declarative_base()

class EventStoreModel(Base):
    __tablename__ = 'event_store'
    
    id = Column(String, primary_key=True)
    stream_id = Column(String, index=True, nullable=False)
    version = Column(Integer, nullable=False)
    event_type = Column(String, nullable=False)
    event_data = Column(JSON, nullable=False)
    metadata = Column(JSON, default={})
    created_at = Column(DateTime, default=datetime.utcnow)
    correlation_id = Column(String, index=True)

class EventStore:
    """PostgreSQL-based event store with optimistic concurrency control"""
    
    def __init__(self, database_url: str):
        self.engine = create_engine(database_url)
        self.SessionLocal = sessionmaker(bind=self.engine)
        Base.metadata.create_all(self.engine)
        
    async def append_events(
        self, 
        stream_id: str, 
        events: List[Event], 
        expected_version: Optional[int] = None
    ) -> None:
        """Append events to stream with optimistic concurrency control"""
        session = self.SessionLocal()
        try:
            # Get current version
            current_version = session.query(EventStoreModel)\
                .filter(EventStoreModel.stream_id == stream_id)\
                .count()
            
            # Check optimistic concurrency
            if expected_version is not None and current_version != expected_version:
                raise ConcurrencyError(
                    f"Expected version {expected_version}, got {current_version}"
                )
            
            # Append events
            for i, event in enumerate(events):
                event_model = EventStoreModel(
                    id=event.id,
                    stream_id=stream_id,
                    version=current_version + i + 1,
                    event_type=event.type.value,
                    event_data=event.to_dict(),
                    metadata=event.metadata,
                    correlation_id=event.correlation_id
                )
                session.add(event_model)
            
            session.commit()
            
        except Exception as e:
            session.rollback()
            raise
        finally:
            session.close()
    
    async def read_stream(
        self, 
        stream_id: str, 
        from_version: int = 0,
        to_version: Optional[int] = None
    ) -> List[Event]:
        """Read events from stream"""
        session = self.SessionLocal()
        try:
            query = session.query(EventStoreModel)\
                .filter(EventStoreModel.stream_id == stream_id)\
                .filter(EventStoreModel.version >= from_version)
            
            if to_version:
                query = query.filter(EventStoreModel.version <= to_version)
                
            events = query.order_by(EventStoreModel.version).all()
            
            return [
                Event.from_dict(event.event_data) 
                for event in events
            ]
            
        finally:
            session.close()
    
    async def read_all_events(
        self, 
        from_position: int = 0,
        max_count: int = 1000
    ) -> List[Event]:
        """Read all events from all streams (for projections)"""
        session = self.SessionLocal()
        try:
            events = session.query(EventStoreModel)\
                .filter(EventStoreModel.id > from_position)\
                .order_by(EventStoreModel.created_at)\
                .limit(max_count)\
                .all()
            
            return [
                Event.from_dict(event.event_data) 
                for event in events
            ]
            
        finally:
            session.close()

class ConcurrencyError(Exception):
    """Raised when optimistic concurrency check fails"""
    pass

# =============================================================================
# EVENT BUS IMPLEMENTATION (Apache Kafka)
# =============================================================================

class EventBus:
    """Apache Kafka-based event bus for reliable event distribution"""
    
    def __init__(
        self, 
        bootstrap_servers: List[str],
        schema_registry_url: str = None
    ):
        self.bootstrap_servers = bootstrap_servers
        self.schema_registry_url = schema_registry_url
        self.producer = None
        self.consumers: Dict[str, KafkaConsumer] = {}
        self.handlers: Dict[EventType, List[Callable]] = {}
        self.logger = logging.getLogger(__name__)
    
    def start(self):
        """Initialize Kafka producer"""
        self.producer = KafkaProducer(
            bootstrap_servers=self.bootstrap_servers,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda k: k.encode('utf-8') if k else None,
            retries=3,
            acks='all',  # Wait for all replicas
            compression_type='snappy',
            batch_size=16384,
            linger_ms=5,  # Small delay for batching
            max_in_flight_requests_per_connection=1  # Ensure ordering
        )
    
    async def publish_event(self, event: Event, topic: str = None) -> None:
        """Publish event to Kafka topic"""
        if not self.producer:
            raise RuntimeError("Event bus not started")
        
        # Determine topic from event type if not specified
        if not topic:
            topic = f"pyairtable.{event.aggregate_type}.{event.type.value}"
        
        try:
            # Use aggregate_id as partition key for ordering
            future = self.producer.send(
                topic=topic,
                key=event.aggregate_id,
                value=event.to_dict(),
                headers=[
                    ('event_type', event.type.value.encode()),
                    ('correlation_id', (event.correlation_id or '').encode()),
                    ('timestamp', event.timestamp.isoformat().encode())
                ]
            )
            
            # Wait for confirmation
            record_metadata = future.get(timeout=10)
            
            self.logger.info(
                f"Event published: {event.type.value} to {topic} "
                f"(partition: {record_metadata.partition}, "
                f"offset: {record_metadata.offset})"
            )
            
        except KafkaError as e:
            self.logger.error(f"Failed to publish event: {e}")
            raise
    
    def subscribe(
        self, 
        topics: List[str], 
        consumer_group: str,
        handler: Callable[[Event], None]
    ) -> None:
        """Subscribe to events from topics"""
        consumer = KafkaConsumer(
            *topics,
            bootstrap_servers=self.bootstrap_servers,
            group_id=consumer_group,
            auto_offset_reset='earliest',
            enable_auto_commit=True,
            auto_commit_interval_ms=1000,
            value_deserializer=lambda v: json.loads(v.decode('utf-8')),
            consumer_timeout_ms=1000
        )
        
        self.consumers[consumer_group] = consumer
        
        # Start consumer loop in background
        asyncio.create_task(self._consume_events(consumer, handler))
    
    async def _consume_events(
        self, 
        consumer: KafkaConsumer, 
        handler: Callable[[Event], None]
    ) -> None:
        """Consume events from Kafka topics"""
        try:
            for message in consumer:
                try:
                    event = Event.from_dict(message.value)
                    await handler(event)
                    
                except Exception as e:
                    self.logger.error(
                        f"Error processing event: {e}", 
                        extra={'event': message.value}
                    )
                    
        except Exception as e:
            self.logger.error(f"Consumer error: {e}")
    
    def stop(self):
        """Stop event bus and close connections"""
        if self.producer:
            self.producer.flush()
            self.producer.close()
        
        for consumer in self.consumers.values():
            consumer.close()

# =============================================================================
# SAGA PATTERN IMPLEMENTATION
# =============================================================================

class SagaStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    COMPENSATING = "compensating"
    FAILED = "failed"
    COMPENSATED = "compensated"

@dataclass
class SagaStep:
    """Individual step in a SAGA"""
    id: str
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

@dataclass
class SagaInstance:
    """SAGA orchestrator instance"""
    id: str
    type: str
    status: SagaStatus
    steps: List[SagaStep]
    current_step: int = 0
    input_data: Dict[str, Any] = None
    output_data: Dict[str, Any] = None
    error_message: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    correlation_id: Optional[str] = None

class SagaOrchestrator:
    """SAGA pattern orchestrator for distributed transactions"""
    
    def __init__(
        self, 
        event_store: EventStore, 
        event_bus: EventBus,
        redis_client: redis.Redis
    ):
        self.event_store = event_store
        self.event_bus = event_bus
        self.redis = redis_client
        self.logger = logging.getLogger(__name__)
        self.sagas: Dict[str, SagaInstance] = {}
    
    async def start_saga(
        self, 
        saga_type: str, 
        steps: List[SagaStep],
        input_data: Dict[str, Any] = None,
        correlation_id: str = None
    ) -> str:
        """Start a new SAGA instance"""
        saga_id = str(uuid.uuid4())
        
        saga = SagaInstance(
            id=saga_id,
            type=saga_type,
            status=SagaStatus.PENDING,
            steps=steps,
            input_data=input_data or {},
            correlation_id=correlation_id or str(uuid.uuid4()),
            started_at=datetime.now(timezone.utc)
        )
        
        # Store SAGA instance
        self.sagas[saga_id] = saga
        await self._persist_saga(saga)
        
        # Emit SAGA started event
        event = Event(
            type=EventType.WORKFLOW_STARTED,
            aggregate_id=saga_id,
            aggregate_type="saga",
            version=1,
            data={
                "saga_type": saga_type,
                "steps_count": len(steps),
                "input_data": input_data
            },
            correlation_id=correlation_id
        )
        
        await self.event_store.append_events(f"saga-{saga_id}", [event])
        await self.event_bus.publish_event(event, f"pyairtable.saga.started")
        
        # Start processing
        await self._process_next_step(saga)
        
        return saga_id
    
    async def _process_next_step(self, saga: SagaInstance) -> None:
        """Process the next step in the SAGA"""
        if saga.current_step >= len(saga.steps):
            # SAGA completed successfully
            saga.status = SagaStatus.COMPLETED
            saga.completed_at = datetime.now(timezone.utc)
            await self._persist_saga(saga)
            
            # Emit completion event
            event = Event(
                type=EventType.WORKFLOW_COMPLETED,
                aggregate_id=saga.id,
                aggregate_type="saga",
                version=saga.current_step + 1,
                data={"output_data": saga.output_data},
                correlation_id=saga.correlation_id
            )
            
            await self.event_store.append_events(f"saga-{saga.id}", [event])
            await self.event_bus.publish_event(event, f"pyairtable.saga.completed")
            return
        
        step = saga.steps[saga.current_step]
        step.status = "running"
        step.started_at = datetime.now(timezone.utc)
        saga.status = SagaStatus.RUNNING
        
        await self._persist_saga(saga)
        
        try:
            # Send command to target service
            command_event = Event(
                type=EventType.WORKFLOW_STEP_COMPLETED,  # This would be more specific
                aggregate_id=saga.id,
                aggregate_type="saga",
                version=saga.current_step + 1,
                data={
                    "step_id": step.id,
                    "service": step.service,
                    "command": step.command
                },
                correlation_id=saga.correlation_id
            )
            
            await self.event_bus.publish_event(
                command_event, 
                f"pyairtable.command.{step.service}"
            )
            
            # Set timeout for step
            await self._set_step_timeout(saga.id, step.id, step.timeout_seconds)
            
        except Exception as e:
            self.logger.error(f"Failed to execute SAGA step: {e}")
            await self._handle_step_failure(saga, step, str(e))
    
    async def handle_step_response(
        self, 
        saga_id: str, 
        step_id: str, 
        success: bool,
        result: Dict[str, Any] = None,
        error: str = None
    ) -> None:
        """Handle response from a SAGA step"""
        saga = self.sagas.get(saga_id)
        if not saga:
            self.logger.error(f"SAGA not found: {saga_id}")
            return
        
        step = next((s for s in saga.steps if s.id == step_id), None)
        if not step:
            self.logger.error(f"Step not found: {step_id}")
            return
        
        if success:
            step.status = "completed"
            step.completed_at = datetime.now(timezone.utc)
            
            # Update saga output with step result
            if result:
                saga.output_data = {**(saga.output_data or {}), **result}
            
            # Move to next step
            saga.current_step += 1
            await self._process_next_step(saga)
            
        else:
            await self._handle_step_failure(saga, step, error or "Unknown error")
    
    async def _handle_step_failure(
        self, 
        saga: SagaInstance, 
        step: SagaStep,
        error: str
    ) -> None:
        """Handle step failure and start compensation"""
        step.status = "failed"
        step.error_message = error
        step.completed_at = datetime.now(timezone.utc)
        
        saga.status = SagaStatus.COMPENSATING
        saga.error_message = error
        
        await self._persist_saga(saga)
        
        # Emit failure event
        event = Event(
            type=EventType.WORKFLOW_FAILED,
            aggregate_id=saga.id,
            aggregate_type="saga",
            version=saga.current_step + 1,
            data={
                "failed_step": step.id,
                "error": error
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"saga-{saga.id}", [event])
        await self.event_bus.publish_event(event, f"pyairtable.saga.failed")
        
        # Start compensation
        await self._start_compensation(saga)
    
    async def _start_compensation(self, saga: SagaInstance) -> None:
        """Execute compensation commands in reverse order"""
        compensation_steps = []
        
        # Collect completed steps that need compensation
        for i in range(saga.current_step - 1, -1, -1):
            step = saga.steps[i]
            if step.status == "completed" and step.compensation_command:
                compensation_steps.append(step)
        
        # Execute compensations
        for step in compensation_steps:
            try:
                compensation_event = Event(
                    type=EventType.WORKFLOW_STEP_COMPLETED,  # Would be more specific
                    aggregate_id=saga.id,
                    aggregate_type="saga",
                    version=len(saga.steps) + len(compensation_steps),
                    data={
                        "step_id": f"compensate-{step.id}",
                        "service": step.service,
                        "command": step.compensation_command
                    },
                    correlation_id=saga.correlation_id
                )
                
                await self.event_bus.publish_event(
                    compensation_event,
                    f"pyairtable.compensation.{step.service}"
                )
                
            except Exception as e:
                self.logger.error(f"Compensation failed for step {step.id}: {e}")
        
        # Mark SAGA as compensated
        saga.status = SagaStatus.COMPENSATED
        saga.completed_at = datetime.now(timezone.utc)
        await self._persist_saga(saga)
    
    async def _persist_saga(self, saga: SagaInstance) -> None:
        """Persist SAGA state to Redis"""
        saga_data = asdict(saga)
        # Convert datetime objects to ISO strings
        for key, value in saga_data.items():
            if isinstance(value, datetime):
                saga_data[key] = value.isoformat()
        
        await self.redis.setex(
            f"saga:{saga.id}",
            3600,  # 1 hour TTL
            json.dumps(saga_data, default=str)
        )
    
    async def _set_step_timeout(
        self, 
        saga_id: str, 
        step_id: str, 
        timeout_seconds: int
    ) -> None:
        """Set timeout for a SAGA step"""
        timeout_key = f"saga_timeout:{saga_id}:{step_id}"
        await self.redis.setex(timeout_key, timeout_seconds, "timeout")
        
        # In a real implementation, you'd have a background process
        # checking for timeouts and triggering compensation

# =============================================================================
# EXAMPLE SAGA DEFINITIONS
# =============================================================================

class UserOnboardingSaga:
    """Example SAGA for user onboarding process"""
    
    @staticmethod
    def create_steps(user_data: Dict[str, Any]) -> List[SagaStep]:
        return [
            SagaStep(
                id="create_auth_user",
                name="Create Authentication User",
                service="auth-service",
                command={
                    "action": "create_user",
                    "data": {
                        "email": user_data["email"],
                        "password": user_data["password"]
                    }
                },
                compensation_command={
                    "action": "delete_user",
                    "data": {"email": user_data["email"]}
                }
            ),
            SagaStep(
                id="create_user_profile",
                name="Create User Profile",
                service="user-service",
                command={
                    "action": "create_profile",
                    "data": {
                        "user_id": "{{previous_step_output.user_id}}",
                        "first_name": user_data.get("first_name"),
                        "last_name": user_data.get("last_name")
                    }
                },
                compensation_command={
                    "action": "delete_profile",
                    "data": {"user_id": "{{previous_step_output.user_id}}"}
                }
            ),
            SagaStep(
                id="setup_tenant",
                name="Setup Tenant",
                service="permission-service",
                command={
                    "action": "create_tenant",
                    "data": {
                        "user_id": "{{step_1_output.user_id}}",
                        "tenant_name": user_data.get("company_name"),
                        "plan": "free"
                    }
                },
                compensation_command={
                    "action": "delete_tenant",
                    "data": {"tenant_id": "{{current_step_output.tenant_id}}"}
                }
            ),
            SagaStep(
                id="send_welcome_email",
                name="Send Welcome Email",
                service="notification-service",
                command={
                    "action": "send_notification",
                    "data": {
                        "user_id": "{{step_1_output.user_id}}",
                        "template": "welcome_email",
                        "data": user_data
                    }
                }
                # No compensation needed for notification
            )
        ]

class AirtableIntegrationSaga:
    """SAGA for connecting an Airtable base"""
    
    @staticmethod
    def create_steps(integration_data: Dict[str, Any]) -> List[SagaStep]:
        return [
            SagaStep(
                id="validate_airtable_access",
                name="Validate Airtable Access",
                service="airtable-connector",
                command={
                    "action": "validate_access",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "api_key": integration_data["api_key"]
                    }
                }
            ),
            SagaStep(
                id="fetch_schema",
                name="Fetch Base Schema",
                service="schema-service",
                command={
                    "action": "fetch_schema",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "tenant_id": integration_data["tenant_id"]
                    }
                },
                compensation_command={
                    "action": "delete_schema",
                    "data": {"base_id": integration_data["base_id"]}
                }
            ),
            SagaStep(
                id="setup_webhook",
                name="Setup Airtable Webhook",
                service="webhook-service",
                command={
                    "action": "create_webhook",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "tenant_id": integration_data["tenant_id"],
                        "callback_url": integration_data["webhook_url"]
                    }
                },
                compensation_command={
                    "action": "delete_webhook",
                    "data": {"webhook_id": "{{current_step_output.webhook_id}}"}
                }
            ),
            SagaStep(
                id="initial_sync",
                name="Perform Initial Data Sync",
                service="data-sync-service",
                command={
                    "action": "full_sync",
                    "data": {
                        "base_id": integration_data["base_id"],
                        "tenant_id": integration_data["tenant_id"]
                    }
                },
                timeout_seconds=600  # 10 minutes for initial sync
            )
        ]

# =============================================================================
# EVENT HANDLERS AND PROJECTIONS
# =============================================================================

class EventHandler(ABC):
    """Base class for event handlers"""
    
    @abstractmethod
    async def handle(self, event: Event) -> None:
        """Handle an event"""
        pass

class UserProjectionHandler(EventHandler):
    """Maintains user read model from events"""
    
    def __init__(self, database_url: str):
        self.engine = create_engine(database_url)
        
    async def handle(self, event: Event) -> None:
        if event.type == EventType.USER_REGISTERED:
            await self._create_user_projection(event)
        elif event.type == EventType.USER_PROFILE_UPDATED:
            await self._update_user_projection(event)
    
    async def _create_user_projection(self, event: Event) -> None:
        """Create user projection from registration event"""
        # Implementation would insert into read model table
        pass
    
    async def _update_user_projection(self, event: Event) -> None:
        """Update user projection from profile update event"""
        # Implementation would update read model table
        pass

# =============================================================================
# USAGE EXAMPLE
# =============================================================================

async def main():
    """Example usage of the event sourcing and SAGA system"""
    
    # Initialize components
    event_store = EventStore("postgresql://user:pass@localhost/eventstore")
    event_bus = EventBus(["localhost:9092"])
    redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)
    
    saga_orchestrator = SagaOrchestrator(event_store, event_bus, redis_client)
    
    # Start event bus
    event_bus.start()
    
    # Example: Start user onboarding SAGA
    user_data = {
        "email": "newuser@example.com",
        "password": "secure_password",
        "first_name": "John",
        "last_name": "Doe",
        "company_name": "Acme Corp"
    }
    
    steps = UserOnboardingSaga.create_steps(user_data)
    saga_id = await saga_orchestrator.start_saga(
        saga_type="user_onboarding",
        steps=steps,
        input_data=user_data
    )
    
    print(f"Started user onboarding SAGA: {saga_id}")
    
    # Example: Start Airtable integration SAGA
    integration_data = {
        "base_id": "appXXXXXXXXXXXXXX",
        "api_key": "keyXXXXXXXXXXXXXX",
        "tenant_id": str(uuid.uuid4()),
        "webhook_url": "https://api.pyairtable.com/webhooks/receive"
    }
    
    integration_steps = AirtableIntegrationSaga.create_steps(integration_data)
    integration_saga_id = await saga_orchestrator.start_saga(
        saga_type="airtable_integration",
        steps=integration_steps,
        input_data=integration_data
    )
    
    print(f"Started Airtable integration SAGA: {integration_saga_id}")

if __name__ == "__main__":
    asyncio.run(main())