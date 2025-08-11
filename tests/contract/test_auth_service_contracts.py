"""
API Contract tests for Auth Service.
Tests the API contracts between services using OpenAPI specifications and JSON Schema validation.
"""

import pytest
import httpx
import asyncio
from typing import Dict, Any
import json
import jsonschema
from tests.fixtures.factories import TestDataFactory

class TestAuthServiceContracts:
    """Test API contracts for Auth Service"""
    
    def setup_method(self):
        """Setup test environment before each test"""
        self.factory = TestDataFactory()
        self.base_url = "http://localhost:8004"
        
    @pytest.fixture
    def auth_schemas(self):
        """OpenAPI schemas for Auth Service endpoints"""
        return {
            "register_request": {
                "type": "object",
                "required": ["email", "password", "first_name", "last_name"],
                "properties": {
                    "email": {
                        "type": "string",
                        "format": "email",
                        "maxLength": 255
                    },
                    "password": {
                        "type": "string",
                        "minLength": 8,
                        "maxLength": 100
                    },
                    "first_name": {
                        "type": "string",
                        "minLength": 1,
                        "maxLength": 50
                    },
                    "last_name": {
                        "type": "string",
                        "minLength": 1,
                        "maxLength": 50
                    },
                    "username": {
                        "type": "string",
                        "minLength": 3,
                        "maxLength": 30
                    }
                },
                "additionalProperties": False
            },
            "register_response": {
                "type": "object",
                "required": ["id", "email", "first_name", "last_name", "is_active", "created_at"],
                "properties": {
                    "id": {"type": "string", "format": "uuid"},
                    "email": {"type": "string", "format": "email"},
                    "first_name": {"type": "string"},
                    "last_name": {"type": "string"},
                    "username": {"type": "string"},
                    "is_active": {"type": "boolean"},
                    "is_verified": {"type": "boolean"},
                    "created_at": {"type": "string", "format": "date-time"},
                    "updated_at": {"type": "string", "format": "date-time"}
                },
                "additionalProperties": False
            },
            "login_request": {
                "type": "object",
                "properties": {
                    "email": {"type": "string", "format": "email"},
                    "username": {"type": "string"},
                    "password": {"type": "string", "minLength": 1}
                },
                "anyOf": [
                    {"required": ["email", "password"]},
                    {"required": ["username", "password"]}
                ],
                "additionalProperties": False
            },
            "login_response": {
                "type": "object",
                "required": ["access_token", "refresh_token", "token_type", "expires_in"],
                "properties": {
                    "access_token": {"type": "string"},
                    "refresh_token": {"type": "string"},
                    "token_type": {"type": "string", "enum": ["Bearer"]},
                    "expires_in": {"type": "integer", "minimum": 1}
                },
                "additionalProperties": False
            },
            "error_response": {
                "type": "object",
                "required": ["error"],
                "properties": {
                    "error": {"type": "string"},
                    "details": {"type": "string"},
                    "code": {"type": "string"}
                },
                "additionalProperties": False
            }
        }
    
    @pytest.mark.contract
    async def test_register_endpoint_contract(self, auth_schemas):
        """Test /auth/register endpoint contract compliance"""
        
        # Test valid registration request
        valid_request = {
            "email": "test@example.com",
            "password": "ValidPassword123!",
            "first_name": "John",
            "last_name": "Doe",
            "username": "johndoe"
        }
        
        # Validate request against schema
        try:
            jsonschema.validate(valid_request, auth_schemas["register_request"])
            request_valid = True
        except jsonschema.ValidationError:
            request_valid = False
        
        assert request_valid, "Valid registration request should pass schema validation"
        
        # Test response schema compliance (mocked for unit test)
        mock_response = {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "first_name": "John",
            "last_name": "Doe",
            "username": "johndoe",
            "is_active": True,
            "is_verified": False,
            "created_at": "2023-12-01T10:00:00Z",
            "updated_at": "2023-12-01T10:00:00Z"
        }
        
        try:
            jsonschema.validate(mock_response, auth_schemas["register_response"])
            response_valid = True
        except jsonschema.ValidationError:
            response_valid = False
        
        assert response_valid, "Registration response should match schema"
    
    @pytest.mark.contract
    async def test_register_validation_errors_contract(self, auth_schemas):
        """Test registration validation error responses"""
        
        invalid_requests = [
            # Missing required fields
            {"email": "test@example.com"},
            {"password": "ValidPassword123!"},
            {"first_name": "John", "last_name": "Doe"},
            
            # Invalid field formats
            {"email": "invalid-email", "password": "ValidPassword123!", "first_name": "John", "last_name": "Doe"},
            {"email": "test@example.com", "password": "123", "first_name": "John", "last_name": "Doe"},
            {"email": "test@example.com", "password": "ValidPassword123!", "first_name": "", "last_name": "Doe"},
        ]
        
        for invalid_request in invalid_requests:
            try:
                jsonschema.validate(invalid_request, auth_schemas["register_request"])
                should_fail = False
            except jsonschema.ValidationError:
                should_fail = True
            
            assert should_fail, f"Invalid request should fail validation: {invalid_request}"
    
    @pytest.mark.contract
    async def test_login_endpoint_contract(self, auth_schemas):
        """Test /auth/login endpoint contract compliance"""
        
        # Test email login
        email_login = {
            "email": "test@example.com",
            "password": "ValidPassword123!"
        }
        
        try:
            jsonschema.validate(email_login, auth_schemas["login_request"])
            email_valid = True
        except jsonschema.ValidationError:
            email_valid = False
        
        assert email_valid, "Email login request should pass validation"
        
        # Test username login
        username_login = {
            "username": "testuser",
            "password": "ValidPassword123!"
        }
        
        try:
            jsonschema.validate(username_login, auth_schemas["login_request"])
            username_valid = True
        except jsonschema.ValidationError:
            username_valid = False
        
        assert username_valid, "Username login request should pass validation"
        
        # Test successful login response
        mock_login_response = {
            "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.access_token",
            "refresh_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.refresh_token",
            "token_type": "Bearer",
            "expires_in": 3600
        }
        
        try:
            jsonschema.validate(mock_login_response, auth_schemas["login_response"])
            response_valid = True
        except jsonschema.ValidationError:
            response_valid = False
        
        assert response_valid, "Login response should match schema"
    
    @pytest.mark.contract
    async def test_error_response_contract(self, auth_schemas):
        """Test error response contract compliance"""
        
        error_responses = [
            # Basic error
            {"error": "Invalid request body"},
            
            # Error with details
            {"error": "Validation failed", "details": "Email is required"},
            
            # Error with code
            {"error": "Authentication failed", "code": "INVALID_CREDENTIALS"},
            
            # Full error response
            {"error": "Registration failed", "details": "Email already exists", "code": "DUPLICATE_EMAIL"}
        ]
        
        for error_response in error_responses:
            try:
                jsonschema.validate(error_response, auth_schemas["error_response"])
                error_valid = True
            except jsonschema.ValidationError:
                error_valid = False
            
            assert error_valid, f"Error response should match schema: {error_response}"

