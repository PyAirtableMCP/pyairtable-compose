import json
import asyncio
from datetime import datetime
from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from ..models.workflows import Workflow, WorkflowStatus
from ..models.executions import WorkflowExecution, ExecutionStatus
from ..config import settings
from ..utils.redis_client import get_redis_client
import logging

logger = logging.getLogger(__name__)

class WorkflowService:
    def __init__(self, db: Session):
        self.db = db
    
    def create_workflow(
        self,
        name: str,
        description: Optional[str],
        workflow_config: Dict[str, Any],
        trigger_config: Optional[Dict[str, Any]] = None,
        cron_schedule: Optional[str] = None,
        is_scheduled: bool = False,
        trigger_on_file_upload: bool = False,
        trigger_file_extensions: Optional[str] = None,
        timeout_seconds: int = 300
    ) -> Workflow:
        """Create a new workflow"""
        # Validate workflow config
        if not workflow_config:
            raise ValueError("Workflow configuration is required")
        
        # Validate cron schedule if provided
        if cron_schedule and is_scheduled:
            try:
                from croniter import croniter
                if not croniter.is_valid(cron_schedule):
                    raise ValueError("Invalid cron schedule format")
            except ImportError:
                logger.warning("croniter not installed, skipping cron validation")
        
        workflow = Workflow(
            name=name,
            description=description,
            workflow_config=json.dumps(workflow_config),
            trigger_config=json.dumps(trigger_config) if trigger_config else None,
            cron_schedule=cron_schedule,
            is_scheduled=is_scheduled,
            trigger_on_file_upload=trigger_on_file_upload,
            trigger_file_extensions=trigger_file_extensions,
            timeout_seconds=timeout_seconds,
            status=WorkflowStatus.ACTIVE
        )
        
        self.db.add(workflow)
        self.db.commit()
        self.db.refresh(workflow)
        
        logger.info(f"Workflow created: {workflow.id} - {name}")
        return workflow
    
    def get_workflow(self, workflow_id: int) -> Optional[Workflow]:
        """Get workflow by ID"""
        return self.db.query(Workflow).filter(
            and_(Workflow.id == workflow_id, Workflow.status != WorkflowStatus.DELETED)
        ).first()
    
    def list_workflows(self, status: Optional[str] = None, limit: int = 100, offset: int = 0) -> List[Workflow]:
        """List workflows with optional filtering"""
        query = self.db.query(Workflow).filter(Workflow.status != WorkflowStatus.DELETED)
        
        if status:
            try:
                status_enum = WorkflowStatus(status)
                query = query.filter(Workflow.status == status_enum)
            except ValueError:
                pass  # Invalid status, ignore filter
        
        return query.offset(offset).limit(limit).all()
    
    def update_workflow(self, workflow_id: int, updates: Dict[str, Any]) -> Optional[Workflow]:
        """Update workflow"""
        workflow = self.get_workflow(workflow_id)
        if not workflow:
            return None
        
        # Update allowed fields
        allowed_fields = [
            'name', 'description', 'cron_schedule', 'is_scheduled',
            'trigger_on_file_upload', 'trigger_file_extensions',
            'timeout_seconds', 'is_enabled'
        ]
        
        for field, value in updates.items():
            if field in allowed_fields and value is not None:
                setattr(workflow, field, value)
            elif field == 'workflow_config' and value is not None:
                workflow.workflow_config = json.dumps(value)
            elif field == 'trigger_config' and value is not None:
                workflow.trigger_config = json.dumps(value)
        
        # Validate cron schedule if updated
        if 'cron_schedule' in updates and updates['cron_schedule']:
            try:
                from croniter import croniter
                if not croniter.is_valid(updates['cron_schedule']):
                    raise ValueError("Invalid cron schedule format")
            except ImportError:
                logger.warning("croniter not installed, skipping cron validation")
        
        self.db.commit()
        self.db.refresh(workflow)
        
        logger.info(f"Workflow updated: {workflow_id}")
        return workflow
    
    def delete_workflow(self, workflow_id: int) -> bool:
        """Delete workflow (soft delete)"""
        workflow = self.get_workflow(workflow_id)
        if not workflow:
            return False
        
        workflow.status = WorkflowStatus.DELETED
        workflow.deleted_at = datetime.utcnow()
        self.db.commit()
        
        logger.info(f"Workflow deleted: {workflow_id}")
        return True
    
    def get_file_trigger_workflows(self, file_extension: str) -> List[Workflow]:
        """Get workflows that should trigger on file upload"""
        return self.db.query(Workflow).filter(
            and_(
                Workflow.status == WorkflowStatus.ACTIVE,
                Workflow.is_enabled == True,
                Workflow.trigger_on_file_upload == True,
                or_(
                    Workflow.trigger_file_extensions.is_(None),
                    Workflow.trigger_file_extensions.contains(file_extension.lower())
                )
            )
        ).all()
    
    def get_scheduled_workflows(self) -> List[Workflow]:
        """Get workflows that should be scheduled"""
        return self.db.query(Workflow).filter(
            and_(
                Workflow.status == WorkflowStatus.ACTIVE,
                Workflow.is_enabled == True,
                Workflow.is_scheduled == True,
                Workflow.cron_schedule.isnot(None)
            )
        ).all()
    
    def create_execution(
        self,
        workflow_id: int,
        trigger_type: str,
        trigger_data: Optional[Dict[str, Any]] = None
    ) -> WorkflowExecution:
        """Create a new workflow execution"""
        execution = WorkflowExecution(
            workflow_id=workflow_id,
            trigger_type=trigger_type,
            trigger_data=json.dumps(trigger_data) if trigger_data else None,
            status=ExecutionStatus.PENDING
        )
        
        self.db.add(execution)
        self.db.commit()
        self.db.refresh(execution)
        
        logger.info(f"Workflow execution created: {execution.id} for workflow {workflow_id}")
        return execution
    
    def get_workflow_executions(
        self,
        workflow_id: int,
        status: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> List[WorkflowExecution]:
        """Get executions for a specific workflow"""
        query = self.db.query(WorkflowExecution).filter(WorkflowExecution.workflow_id == workflow_id)
        
        if status:
            try:
                status_enum = ExecutionStatus(status)
                query = query.filter(WorkflowExecution.status == status_enum)
            except ValueError:
                pass  # Invalid status, ignore filter
        
        return query.order_by(WorkflowExecution.created_at.desc()).offset(offset).limit(limit).all()
    
    def list_executions(
        self,
        workflow_id: Optional[int] = None,
        status: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> List[WorkflowExecution]:
        """List workflow executions with optional filtering"""
        query = self.db.query(WorkflowExecution)
        
        if workflow_id:
            query = query.filter(WorkflowExecution.workflow_id == workflow_id)
        
        if status:
            try:
                status_enum = ExecutionStatus(status)
                query = query.filter(WorkflowExecution.status == status_enum)
            except ValueError:
                pass  # Invalid status, ignore filter
        
        return query.order_by(WorkflowExecution.created_at.desc()).offset(offset).limit(limit).all()
    
    async def execute_workflow_async(self, execution_id: int):
        """Execute workflow asynchronously"""
        try:
            execution = self.db.query(WorkflowExecution).filter(WorkflowExecution.id == execution_id).first()
            if not execution:
                logger.error(f"Execution not found: {execution_id}")
                return
            
            workflow = self.get_workflow(execution.workflow_id)
            if not workflow or not workflow.is_executable:
                execution.status = ExecutionStatus.CANCELLED
                execution.error_message = "Workflow not executable"
                self.db.commit()
                return
            
            # Update execution status
            execution.status = ExecutionStatus.RUNNING
            execution.started_at = datetime.utcnow()
            self.db.commit()
            
            logger.info(f"Executing workflow: {workflow.id} (execution: {execution_id})")
            
            # Parse workflow configuration
            workflow_config = json.loads(workflow.workflow_config)
            
            # Execute workflow steps
            result = await self._execute_workflow_steps(workflow_config, execution)
            
            # Update execution with results
            execution.status = ExecutionStatus.COMPLETED
            execution.result_data = json.dumps(result) if result else None
            execution.completed_at = datetime.utcnow()
            execution.execution_time_ms = execution.calculate_duration()
            
            # Update workflow statistics
            workflow.total_executions += 1
            workflow.successful_executions += 1
            workflow.last_execution_at = execution.completed_at
            
            self.db.commit()
            logger.info(f"Workflow execution completed: {execution_id}")
            
        except asyncio.TimeoutError:
            logger.error(f"Workflow execution timeout: {execution_id}")
            execution.status = ExecutionStatus.TIMEOUT
            execution.error_message = "Execution timed out"
            execution.completed_at = datetime.utcnow()
            workflow.total_executions += 1
            workflow.failed_executions += 1
            self.db.commit()
            
        except Exception as e:
            logger.error(f"Workflow execution failed: {execution_id} - {str(e)}")
            execution.status = ExecutionStatus.FAILED
            execution.error_message = str(e)
            execution.completed_at = datetime.utcnow()
            execution.retry_count += 1
            
            workflow.total_executions += 1
            workflow.failed_executions += 1
            
            self.db.commit()
    
    async def _execute_workflow_steps(self, workflow_config: Dict[str, Any], execution: WorkflowExecution) -> Dict[str, Any]:
        """Execute individual workflow steps"""
        steps = workflow_config.get('steps', [])
        results = {}
        
        for i, step in enumerate(steps):
            step_name = step.get('name', f'step_{i}')
            step_type = step.get('type')
            step_config = step.get('config', {})
            
            logger.info(f"Executing step: {step_name} ({step_type})")
            
            try:
                step_result = await self._execute_step(step_type, step_config, execution)
                results[step_name] = step_result
                
                # Update execution log
                if execution.log_output:
                    logs = json.loads(execution.log_output)
                else:
                    logs = []
                
                logs.append({
                    'timestamp': datetime.utcnow().isoformat(),
                    'step': step_name,
                    'status': 'completed',
                    'result': step_result
                })
                
                execution.log_output = json.dumps(logs)
                self.db.commit()
                
            except Exception as e:
                logger.error(f"Step {step_name} failed: {str(e)}")
                raise e
        
        return results
    
    async def _execute_step(self, step_type: str, step_config: Dict[str, Any], execution: WorkflowExecution) -> Any:
        """Execute a single workflow step"""
        if step_type == 'http_request':
            return await self._execute_http_request(step_config)
        elif step_type == 'file_process':
            return await self._execute_file_process(step_config, execution)
        elif step_type == 'delay':
            delay_seconds = step_config.get('seconds', 1)
            await asyncio.sleep(delay_seconds)
            return {'delayed': delay_seconds}
        elif step_type == 'log':
            message = step_config.get('message', 'Workflow step executed')
            logger.info(f"Workflow log: {message}")
            return {'message': message}
        else:
            raise ValueError(f"Unknown step type: {step_type}")
    
    async def _execute_http_request(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Execute HTTP request step"""
        import aiohttp
        
        url = config.get('url')
        method = config.get('method', 'GET').upper()
        headers = config.get('headers', {})
        data = config.get('data')
        
        if not url:
            raise ValueError("URL is required for HTTP request step")
        
        async with aiohttp.ClientSession() as session:
            async with session.request(method, url, headers=headers, json=data) as response:
                result = {
                    'status_code': response.status,
                    'headers': dict(response.headers),
                    'body': await response.text()
                }
                
                if response.content_type == 'application/json':
                    try:
                        result['json'] = await response.json()
                    except:
                        pass
                
                return result
    
    async def _execute_file_process(self, config: Dict[str, Any], execution: WorkflowExecution) -> Dict[str, Any]:
        """Execute file processing step"""
        # Get file ID from trigger data or config
        trigger_data = json.loads(execution.trigger_data) if execution.trigger_data else {}
        file_id = config.get('file_id') or trigger_data.get('file_id')
        
        if not file_id:
            raise ValueError("File ID is required for file processing step")
        
        # Here you would integrate with file processing logic
        # For now, return a placeholder result
        return {
            'file_id': file_id,
            'action': config.get('action', 'process'),
            'status': 'completed'
        }