"""SAGA orchestrator implementation."""

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

import httpx
import redis.asyncio as redis

from ..core.config import Settings
from ..event_bus.base import EventBus
from ..models.events import Event, EventType, DomainEventAdapter
from ..models.sagas import SagaInstance, SagaStep, SagaStatus
from ..services.saga_definitions import UserOnboardingSaga, AirtableIntegrationSaga
from ..persistence.postgres_repository import PostgresSagaRepository
from .event_store import EventStore

logger = logging.getLogger(__name__)


class SagaOrchestrator:
    """SAGA pattern orchestrator for distributed transactions."""
    
    def __init__(
        self, 
        event_store: EventStore, 
        event_bus: EventBus,
        redis_client: redis.Redis,
        settings: Settings,
        postgres_repository: Optional[PostgresSagaRepository] = None
    ):
        self.event_store = event_store
        self.event_bus = event_bus
        self.redis = redis_client
        self.settings = settings
        self.postgres_repository = postgres_repository
        self.logger = logging.getLogger(__name__)
        self.sagas: Dict[str, SagaInstance] = {}
        self.http_client = httpx.AsyncClient(timeout=30.0)
    
    async def start_event_subscriptions(self) -> None:
        """Start listening for domain events that trigger SAGAs."""
        # Subscribe to user registration events
        await self.event_bus.subscribe(
            topics=["pyairtable.user.user.registered"],
            consumer_group="saga-orchestrator",
            handler=self._handle_domain_event
        )
        
        # Subscribe to SAGA response events
        await self.event_bus.subscribe(
            topics=[
                "pyairtable.saga.step_response",
                "pyairtable.command.response",
            ],
            consumer_group="saga-orchestrator-responses",
            handler=self._handle_saga_response
        )
        
        logger.info("Started event subscriptions for SAGA orchestrator")
    
    async def _handle_domain_event(self, event: Event) -> None:
        """Handle domain events that may trigger SAGAs."""
        try:
            logger.info(f"Received domain event: {event.type.value}")
            
            if event.type == EventType.USER_REGISTERED:
                await self._trigger_user_onboarding_saga(event)
            
        except Exception as e:
            logger.error(f"Error handling domain event {event.id}: {e}")
    
    async def _trigger_user_onboarding_saga(self, event: Event) -> None:
        """Trigger user onboarding SAGA from user registration event."""
        try:
            user_data = event.data
            
            # Create SAGA steps
            steps = UserOnboardingSaga.create_steps(user_data)
            
            # Start SAGA
            saga_id = await self.start_saga(
                saga_type="user_onboarding",
                steps=steps,
                input_data=user_data,
                correlation_id=event.correlation_id,
                tenant_id=event.metadata.get("tenant_id")
            )
            
            logger.info(f"Started user onboarding SAGA {saga_id} for user {user_data.get('email')}")
            
        except Exception as e:
            logger.error(f"Failed to trigger user onboarding SAGA: {e}")
    
    async def start_saga(
        self, 
        saga_type: str, 
        steps: List[SagaStep],
        input_data: Dict[str, Any] = None,
        correlation_id: str = None,
        tenant_id: str = None
    ) -> str:
        """Start a new SAGA instance."""
        saga_id = str(uuid.uuid4())
        
        saga = SagaInstance(
            id=saga_id,
            type=saga_type,
            status=SagaStatus.PENDING,
            steps=steps,
            input_data=input_data or {},
            correlation_id=correlation_id or str(uuid.uuid4()),
            tenant_id=tenant_id,
            started_at=datetime.now(timezone.utc)
        )
        
        # Store SAGA instance
        self.sagas[saga_id] = saga
        await self._persist_saga(saga)
        
        # Emit SAGA started event
        event = Event(
            type=EventType.SAGA_STARTED,
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
        """Process the next step in the SAGA."""
        if saga.current_step >= len(saga.steps):
            # SAGA completed successfully
            await self._complete_saga(saga)
            return
        
        step = saga.steps[saga.current_step]
        step.status = "running"
        step.started_at = datetime.now(timezone.utc)
        saga.status = SagaStatus.RUNNING
        
        await self._persist_saga(saga)
        
        try:
            # Execute step
            await self._execute_step(saga, step)
            
        except Exception as e:
            logger.error(f"Failed to execute SAGA step: {e}")
            await self._handle_step_failure(saga, step, str(e))
    
    async def _execute_step(self, saga: SagaInstance, step: SagaStep) -> None:
        """Execute a SAGA step by calling the target service."""
        service_url = self._get_service_url(step.service)
        command = step.command.copy()
        
        # Substitute variables from previous steps
        command = self._substitute_variables(command, saga)
        
        try:
            # Send HTTP request to service
            response = await self.http_client.post(
                f"{service_url}/commands",
                json={
                    "saga_id": saga.id,
                    "step_id": step.id,
                    "command": command,
                    "correlation_id": saga.correlation_id
                },
                headers={"X-API-Key": self.settings.api_key} if self.settings.api_key else {}
            )
            
            if response.status_code == 200:
                result = response.json()
                await self._handle_step_success(saga, step, result)
            else:
                await self._handle_step_failure(
                    saga, 
                    step, 
                    f"Service returned {response.status_code}: {response.text}"
                )
                
        except Exception as e:
            await self._handle_step_failure(saga, step, str(e))
    
    def _get_service_url(self, service: str) -> str:
        """Get the URL for a service."""
        service_urls = {
            "auth-service": self.settings.auth_service_url,
            "user-service": self.settings.user_service_url,
            "permission-service": self.settings.permission_service_url,
            "notification-service": self.settings.notification_service_url,
            "airtable-connector": self.settings.airtable_connector_url,
            "schema-service": self.settings.schema_service_url,
            "webhook-service": self.settings.webhook_service_url,
            "data-sync-service": self.settings.data_sync_service_url,
        }
        return service_urls.get(service, service)
    
    def _substitute_variables(self, command: Dict[str, Any], saga: SagaInstance) -> Dict[str, Any]:
        """Substitute variables in command from previous step outputs."""
        command_str = json.dumps(command)
        
        # Substitute from saga output data
        for key, value in saga.output_data.items():
            command_str = command_str.replace(f"{{{{output.{key}}}}}", str(value))
        
        # Substitute from input data
        for key, value in saga.input_data.items():
            command_str = command_str.replace(f"{{{{input.{key}}}}}", str(value))
        
        return json.loads(command_str)
    
    async def _handle_step_success(
        self, 
        saga: SagaInstance, 
        step: SagaStep, 
        result: Dict[str, Any]
    ) -> None:
        """Handle successful step completion."""
        step.status = "completed"
        step.completed_at = datetime.now(timezone.utc)
        step.result = result
        
        # Update saga output with step result
        if result:
            saga.output_data.update(result)
        
        # Move to next step
        saga.current_step += 1
        
        await self._persist_saga(saga)
        
        # Emit step completed event
        event = Event(
            type=EventType.SAGA_STEP_COMPLETED,
            aggregate_id=saga.id,
            aggregate_type="saga",
            version=saga.current_step,
            data={
                "step_id": step.id,
                "step_name": step.name,
                "result": result
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"saga-{saga.id}", [event])
        await self.event_bus.publish_event(event)
        
        # Process next step
        await self._process_next_step(saga)
    
    async def _handle_step_failure(
        self, 
        saga: SagaInstance, 
        step: SagaStep,
        error: str
    ) -> None:
        """Handle step failure and start compensation."""
        step.status = "failed"
        step.error_message = error
        step.completed_at = datetime.now(timezone.utc)
        
        saga.status = SagaStatus.COMPENSATING
        saga.error_message = error
        
        await self._persist_saga(saga)
        
        # Emit failure event
        event = Event(
            type=EventType.SAGA_FAILED,
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
        await self.event_bus.publish_event(event)
        
        # Start compensation
        await self._start_compensation(saga)
    
    async def _start_compensation(self, saga: SagaInstance) -> None:
        """Execute compensation commands in reverse order."""
        compensation_steps = []
        
        # Collect completed steps that need compensation
        for i in range(saga.current_step - 1, -1, -1):
            step = saga.steps[i]
            if step.status == "completed" and step.compensation_command:
                compensation_steps.append(step)
        
        # Execute compensations
        for step in compensation_steps:
            try:
                await self._execute_compensation(saga, step)
                
            except Exception as e:
                logger.error(f"Compensation failed for step {step.id}: {e}")
        
        # Mark SAGA as compensated
        saga.status = SagaStatus.COMPENSATED
        saga.completed_at = datetime.now(timezone.utc)
        await self._persist_saga(saga)
        
        # Emit compensated event
        event = Event(
            type=EventType.SAGA_COMPENSATED,
            aggregate_id=saga.id,
            aggregate_type="saga",
            version=len(saga.steps) + 1,
            data={"compensated_steps": len(compensation_steps)},
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"saga-{saga.id}", [event])
        await self.event_bus.publish_event(event)
    
    async def _execute_compensation(self, saga: SagaInstance, step: SagaStep) -> None:
        """Execute compensation for a completed step."""
        service_url = self._get_service_url(step.service)
        compensation_command = self._substitute_variables(step.compensation_command, saga)
        
        try:
            response = await self.http_client.post(
                f"{service_url}/compensations",
                json={
                    "saga_id": saga.id,
                    "step_id": step.id,
                    "command": compensation_command,
                    "correlation_id": saga.correlation_id
                },
                headers={"X-API-Key": self.settings.api_key} if self.settings.api_key else {}
            )
            
            if response.status_code != 200:
                logger.error(f"Compensation failed for step {step.id}: {response.text}")
                
        except Exception as e:
            logger.error(f"Failed to execute compensation for step {step.id}: {e}")
    
    async def _complete_saga(self, saga: SagaInstance) -> None:
        """Mark SAGA as completed."""
        saga.status = SagaStatus.COMPLETED
        saga.completed_at = datetime.now(timezone.utc)
        await self._persist_saga(saga)
        
        # Emit completion event
        event = Event(
            type=EventType.SAGA_COMPLETED,
            aggregate_id=saga.id,
            aggregate_type="saga",
            version=saga.current_step + 1,
            data={"output_data": saga.output_data},
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"saga-{saga.id}", [event])
        await self.event_bus.publish_event(event)
        
        logger.info(f"SAGA {saga.id} completed successfully")
    
    async def _persist_saga(self, saga: SagaInstance) -> None:
        """Persist SAGA state to PostgreSQL and Redis."""
        try:
            # Save to PostgreSQL for durability
            if self.postgres_repository:
                await self.postgres_repository.save_saga_instance(saga)
            
            # Also save to Redis for fast access (with TTL)
            saga_data = saga.dict()
            
            # Convert datetime objects to ISO strings
            for key, value in saga_data.items():
                if isinstance(value, datetime):
                    saga_data[key] = value.isoformat()
            
            # Handle nested datetime objects in steps
            for step in saga_data.get("steps", []):
                for field in ["started_at", "completed_at"]:
                    if step.get(field):
                        step[field] = step[field].isoformat() if isinstance(step[field], datetime) else step[field]
            
            await self.redis.setex(
                f"saga:{saga.id}",
                3600,  # 1 hour TTL
                json.dumps(saga_data, default=str)
            )
            
        except Exception as e:
            logger.error(f"Failed to persist SAGA {saga.id}: {e}")
    
    async def get_saga(self, saga_id: str) -> Optional[SagaInstance]:
        """Get SAGA instance by ID."""
        try:
            # Try to get from memory first
            if saga_id in self.sagas:
                return self.sagas[saga_id]
            
            # Try to get from Redis for fast access
            saga_data = await self.redis.get(f"saga:{saga_id}")
            if saga_data:
                data = json.loads(saga_data)
                saga = SagaInstance(**data)
                self.sagas[saga_id] = saga
                return saga
            
            # Fallback to PostgreSQL for persistent storage
            if self.postgres_repository:
                saga = await self.postgres_repository.get_saga_instance(saga_id)
                if saga:
                    self.sagas[saga_id] = saga
                    # Update Redis cache
                    await self._cache_saga_in_redis(saga)
                    return saga
            
            return None
            
        except Exception as e:
            logger.error(f"Failed to get SAGA {saga_id}: {e}")
            return None
    
    async def _cache_saga_in_redis(self, saga: SagaInstance) -> None:
        """Cache SAGA instance in Redis."""
        try:
            saga_data = saga.dict()
            
            # Convert datetime objects to ISO strings
            for key, value in saga_data.items():
                if isinstance(value, datetime):
                    saga_data[key] = value.isoformat()
            
            # Handle nested datetime objects in steps
            for step in saga_data.get("steps", []):
                for field in ["started_at", "completed_at"]:
                    if step.get(field):
                        step[field] = step[field].isoformat() if isinstance(step[field], datetime) else step[field]
            
            await self.redis.setex(
                f"saga:{saga.id}",
                3600,  # 1 hour TTL
                json.dumps(saga_data, default=str)
            )
        except Exception as e:
            logger.error(f"Failed to cache SAGA {saga.id} in Redis: {e}")
    
    async def _handle_saga_response(self, event: Event) -> None:
        """Handle responses from SAGA steps."""
        try:
            saga_id = event.data.get("saga_id")
            step_id = event.data.get("step_id")
            success = event.data.get("success", False)
            result = event.data.get("result", {})
            error = event.data.get("error")
            
            saga = await self.get_saga(saga_id)
            if not saga:
                logger.error(f"SAGA not found for response: {saga_id}")
                return
            
            step = next((s for s in saga.steps if s.id == step_id), None)
            if not step:
                logger.error(f"Step not found for response: {step_id}")
                return
            
            if success:
                await self._handle_step_success(saga, step, result)
            else:
                await self._handle_step_failure(saga, step, error or "Unknown error")
                
        except Exception as e:
            logger.error(f"Error handling SAGA response: {e}")
    
    async def list_sagas(
        self, 
        status: Optional[SagaStatus] = None,
        saga_type: Optional[str] = None,
        limit: int = 100,
        tenant_id: Optional[str] = None
    ) -> List[SagaInstance]:
        """List SAGA instances with optional filtering."""
        try:
            # Use PostgreSQL for comprehensive querying if available
            if self.postgres_repository:
                return await self.postgres_repository.list_saga_instances(
                    status=status,
                    saga_type=saga_type,
                    tenant_id=tenant_id,
                    limit=limit,
                    offset=0
                )
            
            # Fallback to Redis-based implementation
            sagas = []
            
            # Get saga keys from Redis
            keys = await self.redis.keys("saga:*")
            for key in keys[:limit]:
                saga_data = await self.redis.get(key)
                if saga_data:
                    data = json.loads(saga_data)
                    saga = SagaInstance(**data)
                    
                    # Apply filters
                    if status and saga.status != status:
                        continue
                    if saga_type and saga.type != saga_type:
                        continue
                    if tenant_id and saga.tenant_id != tenant_id:
                        continue
                    
                    sagas.append(saga)
            
            return sorted(sagas, key=lambda s: s.started_at or datetime.min, reverse=True)
            
        except Exception as e:
            logger.error(f"Failed to list SAGAs: {e}")
            return []