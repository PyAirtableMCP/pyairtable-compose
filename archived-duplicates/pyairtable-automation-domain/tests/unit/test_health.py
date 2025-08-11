"""Unit tests for health check endpoints."""

import pytest
from fastapi.testclient import TestClient


@pytest.mark.unit
def test_health_check(test_client: TestClient):
    """Test basic health check endpoint."""
    response = test_client.get("/health")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["status"] == "healthy"
    assert data["service"] == "automation-domain"
    assert "timestamp" in data


@pytest.mark.unit
def test_readiness_check(test_client: TestClient):
    """Test readiness check endpoint."""
    response = test_client.get("/ready")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["status"] == "ready"
    assert "timestamp" in data


@pytest.mark.unit
def test_liveness_check(test_client: TestClient):
    """Test liveness check endpoint."""
    response = test_client.get("/live")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["status"] == "alive"
    assert "timestamp" in data


@pytest.mark.unit
def test_root_endpoint(test_client: TestClient):
    """Test root service information endpoint."""
    response = test_client.get("/")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["service"] == "PyAirtable Automation Domain"
    assert data["version"] == "1.0.0"
    assert data["status"] == "healthy"
    assert "environment" in data


@pytest.mark.unit
def test_service_info_endpoint(test_client: TestClient):
    """Test detailed service information endpoint."""
    response = test_client.get("/info")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["service"] == "PyAirtable Automation Domain"
    assert data["version"] == "1.0.0"
    assert "features" in data
    assert "endpoints" in data
    
    # Check that key features are listed
    features = data["features"]
    assert "Workflow Execution Engine" in features
    assert "Email & SMS Notifications" in features
    assert "Webhook Management & Delivery" in features
    assert "Automation Orchestration" in features
    
    # Check that key endpoints are listed
    endpoints = data["endpoints"]
    assert "health" in endpoints
    assert "workflows" in endpoints
    assert "notifications" in endpoints
    assert "webhooks" in endpoints
    assert "automation" in endpoints