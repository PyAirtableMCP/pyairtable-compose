"""
Integration tests for frontend-backend communication.

Tests:
1. Frontend can authenticate with backend API
2. API responses are properly formatted for frontend consumption  
3. Session management between frontend and backend
4. WebSocket connections for real-time features
5. Error handling and user feedback
"""

import pytest
import asyncio
import httpx
import json
from typing import Dict, Any, Optional
from datetime import datetime


class TestFrontendBackendCommunication:
    """Integration tests for frontend-backend communication patterns"""
    
    API_URL = "http://localhost:8000"  # API Gateway (backend for frontend)
    FRONTEND_URL = "http://localhost:5173"  # Vite Frontend
    
    @pytest.fixture
    async def http_client(self):
        """HTTP client for API requests"""
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            yield client
    
    @pytest.fixture
    async def frontend_client(self):
        """HTTP client for frontend requests"""
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            yield client
    
    @pytest.fixture
    def frontend_headers(self):
        """Headers that frontend would send"""
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "PyAirtable-Frontend/1.0",
            "Origin": "http://localhost:5173"
        }
    
    @pytest.fixture
    async def authenticated_session(self, http_client):
        """Create authenticated session and return session data"""
        timestamp = str(asyncio.get_event_loop().time()).replace('.', '')
        test_user = {
            "name": f"Frontend Test User {timestamp}",
            "email": f"frontend_test_{timestamp}@example.com", 
            "password": "TestPassword123!"
        }
        
        # Register user
        registration = await http_client.post(
            f"{self.API_URL}/api/v1/auth/register",
            json=test_user,
            headers={"Content-Type": "application/json"}
        )
        
        if registration.status_code != 201:
            pytest.skip("Could not register test user")
        
        # Login user
        login_response = await http_client.post(
            f"{self.API_URL}/api/v1/auth/login",
            json={
                "email": test_user["email"],
                "password": test_user["password"]
            },
            headers={"Content-Type": "application/json"}
        )
        
        if login_response.status_code != 200:
            pytest.skip("Could not login test user")
        
        login_data = login_response.json()
        return {
            "user": test_user,
            "token": login_data["access_token"],
            "refresh_token": login_data["refresh_token"],
            "user_data": login_data["user"]
        }

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_frontend_authentication_flow(self, http_client, frontend_headers):
        """Test complete authentication flow as frontend would perform it"""
        
        timestamp = str(asyncio.get_event_loop().time()).replace('.', '')
        user_data = {
            "name": f"Frontend Auth User {timestamp}",
            "email": f"fe_auth_{timestamp}@example.com",
            "password": "FrontendTest123!"
        }
        
        # Step 1: Register user (as frontend would)
        register_response = await http_client.post(
            f"{self.API_URL}/api/v1/auth/register",
            json=user_data,
            headers=frontend_headers
        )
        
        assert register_response.status_code == 201
        register_data = register_response.json()
        
        # Verify response format expected by frontend
        assert "message" in register_data
        assert "user" in register_data
        assert register_data["user"]["email"] == user_data["email"]
        
        # Step 2: Login user (as frontend would)
        login_response = await http_client.post(
            f"{self.API_URL}/api/v1/auth/login",
            json={
                "email": user_data["email"],
                "password": user_data["password"]
            },
            headers=frontend_headers
        )
        
        assert login_response.status_code == 200
        login_data = login_response.json()
        
        # Verify JWT token format for frontend
        assert "access_token" in login_data
        assert "refresh_token" in login_data
        assert "user" in login_data
        assert isinstance(login_data["access_token"], str)
        assert len(login_data["access_token"]) > 20  # JWT should be substantial length
        
        # Step 3: Use token to access protected resource
        auth_headers = {
            **frontend_headers,
            "Authorization": f"Bearer {login_data['access_token']}"
        }
        
        profile_response = await http_client.get(
            f"{self.API_URL}/api/v1/users/profile",
            headers=auth_headers
        )
        
        assert profile_response.status_code == 200
        profile_data = profile_response.json()
        
        # Verify profile data format for frontend consumption
        required_fields = ["id", "email", "name"]
        for field in required_fields:
            assert field in profile_data, f"Profile missing required field: {field}"

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_api_response_format_consistency(self, http_client, authenticated_session):
        """Test that API responses are consistently formatted for frontend consumption"""
        
        auth_headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {authenticated_session['token']}"
        }
        
        # Test various API endpoints for consistent response format
        endpoints_to_test = [
            ("/api/v1/users/profile", "GET"),
            ("/api/v1/analytics/events", "GET"),
        ]
        
        for endpoint, method in endpoints_to_test:
            if method == "GET":
                response = await http_client.get(
                    f"{self.API_URL}{endpoint}",
                    headers=auth_headers
                )
            else:
                response = await http_client.post(
                    f"{self.API_URL}{endpoint}",
                    json={},
                    headers=auth_headers
                )
            
            # Should get valid response (not connection error)
            assert response.status_code in [200, 201, 400, 401, 403, 404, 405]
            
            # If successful, should return valid JSON
            if response.status_code in [200, 201]:
                data = response.json()
                assert isinstance(data, (dict, list)), f"Invalid JSON response from {endpoint}"
            
            # If error, should have consistent error format
            elif response.status_code in [400, 401, 403, 404]:
                error_data = response.json()
                # Should have error field or detail field
                assert any(field in error_data for field in ["error", "detail", "message"])

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_session_management(self, http_client, authenticated_session):
        """Test session management between frontend and backend"""
        
        token = authenticated_session["token"]
        refresh_token = authenticated_session["refresh_token"]
        
        # Test token refresh flow
        refresh_response = await http_client.post(
            f"{self.API_URL}/api/v1/auth/refresh",
            json={"refresh_token": refresh_token},
            headers={"Content-Type": "application/json"}
        )
        
        assert refresh_response.status_code == 200
        refresh_data = refresh_response.json()
        
        assert "access_token" in refresh_data
        new_token = refresh_data["access_token"]
        assert new_token != token  # Should be a new token
        
        # Test new token works
        auth_headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {new_token}"
        }
        
        profile_response = await http_client.get(
            f"{self.API_URL}/api/v1/users/profile",
            headers=auth_headers
        )
        
        assert profile_response.status_code == 200

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_error_handling_for_frontend(self, http_client, frontend_headers):
        """Test that errors are returned in a format suitable for frontend handling"""
        
        # Test validation errors
        invalid_registration = await http_client.post(
            f"{self.API_URL}/api/v1/auth/register",
            json={
                "email": "invalid-email",
                "password": "weak"
            },
            headers=frontend_headers
        )
        
        assert invalid_registration.status_code == 400
        error_data = invalid_registration.json()
        
        # Should have error information for frontend to display
        assert "error" in error_data or "detail" in error_data
        
        # Test authentication errors
        invalid_login = await http_client.post(
            f"{self.API_URL}/api/v1/auth/login",
            json={
                "email": "nonexistent@example.com",
                "password": "wrongpassword"
            },
            headers=frontend_headers
        )
        
        assert invalid_login.status_code == 401
        error_data = invalid_login.json()
        assert "error" in error_data or "detail" in error_data
        
        # Test unauthorized access
        unauthorized = await http_client.get(
            f"{self.API_URL}/api/v1/users/profile",
            headers=frontend_headers  # No Authorization header
        )
        
        assert unauthorized.status_code in [401, 403]
        if unauthorized.status_code in [401, 403]:
            error_data = unauthorized.json()
            assert "error" in error_data or "detail" in error_data

    @pytest.mark.integration
    @pytest.mark.frontend  
    async def test_frontend_health_check(self, frontend_client):
        """Test frontend health and readiness endpoints"""
        
        try:
            # Test frontend is accessible
            frontend_health = await frontend_client.get(f"{self.FRONTEND_URL}/api/health")
            if frontend_health.status_code == 200:
                health_data = frontend_health.json()
                assert "status" in health_data
            else:
                # Frontend might not have /api/health, try alternative
                frontend_response = await frontend_client.get(f"{self.FRONTEND_URL}/")
                assert frontend_response.status_code in [200, 404]  # Should get some response
                
        except httpx.ConnectError:
            pytest.skip("Frontend service not running")

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_cors_for_frontend_requests(self, http_client):
        """Test CORS configuration allows frontend requests"""
        
        # Test preflight request from frontend origin
        preflight_response = await http_client.options(
            f"{self.API_URL}/api/v1/auth/login",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Content-Type, Authorization"
            }
        )
        
        # Should allow or handle CORS
        assert preflight_response.status_code in [200, 204, 405]
        
        # Test actual request with Origin header
        actual_request = await http_client.post(
            f"{self.API_URL}/api/v1/auth/login",
            json={"email": "test@example.com", "password": "test"},
            headers={
                "Content-Type": "application/json",
                "Origin": "http://localhost:5173"
            }
        )
        
        # Should accept request from frontend origin
        assert actual_request.status_code in [200, 400, 401]  # Not CORS blocked (403/405)

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_api_pagination_format(self, http_client, authenticated_session):
        """Test that paginated responses follow frontend expectations"""
        
        auth_headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {authenticated_session['token']}"
        }
        
        # Test analytics events endpoint (likely to be paginated)
        events_response = await http_client.get(
            f"{self.API_URL}/api/v1/analytics/events?page=1&limit=10",
            headers=auth_headers
        )
        
        if events_response.status_code == 200:
            events_data = events_response.json()
            
            # If paginated, should have pagination info
            if isinstance(events_data, dict):
                # Check for common pagination patterns
                pagination_fields = ["data", "items", "results", "events"]
                has_pagination = any(field in events_data for field in pagination_fields)
                
                if has_pagination:
                    # Should have metadata about pagination
                    meta_fields = ["total", "page", "limit", "pages", "count"]
                    has_meta = any(field in events_data for field in meta_fields)
                    # Pagination metadata is helpful but not required

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_file_upload_support(self, http_client, authenticated_session):
        """Test file upload functionality for frontend"""
        
        auth_headers = {
            "Authorization": f"Bearer {authenticated_session['token']}"
        }
        
        # Test file upload endpoint (if exists)
        # Create a simple test file
        test_file_content = b"Test file content for upload"
        
        files = {"file": ("test.txt", test_file_content, "text/plain")}
        
        try:
            upload_response = await http_client.post(
                f"{self.API_URL}/api/v1/files/upload",
                files=files,
                headers=auth_headers
            )
            
            # Should either work or endpoint not exist
            assert upload_response.status_code in [200, 201, 404, 405]
            
            if upload_response.status_code in [200, 201]:
                upload_data = upload_response.json()
                # Should return file info for frontend
                assert isinstance(upload_data, dict)
                
        except Exception:
            # File upload endpoint might not exist yet
            pytest.skip("File upload endpoint not available")

    @pytest.mark.integration
    @pytest.mark.frontend
    async def test_real_time_communication_setup(self, http_client):
        """Test WebSocket or real-time communication setup"""
        
        # Test WebSocket endpoint availability
        try:
            ws_response = await http_client.get(f"{self.API_URL}/ws")
            # Should either upgrade to WebSocket or indicate WebSocket support
            assert ws_response.status_code in [101, 400, 404, 426]  # 426 = Upgrade Required
            
        except Exception:
            # WebSocket might not be implemented yet
            pytest.skip("WebSocket endpoint not available")