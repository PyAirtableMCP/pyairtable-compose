"""
Pytest configuration and shared fixtures for integration tests.
"""

import pytest
import asyncio
import httpx
import os
from typing import Dict, Any
from datetime import datetime


def pytest_configure(config):
    """Configure pytest with custom markers"""
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests (deselect with '-m \"not integration\"')"
    )
    config.option.asyncio_mode = "auto"
    config.addinivalue_line(
        "markers", "auth: marks tests as authentication-related"
    )
    config.addinivalue_line(
        "markers", "api_gateway: marks tests as API gateway-related"
    )
    config.addinivalue_line(
        "markers", "frontend: marks tests as frontend communication-related"
    )
    config.addinivalue_line(
        "markers", "ai_chat: marks tests as AI chat functionality-related"
    )
    config.addinivalue_line(
        "markers", "health: marks tests as health check-related"
    )
    config.addinivalue_line(
        "markers", "slow: marks tests as slow running (> 5s)"
    )


def pytest_collection_modifyitems(config, items):
    """Modify test collection to handle markers and skip conditions"""
    for item in items:
        # Add integration marker to all tests in integration directory
        if "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)


@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="session")
def service_urls():
    """Service URLs configuration"""
    return {
        "api_gateway": os.getenv("API_GATEWAY_URL", "http://localhost:8000"),
        "platform_services": os.getenv("PLATFORM_SERVICES_URL", "http://localhost:8007"),
        "airtable_gateway": os.getenv("AIRTABLE_GATEWAY_URL", "http://localhost:8002"),
        "ai_processing": os.getenv("AI_PROCESSING_URL", "http://localhost:8001"),
        "frontend": os.getenv("FRONTEND_URL", "http://localhost:5173"),
    }


@pytest.fixture(scope="session")
async def health_check_all_services(service_urls):
    """Check if all services are healthy before running tests"""
    async with httpx.AsyncClient(timeout=10.0) as client:
        service_status = {}
        
        for service_name, url in service_urls.items():
            try:
                # Try common health endpoints
                health_paths = ["/health", "/api/health", "/api/v1/health"]
                
                for path in health_paths:
                    try:
                        response = await client.get(f"{url}{path}")
                        if response.status_code == 200:
                            service_status[service_name] = "healthy"
                            break
                    except:
                        continue
                else:
                    service_status[service_name] = "unreachable"
                    
            except Exception as e:
                service_status[service_name] = f"error: {str(e)}"
        
        return service_status


@pytest.fixture
def integration_test_config():
    """Configuration for integration tests"""
    return {
        "timeout": 30.0,
        "retry_attempts": 3,
        "retry_delay": 1.0,
        "test_data_prefix": f"test_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
    }


@pytest.fixture
async def cleanup_test_users():
    """Fixture to cleanup test users after tests (if needed)"""
    created_users = []
    
    def register_user(user_data):
        created_users.append(user_data)
        
    yield register_user
    
    # Cleanup logic would go here if we had admin endpoints
    # For now, we rely on test isolation and unique emails


class ServiceAvailability:
    """Helper class to check and manage service availability"""
    
    @staticmethod
    async def check_service(url: str, timeout: float = 5.0) -> Dict[str, Any]:
        """Check if a service is available"""
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                # Try health endpoint
                response = await client.get(f"{url}/health")
                if response.status_code == 200:
                    return {
                        "available": True,
                        "status": "healthy",
                        "response_time": response.elapsed.total_seconds()
                    }
                else:
                    return {
                        "available": True,
                        "status": f"unhealthy_status_{response.status_code}",
                        "response_time": response.elapsed.total_seconds()
                    }
        except httpx.ConnectError:
            return {"available": False, "status": "connection_error"}
        except httpx.TimeoutException:
            return {"available": False, "status": "timeout"}
        except Exception as e:
            return {"available": False, "status": f"error_{type(e).__name__}"}
    
    @staticmethod
    async def wait_for_service(url: str, max_wait: float = 30.0, check_interval: float = 1.0):
        """Wait for a service to become available"""
        import time
        start_time = time.time()
        
        while time.time() - start_time < max_wait:
            status = await ServiceAvailability.check_service(url)
            if status["available"]:
                return True
            await asyncio.sleep(check_interval)
        
        return False


@pytest.fixture
def service_availability():
    """Provide service availability helper"""
    return ServiceAvailability


def pytest_runtest_setup(item):
    """Setup function run before each test"""
    # Add any pre-test setup here
    pass


def pytest_runtest_teardown(item):
    """Teardown function run after each test"""
    # Add any post-test cleanup here
    pass


def pytest_sessionstart(session):
    """Called after the Session object has been created"""
    print("\n" + "="*60)
    print("PyAirtable Integration Test Suite - Sprint 1")
    print("="*60)
    print("Testing authentication, API routing, and core functionality")
    print("="*60 + "\n")


def pytest_sessionfinish(session, exitstatus):
    """Called after whole test run finished"""
    if exitstatus == 0:
        print("\n" + "="*60)
        print("✅ All Integration Tests Passed!")
        print("Sprint 1 functionality verified successfully")
        print("="*60 + "\n")
    else:
        print("\n" + "="*60) 
        print("❌ Some Integration Tests Failed")
        print("Check the test output above for details")
        print("="*60 + "\n")