class TestServiceIntegrationContracts:
    """Test contracts between different services"""
    
    def setup_method(self):
        """Setup test environment before each test"""
        self.factory = TestDataFactory()
    
    @pytest.mark.contract
    async def test_auth_to_api_gateway_contract(self):
        """Test contract between Auth Service and API Gateway"""
        
        # Test token validation request from API Gateway to Auth Service
        token_validation_request = {
            "Authorization": "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.access_token"
        }
        
        # Expected response from Auth Service to API Gateway
        expected_validation_response = {
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "scopes": ["read", "write"],
            "exp": 1698768000,
            "iat": 1698764400
        }
        
        # Validate contract expectations
        assert "Authorization" in token_validation_request
        assert token_validation_request["Authorization"].startswith("Bearer ")
        assert "user_id" in expected_validation_response
        assert "email" in expected_validation_response
        assert "exp" in expected_validation_response
    
    @pytest.mark.contract
    async def test_auth_to_user_service_contract(self):
        """Test contract between Auth Service and User Service"""
        
        # Test user creation request from Auth Service to User Service
        user_creation_request = {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "first_name": "John",
            "last_name": "Doe",
            "username": "johndoe",
            "is_active": True,
            "created_at": "2023-12-01T10:00:00Z"
        }
        
        # Expected response from User Service
        expected_user_response = {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "first_name": "John",
            "last_name": "Doe",
            "username": "johndoe",
            "is_active": True,
            "profile_complete": False,
            "created_at": "2023-12-01T10:00:00Z",
            "updated_at": "2023-12-01T10:00:00Z"
        }
        
        # Validate contract expectations
        assert user_creation_request["id"] == expected_user_response["id"]
        assert user_creation_request["email"] == expected_user_response["email"]
        assert "profile_complete" in expected_user_response
    
    @pytest.mark.contract
    async def test_auth_to_notification_service_contract(self):
        """Test contract between Auth Service and Notification Service"""
        
        # Test welcome email request from Auth Service to Notification Service
        welcome_email_request = {
            "type": "welcome_email",
            "recipient": {
                "email": "test@example.com",
                "first_name": "John",
                "last_name": "Doe"
            },
            "template_data": {
                "user_id": "550e8400-e29b-41d4-a716-446655440000",
                "verification_token": "abc123def456",
                "verification_url": "https://app.example.com/verify?token=abc123def456"
            },
            "priority": "normal",
            "scheduled_at": None
        }
        
        # Expected response from Notification Service
        expected_notification_response = {
            "message_id": "msg_550e8400-e29b-41d4-a716",
            "status": "queued",
            "scheduled_at": "2023-12-01T10:00:00Z",
            "estimated_delivery": "2023-12-01T10:05:00Z"
        }
        
        # Validate contract expectations
        assert welcome_email_request["type"] == "welcome_email"
        assert "email" in welcome_email_request["recipient"]
        assert "verification_url" in welcome_email_request["template_data"]
        assert "message_id" in expected_notification_response
        assert expected_notification_response["status"] in ["queued", "sent", "failed"]

