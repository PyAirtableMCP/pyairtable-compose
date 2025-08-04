"""Pytest configuration and fixtures."""

import asyncio
import os
from typing import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from src.core.app import create_application
from src.core.config import get_settings
from src.database.base import Base
from src.database.connection import get_session
from src.utils.redis_client import get_redis_client


@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
def test_settings():
    """Test settings with overrides."""
    # Set test environment variables
    os.environ.update({
        "ENVIRONMENT": "testing",
        "DATABASE_URL": "sqlite+aiosqlite:///:memory:",
        "REDIS_URL": "redis://localhost:6379/15",  # Use test database
        "AIRTABLE_TOKEN": "test_token",
        "SECURITY_INTERNAL_API_KEY": "test_api_key",
        "SECURITY_JWT_SECRET_KEY": "test_jwt_secret",
        "OBSERVABILITY_LOG_LEVEL": "DEBUG",
    })
    
    # Clear settings cache and get fresh instance
    get_settings.cache_clear()
    return get_settings()


@pytest.fixture(scope="session")
async def test_db_engine(test_settings):
    """Create test database engine."""
    engine = create_async_engine(
        test_settings.database.url,
        echo=test_settings.database.echo,
    )
    
    # Create all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    yield engine
    
    # Drop all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    
    await engine.dispose()


@pytest.fixture
async def test_db_session(test_db_engine) -> AsyncGenerator[AsyncSession, None]:
    """Create test database session."""
    session_factory = sessionmaker(
        bind=test_db_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    
    async with session_factory() as session:
        yield session
        await session.rollback()


@pytest.fixture
def mock_redis():
    """Mock Redis client."""
    mock_redis = AsyncMock()
    mock_redis.get.return_value = None
    mock_redis.set.return_value = True
    mock_redis.setex.return_value = True
    mock_redis.delete.return_value = 1
    mock_redis.scan.return_value = (0, [])
    mock_redis.ping.return_value = True
    return mock_redis


@pytest.fixture
def test_app(test_settings, test_db_session, mock_redis):
    """Create test FastAPI application."""
    app = create_application()
    
    # Override dependencies
    app.dependency_overrides[get_session] = lambda: test_db_session
    app.dependency_overrides[get_redis_client] = lambda: mock_redis
    
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
def mock_airtable_response():
    """Mock Airtable API response."""
    return {
        "records": [
            {
                "id": "rec123456789",
                "fields": {
                    "Name": "Test Record",
                    "Status": "Active"
                },
                "createdTime": "2023-01-01T00:00:00.000Z"
            }
        ]
    }


@pytest.fixture
def mock_airtable_base():
    """Mock Airtable base data."""
    return {
        "id": "app123456789",
        "name": "Test Base",
        "permissionLevel": "create"
    }


@pytest.fixture
def mock_airtable_table():
    """Mock Airtable table schema."""
    return {
        "id": "tbl123456789",
        "name": "Test Table",
        "primaryFieldId": "fld123456789",
        "fields": [
            {
                "id": "fld123456789",
                "name": "Name",
                "type": "singleLineText"
            }
        ]
    }


@pytest.fixture
def auth_headers():
    """Authentication headers for testing."""
    return {
        "X-API-Key": "test_api_key"
    }


@pytest.fixture
def jwt_headers():
    """JWT authentication headers for testing."""
    # This would generate a valid JWT token for testing
    return {
        "Authorization": "Bearer test_jwt_token"
    }


@pytest.fixture(autouse=True)
def reset_mocks():
    """Reset all mocks after each test."""
    yield
    # Reset any global state or mocks here


# Test data factories

@pytest.fixture
def create_test_workflow():
    """Factory for creating test workflow data."""
    def _create_workflow(**kwargs):
        default_data = {
            "name": "Test Workflow",
            "description": "Test workflow description",
            "trigger": {
                "type": "manual",
                "settings": {}
            },
            "actions": [
                {
                    "name": "Test Action",
                    "type": "airtable_create",
                    "settings": {
                        "base_id": "app123456789",
                        "table_id": "tbl123456789"
                    }
                }
            ]
        }
        default_data.update(kwargs)
        return default_data
    
    return _create_workflow


@pytest.fixture
def create_test_record():
    """Factory for creating test record data."""
    def _create_record(**kwargs):
        default_data = {
            "fields": {
                "Name": "Test Record",
                "Status": "Active"
            }
        }
        default_data.update(kwargs)
        return default_data
    
    return _create_record


# Async fixtures for database operations

@pytest_asyncio.fixture
async def create_test_db_workflow(test_db_session):
    """Create a test workflow in the database."""
    from src.models.workflows import Workflow, WorkflowStatus
    
    workflow = Workflow(
        name="Test Workflow",
        description="Test workflow",
        status=WorkflowStatus.DRAFT,
        trigger_config={"type": "manual"},
        actions_config=[{"type": "test_action"}],
    )
    
    test_db_session.add(workflow)
    await test_db_session.commit()
    await test_db_session.refresh(workflow)
    
    return workflow


# Mock external services

@pytest.fixture
def mock_httpx_client():
    """Mock httpx AsyncClient for external API calls."""
    mock_client = AsyncMock()
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {"success": True}
    mock_client.request.return_value = mock_response
    return mock_client


@pytest.fixture(autouse=True)
def mock_external_services(monkeypatch, mock_httpx_client):
    """Mock all external services by default."""
    # Mock httpx client
    monkeypatch.setattr("httpx.AsyncClient", lambda **kwargs: mock_httpx_client)
    
    # Add other external service mocks here
    pass


# Markers for different test types

def pytest_configure(config):
    """Configure pytest markers."""
    config.addinivalue_line("markers", "unit: Unit tests")
    config.addinivalue_line("markers", "integration: Integration tests")
    config.addinivalue_line("markers", "slow: Slow running tests")
    config.addinivalue_line("markers", "external: Tests requiring external services")