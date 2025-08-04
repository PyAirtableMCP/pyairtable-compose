"""
Global pytest configuration for PyAirtable test suite.
Provides shared fixtures, test environment setup, and common utilities.
"""

import asyncio
import os
import pytest
import docker
import asyncpg
import redis.asyncio as redis
import httpx
from typing import AsyncGenerator, Dict, Any
from pathlib import Path
from dataclasses import dataclass
from unittest.mock import AsyncMock
import logging

# Configure logging for tests
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class TestEnvironment:
    """Test environment configuration"""
    database_url: str
    redis_url: str
    api_gateway_url: str
    llm_orchestrator_url: str
    airtable_gateway_url: str
    mcp_server_url: str
    auth_service_url: str
    is_integration: bool = False
    is_e2e: bool = False

# Test environment configuration
TEST_ENV = os.getenv("TEST_ENV", "unit")
IS_CI = os.getenv("CI", "false").lower() == "true"

# Database configuration
TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql://test_user:test_password@localhost:5433/test_db"
)

# Redis configuration
TEST_REDIS_URL = os.getenv(
    "TEST_REDIS_URL",
    "redis://:test_password@localhost:6380"
)

# Service URLs for integration tests
SERVICE_URLS = {
    "api_gateway": os.getenv("API_GATEWAY_URL", "http://localhost:8000"),
    "llm_orchestrator": os.getenv("LLM_ORCHESTRATOR_URL", "http://localhost:8003"),
    "airtable_gateway": os.getenv("AIRTABLE_GATEWAY_URL", "http://localhost:8001"),
    "mcp_server": os.getenv("MCP_SERVER_URL", "http://localhost:8002"),
    "auth_service": os.getenv("AUTH_SERVICE_URL", "http://localhost:8004"),
}

def pytest_configure(config):
    """Configure pytest with custom markers"""
    config.addinivalue_line("markers", "unit: Unit tests")
    config.addinivalue_line("markers", "integration: Integration tests")
    config.addinivalue_line("markers", "e2e: End-to-end tests")
    config.addinivalue_line("markers", "performance: Performance tests")
    config.addinivalue_line("markers", "security: Security tests")
    config.addinivalue_line("markers", "chaos: Chaos engineering tests")
    config.addinivalue_line("markers", "slow: Slow tests")
    config.addinivalue_line("markers", "database: Tests requiring database")
    config.addinivalue_line("markers", "redis: Tests requiring Redis")
    config.addinivalue_line("markers", "external: Tests requiring external services")

