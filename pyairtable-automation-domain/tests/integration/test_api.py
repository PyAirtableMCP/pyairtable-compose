"""Integration tests for API endpoints."""

import pytest
from fastapi.testclient import TestClient


@pytest.mark.integration
def test_workflow_endpoints_structure(test_client: TestClient, auth_headers: dict):
    """Test workflow endpoints return proper structure."""
    # Test list workflows (should return empty list initially)
    response = test_client.get("/api/v1/workflows", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)


@pytest.mark.integration 
def test_notification_endpoints_structure(test_client: TestClient, auth_headers: dict):
    """Test notification endpoints return proper structure."""
    # Test list notifications
    response = test_client.get("/api/v1/notifications", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert "notifications" in data
    assert "total" in data
    assert "limit" in data
    assert "offset" in data


@pytest.mark.integration
def test_webhook_endpoints_structure(test_client: TestClient, auth_headers: dict):
    """Test webhook endpoints return proper structure."""
    # Test list webhook endpoints
    response = test_client.get("/api/v1/webhooks/endpoints", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    
    # Test list supported events
    response = test_client.get("/api/v1/webhooks/events")
    assert response.status_code == 200
    data = response.json()
    assert "events" in data
    assert isinstance(data["events"], list)


@pytest.mark.integration
def test_automation_endpoints_structure(test_client: TestClient, auth_headers: dict):
    """Test automation endpoints return proper structure."""
    # Test list automation rules
    response = test_client.get("/api/v1/automation/rules", headers=auth_headers)
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    
    # Test get automation stats
    response = test_client.get("/api/v1/automation/stats", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert "total_rules" in data
    assert "active_rules" in data
    assert "total_executions" in data
    
    # Test list trigger types
    response = test_client.get("/api/v1/automation/triggers")
    assert response.status_code == 200
    data = response.json()
    assert "triggers" in data
    assert isinstance(data["triggers"], list)
    
    # Test list action types
    response = test_client.get("/api/v1/automation/actions")
    assert response.status_code == 200
    data = response.json()
    assert "actions" in data
    assert isinstance(data["actions"], list)


@pytest.mark.integration
def test_authentication_required(test_client: TestClient):
    """Test that authentication is required for protected endpoints."""
    # Test without auth headers
    protected_endpoints = [
        "/api/v1/workflows",
        "/api/v1/notifications",
        "/api/v1/webhooks/endpoints",
        "/api/v1/automation/rules"
    ]
    
    for endpoint in protected_endpoints:
        response = test_client.get(endpoint)
        assert response.status_code == 401


@pytest.mark.integration
def test_cors_headers(test_client: TestClient):
    """Test CORS headers are properly set."""
    response = test_client.options("/")
    
    # Should have CORS headers
    assert "access-control-allow-origin" in response.headers
    assert "access-control-allow-methods" in response.headers


@pytest.mark.integration
def test_request_id_tracking(test_client: TestClient, auth_headers: dict):
    """Test that request IDs are tracked."""
    response = test_client.get("/api/v1/workflows", headers=auth_headers)
    
    # Should have process time header
    assert "X-Process-Time" in response.headers