"""
Contract tests for Auth Service API.
These tests verify the contract between consumers and the auth service.
"""

import pytest
import httpx
from pact import Consumer, Provider
from pact_setup import ContractTestHelper, APIContractPatterns


class TestAuthServiceContract:
    """Contract tests for Auth Service."""
    
    @pytest.mark.asyncio
    async def test_register_user_success_contract(self, auth_service_consumer_pact):
        """Test user registration success contract."""
        # Define the expected interaction
        (auth_service_consumer_pact
         .given("no user exists with email test@example.com")
         .upon_receiving("a request to register a new user")
         .with_request(
             method="POST",
             path="/api/v1/auth/register",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "email": "test@example.com",
                 "password": "SecurePassword123!",
                 "name": "Test User",
                 "tenant_id": "tenant-123"
             }
         )
         .will_respond_with(
             status=201,
             headers={"Content-Type": "application/json"},
             body={
                 "data": {
                     "user": APIContractPatterns.USER_SCHEMA,
                     "tokens": APIContractPatterns.TOKEN_RESPONSE_SCHEMA
                 }
             }
         ))
        
        # Execute the test
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/register",
                    json={
                        "email": "test@example.com",
                        "password": "SecurePassword123!",
                        "name": "Test User", 
                        "tenant_id": "tenant-123"
                    },
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 201
                data = response.json()
                assert "data" in data
                assert "user" in data["data"]
                assert "tokens" in data["data"]
                assert data["data"]["user"]["email"] == "test@example.com"
                assert data["data"]["user"]["name"] == "Test User"
    
    @pytest.mark.asyncio
    async def test_register_user_email_exists_contract(self, auth_service_consumer_pact):
        """Test user registration with existing email contract."""
        (auth_service_consumer_pact
         .given("user exists with email existing@example.com")
         .upon_receiving("a request to register with existing email")
         .with_request(
             method="POST",
             path="/api/v1/auth/register",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "email": "existing@example.com",
                 "password": "SecurePassword123!",
                 "name": "Test User",
                 "tenant_id": "tenant-123"
             }
         )
         .will_respond_with(
             status=409,
             headers={"Content-Type": "application/json"},
             body={
                 "error": {
                     "code": 409,
                     "message": "Email already registered",
                     "timestamp": "@type:string"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/register",
                    json={
                        "email": "existing@example.com",
                        "password": "SecurePassword123!",
                        "name": "Test User",
                        "tenant_id": "tenant-123"
                    },
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 409
                data = response.json()
                assert "error" in data
                assert data["error"]["code"] == 409
                assert "already registered" in data["error"]["message"].lower()
    
    @pytest.mark.asyncio
    async def test_login_success_contract(self, auth_service_consumer_pact):
        """Test successful login contract."""
        (auth_service_consumer_pact
         .given("user exists with email test@example.com and password is correct")
         .upon_receiving("a request to login with valid credentials")
         .with_request(
             method="POST",
             path="/api/v1/auth/login",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "email": "test@example.com",
                 "password": "SecurePassword123!"
             }
         )
         .will_respond_with(
             status=200,
             headers={"Content-Type": "application/json"},
             body={
                 "data": {
                     "user": APIContractPatterns.USER_SCHEMA,
                     "tokens": APIContractPatterns.TOKEN_RESPONSE_SCHEMA
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/login",
                    json={
                        "email": "test@example.com",
                        "password": "SecurePassword123!"
                    },
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 200
                data = response.json()
                assert "data" in data
                assert "user" in data["data"]
                assert "tokens" in data["data"]
    
    @pytest.mark.asyncio
    async def test_login_invalid_credentials_contract(self, auth_service_consumer_pact):
        """Test login with invalid credentials contract."""
        (auth_service_consumer_pact
         .given("user exists with email test@example.com")
         .upon_receiving("a request to login with invalid password")
         .with_request(
             method="POST",
             path="/api/v1/auth/login",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "email": "test@example.com",
                 "password": "WrongPassword"
             }
         )
         .will_respond_with(
             status=401,
             headers={"Content-Type": "application/json"},
             body={
                 "error": {
                     "code": 401,
                     "message": "Invalid credentials",
                     "timestamp": "@type:string"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/login",
                    json={
                        "email": "test@example.com",
                        "password": "WrongPassword"
                    },
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 401
                data = response.json()
                assert "error" in data
                assert data["error"]["code"] == 401
    
    @pytest.mark.asyncio
    async def test_refresh_token_success_contract(self, auth_service_consumer_pact):
        """Test token refresh success contract."""
        (auth_service_consumer_pact
         .given("valid refresh token exists")
         .upon_receiving("a request to refresh token")
         .with_request(
             method="POST",
             path="/api/v1/auth/refresh",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "refresh_token": "valid-refresh-token"
             }
         )
         .will_respond_with(
             status=200,
             headers={"Content-Type": "application/json"},
             body={
                 "data": {
                     "tokens": APIContractPatterns.TOKEN_RESPONSE_SCHEMA
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/refresh",
                    json={"refresh_token": "valid-refresh-token"},
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 200
                data = response.json()
                assert "data" in data
                assert "tokens" in data["data"]
    
    @pytest.mark.asyncio
    async def test_refresh_token_invalid_contract(self, auth_service_consumer_pact):
        """Test token refresh with invalid token contract."""
        (auth_service_consumer_pact
         .given("refresh token is invalid or expired")
         .upon_receiving("a request to refresh token with invalid token")
         .with_request(
             method="POST",
             path="/api/v1/auth/refresh",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "refresh_token": "invalid-refresh-token"
             }
         )
         .will_respond_with(
             status=401,
             headers={"Content-Type": "application/json"},
             body={
                 "error": {
                     "code": 401,
                     "message": "Invalid or expired refresh token",
                     "timestamp": "@type:string"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/refresh",
                    json={"refresh_token": "invalid-refresh-token"},
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 401
    
    @pytest.mark.asyncio
    async def test_logout_success_contract(self, auth_service_consumer_pact):
        """Test logout success contract."""
        (auth_service_consumer_pact
         .given("user is authenticated")
         .upon_receiving("a request to logout")
         .with_request(
             method="POST",
             path="/api/v1/auth/logout",
             headers=ContractTestHelper.auth_headers("valid-access-token"),
             body={
                 "refresh_token": "valid-refresh-token"
             }
         )
         .will_respond_with(
             status=200,
             headers={"Content-Type": "application/json"},
             body={
                 "data": {
                     "message": "Successfully logged out"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/logout",
                    json={"refresh_token": "valid-refresh-token"},
                    headers=ContractTestHelper.auth_headers("valid-access-token")
                )
                
                assert response.status_code == 200
                data = response.json()
                assert "data" in data
                assert "message" in data["data"]
    
    @pytest.mark.asyncio
    async def test_get_current_user_contract(self, auth_service_consumer_pact):
        """Test get current user contract."""
        (auth_service_consumer_pact
         .given("user is authenticated")
         .upon_receiving("a request to get current user")
         .with_request(
             method="GET",
             path="/api/v1/auth/me",
             headers=ContractTestHelper.auth_headers("valid-access-token")
         )
         .will_respond_with(
             status=200,
             headers={"Content-Type": "application/json"},
             body={
                 "data": {
                     "user": APIContractPatterns.USER_SCHEMA
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.get(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/me",
                    headers=ContractTestHelper.auth_headers("valid-access-token")
                )
                
                assert response.status_code == 200
                data = response.json()
                assert "data" in data
                assert "user" in data["data"]
    
    @pytest.mark.asyncio
    async def test_get_current_user_unauthorized_contract(self, auth_service_consumer_pact):
        """Test get current user unauthorized contract."""
        (auth_service_consumer_pact
         .given("no authentication provided")
         .upon_receiving("a request to get current user without auth")
         .with_request(
             method="GET",
             path="/api/v1/auth/me",
             headers=ContractTestHelper.standard_headers()
         )
         .will_respond_with(
             status=401,
             headers={"Content-Type": "application/json"},
             body={
                 "error": {
                     "code": 401,
                     "message": "Authentication required",
                     "timestamp": "@type:string"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.get(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/me",
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 401
    
    @pytest.mark.asyncio
    async def test_change_password_success_contract(self, auth_service_consumer_pact):
        """Test change password success contract."""
        (auth_service_consumer_pact
         .given("user is authenticated")
         .upon_receiving("a request to change password")
         .with_request(
             method="PUT",
             path="/api/v1/auth/password",
             headers=ContractTestHelper.auth_headers("valid-access-token"),
             body={
                 "current_password": "CurrentPassword123!",
                 "new_password": "NewSecurePassword123!"
             }
         )
         .will_respond_with(
             status=200,
             headers={"Content-Type": "application/json"},
             body={
                 "data": {
                     "message": "Password updated successfully"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.put(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/password",
                    json={
                        "current_password": "CurrentPassword123!",
                        "new_password": "NewSecurePassword123!"
                    },
                    headers=ContractTestHelper.auth_headers("valid-access-token")
                )
                
                assert response.status_code == 200
                data = response.json()
                assert "data" in data
                assert "message" in data["data"]
    
    @pytest.mark.asyncio
    async def test_validation_error_contract(self, auth_service_consumer_pact):
        """Test validation error contract."""
        (auth_service_consumer_pact
         .given("no user requirements")
         .upon_receiving("a request with invalid data")
         .with_request(
             method="POST",
             path="/api/v1/auth/register",
             headers=ContractTestHelper.standard_headers(),
             body={
                 "email": "invalid-email",
                 "password": "weak",
                 "name": "",
                 "tenant_id": ""
             }
         )
         .will_respond_with(
             status=422,
             headers={"Content-Type": "application/json"},
             body={
                 "error": {
                     "code": 422,
                     "message": "Validation failed",
                     "details": [
                         {
                             "field": "@type:string",
                             "message": "@type:string"
                         }
                     ],
                     "timestamp": "@type:string"
                 }
             }
         ))
        
        async with httpx.AsyncClient() as client:
            with auth_service_consumer_pact:
                response = await client.post(
                    f"{auth_service_consumer_pact.uri}/api/v1/auth/register",
                    json={
                        "email": "invalid-email",
                        "password": "weak",
                        "name": "",
                        "tenant_id": ""
                    },
                    headers=ContractTestHelper.standard_headers()
                )
                
                assert response.status_code == 422
                data = response.json()
                assert "error" in data
                assert data["error"]["code"] == 422
                assert "details" in data["error"]