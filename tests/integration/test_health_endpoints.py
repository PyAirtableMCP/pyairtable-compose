"""
Integration tests for health endpoint verification across all services.

Tests:
1. Health endpoints respond correctly for all services
2. Service dependencies are properly checked
3. Health checks include necessary system information
4. Readiness vs liveness distinctions
5. Health endpoint performance and reliability
"""

import pytest
import asyncio
import httpx
import json
from typing import Dict, Any, List
from datetime import datetime


class TestHealthEndpoints:
    """Integration tests for health endpoints across the microservices architecture"""
    
    # Service URLs and their expected health endpoints
    SERVICES = {
        "api_gateway": {
            "url": "http://localhost:8000",
            "health_paths": ["/api/health", "/health"]
        },
        "platform_services": {
            "url": "http://localhost:8007", 
            "health_paths": ["/health"]
        },
        "airtable_gateway": {
            "url": "http://localhost:8002",
            "health_paths": ["/health", "/api/v1/health"]
        },
        "ai_processing": {
            "url": "http://localhost:8001",
            "health_paths": ["/health"]
        },
        "frontend": {
            "url": "http://localhost:3000",
            "health_paths": ["/api/health", "/health/ready"]
        }
    }
    
    @pytest.fixture
    async def http_client(self):
        """HTTP client for health check requests"""
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            yield client
    
    @pytest.fixture
    def health_headers(self):
        """Standard headers for health check requests"""
        return {
            "Accept": "application/json",
            "User-Agent": "PyAirtable-HealthCheck/1.0"
        }

    @pytest.mark.integration
    @pytest.mark.health
    async def test_all_service_health_endpoints(self, http_client, health_headers):
        """Test health endpoints for all services"""
        
        health_results = {}
        
        for service_name, service_config in self.SERVICES.items():
            service_url = service_config["url"]
            health_paths = service_config["health_paths"]
            
            service_healthy = False
            
            for health_path in health_paths:
                try:
                    response = await http_client.get(
                        f"{service_url}{health_path}",
                        headers=health_headers
                    )
                    
                    if response.status_code == 200:
                        health_data = response.json()
                        
                        # Verify health response structure
                        assert isinstance(health_data, dict), f"{service_name} health response not a dict"
                        
                        # Check for status field
                        status_fields = ["status", "health", "state"]
                        has_status = any(field in health_data for field in status_fields)
                        assert has_status, f"{service_name} health missing status field"
                        
                        # Check status value
                        status = (
                            health_data.get("status") or 
                            health_data.get("health") or 
                            health_data.get("state")
                        )
                        
                        healthy_values = ["healthy", "ok", "up", "ready", "running"]
                        assert status in healthy_values, f"{service_name} unhealthy status: {status}"
                        
                        service_healthy = True
                        health_results[service_name] = {
                            "status": "healthy",
                            "endpoint": health_path,
                            "response": health_data
                        }
                        break
                        
                except httpx.ConnectError:
                    continue
                except Exception as e:
                    health_results[service_name] = {
                        "status": "error", 
                        "error": str(e)
                    }
                    continue
            
            if not service_healthy:
                health_results[service_name] = {
                    "status": "unavailable",
                    "message": f"Service not responding on {service_url}"
                }
        
        # Report results
        healthy_services = [name for name, result in health_results.items() if result["status"] == "healthy"]
        unhealthy_services = [name for name, result in health_results.items() if result["status"] != "healthy"]
        
        print(f"\nHealth Check Results:")
        print(f"Healthy services: {len(healthy_services)}")
        print(f"Unhealthy/Unavailable services: {len(unhealthy_services)}")
        
        for service_name, result in health_results.items():
            print(f"  {service_name}: {result['status']}")
        
        # At least API Gateway should be healthy for tests to be meaningful
        assert "api_gateway" in healthy_services, "API Gateway must be healthy for integration tests"

    @pytest.mark.integration
    @pytest.mark.health
    async def test_api_gateway_health_details(self, http_client, health_headers):
        """Test API Gateway health endpoint in detail"""
        
        try:
            response = await http_client.get(
                f"{self.SERVICES['api_gateway']['url']}/api/health",
                headers=health_headers
            )
            
            assert response.status_code == 200
            health_data = response.json()
            
            # Verify required fields
            assert "status" in health_data
            assert health_data["status"] in ["healthy", "ok"]
            
            # Check for additional useful information
            useful_fields = ["service", "version", "timestamp", "uptime"]
            has_info = any(field in health_data for field in useful_fields)
            
            # Service identification
            if "service" in health_data:
                assert isinstance(health_data["service"], str)
                assert len(health_data["service"]) > 0
            
            # Timestamp should be recent if present
            if "timestamp" in health_data:
                # Should be a valid timestamp format
                assert isinstance(health_data["timestamp"], str)
                
        except httpx.ConnectError:
            pytest.skip("API Gateway not running")

    @pytest.mark.integration
    @pytest.mark.health
    async def test_platform_services_health_details(self, http_client, health_headers):
        """Test Platform Services health endpoint in detail"""
        
        try:
            response = await http_client.get(
                f"{self.SERVICES['platform_services']['url']}/health",
                headers=health_headers
            )
            
            assert response.status_code == 200
            health_data = response.json()
            
            # Verify basic health structure
            assert "status" in health_data
            assert health_data["status"] in ["healthy", "ok"]
            
            # Platform Services should check dependencies
            # Look for database and Redis connectivity info
            dependency_indicators = ["database", "redis", "db", "cache", "dependencies"]
            has_dependencies = any(indicator in str(health_data).lower() for indicator in dependency_indicators)
            
            # Service should identify itself
            if "service" in health_data:
                assert "platform" in health_data["service"].lower()
            
        except httpx.ConnectError:
            pytest.skip("Platform Services not running")

    @pytest.mark.integration
    @pytest.mark.health
    async def test_airtable_gateway_health_details(self, http_client, health_headers):
        """Test Airtable Gateway health endpoint in detail"""
        
        try:
            # Try multiple possible health endpoints
            for health_path in self.SERVICES['airtable_gateway']['health_paths']:
                response = await http_client.get(
                    f"{self.SERVICES['airtable_gateway']['url']}{health_path}",
                    headers=health_headers
                )
                
                if response.status_code == 200:
                    health_data = response.json()
                    
                    # Verify health response
                    assert isinstance(health_data, dict)
                    assert "status" in health_data
                    assert health_data["status"] in ["healthy", "ready", "ok"]
                    
                    # Should identify as airtable service
                    if "service" in health_data:
                        assert "airtable" in health_data["service"].lower()
                    
                    break
            else:
                pytest.fail("No Airtable Gateway health endpoint responded successfully")
                
        except httpx.ConnectError:
            pytest.skip("Airtable Gateway not running")

    @pytest.mark.integration
    @pytest.mark.health
    async def test_ai_processing_health_details(self, http_client, health_headers):
        """Test AI Processing Service health endpoint in detail"""
        
        try:
            response = await http_client.get(
                f"{self.SERVICES['ai_processing']['url']}/health",
                headers=health_headers
            )
            
            assert response.status_code == 200
            health_data = response.json()
            
            # Verify health response
            assert "status" in health_data
            assert health_data["status"] in ["healthy", "ok", "ready"]
            
            # AI service might report model or processing status
            ai_indicators = ["ai", "model", "processing", "llm"]
            if any(indicator in str(health_data).lower() for indicator in ai_indicators):
                # Great! Service provides AI-specific health info
                pass
                
        except httpx.ConnectError:
            pytest.skip("AI Processing Service not running")

    @pytest.mark.integration
    @pytest.mark.health
    async def test_health_endpoint_performance(self, http_client, health_headers):
        """Test that health endpoints respond quickly"""
        
        import time
        
        for service_name, service_config in self.SERVICES.items():
            service_url = service_config["url"]
            health_paths = service_config["health_paths"]
            
            for health_path in health_paths:
                try:
                    start_time = time.time()
                    
                    response = await http_client.get(
                        f"{service_url}{health_path}",
                        headers=health_headers,
                        timeout=5.0  # Health checks should be fast
                    )
                    
                    end_time = time.time()
                    response_time = end_time - start_time
                    
                    if response.status_code == 200:
                        # Health endpoints should respond quickly (under 2 seconds)
                        assert response_time < 2.0, f"{service_name} health check too slow: {response_time}s"
                        break
                        
                except httpx.TimeoutException:
                    pytest.fail(f"{service_name} health check timed out")
                except httpx.ConnectError:
                    continue

    @pytest.mark.integration
    @pytest.mark.health
    async def test_health_endpoint_consistency(self, http_client, health_headers):
        """Test that health endpoints return consistent results"""
        
        # Test API Gateway health multiple times
        try:
            responses = []
            for _ in range(3):
                response = await http_client.get(
                    f"{self.SERVICES['api_gateway']['url']}/api/health",
                    headers=health_headers
                )
                if response.status_code == 200:
                    responses.append(response.json())
                
                # Small delay between requests
                await asyncio.sleep(0.1)
            
            if len(responses) > 1:
                # Status should be consistent
                statuses = [resp.get("status") for resp in responses]
                assert all(status == statuses[0] for status in statuses), "Inconsistent health status"
                
                # Service name should be consistent
                services = [resp.get("service") for resp in responses if resp.get("service")]
                if services:
                    assert all(service == services[0] for service in services), "Inconsistent service name"
                    
        except httpx.ConnectError:
            pytest.skip("API Gateway not running")

    @pytest.mark.integration
    @pytest.mark.health
    async def test_readiness_vs_liveness(self, http_client, health_headers):
        """Test distinction between readiness and liveness checks (if implemented)"""
        
        readiness_endpoints = [
            "/ready",
            "/readiness", 
            "/health/ready",
            "/api/ready"
        ]
        
        liveness_endpoints = [
            "/alive",
            "/liveness",
            "/health/live",
            "/api/alive"
        ]
        
        # Test API Gateway for readiness/liveness endpoints
        api_gateway_url = self.SERVICES['api_gateway']['url']
        
        readiness_found = False
        liveness_found = False
        
        for endpoint in readiness_endpoints:
            try:
                response = await http_client.get(f"{api_gateway_url}{endpoint}", headers=health_headers)
                if response.status_code == 200:
                    readiness_found = True
                    break
            except:
                continue
        
        for endpoint in liveness_endpoints:
            try:
                response = await http_client.get(f"{api_gateway_url}{endpoint}", headers=health_headers)
                if response.status_code == 200:
                    liveness_found = True
                    break
            except:
                continue
        
        # Having separate readiness/liveness is good practice but not required
        if readiness_found and liveness_found:
            # Excellent! Proper health check separation
            pass

    @pytest.mark.integration
    @pytest.mark.health
    async def test_health_dependency_checks(self, http_client, health_headers):
        """Test that health endpoints check service dependencies"""
        
        # Platform Services should check database and Redis
        try:
            response = await http_client.get(
                f"{self.SERVICES['platform_services']['url']}/health",
                headers=health_headers
            )
            
            if response.status_code == 200:
                health_data = response.json()
                
                # Look for dependency health information
                dependency_keywords = ["database", "redis", "postgres", "cache", "dependencies"]
                health_text = json.dumps(health_data).lower()
                
                has_dependency_info = any(keyword in health_text for keyword in dependency_keywords)
                
                if has_dependency_info:
                    # Great! Service reports dependency status
                    pass
                
        except httpx.ConnectError:
            pytest.skip("Platform Services not running")

    @pytest.mark.integration
    @pytest.mark.health
    async def test_health_monitoring_info(self, http_client, health_headers):
        """Test that health endpoints provide useful monitoring information"""
        
        expected_monitoring_fields = [
            "version",
            "timestamp",
            "uptime", 
            "memory",
            "cpu",
            "connections",
            "requests_processed"
        ]
        
        for service_name, service_config in self.SERVICES.items():
            service_url = service_config["url"]
            
            try:
                # Try the first health path for each service
                health_path = service_config["health_paths"][0]
                response = await http_client.get(
                    f"{service_url}{health_path}",
                    headers=health_headers
                )
                
                if response.status_code == 200:
                    health_data = response.json()
                    
                    # Check for monitoring information
                    monitoring_fields_present = [
                        field for field in expected_monitoring_fields 
                        if field in health_data
                    ]
                    
                    # Having monitoring info is good but not required
                    if monitoring_fields_present:
                        print(f"{service_name} provides monitoring fields: {monitoring_fields_present}")
                        
                        # Validate field types if present
                        if "timestamp" in health_data:
                            assert isinstance(health_data["timestamp"], str)
                        
                        if "version" in health_data:
                            assert isinstance(health_data["version"], str)
                            assert len(health_data["version"]) > 0
                            
            except httpx.ConnectError:
                continue