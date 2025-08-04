"""Webhook delivery tasks."""

import asyncio
import hashlib
import hmac
import json
from datetime import datetime
from typing import Any, Dict, List, Optional

import httpx
from celery import Task

from .celery_app import get_celery_app, BaseTask
from ..core.config import get_settings
from ..core.logging import get_logger

# Get Celery app instance
celery_app = get_celery_app()
logger = get_logger(__name__)


@celery_app.task(base=BaseTask, bind=True, name="automation.webhooks.deliver")
def deliver_webhook_task(
    self: Task,
    endpoint_id: str,
    url: str,
    payload: Dict[str, Any],
    method: str = "POST",
    headers: Optional[Dict[str, str]] = None,
    secret: Optional[str] = None,
    retry_policy: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Deliver webhook to endpoint."""
    logger.info(
        "Delivering webhook",
        endpoint_id=endpoint_id,
        url=url,
        method=method
    )
    
    try:
        # Prepare headers
        request_headers = headers.copy() if headers else {}
        request_headers["Content-Type"] = "application/json"
        request_headers["User-Agent"] = "PyAirtable-Webhook/1.0"
        
        # Add timestamp
        timestamp = datetime.utcnow().isoformat()
        request_headers["X-Webhook-Timestamp"] = timestamp
        
        # Prepare payload
        payload_with_meta = {
            **payload,
            "timestamp": timestamp,
            "webhook_id": self.request.id
        }
        
        payload_json = json.dumps(payload_with_meta, sort_keys=True)
        
        # Add signature if secret provided
        if secret:
            signature = _generate_webhook_signature(payload_json, secret)
            request_headers["X-Webhook-Signature"] = signature
        
        # Deliver webhook
        result = asyncio.run(_deliver_webhook_async(
            url=url,
            method=method,
            payload=payload_json,
            headers=request_headers
        ))
        
        logger.info(
            "Webhook delivered successfully",
            endpoint_id=endpoint_id,
            url=url,
            status_code=result["status_code"],
            delivery_id=result["delivery_id"]
        )
        
        return {
            "status": "delivered",
            "endpoint_id": endpoint_id,
            "url": url,
            "delivery_id": result["delivery_id"],
            "status_code": result["status_code"],
            "response_body": result["response_body"],
            "delivered_at": datetime.utcnow().isoformat(),
            "attempts": self.request.retries + 1,
            "task_id": self.request.id
        }
        
    except Exception as exc:
        logger.error(
            "Webhook delivery failed",
            endpoint_id=endpoint_id,
            url=url,
            error=str(exc)
        )
        
        # Get retry policy
        max_retries = 3
        retry_delay = 60
        if retry_policy:
            max_retries = retry_policy.get("max_retries", 3)
            retry_delay = retry_policy.get("retry_delay", 60)
        
        # Retry logic
        if self.request.retries < max_retries:
            # Exponential backoff
            backoff_multiplier = retry_policy.get("backoff_multiplier", 2) if retry_policy else 2
            delay = retry_delay * (backoff_multiplier ** self.request.retries)
            
            logger.info(
                "Retrying webhook delivery",
                endpoint_id=endpoint_id,
                url=url,
                retry_count=self.request.retries + 1,
                delay=delay
            )
            raise self.retry(countdown=delay, exc=exc)
        
        # Final failure
        return {
            "status": "failed",
            "endpoint_id": endpoint_id,
            "url": url,
            "error": str(exc),
            "failed_at": datetime.utcnow().isoformat(),
            "attempts": self.request.retries + 1,
            "task_id": self.request.id
        }


@celery_app.task(base=BaseTask, bind=True, name="automation.webhooks.deliver_to_endpoints")
def deliver_to_endpoints_task(
    self: Task,
    event_type: str,
    payload: Dict[str, Any],
    source: str = "automation"
) -> Dict[str, Any]:
    """Deliver webhook to all subscribed endpoints."""
    logger.info(
        "Delivering webhook to subscribed endpoints",
        event_type=event_type,
        source=source
    )
    
    try:
        # TODO: Query database for subscribed endpoints
        # This is a mock implementation
        subscribed_endpoints = _get_subscribed_endpoints(event_type)
        
        delivery_results = []
        for endpoint in subscribed_endpoints:
            # Queue individual delivery task
            delivery_task = deliver_webhook_task.delay(
                endpoint_id=endpoint["id"],
                url=endpoint["url"],
                payload=payload,
                method=endpoint.get("method", "POST"),
                headers=endpoint.get("headers"),
                secret=endpoint.get("secret"),
                retry_policy=endpoint.get("retry_policy")
            )
            
            delivery_results.append({
                "endpoint_id": endpoint["id"],
                "task_id": delivery_task.id,
                "status": "queued"
            })
        
        logger.info(
            "Webhook delivery queued for endpoints",
            event_type=event_type,
            endpoint_count=len(subscribed_endpoints)
        )
        
        return {
            "event_type": event_type,
            "source": source,
            "endpoint_count": len(subscribed_endpoints),
            "deliveries": delivery_results,
            "queued_at": datetime.utcnow().isoformat()
        }
        
    except Exception as exc:
        logger.error(
            "Failed to queue webhook deliveries",
            event_type=event_type,
            error=str(exc)
        )
        raise


@celery_app.task(base=BaseTask, bind=True, name="automation.webhooks.verify_endpoint")
def verify_webhook_endpoint_task(
    self: Task,
    endpoint_id: str,
    url: str,
    secret: Optional[str] = None
) -> Dict[str, Any]:
    """Verify webhook endpoint is reachable."""
    logger.info("Verifying webhook endpoint", endpoint_id=endpoint_id, url=url)
    
    try:
        # Send verification request
        verification_payload = {
            "type": "webhook_verification",
            "endpoint_id": endpoint_id,
            "timestamp": datetime.utcnow().isoformat(),
            "challenge": f"verify_{endpoint_id}_{datetime.utcnow().timestamp()}"
        }
        
        headers = {
            "Content-Type": "application/json",
            "User-Agent": "PyAirtable-Webhook-Verification/1.0"
        }
        
        payload_json = json.dumps(verification_payload)
        
        if secret:
            signature = _generate_webhook_signature(payload_json, secret)
            headers["X-Webhook-Signature"] = signature
        
        result = asyncio.run(_deliver_webhook_async(
            url=url,
            method="POST",
            payload=payload_json,
            headers=headers,
            timeout=10  # Shorter timeout for verification
        ))
        
        # Check if verification was successful
        is_verified = result["status_code"] in [200, 201, 202]
        
        logger.info(
            "Webhook endpoint verification completed",
            endpoint_id=endpoint_id,
            url=url,
            verified=is_verified,
            status_code=result["status_code"]
        )
        
        return {
            "endpoint_id": endpoint_id,
            "url": url,
            "verified": is_verified,
            "status_code": result["status_code"],
            "response_body": result["response_body"],
            "verified_at": datetime.utcnow().isoformat()
        }
        
    except Exception as exc:
        logger.error(
            "Webhook endpoint verification failed",
            endpoint_id=endpoint_id,
            url=url,
            error=str(exc)
        )
        
        return {
            "endpoint_id": endpoint_id,
            "url": url,
            "verified": False,
            "error": str(exc),
            "verified_at": datetime.utcnow().isoformat()
        }


async def _deliver_webhook_async(
    url: str,
    method: str,
    payload: str,
    headers: Dict[str, str],
    timeout: int = 30
) -> Dict[str, Any]:
    """Deliver webhook asynchronously."""
    settings = get_settings()
    
    async with httpx.AsyncClient(
        timeout=timeout,
        verify=settings.webhook.verify_ssl
    ) as client:
        response = await client.request(
            method=method,
            url=url,
            content=payload,
            headers=headers
        )
        
        return {
            "delivery_id": headers.get("X-Webhook-Timestamp", "unknown"),
            "status_code": response.status_code,
            "response_body": response.text[:1000],  # Limit response body size
            "headers": dict(response.headers)
        }


def _generate_webhook_signature(payload: str, secret: str) -> str:
    """Generate HMAC signature for webhook."""
    signature = hmac.new(
        secret.encode("utf-8"),
        payload.encode("utf-8"),
        hashlib.sha256
    ).hexdigest()
    return f"sha256={signature}"


def _get_subscribed_endpoints(event_type: str) -> List[Dict[str, Any]]:
    """Get endpoints subscribed to event type."""
    # TODO: Replace with actual database query
    # This is a mock implementation
    mock_endpoints = [
        {
            "id": "endpoint_1",
            "url": "https://example.com/webhook",
            "method": "POST",
            "events": ["workflow.completed", "notification.sent"],
            "secret": "webhook_secret_123",
            "headers": {"X-Source": "pyairtable"},
            "retry_policy": {
                "max_retries": 3,
                "retry_delay": 60,
                "backoff_multiplier": 2
            }
        }
    ]
    
    # Filter endpoints by event type
    return [
        endpoint for endpoint in mock_endpoints
        if event_type in endpoint.get("events", [])
    ]


@celery_app.task(base=BaseTask, name="automation.webhooks.cleanup")
def cleanup_webhook_deliveries_task(days_old: int = 30) -> Dict[str, Any]:
    """Clean up old webhook delivery records."""
    logger.info("Cleaning up old webhook deliveries", days_old=days_old)
    
    try:
        # TODO: Implement cleanup logic
        cleanup_result = {
            "deliveries_deleted": 0,
            "cleanup_completed_at": datetime.utcnow().isoformat()
        }
        
        logger.info(
            "Webhook delivery cleanup completed",
            deliveries_deleted=cleanup_result["deliveries_deleted"]
        )
        
        return cleanup_result
        
    except Exception as exc:
        logger.error("Webhook delivery cleanup failed", error=str(exc))
        raise


@celery_app.task(base=BaseTask, name="automation.webhooks.health_check")
def webhook_health_check_task() -> Dict[str, Any]:
    """Perform health check on all webhook endpoints."""
    logger.info("Performing webhook endpoint health check")
    
    try:
        # TODO: Query all active endpoints and verify them
        # This is a mock implementation
        endpoints = []  # Would query from database
        
        verification_results = []
        for endpoint in endpoints:
            verification_task = verify_webhook_endpoint_task.delay(
                endpoint_id=endpoint["id"],
                url=endpoint["url"],
                secret=endpoint.get("secret")
            )
            verification_results.append({
                "endpoint_id": endpoint["id"],
                "task_id": verification_task.id
            })
        
        return {
            "endpoints_checked": len(endpoints),
            "verifications": verification_results,
            "health_check_started_at": datetime.utcnow().isoformat()
        }
        
    except Exception as exc:
        logger.error("Webhook health check failed", error=str(exc))
        raise