def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers based on location"""
    for item in items:
        # Add markers based on test location
        if "unit" in str(item.fspath):
            item.add_marker(pytest.mark.unit)
        elif "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)
        elif "e2e" in str(item.fspath):
            item.add_marker(pytest.mark.e2e)
        elif "performance" in str(item.fspath):
            item.add_marker(pytest.mark.performance)
        elif "security" in str(item.fspath):
            item.add_marker(pytest.mark.security)
        elif "chaos" in str(item.fspath):
            item.add_marker(pytest.mark.chaos)

@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    yield loop
    loop.close()

@pytest.fixture(scope="session")
def test_environment() -> TestEnvironment:
    """Provide test environment configuration"""
    return TestEnvironment(
        database_url=TEST_DATABASE_URL,
        redis_url=TEST_REDIS_URL,
        api_gateway_url=SERVICE_URLS["api_gateway"],
        llm_orchestrator_url=SERVICE_URLS["llm_orchestrator"],
        airtable_gateway_url=SERVICE_URLS["airtable_gateway"],
        mcp_server_url=SERVICE_URLS["mcp_server"],
        auth_service_url=SERVICE_URLS["auth_service"],
        is_integration=TEST_ENV in ["integration", "e2e"],
        is_e2e=TEST_ENV == "e2e"
    )

@pytest.fixture(scope="session")
async def docker_client():
    """Provide Docker client for container management"""
    if TEST_ENV in ["integration", "e2e"]:
        client = docker.from_env()
        yield client
        client.close()
    else:
        yield None

@pytest.fixture
async def db_connection() -> AsyncGenerator[asyncpg.Connection, None]:
    """Provide a database connection for tests"""
    if TEST_ENV in ["unit"] and not pytest.current_request.node.get_closest_marker("database"):
        # Skip database connection for unit tests unless specifically marked
        yield None
        return
    
    try:
        conn = await asyncpg.connect(TEST_DATABASE_URL)
        yield conn
    except Exception as e:
        logger.warning(f"Could not connect to test database: {e}")
        yield None
    finally:
        if 'conn' in locals():
            await conn.close()

@pytest.fixture
async def redis_client() -> AsyncGenerator[redis.Redis, None]:
    """Provide a Redis client for tests"""
    if TEST_ENV in ["unit"] and not pytest.current_request.node.get_closest_marker("redis"):
        # Skip Redis connection for unit tests unless specifically marked
        yield None
        return
    
    try:
        client = redis.Redis.from_url(TEST_REDIS_URL)
        await client.ping()  # Test connection
        yield client
    except Exception as e:
        logger.warning(f"Could not connect to test Redis: {e}")
        yield None
    finally:
        if 'client' in locals():
            await client.close()

@pytest.fixture
async def http_client() -> AsyncGenerator[httpx.AsyncClient, None]:
    """Provide an HTTP client for API testing"""
    async with httpx.AsyncClient(timeout=30.0) as client:
        yield client

@pytest.fixture
async def authenticated_client(http_client: httpx.AsyncClient, test_environment: TestEnvironment) -> httpx.AsyncClient:
    """Provide an authenticated HTTP client"""
    # Perform authentication
    auth_response = await http_client.post(
        f"{test_environment.auth_service_url}/auth/login",
        json={
            "email": "test@example.com",
            "password": "test_password"
        }
    )
    
    if auth_response.status_code == 200:
        token = auth_response.json().get("access_token")
        http_client.headers.update({"Authorization": f"Bearer {token}"})
    
    return http_client

@pytest.fixture(autouse=True)
async def cleanup_database(db_connection: asyncpg.Connection):
    """Clean database before each test"""
    if db_connection is None:
        yield
        return
    
    try:
        # Clean up test data before test
        await db_connection.execute("BEGIN")
        
        # Get all table names
        tables_query = """
            SELECT tablename FROM pg_tables 
            WHERE schemaname = 'public' 
            AND tablename NOT LIKE 'alembic_%'
        """
        tables = await db_connection.fetch(tables_query)
        
        # Truncate all tables
        for table in tables:
            await db_connection.execute(f"TRUNCATE TABLE {table['tablename']} CASCADE")
        
        await db_connection.execute("COMMIT")
        
        yield
        
        # Clean up after test
        await db_connection.execute("BEGIN")
        for table in tables:
            await db_connection.execute(f"TRUNCATE TABLE {table['tablename']} CASCADE")
        await db_connection.execute("COMMIT")
        
    except Exception as e:
        logger.warning(f"Database cleanup failed: {e}")
        if db_connection:
            await db_connection.execute("ROLLBACK")
        yield

@pytest.fixture(autouse=True)
async def cleanup_redis(redis_client: redis.Redis):
    """Clean Redis before each test"""
    if redis_client is None:
        yield
        return
    
    try:
        # Clean Redis before test
        await redis_client.flushdb()
        yield
        # Clean Redis after test
        await redis_client.flushdb()
    except Exception as e:
        logger.warning(f"Redis cleanup failed: {e}")
        yield

@pytest.fixture
def mock_external_services():
    """Provide mocks for external services"""
    mocks = {
        "airtable_api": AsyncMock(),
        "gemini_api": AsyncMock(),
        "openai_api": AsyncMock(),
        "anthropic_api": AsyncMock(),
    }
    
    # Configure default mock responses
    mocks["airtable_api"].get_records.return_value = {
        "records": [
            {"id": "rec123", "fields": {"Name": "Test Record"}}
        ]
    }
    
    mocks["gemini_api"].generate_content.return_value = {
        "text": "Mock AI response"
    }
    
    return mocks

@pytest.fixture
def test_data_factory():
    """Provide factory for generating test data"""
    from tests.fixtures.factories import TestDataFactory
    return TestDataFactory()

# Performance testing fixtures
@pytest.fixture
def performance_config():
    """Configuration for performance tests"""
    return {
        "load_test_users": int(os.getenv("LOAD_TEST_USERS", "10")),
        "stress_test_users": int(os.getenv("STRESS_TEST_USERS", "100")),
        "test_duration": int(os.getenv("TEST_DURATION", "60")),
        "ramp_up_time": int(os.getenv("RAMP_UP_TIME", "10")),
        "acceptable_response_time": float(os.getenv("ACCEPTABLE_RESPONSE_TIME", "2.0")),
        "acceptable_error_rate": float(os.getenv("ACCEPTABLE_ERROR_RATE", "0.01")),
    }

# Chaos engineering fixtures
@pytest.fixture
def chaos_config():
    """Configuration for chaos engineering tests"""
    return {
        "network_delay_ms": int(os.getenv("NETWORK_DELAY_MS", "100")),
        "packet_loss_rate": float(os.getenv("PACKET_LOSS_RATE", "0.1")),
        "cpu_stress_duration": int(os.getenv("CPU_STRESS_DURATION", "30")),
        "memory_stress_mb": int(os.getenv("MEMORY_STRESS_MB", "512")),
        "disk_stress_duration": int(os.getenv("DISK_STRESS_DURATION", "30")),
    }

# Helper functions
def skip_if_not_integration():
    """Skip test if not running integration tests"""
    return pytest.mark.skipif(
        TEST_ENV not in ["integration", "e2e"],
        reason="Integration test environment not available"
    )

def skip_if_not_e2e():
    """Skip test if not running E2E tests"""
    return pytest.mark.skipif(
        TEST_ENV != "e2e",
        reason="E2E test environment not available"
    )

def requires_service(service_name: str):
    """Mark test as requiring specific service"""
    return pytest.mark.skipif(
        not os.getenv(f"{service_name.upper()}_URL"),
        reason=f"{service_name} service not available"
    )