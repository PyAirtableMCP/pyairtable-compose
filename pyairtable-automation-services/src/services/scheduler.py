import asyncio
import logging
from datetime import datetime, timedelta
from typing import List
from sqlalchemy.orm import Session

from ..database import SessionLocal
from ..models.workflows import Workflow, WorkflowStatus
from .workflow_service import WorkflowService
from ..config import settings

logger = logging.getLogger(__name__)

class WorkflowScheduler:
    def __init__(self):
        self.running = False
        self.task = None
        self.check_interval = settings.scheduler_check_interval
    
    async def start(self):
        """Start the workflow scheduler"""
        if self.running:
            return
        
        self.running = True
        self.task = asyncio.create_task(self._scheduler_loop())
        logger.info("Workflow scheduler started")
    
    async def stop(self):
        """Stop the workflow scheduler"""
        if not self.running:
            return
        
        self.running = False
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
        
        logger.info("Workflow scheduler stopped")
    
    async def _scheduler_loop(self):
        """Main scheduler loop"""
        while self.running:
            try:
                await self._check_scheduled_workflows()
                await asyncio.sleep(self.check_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Scheduler error: {str(e)}")
                await asyncio.sleep(self.check_interval)
    
    async def _check_scheduled_workflows(self):
        """Check for workflows that need to be executed"""
        try:
            db = SessionLocal()
            workflow_service = WorkflowService(db)
            
            # Get all scheduled workflows
            scheduled_workflows = workflow_service.get_scheduled_workflows()
            
            for workflow in scheduled_workflows:
                try:
                    if await self._should_execute_workflow(workflow):
                        logger.info(f"Triggering scheduled workflow: {workflow.id} - {workflow.name}")
                        
                        execution = workflow_service.create_execution(
                            workflow_id=workflow.id,
                            trigger_type="scheduled",
                            trigger_data={
                                "scheduled_time": datetime.utcnow().isoformat(),
                                "cron_schedule": workflow.cron_schedule
                            }
                        )
                        
                        # Execute workflow in background
                        asyncio.create_task(workflow_service.execute_workflow_async(execution.id))
                        
                except Exception as e:
                    logger.error(f"Failed to process scheduled workflow {workflow.id}: {str(e)}")
            
            db.close()
            
        except Exception as e:
            logger.error(f"Failed to check scheduled workflows: {str(e)}")
    
    async def _should_execute_workflow(self, workflow: Workflow) -> bool:
        """Check if a workflow should be executed now"""
        if not workflow.cron_schedule:
            return False
        
        try:
            from croniter import croniter
            
            # Get the next scheduled time from the last execution or creation
            base_time = workflow.last_execution_at or workflow.created_at
            
            # Create croniter instance
            cron = croniter(workflow.cron_schedule, base_time)
            next_run = cron.get_next(datetime)
            
            # Check if it's time to run (within the check interval)
            now = datetime.utcnow()
            time_diff = (next_run - now).total_seconds()
            
            # Execute if the next run time has passed or is within the check interval
            return time_diff <= self.check_interval
            
        except ImportError:
            logger.warning("croniter not installed, cannot schedule workflows")
            return False
        except Exception as e:
            logger.error(f"Error checking workflow schedule for {workflow.id}: {str(e)}")
            return False
    
    def get_status(self) -> dict:
        """Get scheduler status"""
        return {
            "running": self.running,
            "check_interval": self.check_interval,
            "task_status": "running" if self.task and not self.task.done() else "stopped"
        }