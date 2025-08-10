"""Orchestration pattern implementation for SAGA transactions.

In orchestration pattern, a central coordinator manages all steps and makes
decisions about the workflow. This provides better control and monitoring
but creates a single point of failure.
"""

import asyncio
import logging
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Callable

import httpx

from ..event_bus.base import EventBus
from ..models.events import Event, EventType
from ..models.sagas import SagaInstance, SagaStep, SagaStatus
from ..saga_engine.event_store import EventStore

logger = logging.getLogger(__name__)


class OrchestrationController:
    """Controls SAGA execution using orchestration pattern."""
    
    def __init__(
        self,
        event_store: EventStore,
        event_bus: EventBus,
        service_registry: Optional[Dict[str, str]] = None
    ):
        self.event_store = event_store
        self.event_bus = event_bus
        self.service_registry = service_registry or {}
        self.active_sagas: Dict[str, SagaInstance] = {}
        self.step_handlers: Dict[str, Callable] = {}
        self.http_client = httpx.AsyncClient(timeout=30.0)
        self.compensation_strategies: Dict[str, str] = {}
        
    async def start(self) -> None:
        """Start orchestration controller and event subscriptions."""
        await self._setup_event_handlers()
        await self._register_step_handlers()
        logger.info("Orchestration controller started")
    
    async def _setup_event_handlers(self) -> None:
        """Set up event handlers for orchestration pattern."""
        # Subscribe to orchestration responses
        await self.event_bus.subscribe(
            topics=[
                "pyairtable.orchestration.step_response",
                "pyairtable.orchestration.compensation_response"
            ],
            consumer_group="orchestration-controller",
            handler=self._handle_orchestration_response
        )
        
        # Subscribe to service health events
        await self.event_bus.subscribe(
            topics=["pyairtable.service.*.health"],
            consumer_group="orchestration-health",
            handler=self._handle_service_health
        )
    
    async def _register_step_handlers(self) -> None:
        """Register handlers for different step types."""
        self.step_handlers.update({
            "http_call": self._execute_http_step,
            "event_publish": self._execute_event_step,
            "data_transform": self._execute_transform_step,
            "conditional": self._execute_conditional_step,
            "parallel": self._execute_parallel_step,
            "wait": self._execute_wait_step
        })
    
    async def start_orchestration_saga(
        self,
        saga_id: str,
        saga_type: str,
        steps: List[SagaStep],
        input_data: Dict[str, Any],
        correlation_id: str,
        orchestration_config: Optional[Dict[str, Any]] = None
    ) -> None:
        """Start a SAGA using orchestration pattern."""
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
            
            # Add orchestration-specific metadata
            saga.metadata = {
                "pattern": "orchestration",
                "controller": "central",
                "config": orchestration_config or {},
                "retry_count": 0,
                "max_retries": orchestration_config.get("max_retries", 3) if orchestration_config else 3
            }
            
            self.active_sagas[saga_id] = saga
            
            # Emit orchestration started event
            start_event = Event(
                type=EventType.SAGA_STARTED,
                aggregate_id=saga_id,
                aggregate_type="orchestration_saga",
                version=1,
                data={
                    "saga_type": saga_type,
                    "pattern": "orchestration",
                    "controller": "central",
                    "steps": [
                        {
                            "id": step.id,
                            "name": step.name,
                            "service": step.service,
                            "type": getattr(step, 'step_type', 'http_call')
                        }
                        for step in steps
                    ],
                    "input_data": input_data
                },
                correlation_id=correlation_id
            )
            
            await self.event_store.append_events(f"orchestration-saga-{saga_id}", [start_event])
            await self.event_bus.publish_event(start_event, "pyairtable.saga.orchestration_started")
            
            # Start execution
            await self._execute_orchestration_step(saga, 0)
            
            logger.info(f"Started orchestration SAGA {saga_id} with {len(steps)} steps")
            
        except Exception as e:
            logger.error(f"Failed to start orchestration SAGA {saga_id}: {e}")
            raise
    
    async def _execute_orchestration_step(
        self,
        saga: SagaInstance,
        step_index: int,
        retry_count: int = 0
    ) -> None:
        """Execute a specific step in orchestration pattern."""
        try:
            if step_index >= len(saga.steps):
                await self._complete_orchestration_saga(saga)
                return
            
            step = saga.steps[step_index]
            step.status = "running"
            step.started_at = datetime.now(timezone.utc)
            saga.current_step = step_index
            
            # Determine step type and execute accordingly
            step_type = getattr(step, 'step_type', 'http_call')
            handler = self.step_handlers.get(step_type, self._execute_http_step)
            
            logger.info(f"Executing orchestration step '{step.name}' (type: {step_type}) for SAGA {saga.id}")
            
            # Execute step with timeout and error handling
            try:
                result = await asyncio.wait_for(
                    handler(saga, step, step_index),
                    timeout=step.command.get('timeout', 30.0)
                )
                
                await self._handle_orchestration_step_success(saga, step, step_index, result)
                
            except asyncio.TimeoutError:
                await self._handle_orchestration_step_timeout(saga, step, step_index, retry_count)
            except Exception as step_error:
                await self._handle_orchestration_step_error(saga, step, step_index, str(step_error), retry_count)
                
        except Exception as e:
            logger.error(f"Fatal error executing orchestration step: {e}")
            await self._fail_orchestration_saga(saga, str(e))
    
    async def _execute_http_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int
    ) -> Dict[str, Any]:
        """Execute HTTP-based step."""
        service_url = self._get_service_url(step.service)
        command = self._substitute_variables(step.command, saga)
        
        method = command.get('method', 'POST')
        endpoint = command.get('endpoint', '/commands')
        headers = command.get('headers', {})
        payload = command.get('payload', {})
        
        # Add orchestration metadata
        headers['X-Orchestration-Saga-Id'] = saga.id
        headers['X-Orchestration-Step-Id'] = step.id
        headers['X-Orchestration-Correlation-Id'] = saga.correlation_id
        
        full_payload = {
            "saga_id": saga.id,
            "step_id": step.id,
            "command": payload,
            "correlation_id": saga.correlation_id,
            "orchestration_metadata": {
                "step_index": step_index,
                "total_steps": len(saga.steps),
                "input_data": saga.input_data,
                "previous_outputs": saga.output_data
            }
        }
        
        if method.upper() == 'GET':
            response = await self.http_client.get(
                f"{service_url}{endpoint}",
                headers=headers,
                params=payload
            )
        else:
            response = await self.http_client.request(
                method,
                f"{service_url}{endpoint}",
                headers=headers,
                json=full_payload
            )
        
        if response.status_code >= 400:
            raise Exception(f"HTTP {response.status_code}: {response.text}")
        
        return response.json() if response.content else {}
    
    async def _execute_event_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int
    ) -> Dict[str, Any]:
        """Execute event publishing step."""
        command = self._substitute_variables(step.command, saga)
        
        event_type = command.get('event_type')
        event_data = command.get('data', {})
        topic = command.get('topic')
        
        if not event_type or not topic:
            raise Exception("Event step requires 'event_type' and 'topic'")
        
        # Create and publish event
        orchestration_event = Event(
            type=EventType.COMMAND_ISSUED,
            aggregate_id=saga.id,
            aggregate_type="orchestration_step",
            version=step_index + 1,
            data={
                "orchestration_saga_id": saga.id,
                "step_id": step.id,
                "event_type": event_type,
                "event_data": event_data,
                "step_index": step_index
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_bus.publish_event(orchestration_event, topic)
        
        # Wait for response if synchronous
        if command.get('wait_for_response', False):
            # This would require implementing a response waiting mechanism
            # For now, return immediately
            pass
        
        return {"event_published": True, "topic": topic}
    
    async def _execute_transform_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int
    ) -> Dict[str, Any]:
        """Execute data transformation step."""
        command = self._substitute_variables(step.command, saga)
        
        transform_type = command.get('transform_type')
        input_data = command.get('input_data', saga.output_data)
        transformation = command.get('transformation', {})
        
        if transform_type == "field_mapping":
            result = {}
            for target_field, source_path in transformation.items():
                # Simple dot notation path resolution
                value = input_data
                for path_part in source_path.split('.'):
                    if isinstance(value, dict) and path_part in value:
                        value = value[path_part]
                    else:
                        value = None
                        break
                result[target_field] = value
                
        elif transform_type == "filter":
            condition = transformation.get('condition', {})
            # Simple filtering - in production you'd want a more robust system
            result = input_data
            
        elif transform_type == "aggregate":
            # Simple aggregation operations
            operation = transformation.get('operation')
            field = transformation.get('field')
            
            if operation == "count" and isinstance(input_data, list):
                result = {"count": len(input_data)}
            elif operation == "sum" and isinstance(input_data, list) and field:
                result = {"sum": sum(item.get(field, 0) for item in input_data if isinstance(item, dict))}
            else:
                result = input_data
                
        else:
            result = input_data
        
        return result
    
    async def _execute_conditional_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int
    ) -> Dict[str, Any]:
        """Execute conditional step with branching logic."""
        command = self._substitute_variables(step.command, saga)
        
        condition = command.get('condition', {})
        true_action = command.get('true_action', {})
        false_action = command.get('false_action', {})
        
        # Evaluate condition (simplified)
        condition_result = self._evaluate_condition(condition, saga)
        
        action = true_action if condition_result else false_action
        
        if action.get('skip_to_step'):
            # Modify saga to skip to specific step
            target_step = action['skip_to_step']
            for i, s in enumerate(saga.steps):
                if s.name == target_step or s.id == target_step:
                    saga.current_step = i - 1  # Will be incremented after this step
                    break
        
        return {
            "condition_result": condition_result,
            "action_taken": "true_action" if condition_result else "false_action",
            "details": action
        }
    
    def _evaluate_condition(self, condition: Dict[str, Any], saga: SagaInstance) -> bool:
        """Evaluate a condition against saga data."""
        field = condition.get('field')
        operator = condition.get('operator', 'equals')
        value = condition.get('value')
        
        # Get field value from saga data
        field_value = None
        if field:
            if field.startswith('input.'):
                field_value = saga.input_data.get(field[6:])
            elif field.startswith('output.'):
                field_value = saga.output_data.get(field[7:])
        
        # Evaluate based on operator
        if operator == 'equals':
            return field_value == value
        elif operator == 'not_equals':
            return field_value != value
        elif operator == 'greater_than':
            return field_value > value if field_value is not None else False
        elif operator == 'less_than':
            return field_value < value if field_value is not None else False
        elif operator == 'exists':
            return field_value is not None
        elif operator == 'not_exists':
            return field_value is None
        
        return False
    
    async def _execute_parallel_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int
    ) -> Dict[str, Any]:
        """Execute parallel sub-steps."""
        command = step.command
        parallel_steps = command.get('parallel_steps', [])
        
        if not parallel_steps:
            return {}
        
        # Execute all parallel steps concurrently
        tasks = []
        for i, parallel_step in enumerate(parallel_steps):
            # Create temporary step for parallel execution
            temp_step = SagaStep(
                id=f"{step.id}_parallel_{i}",
                name=parallel_step.get('name', f'Parallel Step {i+1}'),
                service=parallel_step.get('service'),
                command=parallel_step.get('command', {}),
                step_type=parallel_step.get('type', 'http_call')
            )
            
            handler = self.step_handlers.get(temp_step.step_type, self._execute_http_step)
            task = asyncio.create_task(handler(saga, temp_step, step_index))
            tasks.append((i, task))
        
        # Wait for all parallel steps to complete
        results = {}
        errors = {}
        
        for i, task in tasks:
            try:
                result = await task
                results[f"parallel_step_{i}"] = result
            except Exception as e:
                errors[f"parallel_step_{i}"] = str(e)
        
        if errors:
            raise Exception(f"Parallel step failures: {errors}")
        
        return {
            "parallel_results": results,
            "completed_count": len(results)
        }
    
    async def _execute_wait_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int
    ) -> Dict[str, Any]:
        """Execute wait/delay step."""
        command = step.command
        wait_seconds = command.get('duration_seconds', 1.0)
        wait_condition = command.get('wait_condition')
        
        if wait_condition:
            # Wait for condition to be met (with timeout)
            max_wait = command.get('max_wait_seconds', 60.0)
            check_interval = command.get('check_interval_seconds', 1.0)
            
            waited_time = 0.0
            while waited_time < max_wait:
                if self._evaluate_condition(wait_condition, saga):
                    break
                await asyncio.sleep(check_interval)
                waited_time += check_interval
            else:
                raise Exception(f"Wait condition not met within {max_wait} seconds")
        else:
            # Simple delay
            await asyncio.sleep(wait_seconds)
        
        return {"waited_seconds": wait_seconds if not wait_condition else waited_time}
    
    def _get_service_url(self, service: str) -> str:
        """Get the URL for a service."""
        return self.service_registry.get(service, f"http://{service}:8000")
    
    def _substitute_variables(self, command: Dict[str, Any], saga: SagaInstance) -> Dict[str, Any]:
        """Substitute variables in command from saga data."""
        import json
        
        command_str = json.dumps(command)
        
        # Substitute from saga output data
        for key, value in saga.output_data.items():
            command_str = command_str.replace(f"{{{{output.{key}}}}}", str(value))
        
        # Substitute from input data
        for key, value in saga.input_data.items():
            command_str = command_str.replace(f"{{{{input.{key}}}}}", str(value))
        
        return json.loads(command_str)
    
    async def _handle_orchestration_step_success(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int,
        result: Dict[str, Any]
    ) -> None:
        """Handle successful orchestration step completion."""
        step.status = "completed"
        step.completed_at = datetime.now(timezone.utc)
        step.result = result
        
        # Update saga output data
        if result:
            saga.output_data.update(result)
        
        # Emit step completed event
        step_event = Event(
            type=EventType.SAGA_STEP_COMPLETED,
            aggregate_id=saga.id,
            aggregate_type="orchestration_step",
            version=step_index + 1,
            data={
                "step_id": step.id,
                "step_name": step.name,
                "step_index": step_index,
                "result": result,
                "pattern": "orchestration"
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"orchestration-saga-{saga.id}", [step_event])
        await self.event_bus.publish_event(step_event)
        
        logger.info(f"Orchestration step '{step.name}' completed for SAGA {saga.id}")
        
        # Continue to next step
        await self._execute_orchestration_step(saga, step_index + 1)
    
    async def _handle_orchestration_step_timeout(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int,
        retry_count: int
    ) -> None:
        """Handle orchestration step timeout."""
        max_retries = saga.metadata.get("max_retries", 3)
        
        if retry_count < max_retries:
            logger.warning(f"Orchestration step '{step.name}' timed out, retrying ({retry_count + 1}/{max_retries})")
            await asyncio.sleep(2 ** retry_count)  # Exponential backoff
            await self._execute_orchestration_step(saga, step_index, retry_count + 1)
        else:
            error_msg = f"Step '{step.name}' timed out after {max_retries} retries"
            await self._handle_orchestration_step_error(saga, step, step_index, error_msg, retry_count)
    
    async def _handle_orchestration_step_error(
        self,
        saga: SagaInstance,
        step: SagaStep,
        step_index: int,
        error: str,
        retry_count: int
    ) -> None:
        """Handle orchestration step error."""
        max_retries = saga.metadata.get("max_retries", 3)
        
        if retry_count < max_retries and step.command.get('retryable', True):
            logger.warning(f"Orchestration step '{step.name}' failed, retrying ({retry_count + 1}/{max_retries}): {error}")
            await asyncio.sleep(2 ** retry_count)  # Exponential backoff
            await self._execute_orchestration_step(saga, step_index, retry_count + 1)
        else:
            # Step failed permanently
            step.status = "failed"
            step.completed_at = datetime.now(timezone.utc)
            step.error_message = error
            
            logger.error(f"Orchestration step '{step.name}' failed permanently for SAGA {saga.id}: {error}")
            
            # Start compensation
            await self._start_orchestration_compensation(saga)
    
    async def _complete_orchestration_saga(self, saga: SagaInstance) -> None:
        """Complete orchestration SAGA."""
        saga.status = SagaStatus.COMPLETED
        saga.completed_at = datetime.now(timezone.utc)
        
        # Emit completion event
        completion_event = Event(
            type=EventType.SAGA_COMPLETED,
            aggregate_id=saga.id,
            aggregate_type="orchestration_saga",
            version=len(saga.steps) + 1,
            data={
                "pattern": "orchestration",
                "output_data": saga.output_data,
                "completed_steps": len(saga.steps),
                "total_duration_seconds": (
                    saga.completed_at - saga.started_at
                ).total_seconds() if saga.started_at else None
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"orchestration-saga-{saga.id}", [completion_event])
        await self.event_bus.publish_event(completion_event, "pyairtable.saga.orchestration_completed")
        
        # Cleanup
        del self.active_sagas[saga.id]
        
        logger.info(f"Orchestration SAGA {saga.id} completed successfully")
    
    async def _start_orchestration_compensation(self, saga: SagaInstance) -> None:
        """Start compensation process for orchestration SAGA."""
        saga.status = SagaStatus.COMPENSATING
        
        # Get completed steps in reverse order
        completed_steps = [
            (i, step) for i, step in enumerate(reversed(saga.steps[:saga.current_step + 1]))
            if step.status == "completed" and step.compensation_command
        ]
        
        if not completed_steps:
            await self._complete_orchestration_compensation(saga)
            return
        
        logger.info(f"Starting orchestration compensation for SAGA {saga.id} with {len(completed_steps)} steps")
        
        # Execute compensation steps sequentially
        for i, (original_index, step) in enumerate(completed_steps):
            try:
                await self._execute_orchestration_compensation_step(saga, step, i)
            except Exception as e:
                logger.error(f"Orchestration compensation failed for step {step.id}: {e}")
                # Continue with other compensations
        
        await self._complete_orchestration_compensation(saga)
    
    async def _execute_orchestration_compensation_step(
        self,
        saga: SagaInstance,
        step: SagaStep,
        compensation_index: int
    ) -> None:
        """Execute compensation for a specific step."""
        service_url = self._get_service_url(step.service)
        compensation_command = self._substitute_variables(step.compensation_command, saga)
        
        try:
            response = await self.http_client.post(
                f"{service_url}/compensations",
                json={
                    "saga_id": saga.id,
                    "step_id": step.id,
                    "command": compensation_command,
                    "correlation_id": saga.correlation_id,
                    "orchestration_metadata": {
                        "compensation_index": compensation_index,
                        "pattern": "orchestration"
                    }
                },
                headers={"X-Orchestration-Compensation": "true"}
            )
            
            if response.status_code >= 400:
                logger.error(f"Orchestration compensation failed for step {step.id}: {response.text}")
            else:
                logger.info(f"Orchestration compensation completed for step '{step.name}'")
                
        except Exception as e:
            logger.error(f"Failed to execute orchestration compensation for step {step.id}: {e}")
    
    async def _complete_orchestration_compensation(self, saga: SagaInstance) -> None:
        """Complete orchestration compensation process."""
        saga.status = SagaStatus.COMPENSATED
        saga.completed_at = datetime.now(timezone.utc)
        
        # Emit compensated event
        compensated_event = Event(
            type=EventType.SAGA_COMPENSATED,
            aggregate_id=saga.id,
            aggregate_type="orchestration_saga",
            version=len(saga.steps) + 10,
            data={
                "pattern": "orchestration",
                "compensated_at": saga.completed_at.isoformat(),
                "total_duration_seconds": (
                    saga.completed_at - saga.started_at
                ).total_seconds() if saga.started_at else None
            },
            correlation_id=saga.correlation_id
        )
        
        await self.event_store.append_events(f"orchestration-saga-{saga.id}", [compensated_event])
        await self.event_bus.publish_event(compensated_event, "pyairtable.saga.orchestration_compensated")
        
        # Cleanup
        del self.active_sagas[saga.id]
        
        logger.info(f"Orchestration SAGA {saga.id} compensation completed")
    
    async def _fail_orchestration_saga(self, saga: SagaInstance, error: str) -> None:
        """Handle orchestration SAGA failure."""
        saga.status = SagaStatus.COMPENSATING
        saga.error_message = error
        
        await self._start_orchestration_compensation(saga)
    
    async def _handle_orchestration_response(self, event: Event) -> None:
        """Handle responses from orchestration operations."""
        try:
            saga_id = event.data.get("saga_id")
            if saga_id not in self.active_sagas:
                return
            
            # Process orchestration-specific responses
            response_type = event.data.get("response_type")
            if response_type == "step_completed":
                # Handle asynchronous step completion
                pass
            elif response_type == "compensation_completed":
                # Handle asynchronous compensation completion
                pass
                
        except Exception as e:
            logger.error(f"Error handling orchestration response: {e}")
    
    async def _handle_service_health(self, event: Event) -> None:
        """Handle service health events for orchestration decisions."""
        try:
            service_name = event.data.get("service")
            health_status = event.data.get("status")
            
            if health_status == "unhealthy":
                # Find sagas that might be affected
                affected_sagas = [
                    saga for saga in self.active_sagas.values()
                    if saga.status == SagaStatus.RUNNING and
                    any(step.service == service_name and step.status == "running" for step in saga.steps)
                ]
                
                for saga in affected_sagas:
                    logger.warning(f"Service {service_name} is unhealthy, may affect SAGA {saga.id}")
                    # You could implement circuit breaker logic here
                    
        except Exception as e:
            logger.error(f"Error handling service health event: {e}")
    
    def get_orchestration_status(self, saga_id: str) -> Optional[Dict[str, Any]]:
        """Get status of orchestration SAGA."""
        if saga_id not in self.active_sagas:
            return None
        
        saga = self.active_sagas[saga_id]
        return {
            "saga_id": saga_id,
            "pattern": "orchestration",
            "status": saga.status.value,
            "current_step": saga.current_step,
            "total_steps": len(saga.steps),
            "started_at": saga.started_at.isoformat() if saga.started_at else None,
            "completed_at": saga.completed_at.isoformat() if saga.completed_at else None,
            "error_message": saga.error_message,
            "metadata": saga.metadata,
            "steps": [
                {
                    "id": step.id,
                    "name": step.name,
                    "service": step.service,
                    "status": step.status,
                    "started_at": step.started_at.isoformat() if step.started_at else None,
                    "completed_at": step.completed_at.isoformat() if step.completed_at else None,
                    "duration_ms": (
                        int((step.completed_at - step.started_at).total_seconds() * 1000)
                        if step.started_at and step.completed_at else None
                    ),
                    "error_message": step.error_message,
                    "result": step.result
                }
                for step in saga.steps
            ]
        }
    
    async def list_orchestration_sagas(self) -> List[Dict[str, Any]]:
        """List all active orchestration SAGAs."""
        return [
            self.get_orchestration_status(saga_id)
            for saga_id in self.active_sagas.keys()
        ]