"""
End-to-end tests for Outbox Pattern implementation.
Tests reliable message delivery and transactional consistency.
"""

import pytest
import asyncio
import httpx
from typing import Dict, Any, List
from datetime import datetime, timedelta
from tests.fixtures.factories import TestDataFactory
from tests.fixtures.mock_services import create_mock_services, reset_all_mocks

@pytest.mark.e2e
@pytest.mark.asyncio
class TestOutboxPattern:
    """Test Outbox Pattern for reliable message delivery"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        self.mocks = create_mock_services()
        
        # Outbox pattern endpoints
        self.outbox_url = f"{test_environment.api_gateway_url}/outbox"
        self.messages_url = f"{test_environment.api_gateway_url}/messages"
        self.commands_url = f"{test_environment.api_gateway_url}/commands"
        
        yield
        
        reset_all_mocks(self.mocks)
    
    async def test_transactional_outbox_message_delivery(self, http_client: httpx.AsyncClient):
        """Test that database transactions and message publishing are atomic"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Act - Create user (should create database record AND outbox message atomically)
        create_command = {
            "command_type": "CreateUser",
            "data": {
                "email": user_data.email,
                "username": user_data.username,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "password": "password123"
            },
            "outbox_events": [
                {
                    "event_type": "UserCreated",
                    "destination": "user-service",
                    "topic": "user.events"
                },
                {
                    "event_type": "SendWelcomeEmail",
                    "destination": "notification-service",
                    "topic": "notifications.email"
                }
            ]
        }
        
        response = await http_client.post(
            f"{self.commands_url}/users",
            json=create_command
        )
        
        assert response.status_code == 202
        command_result = response.json()
        user_id = command_result["aggregate_id"]
        
        # Wait for transaction completion
        await asyncio.sleep(2)
        
        # Assert - Verify user was created in database
        user_response = await http_client.get(
            f"{self.test_env.auth_service_url}/users/{user_id}"
        )
        assert user_response.status_code == 200
        
        # Verify outbox messages were created
        outbox_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={"aggregate_id": user_id}
        )
        assert outbox_response.status_code == 200
        
        outbox_messages = outbox_response.json()["messages"]
        assert len(outbox_messages) == 2
        
        # Verify message content
        user_created_msg = next(m for m in outbox_messages if m["event_type"] == "UserCreated")
        assert user_created_msg["destination"] == "user-service"
        assert user_created_msg["topic"] == "user.events"
        assert user_created_msg["payload"]["user_id"] == user_id
        assert user_created_msg["payload"]["email"] == user_data.email
        
        welcome_email_msg = next(m for m in outbox_messages if m["event_type"] == "SendWelcomeEmail")
        assert welcome_email_msg["destination"] == "notification-service"
        assert welcome_email_msg["topic"] == "notifications.email"
        
        # Verify messages are marked as pending initially
        for message in outbox_messages:
            assert message["status"] == "PENDING"
            assert message["attempts"] == 0
            assert message["created_at"] is not None
    
    async def test_outbox_message_processing_and_delivery(self, http_client: httpx.AsyncClient):
        """Test outbox message processing worker and delivery confirmation"""
        # Arrange - Create user with outbox messages
        user_data = self.factory.create_user()
        
        create_response = await http_client.post(
            f"{self.commands_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                },
                "outbox_events": [
                    {
                        "event_type": "UserCreated",
                        "destination": "user-service",
                        "topic": "user.events"
                    }
                ]
            }
        )
        
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Get the outbox message
        outbox_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={"aggregate_id": user_id, "status": "PENDING"}
        )
        outbox_messages = outbox_response.json()["messages"]
        assert len(outbox_messages) == 1
        
        message_id = outbox_messages[0]["id"]
        
        # Act - Trigger outbox processing (simulate worker)
        process_response = await http_client.post(
            f"{self.outbox_url}/process",
            json={"batch_size": 10}
        )
        assert process_response.status_code == 200
        
        processing_result = process_response.json()
        assert processing_result["processed_count"] >= 1
        
        # Wait for message delivery
        await asyncio.sleep(3)
        
        # Assert - Verify message status updated
        message_status_response = await http_client.get(
            f"{self.outbox_url}/messages/{message_id}"
        )
        assert message_status_response.status_code == 200
        
        message_status = message_status_response.json()
        assert message_status["status"] in ["DELIVERED", "PROCESSING"]
        assert message_status["attempts"] >= 1
        assert message_status["last_attempt_at"] is not None
        
        if message_status["status"] == "DELIVERED":
            assert message_status["delivered_at"] is not None
            assert message_status["delivery_confirmation"] is not None
    
    async def test_outbox_retry_mechanism_on_failure(self, http_client: httpx.AsyncClient):
        """Test outbox retry mechanism when message delivery fails"""
        # Arrange - Create scenario that will cause delivery failure
        user_data = self.factory.create_user()
        
        create_response = await http_client.post(
            f"{self.commands_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                },
                "outbox_events": [
                    {
                        "event_type": "TestFailure",
                        "destination": "non-existent-service",  # This will fail
                        "topic": "test.failures",
                        "retry_config": {
                            "max_attempts": 3,
                            "retry_delay": 1,
                            "backoff_multiplier": 2
                        }
                    }
                ]
            }
        )
        
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Get the message that will fail
        outbox_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={"aggregate_id": user_id}
        )
        message_id = outbox_response.json()["messages"][0]["id"]
        
        # Act - Trigger processing multiple times to test retry
        for attempt in range(5):  # More than max_attempts to test failure handling
            process_response = await http_client.post(
                f"{self.outbox_url}/process",
                json={"batch_size": 10, "include_failed": True}
            )
            await asyncio.sleep(2)  # Wait between retry attempts
        
        # Assert - Verify retry behavior
        final_message_response = await http_client.get(
            f"{self.outbox_url}/messages/{message_id}"
        )
        final_message = final_message_response.json()
        
        assert final_message["attempts"] >= 3  # Should have attempted at least max_attempts
        assert final_message["status"] == "FAILED"  # Should be marked as failed after max attempts
        assert final_message["last_error"] is not None
        assert final_message["failed_at"] is not None
        
        # Verify retry delays followed exponential backoff
        assert len(final_message["attempt_history"]) >= 3
        
        # Check that retry delays increased (exponential backoff)
        if len(final_message["attempt_history"]) >= 2:
            first_delay = final_message["attempt_history"][1]["delay_before_attempt"]
            second_delay = final_message["attempt_history"][2]["delay_before_attempt"]
            assert second_delay > first_delay  # Backoff should increase delay
    
    async def test_outbox_dead_letter_queue_handling(self, http_client: httpx.AsyncClient):
        """Test dead letter queue for permanently failed messages"""
        # Arrange - Create message that will permanently fail
        user_data = self.factory.create_user()
        
        create_response = await http_client.post(
            f"{self.commands_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                },
                "outbox_events": [
                    {
                        "event_type": "PermanentFailure",
                        "destination": "invalid-service",
                        "topic": "test.permanent-failures",
                        "retry_config": {
                            "max_attempts": 2,
                            "retry_delay": 1
                        }
                    }
                ]
            }
        )
        
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Force processing to exhaust retries
        for _ in range(3):
            await http_client.post(
                f"{self.outbox_url}/process",
                json={"batch_size": 10, "include_failed": True}
            )
            await asyncio.sleep(1)
        
        # Act - Check dead letter queue
        dlq_response = await http_client.get(f"{self.outbox_url}/dead-letter-queue")
        assert dlq_response.status_code == 200
        
        dlq_messages = dlq_response.json()["messages"]
        
        # Find our failed message in DLQ
        failed_message = next(
            (msg for msg in dlq_messages if msg["aggregate_id"] == user_id),
            None
        )
        
        # Assert - Verify message in dead letter queue
        assert failed_message is not None
        assert failed_message["status"] == "DEAD_LETTER"
        assert failed_message["attempts"] >= 2
        assert failed_message["moved_to_dlq_at"] is not None
        assert failed_message["final_error"] is not None
        
        # Test DLQ message retry (manual intervention)
        retry_dlq_response = await http_client.post(
            f"{self.outbox_url}/dead-letter-queue/{failed_message['id']}/retry",
            json={"reset_attempts": True}
        )
        assert retry_dlq_response.status_code == 202
        
        # Message should be moved back to pending
        await asyncio.sleep(1)
        
        retried_message_response = await http_client.get(
            f"{self.outbox_url}/messages/{failed_message['id']}"
        )
        retried_message = retried_message_response.json()
        
        assert retried_message["status"] == "PENDING"
        assert retried_message["attempts"] == 0  # Reset
        assert retried_message["moved_to_dlq_at"] is None
    
    async def test_outbox_batch_processing_performance(self, http_client: httpx.AsyncClient):
        """Test outbox batch processing for performance at scale"""
        # Arrange - Create multiple users to generate many outbox messages
        num_users = 20
        user_ids = []
        
        for i in range(num_users):
            user_data = self.factory.create_user(
                email=f"batchuser{i}@example.com",
                username=f"batchuser{i}"
            )
            
            create_response = await http_client.post(
                f"{self.commands_url}/users",
                json={
                    "command_type": "CreateUser",
                    "data": {
                        "email": user_data.email,
                        "username": user_data.username,
                        "first_name": user_data.first_name,
                        "last_name": user_data.last_name,
                        "password": "password123"
                    },
                    "outbox_events": [
                        {
                            "event_type": "UserCreated",
                            "destination": "user-service",
                            "topic": "user.events"
                        },
                        {
                            "event_type": "SendWelcomeEmail",
                            "destination": "notification-service",
                            "topic": "notifications.email"
                        }
                    ]
                }
            )
            user_ids.append(create_response.json()["aggregate_id"])
        
        await asyncio.sleep(2)  # Wait for all users to be created
        
        # Verify messages are pending
        pending_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={"status": "PENDING", "limit": 100}
        )
        pending_messages = pending_response.json()["messages"]
        assert len(pending_messages) >= num_users * 2  # 2 messages per user
        
        # Act - Process in batches and measure performance
        batch_sizes = [5, 10, 20]
        
        for batch_size in batch_sizes:
            start_time = datetime.utcnow()
            
            process_response = await http_client.post(
                f"{self.outbox_url}/process",
                json={
                    "batch_size": batch_size,
                    "max_processing_time": 30
                }
            )
            
            processing_time = (datetime.utcnow() - start_time).total_seconds()
            
            assert process_response.status_code == 200
            result = process_response.json()
            
            # Verify batch processing efficiency
            if result["processed_count"] > 0:
                messages_per_second = result["processed_count"] / processing_time
                assert messages_per_second > 1.0, \
                    f"Batch processing too slow: {messages_per_second} msg/sec"
                
                # Larger batches should be more efficient (up to a point)
                assert processing_time < 10.0, \
                    f"Batch processing took too long: {processing_time}s"
        
        await asyncio.sleep(3)  # Wait for final processing
        
        # Assert - Verify all messages were eventually processed
        final_status_response = await http_client.get(
            f"{self.outbox_url}/stats"
        )
        stats = final_status_response.json()
        
        assert stats["total_delivered"] >= num_users * 2
        assert stats["pending_count"] == 0 or stats["pending_count"] < 5  # Allow for small delays
    
    async def test_outbox_duplicate_message_prevention(self, http_client: httpx.AsyncClient):
        """Test prevention of duplicate message delivery"""
        # Arrange
        user_data = self.factory.create_user()
        
        create_response = await http_client.post(
            f"{self.commands_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                },
                "outbox_events": [
                    {
                        "event_type": "UserCreated",
                        "destination": "user-service",
                        "topic": "user.events",
                        "idempotency_key": f"user-created-{user_data.email}"
                    }
                ]
            }
        )
        
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(1)
        
        # Get the original message
        outbox_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={"aggregate_id": user_id}
        )
        original_message = outbox_response.json()["messages"][0]
        
        # Act - Try to create duplicate message with same idempotency key
        duplicate_response = await http_client.post(
            f"{self.outbox_url}/messages",
            json={
                "event_type": "UserCreated",
                "destination": "user-service",
                "topic": "user.events",
                "aggregate_id": user_id,
                "payload": {"user_id": user_id, "email": user_data.email},
                "idempotency_key": f"user-created-{user_data.email}"  # Same key
            }
        )
        
        # Assert - Duplicate should be rejected or ignored
        if duplicate_response.status_code == 409:
            # Explicitly rejected as duplicate
            assert "duplicate" in duplicate_response.json()["error"].lower()
        elif duplicate_response.status_code == 200:
            # Silently ignored, return existing message
            returned_message = duplicate_response.json()
            assert returned_message["id"] == original_message["id"]
        
        # Verify only one message exists
        final_outbox_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={"aggregate_id": user_id}
        )
        final_messages = final_outbox_response.json()["messages"]
        assert len(final_messages) == 1
        assert final_messages[0]["id"] == original_message["id"]
    
    async def test_outbox_message_ordering_guarantee(self, http_client: httpx.AsyncClient):
        """Test that outbox messages maintain ordering guarantees"""
        # Arrange
        user_data = self.factory.create_user()
        
        # Create user with ordered sequence of events
        create_response = await http_client.post(
            f"{self.commands_url}/users",
            json={
                "command_type": "CreateUser",
                "data": {
                    "email": user_data.email,
                    "username": user_data.username,
                    "first_name": user_data.first_name,
                    "last_name": user_data.last_name,
                    "password": "password123"
                },
                "outbox_events": [
                    {
                        "event_type": "UserCreated",
                        "destination": "user-service",
                        "topic": "user.events",
                        "sequence_number": 1,
                        "ordering_key": user_data.email
                    }
                ]
            }
        )
        
        user_id = create_response.json()["aggregate_id"]
        await asyncio.sleep(0.5)
        
        # Add more events in sequence
        update_events = [
            {"event_type": "ProfileUpdated", "sequence_number": 2},
            {"event_type": "EmailVerified", "sequence_number": 3},
            {"event_type": "UserActivated", "sequence_number": 4}
        ]
        
        for event in update_events:
            await http_client.post(
                f"{self.outbox_url}/messages",
                json={
                    "event_type": event["event_type"],
                    "destination": "user-service",
                    "topic": "user.events",
                    "aggregate_id": user_id,
                    "payload": {"user_id": user_id, "action": event["event_type"]},
                    "sequence_number": event["sequence_number"],
                    "ordering_key": user_data.email
                }
            )
            await asyncio.sleep(0.1)
        
        await asyncio.sleep(1)
        
        # Act - Process messages with ordering
        process_response = await http_client.post(
            f"{self.outbox_url}/process",
            json={
                "batch_size": 10,
                "preserve_ordering": True,
                "ordering_key": user_data.email
            }
        )
        assert process_response.status_code == 200
        
        await asyncio.sleep(2)
        
        # Assert - Verify messages were delivered in correct order
        delivered_response = await http_client.get(
            f"{self.outbox_url}/messages",
            params={
                "aggregate_id": user_id,
                "status": "DELIVERED",
                "ordering_key": user_data.email,
                "sort": "sequence_number"
            }
        )
        
        delivered_messages = delivered_response.json()["messages"]
        assert len(delivered_messages) >= 4
        
        # Verify sequence numbers are in order
        sequence_numbers = [msg["sequence_number"] for msg in delivered_messages]
        assert sequence_numbers == sorted(sequence_numbers)
        
        # Verify delivery timestamps respect ordering
        delivery_times = [
            datetime.fromisoformat(msg["delivered_at"].replace('Z', '+00:00'))
            for msg in delivered_messages if msg["delivered_at"]
        ]
        
        # Each message should be delivered after the previous one
        for i in range(1, len(delivery_times)):
            assert delivery_times[i] >= delivery_times[i-1], \
                "Message delivery order violation"