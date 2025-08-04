"""
End-to-end tests for SAGA workflow patterns.
Tests the complete user registration workflow with compensation logic.
"""

import pytest
import asyncio
import httpx
from typing import Dict, Any, List
from datetime import datetime, timedelta
from tests.fixtures.factories import TestDataFactory, create_user
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.e2e
@pytest.mark.asyncio
class TestSagaWorkflows:
    """Test SAGA workflow orchestration end-to-end"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        # SAGA orchestrator endpoints
        self.saga_url = f"{test_environment.api_gateway_url}/saga"
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_user_registration_saga_success(self, http_client: httpx.AsyncClient):
        """Test successful user registration SAGA workflow"""
        # Arrange
        user_data = self.factory.create_user(
            email="newuser@example.com",
            username="newuser123"
        )
        
        registration_request = {
            "email": user_data.email,
            "username": user_data.username,
            "first_name": user_data.first_name,
            "last_name": user_data.last_name,
            "password": "password123"
        }
        
        # Act - Start user registration SAGA
        response = await http_client.post(
            f"{self.saga_url}/user-registration",
            json=registration_request
        )
        
        # Assert SAGA started
        assert response.status_code == 202
        saga_data = response.json()
        saga_id = saga_data["saga_id"]
        assert saga_data["status"] == "STARTED"
        assert saga_data["saga_type"] == "UserRegistration"
        
        # Wait for SAGA completion (with timeout)
        completion_timeout = 30  # seconds
        start_time = datetime.utcnow()
        
        while True:
            # Check SAGA status
            status_response = await http_client.get(f"{self.saga_url}/status/{saga_id}")
            assert status_response.status_code == 200
            
            status_data = status_response.json()
            
            if status_data["status"] == "COMPLETED":
                break
            elif status_data["status"] == "FAILED":
                pytest.fail(f"SAGA failed: {status_data.get('error')}")
            elif (datetime.utcnow() - start_time).seconds > completion_timeout:
                pytest.fail("SAGA completion timeout")
            
            await asyncio.sleep(1)
        
        # Verify SAGA completion details
        assert status_data["status"] == "COMPLETED"
        assert len(status_data["steps"]) >= 3  # CreateUser, CreateWorkspace, SendWelcomeEmail
        
        completed_steps = [step for step in status_data["steps"] if step["status"] == "COMPLETED"]
        assert len(completed_steps) == len(status_data["steps"])
        
        # Verify user was created
        user_id = status_data["context"]["user_id"]
        user_response = await http_client.get(f"{self.test_env.auth_service_url}/users/{user_id}")
        assert user_response.status_code == 200
        
        user_details = user_response.json()
        assert user_details["email"] == user_data.email
        assert user_details["username"] == user_data.username
        
        # Verify workspace was created
        workspace_id = status_data["context"]["workspace_id"]
        workspace_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/workspaces/{workspace_id}"
        )
        assert workspace_response.status_code == 200
        
        workspace_details = workspace_response.json()
        assert workspace_details["owner_id"] == user_id
    
    async def test_user_registration_saga_compensation(self, http_client: httpx.AsyncClient):
        """Test user registration SAGA with compensation (rollback)"""
        # Arrange
        user_data = self.factory.create_user(
            email="failuser@example.com",
            username="failuser123"
        )
        
        # Simulate a scenario that will cause the workflow to fail
        # For example, duplicate email (assuming email uniqueness constraint)
        existing_user = self.factory.create_user(email=user_data.email)
        
        # Pre-create the user to cause a conflict
        await http_client.post(
            f"{self.test_env.auth_service_url}/users",
            json={
                "email": existing_user.email,
                "username": "existinguser",
                "first_name": existing_user.first_name,
                "last_name": existing_user.last_name,
                "hashed_password": existing_user.hashed_password
            }
        )
        
        registration_request = {
            "email": user_data.email,  # This will conflict
            "username": user_data.username,
            "first_name": user_data.first_name,
            "last_name": user_data.last_name,
            "password": "password123"
        }
        
        # Act - Start user registration SAGA (should fail and compensate)
        response = await http_client.post(
            f"{self.saga_url}/user-registration",
            json=registration_request
        )
        
        assert response.status_code == 202
        saga_data = response.json()
        saga_id = saga_data["saga_id"]
        
        # Wait for SAGA completion/failure
        completion_timeout = 30
        start_time = datetime.utcnow()
        
        while True:
            status_response = await http_client.get(f"{self.saga_url}/status/{saga_id}")
            status_data = status_response.json()
            
            if status_data["status"] in ["FAILED", "COMPENSATED"]:
                break
            elif (datetime.utcnow() - start_time).seconds > completion_timeout:
                pytest.fail("SAGA timeout")
            
            await asyncio.sleep(1)
        
        # Assert compensation occurred
        assert status_data["status"] in ["FAILED", "COMPENSATED"]
        
        # Verify compensation steps were executed
        compensation_steps = [
            step for step in status_data["steps"] 
            if step.get("compensation_executed", False)
        ]
        assert len(compensation_steps) > 0
        
        # Verify no partial state remains (everything rolled back)
        if "user_id" in status_data["context"]:
            user_id = status_data["context"]["user_id"]
            user_response = await http_client.get(f"{self.test_env.auth_service_url}/users/{user_id}")
            # User should not exist or be marked as deleted
            assert user_response.status_code in [404, 410]
        
        if "workspace_id" in status_data["context"]:
            workspace_id = status_data["context"]["workspace_id"]
            workspace_response = await http_client.get(
                f"{self.test_env.api_gateway_url}/workspaces/{workspace_id}"
            )
            # Workspace should not exist or be marked as deleted
            assert workspace_response.status_code in [404, 410]
    
    async def test_saga_timeout_handling(self, http_client: httpx.AsyncClient):
        """Test SAGA timeout and automatic compensation"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create a SAGA with a very short timeout
        registration_request = {
            "email": user_data.email,
            "username": user_data.username,
            "first_name": user_data.first_name,
            "last_name": user_data.last_name,
            "password": "password123",
            "saga_timeout": 5  # 5 seconds timeout
        }
        
        # Act
        response = await http_client.post(
            f"{self.saga_url}/user-registration",
            json=registration_request
        )
        
        saga_data = response.json()
        saga_id = saga_data["saga_id"]
        
        # Wait longer than timeout
        await asyncio.sleep(10)
        
        # Check SAGA status
        status_response = await http_client.get(f"{self.saga_url}/status/{saga_id}")
        status_data = status_response.json()
        
        # Assert timeout was handled
        assert status_data["status"] in ["TIMEOUT", "COMPENSATED"]
        assert status_data.get("timeout_occurred", False)
        
        # Verify cleanup occurred
        if "user_id" in status_data["context"]:
            user_id = status_data["context"]["user_id"]
            user_response = await http_client.get(f"{self.test_env.auth_service_url}/users/{user_id}")
            assert user_response.status_code in [404, 410]
    
    async def test_concurrent_saga_execution(self, http_client: httpx.AsyncClient):
        """Test concurrent SAGA execution without conflicts"""
        # Arrange
        num_concurrent_sagas = 5
        users_data = [self.factory.create_user() for _ in range(num_concurrent_sagas)]
        
        async def execute_saga(user_data):
            registration_request = {
                "email": user_data.email,
                "username": user_data.username,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "password": "password123"
            }
            
            response = await http_client.post(
                f"{self.saga_url}/user-registration",
                json=registration_request
            )
            
            saga_data = response.json()
            saga_id = saga_data["saga_id"]
            
            # Wait for completion
            while True:
                status_response = await http_client.get(f"{self.saga_url}/status/{saga_id}")
                status_data = status_response.json()
                
                if status_data["status"] in ["COMPLETED", "FAILED", "COMPENSATED"]:
                    return status_data
                
                await asyncio.sleep(0.5)
        
        # Act - Execute SAGAs concurrently
        tasks = [execute_saga(user_data) for user_data in users_data]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Assert all SAGAs completed successfully
        successful_sagas = [
            result for result in results 
            if isinstance(result, dict) and result["status"] == "COMPLETED"
        ]
        
        assert len(successful_sagas) == num_concurrent_sagas
        
        # Verify no duplicate users were created
        created_user_ids = [saga["context"]["user_id"] for saga in successful_sagas]
        assert len(created_user_ids) == len(set(created_user_ids))  # All unique
    
    async def test_saga_step_failure_and_retry(self, http_client: httpx.AsyncClient):
        """Test SAGA step failure with retry logic"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create registration request with retry configuration
        registration_request = {
            "email": user_data.email,
            "username": user_data.username,
            "first_name": user_data.first_name,
            "last_name": user_data.last_name,
            "password": "password123",
            "retry_config": {
                "max_retries": 3,
                "retry_delay": 1
            }
        }
        
        # Act
        response = await http_client.post(
            f"{self.saga_url}/user-registration",
            json=registration_request
        )
        
        saga_data = response.json()
        saga_id = saga_data["saga_id"]
        
        # Monitor SAGA execution
        retry_attempts = 0
        max_wait = 60
        start_time = datetime.utcnow()
        
        while True:
            status_response = await http_client.get(f"{self.saga_url}/status/{saga_id}")
            status_data = status_response.json()
            
            # Check for retry attempts
            for step in status_data["steps"]:
                if step.get("retry_count", 0) > retry_attempts:
                    retry_attempts = step["retry_count"]
            
            if status_data["status"] in ["COMPLETED", "FAILED", "COMPENSATED"]:
                break
            
            if (datetime.utcnow() - start_time).seconds > max_wait:
                break
            
            await asyncio.sleep(1)
        
        # Assert retry logic was executed if needed
        if status_data["status"] == "COMPLETED":
            # SAGA completed successfully (possibly after retries)
            assert True
        else:
            # If SAGA failed, verify retries were attempted
            assert retry_attempts > 0, "No retries were attempted for failed step"
    
    async def test_saga_event_sourcing_integration(self, http_client: httpx.AsyncClient):
        """Test SAGA integration with event sourcing"""
        # Arrange
        user_data = self.factory.create_user()
        
        registration_request = {
            "email": user_data.email,
            "username": user_data.username,
            "first_name": user_data.first_name,
            "last_name": user_data.last_name,
            "password": "password123"
        }
        
        # Act - Execute SAGA
        response = await http_client.post(
            f"{self.saga_url}/user-registration",
            json=registration_request
        )
        
        saga_data = response.json()
        saga_id = saga_data["saga_id"]
        
        # Wait for completion
        while True:
            status_response = await http_client.get(f"{self.saga_url}/status/{saga_id}")
            status_data = status_response.json()
            
            if status_data["status"] == "COMPLETED":
                break
            elif status_data["status"] in ["FAILED", "COMPENSATED"]:
                pytest.fail(f"SAGA failed: {status_data}")
            
            await asyncio.sleep(1)
        
        # Verify events were published
        events_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/events",
            params={"saga_id": saga_id}
        )
        assert events_response.status_code == 200
        
        events = events_response.json()["events"]
        
        # Expected events in order
        expected_event_types = [
            "SagaStarted",
            "UserCreationStarted",
            "UserCreated", 
            "WorkspaceCreationStarted",
            "WorkspaceCreated",
            "WelcomeEmailStarted",
            "WelcomeEmailSent",
            "SagaCompleted"
        ]
        
        event_types = [event["event_type"] for event in events]
        
        # Verify all expected events were published
        for expected_type in expected_event_types:
            assert expected_type in event_types, f"Missing event: {expected_type}"
        
        # Verify event ordering
        saga_started_index = event_types.index("SagaStarted")
        saga_completed_index = event_types.index("SagaCompleted")
        assert saga_started_index < saga_completed_index
        
        # Verify event data consistency
        user_created_event = next(e for e in events if e["event_type"] == "UserCreated")
        workspace_created_event = next(e for e in events if e["event_type"] == "WorkspaceCreated")
        
        assert user_created_event["aggregate_id"] == status_data["context"]["user_id"]
        assert workspace_created_event["data"]["owner_id"] == status_data["context"]["user_id"]