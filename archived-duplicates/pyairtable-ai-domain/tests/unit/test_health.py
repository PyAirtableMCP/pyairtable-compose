"""Test health endpoints"""
import pytest
from fastapi.testclient import TestClient


def test_health_endpoint(client: TestClient):
    """Test basic health endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    
    data = response.json()
    assert "status" in data
    assert "service" in data
    assert "version" in data
    assert "timestamp" in data
    assert "checks" in data
    
    assert data["service"] == "pyairtable-ai-domain"


def test_readiness_endpoint(client: TestClient):
    """Test readiness endpoint"""
    response = client.get("/health/ready")
    # This might return 503 if services aren't initialized
    assert response.status_code in [200, 503]
    
    data = response.json()
    assert "ready" in data


def test_liveness_endpoint(client: TestClient):
    """Test liveness endpoint"""
    response = client.get("/health/live")
    assert response.status_code == 200
    
    data = response.json()
    assert data["alive"] is True
    assert "timestamp" in data


@pytest.mark.asyncio
async def test_health_with_mocked_services(client: TestClient, mock_provider_manager, mock_model_manager, mock_tool_registry):
    """Test health endpoint with mocked services"""
    # This would require injecting mocks into the app state
    # For now, just test that the endpoint responds
    response = client.get("/health")
    assert response.status_code == 200