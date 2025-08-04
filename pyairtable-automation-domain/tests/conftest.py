"""Test configuration and fixtures."""

import asyncio
import os
from typing import AsyncGenerator, Generator

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from src.core.app import create_application
from src.core.config import Settings
from src.database.connection import get_session


# Set test environment
os.environ["ENV"] = "testing"
os.environ["DATABASE_URL"] = "postgresql+asyncpg://postgres:postgres@localhost:5432/pyairtable_automation_test"
os.environ["REDIS_URL"] = "redis://localhost:6379/15"
os.environ["INTERNAL_API_KEY"] = "test-api-key"
os.environ["JWT_SECRET_KEY"] = "test-jwt-secret"
os.environ["WEBHOOK_SECRET_KEY"] = "test-webhook-secret"


@pytest.fixture(scope="session")
def event_loop() -> Generator[asyncio.AbstractEventLoop, None, None]:
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def test_settings() -> Settings:
    """Get test settings."""
    return Settings()


@pytest.fixture
async def test_db_engine():
    """Create test database engine."""
    settings = Settings()
    engine = create_async_engine(
        settings.database.url,
        echo=settings.database.echo,
        pool_pre_ping=True,
    )
    yield engine
    await engine.dispose()


@pytest.fixture
async def test_db_session(test_db_engine) -> AsyncGenerator[AsyncSession, None]:
    """Create test database session."""
    async_session_factory = sessionmaker(
        test_db_engine,
        class_=AsyncSession,
        expire_on_commit=False
    )
    
    async with async_session_factory() as session:
        yield session


@pytest.fixture
def test_app():
    """Create test FastAPI application."""
    app = create_application()
    return app


@pytest.fixture
def test_client(test_app) -> TestClient:
    """Create test client."""
    return TestClient(test_app)


@pytest.fixture
async def async_test_client(test_app) -> AsyncGenerator[AsyncClient, None]:
    """Create async test client."""
    async with AsyncClient(app=test_app, base_url="http://test") as client:
        yield client


@pytest.fixture
def auth_headers() -> dict:
    """Get authentication headers for tests."""
    return {
        "Authorization": "Bearer test-api-key",
        "Content-Type": "application/json"
    }


@pytest.fixture
def mock_workflow_data() -> dict:
    """Mock workflow data for tests."""
    return {
        "name": "Test Workflow",
        "description": "A test workflow",
        "trigger_type": "manual",
        "trigger_config": {},
        "steps": [
            {
                "id": "step1",
                "type": "http_request",
                "config": {
                    "url": "https://httpbin.org/post",
                    "method": "POST",
                    "headers": {"Content-Type": "application/json"},
                    "body": {"test": "data"}
                }
            }
        ],
        "enabled": True
    }


@pytest.fixture
def mock_notification_data() -> dict:
    """Mock notification data for tests."""
    return {
        "to": ["test@example.com"],
        "subject": "Test Notification",
        "body": "This is a test notification",
        "html_body": "<p>This is a test notification</p>",
        "priority": "normal"
    }


@pytest.fixture
def mock_webhook_endpoint_data() -> dict:
    """Mock webhook endpoint data for tests."""
    return {
        "name": "Test Webhook",
        "url": "https://httpbin.org/post",
        "description": "A test webhook endpoint",
        "events": ["workflow.completed", "notification.sent"],
        "enabled": True,
        "secret": "test-secret",
        "headers": {"X-Source": "pyairtable"},
        "retry_policy": {
            "max_retries": 3,
            "retry_delay": 60,
            "backoff_multiplier": 2
        }
    }


@pytest.fixture
def mock_automation_rule_data() -> dict:
    """Mock automation rule data for tests."""
    return {
        "name": "Test Automation Rule",
        "description": "A test automation rule",
        "trigger": {
            "type": "event",
            "event_type": "user.created"
        },
        "conditions": [
            {
                "type": "field_check",
                "field": "user.active",
                "operator": "equals",
                "value": True
            }
        ],
        "actions": [
            {
                "type": "notification",
                "notification_type": "email",
                "template": "welcome_email",
                "to": "{{user.email}}"
            }
        ],
        "enabled": True,
        "priority": 1
    }


@pytest.fixture
def celery_worker_parameters():
    """Configure Celery worker for tests."""
    return {
        "perform_ping_check": False,
        "pool": "solo",  # Use solo pool for testing
    }


@pytest.fixture
def celery_config():
    """Configure Celery for tests."""
    return {
        "broker_url": "redis://localhost:6379/15",
        "result_backend": "redis://localhost:6379/15",
        "task_always_eager": True,  # Execute tasks synchronously
        "task_eager_propagates": True,  # Propagate exceptions
    }


# Markers for different test types
def pytest_configure(config):
    """Configure pytest markers."""
    config.addinivalue_line("markers", "unit: mark test as a unit test")
    config.addinivalue_line("markers", "integration: mark test as an integration test")
    config.addinivalue_line("markers", "celery: mark test as requiring Celery worker")
    config.addinivalue_line("markers", "slow: mark test as slow running")


# Database dependency override for tests
def get_test_session_dependency(test_db_session):
    """Override database session dependency for tests."""
    async def _get_test_session():
        yield test_db_session
    return _get_test_session