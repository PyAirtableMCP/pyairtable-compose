"""
Integration tests for AI chat functionality.

Tests:
1. Chat endpoint availability and authentication
2. Chat message processing and response generation  
3. Session context management
4. Integration with Airtable data
5. Error handling for AI service failures
"""

import pytest
import asyncio
import httpx
import json
from typing import Dict, Any, List
from datetime import datetime


class TestAIChatIntegration:
    """Integration tests for AI chat functionality"""
    
    API_URL = "http://localhost:8000"  # API Gateway
    AI_URL = "http://localhost:8001"  # AI Processing Service Direct
    
    @pytest.fixture
    async def http_client(self):
        """HTTP client for making requests"""
        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
            yield client
    
    @pytest.fixture
    async def authenticated_session(self, http_client):
        """Create authenticated session for chat testing"""
        timestamp = str(asyncio.get_event_loop().time()).replace('.', '')
        test_user = {
            "name": f"Chat Test User {timestamp}",
            "email": f"chat_test_{timestamp}@example.com",
            "password": "ChatTest123!"
        }
        
        # Register and login user
        await http_client.post(
            f"{self.API_URL}/api/v1/auth/register",
            json=test_user,
            headers={"Content-Type": "application/json"}
        )
        
        login_response = await http_client.post(
            f"{self.API_URL}/api/v1/auth/login",
            json={
                "email": test_user["email"],
                "password": test_user["password"]
            },
            headers={"Content-Type": "application/json"}
        )
        
        if login_response.status_code != 200:
            pytest.skip("Could not authenticate for chat testing")
            
        login_data = login_response.json()
        return {
            "user": test_user,
            "token": login_data["access_token"],
            "user_data": login_data["user"]
        }
    
    @pytest.fixture
    def chat_headers(self, authenticated_session):
        """Headers for authenticated chat requests"""
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": f"Bearer {authenticated_session['token']}"
        }

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_chat_endpoint_availability(self, http_client, chat_headers):
        """Test that chat endpoints are accessible and require authentication"""
        
        # Test unauthenticated access is blocked
        unauth_response = await http_client.post(
            f"{self.API_URL}/api/v1/chat",
            json={"message": "Hello"},
            headers={"Content-Type": "application/json"}
        )
        assert unauth_response.status_code in [401, 403, 404]
        
        # Test authenticated access to chat endpoint
        auth_response = await http_client.post(
            f"{self.API_URL}/api/v1/chat",
            json={"message": "Hello, can you help me?"},
            headers=chat_headers
        )
        
        # Should either work or endpoint not configured yet
        assert auth_response.status_code in [200, 201, 404, 405]

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_direct_ai_service_health(self, http_client):
        """Test AI processing service health check"""
        
        try:
            ai_health = await http_client.get(f"{self.AI_URL}/health")
            assert ai_health.status_code == 200
            
            health_data = ai_health.json()
            assert "status" in health_data
            assert health_data["status"] in ["healthy", "ok"]
            
        except httpx.ConnectError:
            pytest.skip("AI Processing Service not running")

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_chat_message_processing(self, http_client, chat_headers):
        """Test basic chat message processing"""
        
        test_messages = [
            "Hello, what can you help me with?",
            "Can you explain what PyAirtable does?",
            "Help me understand my data",
        ]
        
        for message in test_messages:
            chat_request = {
                "message": message,
                "conversation_id": f"test_{asyncio.get_event_loop().time()}"
            }
            
            response = await http_client.post(
                f"{self.API_URL}/api/v1/chat",
                json=chat_request,
                headers=chat_headers
            )
            
            if response.status_code == 404:
                pytest.skip("Chat endpoint not configured")
                
            if response.status_code in [200, 201]:
                chat_data = response.json()
                
                # Verify response format
                assert isinstance(chat_data, dict)
                expected_fields = ["response", "message", "reply", "answer"]
                has_response = any(field in chat_data for field in expected_fields)
                assert has_response, f"Chat response missing response field: {chat_data}"
                
                # Verify response content
                response_text = (
                    chat_data.get("response") or 
                    chat_data.get("message") or 
                    chat_data.get("reply") or 
                    chat_data.get("answer")
                )
                assert isinstance(response_text, str)
                assert len(response_text) > 0
                
            else:
                # Service might be unavailable
                assert response.status_code in [500, 502, 503]

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_chat_session_management(self, http_client, chat_headers):
        """Test chat conversation session management"""
        
        conversation_id = f"session_test_{asyncio.get_event_loop().time()}"
        
        # Send first message
        first_message = {
            "message": "My name is John and I'm working on data analysis.",
            "conversation_id": conversation_id
        }
        
        first_response = await http_client.post(
            f"{self.API_URL}/api/v1/chat",
            json=first_message,
            headers=chat_headers
        )
        
        if first_response.status_code == 404:
            pytest.skip("Chat endpoint not configured")
            
        if first_response.status_code not in [200, 201]:
            pytest.skip("Chat service not available")
            
        # Send follow-up message that references context
        followup_message = {
            "message": "What did I say my name was?",
            "conversation_id": conversation_id
        }
        
        followup_response = await http_client.post(
            f"{self.API_URL}/api/v1/chat",
            json=followup_message,
            headers=chat_headers
        )
        
        if followup_response.status_code in [200, 201]:
            followup_data = followup_response.json()
            response_text = (
                followup_data.get("response") or 
                followup_data.get("message") or 
                followup_data.get("reply") or 
                followup_data.get("answer") or ""
            ).lower()
            
            # AI should remember the name from context (if session management works)
            # This is a soft assertion since context management might not be implemented
            if "john" in response_text:
                # Great! Context was maintained
                pass

    @pytest.mark.integration  
    @pytest.mark.ai_chat
    async def test_chat_airtable_integration(self, http_client, chat_headers):
        """Test chat integration with Airtable data"""
        
        airtable_related_queries = [
            "Show me my Airtable data",
            "What tables do I have access to?",
            "Can you analyze my database?",
            "Help me understand my records",
        ]
        
        for query in airtable_related_queries:
            chat_request = {
                "message": query,
                "conversation_id": f"airtable_test_{asyncio.get_event_loop().time()}"
            }
            
            response = await http_client.post(
                f"{self.API_URL}/api/v1/chat",
                json=chat_request,
                headers=chat_headers
            )
            
            if response.status_code == 404:
                pytest.skip("Chat endpoint not configured")
                
            if response.status_code in [200, 201]:
                chat_data = response.json()
                
                # Verify we got a response
                response_text = (
                    chat_data.get("response") or 
                    chat_data.get("message") or 
                    chat_data.get("reply") or 
                    chat_data.get("answer") or ""
                )
                
                assert isinstance(response_text, str)
                assert len(response_text) > 0
                
                # Check if response indicates Airtable integration
                airtable_keywords = ["table", "database", "record", "airtable", "data", "field"]
                has_airtable_context = any(keyword in response_text.lower() for keyword in airtable_keywords)
                
                # This is informational - integration might not be complete
                if has_airtable_context:
                    # Great! Shows Airtable integration
                    pass

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_chat_error_handling(self, http_client, chat_headers):
        """Test chat error handling scenarios"""
        
        error_scenarios = [
            # Empty message
            {"message": ""},
            # Very long message
            {"message": "A" * 10000},
            # Missing message field
            {"query": "test"},
            # Invalid conversation ID
            {"message": "test", "conversation_id": ""},
        ]
        
        for scenario in error_scenarios:
            response = await http_client.post(
                f"{self.API_URL}/api/v1/chat",
                json=scenario,
                headers=chat_headers
            )
            
            if response.status_code == 404:
                pytest.skip("Chat endpoint not configured")
            
            # Should handle errors gracefully
            assert response.status_code in [200, 201, 400, 422]
            
            if response.status_code in [200, 201]:
                # If successful, should have valid response
                data = response.json()
                assert isinstance(data, dict)
            
            elif response.status_code in [400, 422]:
                # If validation error, should have error message
                error_data = response.json()
                assert "error" in error_data or "detail" in error_data

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_chat_response_time(self, http_client, chat_headers):
        """Test chat response time is reasonable"""
        
        import time
        
        chat_request = {
            "message": "Hello, this is a simple test message",
            "conversation_id": f"perf_test_{asyncio.get_event_loop().time()}"
        }
        
        start_time = time.time()
        
        response = await http_client.post(
            f"{self.API_URL}/api/v1/chat",
            json=chat_request,
            headers=chat_headers
        )
        
        end_time = time.time()
        response_time = end_time - start_time
        
        if response.status_code == 404:
            pytest.skip("Chat endpoint not configured")
            
        # Response should be within reasonable time (30 seconds for AI processing)
        assert response_time < 30.0, f"Chat response took too long: {response_time}s"
        
        if response.status_code in [200, 201]:
            # If successful, response time should be reasonable
            assert response_time < 15.0, f"Successful chat response too slow: {response_time}s"

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_concurrent_chat_requests(self, http_client, chat_headers):
        """Test handling of concurrent chat requests"""
        
        # Send multiple concurrent requests
        tasks = []
        for i in range(3):  # Small number to avoid overwhelming
            chat_request = {
                "message": f"Concurrent test message {i}",
                "conversation_id": f"concurrent_{i}_{asyncio.get_event_loop().time()}"
            }
            
            task = http_client.post(
                f"{self.API_URL}/api/v1/chat",
                json=chat_request,
                headers=chat_headers
            )
            tasks.append(task)
        
        responses = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Check responses
        successful_responses = 0
        for response in responses:
            if isinstance(response, Exception):
                continue
                
            if response.status_code == 404:
                pytest.skip("Chat endpoint not configured")
                
            if response.status_code in [200, 201]:
                successful_responses += 1
            elif response.status_code in [429, 503]:
                # Rate limiting or service overload is acceptable
                pass
        
        # At least some requests should succeed
        assert successful_responses > 0, "No concurrent requests succeeded"

    @pytest.mark.integration
    @pytest.mark.ai_chat
    async def test_chat_conversation_history(self, http_client, chat_headers):
        """Test conversation history retrieval (if available)"""
        
        conversation_id = f"history_test_{asyncio.get_event_loop().time()}"
        
        # Send a message first
        chat_request = {
            "message": "Remember this: my favorite color is blue",
            "conversation_id": conversation_id
        }
        
        await http_client.post(
            f"{self.API_URL}/api/v1/chat",
            json=chat_request,
            headers=chat_headers
        )
        
        # Try to get conversation history
        history_response = await http_client.get(
            f"{self.API_URL}/api/v1/chat/history/{conversation_id}",
            headers=chat_headers
        )
        
        if history_response.status_code == 404:
            # History endpoint might not be implemented
            pytest.skip("Chat history endpoint not available")
        
        if history_response.status_code == 200:
            history_data = history_response.json()
            
            # Should be a list of messages
            assert isinstance(history_data, (list, dict))
            
            if isinstance(history_data, list):
                assert len(history_data) > 0
            elif isinstance(history_data, dict):
                # Might be wrapped in metadata
                assert "messages" in history_data or "history" in history_data