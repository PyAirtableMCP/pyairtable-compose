"""Test configuration and fixtures"""
import pytest
import asyncio
from typing import AsyncGenerator
from fastapi.testclient import TestClient

from src.core.app import create_app
from src.core.config import get_settings


@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def app():
    """Create FastAPI app for testing"""
    return create_app()


@pytest.fixture
def client(app):
    """Create test client"""
    return TestClient(app)


@pytest.fixture
def settings():
    """Get test settings"""
    return get_settings()


@pytest.fixture
async def mock_provider_manager():
    """Mock LLM provider manager for testing"""
    from unittest.mock import AsyncMock, MagicMock
    
    mock_manager = AsyncMock()
    mock_manager.chat_completion = AsyncMock()
    mock_manager.stream_chat_completion = AsyncMock()
    mock_manager.create_embeddings = AsyncMock()
    mock_manager.list_models = AsyncMock(return_value=[])
    mock_manager.get_provider_health = AsyncMock(return_value={})
    mock_manager.get_usage_stats = AsyncMock(return_value={})
    
    return mock_manager


@pytest.fixture
async def mock_model_manager():
    """Mock model manager for testing"""
    from unittest.mock import AsyncMock
    
    mock_manager = AsyncMock()
    mock_manager.generate_embeddings = AsyncMock()
    mock_manager.classify_text = AsyncMock()
    mock_manager.generate_text = AsyncMock()
    mock_manager.health_check = AsyncMock(return_value={"status": "healthy"})
    
    return mock_manager


@pytest.fixture
async def mock_tool_registry():
    """Mock tool registry for testing"""
    from unittest.mock import AsyncMock
    
    mock_registry = AsyncMock()
    mock_registry.execute_tool = AsyncMock()
    mock_registry.list_tools = AsyncMock(return_value=[])
    mock_registry.health_check = AsyncMock(return_value={"status": "healthy"})
    
    return mock_registry