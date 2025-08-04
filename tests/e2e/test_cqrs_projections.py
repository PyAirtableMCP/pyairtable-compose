"""
End-to-end tests for CQRS (Command Query Responsibility Segregation) projections.
Tests command/query separation and event-driven projection updates.
"""

import pytest
import asyncio
import httpx
from typing import Dict, Any, List
from datetime import datetime
from tests.fixtures.factories import TestDataFactory, create_user, create_workspace
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.e2e
@pytest.mark.asyncio
class TestCQRSProjections:
    """Test CQRS projection patterns end-to-end"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        # CQRS endpoints
        self.command_url = f"{test_environment.api_gateway_url}/commands"
        self.query_url = f"{test_environment.api_gateway_url}/queries"
        self.events_url = f"{test_environment.api_gateway_url}/events"
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_user_creation_command_and_projection(self, http_client: httpx.AsyncClient):
        """Test user creation command creates proper projections"""
        # Arrange
        user_data = self.factory.create_user()
        
        create_user_command = {
            "command_type": "CreateUser",
            "data": {
                "email": user_data.email,
                "username": user_data.username,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "password": "password123"
            },
            "metadata": {
                "correlation_id": f"cmd_{user_data.id}",
                "initiated_by": "test_user"
            }
        }
        
        # Act - Send command
        command_response = await http_client.post(
            f"{self.command_url}/users",
            json=create_user_command
        )
        
        # Assert command accepted
        assert command_response.status_code == 202
        command_result = command_response.json()
        command_id = command_result["command_id"]
        user_id = command_result["aggregate_id"]
        
        # Wait for command processing and projection updates
        await asyncio.sleep(2)
        
        # Verify command was processed
        command_status_response = await http_client.get(
            f"{self.command_url}/status/{command_id}"
        )
        assert command_status_response.status_code == 200
        command_status = command_status_response.json()
        assert command_status["status"] == "COMPLETED"
        
        # Verify read model projection was created
        user_query_response = await http_client.get(
            f"{self.query_url}/users/{user_id}"
        )
        assert user_query_response.status_code == 200
        
        user_projection = user_query_response.json()
        assert user_projection["id"] == user_id
        assert user_projection["email"] == user_data.email
        assert user_projection["username"] == user_data.username
        assert user_projection["first_name"] == user_data.first_name
        assert user_projection["last_name"] == user_data.last_name
        assert "password" not in user_projection  # Sensitive data not in read model
        
        # Verify events were generated
        events_response = await http_client.get(
            f"{self.events_url}",
            params={"aggregate_id": user_id, "aggregate_type": "User"}
        )
        assert events_response.status_code == 200
        
        events = events_response.json()["events"]
        assert len(events) >= 1
        
        user_created_event = events[0]
        assert user_created_event["event_type"] == "UserCreated"
        assert user_created_event["aggregate_id"] == user_id
        assert user_created_event["data"]["email"] == user_data.email
    
    async def test_workspace_command_updates_multiple_projections(self, http_client: httpx.AsyncClient):
        """Test workspace creation updates multiple read model projections"""
        # Arrange - First create a user
        user_data = self.factory.create_user()
        user_create_response = await http_client.post(
            f"{self.command_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                }
            }
        )
        user_id = user_create_response.json()["aggregate_id"]
        
        await asyncio.sleep(1)  # Wait for user creation
        
        # Now create workspace
        workspace_data = self.factory.create_workspace(owner_id=user_id)
        
        create_workspace_command = {
            "command_type": "CreateWorkspace",
            "data": {
                "name": workspace_data.name,
                "description": workspace_data.description,
                "owner_id": user_id
            },
            "metadata": {
                "correlation_id": f"cmd_{workspace_data.id}",
                "initiated_by": user_id
            }
        }
        
        # Act - Send workspace creation command
        workspace_response = await http_client.post(
            f"{self.command_url}/workspaces",
            json=create_workspace_command
        )
        
        assert workspace_response.status_code == 202
        workspace_result = workspace_response.json()
        workspace_id = workspace_result["aggregate_id"]
        
        # Wait for projections to update
        await asyncio.sleep(3)
        
        # Verify workspace projection
        workspace_query_response = await http_client.get(
            f"{self.query_url}/workspaces/{workspace_id}"
        )
        assert workspace_query_response.status_code == 200
        
        workspace_projection = workspace_query_response.json()
        assert workspace_projection["id"] == workspace_id
        assert workspace_projection["name"] == workspace_data.name
        assert workspace_projection["owner_id"] == user_id
        
        # Verify user projection was updated with workspace info
        user_query_response = await http_client.get(
            f"{self.query_url}/users/{user_id}"
        )
        assert user_query_response.status_code == 200
        
        user_projection = user_query_response.json()
        assert "workspaces" in user_projection
        assert len(user_projection["workspaces"]) == 1
        assert user_projection["workspaces"][0]["id"] == workspace_id
        assert user_projection["workspaces"][0]["name"] == workspace_data.name
        
        # Verify workspace summary projection
        workspace_summary_response = await http_client.get(
            f"{self.query_url}/workspace-summaries/{workspace_id}"
        )
        assert workspace_summary_response.status_code == 200
        
        summary_projection = workspace_summary_response.json()
        assert summary_projection["workspace_id"] == workspace_id
        assert summary_projection["owner_name"] == f"{user_data.first_name} {user_data.last_name}"
        assert summary_projection["member_count"] == 1  # Owner is first member
    
    async def test_projection_consistency_across_services(self, http_client: httpx.AsyncClient):
        """Test projection consistency across multiple services"""
        # Arrange - Create user and workspace
        user_data = self.factory.create_user()
        
        # Create user
        user_response = await http_client.post(
            f"{self.command_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                }
            }
        )
        user_id = user_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Create workspace
        workspace_response = await http_client.post(
            f"{self.command_url}/workspaces",
            json={
                "command_type": "CreateWorkspace",
                "data": {
                    "name": "Test Workspace",
                    "description": "Test workspace for CQRS",
                    "owner_id": user_id
                }
            }
        )
        workspace_id = workspace_response.json()["aggregate_id"]
        await asyncio.sleep(2)
        
        # Act - Update user profile
        update_user_command = {
            "command_type": "UpdateUserProfile",
            "data": {
                "first_name": "Updated First",
                "last_name": "Updated Last"
            },
            "metadata": {
                "correlation_id": f"update_{user_id}",
                "initiated_by": user_id
            }
        }
        
        update_response = await http_client.put(
            f"{self.command_url}/users/{user_id}",
            json=update_user_command
        )
        assert update_response.status_code == 202
        
        # Wait for projections to update
        await asyncio.sleep(3)
        
        # Verify consistency across different projections
        
        # 1. User projection should be updated
        user_projection_response = await http_client.get(f"{self.query_url}/users/{user_id}")
        user_projection = user_projection_response.json()
        assert user_projection["first_name"] == "Updated First"
        assert user_projection["last_name"] == "Updated Last"
        
        # 2. Workspace summary should reflect updated owner name
        workspace_summary_response = await http_client.get(
            f"{self.query_url}/workspace-summaries/{workspace_id}"
        )
        workspace_summary = workspace_summary_response.json()
        assert workspace_summary["owner_name"] == "Updated First Updated Last"
        
        # 3. User activity projection should include the update
        user_activity_response = await http_client.get(
            f"{self.query_url}/user-activities/{user_id}"
        )
        user_activities = user_activity_response.json()
        
        profile_updates = [
            activity for activity in user_activities["activities"]
            if activity["type"] == "ProfileUpdated"
        ]
        assert len(profile_updates) >= 1
        
        latest_update = profile_updates[-1]
        assert latest_update["data"]["first_name"] == "Updated First"
        assert latest_update["data"]["last_name"] == "Updated Last"
    
    async def test_projection_rebuild_from_event_stream(self, http_client: httpx.AsyncClient):
        """Test projection rebuild capability from event stream"""
        # Arrange - Create user with multiple events
        user_data = self.factory.create_user()
        
        # Create user
        create_response = await http_client.post(
            f"{self.command_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                }
            }
        )
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Update user multiple times
        updates = [
            {"first_name": "First Update"},
            {"last_name": "Last Update"},
            {"email": "updated@example.com"}
        ]
        
        for i, update_data in enumerate(updates):
            await http_client.put(
                f"{self.command_url}/users/{user_id}",
                json={
                    "command_type": "UpdateUserProfile",
                    "data": update_data,
                    "metadata": {"correlation_id": f"update_{i}"}
                }
            )
            await asyncio.sleep(0.5)
        
        await asyncio.sleep(2)  # Wait for all projections to update
        
        # Act - Trigger projection rebuild
        rebuild_response = await http_client.post(
            f"{self.query_url}/projections/users/{user_id}/rebuild"
        )
        assert rebuild_response.status_code == 202
        
        rebuild_job_id = rebuild_response.json()["job_id"]
        
        # Wait for rebuild completion
        timeout = 30
        start_time = datetime.utcnow()
        
        while True:
            rebuild_status_response = await http_client.get(
                f"{self.query_url}/projections/rebuild-status/{rebuild_job_id}"
            )
            rebuild_status = rebuild_status_response.json()
            
            if rebuild_status["status"] == "COMPLETED":
                break
            elif rebuild_status["status"] == "FAILED":
                pytest.fail(f"Projection rebuild failed: {rebuild_status.get('error')}")
            elif (datetime.utcnow() - start_time).seconds > timeout:
                pytest.fail("Projection rebuild timeout")
            
            await asyncio.sleep(1)
        
        # Verify rebuilt projection matches expected final state
        rebuilt_projection_response = await http_client.get(f"{self.query_url}/users/{user_id}")
        rebuilt_projection = rebuilt_projection_response.json()
        
        assert rebuilt_projection["first_name"] == "First Update"
        assert rebuilt_projection["last_name"] == "Last Update"
        assert rebuilt_projection["email"] == "updated@example.com"
        assert rebuilt_projection["username"] == user_data.username  # Unchanged
        
        # Verify projection metadata indicates rebuild
        assert rebuilt_projection["_metadata"]["rebuilt_at"] is not None
        assert rebuilt_projection["_metadata"]["version"] >= len(updates) + 1  # Create + updates
    
    async def test_query_performance_with_projections(self, http_client: httpx.AsyncClient):
        """Test query performance benefits of CQRS projections"""
        # Arrange - Create multiple users and workspaces for performance testing
        num_users = 10
        num_workspaces_per_user = 3
        
        user_ids = []
        workspace_ids = []
        
        # Create users
        for i in range(num_users):
            user_data = self.factory.create_user(
                email=f"perfuser{i}@example.com",
                username=f"perfuser{i}"
            )
            
            user_response = await http_client.post(
                f"{self.command_url}/users",
                json={
                    "command_type": "CreateUser",
                    "data": {
                        "email": user_data.email,
                        "username": user_data.username,
                        "first_name": user_data.first_name,
                        "last_name": user_data.last_name,
                        "password": "password123"
                    }
                }
            )
            user_ids.append(user_response.json()["aggregate_id"])
        
        await asyncio.sleep(2)  # Wait for user creation
        
        # Create workspaces
        for user_id in user_ids:
            for j in range(num_workspaces_per_user):
                workspace_data = self.factory.create_workspace(owner_id=user_id)
                workspace_response = await http_client.post(
                    f"{self.command_url}/workspaces",
                    json={
                        "command_type": "CreateWorkspace",
                        "data": {
                            "name": f"{workspace_data.name}_{j}",
                            "description": workspace_data.description,
                            "owner_id": user_id
                        }
                    }
                )
                workspace_ids.append(workspace_response.json()["aggregate_id"])
        
        await asyncio.sleep(5)  # Wait for workspace creation and projections
        
        # Act & Assert - Test query performance
        
        # 1. Test user list query (should use optimized projection)
        start_time = datetime.utcnow()
        users_list_response = await http_client.get(
            f"{self.query_url}/users",
            params={"limit": 50, "include_workspaces": "true"}
        )
        users_query_time = (datetime.utcnow() - start_time).total_seconds()
        
        assert users_list_response.status_code == 200
        users_list = users_list_response.json()
        assert len(users_list["users"]) >= num_users
        
        # Verify workspace data is included (from projection, not real-time join)
        users_with_workspaces = [
            user for user in users_list["users"] 
            if len(user.get("workspaces", [])) > 0
        ]
        assert len(users_with_workspaces) >= num_users
        
        # 2. Test workspace summary query
        start_time = datetime.utcnow()
        workspaces_summary_response = await http_client.get(
            f"{self.query_url}/workspace-summaries",
            params={"limit": 100}
        )
        workspace_summary_query_time = (datetime.utcnow() - start_time).total_seconds()
        
        assert workspaces_summary_response.status_code == 200
        workspace_summaries = workspaces_summary_response.json()
        assert len(workspace_summaries["summaries"]) >= len(workspace_ids)
        
        # 3. Test user activity aggregation query
        start_time = datetime.utcnow()
        activity_stats_response = await http_client.get(
            f"{self.query_url}/activity-stats",
            params={"time_range": "24h"}
        )
        activity_query_time = (datetime.utcnow() - start_time).total_seconds()
        
        assert activity_stats_response.status_code == 200
        activity_stats = activity_stats_response.json()
        assert "total_users_created" in activity_stats
        assert "total_workspaces_created" in activity_stats
        
        # Assert reasonable query performance (projections should make queries fast)
        assert users_query_time < 2.0, f"User query too slow: {users_query_time}s"
        assert workspace_summary_query_time < 2.0, f"Workspace summary query too slow: {workspace_summary_query_time}s"
        assert activity_query_time < 1.0, f"Activity stats query too slow: {activity_query_time}s"
    
    async def test_projection_eventual_consistency(self, http_client: httpx.AsyncClient):
        """Test eventual consistency of projections across services"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create user
        user_response = await http_client.post(
            f"{self.command_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                }
            }
        )
        user_id = user_response.json()["aggregate_id"]
        
        # Act - Perform rapid updates
        rapid_updates = [
            {"first_name": f"Name_{i}"} for i in range(5)
        ]
        
        for update in rapid_updates:
            await http_client.put(
                f"{self.command_url}/users/{user_id}",
                json={
                    "command_type": "UpdateUserProfile", 
                    "data": update
                }
            )
            # Don't wait between updates - test eventual consistency
        
        # Wait for eventual consistency
        final_expected_name = "Name_4"
        max_wait_time = 10
        start_time = datetime.utcnow()
        
        while True:
            # Check different projection services
            user_projection_response = await http_client.get(f"{self.query_url}/users/{user_id}")
            user_projection = user_projection_response.json()
            
            if user_projection["first_name"] == final_expected_name:
                break
            
            if (datetime.utcnow() - start_time).seconds > max_wait_time:
                pytest.fail(f"Eventual consistency not achieved within {max_wait_time} seconds")
            
            await asyncio.sleep(0.5)
        
        # Verify all projections are eventually consistent
        user_projection_response = await http_client.get(f"{self.query_url}/users/{user_id}")
        user_projection = user_projection_response.json()
        assert user_projection["first_name"] == final_expected_name
        
        # Check events are in correct order
        events_response = await http_client.get(
            f"{self.events_url}",
            params={"aggregate_id": user_id, "aggregate_type": "User"}
        )
        events = events_response.json()["events"]
        
        # Should have UserCreated + 5 ProfileUpdated events
        profile_updated_events = [
            e for e in events if e["event_type"] == "ProfileUpdated"
        ]
        assert len(profile_updated_events) == 5
        
        # Events should be ordered by version
        versions = [event["version"] for event in events]
        assert versions == sorted(versions)