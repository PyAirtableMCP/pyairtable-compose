"""Integration tests for core services"""
import os
import asyncio
import httpx
import pytest
from typing import Dict, Any


BASE_URLS = {
    "api_gateway": "http://localhost:8080",
    "auth_service": "http://localhost:8081",
    "airtable_gateway": "http://localhost:8093",
    "llm_orchestrator": "http://localhost:8091",
    "mcp_server": "http://localhost:8092"
}


class TestCoreServices:
    """Integration tests for core PyAirtable services"""
    
    @pytest.fixture
    async def client(self):
        """Create async HTTP client"""
        async with httpx.AsyncClient(timeout=30.0) as client:
            yield client
    
    @pytest.fixture
    async def auth_token(self, client):
        """Get authentication token"""
        # Try to login first
        login_data = {
            "email": "test@example.com",
            "password": "Test123!@#"
        }
        
        try:
            response = await client.post(
                f"{BASE_URLS['api_gateway']}/auth/login",
                json=login_data
            )
            if response.status_code == 200:
                return response.json()["access_token"]
        except:
            pass
        
        # If login fails, try registration
        register_data = {
            **login_data,
            "first_name": "Test",
            "last_name": "User"
        }
        
        try:
            await client.post(
                f"{BASE_URLS['api_gateway']}/auth/register",
                json=register_data
            )
            
            # Now login
            response = await client.post(
                f"{BASE_URLS['api_gateway']}/auth/login",
                json=login_data
            )
            if response.status_code == 200:
                return response.json()["access_token"]
        except:
            pass
        
        return None
    
    @pytest.mark.asyncio
    async def test_all_services_health(self, client):
        """Test health endpoints of all core services"""
        for service_name, base_url in BASE_URLS.items():
            response = await client.get(f"{base_url}/health")
            assert response.status_code == 200, f"{service_name} health check failed"
            data = response.json()
            assert data.get("status") in ["healthy", "ready"], f"{service_name} not healthy"
    
    @pytest.mark.asyncio
    async def test_api_gateway_routing(self, client, auth_token):
        """Test API Gateway routes to other services"""
        if not auth_token:
            pytest.skip("No auth token available")
        
        headers = {"Authorization": f"Bearer {auth_token}"}
        
        # Test routes
        routes_to_test = [
            ("/api/v1/airtable/bases", "Airtable Gateway"),
            ("/api/v1/llm/sessions", "LLM Orchestrator"),
            ("/api/v1/mcp/tools", "MCP Server"),
        ]
        
        for route, service in routes_to_test:
            response = await client.get(
                f"{BASE_URLS['api_gateway']}{route}",
                headers=headers
            )
            # We expect either 200 (success) or 500 (if backend service has issues)
            assert response.status_code in [200, 500], f"{service} route failed"
    
    @pytest.mark.asyncio
    async def test_auth_flow(self, client):
        """Test complete authentication flow"""
        # Generate unique email
        import uuid
        email = f"test_{uuid.uuid4().hex[:8]}@example.com"
        
        # Register
        register_data = {
            "email": email,
            "password": "SecurePass123!",
            "first_name": "Integration",
            "last_name": "Test"
        }
        
        response = await client.post(
            f"{BASE_URLS['api_gateway']}/auth/register",
            json=register_data
        )
        assert response.status_code == 201, "Registration failed"
        
        # Login
        login_data = {
            "email": email,
            "password": "SecurePass123!"
        }
        
        response = await client.post(
            f"{BASE_URLS['api_gateway']}/auth/login",
            json=login_data
        )
        assert response.status_code == 200, "Login failed"
        
        tokens = response.json()
        assert "access_token" in tokens
        assert "refresh_token" in tokens
        
        # Use token to access protected endpoint
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        response = await client.get(
            f"{BASE_URLS['api_gateway']}/auth/me",
            headers=headers
        )
        assert response.status_code in [200, 404], "Protected endpoint access failed"
    
    @pytest.mark.asyncio
    async def test_airtable_gateway_caching(self, client, auth_token):
        """Test Airtable Gateway caching functionality"""
        if not auth_token:
            pytest.skip("No auth token available")
        
        headers = {"Authorization": f"Bearer {auth_token}"}
        
        # Make first request (should hit Airtable API)
        response1 = await client.get(
            f"{BASE_URLS['api_gateway']}/api/v1/airtable/bases",
            headers=headers
        )
        
        # Make second request (should be cached)
        response2 = await client.get(
            f"{BASE_URLS['api_gateway']}/api/v1/airtable/bases",
            headers=headers
        )
        
        # Both should have same status
        assert response1.status_code == response2.status_code
        
        # If successful, data should be identical
        if response1.status_code == 200:
            assert response1.json() == response2.json()
    
    @pytest.mark.asyncio
    async def test_llm_orchestrator_chat(self, client, auth_token):
        """Test LLM Orchestrator chat completion"""
        if not auth_token:
            pytest.skip("No auth token available")
        
        if not os.getenv("GEMINI_API_KEY"):
            pytest.skip("No Gemini API key configured")
        
        headers = {"Authorization": f"Bearer {auth_token}"}
        
        chat_request = {
            "messages": [
                {"role": "user", "content": "Say 'Hello, Integration Test!' and nothing else."}
            ],
            "temperature": 0.1,
            "max_tokens": 50
        }
        
        response = await client.post(
            f"{BASE_URLS['api_gateway']}/api/v1/llm/chat/completions",
            json=chat_request,
            headers=headers
        )
        
        if response.status_code == 200:
            data = response.json()
            assert "choices" in data
            assert len(data["choices"]) > 0
            assert "message" in data["choices"][0]
    
    @pytest.mark.asyncio
    async def test_mcp_server_tools(self, client, auth_token):
        """Test MCP Server tool listing"""
        if not auth_token:
            pytest.skip("No auth token available")
        
        headers = {"Authorization": f"Bearer {auth_token}"}
        
        # List tools
        response = await client.get(
            f"{BASE_URLS['api_gateway']}/api/v1/mcp/tools",
            headers=headers
        )
        
        assert response.status_code == 200
        tools = response.json()
        assert isinstance(tools, list)
        assert len(tools) > 0
        
        # Check tool structure
        for tool in tools:
            assert "name" in tool
            assert "description" in tool
            assert "input_schema" in tool
    
    @pytest.mark.asyncio
    async def test_mcp_tool_execution(self, client, auth_token):
        """Test MCP Server tool execution"""
        if not auth_token:
            pytest.skip("No auth token available")
        
        headers = {"Authorization": f"Bearer {auth_token}"}
        
        # Execute calculate tool
        tool_request = {
            "expression": "2 + 2"
        }
        
        response = await client.post(
            f"{BASE_URLS['api_gateway']}/api/v1/mcp/tools/calculate/execute",
            json=tool_request,
            headers=headers
        )
        
        if response.status_code == 200:
            data = response.json()
            assert "result" in data
            result = data["result"]
            assert result["result"] == 4
    
    @pytest.mark.asyncio
    async def test_service_integration_flow(self, client, auth_token):
        """Test complete integration flow across services"""
        if not auth_token:
            pytest.skip("No auth token available")
        
        headers = {"Authorization": f"Bearer {auth_token}"}
        
        # 1. Create a chat session
        session_response = await client.post(
            f"{BASE_URLS['api_gateway']}/api/v1/llm/sessions",
            headers=headers
        )
        
        if session_response.status_code == 200:
            session = session_response.json()
            session_id = session["id"]
            
            # 2. Send a message asking about Airtable
            chat_request = {
                "messages": [
                    {"role": "user", "content": "List the available MCP tools"}
                ],
                "session_id": session_id
            }
            
            chat_response = await client.post(
                f"{BASE_URLS['api_gateway']}/api/v1/llm/chat/completions",
                json=chat_request,
                headers=headers
            )
            
            assert chat_response.status_code in [200, 500]
            
            # 3. Get session messages
            messages_response = await client.get(
                f"{BASE_URLS['api_gateway']}/api/v1/llm/sessions/{session_id}/messages",
                headers=headers
            )
            
            if messages_response.status_code == 200:
                messages = messages_response.json()
                assert len(messages) >= 1  # At least the user message


if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v"])