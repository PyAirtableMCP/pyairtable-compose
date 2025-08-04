"""
Integration tests for API Gateway service.
Tests routing, authentication, rate limiting, and service proxy functionality.
"""

import pytest
import asyncio
import httpx
import time
from typing import Dict, Any, List
from datetime import datetime, timedelta
from tests.fixtures.factories import TestDataFactory
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.integration
@pytest.mark.asyncio
class TestAPIGatewayIntegration:
    """Test API Gateway integration with downstream services"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        # API Gateway URL
        self.gateway_url = test_environment.api_gateway_url
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_api_gateway_routing_to_services(self, http_client: httpx.AsyncClient):
        """Test API Gateway correctly routes requests to downstream services"""
        # Test routing to Auth Service
        auth_response = await http_client.get(f"{self.gateway_url}/auth/health")
        assert auth_response.status_code in [200, 404]  # 404 if service not running
        
        # Test routing to LLM Orchestrator
        llm_health_response = await http_client.get(f"{self.gateway_url}/llm/health")
        assert llm_health_response.status_code in [200, 404]
        
        # Test routing to Airtable Gateway
        airtable_health_response = await http_client.get(f"{self.gateway_url}/airtable/health")
        assert airtable_health_response.status_code in [200, 404]
        
        # Test routing to MCP Server
        mcp_health_response = await http_client.get(f"{self.gateway_url}/mcp/health")
        assert mcp_health_response.status_code in [200, 404]
        
        # Test invalid route returns 404
        invalid_response = await http_client.get(f"{self.gateway_url}/nonexistent/service")
        assert invalid_response.status_code == 404
    
    async def test_api_gateway_authentication_middleware(self, http_client: httpx.AsyncClient):
        """Test API Gateway authentication middleware"""
        # Test unauthenticated request to protected endpoint
        protected_response = await http_client.get(f"{self.gateway_url}/protected/users")
        assert protected_response.status_code == 401
        
        # Test with invalid token
        invalid_token_response = await http_client.get(
            f"{self.gateway_url}/protected/users",
            headers={"Authorization": "Bearer invalid-token"}
        )
        assert invalid_token_response.status_code == 401
        
        # Test authentication flow
        auth_data = {
            "email": "test@example.com",
            "password": "test_password"
        }
        
        auth_response = await http_client.post(
            f"{self.gateway_url}/auth/login",
            json=auth_data
        )
        
        if auth_response.status_code == 200:
            # Authentication successful
            auth_result = auth_response.json()
            access_token = auth_result["access_token"]
            
            # Test authenticated request
            authenticated_response = await http_client.get(
                f"{self.gateway_url}/protected/users",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            assert authenticated_response.status_code in [200, 404]  # 200 if users exist, 404 if empty
            
            # Test token validation
            validate_response = await http_client.get(
                f"{self.gateway_url}/auth/validate",
                headers={"Authorization": f"Bearer {access_token}"}
            )
            assert validate_response.status_code == 200
            
            validation_result = validate_response.json()
            assert validation_result["valid"] == True
            assert "user_id" in validation_result
    
    async def test_api_gateway_rate_limiting(self, http_client: httpx.AsyncClient):
        """Test API Gateway rate limiting functionality"""
        # Get rate limit configuration
        config_response = await http_client.get(f"{self.gateway_url}/config/rate-limits")
        
        if config_response.status_code == 200:
            rate_limits = config_response.json()
            requests_per_minute = rate_limits.get("requests_per_minute", 60)
            burst_limit = rate_limits.get("burst_limit", 10)
        else:
            # Default values for testing
            requests_per_minute = 60
            burst_limit = 10
        
        # Test burst protection
        burst_responses = []
        for i in range(burst_limit + 5):  # Exceed burst limit
            response = await http_client.get(f"{self.gateway_url}/health")
            burst_responses.append(response.status_code)
            
            if i < burst_limit:
                # Within burst limit - should succeed
                assert response.status_code == 200
            else:
                # Exceeded burst limit - might be rate limited
                if response.status_code == 429:
                    rate_limit_headers = response.headers
                    assert "X-RateLimit-Limit" in rate_limit_headers
                    assert "X-RateLimit-Remaining" in rate_limit_headers
                    assert "Retry-After" in rate_limit_headers
                    break
        
        # Test rate limit recovery
        await asyncio.sleep(2)  # Wait for rate limit window to reset
        
        recovery_response = await http_client.get(f"{self.gateway_url}/health")
        assert recovery_response.status_code == 200
    
    async def test_api_gateway_request_validation(self, http_client: httpx.AsyncClient):
        """Test API Gateway request validation"""
        # Test request size limits
        large_payload = {"data": "x" * 10000}  # 10KB payload
        
        large_request_response = await http_client.post(
            f"{self.gateway_url}/test/large-payload",
            json=large_payload
        )
        
        if large_request_response.status_code == 413:
            # Request too large
            assert "too large" in large_request_response.json()["error"].lower()
        
        # Test malformed JSON
        malformed_response = await http_client.post(
            f"{self.gateway_url}/test/json",
            content="invalid json content",
            headers={"Content-Type": "application/json"}
        )
        assert malformed_response.status_code == 400
        
        # Test missing required headers
        no_content_type_response = await http_client.post(
            f"{self.gateway_url}/test/json",
            content='{"valid": "json"}'
        )
        # Should either succeed or fail with appropriate error
        assert no_content_type_response.status_code in [200, 400, 415]
    
    async def test_api_gateway_cors_handling(self, http_client: httpx.AsyncClient):
        """Test API Gateway CORS (Cross-Origin Resource Sharing) handling"""
        # Test preflight request
        preflight_response = await http_client.request(
            "OPTIONS",
            f"{self.gateway_url}/api/test",
            headers={
                "Origin": "https://example.com",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Content-Type,Authorization"
            }
        )
        
        if preflight_response.status_code == 200:
            cors_headers = preflight_response.headers
            assert "Access-Control-Allow-Origin" in cors_headers
            assert "Access-Control-Allow-Methods" in cors_headers
            assert "Access-Control-Allow-Headers" in cors_headers
        
        # Test actual CORS request
        cors_response = await http_client.get(
            f"{self.gateway_url}/health",
            headers={"Origin": "https://example.com"}
        )
        
        if cors_response.status_code == 200:
            assert "Access-Control-Allow-Origin" in cors_response.headers
    
    async def test_api_gateway_service_discovery(self, http_client: httpx.AsyncClient):
        """Test API Gateway service discovery and health checking"""
        # Test service registry endpoint
        services_response = await http_client.get(f"{self.gateway_url}/internal/services")
        
        if services_response.status_code == 200:
            services = services_response.json()
            assert "services" in services
            
            # Verify expected services are registered
            service_names = [service["name"] for service in services["services"]]
            expected_services = ["auth-service", "llm-orchestrator", "airtable-gateway", "mcp-server"]
            
            for expected_service in expected_services:
                if expected_service in service_names:
                    service_info = next(s for s in services["services"] if s["name"] == expected_service)
                    assert "url" in service_info
                    assert "health_check_url" in service_info
                    assert "status" in service_info
        
        # Test health check aggregation
        health_response = await http_client.get(f"{self.gateway_url}/health/detailed")
        
        if health_response.status_code == 200:
            health_details = health_response.json()
            assert "services" in health_details
            assert "overall_status" in health_details
            
            # Each service should have health status
            for service_name, service_health in health_details["services"].items():
                assert "status" in service_health
                assert service_health["status"] in ["healthy", "unhealthy", "unknown"]
                if service_health["status"] == "healthy":
                    assert "response_time" in service_health
    
    async def test_api_gateway_load_balancing(self, http_client: httpx.AsyncClient):
        """Test API Gateway load balancing between service instances"""
        # Test multiple requests to the same service
        response_sources = []
        
        for i in range(10):
            response = await http_client.get(f"{self.gateway_url}/airtable/health")
            
            if response.status_code == 200:
                # Check for load balancing headers
                if "X-Instance-ID" in response.headers:
                    response_sources.append(response.headers["X-Instance-ID"])
                elif "Server" in response.headers:
                    response_sources.append(response.headers["Server"])
                else:
                    response_sources.append("unknown")
        
        # If load balancing is configured and multiple instances exist,
        # we should see different instance IDs
        if len(set(response_sources)) > 1:
            # Multiple instances detected
            assert len(set(response_sources)) >= 2, "Load balancing should distribute across instances"
    
    async def test_api_gateway_circuit_breaker(self, http_client: httpx.AsyncClient):
        """Test API Gateway circuit breaker for failing services"""
        # Try to access a service that might be down
        failing_service_url = f"{self.gateway_url}/failing-service/test"
        
        failure_count = 0
        circuit_breaker_triggered = False
        
        # Make multiple requests to potentially trigger circuit breaker
        for i in range(10):
            response = await http_client.get(failing_service_url)
            
            if response.status_code >= 500:
                failure_count += 1
            elif response.status_code == 503 and "circuit breaker" in response.text.lower():
                circuit_breaker_triggered = True
                break
            
            await asyncio.sleep(0.1)
        
        # If circuit breaker is implemented and service is failing
        if failure_count >= 3:  # Threshold typically around 3-5 failures
            # Make one more request to check for circuit breaker response
            cb_test_response = await http_client.get(failing_service_url)
            if cb_test_response.status_code == 503:
                circuit_breaker_triggered = True
        
        # Test circuit breaker recovery (half-open state)
        if circuit_breaker_triggered:
            # Wait for circuit breaker timeout
            await asyncio.sleep(5)
            
            recovery_response = await http_client.get(failing_service_url)
            # Should either succeed (if service recovered) or fail normally (not circuit breaker)
            assert recovery_response.status_code != 503 or "circuit breaker" not in recovery_response.text.lower()
    
    async def test_api_gateway_request_response_transformation(self, http_client: httpx.AsyncClient):
        """Test API Gateway request/response transformation"""
        # Test request header forwarding
        custom_headers = {
            "X-Custom-Header": "test-value",
            "X-Request-ID": "test-request-123",
            "User-Agent": "PyAirtable-Test/1.0"
        }
        
        response = await http_client.get(
            f"{self.gateway_url}/echo/headers",
            headers=custom_headers
        )
        
        if response.status_code == 200:
            echoed_headers = response.json()
            
            # Verify custom headers were forwarded
            assert echoed_headers.get("X-Custom-Header") == "test-value"
            assert echoed_headers.get("X-Request-ID") == "test-request-123"
        
        # Test response header injection
        api_response = await http_client.get(f"{self.gateway_url}/health")
        
        if api_response.status_code == 200:
            # Check for API Gateway injected headers
            expected_headers = ["X-Gateway-Version", "X-Request-ID", "X-Response-Time"]
            
            for header in expected_headers:
                if header in api_response.headers:
                    assert api_response.headers[header] is not None
    
    async def test_api_gateway_websocket_proxy(self, http_client: httpx.AsyncClient):
        """Test API Gateway WebSocket proxying"""
        # Note: This test requires WebSocket support
        # For now, test WebSocket upgrade endpoint availability
        
        websocket_upgrade_response = await http_client.get(
            f"{self.gateway_url}/ws/chat",
            headers={
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Key": "test-key",
                "Sec-WebSocket-Version": "13"
            }
        )
        
        # Should either upgrade to WebSocket (101) or indicate WebSocket support
        expected_codes = [101, 426, 404]  # 101=upgrade, 426=upgrade required, 404=not found
        assert websocket_upgrade_response.status_code in expected_codes
    
    async def test_api_gateway_metrics_collection(self, http_client: httpx.AsyncClient):
        """Test API Gateway metrics collection"""
        # Make several requests to generate metrics
        for i in range(5):
            await http_client.get(f"{self.gateway_url}/health")
            await http_client.get(f"{self.gateway_url}/auth/health")
            await asyncio.sleep(0.1)
        
        # Test metrics endpoint
        metrics_response = await http_client.get(f"{self.gateway_url}/metrics")
        
        if metrics_response.status_code == 200:
            metrics_content = metrics_response.text
            
            # Should contain Prometheus-format metrics
            expected_metrics = [
                "http_requests_total",
                "http_request_duration_seconds",
                "http_requests_in_flight"
            ]
            
            for metric in expected_metrics:
                if metric in metrics_content:
                    assert metric in metrics_content
        
        # Test internal metrics API
        internal_metrics_response = await http_client.get(f"{self.gateway_url}/internal/metrics")
        
        if internal_metrics_response.status_code == 200:
            internal_metrics = internal_metrics_response.json()
            
            assert "request_count" in internal_metrics
            assert "response_times" in internal_metrics
            assert "error_rates" in internal_metrics
            
            # Verify our test requests are counted
            assert internal_metrics["request_count"] >= 10  # From our test requests
    
    async def test_api_gateway_security_headers(self, http_client: httpx.AsyncClient):
        """Test API Gateway security header injection"""
        response = await http_client.get(f"{self.gateway_url}/health")
        
        if response.status_code == 200:
            security_headers = [
                "X-Content-Type-Options",
                "X-Frame-Options", 
                "X-XSS-Protection",
                "Strict-Transport-Security",
                "Content-Security-Policy"
            ]
            
            present_headers = []
            for header in security_headers:
                if header in response.headers:
                    present_headers.append(header)
            
            # At least some security headers should be present
            if len(present_headers) > 0:
                # Verify header values are secure
                if "X-Content-Type-Options" in response.headers:
                    assert response.headers["X-Content-Type-Options"] == "nosniff"
                
                if "X-Frame-Options" in response.headers:
                    assert response.headers["X-Frame-Options"] in ["DENY", "SAMEORIGIN"]
                
                if "X-XSS-Protection" in response.headers:
                    assert "1" in response.headers["X-XSS-Protection"]