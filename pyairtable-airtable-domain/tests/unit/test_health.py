"""Unit tests for health endpoints."""

import pytest
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_health_check(test_client: TestClient):
    """Test basic health check endpoint."""
    response = test_client.get("/health")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert data["service"] == "pyairtable-airtable-domain"
    assert data["version"] == "1.0.0"


@pytest.mark.unit
def test_root_endpoint(test_client: TestClient):
    """Test root endpoint."""
    response = test_client.get("/")
    
    assert response.status_code == 200
    data = response.json()
    
    assert "service" in data
    assert "version" in data
    assert "description" in data
    assert data["status"] == "healthy"


@pytest.mark.unit
def test_service_info(test_client: TestClient):
    """Test service info endpoint."""
    response = test_client.get("/info")
    
    assert response.status_code == 200
    data = response.json()
    
    assert "service" in data
    assert "version" in data
    assert "features" in data
    assert "endpoints" in data
    assert isinstance(data["features"], list)
    assert len(data["features"]) > 0


@pytest.mark.unit
def test_readiness_check(test_client: TestClient):
    """Test readiness probe endpoint."""
    response = test_client.get("/ready")
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"


@pytest.mark.unit
def test_liveness_check(test_client: TestClient):
    """Test liveness probe endpoint."""
    response = test_client.get("/live")
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"