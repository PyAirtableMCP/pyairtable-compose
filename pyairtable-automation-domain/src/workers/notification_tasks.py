"""Notification delivery tasks."""

import asyncio
import smtplib
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any, Dict, List, Optional

import aiosmtplib
import httpx
from celery import Task
from jinja2 import Template

from .celery_app import get_celery_app, BaseTask
from ..core.config import get_settings
from ..core.logging import get_logger

# Get Celery app instance
celery_app = get_celery_app()
logger = get_logger(__name__)


@celery_app.task(base=BaseTask, bind=True, name="automation.notifications.send_email")
def send_email_task(
    self: Task,
    to: List[str],
    subject: str,
    body: str,
    html_body: Optional[str] = None,
    cc: Optional[List[str]] = None,
    bcc: Optional[List[str]] = None,
    template_id: Optional[str] = None,
    template_data: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Send email notification."""
    logger.info(
        "Sending email notification",
        to=to,
        subject=subject,
        template_id=template_id
    )
    
    try:
        settings = get_settings()
        
        # Render template if provided
        if template_id and template_data:
            rendered_content = _render_email_template(template_id, template_data)
            if rendered_content:
                subject = rendered_content.get("subject", subject)
                body = rendered_content.get("body", body)
                html_body = rendered_content.get("html_body", html_body)
        
        # Send email
        result = asyncio.run(_send_email_async(
            to=to,
            subject=subject,
            body=body,
            html_body=html_body,
            cc=cc,
            bcc=bcc,
            settings=settings
        ))
        
        logger.info(
            "Email notification sent successfully",
            to=to,
            subject=subject,
            message_id=result.get("message_id")
        )
        
        return {
            "status": "sent",
            "to": to,
            "subject": subject,
            "sent_at": datetime.utcnow().isoformat(),
            "message_id": result.get("message_id"),
            "task_id": self.request.id
        }
        
    except Exception as exc:
        logger.error(
            "Email notification failed",
            to=to,
            subject=subject,
            error=str(exc)
        )
        
        # Retry logic
        if self.request.retries < 3:
            logger.info(
                "Retrying email notification",
                to=to,
                retry_count=self.request.retries + 1
            )
            raise self.retry(countdown=60 * (2 ** self.request.retries), exc=exc)
        
        # Final failure
        return {
            "status": "failed",
            "to": to,
            "subject": subject,
            "error": str(exc),
            "failed_at": datetime.utcnow().isoformat(),
            "task_id": self.request.id
        }


@celery_app.task(base=BaseTask, bind=True, name="automation.notifications.send_sms")
def send_sms_task(
    self: Task,
    to: List[str],
    message: str,
    template_id: Optional[str] = None,
    template_data: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Send SMS notification."""
    logger.info(
        "Sending SMS notification",
        to=to,
        template_id=template_id
    )
    
    try:
        # Render template if provided
        if template_id and template_data:
            rendered_message = _render_sms_template(template_id, template_data)
            if rendered_message:
                message = rendered_message
        
        # TODO: Implement actual SMS sending via provider (Twilio, AWS SNS, etc.)
        result = _send_sms_mock(to, message)
        
        logger.info(
            "SMS notification sent successfully",
            to=to,
            message_id=result.get("message_id")
        )
        
        return {
            "status": "sent",
            "to": to,
            "sent_at": datetime.utcnow().isoformat(),
            "message_id": result.get("message_id"),
            "task_id": self.request.id
        }
        
    except Exception as exc:
        logger.error(
            "SMS notification failed",
            to=to,
            error=str(exc)
        )
        
        # Retry logic
        if self.request.retries < 3:
            logger.info(
                "Retrying SMS notification",
                to=to,
                retry_count=self.request.retries + 1
            )
            raise self.retry(countdown=60 * (2 ** self.request.retries), exc=exc)
        
        # Final failure
        return {
            "status": "failed",
            "to": to,
            "error": str(exc),
            "failed_at": datetime.utcnow().isoformat(),
            "task_id": self.request.id
        }


@celery_app.task(base=BaseTask, bind=True, name="automation.notifications.send")
def send_notification_task(
    self: Task,
    type: str,
    config: Dict[str, Any]
) -> Dict[str, Any]:
    """Send notification of any type."""
    logger.info("Sending notification", type=type)
    
    try:
        if type == "email":
            return send_email_task(
                to=config["to"],
                subject=config["subject"],
                body=config["body"],
                html_body=config.get("html_body"),
                cc=config.get("cc"),
                bcc=config.get("bcc"),
                template_id=config.get("template_id"),
                template_data=config.get("template_data")
            )
        elif type == "sms":
            return send_sms_task(
                to=config["to"],
                message=config["message"],
                template_id=config.get("template_id"),
                template_data=config.get("template_data")
            )
        else:
            raise ValueError(f"Unknown notification type: {type}")
            
    except Exception as exc:
        logger.error(
            "Notification sending failed",
            type=type,
            error=str(exc)
        )
        raise


async def _send_email_async(
    to: List[str],
    subject: str,
    body: str,
    html_body: Optional[str] = None,
    cc: Optional[List[str]] = None,
    bcc: Optional[List[str]] = None,
    settings=None
) -> Dict[str, Any]:
    """Send email asynchronously."""
    if not settings:
        settings = get_settings()
    
    # Create message
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{settings.notification.from_name} <{settings.notification.from_email}>"
    msg["To"] = ", ".join(to)
    
    if cc:
        msg["Cc"] = ", ".join(cc)
    
    # Add body parts
    msg.attach(MIMEText(body, "plain"))
    if html_body:
        msg.attach(MIMEText(html_body, "html"))
    
    # Send email
    smtp_client = aiosmtplib.SMTP(
        hostname=settings.notification.smtp_host,
        port=settings.notification.smtp_port,
        use_tls=settings.notification.smtp_use_tls,
    )
    
    await smtp_client.connect()
    
    if settings.notification.smtp_username and settings.notification.smtp_password:
        await smtp_client.login(
            settings.notification.smtp_username,
            settings.notification.smtp_password
        )
    
    # Build recipient list
    recipients = to.copy()
    if cc:
        recipients.extend(cc)
    if bcc:
        recipients.extend(bcc)
    
    result = await smtp_client.send_message(msg, recipients=recipients)
    await smtp_client.quit()
    
    return {"message_id": msg["Message-ID"], "result": result}


def _send_sms_mock(to: List[str], message: str) -> Dict[str, Any]:
    """Mock SMS sending (replace with actual provider)."""
    # TODO: Replace with actual SMS provider integration
    import uuid
    return {
        "message_id": str(uuid.uuid4()),
        "to": to,
        "message": message,
        "provider": "mock"
    }


def _render_email_template(template_id: str, data: Dict[str, Any]) -> Optional[Dict[str, str]]:
    """Render email template with data."""
    try:
        # TODO: Load template from database or file system
        # This is a mock implementation
        template_content = {
            "welcome": {
                "subject": "Welcome to {{ app_name }}!",
                "body": "Hello {{ user_name }}, welcome to {{ app_name }}!",
                "html_body": "<h1>Hello {{ user_name }}</h1><p>Welcome to {{ app_name }}!</p>"
            },
            "notification": {
                "subject": "{{ subject }}",
                "body": "{{ message }}",
                "html_body": "<p>{{ message }}</p>"
            }
        }
        
        template = template_content.get(template_id)
        if not template:
            return None
        
        # Render templates
        rendered = {}
        for key, value in template.items():
            if value:
                jinja_template = Template(value)
                rendered[key] = jinja_template.render(data)
        
        return rendered
        
    except Exception as exc:
        logger.error("Template rendering failed", template_id=template_id, error=str(exc))
        return None


def _render_sms_template(template_id: str, data: Dict[str, Any]) -> Optional[str]:
    """Render SMS template with data."""
    try:
        # TODO: Load template from database or file system
        # This is a mock implementation
        template_content = {
            "welcome": "Welcome to {{ app_name }}, {{ user_name }}!",
            "notification": "{{ message }}",
            "alert": "ALERT: {{ message }}"
        }
        
        template_text = template_content.get(template_id)
        if not template_text:
            return None
        
        jinja_template = Template(template_text)
        return jinja_template.render(data)
        
    except Exception as exc:
        logger.error("SMS template rendering failed", template_id=template_id, error=str(exc))
        return None


@celery_app.task(base=BaseTask, name="automation.notifications.cleanup")
def cleanup_notifications_task(days_old: int = 90) -> Dict[str, Any]:
    """Clean up old notification records."""
    logger.info("Cleaning up old notifications", days_old=days_old)
    
    try:
        # TODO: Implement cleanup logic
        cleanup_result = {
            "notifications_deleted": 0,
            "cleanup_completed_at": datetime.utcnow().isoformat()
        }
        
        logger.info(
            "Notification cleanup completed",
            notifications_deleted=cleanup_result["notifications_deleted"]
        )
        
        return cleanup_result
        
    except Exception as exc:
        logger.error("Notification cleanup failed", error=str(exc))
        raise