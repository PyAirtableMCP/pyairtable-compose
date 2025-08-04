"""
End-to-end tests for WebSocket functionality and real-time features.
Tests real-time updates, collaboration, and live data synchronization.
"""

import pytest
import asyncio
import websockets
import json
import time
from typing import Dict, List, Any
from unittest.mock import AsyncMock
import httpx


@pytest.mark.e2e
@pytest.mark.external
class TestWebSocketRealTimeFeatures:
    """Test WebSocket real-time functionality"""

    @pytest.fixture(autouse=True)
    async def setup_websocket_test(self, test_environment):
        """Setup WebSocket test environment"""
        self.websocket_url = test_environment.api_gateway_url.replace('http', 'ws') + '/ws'
        self.api_base_url = test_environment.api_gateway_url
        self.connected_clients = []
        
        yield
        
        # Cleanup connections
        for client in self.connected_clients:
            if not client.closed:
                await client.close()

    async def test_websocket_connection_establishment(self, test_environment):
        """Test WebSocket connection establishment and authentication"""
        # First authenticate to get token
        async with httpx.AsyncClient() as http_client:
            auth_response = await http_client.post(
                f"{self.api_base_url}/auth/login",
                json={
                    "email": "test@example.com",
                    "password": "test_password"
                }
            )
            assert auth_response.status_code == 200
            token = auth_response.json().get("access_token")

        # Establish WebSocket connection with authentication
        headers = {"Authorization": f"Bearer {token}"}
        
        try:
            websocket = await websockets.connect(
                self.websocket_url,
                extra_headers=headers,
                timeout=10
            )
            self.connected_clients.append(websocket)
            
            # Send ping to verify connection
            await websocket.send(json.dumps({
                "type": "ping",
                "timestamp": time.time()
            }))
            
            # Wait for pong response
            response = await asyncio.wait_for(websocket.recv(), timeout=5)
            message = json.loads(response)
            
            assert message["type"] == "pong"
            assert "timestamp" in message
            
        except Exception as e:
            pytest.fail(f"WebSocket connection failed: {e}")

    async def test_real_time_table_updates(self, test_environment, test_data_factory):
        """Test real-time table updates via WebSocket"""
        # Setup authenticated WebSocket connection
        websocket = await self._establish_authenticated_connection()
        
        # Subscribe to table updates
        await websocket.send(json.dumps({
            "type": "subscribe",
            "channel": "table_updates",
            "table_id": "test_table_123"
        }))
        
        # Confirm subscription
        response = await asyncio.wait_for(websocket.recv(), timeout=5)
        message = json.loads(response)
        assert message["type"] == "subscription_confirmed"
        assert message["channel"] == "table_updates"
        
        # Create a new record via HTTP API to trigger WebSocket update
        record_data = test_data_factory.create_record_data()
        
        async with httpx.AsyncClient() as http_client:
            create_response = await http_client.post(
                f"{self.api_base_url}/api/tables/test_table_123/records",
                json=record_data,
                headers={"Authorization": f"Bearer {await self._get_test_token()}"}
            )
            assert create_response.status_code == 201
        
        # Wait for WebSocket notification
        update_message = await asyncio.wait_for(websocket.recv(), timeout=10)
        update_data = json.loads(update_message)
        
        assert update_data["type"] == "table_update"
        assert update_data["action"] == "record_created"
        assert update_data["table_id"] == "test_table_123"
        assert "record" in update_data
        assert update_data["record"]["fields"]["name"] == record_data["name"]

    async def test_collaborative_editing(self, test_environment):
        """Test collaborative editing with multiple WebSocket connections"""
        # Establish two WebSocket connections (simulating two users)
        user1_ws = await self._establish_authenticated_connection("user1@example.com")
        user2_ws = await self._establish_authenticated_connection("user2@example.com")
        
        table_id = "collaborative_table_456"
        
        # Both users subscribe to the same table
        for ws in [user1_ws, user2_ws]:
            await ws.send(json.dumps({
                "type": "subscribe",
                "channel": "table_updates",
                "table_id": table_id
            }))
            
            # Confirm subscription
            response = await asyncio.wait_for(ws.recv(), timeout=5)
            message = json.loads(response)
            assert message["type"] == "subscription_confirmed"
        
        # User 1 starts editing a record
        await user1_ws.send(json.dumps({
            "type": "start_editing",
            "table_id": table_id,
            "record_id": "rec_123",
            "field": "name",
            "user_id": "user1"
        }))
        
        # User 2 should receive editing notification
        edit_notification = await asyncio.wait_for(user2_ws.recv(), timeout=5)
        edit_data = json.loads(edit_notification)
        
        assert edit_data["type"] == "editing_started"
        assert edit_data["record_id"] == "rec_123"
        assert edit_data["field"] == "name"
        assert edit_data["user_id"] == "user1"
        
        # User 1 makes changes
        await user1_ws.send(json.dumps({
            "type": "field_change",
            "table_id": table_id,
            "record_id": "rec_123",
            "field": "name",
            "value": "Updated Name",
            "user_id": "user1"
        }))
        
        # User 2 should receive the change
        change_notification = await asyncio.wait_for(user2_ws.recv(), timeout=5)
        change_data = json.loads(change_notification)
        
        assert change_data["type"] == "field_changed"
        assert change_data["value"] == "Updated Name"
        
        # User 1 stops editing
        await user1_ws.send(json.dumps({
            "type": "stop_editing",
            "table_id": table_id,
            "record_id": "rec_123",
            "field": "name",
            "user_id": "user1"
        }))
        
        # User 2 should receive editing stopped notification
        stop_notification = await asyncio.wait_for(user2_ws.recv(), timeout=5)
        stop_data = json.loads(stop_notification)
        
        assert stop_data["type"] == "editing_stopped"
        assert stop_data["record_id"] == "rec_123"

    async def test_presence_awareness(self, test_environment):
        """Test user presence awareness in collaborative sessions"""
        # Establish connections for multiple users
        user1_ws = await self._establish_authenticated_connection("user1@example.com")
        user2_ws = await self._establish_authenticated_connection("user2@example.com")
        user3_ws = await self._establish_authenticated_connection("user3@example.com")
        
        workspace_id = "workspace_789"
        
        # Users join workspace
        for user_id, ws in [("user1", user1_ws), ("user2", user2_ws), ("user3", user3_ws)]:
            await ws.send(json.dumps({
                "type": "join_workspace",
                "workspace_id": workspace_id,
                "user_id": user_id
            }))
        
        # Each user should receive presence updates about others
        for ws in [user1_ws, user2_ws, user3_ws]:
            presence_updates = []
            
            # Collect presence updates
            try:
                while len(presence_updates) < 2:  # Expecting 2 other users
                    message = await asyncio.wait_for(ws.recv(), timeout=3)
                    data = json.loads(message)
                    if data["type"] == "user_joined":
                        presence_updates.append(data)
            except asyncio.TimeoutError:
                pass  # No more messages expected
            
            # Verify we received presence information about other users
            assert len(presence_updates) >= 1

    async def test_real_time_chat_integration(self, test_environment):
        """Test real-time chat integration with AI assistant"""
        websocket = await self._establish_authenticated_connection()
        
        # Subscribe to chat updates
        await websocket.send(json.dumps({
            "type": "subscribe",
            "channel": "chat_updates",
            "session_id": "chat_session_456"
        }))
        
        # Send chat message
        await websocket.send(json.dumps({
            "type": "chat_message",
            "session_id": "chat_session_456",
            "message": "Analyze the data in my table",
            "user_id": "test_user"
        }))
        
        # Expect acknowledgment
        ack_message = await asyncio.wait_for(websocket.recv(), timeout=5)
        ack_data = json.loads(ack_message)
        assert ack_data["type"] == "message_received"
        
        # Expect AI response (this might take longer)
        ai_response = await asyncio.wait_for(websocket.recv(), timeout=30)
        ai_data = json.loads(ai_response)
        
        assert ai_data["type"] == "ai_response"
        assert "response" in ai_data
        assert len(ai_data["response"]) > 0

    async def test_websocket_error_handling(self, test_environment):
        """Test WebSocket error handling and recovery"""
        websocket = await self._establish_authenticated_connection()
        
        # Send invalid message format
        await websocket.send("invalid_json_message")
        
        # Should receive error message
        error_response = await asyncio.wait_for(websocket.recv(), timeout=5)
        error_data = json.loads(error_response)
        
        assert error_data["type"] == "error"
        assert "message" in error_data
        
        # Connection should still be alive after error
        await websocket.send(json.dumps({
            "type": "ping",
            "timestamp": time.time()
        }))
        
        pong_response = await asyncio.wait_for(websocket.recv(), timeout=5)
        pong_data = json.loads(pong_response)
        assert pong_data["type"] == "pong"

    async def test_connection_scalability(self, test_environment):
        """Test WebSocket connection scalability"""
        connections = []
        max_connections = 50  # Test with 50 concurrent connections
        
        try:
            # Establish multiple connections
            tasks = []
            for i in range(max_connections):
                task = asyncio.create_task(
                    self._establish_authenticated_connection(f"user{i}@example.com")
                )
                tasks.append(task)
            
            connections = await asyncio.gather(*tasks)
            
            # Verify all connections are established
            assert len(connections) == max_connections
            
            # Send ping to all connections
            ping_tasks = []
            for ws in connections:
                ping_task = asyncio.create_task(
                    ws.send(json.dumps({
                        "type": "ping",
                        "timestamp": time.time()
                    }))
                )
                ping_tasks.append(ping_task)
            
            await asyncio.gather(*ping_tasks)
            
            # Verify all connections respond
            pong_tasks = []
            for ws in connections:
                pong_task = asyncio.create_task(
                    asyncio.wait_for(ws.recv(), timeout=10)
                )
                pong_tasks.append(pong_task)
            
            responses = await asyncio.gather(*pong_tasks)
            
            # All should be pong responses
            for response in responses:
                data = json.loads(response)
                assert data["type"] == "pong"
                
        finally:
            # Cleanup all connections
            for ws in connections:
                if not ws.closed:
                    await ws.close()

    async def test_message_ordering_and_reliability(self, test_environment):
        """Test message ordering and reliability in WebSocket communication"""
        websocket = await self._establish_authenticated_connection()
        
        # Subscribe to updates
        await websocket.send(json.dumps({
            "type": "subscribe",
            "channel": "test_ordering",
            "table_id": "order_test_table"
        }))
        
        # Send multiple rapid updates
        num_messages = 10
        sent_messages = []
        
        for i in range(num_messages):
            message = {
                "type": "test_message",
                "sequence": i,
                "data": f"message_{i}",
                "timestamp": time.time()
            }
            sent_messages.append(message)
            await websocket.send(json.dumps(message))
        
        # Receive and verify message ordering
        received_messages = []
        for _ in range(num_messages):
            response = await asyncio.wait_for(websocket.recv(), timeout=5)
            received_messages.append(json.loads(response))
        
        # Verify messages are received in order
        for i, received in enumerate(received_messages):
            if received["type"] == "test_message":
                assert received["sequence"] == i

    async def _establish_authenticated_connection(self, email: str = "test@example.com") -> websockets.WebSocketServerProtocol:
        """Helper to establish authenticated WebSocket connection"""
        # Get authentication token
        token = await self._get_test_token(email)
        
        # Establish WebSocket connection
        headers = {"Authorization": f"Bearer {token}"}
        websocket = await websockets.connect(
            self.websocket_url,
            extra_headers=headers,
            timeout=10
        )
        
        self.connected_clients.append(websocket)
        return websocket

    async def _get_test_token(self, email: str = "test@example.com") -> str:
        """Helper to get authentication token for testing"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base_url}/auth/login",
                json={
                    "email": email,
                    "password": "test_password"
                }
            )
            if response.status_code == 200:
                return response.json().get("access_token")
            else:
                # If login fails, create the user first
                await client.post(
                    f"{self.api_base_url}/auth/register",
                    json={
                        "email": email,
                        "password": "test_password",
                        "first_name": "Test",
                        "last_name": "User"
                    }
                )
                
                # Try login again
                response = await client.post(
                    f"{self.api_base_url}/auth/login",
                    json={
                        "email": email,
                        "password": "test_password"
                    }
                )
                return response.json().get("access_token")


@pytest.mark.e2e
class TestWebSocketPerformance:
    """Test WebSocket performance characteristics"""

    async def test_message_throughput(self, test_environment):
        """Test WebSocket message throughput"""
        websocket = await self._establish_authenticated_connection()
        
        # Send burst of messages and measure throughput
        num_messages = 1000
        start_time = time.time()
        
        # Send messages
        send_tasks = []
        for i in range(num_messages):
            task = asyncio.create_task(
                websocket.send(json.dumps({
                    "type": "throughput_test",
                    "sequence": i
                }))
            )
            send_tasks.append(task)
        
        await asyncio.gather(*send_tasks)
        
        send_duration = time.time() - start_time
        messages_per_second = num_messages / send_duration
        
        # Should handle at least 100 messages per second
        assert messages_per_second > 100, f"Throughput too low: {messages_per_second:.2f} msg/s"
        
        print(f"WebSocket throughput: {messages_per_second:.2f} messages/second")

    async def test_latency_measurement(self, test_environment):
        """Test WebSocket message latency"""
        websocket = await self._establish_authenticated_connection()
        
        latencies = []
        num_tests = 50
        
        for i in range(num_tests):
            start_time = time.time()
            
            await websocket.send(json.dumps({
                "type": "latency_test",
                "timestamp": start_time
            }))
            
            response = await websocket.recv()
            end_time = time.time()
            
            latency = end_time - start_time
            latencies.append(latency)
            
            # Small delay between tests
            await asyncio.sleep(0.01)
        
        avg_latency = sum(latencies) / len(latencies)
        max_latency = max(latencies)
        
        # Average latency should be under 100ms
        assert avg_latency < 0.1, f"Average latency too high: {avg_latency:.3f}s"
        
        # Maximum latency should be under 500ms
        assert max_latency < 0.5, f"Maximum latency too high: {max_latency:.3f}s"
        
        print(f"WebSocket latency - Avg: {avg_latency:.3f}s, Max: {max_latency:.3f}s")

    async def _establish_authenticated_connection(self) -> websockets.WebSocketServerProtocol:
        """Helper to establish authenticated WebSocket connection"""
        # This would use the same logic as the main test class
        pass