"""
End-to-end tests for Event Sourcing patterns.
Tests event replay, state reconstruction, and event store consistency.
"""

import pytest
import asyncio
import httpx
from typing import Dict, Any, List
from datetime import datetime, timedelta
from tests.fixtures.factories import TestDataFactory, create_event_stream
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.e2e
@pytest.mark.asyncio
class TestEventSourcing:
    """Test Event Sourcing patterns end-to-end"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        # Event sourcing endpoints
        self.events_url = f"{test_environment.api_gateway_url}/events"
        self.aggregates_url = f"{test_environment.api_gateway_url}/aggregates"
        self.replay_url = f"{test_environment.api_gateway_url}/event-replay"
        self.snapshots_url = f"{test_environment.api_gateway_url}/snapshots"
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_event_sourcing_user_lifecycle(self, http_client: httpx.AsyncClient):
        """Test complete user lifecycle with event sourcing"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Act 1 - Create user (generates UserCreated event)
        create_command = {
            "command_type": "CreateUser",
            "data": {
                "email": user_data.email,
                "username": user_data.username,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "password": "password123"
            }
        }
        
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users",
            json=create_command
        )
        assert create_response.status_code == 202
        
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Act 2 - Update user profile (generates ProfileUpdated event)
        update_command = {
            "command_type": "UpdateUserProfile",
            "data": {
                "first_name": "Updated First",
                "last_name": "Updated Last"
            }
        }
        
        update_response = await http_client.put(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
            json=update_command
        )
        assert update_response.status_code == 202
        await asyncio.sleep(1)
        
        # Act 3 - Change email (generates EmailChanged event)
        email_command = {
            "command_type": "ChangeEmail",
            "data": {
                "new_email": "newemail@example.com",
                "verification_required": True
            }
        }
        
        email_response = await http_client.put(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}/email",
            json=email_command
        )
        assert email_response.status_code == 202
        await asyncio.sleep(1)
        
        # Act 4 - Deactivate user (generates UserDeactivated event)
        deactivate_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}/deactivate"
        )
        assert deactivate_response.status_code == 202
        await asyncio.sleep(1)
        
        # Assert - Verify complete event stream
        events_response = await http_client.get(
            f"{self.events_url}",
            params={"aggregate_id": user_id, "aggregate_type": "User"}
        )
        assert events_response.status_code == 200
        
        events = events_response.json()["events"]
        assert len(events) >= 4
        
        # Verify event sequence and types
        expected_event_types = ["UserCreated", "ProfileUpdated", "EmailChanged", "UserDeactivated"]
        actual_event_types = [event["event_type"] for event in events]
        
        for expected_type in expected_event_types:
            assert expected_type in actual_event_types
        
        # Verify event ordering (version numbers should be sequential)
        versions = [event["version"] for event in events]
        assert versions == list(range(1, len(events) + 1))
        
        # Verify event data integrity
        user_created_event = next(e for e in events if e["event_type"] == "UserCreated")
        assert user_created_event["data"]["email"] == user_data.email
        assert user_created_event["data"]["username"] == user_data.username
        
        email_changed_event = next(e for e in events if e["event_type"] == "EmailChanged")
        assert email_changed_event["data"]["new_email"] == "newemail@example.com"
        assert email_changed_event["data"]["verification_required"] == True
        
        # Verify aggregate current state can be derived from events
        aggregate_response = await http_client.get(f"{self.aggregates_url}/users/{user_id}")
        assert aggregate_response.status_code == 200
        
        aggregate_state = aggregate_response.json()
        assert aggregate_state["id"] == user_id
        assert aggregate_state["email"] == "newemail@example.com"  # Latest email
        assert aggregate_state["first_name"] == "Updated First"    # Latest name
        assert aggregate_state["is_active"] == False              # Deactivated
        assert aggregate_state["version"] == len(events)
    
    async def test_event_replay_state_reconstruction(self, http_client: httpx.AsyncClient):
        """Test event replay and state reconstruction"""
        # Arrange - Create user with multiple state changes
        user_data = self.factory.create_user()
        
        # Create user
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users",
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
        await asyncio.sleep(0.5)
        
        # Perform multiple updates
        updates = [
            {"first_name": "Update1"},
            {"last_name": "Update2"},
            {"first_name": "Update3", "last_name": "Update4"},
            {"email": "final@example.com"}
        ]
        
        for i, update_data in enumerate(updates):
            await http_client.put(
                f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
                json={
                    "command_type": "UpdateUserProfile",
                    "data": update_data
                }
            )
            await asyncio.sleep(0.2)
        
        await asyncio.sleep(2)  # Wait for all events to be processed
        
        # Get final state
        final_state_response = await http_client.get(f"{self.aggregates_url}/users/{user_id}")
        final_state = final_state_response.json()
        
        # Act - Trigger event replay to reconstruct state
        replay_request = {
            "aggregate_id": user_id,
            "aggregate_type": "User",
            "from_version": 1,
            "to_version": None,  # Replay all events
            "validate_state": True
        }
        
        replay_response = await http_client.post(
            f"{self.replay_url}/reconstruct",
            json=replay_request
        )
        assert replay_response.status_code == 202
        
        replay_job_id = replay_response.json()["job_id"]
        
        # Wait for replay completion
        timeout = 30
        start_time = datetime.utcnow()
        
        while True:
            replay_status_response = await http_client.get(
                f"{self.replay_url}/status/{replay_job_id}"
            )
            replay_status = replay_status_response.json()
            
            if replay_status["status"] == "COMPLETED":
                break
            elif replay_status["status"] == "FAILED":
                pytest.fail(f"Event replay failed: {replay_status.get('error')}")
            elif (datetime.utcnow() - start_time).seconds > timeout:
                pytest.fail("Event replay timeout")
            
            await asyncio.sleep(1)
        
        # Assert - Verify reconstructed state matches final state
        reconstructed_state = replay_status["reconstructed_state"]
        
        assert reconstructed_state["id"] == final_state["id"]
        assert reconstructed_state["email"] == final_state["email"]
        assert reconstructed_state["first_name"] == final_state["first_name"]
        assert reconstructed_state["last_name"] == final_state["last_name"]
        assert reconstructed_state["version"] == final_state["version"]
        
        # Verify replay validation passed
        assert replay_status["validation_passed"] == True
        assert replay_status["events_replayed"] == final_state["version"]
    
    async def test_point_in_time_state_reconstruction(self, http_client: httpx.AsyncClient):
        """Test reconstructing aggregate state at specific point in time"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create user
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": "Original",
                    "last_name": "Name",
                    "password": "password123"
                }
            }
        )
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(0.5)
        
        # Record timestamps for point-in-time testing
        checkpoints = []
        
        # Checkpoint 1: After creation
        checkpoints.append({
            "name": "after_creation",
            "timestamp": datetime.utcnow(),
            "expected_first_name": "Original",
            "expected_last_name": "Name"
        })
        
        await asyncio.sleep(1)
        
        # Update 1
        await http_client.put(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
            json={
                "command_type": "UpdateUserProfile",
                "data": {"first_name": "Updated1"}
            }
        )
        await asyncio.sleep(0.5)
        
        # Checkpoint 2: After first update
        checkpoints.append({
            "name": "after_first_update",
            "timestamp": datetime.utcnow(),
            "expected_first_name": "Updated1",
            "expected_last_name": "Name"
        })
        
        await asyncio.sleep(1)
        
        # Update 2
        await http_client.put(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
            json={
                "command_type": "UpdateUserProfile",
                "data": {"last_name": "Updated2"}
            }
        )
        await asyncio.sleep(0.5)
        
        # Checkpoint 3: After second update
        checkpoints.append({
            "name": "after_second_update",
            "timestamp": datetime.utcnow(),
            "expected_first_name": "Updated1",
            "expected_last_name": "Updated2"
        })
        
        await asyncio.sleep(2)
        
        # Act & Assert - Test point-in-time reconstruction for each checkpoint
        for checkpoint in checkpoints:
            pit_request = {
                "aggregate_id": user_id,
                "aggregate_type": "User",
                "point_in_time": checkpoint["timestamp"].isoformat()
            }
            
            pit_response = await http_client.post(
                f"{self.replay_url}/point-in-time",
                json=pit_request
            )
            assert pit_response.status_code == 200
            
            pit_state = pit_response.json()["state"]
            
            assert pit_state["first_name"] == checkpoint["expected_first_name"], \
                f"Point-in-time state incorrect for {checkpoint['name']}"
            assert pit_state["last_name"] == checkpoint["expected_last_name"], \
                f"Point-in-time state incorrect for {checkpoint['name']}"
    
    async def test_event_store_consistency_under_load(self, http_client: httpx.AsyncClient):
        """Test event store consistency under concurrent load"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create user
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users",
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
        
        # Act - Perform concurrent updates
        num_concurrent_updates = 10
        
        async def concurrent_update(update_id: int):
            return await http_client.put(
                f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
                json={
                    "command_type": "UpdateUserProfile",
                    "data": {
                        "first_name": f"ConcurrentUpdate{update_id}",
                        "metadata": {"update_id": update_id}
                    }
                }
            )
        
        # Execute concurrent updates
        tasks = [concurrent_update(i) for i in range(num_concurrent_updates)]
        responses = await asyncio.gather(*tasks, return_exceptions=True)
        
        # All updates should be accepted (202) even if concurrent
        successful_responses = [
            r for r in responses 
            if not isinstance(r, Exception) and r.status_code == 202
        ]
        assert len(successful_responses) == num_concurrent_updates
        
        await asyncio.sleep(3)  # Wait for all events to be processed
        
        # Assert - Verify event store consistency
        events_response = await http_client.get(
            f"{self.events_url}",
            params={"aggregate_id": user_id, "aggregate_type": "User"}
        )
        events = events_response.json()["events"]
        
        # Should have UserCreated + all updates
        profile_updated_events = [
            e for e in events if e["event_type"] == "ProfileUpdated"
        ]
        assert len(profile_updated_events) == num_concurrent_updates
        
        # Verify version numbers are sequential (no gaps or duplicates)
        versions = [event["version"] for event in events]
        assert versions == list(range(1, len(events) + 1))
        
        # Verify no duplicate events
        event_ids = [event["event_id"] for event in events]
        assert len(event_ids) == len(set(event_ids))
        
        # Verify final state consistency
        final_state_response = await http_client.get(f"{self.aggregates_url}/users/{user_id}")
        final_state = final_state_response.json()
        
        # Final state should have one of the concurrent updates
        assert final_state["first_name"].startswith("ConcurrentUpdate")
        assert final_state["version"] == len(events)
    
    async def test_event_snapshots_and_optimization(self, http_client: httpx.AsyncClient):
        """Test event snapshots for performance optimization"""
        # Arrange - Create user and generate many events
        user_data = self.factory.create_user()
        
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users",
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
        await asyncio.sleep(0.5)
        
        # Generate many events to trigger snapshot creation
        num_updates = 15  # Assuming snapshot threshold is 10 events
        
        for i in range(num_updates):
            await http_client.put(
                f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
                json={
                    "command_type": "UpdateUserProfile",
                    "data": {"first_name": f"Update{i}"}
                }
            )
            await asyncio.sleep(0.1)
        
        await asyncio.sleep(3)  # Wait for events and potential snapshot creation
        
        # Act - Check if snapshot was created
        snapshots_response = await http_client.get(
            f"{self.snapshots_url}",
            params={"aggregate_id": user_id, "aggregate_type": "User"}
        )
        assert snapshots_response.status_code == 200
        
        snapshots = snapshots_response.json()["snapshots"]
        
        if len(snapshots) > 0:
            # Snapshot exists - verify it's being used for optimization
            latest_snapshot = snapshots[-1]
            assert latest_snapshot["aggregate_id"] == user_id
            assert latest_snapshot["version"] >= 10  # Should snapshot after threshold
            
            # Measure performance improvement with snapshot
            start_time = datetime.utcnow()
            state_response = await http_client.get(f"{self.aggregates_url}/users/{user_id}")
            query_time_with_snapshot = (datetime.utcnow() - start_time).total_seconds()
            
            assert state_response.status_code == 200
            state = state_response.json()
            assert state["first_name"] == f"Update{num_updates - 1}"  # Latest update
            
            # Performance should be good even with many events
            assert query_time_with_snapshot < 1.0, \
                f"Query too slow even with snapshot: {query_time_with_snapshot}s"
            
            # Test snapshot-based reconstruction
            reconstruct_from_snapshot_request = {
                "aggregate_id": user_id,
                "aggregate_type": "User",
                "use_snapshots": True,
                "from_version": latest_snapshot["version"] + 1
            }
            
            reconstruct_response = await http_client.post(
                f"{self.replay_url}/reconstruct",
                json=reconstruct_from_snapshot_request
            )
            assert reconstruct_response.status_code == 202
            
            # Verify reconstruction uses snapshot optimization
            job_id = reconstruct_response.json()["job_id"]
            
            # Wait for completion
            while True:
                status_response = await http_client.get(f"{self.replay_url}/status/{job_id}")
                status = status_response.json()
                
                if status["status"] == "COMPLETED":
                    break
                elif status["status"] == "FAILED":
                    pytest.fail("Snapshot-based reconstruction failed")
                
                await asyncio.sleep(0.5)
            
            # Should have used snapshot (fewer events replayed)
            assert status["events_replayed"] < num_updates
            assert status["snapshot_used"] == True
            assert status["reconstructed_state"]["version"] == num_updates + 1  # +1 for creation
    
    async def test_event_projection_updates(self, http_client: httpx.AsyncClient):
        """Test that events properly update read model projections"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create user
        create_response = await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users",
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
        
        # Act - Perform updates that should trigger projection updates
        await http_client.put(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}",
            json={
                "command_type": "UpdateUserProfile",
                "data": {"first_name": "ProjectionTest"}
            }
        )
        
        await http_client.post(
            f"{self.test_env.api_gateway_url}/commands/users/{user_id}/activate"
        )
        
        await asyncio.sleep(2)  # Wait for event processing and projection updates
        
        # Assert - Verify projections are updated
        
        # 1. User profile projection
        user_query_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/queries/users/{user_id}"
        )
        assert user_query_response.status_code == 200
        user_projection = user_query_response.json()
        assert user_projection["first_name"] == "ProjectionTest"
        assert user_projection["is_active"] == True
        
        # 2. User activity projection
        activity_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/queries/user-activities/{user_id}"
        )
        assert activity_response.status_code == 200
        activities = activity_response.json()["activities"]
        
        activity_types = [activity["type"] for activity in activities]
        assert "UserCreated" in activity_types
        assert "ProfileUpdated" in activity_types
        assert "UserActivated" in activity_types
        
        # 3. User statistics projection
        stats_response = await http_client.get(
            f"{self.test_env.api_gateway_url}/queries/user-stats/{user_id}"
        )
        assert stats_response.status_code == 200
        stats = stats_response.json()
        assert stats["total_profile_updates"] >= 1
        assert stats["last_activity_date"] is not None
        
        # Verify projection consistency with event store
        events_response = await http_client.get(
            f"{self.events_url}",
            params={"aggregate_id": user_id, "aggregate_type": "User"}
        )
        events = events_response.json()["events"]
        
        # Projections should reflect all events
        assert len(activities) == len(events)
        
        # Latest projection version should match latest event version
        latest_event_version = max(event["version"] for event in events)
        assert user_projection["_metadata"]["version"] == latest_event_version