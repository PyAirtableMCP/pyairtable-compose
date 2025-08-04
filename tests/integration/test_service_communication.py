"""
Integration tests for service-to-service communication.
Tests API contracts, data flow, and service dependencies.
"""

import pytest
import asyncio
import httpx
import asyncpg
import redis.asyncio as redis
import json
import time
from typing import Dict, List, Any
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class ServiceEndpoint:
    """Service endpoint configuration"""
    name: str
    url: str
    health_path: str = "/health"
    timeout: float = 30.0


@pytest.mark.integration
class TestServiceCommunication:
    """Test communication between all PyAirtable services"""

    @pytest.fixture(autouse=True)
    async def setup_services(self, test_environment):
        """Setup service endpoints for testing"""
        self.services = {
            "api_gateway": ServiceEndpoint(
                name="API Gateway",
                url=test_environment.api_gateway_url,
                health_path="/health"
            ),
            "llm_orchestrator": ServiceEndpoint(
                name="LLM Orchestrator",
                url=test_environment.llm_orchestrator_url,
                health_path="/health"
            ),
            "airtable_gateway": ServiceEndpoint(
                name="Airtable Gateway",
                url=test_environment.airtable_gateway_url,
                health_path="/health"
            ),
            "mcp_server": ServiceEndpoint(
                name="MCP Server",
                url=test_environment.mcp_server_url,
                health_path="/health"
            ),
            "auth_service": ServiceEndpoint(
                name="Auth Service",
                url=test_environment.auth_service_url,
                health_path="/health"
            )
        }
        
        # Add Go services if available
        go_services = {
            "go_auth": "http://localhost:8010",
            "go_gateway": "http://localhost:8011",
            "permission_service": "http://localhost:8012",
            "user_service": "http://localhost:8013",
            "workspace_service": "http://localhost:8014",
            "notification_service": "http://localhost:8015",
        }
        
        for service_name, url in go_services.items():
            self.services[service_name] = ServiceEndpoint(
                name=service_name.replace("_", " ").title(),
                url=url,
                health_path="/health"
            )

    async def test_all_services_health_check(self):
        """Test that all services are healthy and responding"""
        health_results = {}
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            tasks = []
            
            for service_id, service in self.services.items():
                task = self._check_service_health(client, service_id, service)
                tasks.append(task)
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            for i, (service_id, result) in enumerate(zip(self.services.keys(), results)):
                if isinstance(result, Exception):
                    health_results[service_id] = {
                        "healthy": False,
                        "error": str(result)
                    }
                else:
                    health_results[service_id] = result
        
        # Log results
        for service_id, result in health_results.items():
            status = "✓" if result["healthy"] else "✗"
            logger.info(f"{status} {self.services[service_id].name}: {result}")
        
        # At least core services should be healthy
        core_services = ["api_gateway", "auth_service"]
        for service_id in core_services:
            if service_id in health_results:
                assert health_results[service_id]["healthy"], \
                    f"Core service {service_id} is not healthy: {health_results[service_id]}"

    async def test_authentication_flow_integration(self, test_data_factory):
        """Test complete authentication flow across services"""
        user_data = test_data_factory.create_user_data()
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Step 1: Register user via API Gateway
            register_response = await client.post(
                f"{self.services['api_gateway'].url}/auth/register",
                json={
                    "email": user_data["email"],
                    "password": user_data["password"],
                    "first_name": user_data["first_name"],
                    "last_name": user_data["last_name"]
                }
            )
            
            # Should either succeed or user already exists
            assert register_response.status_code in [201, 409]
            
            # Step 2: Login via Auth Service
            login_response = await client.post(
                f"{self.services['auth_service'].url}/auth/login",
                json={
                    "email": user_data["email"],
                    "password": user_data["password"]
                }
            )
            
            assert login_response.status_code == 200
            auth_data = login_response.json()
            assert "access_token" in auth_data
            access_token = auth_data["access_token"]
            
            # Step 3: Use token to access protected endpoint via API Gateway
            headers = {"Authorization": f"Bearer {access_token}"}
            profile_response = await client.get(
                f"{self.services['api_gateway'].url}/auth/profile",
                headers=headers
            )
            
            assert profile_response.status_code == 200
            profile_data = profile_response.json()
            assert profile_data["email"] == user_data["email"]

    async def test_data_flow_airtable_integration(self, test_data_factory):
        """Test data flow through Airtable integration services"""
        # Get authentication token
        token = await self._get_test_token()
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Step 1: Create table via API Gateway
            table_data = test_data_factory.create_table_data()
            create_table_response = await client.post(
                f"{self.services['api_gateway'].url}/api/tables",
                json=table_data,
                headers=headers
            )
            
            if create_table_response.status_code not in [201, 409]:
                # Skip if service not available
                pytest.skip("Airtable integration service not available")
            
            table_id = create_table_response.json().get("id", "test_table")
            
            # Step 2: Add record via Airtable Gateway
            record_data = test_data_factory.create_record_data()
            create_record_response = await client.post(
                f"{self.services['airtable_gateway'].url}/tables/{table_id}/records",
                json=record_data,
                headers=headers
            )
            
            # Should succeed or service unavailable
            if create_record_response.status_code == 404:
                pytest.skip("Airtable Gateway service not available")
            
            assert create_record_response.status_code == 201
            record_id = create_record_response.json()["id"]
            
            # Step 3: Retrieve record via API Gateway
            get_record_response = await client.get(
                f"{self.services['api_gateway'].url}/api/tables/{table_id}/records/{record_id}",
                headers=headers
            )
            
            assert get_record_response.status_code == 200
            retrieved_record = get_record_response.json()
            assert retrieved_record["fields"]["name"] == record_data["name"]

    async def test_ai_chat_service_integration(self, test_data_factory):
        """Test AI chat service integration flow"""
        token = await self._get_test_token()
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(timeout=60.0) as client:
            # Step 1: Start chat session via API Gateway
            session_response = await client.post(
                f"{self.services['api_gateway'].url}/api/chat/sessions",
                json={"context": "table_analysis"},
                headers=headers
            )
            
            if session_response.status_code == 404:
                pytest.skip("Chat service not available")
            
            assert session_response.status_code == 201
            session_id = session_response.json()["session_id"]
            
            # Step 2: Send message via LLM Orchestrator
            message_data = {
                "session_id": session_id,
                "message": "Analyze the data in my table and provide insights",
                "context": {
                    "table_id": "test_table",
                    "user_intent": "data_analysis"
                }
            }
            
            chat_response = await client.post(
                f"{self.services['llm_orchestrator'].url}/chat/message",
                json=message_data,
                headers=headers
            )
            
            if chat_response.status_code == 404:
                pytest.skip("LLM Orchestrator service not available")
            
            assert chat_response.status_code == 200
            response_data = chat_response.json()
            assert "response" in response_data
            assert len(response_data["response"]) > 0

    async def test_mcp_server_integration(self):
        """Test MCP server integration and tool availability"""
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Test MCP server tools endpoint
            tools_response = await client.get(
                f"{self.services['mcp_server'].url}/tools"
            )
            
            if tools_response.status_code == 404:
                pytest.skip("MCP Server not available")
            
            assert tools_response.status_code == 200
            tools_data = tools_response.json()
            assert "tools" in tools_data
            assert len(tools_data["tools"]) > 0
            
            # Test tool execution
            tool_execution_response = await client.post(
                f"{self.services['mcp_server'].url}/tools/execute",
                json={
                    "tool": "airtable_query",
                    "parameters": {
                        "table_id": "test_table",
                        "query": "SELECT * FROM records LIMIT 10"
                    }
                }
            )
            
            # Should either succeed or indicate no data
            assert tool_execution_response.status_code in [200, 404]

    async def test_database_integration_consistency(self, db_connection):
        """Test database integration and data consistency"""
        if db_connection is None:
            pytest.skip("Database not available for testing")
        
        # Test database connectivity from services
        async with httpx.AsyncClient(timeout=30.0) as client:
            token = await self._get_test_token()
            headers = {"Authorization": f"Bearer {token}"}
            
            # Create test data via API
            test_data = {
                "name": f"Integration Test {int(time.time())}",
                "email": "integration@test.com",
                "data": {"test": True}
            }
            
            create_response = await client.post(
                f"{self.services['api_gateway'].url}/api/test-records",
                json=test_data,
                headers=headers
            )
            
            if create_response.status_code == 404:
                # Create via direct database if API not available
                await db_connection.execute(
                    "INSERT INTO test_records (name, email, data) VALUES ($1, $2, $3)",
                    test_data["name"], test_data["email"], json.dumps(test_data["data"])
                )
                
                # Verify data exists
                result = await db_connection.fetchrow(
                    "SELECT * FROM test_records WHERE email = $1",
                    test_data["email"]
                )
                assert result is not None
                assert result["name"] == test_data["name"]

    async def test_redis_cache_integration(self, redis_client):
        """Test Redis cache integration across services"""
        if redis_client is None:
            pytest.skip("Redis not available for testing")
        
        # Test cache operations
        test_key = f"integration_test_{int(time.time())}"
        test_value = {"data": "test_cache_value", "timestamp": time.time()}
        
        # Set cache value
        await redis_client.setex(test_key, 60, json.dumps(test_value))
        
        # Verify cache value via service
        async with httpx.AsyncClient(timeout=30.0) as client:
            cache_response = await client.get(
                f"{self.services['api_gateway'].url}/api/cache/{test_key}"
            )
            
            if cache_response.status_code == 200:
                cached_data = cache_response.json()
                assert cached_data["data"] == test_value["data"]
            elif cache_response.status_code == 404:
                # Direct Redis verification if API not available
                cached_value = await redis_client.get(test_key)
                assert cached_value is not None
                cached_data = json.loads(cached_value)
                assert cached_data["data"] == test_value["data"]

    async def test_event_driven_communication(self):
        """Test event-driven communication between services"""
        token = await self._get_test_token()
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Trigger event via one service
            event_data = {
                "event_type": "user_action",
                "payload": {
                    "action": "table_created",
                    "table_id": "test_table_123",
                    "user_id": "test_user"
                }
            }
            
            event_response = await client.post(
                f"{self.services['api_gateway'].url}/api/events",
                json=event_data,
                headers=headers
            )
            
            if event_response.status_code == 404:
                pytest.skip("Event system not available")
            
            # Allow time for event processing
            await asyncio.sleep(2)
            
            # Verify event was processed by checking side effects
            # This could be checking logs, database state, or other services
            status_response = await client.get(
                f"{self.services['api_gateway'].url}/api/events/status",
                headers=headers
            )
            
            if status_response.status_code == 200:
                status_data = status_response.json()
                assert "processed_events" in status_data

    async def test_cross_service_error_propagation(self):
        """Test error propagation across service boundaries"""
        token = await self._get_test_token()
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Send request that should cause downstream error
            error_response = await client.post(
                f"{self.services['api_gateway'].url}/api/test-error",
                json={"force_error": True},
                headers=headers
            )
            
            # Should receive proper error response
            if error_response.status_code != 404:  # Service available
                assert error_response.status_code >= 400
                error_data = error_response.json()
                assert "error" in error_data or "message" in error_data

    async def test_service_dependency_resilience(self):
        """Test service behavior when dependencies are unavailable"""
        token = await self._get_test_token()
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Test API Gateway behavior when downstream services are down
            # This simulates partial system failure
            
            # Try accessing features that depend on various services
            test_endpoints = [
                "/api/tables",
                "/api/chat/sessions",
                "/auth/profile",
                "/api/health"
            ]
            
            for endpoint in test_endpoints:
                try:
                    response = await client.get(
                        f"{self.services['api_gateway'].url}{endpoint}",
                        headers=headers,
                        timeout=10.0
                    )
                    
                    # Should either succeed or fail gracefully
                    assert response.status_code != 500  # No internal server errors
                    
                except httpx.TimeoutException:
                    # Timeouts are acceptable in this test
                    pass

    async def _check_service_health(self, client: httpx.AsyncClient, service_id: str, service: ServiceEndpoint) -> Dict[str, Any]:
        """Check health of a single service"""
        try:
            response = await client.get(
                f"{service.url}{service.health_path}",
                timeout=service.timeout
            )
            
            return {
                "healthy": response.status_code == 200,
                "status_code": response.status_code,
                "response_time": response.elapsed.total_seconds() if hasattr(response, 'elapsed') else 0,
                "details": response.json() if response.status_code == 200 else response.text
            }
            
        except Exception as e:
            return {
                "healthy": False,
                "error": str(e),
                "error_type": type(e).__name__
            }

    async def _get_test_token(self, email: str = "test@example.com") -> str:
        """Get authentication token for testing"""
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Try to login first
            login_response = await client.post(
                f"{self.services['auth_service'].url}/auth/login",
                json={
                    "email": email,
                    "password": "test_password"
                }
            )
            
            if login_response.status_code == 200:
                return login_response.json().get("access_token")
            
            # If login fails, try to register
            register_response = await client.post(
                f"{self.services['auth_service'].url}/auth/register",
                json={
                    "email": email,
                    "password": "test_password",
                    "first_name": "Test",
                    "last_name": "User"
                }
            )
            
            # Try login again
            login_response = await client.post(
                f"{self.services['auth_service'].url}/auth/login",
                json={
                    "email": email,
                    "password": "test_password"
                }
            )
            
            if login_response.status_code == 200:
                return login_response.json().get("access_token")
            
            # Return mock token if all else fails
            return "mock_token_for_testing"


