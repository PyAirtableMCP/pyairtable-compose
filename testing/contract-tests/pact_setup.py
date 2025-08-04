"""
Pact contract testing setup for PyAirtable microservices.
This module provides utilities for consumer-driven contract testing.
"""

import json
import os
from typing import Dict, Any, Optional
from pact import Consumer, Provider, Pact
from pact.verifier import Verifier
import httpx
import pytest
from pathlib import Path


class PactTestFramework:
    """Framework for managing Pact contract tests."""
    
    def __init__(self, pact_dir: str = "./pacts"):
        """Initialize the Pact testing framework."""
        self.pact_dir = Path(pact_dir)
        self.pact_dir.mkdir(exist_ok=True)
        self.pacts: Dict[str, Pact] = {}
        
    def create_consumer_pact(self, consumer: str, provider: str, host: str = "localhost", port: int = 8080) -> Pact:
        """Create a new consumer pact."""
        pact_key = f"{consumer}-{provider}"
        
        if pact_key not in self.pacts:
            self.pacts[pact_key] = Pact(
                consumer=Consumer(consumer),
                provider=Provider(provider),
                host_name=host,
                port=port,
                pact_dir=str(self.pact_dir)
            )
        
        return self.pacts[pact_key]
    
    async def verify_provider_contracts(self, provider_url: str, provider_name: str) -> bool:
        """Verify provider contracts against pact files."""
        pact_files = list(self.pact_dir.glob(f"*-{provider_name}.json"))
        
        if not pact_files:
            print(f"No pact files found for provider {provider_name}")
            return True
        
        verifier = Verifier(provider=provider_name, provider_base_url=provider_url)
        
        success = True
        for pact_file in pact_files:
            try:
                # Load pact file
                with open(pact_file) as f:
                    pact_content = json.load(f)
                
                # Verify each interaction
                for interaction in pact_content.get("interactions", []):
                    result = await self._verify_interaction(provider_url, interaction)
                    if not result:
                        success = False
                        print(f"Failed to verify interaction: {interaction.get('description')}")
                
            except Exception as e:
                print(f"Error verifying {pact_file}: {e}")
                success = False
        
        return success
    
    async def _verify_interaction(self, provider_url: str, interaction: Dict[str, Any]) -> bool:
        """Verify a single interaction against the provider."""
        request = interaction.get("request", {})
        expected_response = interaction.get("response", {})
        
        try:
            async with httpx.AsyncClient() as client:
                # Build request URL
                url = f"{provider_url}{request.get('path', '/')}"
                
                # Make request
                response = await client.request(
                    method=request.get("method", "GET"),
                    url=url,
                    headers=request.get("headers", {}),
                    json=request.get("body") if request.get("body") else None,
                    params=request.get("query")
                )
                
                # Verify response
                return self._verify_response_matches(response, expected_response)
                
        except Exception as e:
            print(f"Error making request: {e}")
            return False
    
    def _verify_response_matches(self, actual_response: httpx.Response, expected: Dict[str, Any]) -> bool:
        """Verify that actual response matches expected response."""
        # Check status code
        expected_status = expected.get("status", 200)
        if actual_response.status_code != expected_status:
            print(f"Status code mismatch: expected {expected_status}, got {actual_response.status_code}")
            return False
        
        # Check headers
        expected_headers = expected.get("headers", {})
        for header, value in expected_headers.items():
            if header.lower() not in actual_response.headers:
                print(f"Missing header: {header}")
                return False
            
            actual_value = actual_response.headers[header.lower()]
            if actual_value != value:
                print(f"Header mismatch for {header}: expected {value}, got {actual_value}")
                return False
        
        # Check body
        expected_body = expected.get("body")
        if expected_body is not None:
            try:
                actual_body = actual_response.json()
                return self._match_json_structure(actual_body, expected_body)
            except Exception:
                return actual_response.text == expected_body
        
        return True
    
    def _match_json_structure(self, actual: Any, expected: Any) -> bool:
        """Match JSON structure with type matching."""
        if isinstance(expected, dict) and isinstance(actual, dict):
            for key, expected_value in expected.items():
                if key not in actual:
                    print(f"Missing key in response: {key}")
                    return False
                
                if not self._match_json_structure(actual[key], expected_value):
                    return False
            return True
        
        elif isinstance(expected, list) and isinstance(actual, list):
            if len(expected) != len(actual):
                # For array matching, we often just check structure of first item
                if expected and actual:
                    return self._match_json_structure(actual[0], expected[0])
                return len(expected) == len(actual)
            
            for i, expected_item in enumerate(expected):
                if not self._match_json_structure(actual[i], expected_item):
                    return False
            return True
        
        elif isinstance(expected, str) and expected.startswith("@"):
            # Handle Pact matchers (simplified)
            return self._handle_pact_matcher(actual, expected)
        
        else:
            return actual == expected
    
    def _handle_pact_matcher(self, actual: Any, matcher: str) -> bool:
        """Handle Pact matcher expressions."""
        if matcher == "@type:string":
            return isinstance(actual, str)
        elif matcher == "@type:integer":
            return isinstance(actual, int)
        elif matcher == "@type:boolean":
            return isinstance(actual, bool)
        elif matcher == "@type:array":
            return isinstance(actual, list)
        elif matcher == "@type:object":
            return isinstance(actual, dict)
        elif matcher.startswith("@regex:"):
            import re
            pattern = matcher[7:]  # Remove "@regex:" prefix
            return bool(re.match(pattern, str(actual)))
        
        return True


