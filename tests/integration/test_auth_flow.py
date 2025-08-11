"""
Integration tests for authentication flow across the microservices architecture.

Tests:
1. User registration via API Gateway -> Platform Services
2. User login and JWT token validation  
3. JWT token validation across services
4. Session management with Redis
5. Authentication middleware protection
"""

import pytest
import asyncio
import httpx
import json
from typing import Dict, Any
from datetime import datetime, timedelta


class TestAuthenticationFlow:
    """Integration tests for the complete authentication flow"""
    
    BASE_URL = "http://localhost:8000"  # API Gateway
    PLATFORM_URL = "http://localhost:8007"  # Platform Services Direct
    AIRTABLE_URL = "http://localhost:8002"  # Airtable Gateway
    AI_URL = "http://localhost:8001"  # AI Processing Service
    
    @pytest.fixture
    async def http_client(self):
        """HTTP client for making requests"""
        async with httpx.AsyncClient(timeout=30.0, follow_redirects=True) as client:
            yield client
    
    @pytest.fixture
    def test_user_data(self):
        """Test user data for registration"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        return {
            "name": f"Test User {timestamp}",
            "email": f"test_{timestamp}@example.com",
            "password": "TestPassword123!",
            "confirm_password": "TestPassword123!"
        }
    
    @pytest.fixture
    def auth_headers(self):
        """Headers for API authentication"""
        return {
            "Content-Type": "application/json",
            "Accept": "application/json"
        }

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_user_registration_flow(self, http_client, test_user_data, auth_headers):
        """Test complete user registration flow through API Gateway"""
        
        # Register new user via API Gateway
        registration_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user_data,
            headers=auth_headers
        )
        
        assert registration_response.status_code == 201, f"Registration failed: {registration_response.text}"
        registration_data = registration_response.json()
        
        assert "message" in registration_data
        assert "user" in registration_data
        assert registration_data["user"]["email"] == test_user_data["email"]
        assert registration_data["user"]["name"] == test_user_data["name"]
        assert "id" in registration_data["user"]
        
        # Verify user was created by attempting login
        login_data = {
            "email": test_user_data["email"],
            "password": test_user_data["password"]
        }
        
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json=login_data,
            headers=auth_headers
        )
        
        assert login_response.status_code == 200, f"Login after registration failed: {login_response.text}"
        login_result = login_response.json()
        
        assert "access_token" in login_result
        assert "refresh_token" in login_result
        assert "user" in login_result
        assert login_result["user"]["email"] == test_user_data["email"]

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_user_login_and_jwt_validation(self, http_client, test_user_data, auth_headers):
        """Test user login and JWT token validation across services"""
        
        # First register the user
        await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user_data,
            headers=auth_headers
        )
        
        # Login to get JWT token
        login_data = {
            "email": test_user_data["email"],
            "password": test_user_data["password"]
        }
        
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json=login_data,
            headers=auth_headers
        )
        
        assert login_response.status_code == 200
        login_result = login_response.json()
        
        access_token = login_result["access_token"]
        user_id = login_result["user"]["id"]
        
        # Test JWT validation by accessing protected endpoints
        protected_headers = {
            **auth_headers,
            "Authorization": f"Bearer {access_token}"
        }
        
        # Test user profile endpoint via API Gateway
        profile_response = await http_client.get(
            f"{self.BASE_URL}/api/v1/users/profile",
            headers=protected_headers
        )
        
        assert profile_response.status_code == 200
        profile_data = profile_response.json()
        assert profile_data["email"] == test_user_data["email"]
        assert profile_data["id"] == user_id

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_jwt_token_refresh_flow(self, http_client, test_user_data, auth_headers):
        """Test JWT refresh token functionality"""
        
        # Register and login user
        await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user_data,
            headers=auth_headers
        )
        
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json={
                "email": test_user_data["email"],
                "password": test_user_data["password"]
            },
            headers=auth_headers
        )
        
        login_result = login_response.json()
        refresh_token = login_result["refresh_token"]
        
        # Use refresh token to get new access token
        refresh_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/refresh",
            json={"refresh_token": refresh_token},
            headers=auth_headers
        )
        
        assert refresh_response.status_code == 200
        refresh_result = refresh_response.json()
        
        assert "access_token" in refresh_result
        assert "refresh_token" in refresh_result
        
        # Verify new token works
        new_token = refresh_result["access_token"]
        protected_headers = {
            **auth_headers,
            "Authorization": f"Bearer {new_token}"
        }
        
        profile_response = await http_client.get(
            f"{self.BASE_URL}/api/v1/users/profile",
            headers=protected_headers
        )
        
        assert profile_response.status_code == 200

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_authentication_middleware_protection(self, http_client, auth_headers):
        """Test that protected endpoints require authentication"""
        
        # Try to access protected endpoint without token
        response = await http_client.get(
            f"{self.BASE_URL}/api/v1/users/profile",
            headers=auth_headers
        )
        
        assert response.status_code in [401, 403]  # Should be unauthorized
        
        # Try with invalid token
        invalid_headers = {
            **auth_headers,
            "Authorization": "Bearer invalid-token"
        }
        
        response = await http_client.get(
            f"{self.BASE_URL}/api/v1/users/profile", 
            headers=invalid_headers
        )
        
        assert response.status_code in [401, 403]

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_logout_flow(self, http_client, test_user_data, auth_headers):
        """Test user logout and token invalidation"""
        
        # Register and login user
        await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user_data,
            headers=auth_headers
        )
        
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json={
                "email": test_user_data["email"],
                "password": test_user_data["password"]
            },
            headers=auth_headers
        )
        
        login_result = login_response.json()
        access_token = login_result["access_token"]
        
        protected_headers = {
            **auth_headers,
            "Authorization": f"Bearer {access_token}"
        }
        
        # Verify token works before logout
        profile_response = await http_client.get(
            f"{self.BASE_URL}/api/v1/users/profile",
            headers=protected_headers
        )
        assert profile_response.status_code == 200
        
        # Logout
        logout_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/logout",
            headers=protected_headers
        )
        
        assert logout_response.status_code == 200
        
        # Verify token no longer works after logout
        profile_response = await http_client.get(
            f"{self.BASE_URL}/api/v1/users/profile",
            headers=protected_headers
        )
        assert profile_response.status_code in [401, 403]

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_cross_service_authentication(self, http_client, test_user_data, auth_headers):
        """Test that JWT tokens work across different microservices"""
        
        # Register and login user
        await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user_data,
            headers=auth_headers
        )
        
        login_response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json={
                "email": test_user_data["email"],
                "password": test_user_data["password"]
            },
            headers=auth_headers
        )
        
        login_result = login_response.json()
        access_token = login_result["access_token"]
        
        protected_headers = {
            **auth_headers,
            "Authorization": f"Bearer {access_token}"
        }
        
        # Test authentication works for different services via API Gateway
        services_to_test = [
            f"{self.BASE_URL}/api/v1/users/profile",  # Platform Services
            f"{self.BASE_URL}/api/v1/analytics/events",  # Platform Services Analytics
        ]
        
        for endpoint in services_to_test:
            response = await http_client.get(endpoint, headers=protected_headers)
            # Should be authenticated (200) or have proper business logic response
            assert response.status_code not in [401, 403], f"Authentication failed for {endpoint}"

    @pytest.mark.integration
    @pytest.mark.auth
    async def test_invalid_credentials(self, http_client, auth_headers):
        """Test login with invalid credentials"""
        
        invalid_login_data = {
            "email": "nonexistent@example.com",
            "password": "wrongpassword"
        }
        
        response = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/login",
            json=invalid_login_data,
            headers=auth_headers
        )
        
        assert response.status_code == 401
        error_data = response.json()
        assert "error" in error_data

    @pytest.mark.integration
    @pytest.mark.auth  
    async def test_duplicate_registration(self, http_client, test_user_data, auth_headers):
        """Test that duplicate email registration is prevented"""
        
        # Register user first time
        response1 = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register",
            json=test_user_data,
            headers=auth_headers
        )
        assert response1.status_code == 201
        
        # Try to register same email again
        response2 = await http_client.post(
            f"{self.BASE_URL}/api/v1/auth/register", 
            json=test_user_data,
            headers=auth_headers
        )
        
        assert response2.status_code == 400  # Should fail
        error_data = response2.json()
        assert "error" in error_data