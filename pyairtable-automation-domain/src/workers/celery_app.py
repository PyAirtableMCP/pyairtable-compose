"""Celery application configuration and task management."""

import sys
from typing import Any, Dict, Optional

from celery import Celery
from celery.signals import setup_logging, worker_ready, worker_shutdown
from kombu import Queue

from ..core.config import get_settings
from ..core.logging import configure_logging, get_logger

# Global Celery instance
celery_app: Optional[Celery] = None
logger = get_logger(__name__)


def create_celery_app() -> Celery:
    """Create and configure Celery application."""
    settings = get_settings()
    
    app = Celery("automation-domain")
    
    # Configure Celery
    app.conf.update(
        broker_url=settings.celery.broker_url,
        result_backend=settings.celery.result_backend,
        task_serializer=settings.celery.task_serializer,
        accept_content=settings.celery.accept_content,
        result_serializer=settings.celery.result_serializer,
        timezone=settings.celery.timezone,
        enable_utc=settings.celery.enable_utc,
        task_track_started=settings.celery.task_track_started,
        task_time_limit=settings.celery.task_time_limit,
        task_soft_time_limit=settings.celery.task_soft_time_limit,
        worker_prefetch_multiplier=settings.celery.worker_prefetch_multiplier,
        
        # Queue configuration
        task_routes={
            'automation.workflows.*': {'queue': 'workflow'},
            'automation.notifications.*': {'queue': 'notification'},
            'automation.webhooks.*': {'queue': 'webhook'},
            'automation.automation.*': {'queue': 'automation'},
        },
        
        # Queue definitions with priorities
        task_queues=[
            Queue('critical', routing_key='critical', priority=10),
            Queue('workflow', routing_key='workflow', priority=5),
            Queue('notification', routing_key='notification', priority=3),
            Queue('webhook', routing_key='webhook', priority=3),
            Queue('automation', routing_key='automation', priority=1),
            Queue('default', routing_key='default', priority=1),
        ],
        
        # Task execution settings
        task_acks_late=True,
        worker_log_format='[%(asctime)s: %(levelname)s/%(processName)s] %(message)s',
        worker_task_log_format='[%(asctime)s: %(levelname)s/%(processName)s][%(task_name)s(%(task_id)s)] %(message)s',
        
        # Result settings
        result_expires=3600,  # 1 hour
        result_persistent=True,
        
        # Beat scheduler settings
        beat_schedule={},
        beat_scheduler='celery.beat:PersistentScheduler',
    )
    
    # Import tasks to register them
    app.autodiscover_tasks([
        'src.workers.workflow_tasks',
        'src.workers.notification_tasks', 
        'src.workers.webhook_tasks',
        'src.workers.automation_tasks',
    ])
    
    return app


def initialize_celery() -> None:
    """Initialize the global Celery app."""
    global celery_app
    if celery_app is None:
        celery_app = create_celery_app()
        logger.info("Celery application initialized")


def cleanup_celery() -> None:
    """Cleanup Celery resources."""
    global celery_app
    if celery_app is not None:
        try:
            celery_app.control.shutdown()
            logger.info("Celery application shut down")
        except Exception as e:
            logger.error("Error shutting down Celery", error=str(e))
        finally:
            celery_app = None


def get_celery_app() -> Celery:
    """Get the Celery application instance."""
    global celery_app
    if celery_app is None:
        initialize_celery()
    return celery_app


# Celery signals
@setup_logging.connect
def setup_celery_logging(**kwargs):
    """Configure logging for Celery workers."""
    configure_logging()


@worker_ready.connect
def worker_ready_handler(sender=None, **kwargs):
    """Handle worker ready signal."""
    logger.info("Celery worker ready", worker=sender)


@worker_shutdown.connect
def worker_shutdown_handler(sender=None, **kwargs):
    """Handle worker shutdown signal."""
    logger.info("Celery worker shutting down", worker=sender)


def start_worker():
    """Start Celery worker."""
    app = get_celery_app()
    app.start([
        'worker',
        '--loglevel=info',
        '--queues=critical,workflow,notification,webhook,automation,default',
        '--concurrency=4',
        '--pool=prefork',
    ])


# Base task class with common functionality
class BaseTask(celery_app.Task if celery_app else object):
    """Base task class with common functionality."""
    
    def on_failure(self, exc, task_id, args, kwargs, einfo):
        """Handle task failure."""
        logger.error(
            "Task failed",
            task_id=task_id,
            task_name=self.name,
            error=str(exc),
            args=args,
            kwargs=kwargs
        )
    
    def on_success(self, retval, task_id, args, kwargs):
        """Handle task success."""
        logger.info(
            "Task completed successfully",
            task_id=task_id,
            task_name=self.name,
            result=retval
        )
    
    def on_retry(self, exc, task_id, args, kwargs, einfo):
        """Handle task retry."""
        logger.warning(
            "Task retrying",
            task_id=task_id,
            task_name=self.name,
            error=str(exc),
            retry_count=self.request.retries
        )


# Create the celery app instance if running as module
if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "worker":
        start_worker()
    else:
        # Initialize for imports
        initialize_celery()