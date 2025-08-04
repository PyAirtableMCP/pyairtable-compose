"""
Load testing for PyAirtable services using Locust.
Tests system behavior under various load conditions.
"""

import pytest
import asyncio
import httpx
import time
import statistics
from typing import Dict, Any, List
from datetime import datetime, timedelta
from locust import HttpUser, task, between, events
from locust.env import Environment
from locust.stats import stats_printer, stats_history
from locust.log import setup_logging
from tests.fixtures.factories import TestDataFactory
from tests.conftest import skip_if_not_integration

@pytest.mark.performance
@pytest.mark.slow
class TestLoadTesting:
    """Load testing scenarios for PyAirtable"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment, performance_config):
        """Setup performance test environment"""
        self.test_env = test_environment
        self.config = performance_config
        self.factory = TestDataFactory()
        self.results = {}
        
        yield
    
    @skip_if_not_integration()
    def test_api_gateway_load_test(self, performance_config):
        """Test API Gateway under load"""
        setup_logging("INFO", None)
        
        class APIGatewayUser(HttpUser):
            wait_time = between(1, 3)
            host = self.test_env.api_gateway_url
            
            def on_start(self):
                """Setup user session"""
                # Authenticate user for protected endpoints
                auth_response = self.client.post("/auth/login", json={
                    "email": "test@example.com",
                    "password": "test_password"
                })
                
                if auth_response.status_code == 200:
                    token = auth_response.json().get("access_token")
                    self.client.headers.update({"Authorization": f"Bearer {token}"})
            
            @task(3)
            def health_check(self):
                """Most frequent - health check"""
                self.client.get("/health")
            
            @task(2) 
            def get_user_profile(self):
                """Get user profile"""
                self.client.get("/auth/profile")
            
            @task(1)
            def list_workspaces(self):
                """List user workspaces"""
                self.client.get("/workspaces")
            
            @task(1)
            def airtable_records(self):
                """Get Airtable records"""
                self.client.get("/airtable/records?table_id=tblTest&limit=10")
        
        # Setup test environment
        env = Environment(user_classes=[APIGatewayUser])
        env.create_local_runner()
        
        # Start load test
        env.runner.start(
            user_count=performance_config["load_test_users"],
            spawn_rate=5
        )
        
        # Run for specified duration
        time.sleep(performance_config["test_duration"])
        
        # Stop load test
        env.runner.quit()
        
        # Analyze results
        stats = env.runner.stats
        
        # Assert performance requirements
        total_requests = stats.total.num_requests
        assert total_requests > 0, "No requests were made"
        
        failure_rate = stats.total.num_failures / total_requests if total_requests > 0 else 1
        assert failure_rate <= performance_config["acceptable_error_rate"], \
            f"Failure rate {failure_rate:.3f} exceeds acceptable rate {performance_config['acceptable_error_rate']}"
        
        avg_response_time = stats.total.avg_response_time / 1000  # Convert to seconds
        assert avg_response_time <= performance_config["acceptable_response_time"], \
            f"Average response time {avg_response_time:.3f}s exceeds acceptable {performance_config['acceptable_response_time']}s"
        
        # Store results for reporting
        self.results["api_gateway_load"] = {
            "total_requests": total_requests,
            "failure_rate": failure_rate,
            "avg_response_time": avg_response_time,
            "max_response_time": stats.total.max_response_time / 1000,
            "requests_per_second": stats.total.current_rps,
            "percentiles": {
                "50th": stats.total.get_response_time_percentile(0.5) / 1000,
                "90th": stats.total.get_response_time_percentile(0.9) / 1000,
                "95th": stats.total.get_response_time_percentile(0.95) / 1000,
                "99th": stats.total.get_response_time_percentile(0.99) / 1000,
            }
        }
    
    @skip_if_not_integration()
    def test_database_connection_pool_load(self, performance_config):
        """Test database connection pool under concurrent load"""
        
        class DatabaseUser(HttpUser):
            wait_time = between(0.1, 0.5)
            host = self.test_env.api_gateway_url
            
            @task
            def create_and_delete_user(self):
                """Create and delete user to test database operations"""
                user_data = self.factory.create_user()
                
                # Create user
                create_response = self.client.post("/users", json={
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                })
                
                if create_response.status_code in [200, 201, 202]:
                    user_id = create_response.json().get("id")
                    
                    # Read user
                    self.client.get(f"/users/{user_id}")
                    
                    # Update user
                    self.client.put(f"/users/{user_id}", json={
                        "first_name": "Updated"
                    })
                    
                    # Delete user
                    self.client.delete(f"/users/{user_id}")
        
        env = Environment(user_classes=[DatabaseUser])
        env.create_local_runner()
        
        # Higher concurrency for database testing
        env.runner.start(
            user_count=performance_config["stress_test_users"],
            spawn_rate=10
        )
        
        # Shorter duration but higher intensity
        time.sleep(30)
        env.runner.quit()
        
        stats = env.runner.stats
        failure_rate = stats.total.num_failures / stats.total.num_requests if stats.total.num_requests > 0 else 1
        
        # Database operations should handle concurrent load well
        assert failure_rate <= 0.05, f"Database load test failure rate {failure_rate:.3f} too high"
        
        self.results["database_load"] = {
            "total_requests": stats.total.num_requests,
            "failure_rate": failure_rate,
            "avg_response_time": stats.total.avg_response_time / 1000,
            "concurrent_users": performance_config["stress_test_users"]
        }
    
    @skip_if_not_integration()
    @pytest.mark.asyncio
    async def test_llm_orchestrator_throughput(self, performance_config):
        """Test LLM Orchestrator throughput with concurrent requests"""
        
        async def make_chat_request(session: httpx.AsyncClient, session_id: str):
            """Make a single chat request"""
            start_time = time.time()
            
            try:
                response = await session.post(
                    f"{self.test_env.llm_orchestrator_url}/chat",
                    json={
                        "message": "Hello, how are you?",
                        "session_id": session_id
                    },
                    timeout=30.0
                )
                
                response_time = time.time() - start_time
                
                return {
                    "status_code": response.status_code,
                    "response_time": response_time,
                    "success": response.status_code == 200
                }
                
            except Exception as e:
                return {
                    "status_code": 0,
                    "response_time": time.time() - start_time,
                    "success": False,
                    "error": str(e)
                }
        
        # Test concurrent chat requests
        num_concurrent = 20
        num_requests_per_user = 5
        
        async with httpx.AsyncClient() as session:
            tasks = []
            
            for user_id in range(num_concurrent):
                for request_id in range(num_requests_per_user):
                    session_id = f"perf_test_{user_id}_{request_id}"
                    tasks.append(make_chat_request(session, session_id))
            
            # Execute all requests concurrently
            start_time = time.time()
            results = await asyncio.gather(*tasks, return_exceptions=True)
            total_time = time.time() - start_time
        
        # Analyze results
        successful_requests = [r for r in results if isinstance(r, dict) and r.get("success")]
        failed_requests = [r for r in results if isinstance(r, Exception) or not r.get("success")]
        
        total_requests = len(results)
        success_rate = len(successful_requests) / total_requests
        
        response_times = [r["response_time"] for r in successful_requests]
        avg_response_time = statistics.mean(response_times) if response_times else 0
        throughput = total_requests / total_time
        
        # Performance assertions
        assert success_rate >= 0.90, f"LLM throughput test success rate {success_rate:.3f} too low"
        assert avg_response_time <= 10.0, f"Average LLM response time {avg_response_time:.3f}s too high"
        assert throughput >= 2.0, f"LLM throughput {throughput:.3f} requests/sec too low"
        
        self.results["llm_throughput"] = {
            "total_requests": total_requests,
            "successful_requests": len(successful_requests),
            "success_rate": success_rate,
            "avg_response_time": avg_response_time,
            "max_response_time": max(response_times) if response_times else 0,
            "min_response_time": min(response_times) if response_times else 0,
            "throughput": throughput,
            "concurrent_users": num_concurrent
        }
    
    @skip_if_not_integration()
    def test_airtable_gateway_rate_limiting(self, performance_config):
        """Test Airtable Gateway rate limiting behavior"""
        
        class AirtableUser(HttpUser):
            wait_time = between(0.1, 0.2)  # Aggressive timing to trigger rate limits
            host = self.test_env.airtable_gateway_url
            
            @task
            def get_records(self):
                """Rapidly request Airtable records"""
                self.client.get("/records?table_id=tblTest&limit=100")
            
            @task
            def create_record(self):
                """Create Airtable record"""
                record_data = self.factory.create_airtable_record()
                self.client.post("/records", json={
                    "table_id": "tblTest",
                    "fields": record_data.fields
                })
        
        env = Environment(user_classes=[AirtableUser])
        env.create_local_runner()
        
        # Start with moderate load
        env.runner.start(user_count=10, spawn_rate=5)
        time.sleep(20)
        
        # Increase load to trigger rate limiting
        env.runner.start(user_count=50, spawn_rate=10)
        time.sleep(10)
        
        env.runner.quit()
        
        stats = env.runner.stats
        
        # Check for rate limiting responses (429 status codes)
        rate_limited_requests = 0
        for stat in stats.entries.values():
            if hasattr(stat, 'response_times') and 429 in stat.response_times:
                rate_limited_requests += stat.response_times[429]
        
        # Rate limiting should activate under high load
        assert rate_limited_requests > 0, "Rate limiting did not activate during load test"
        
        self.results["rate_limiting"] = {
            "total_requests": stats.total.num_requests,
            "rate_limited_requests": rate_limited_requests,
            "rate_limit_percentage": rate_limited_requests / stats.total.num_requests * 100
        }
    
    @skip_if_not_integration()
    @pytest.mark.asyncio
    async def test_websocket_connection_scaling(self, performance_config):
        """Test WebSocket connection scaling"""
        
        # Note: This test assumes WebSocket support in the services
        # Placeholder implementation for future WebSocket functionality
        
        num_connections = 100
        connection_results = []
        
        # Simulate WebSocket connection attempts
        async with httpx.AsyncClient() as client:
            for i in range(num_connections):
                try:
                    # Test WebSocket upgrade endpoint
                    response = await client.get(
                        f"{self.test_env.api_gateway_url}/ws/test",
                        headers={
                            "Upgrade": "websocket",
                            "Connection": "Upgrade",
                            "Sec-WebSocket-Key": f"test-key-{i}",
                            "Sec-WebSocket-Version": "13"
                        },
                        timeout=5.0
                    )
                    
                    connection_results.append({
                        "connection_id": i,
                        "status_code": response.status_code,
                        "success": response.status_code in [101, 426]  # 101=upgraded, 426=upgrade required
                    })
                    
                except Exception as e:
                    connection_results.append({
                        "connection_id": i,
                        "status_code": 0,
                        "success": False,
                        "error": str(e)
                    })
        
        successful_connections = [r for r in connection_results if r["success"]]
        success_rate = len(successful_connections) / len(connection_results)
        
        # WebSocket scaling performance
        self.results["websocket_scaling"] = {
            "total_attempts": len(connection_results),
            "successful_connections": len(successful_connections),
            "success_rate": success_rate
        }
        
        # If WebSocket is implemented, should handle many concurrent connections
        if any(r["status_code"] == 101 for r in connection_results):
            assert success_rate >= 0.95, f"WebSocket connection success rate {success_rate:.3f} too low"
    
    @skip_if_not_integration()
    def test_memory_usage_under_load(self, performance_config):
        """Test memory usage patterns under load"""
        
        class MemoryStressUser(HttpUser):
            wait_time = between(0.1, 0.5)
            host = self.test_env.api_gateway_url
            
            @task
            def large_data_operations(self):
                """Perform operations that might cause memory pressure"""
                
                # Large payload upload
                large_data = {"data": "x" * 10000}  # 10KB payload
                self.client.post("/test/large-payload", json=large_data)
                
                # Request large dataset
                self.client.get("/airtable/records?table_id=tblTest&limit=1000")
                
                # Complex LLM operation
                self.client.post("/llm/chat", json={
                    "message": "Analyze this complex data: " + "x" * 1000,
                    "session_id": f"memory_test_{time.time()}"
                })
        
        env = Environment(user_classes=[MemoryStressUser])
        env.create_local_runner()
        
        # Record initial memory usage (would need monitoring integration)
        start_time = time.time()
        
        env.runner.start(user_count=30, spawn_rate=5)
        time.sleep(60)  # Run for 1 minute
        env.runner.quit()
        
        end_time = time.time()
        
        stats = env.runner.stats
        
        # Basic memory stress test validation
        assert stats.total.num_requests > 0, "No requests completed during memory stress test"
        
        failure_rate = stats.total.num_failures / stats.total.num_requests
        assert failure_rate <= 0.10, f"Memory stress test failure rate {failure_rate:.3f} too high"
        
        self.results["memory_stress"] = {
            "duration": end_time - start_time,
            "total_requests": stats.total.num_requests,
            "failure_rate": failure_rate,
            "avg_response_time": stats.total.avg_response_time / 1000
        }
    
    def teardown_method(self):
        """Generate performance test report"""
        if self.results:
            print("\n" + "="*50)
            print("PERFORMANCE TEST RESULTS")
            print("="*50)
            
            for test_name, results in self.results.items():
                print(f"\n{test_name.upper().replace('_', ' ')}:")
                for metric, value in results.items():
                    if isinstance(value, float):
                        print(f"  {metric}: {value:.3f}")
                    elif isinstance(value, dict):
                        print(f"  {metric}:")
                        for k, v in value.items():
                            print(f"    {k}: {v:.3f}" if isinstance(v, float) else f"    {k}: {v}")
                    else:
                        print(f"  {metric}: {value}")
            
            print("\n" + "="*50)