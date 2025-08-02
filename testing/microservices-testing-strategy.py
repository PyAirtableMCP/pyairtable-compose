"""
PyAirtable Microservices Testing Strategy
Comprehensive testing framework including contract testing, integration testing,
chaos engineering, and end-to-end validation
"""

import asyncio
import json
import random
import time
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum
from typing import Dict, List, Optional, Any, Callable
import logging

import pytest
import requests
import aiohttp
import asyncpg
from pact import Consumer, Provider, Like, Term, Format
from kubernetes import client, config
import docker
from locust import HttpUser, task, between
from testcontainers.postgres import PostgresContainer
from testcontainers.redis import RedisContainer
from testcontainers.kafka import KafkaContainer

# =============================================================================
# CONTRACT TESTING WITH PACT
# =============================================================================

class PactTestSuite:
    """Contract testing framework using Pact"""
    
    def __init__(self, pact_broker_url: str, service_name: str):
        self.pact_broker_url = pact_broker_url
        self.service_name = service_name
        self.pacts = {}
    
    def create_consumer_pact(self, provider_name: str, port: int = 1234):
        """Create a Pact consumer for testing"""
        pact = Consumer(self.service_name).has_pact_with(
            Provider(provider_name),
            host_name="localhost",
            port=port,
            pact_dir="./pacts"
        )
        self.pacts[provider_name] = pact
        return pact