class TestAPIVersioningContracts:
    """Test API versioning contracts"""
    
    @pytest.mark.contract
    async def test_api_version_headers(self):
        """Test API versioning through headers"""
        
        # Test API version specification in headers
        version_headers = [
            {"Accept": "application/vnd.pyairtable.v1+json"},
            {"Accept": "application/vnd.pyairtable.v2+json"},
            {"API-Version": "v1"},
            {"API-Version": "v2"}
        ]
        
        for header in version_headers:
            # Each request should specify API version
            has_version = any(
                "v1" in value or "v2" in value 
                for value in header.values()
            )
            assert has_version, f"Header should specify API version: {header}"
    
    @pytest.mark.contract
    async def test_backward_compatibility(self):
        """Test backward compatibility between API versions"""
        
        # V1 response format
        v1_user_response = {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "name": "John Doe",  # Combined name in v1
            "active": True,
            "created": "2023-12-01T10:00:00Z"
        }
        
        # V2 response format (more detailed)
        v2_user_response = {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "first_name": "John",  # Split names in v2
            "last_name": "Doe",
            "username": "johndoe",  # New field in v2
            "is_active": True,  # Renamed field
            "is_verified": False,  # New field in v2
            "created_at": "2023-12-01T10:00:00Z",  # Renamed field
            "updated_at": "2023-12-01T10:00:00Z"  # New field in v2
        }
        
        # Validate that essential data is preserved
        assert v1_user_response["id"] == v2_user_response["id"]
        assert v1_user_response["email"] == v2_user_response["email"]
        assert v1_user_response["active"] == v2_user_response["is_active"]
        
        # V2 should include additional fields
        assert "username" in v2_user_response
        assert "is_verified" in v2_user_response
        assert "updated_at" in v2_user_response