# Pytest fixtures for contract testing
@pytest.fixture(scope="session")
def pact_framework():
    """Provide Pact framework instance."""
    return PactTestFramework()


@pytest.fixture
async def auth_service_consumer_pact(pact_framework):
    """Create consumer pact for auth service."""
    pact = pact_framework.create_consumer_pact(
        consumer="frontend-app",
        provider="auth-service",
        port=8001
    )
    
    # Start mock service
    pact.start_service()
    yield pact
    pact.stop_service()


@pytest.fixture
async def user_service_consumer_pact(pact_framework):
    """Create consumer pact for user service."""
    pact = pact_framework.create_consumer_pact(
        consumer="api-gateway",
        provider="user-service",
        port=8002
    )
    
    pact.start_service()
    yield pact
    pact.stop_service()


# Contract test utilities
class ContractTestHelper:
    """Helper class for contract testing."""
    
    @staticmethod
    def standard_headers() -> Dict[str, str]:
        """Get standard API headers."""
        return {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "PyAirtable-Test/1.0"
        }
    
    @staticmethod
    def auth_headers(token: str) -> Dict[str, str]:
        """Get headers with authentication."""
        headers = ContractTestHelper.standard_headers()
        headers["Authorization"] = f"Bearer {token}"
        return headers
    
    @staticmethod
    def tenant_headers(tenant_id: str) -> Dict[str, str]:
        """Get headers with tenant ID."""
        headers = ContractTestHelper.standard_headers()
        headers["X-Tenant-ID"] = tenant_id
        return headers
    
    @staticmethod
    def error_response(status: int, message: str) -> Dict[str, Any]:
        """Standard error response format."""
        return {
            "status": status,
            "body": {
                "error": {
                    "code": status,
                    "message": message,
                    "timestamp": "@type:string"
                }
            },
            "headers": {
                "Content-Type": "application/json"
            }
        }
    
    @staticmethod
    def success_response(data: Any, status: int = 200) -> Dict[str, Any]:
        """Standard success response format."""
        return {
            "status": status,
            "body": data,
            "headers": {
                "Content-Type": "application/json"
            }
        }


# Common contract patterns
class APIContractPatterns:
    """Common API contract patterns."""
    
    USER_SCHEMA = {
        "id": "@type:string",
        "email": "@regex:^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$",
        "name": "@type:string",
        "tenant_id": "@type:string",
        "is_active": "@type:boolean",
        "role": "@type:string",
        "created_at": "@regex:^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
        "updated_at": "@regex:^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}"
    }
    
    TOKEN_RESPONSE_SCHEMA = {
        "access_token": "@type:string",
        "refresh_token": "@type:string",
        "token_type": "Bearer",
        "expires_in": "@type:integer"
    }
    
    PAGINATION_SCHEMA = {
        "page": "@type:integer",
        "per_page": "@type:integer",
        "total": "@type:integer",
        "total_pages": "@type:integer"
    }
    
    WORKSPACE_SCHEMA = {
        "id": "@type:string",
        "name": "@type:string",
        "description": "@type:string",
        "tenant_id": "@type:string",
        "owner_id": "@type:string",
        "is_active": "@type:boolean",
        "settings": "@type:object",
        "created_at": "@regex:^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}",
        "updated_at": "@regex:^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}"
    }
    
    @classmethod
    def paginated_response(cls, item_schema: Dict[str, Any]) -> Dict[str, Any]:
        """Create paginated response schema."""
        return {
            "data": [item_schema],
            "pagination": cls.PAGINATION_SCHEMA
        }
    
    @classmethod
    def single_item_response(cls, item_schema: Dict[str, Any]) -> Dict[str, Any]:
        """Create single item response schema."""
        return {
            "data": item_schema
        }


# Contract validation utilities
def validate_openapi_spec(spec_path: str, endpoint_url: str) -> bool:
    """Validate OpenAPI specification against live endpoint."""
    try:
        import openapi_spec_validator
        import yaml
        
        with open(spec_path) as f:
            if spec_path.endswith('.yaml') or spec_path.endswith('.yml'):
                spec = yaml.safe_load(f)
            else:
                spec = json.load(f)
        
        # Validate spec format
        openapi_spec_validator.validate_spec(spec)
        
        # TODO: Add live endpoint validation
        return True
        
    except Exception as e:
        print(f"OpenAPI validation failed: {e}")
        return False


# Export main components
__all__ = [
    'PactTestFramework',
    'ContractTestHelper', 
    'APIContractPatterns',
    'validate_openapi_spec'
]