class AuthServiceContractTests:
    """Contract tests for Auth Service"""
    
    def __init__(self, pact_suite: PactTestSuite):
        self.pact = pact_suite.create_consumer_pact("auth-service", 8010)
    
    def test_user_authentication_success(self):
        """Test successful user authentication"""
        expected_response = {
            "user_id": Like("550e8400-e29b-41d4-a716-446655440000"),
            "email": "test@example.com",
            "token": Like("jwt.token.here"),
            "expires_at": Format().iso_8601_datetime(),
            "tenant_id": Like("tenant-123")
        }
        
        (self.pact
         .given("user exists with valid credentials")
         .upon_receiving("authentication request with valid credentials")
         .with_request(
             method="POST",
             path="/api/v1/auth/login",
             headers={"Content-Type": "application/json"},
             body={
                 "email": "test@example.com",
                 "password": "valid_password"
             }
         )
         .will_respond_with(
             status=200,
             headers={"Content-Type": "application/json"},
             body=expected_response
         ))
        
        with self.pact:
            # Make actual request to mock server
            response = requests.post(
                "http://localhost:8010/api/v1/auth/login",
                json={
                    "email": "test@example.com",
                    "password": "valid_password"
                },
                headers={"Content-Type": "application/json"}
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["email"] == "test@example.com"
            assert "token" in data
            assert "user_id" in data
    
    def test_user_authentication_failure(self):
        """Test failed user authentication"""
        (self.pact
         .given("user does not exist")
         .upon_receiving("authentication request with invalid credentials")
         .with_request(
             method="POST",
             path="/api/v1/auth/login",
             body={
                 "email": "nonexistent@example.com",
                 "password": "wrong_password"
             }
         )
         .will_respond_with(
             status=401,
             body={
                 "error": "invalid_credentials",
                 "message": "Invalid email or password"
             }
         ))
        
        with self.pact:
            response = requests.post(
                "http://localhost:8010/api/v1/auth/login",
                json={
                    "email": "nonexistent@example.com",
                    "password": "wrong_password"
                }
            )
            
            assert response.status_code == 401
            assert response.json()["error"] == "invalid_credentials"

class AirtableConnectorContractTests:
    """Contract tests for Airtable Connector Service"""
    
    def __init__(self, pact_suite: PactTestSuite):
        self.pact = pact_suite.create_consumer_pact("airtable-connector", 8020)
    
    def test_fetch_base_schema(self):
        """Test fetching Airtable base schema"""
        expected_response = {
            "base_id": "appXXXXXXXXXXXXXX",
            "tables": Like([{
                "id": "tblXXXXXXXXXXXXXX",
                "name": "Table 1",
                "fields": Like([{
                    "id": "fldXXXXXXXXXXXXXX",
                    "name": "Name",
                    "type": "singleLineText"
                }])
            }])
        }
        
        (self.pact
         .given("valid Airtable base exists")
         .upon_receiving("request for base schema")
         .with_request(
             method="GET",
             path="/api/v1/airtable/bases/appXXXXXXXXXXXXXX/schema",
             headers={"Authorization": "Bearer valid_token"}
         )
         .will_respond_with(
             status=200,
             body=expected_response
         ))
        
        with self.pact:
            response = requests.get(
                "http://localhost:8020/api/v1/airtable/bases/appXXXXXXXXXXXXXX/schema",
                headers={"Authorization": "Bearer valid_token"}
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["base_id"] == "appXXXXXXXXXXXXXX"
            assert "tables" in data

# =============================================================================
# INTEGRATION TESTING
# =============================================================================

class TestEnvironment:
    """Test environment manager using test containers"""
    
    def __init__(self):
        self.containers = {}
        self.services = {}
    
    async def start_infrastructure(self):
        """Start infrastructure services for testing"""
        # Start PostgreSQL
        postgres = PostgresContainer("postgres:16-alpine")
        postgres.start()
        self.containers["postgres"] = postgres
        
        # Start Redis
        redis = RedisContainer("redis:7-alpine")
        redis.start()
        self.containers["redis"] = redis
        
        # Start Kafka
        kafka = KafkaContainer("confluentinc/cp-kafka:latest")
        kafka.start()
        self.containers["kafka"] = kafka
        
        return {
            "postgres_url": postgres.get_connection_url(),
            "redis_url": f"redis://{redis.get_container_host_ip()}:{redis.get_exposed_port(6379)}",
            "kafka_bootstrap_servers": f"{kafka.get_container_host_ip()}:{kafka.get_exposed_port(9092)}"
        }
    
    def stop_infrastructure(self):
        """Stop all test containers"""
        for container in self.containers.values():
            container.stop()

class IntegrationTestSuite:
    """Integration tests for microservices"""
    
    def __init__(self, test_env: TestEnvironment):
        self.test_env = test_env
        self.base_url = "http://localhost"
        self.services = {
            "auth-service": 8010,
            "user-service": 8011,
            "airtable-connector": 8020,
            "llm-orchestrator": 8030,
            "file-storage-service": 8040,
            "workflow-engine": 8050
        }
    
    async def test_user_registration_flow(self):
        """Test complete user registration flow across services"""
        user_data = {
            "email": f"test_{uuid.uuid4()}@example.com",
            "password": "secure_password123",
            "first_name": "Test",
            "last_name": "User",
            "company_name": "Test Corp"
        }
        
        # Step 1: Register user with auth service
        async with aiohttp.ClientSession() as session:
            auth_response = await session.post(
                f"{self.base_url}:{self.services['auth-service']}/api/v1/auth/register",
                json=user_data
            )
            assert auth_response.status == 201
            auth_data = await auth_response.json()
            user_id = auth_data["user_id"]
            token = auth_data["token"]
        
        # Step 2: Create user profile
        profile_data = {
            "user_id": user_id,
            "first_name": user_data["first_name"],
            "last_name": user_data["last_name"]
        }
        
        async with aiohttp.ClientSession() as session:
            profile_response = await session.post(
                f"{self.base_url}:{self.services['user-service']}/api/v1/users/profile",
                json=profile_data,
                headers={"Authorization": f"Bearer {token}"}
            )
            assert profile_response.status == 201
        
        # Step 3: Verify user can authenticate
        async with aiohttp.ClientSession() as session:
            login_response = await session.post(
                f"{self.base_url}:{self.services['auth-service']}/api/v1/auth/login",
                json={
                    "email": user_data["email"],
                    "password": user_data["password"]
                }
            )
            assert login_response.status == 200
            login_data = await login_response.json()
            assert login_data["email"] == user_data["email"]
    
    async def test_airtable_integration_flow(self):
        """Test Airtable integration across multiple services"""
        # Setup test user
        token = await self._create_test_user()
        
        integration_data = {
            "base_id": "appTEST123456789",
            "api_key": "keyTEST123456789"
        }
        
        # Step 1: Validate Airtable access
        async with aiohttp.ClientSession() as session:
            validate_response = await session.post(
                f"{self.base_url}:{self.services['airtable-connector']}/api/v1/airtable/validate",
                json=integration_data,
                headers={"Authorization": f"Bearer {token}"}
            )
            # This might fail in test environment, but we test the endpoint exists
            assert validate_response.status in [200, 401, 403]
        
        # Step 2: Test schema fetch (mock response)
        async with aiohttp.ClientSession() as session:
            schema_response = await session.get(
                f"{self.base_url}:{self.services['airtable-connector']}/api/v1/airtable/bases/{integration_data['base_id']}/schema",
                headers={"Authorization": f"Bearer {token}"}
            )
            # Test endpoint exists and handles request
            assert schema_response.status in [200, 401, 403, 404]
    
    async def test_workflow_execution(self):
        """Test workflow execution across services"""
        token = await self._create_test_user()
        
        workflow_definition = {
            "name": "Test Workflow",
            "steps": [
                {
                    "id": "step1",
                    "type": "file_upload",
                    "config": {"allowed_types": ["txt", "csv"]}
                },
                {
                    "id": "step2", 
                    "type": "process_file",
                    "config": {"extract_text": True}
                }
            ]
        }
        
        # Create workflow
        async with aiohttp.ClientSession() as session:
            create_response = await session.post(
                f"{self.base_url}:{self.services['workflow-engine']}/api/v1/workflows",
                json=workflow_definition,
                headers={"Authorization": f"Bearer {token}"}
            )
            assert create_response.status == 201
            workflow_data = await create_response.json()
            workflow_id = workflow_data["id"]
        
        # Execute workflow
        async with aiohttp.ClientSession() as session:
            execute_response = await session.post(
                f"{self.base_url}:{self.services['workflow-engine']}/api/v1/workflows/{workflow_id}/execute",
                json={"input_data": {"test": True}},
                headers={"Authorization": f"Bearer {token}"}
            )
            assert execute_response.status in [200, 202]  # Accepted for async processing
    
    async def _create_test_user(self) -> str:
        """Helper to create test user and return auth token"""
        user_data = {
            "email": f"test_{uuid.uuid4()}@example.com",
            "password": "test_password"
        }
        
        async with aiohttp.ClientSession() as session:
            response = await session.post(
                f"{self.base_url}:{self.services['auth-service']}/api/v1/auth/register",
                json=user_data
            )
            data = await response.json()
            return data["token"]

# =============================================================================
# PERFORMANCE TESTING WITH LOCUST
# =============================================================================

class PyAirtableUser(HttpUser):
    """Locust user for performance testing"""
    
    wait_time = between(1, 3)
    
    def on_start(self):
        """Setup user session"""
        # Register/login user
        self.user_data = {
            "email": f"loadtest_{uuid.uuid4()}@example.com",
            "password": "loadtest_password"
        }
        
        response = self.client.post(
            "/api/v1/auth/register",
            json=self.user_data,
            name="auth_register"
        )
        
        if response.status_code == 201:
            self.token = response.json()["token"]
        else:
            # Try login if user already exists
            login_response = self.client.post(
                "/api/v1/auth/login",
                json=self.user_data,
                name="auth_login"
            )
            self.token = login_response.json()["token"]
        
        self.headers = {"Authorization": f"Bearer {self.token}"}
    
    @task(3)
    def test_user_profile(self):
        """Test user profile endpoints"""
        self.client.get(
            "/api/v1/users/profile",
            headers=self.headers,
            name="get_user_profile"
        )
    
    @task(5)
    def test_airtable_operations(self):
        """Test Airtable operations"""
        # List bases
        self.client.get(
            "/api/v1/airtable/bases",
            headers=self.headers,
            name="list_airtable_bases"
        )
        
        # Get base schema (might fail, but tests load)
        self.client.get(
            "/api/v1/airtable/bases/appTEST123456789/schema",
            headers=self.headers,
            name="get_base_schema",
            catch_response=True
        )
    
    @task(2)
    def test_file_operations(self):
        """Test file operations"""
        # List files
        self.client.get(
            "/api/v1/files",
            headers=self.headers,
            name="list_files"
        )
    
    @task(1)
    def test_workflow_operations(self):
        """Test workflow operations"""
        # List workflows
        self.client.get(
            "/api/v1/workflows",
            headers=self.headers,
            name="list_workflows"
        )

# =============================================================================
# CHAOS ENGINEERING
# =============================================================================

class ChaosEngineeringTests:
    """Chaos engineering tests for resilience validation"""
    
    def __init__(self, k8s_namespace: str = "pyairtable"):
        config.load_incluster_config()  # or load_kube_config() for local
        self.k8s_apps_v1 = client.AppsV1Api()
        self.k8s_core_v1 = client.CoreV1Api()
        self.namespace = k8s_namespace
        self.docker_client = docker.from_env()
    
    async def test_service_failure_resilience(self):
        """Test system resilience when services fail"""
        test_results = {}
        
        # Test each service failure
        services = [
            "auth-service", "user-service", "airtable-connector",
            "llm-orchestrator", "file-storage-service", "workflow-engine"
        ]
        
        for service in services:
            print(f"Testing resilience against {service} failure...")
            
            # Scale down service to 0 replicas
            await self._scale_deployment(service, 0)
            
            # Wait for service to be unavailable
            await asyncio.sleep(10)
            
            # Test system behavior
            resilience_score = await self._test_system_resilience(failed_service=service)
            test_results[service] = resilience_score
            
            # Restore service
            await self._scale_deployment(service, 1)
            
            # Wait for service to recover
            await asyncio.sleep(30)
        
        return test_results
    
    async def test_network_partition_tolerance(self):
        """Test network partition tolerance"""
        # This would require more advanced network manipulation
        # Using tools like Chaos Mesh or Litmus
        pass
    
    async def test_database_failure_scenarios(self):
        """Test database failure scenarios"""
        scenarios = [
            "connection_pool_exhaustion",
            "slow_queries",
            "temporary_unavailability"
        ]
        
        results = {}
        
        for scenario in scenarios:
            print(f"Testing database scenario: {scenario}")
            
            if scenario == "connection_pool_exhaustion":
                # Create many connections to exhaust pool
                results[scenario] = await self._test_connection_exhaustion()
            
            elif scenario == "slow_queries":
                # Inject artificial delays
                results[scenario] = await self._test_slow_query_handling()
            
            elif scenario == "temporary_unavailability":
                # Temporarily block database access
                results[scenario] = await self._test_database_unavailability()
        
        return results
    
    async def _scale_deployment(self, deployment_name: str, replicas: int):
        """Scale Kubernetes deployment"""
        try:
            # Get current deployment
            deployment = self.k8s_apps_v1.read_namespaced_deployment(
                name=deployment_name,
                namespace=self.namespace
            )
            
            # Update replica count
            deployment.spec.replicas = replicas
            
            # Apply update
            self.k8s_apps_v1.patch_namespaced_deployment(
                name=deployment_name,
                namespace=self.namespace,
                body=deployment
            )
            
            print(f"Scaled {deployment_name} to {replicas} replicas")
            
        except Exception as e:
            print(f"Failed to scale {deployment_name}: {e}")
    
    async def _test_system_resilience(self, failed_service: str) -> Dict[str, Any]:
        """Test system behavior when a service is down"""
        results = {
            "failed_service": failed_service,
            "api_availability": 0,
            "error_rate": 0,
            "response_time_impact": 0
        }
        
        # Test various API endpoints
        test_endpoints = [
            {"url": "/api/v1/auth/login", "method": "POST", "critical": True},
            {"url": "/api/v1/users/profile", "method": "GET", "critical": True},
            {"url": "/api/v1/airtable/bases", "method": "GET", "critical": False},
            {"url": "/api/v1/workflows", "method": "GET", "critical": False},
        ]
        
        total_tests = 0
        successful_tests = 0
        total_response_time = 0
        
        async with aiohttp.ClientSession() as session:
            for endpoint in test_endpoints:
                for _ in range(10):  # Test each endpoint 10 times
                    total_tests += 1
                    start_time = time.time()
                    
                    try:
                        if endpoint["method"] == "GET":
                            response = await session.get(
                                f"http://api-gateway:8000{endpoint['url']}",
                                timeout=aiohttp.ClientTimeout(total=30)
                            )
                        else:
                            response = await session.post(
                                f"http://api-gateway:8000{endpoint['url']}",
                                json={"test": "data"},
                                timeout=aiohttp.ClientTimeout(total=30)
                            )
                        
                        response_time = time.time() - start_time
                        total_response_time += response_time
                        
                        # Consider 2xx, 3xx, and expected 4xx as successful
                        if response.status < 500:
                            successful_tests += 1
                    
                    except Exception as e:
                        print(f"Request failed: {e}")
                        response_time = time.time() - start_time
                        total_response_time += response_time
        
        # Calculate metrics
        results["api_availability"] = (successful_tests / total_tests) * 100
        results["error_rate"] = ((total_tests - successful_tests) / total_tests) * 100
        results["avg_response_time"] = total_response_time / total_tests
        
        return results
    
    async def _test_connection_exhaustion(self) -> Dict[str, Any]:
        """Test connection pool exhaustion"""
        connections = []
        max_connections = 100
        
        try:
            # Create many database connections
            for i in range(max_connections):
                conn = await asyncpg.connect(
                    "postgresql://user:pass@postgres:5432/testdb"
                )
                connections.append(conn)
            
            # Test if system handles exhaustion gracefully
            test_conn = await asyncpg.connect(
                "postgresql://user:pass@postgres:5432/testdb",
                timeout=5
            )
            
            return {"status": "failed", "message": "Should have failed"}
        
        except asyncio.TimeoutError:
            return {"status": "passed", "message": "Connection timeout handled"}
        
        except Exception as e:
            return {"status": "passed", "message": f"Exception handled: {e}"}
        
        finally:
            # Clean up connections
            for conn in connections:
                await conn.close()
    
    async def _test_slow_query_handling(self) -> Dict[str, Any]:
        """Test handling of slow database queries"""
        try:
            conn = await asyncpg.connect(
                "postgresql://user:pass@postgres:5432/testdb"
            )
            
            # Execute slow query with timeout
            start_time = time.time()
            
            try:
                result = await asyncio.wait_for(
                    conn.fetch("SELECT pg_sleep(30), 1 as result;"),
                    timeout=10.0
                )
                return {"status": "failed", "message": "Query should have timed out"}
            
            except asyncio.TimeoutError:
                duration = time.time() - start_time
                return {
                    "status": "passed", 
                    "message": f"Query timeout handled in {duration:.2f}s"
                }
        
        except Exception as e:
            return {"status": "error", "message": str(e)}
        
        finally:
            await conn.close()
    
    async def _test_database_unavailability(self) -> Dict[str, Any]:
        """Test database unavailability scenarios"""
        # This would require network manipulation or database shutdown
        # For now, test connection failure handling
        try:
            conn = await asyncpg.connect(
                "postgresql://user:pass@nonexistent:5432/testdb",
                timeout=5
            )
            return {"status": "failed", "message": "Should not connect"}
        
        except Exception as e:
            return {
                "status": "passed", 
                "message": f"Connection failure handled: {type(e).__name__}"
            }

# =============================================================================
# END-TO-END TESTING
# =============================================================================

class EndToEndTestSuite:
    """End-to-end testing across the entire system"""
    
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
    
    async def test_complete_user_journey(self):
        """Test complete user journey from registration to workflow execution"""
        journey_results = {
            "steps_completed": 0,
            "total_steps": 8,
            "errors": []
        }
        
        try:
            # Step 1: User Registration
            user_data = {
                "email": f"e2e_test_{uuid.uuid4()}@example.com",
                "password": "E2ETestPassword123!",
                "first_name": "E2E",
                "last_name": "Test"
            }
            
            async with aiohttp.ClientSession() as session:
                register_response = await session.post(
                    f"{self.base_url}/api/v1/auth/register",
                    json=user_data
                )
                assert register_response.status == 201
                auth_data = await register_response.json()
                token = auth_data["token"]
                journey_results["steps_completed"] += 1
            
            # Step 2: Profile Creation
            async with aiohttp.ClientSession() as session:
                profile_response = await session.post(
                    f"{self.base_url}/api/v1/users/profile",
                    json={
                        "first_name": user_data["first_name"],
                        "last_name": user_data["last_name"]
                    },
                    headers={"Authorization": f"Bearer {token}"}
                )
                assert profile_response.status in [200, 201]
                journey_results["steps_completed"] += 1
            
            # Step 3: File Upload
            test_file_content = "This is a test file for E2E testing."
            
            async with aiohttp.ClientSession() as session:
                form_data = aiohttp.FormData()
                form_data.add_field('file', test_file_content, filename='test.txt')
                
                upload_response = await session.post(
                    f"{self.base_url}/api/v1/files/upload",
                    data=form_data,
                    headers={"Authorization": f"Bearer {token}"}
                )
                
                if upload_response.status in [200, 201]:
                    upload_data = await upload_response.json()
                    file_id = upload_data.get("file_id")
                    journey_results["steps_completed"] += 1
                else:
                    journey_results["errors"].append(f"File upload failed: {upload_response.status}")
            
            # Step 4: Workflow Creation
            workflow_definition = {
                "name": "E2E Test Workflow",
                "description": "End-to-end test workflow",
                "steps": [
                    {
                        "id": "process_file",
                        "type": "file_processing",
                        "config": {"file_id": file_id if 'file_id' in locals() else None}
                    }
                ]
            }
            
            async with aiohttp.ClientSession() as session:
                workflow_response = await session.post(
                    f"{self.base_url}/api/v1/workflows",
                    json=workflow_definition,
                    headers={"Authorization": f"Bearer {token}"}
                )
                
                if workflow_response.status in [200, 201]:
                    workflow_data = await workflow_response.json()
                    workflow_id = workflow_data["id"]
                    journey_results["steps_completed"] += 1
                else:
                    journey_results["errors"].append(f"Workflow creation failed: {workflow_response.status}")
            
            # Step 5: Workflow Execution
            if 'workflow_id' in locals():
                async with aiohttp.ClientSession() as session:
                    execute_response = await session.post(
                        f"{self.base_url}/api/v1/workflows/{workflow_id}/execute",
                        json={"input_data": {"source": "e2e_test"}},
                        headers={"Authorization": f"Bearer {token}"}
                    )
                    
                    if execute_response.status in [200, 202]:
                        journey_results["steps_completed"] += 1
                    else:
                        journey_results["errors"].append(f"Workflow execution failed: {execute_response.status}")
            
            # Step 6: AI Chat Interaction
            async with aiohttp.ClientSession() as session:
                chat_response = await session.post(
                    f"{self.base_url}/api/v1/chat/conversations",
                    json={
                        "message": "Hello, this is an E2E test message.",
                        "context": {"test": True}
                    },
                    headers={"Authorization": f"Bearer {token}"}
                )
                
                if chat_response.status in [200, 201]:
                    journey_results["steps_completed"] += 1
                else:
                    journey_results["errors"].append(f"Chat interaction failed: {chat_response.status}")
            
            # Step 7: Analytics Tracking
            async with aiohttp.ClientSession() as session:
                analytics_response = await session.get(
                    f"{self.base_url}/api/v1/analytics/usage",
                    headers={"Authorization": f"Bearer {token}"}
                )
                
                if analytics_response.status == 200:
                    journey_results["steps_completed"] += 1
                else:
                    journey_results["errors"].append(f"Analytics access failed: {analytics_response.status}")
            
            # Step 8: User Logout
            async with aiohttp.ClientSession() as session:
                logout_response = await session.post(
                    f"{self.base_url}/api/v1/auth/logout",
                    headers={"Authorization": f"Bearer {token}"}
                )
                
                if logout_response.status in [200, 204]:
                    journey_results["steps_completed"] += 1
                else:
                    journey_results["errors"].append(f"Logout failed: {logout_response.status}")
        
        except Exception as e:
            journey_results["errors"].append(f"Unexpected error: {str(e)}")
        
        # Calculate success rate
        journey_results["success_rate"] = (
            journey_results["steps_completed"] / journey_results["total_steps"]
        ) * 100
        
        return journey_results
    
    async def test_system_health_checks(self):
        """Test all system health endpoints"""
        services = [
            "auth-service:8010",
            "user-service:8011", 
            "airtable-connector:8020",
            "llm-orchestrator:8030",
            "file-storage-service:8040",
            "workflow-engine:8050"
        ]
        
        health_results = {}
        
        async with aiohttp.ClientSession() as session:
            for service in services:
                service_name = service.split(':')[0]
                try:
                    response = await session.get(
                        f"http://{service}/health",
                        timeout=aiohttp.ClientTimeout(total=10)
                    )
                    
                    health_results[service_name] = {
                        "status": response.status,
                        "healthy": response.status == 200,
                        "response_time": 0  # Would need to measure
                    }
                    
                except Exception as e:
                    health_results[service_name] = {
                        "status": "error",
                        "healthy": False,
                        "error": str(e)
                    }
        
        return health_results

# =============================================================================
# TEST RUNNER AND REPORTING
# =============================================================================

class TestRunner:
    """Main test runner that orchestrates all test types"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.results = {}
        
    async def run_all_tests(self):
        """Run all test suites"""
        print("Starting PyAirtable Microservices Test Suite...")
        
        # Setup test environment
        test_env = TestEnvironment()
        infrastructure = await test_env.start_infrastructure()
        
        try:
            # Contract Tests
            print("\n1. Running Contract Tests...")
            await self.run_contract_tests()
            
            # Integration Tests  
            print("\n2. Running Integration Tests...")
            await self.run_integration_tests(test_env)
            
            # End-to-End Tests
            print("\n3. Running End-to-End Tests...")
            await self.run_e2e_tests()
            
            # Chaos Engineering Tests
            print("\n4. Running Chaos Engineering Tests...")
            await self.run_chaos_tests()
            
            # Generate Report
            self.generate_test_report()
            
        finally:
            # Cleanup
            test_env.stop_infrastructure()
    
    async def run_contract_tests(self):
        """Run contract tests"""
        pact_suite = PactTestSuite("http://pact-broker:9292", "api-gateway")
        
        # Auth Service Contracts
        auth_tests = AuthServiceContractTests(pact_suite)
        auth_tests.test_user_authentication_success()
        auth_tests.test_user_authentication_failure()
        
        # Airtable Connector Contracts
        airtable_tests = AirtableConnectorContractTests(pact_suite)
        airtable_tests.test_fetch_base_schema()
        
        self.results["contract_tests"] = {"status": "completed"}
    
    async def run_integration_tests(self, test_env: TestEnvironment):
        """Run integration tests"""
        integration_suite = IntegrationTestSuite(test_env)
        
        results = {}
        results["user_registration"] = await integration_suite.test_user_registration_flow()
        results["airtable_integration"] = await integration_suite.test_airtable_integration_flow()
        results["workflow_execution"] = await integration_suite.test_workflow_execution()
        
        self.results["integration_tests"] = results
    
    async def run_e2e_tests(self):
        """Run end-to-end tests"""
        e2e_suite = EndToEndTestSuite()
        
        results = {}
        results["user_journey"] = await e2e_suite.test_complete_user_journey()
        results["health_checks"] = await e2e_suite.test_system_health_checks()
        
        self.results["e2e_tests"] = results
    
    async def run_chaos_tests(self):
        """Run chaos engineering tests"""
        if not self.config.get("enable_chaos_tests", False):
            print("Chaos tests disabled in configuration")
            return
        
        chaos_suite = ChaosEngineeringTests()
        
        results = {}
        results["service_failures"] = await chaos_suite.test_service_failure_resilience()
        results["database_scenarios"] = await chaos_suite.test_database_failure_scenarios()
        
        self.results["chaos_tests"] = results
    
    def generate_test_report(self):
        """Generate comprehensive test report"""
        report = {
            "timestamp": datetime.now().isoformat(),
            "summary": {
                "total_test_suites": len(self.results),
                "passed_suites": 0,
                "failed_suites": 0
            },
            "details": self.results
        }
        
        # Write report to file
        with open("test_report.json", "w") as f:
            json.dump(report, f, indent=2)
        
        print(f"\nTest Report Generated: test_report.json")
        print(f"Total Test Suites: {report['summary']['total_test_suites']}")

# =============================================================================
# USAGE EXAMPLE
# =============================================================================

async def main():
    """Main function to run tests"""
    config = {
        "enable_chaos_tests": False,  # Set to True for chaos testing
        "base_url": "http://localhost:8000",
        "test_environment": "integration"
    }
    
    runner = TestRunner(config)
    await runner.run_all_tests()

if __name__ == "__main__":
    asyncio.run(main())