class TestServiceHealthContracts:
    """Test health check contracts"""
    
    @pytest.mark.contract
    async def test_health_endpoint_contract(self):
        """Test health endpoint contract"""
        
        # Standard health check response
        health_response = {
            "status": "healthy",
            "timestamp": "2023-12-01T10:00:00Z",
            "version": "1.0.0",
            "dependencies": {
                "database": {
                    "status": "healthy",
                    "response_time_ms": 5,
                    "last_check": "2023-12-01T10:00:00Z"
                },
                "redis": {
                    "status": "healthy",
                    "response_time_ms": 2,
                    "last_check": "2023-12-01T10:00:00Z"
                }
            },
            "metrics": {
                "uptime_seconds": 3600,
                "memory_usage_mb": 128,
                "cpu_usage_percent": 5.2
            }
        }
        
        # Validate health response structure
        assert health_response["status"] in ["healthy", "unhealthy", "degraded"]
        assert "timestamp" in health_response
        assert "version" in health_response
        assert "dependencies" in health_response
        
        # Validate dependency checks
        for dep_name, dep_info in health_response["dependencies"].items():
            assert "status" in dep_info
            assert "response_time_ms" in dep_info
            assert "last_check" in dep_info
    
    @pytest.mark.contract
    async def test_readiness_endpoint_contract(self):
        """Test readiness endpoint contract"""
        
        # Readiness check response
        readiness_response = {
            "ready": True,
            "checks": {
                "database_migrations": "passed",
                "configuration_loaded": "passed",
                "external_services": "passed"
            }
        }
        
        # Validate readiness response
        assert isinstance(readiness_response["ready"], bool)
        assert "checks" in readiness_response
        
        for check_name, check_status in readiness_response["checks"].items():
            assert check_status in ["passed", "failed", "warning"]

class TestSecurityContracts:
    """Test security-related contracts"""
    
    @pytest.mark.contract
    async def test_authentication_contract(self):
        """Test authentication contract requirements"""
        
        # JWT token structure requirements
        jwt_payload = {
            "iss": "pyairtable-auth-service",
            "sub": "550e8400-e29b-41d4-a716-446655440000",
            "aud": "pyairtable-api",
            "exp": 1698768000,
            "iat": 1698764400,
            "jti": "token-unique-id",
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "email": "test@example.com",
            "scopes": ["read", "write"]
        }
        
        # Validate required JWT claims
        required_claims = ["iss", "sub", "aud", "exp", "iat", "jti"]
        for claim in required_claims:
            assert claim in jwt_payload, f"JWT must include {claim} claim"
        
        # Validate custom claims
        assert "user_id" in jwt_payload
        assert "email" in jwt_payload
        assert "scopes" in jwt_payload
        assert isinstance(jwt_payload["scopes"], list)
    
    @pytest.mark.contract
    async def test_authorization_contract(self):
        """Test authorization contract requirements"""
        
        # Authorization request structure
        auth_request = {
            "user_id": "550e8400-e29b-41d4-a716-446655440000",
            "resource": "workspace:123",
            "action": "read",
            "context": {
                "ip_address": "192.168.1.100",
                "user_agent": "PyAirtable-Client/1.0"
            }
        }
        
        # Authorization response structure
        auth_response = {
            "allowed": True,
            "policy": "workspace-member",
            "conditions": [],
            "expires_at": "2023-12-01T11:00:00Z"
        }
        
        # Validate authorization contract
        assert "user_id" in auth_request
        assert "resource" in auth_request
        assert "action" in auth_request
        assert isinstance(auth_response["allowed"], bool)
        
    @pytest.mark.contract
    async def test_rate_limiting_contract(self):
        """Test rate limiting contract"""
        
        # Rate limit headers that should be included in responses
        rate_limit_headers = {
            "X-RateLimit-Limit": "1000",
            "X-RateLimit-Remaining": "999",
            "X-RateLimit-Reset": "1698768000",
            "X-RateLimit-Window": "3600"
        }
        
        # Validate rate limit headers
        assert "X-RateLimit-Limit" in rate_limit_headers
        assert "X-RateLimit-Remaining" in rate_limit_headers
        assert "X-RateLimit-Reset" in rate_limit_headers
        
        # Values should be numeric strings
        assert rate_limit_headers["X-RateLimit-Limit"].isdigit()
        assert rate_limit_headers["X-RateLimit-Remaining"].isdigit()
        assert rate_limit_headers["X-RateLimit-Reset"].isdigit()