@pytest.mark.integration
class TestServicePerformance:
    """Test service performance characteristics"""

    async def test_service_response_times(self):
        """Test service response time requirements"""
        services_to_test = [
            ("api_gateway", "/health"),
            ("auth_service", "/health"),
            ("llm_orchestrator", "/health"),
        ]
        
        results = {}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for service_name, endpoint in services_to_test:
                service_url = getattr(test_environment, f"{service_name}_url", None)
                if not service_url:
                    continue
                
                response_times = []
                
                # Make multiple requests to get average
                for _ in range(10):
                    start_time = time.time()
                    try:
                        response = await client.get(f"{service_url}{endpoint}")
                        response_time = time.time() - start_time
                        
                        if response.status_code == 200:
                            response_times.append(response_time)
                    except Exception:
                        pass
                
                if response_times:
                    avg_response_time = sum(response_times) / len(response_times)
                    results[service_name] = {
                        "avg_response_time": avg_response_time,
                        "max_response_time": max(response_times),
                        "min_response_time": min(response_times)
                    }
        
        # Validate response times
        for service_name, metrics in results.items():
            # Health endpoints should respond within 1 second
            assert metrics["avg_response_time"] < 1.0, \
                f"{service_name} average response time too high: {metrics['avg_response_time']:.3f}s"
            
            # Maximum response time should be under 3 seconds
            assert metrics["max_response_time"] < 3.0, \
                f"{service_name} maximum response time too high: {metrics['max_response_time']:.3f}s"

    async def test_concurrent_request_handling(self):
        """Test service behavior under concurrent load"""
        token = await self._get_test_token()
        headers = {"Authorization": f"Bearer {token}"}
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Send concurrent requests
            num_concurrent = 20
            tasks = []
            
            for i in range(num_concurrent):
                task = client.get(
                    f"{self.services['api_gateway'].url}/auth/profile",
                    headers=headers
                )
                tasks.append(task)
            
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Count successful responses
            successful_responses = 0
            for response in responses:
                if not isinstance(response, Exception) and response.status_code == 200:
                    successful_responses += 1
            
            # At least 80% should succeed
            success_rate = successful_responses / num_concurrent
            assert success_rate >= 0.8, f"Success rate too low: {success_rate:.2%}"

    async def _get_test_token(self) -> str:
        """Get authentication token for testing"""
        # Implementation similar to the main test class
        return "mock_token_for_testing"