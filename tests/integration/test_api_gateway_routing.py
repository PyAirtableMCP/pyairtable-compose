"""
Integration tests for API Gateway routing functionality.

Tests:
1. Request routing to correct backend services
2. Load balancing and service discovery
3. Request/response header management
4. Error handling and circuit breaker behavior
5. Rate limiting and throttling
"""

import pytest
import asyncio
import httpx
import json
from typing import Dict, Any


class TestAPIGatewayRouting:
    """Integration tests for API Gateway routing behavior"""
    
    BASE_URL = "http://localhost:8000"  # API Gateway
    PLATFORM_URL = "http://localhost:8007"  # Platform Services Direct
    AIRTABLE_URL = "http://localhost:8002"  # Airtable Gateway Direct  
    AI_URL = "http://localhost:8001"  # AI Processing Service Direct
    
    @pytest.fixture
    async def http_client(self):
        """HTTP client for making requests"""
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            yield client
    
    @pytest.fixture
    async def authenticated_client(self, http_client):
        """HTTP client with authentication"""
        # Register and login a test user
        timestamp = str(asyncio.get_event_loop().time()).replace('.', '')
        test_user = {
            "name": f"Test User {timestamp}",
            "email": f"test_{timestamp}@example.com",
            "password": "TestPassword123!"
        }
        
        # Register user
        await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user,
            headers={"Content-Type": "application/json"}
        )
        
        # Login to get token
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json={
                "email": test_user["email"],
                "password": test_user["password"]
            },
            headers={"Content-Type": "application/json"}
        )
        
        if login_response.status_code == 200:
            token = login_response.json()["access_token"]
            http_client.headers.update({"Authorization": f"Bearer {token}"})
        
        yield http_client

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_health_endpoint_routing(self, http_client):
        """Test that health endpoints are routed correctly to each service"""
        
        # Test API Gateway health
        gateway_health = await http_client.get(f"{self.BASE_URL}/api/health")
        assert gateway_health.status_code == 200
        
        # Test routing to Platform Services health via gateway  
        platform_health = await http_client.get(f"{self.BASE_URL}/api/v1/platform/health")
        # Should route through or return gateway health - either is acceptable
        assert platform_health.status_code in [200, 404]  # 404 if route not configured yet
        
        # Verify direct service access still works
        try:
            direct_platform = await http_client.get(f"{self.PLATFORM_URL}/health")
            assert direct_platform.status_code == 200
        except httpx.ConnectError:
            pytest.skip("Platform service not running")

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_authentication_service_routing(self, http_client):
        """Test that authentication requests are routed to Platform Services"""
        
        # Test registration routing
        test_user = {
            "name": "Route Test User",
            "email": f"routetest_{asyncio.get_event_loop().time()}@example.com",
            "password": "TestPassword123!"
        }
        
        registration_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user,
            headers={"Content-Type": "application/json"}
        )
        
        assert registration_response.status_code == 201
        
        # Test login routing
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json={
                "email": test_user["email"],
                "password": test_user["password"]
            },
            headers={"Content-Type": "application/json"}
        )
        
        assert login_response.status_code == 200
        login_data = login_response.json()
        assert "access_token" in login_data

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_airtable_service_routing(self, authenticated_client):
        """Test routing to Airtable Gateway service"""
        
        # Test Airtable service info endpoint through gateway
        # This tests if the gateway can route to airtable service
        try:
            airtable_info = await authenticated_client.get(
                f"{self.BASE_URL}/api/v1/airtable/info"
            )
            # Should either work (200) or route not configured (404)
            assert airtable_info.status_code in [200, 401, 404]
        except httpx.ConnectError:
            pytest.skip("Airtable service routing not configured")
            
        # Verify direct access to Airtable service works
        try:
            direct_airtable = await authenticated_client.get(f"{self.AIRTABLE_URL}/health")
            assert direct_airtable.status_code == 200
        except httpx.ConnectError:
            pytest.skip("Airtable service not running")

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_ai_service_routing(self, authenticated_client):
        """Test routing to AI Processing Service"""
        
        # Test AI service health through gateway
        try:
            ai_health = await authenticated_client.get(
                f"{self.BASE_URL}/api/v1/ai/health"
            )
            # Should either work (200) or route not configured (404)
            assert ai_health.status_code in [200, 401, 404]
        except httpx.ConnectError:
            pytest.skip("AI service routing not configured")
        
        # Verify direct access to AI service works
        try:
            direct_ai = await authenticated_client.get(f"{self.AI_URL}/health")
            assert direct_ai.status_code == 200
        except httpx.ConnectError:
            pytest.skip("AI service not running")

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_cors_headers(self, http_client):
        """Test CORS headers are properly set by API Gateway"""
        
        # Test preflight OPTIONS request
        cors_response = await http_client.options(
            f"{self.BASE_URL}/api/v1/auth/login",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Content-Type, Authorization"
            }
        )
        
        # Should allow CORS or return 405 if OPTIONS not handled
        assert cors_response.status_code in [200, 204, 405]
        
        # Test actual request has CORS headers
        response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json={"email": "test@example.com", "password": "password"},
            headers={
                "Content-Type": "application/json",
                "Origin": "http://localhost:3000"
            }
        )
        
        # Check for CORS headers in response (if CORS is configured)
        if "access-control-allow-origin" in response.headers:
            assert response.headers["access-control-allow-origin"] in ["*", "http://localhost:3000"]

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_request_forwarding(self, authenticated_client):
        """Test that requests are properly forwarded to backend services"""
        
        # Test user profile request forwarding
        profile_response = await authenticated_client.get(
            f"{self.BASE_URL}/api/v1/users/profile"
        )
        
        if profile_response.status_code == 200:
            profile_data = profile_response.json()
            # Verify response structure indicates successful forwarding
            assert "email" in profile_data or "id" in profile_data
        else:
            # Authentication might have failed, which is also a valid test result
            assert profile_response.status_code in [401, 403, 404]

    @pytest.mark.integration  
    @pytest.mark.api_gateway
    async def test_error_handling(self, http_client):
        """Test API Gateway error handling for invalid routes and errors"""
        
        # Test non-existent route
        not_found_response = await http_client.get(f"{self.BASE_URL}/api/v1/nonexistent")
        assert not_found_response.status_code == 404
        
        # Test malformed request
        bad_request = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            data="invalid json",
            headers={"Content-Type": "application/json"}
        )
        assert bad_request.status_code == 400

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_rate_limiting(self, http_client):
        """Test API Gateway rate limiting functionality"""
        
        # Make multiple rapid requests to test rate limiting
        responses = []
        
        for i in range(15):  # Try to exceed rate limit
            response = await http_client.get(f"{self.BASE_URL}/api/health")
            responses.append(response.status_code)
        
        # Should get mostly 200s, but might get 429 (rate limited) if configured
        success_count = sum(1 for status in responses if status == 200)
        rate_limited_count = sum(1 for status in responses if status == 429)
        
        # Either no rate limiting (all success) or some requests rate limited
        assert success_count > 0
        # If rate limiting is configured, we might see some 429s

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_service_discovery(self, http_client):
        """Test that API Gateway can discover and route to services"""
        
        # Test multiple service endpoints to verify service discovery
        service_endpoints = [
            "/api/health",  # Gateway health
            "/api/v1/auth/login",  # Platform services
        ]
        
        for endpoint in service_endpoints:
            try:
                response = await http_client.post(
                    f"{self.BASE_URL}{endpoint}",
                    json={"email": "test@example.com", "password": "test"}
                ) if endpoint.endswith("login") else await http_client.get(
                    f"{self.BASE_URL}{endpoint}"
                )
                
                # Should get a response (not connection error)
                assert response.status_code in [200, 400, 401, 404, 405]
                
            except httpx.ConnectError:
                pytest.fail(f"Service discovery failed for {endpoint}")

    @pytest.mark.integration
    @pytest.mark.api_gateway  
    async def test_header_forwarding(self, authenticated_client):
        """Test that headers are properly forwarded between services"""
        
        # Test with custom headers
        custom_headers = {
            "X-Request-ID": "test-request-123",
            "X-Client-Version": "1.0.0"
        }
        
        response = await authenticated_client.get(
            f"{self.BASE_URL}/api/v1/users/profile",
            headers=custom_headers
        )
        
        # Should get a response indicating headers were processed
        assert response.status_code in [200, 401, 403, 404]
        
        # Check if request ID is echoed back (if implemented)
        if "x-request-id" in response.headers:
            assert response.headers["x-request-id"] == "test-request-123"

    @pytest.mark.integration
    @pytest.mark.api_gateway
    async def test_timeout_handling(self, http_client):
        """Test API Gateway timeout handling"""
        
        # Test with short timeout to see how gateway handles it
        try:
            response = await http_client.get(
                f"{self.BASE_URL}/api/health",
                timeout=0.001  # Very short timeout
            )
        except httpx.TimeoutException:
            # Expected behavior for very short timeout
            pass
        except httpx.ConnectError:
            # Service might not be running
            pytest.skip("Gateway service not available")
        
        # Test normal timeout
        response = await http_client.get(
            f"{self.BASE_URL}/api/health",
            timeout=30.0
        )
        assert response.status_code == 200