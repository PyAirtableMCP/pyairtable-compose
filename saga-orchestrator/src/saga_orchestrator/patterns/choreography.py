"""Choreography pattern implementation for SAGA transactions.

In choreography pattern, each service knows about the next step and publishes
events that trigger the next service in the chain. This provides loose coupling
but requires careful event design.
"""

import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Set

from ..event_bus.base import EventBus
from ..models.events import Event, EventType
from ..models.sagas import SagaInstance, SagaStep, SagaStatus
from ..saga_engine.event_store import EventStore

logger = logging.getLogger(__name__)


class ChoreographyCoordinator:
    """Coordinates SAGA execution using choreography pattern."""
    
    def __init__(self, event_store: EventStore, event_bus: EventBus):
        self.event_store = event_store
        self.event_bus = event_bus
        self.active_sagas: Dict[str, SagaInstance] = {}
        self.event_handlers: Dict[str, callable] = {}
        self.service_dependencies: Dict[str, List[str]] = {}
        
    async def start(self) -> None:
        """Start choreography coordinator and event subscriptions."""
        await self._setup_event_handlers()
        logger.info("Choreography coordinator started")
    
    async def _setup_event_handlers(self) -> None:
        """Set up event handlers for choreography pattern."""
        # Subscribe to service completion events
        await self.event_bus.subscribe(
            topics=[
                "pyairtable.service.*.completed",
                "pyairtable.service.*.failed",
                "pyairtable.choreography.step_completed",
                "pyairtable.choreography.step_failed"
            ],
            consumer_group="choreography-coordinator",
            handler=self._handle_choreography_event
        )
        
        # Subscribe to saga events
        await self.event_bus.subscribe(
            topics=[
                "pyairtable.saga.choreography_started",
                "pyairtable.saga.compensation_requested"
            ],
            consumer_group="choreography-saga-handler",
            handler=self._handle_saga_choreography_event
        )
    
    async def start_choreography_saga(
        self,
        saga_id: str,
        saga_type: str,
        steps: List[SagaStep],
        input_data: Dict[str, Any],
        correlation_id: str
    ) -> None:
        """Start a SAGA using choreography pattern."""
        try:
            saga = SagaInstance(
                id=saga_id,
                type=saga_type,
                status=SagaStatus.RUNNING,
                steps=steps,
                input_data=input_data,
                correlation_id=correlation_id,
                started_at=datetime.now(timezone.utc)
            )
            
            self.active_sagas[saga_id] = saga
            
            # Emit choreography started event
            start_event = Event(
                type=EventType.SAGA_STARTED,
                aggregate_id=saga_id,
                aggregate_type="choreography_saga",
                version=1,
                data={
                    "saga_type": saga_type,
                    "pattern": "choreography",
                    "steps": [{"id": step.id, "service": step.service, "name": step.name} for step in steps],
                    "input_data": input_data
                },
                correlation_id=correlation_id
            )
            
            await self.event_store.append_events(f"choreography-saga-{saga_id}", [start_event])
            await self.event_bus.publish_event(start_event, "pyairtable.saga.choreography_started")
            
            # Start first step by publishing initial event
            await self._trigger_first_step(saga)
            
            logger.info(f"Started choreography SAGA {saga_id} with {len(steps)} steps")
            
        except Exception as e:
            logger.error(f"Failed to start choreography SAGA {saga_id}: {e}")
            raise
    
    async def _trigger_first_step(self, saga: SagaInstance) -> None:
        """Trigger the first step in choreography chain."""
        if not saga.steps:
            await self._complete_choreography_saga(saga)
            return
        
        first_step = saga.steps[0]
        first_step.status = "running"
        first_step.started_at = datetime.now(timezone.utc)
        
        # Create trigger event for first service
        trigger_event = Event(
            type=EventType.COMMAND_ISSUED,
            aggregate_id=saga.id,
            aggregate_type="choreography_step",
            version=1,
            data={
                "saga_id": saga.id,
                "step_id": first_step.id,
                "step_name": first_step.name,
                "service": first_step.service,
                "command": first_step.command,
                "input_data": saga.input_data,
                "next_services": self._get_next_services(saga, 0),
                "pattern": "choreography"
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"choreography-saga-{saga.id}", [trigger_event])
        await self.event_bus.publish_event(
            trigger_event, 
            f"pyairtable.choreography.{first_step.service}.execute"
        )
        
        logger.info(f"Triggered first step '{first_step.name}' for choreography SAGA {saga.id}")
    
    def _get_next_services(self, saga: SagaInstance, current_step_index: int) -> List[str]:
        """Get the services that should be triggered next."""
        next_services = []
        
        # Simple sequential pattern - next step in sequence
        if current_step_index + 1 < len(saga.steps):
            next_step = saga.steps[current_step_index + 1]
            next_services.append(next_step.service)
        
        # You could implement more complex dependency logic here
        # For example, parallel steps or conditional branching
        
        return next_services
    
    async def _handle_choreography_event(self, event: Event) -> None:
        """Handle choreography coordination events."""
        try:
            saga_id = event.data.get("saga_id")
            if not saga_id or saga_id not in self.active_sagas:
                logger.debug(f"Choreography event for unknown saga: {saga_id}")
                return
            
            saga = self.active_sagas[saga_id]
            step_id = event.data.get("step_id")
            
            if event.type == EventType.COMMAND_COMPLETED:
                await self._handle_choreography_step_completed(saga, step_id, event.data)
            elif event.type == EventType.COMMAND_FAILED:
                await self._handle_choreography_step_failed(saga, step_id, event.data)
            
        except Exception as e:
            logger.error(f"Error handling choreography event {event.id}: {e}")
    
    async def _handle_choreography_step_completed(
        self,
        saga: SagaInstance,
        step_id: str,
        event_data: Dict[str, Any]
    ) -> None:
        """Handle successful completion of a choreography step."""
        try:
            # Find and update the completed step
            step = next((s for s in saga.steps if s.id == step_id), None)
            if not step:
                logger.error(f"Step {step_id} not found in saga {saga.id}")
                return
            
            step.status = "completed"
            step.completed_at = datetime.now(timezone.utc)
            step.result = event_data.get("result", {})
            
            # Update saga output data
            if step.result:
                saga.output_data.update(step.result)
            
            # Move to next step
            saga.current_step += 1
            
            logger.info(f"Choreography step '{step.name}' completed for SAGA {saga.id}")
            
            # Check if saga is complete
            if saga.current_step >= len(saga.steps):
                await self._complete_choreography_saga(saga)
                return
            
            # Trigger next step in choreography
            await self._trigger_next_choreography_step(saga)
            
        except Exception as e:
            logger.error(f"Error handling choreography step completion: {e}")
            await self._fail_choreography_saga(saga, str(e))
    
    async def _handle_choreography_step_failed(
        self,
        saga: SagaInstance,
        step_id: str,
        event_data: Dict[str, Any]
    ) -> None:
        """Handle failure of a choreography step."""
        try:
            step = next((s for s in saga.steps if s.id == step_id), None)
            if not step:
                logger.error(f"Step {step_id} not found in saga {saga.id}")
                return
            
            step.status = "failed"
            step.completed_at = datetime.now(timezone.utc)
            step.error_message = event_data.get("error", "Unknown error")
            
            logger.error(f"Choreography step '{step.name}' failed for SAGA {saga.id}: {step.error_message}")
            
            # Start choreography compensation
            await self._start_choreography_compensation(saga)
            
        except Exception as e:
            logger.error(f"Error handling choreography step failure: {e}")
    
    async def _trigger_next_choreography_step(self, saga: SagaInstance) -> None:
        """Trigger the next step in choreography chain."""
        if saga.current_step >= len(saga.steps):
            await self._complete_choreography_saga(saga)
            return
        
        next_step = saga.steps[saga.current_step]
        next_step.status = "running"
        next_step.started_at = datetime.now(timezone.utc)
        
        # Create event to trigger next service
        trigger_event = Event(
            type=EventType.COMMAND_ISSUED,
            aggregate_id=saga.id,
            aggregate_type="choreography_step",
            version=saga.current_step + 1,
            data={
                "saga_id": saga.id,
                "step_id": next_step.id,
                "step_name": next_step.name,
                "service": next_step.service,
                "command": next_step.command,
                "previous_output": saga.output_data,
                "next_services": self._get_next_services(saga, saga.current_step),
                "pattern": "choreography"
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"choreography-saga-{saga.id}", [trigger_event])
        await self.event_bus.publish_event(
            trigger_event,
            f"pyairtable.choreography.{next_step.service}.execute"
        )
        
        logger.info(f"Triggered choreography step '{next_step.name}' for SAGA {saga.id}")
    
    async def _complete_choreography_saga(self, saga: SagaInstance) -> None:
        """Complete a choreography SAGA."""
        saga.status = SagaStatus.COMPLETED
        saga.completed_at = datetime.now(timezone.utc)
        
        # Emit completion event
        completion_event = Event(
            type=EventType.SAGA_COMPLETED,
            aggregate_id=saga.id,
            aggregate_type="choreography_saga",
            version=len(saga.steps) + 1,
            data={
                "pattern": "choreography",
                "output_data": saga.output_data,
                "completed_steps": len(saga.steps)
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"choreography-saga-{saga.id}", [completion_event])
        await self.event_bus.publish_event(completion_event, "pyairtable.saga.choreography_completed")
        
        # Cleanup
        del self.active_sagas[saga.id]
        
        logger.info(f"Choreography SAGA {saga.id} completed successfully")
    
    async def _start_choreography_compensation(self, saga: SagaInstance) -> None:
        """Start compensation process for choreography SAGA."""
        saga.status = SagaStatus.COMPENSATING
        
        # Get completed steps in reverse order
        completed_steps = [
            step for step in reversed(saga.steps[:saga.current_step])
            if step.status == "completed" and step.compensation_command
        ]
        
        if not completed_steps:
            await self._complete_choreography_compensation(saga)
            return
        
        # Emit compensation events for each service
        compensation_events = []
        for step in completed_steps:
            compensation_event = Event(
                type=EventType.COMPENSATION_COMMAND,
                aggregate_id=saga.id,
                aggregate_type="choreography_compensation",
                version=len(compensation_events) + 1,
                data={
                    "saga_id": saga.id,
                    "step_id": step.id,
                    "service": step.service,
                    "compensation_command": step.compensation_command,
                    "pattern": "choreography"
                },
                correlation_id=saga.correlation_id
            )
            compensation_events.append(compensation_event)
        
        # Store and publish compensation events
        await self.event_store.append_events(f"choreography-saga-{saga.id}", compensation_events)
        
        for i, (step, event) in enumerate(zip(completed_steps, compensation_events)):
            # Add delay between compensation events to avoid overwhelming services
            if i > 0:
                await asyncio.sleep(0.1)
            
            await self.event_bus.publish_event(
                event,
                f"pyairtable.choreography.{step.service}.compensate"
            )
        
        # Set timeout for compensation completion
        asyncio.create_task(self._compensation_timeout(saga.id, 30.0))  # 30 second timeout
        
        logger.info(f"Started choreography compensation for SAGA {saga.id} with {len(completed_steps)} steps")
    
    async def _complete_choreography_compensation(self, saga: SagaInstance) -> None:
        """Complete compensation process."""
        saga.status = SagaStatus.COMPENSATED
        saga.completed_at = datetime.now(timezone.utc)
        
        # Emit compensated event
        compensated_event = Event(
            type=EventType.SAGA_COMPENSATED,
            aggregate_id=saga.id,
            aggregate_type="choreography_saga",
            version=len(saga.steps) + 10,
            data={
                "pattern": "choreography",
                "compensated_at": saga.completed_at.isoformat()
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"choreography-saga-{saga.id}", [compensated_event])
        await self.event_bus.publish_event(compensated_event, "pyairtable.saga.choreography_compensated")
        
        # Cleanup
        del self.active_sagas[saga.id]
        
        logger.info(f"Choreography SAGA {saga.id} compensation completed")
    
    async def _fail_choreography_saga(self, saga: SagaInstance, error: str) -> None:
        """Handle choreography SAGA failure."""
        saga.status = SagaStatus.COMPENSATING
        saga.error_message = error
        
        await self._start_choreography_compensation(saga)
    
    async def _compensation_timeout(self, saga_id: str, timeout_seconds: float) -> None:
        """Handle compensation timeout."""
        await asyncio.sleep(timeout_seconds)
        
        if saga_id in self.active_sagas:
            saga = self.active_sagas[saga_id]
            if saga.status == SagaStatus.COMPENSATING:
                logger.warning(f"Choreography compensation timed out for SAGA {saga_id}")
                # Force complete compensation
                await self._complete_choreography_compensation(saga)
    
    async def _handle_saga_choreography_event(self, event: Event) -> None:
        """Handle saga-level choreography events."""
        try:
            if event.type.value == "saga_choreography_started":
                # Handle choreography saga initialization
                pass
            elif event.type.value == "compensation_requested":
                saga_id = event.data.get("saga_id")
                if saga_id in self.active_sagas:
                    saga = self.active_sagas[saga_id]
                    await self._start_choreography_compensation(saga)
        
        except Exception as e:
            logger.error(f"Error handling saga choreography event: {e}")
    
    def get_choreography_status(self, saga_id: str) -> Optional[Dict[str, Any]]:
        """Get status of choreography SAGA."""
        if saga_id not in self.active_sagas:
            return None
        
        saga = self.active_sagas[saga_id]
        return {
            "saga_id": saga_id,
            "pattern": "choreography",
            "status": saga.status.value,
            "current_step": saga.current_step,
            "total_steps": len(saga.steps),
            "started_at": saga.started_at.isoformat() if saga.started_at else None,
            "completed_at": saga.completed_at.isoformat() if saga.completed_at else None,
            "error_message": saga.error_message,
            "steps": [
                {
                    "id": step.id,
                    "name": step.name,
                    "service": step.service,
                    "status": step.status,
                    "started_at": step.started_at.isoformat() if step.started_at else None,
                    "completed_at": step.completed_at.isoformat() if step.completed_at else None,
                    "error_message": step.error_message
                }
                for step in saga.steps
            ]
        }
    
    async def list_choreography_sagas(self) -> List[Dict[str, Any]]:
        """List all active choreography SAGAs."""
        return [
            self.get_choreography_status(saga_id)
            for saga_id in self.active_sagas.keys()
        ]