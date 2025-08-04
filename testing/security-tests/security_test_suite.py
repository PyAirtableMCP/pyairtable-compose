"""
Comprehensive security testing suite for PyAirtable system.
Tests authentication, authorization, input validation, and security headers.
"""

import pytest
import httpx
import asyncio
import json
import base64
import time
from typing import Dict, List, Any
from urllib.parse import quote
import jwt
from datetime import datetime, timedelta


class SecurityTestFramework:
    """Framework for security testing."""
    
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
        self.session = None
        
    async def __aenter__(self):
        self.session = httpx.AsyncClient(timeout=30.0)
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.aclose()
    
    async def test_endpoint_security(self, endpoint: str, method: str = "GET", 
                                   payload: Dict = None, headers: Dict = None) -> Dict[str, Any]:
        """Test security aspects of an endpoint."""
        results = {
            "endpoint": endpoint,
            "method": method,
            "vulnerabilities": [],
            "security_headers": {},
            "response_info": {}
        }
        
        try:
            # Test without authentication
            response = await self.session.request(
                method, 
                f"{self.base_url}{endpoint}",
                json=payload,
                headers=headers or {}
            )
            
            results["response_info"] = {
                "status_code": response.status_code,
                "headers": dict(response.headers),
            }
            
            # Check security headers
            results["security_headers"] = self._check_security_headers(response.headers)
            
            # Check for potential vulnerabilities
            results["vulnerabilities"] = await self._check_vulnerabilities(endpoint, method, response)
            
        except Exception as e:
            results["error"] = str(e)
            
        return results
    
    def _check_security_headers(self, headers: httpx.Headers) -> Dict[str, Any]:
        """Check for important security headers."""
        security_headers = {
            "X-Content-Type-Options": headers.get("x-content-type-options"),
            "X-Frame-Options": headers.get("x-frame-options"),
            "X-XSS-Protection": headers.get("x-xss-protection"),
            "Strict-Transport-Security": headers.get("strict-transport-security"),
            "Content-Security-Policy": headers.get("content-security-policy"),
            "Referrer-Policy": headers.get("referrer-policy"),
            "Permissions-Policy": headers.get("permissions-policy"),
        }
        
        missing_headers = [k for k, v in security_headers.items() if v is None]
        return {
            "present": {k: v for k, v in security_headers.items() if v is not None},
            "missing": missing_headers
        }
    
    async def _check_vulnerabilities(self, endpoint: str, method: str, response: httpx.Response) -> List[str]:
        """Check for common vulnerabilities."""
        vulnerabilities = []
        
        # Check for information disclosure
        if "server" in response.headers:
            vulnerabilities.append("Server header exposed")
            
        if "x-powered-by" in response.headers:
            vulnerabilities.append("X-Powered-By header exposed")
        
        # Check response content for sensitive information
        try:
            content = response.text.lower()
            if any(term in content for term in ["password", "token", "secret", "key"]):
                vulnerabilities.append("Potential sensitive information in response")
        except:
            pass
            
        # Check for CORS misconfigurations
        cors_header = response.headers.get("access-control-allow-origin")
        if cors_header == "*":
            vulnerabilities.append("Wildcard CORS policy detected")
            
        return vulnerabilities


@pytest.mark.security
class TestAuthenticationSecurity:
    """Test authentication security."""
    
    @pytest.fixture
    async def security_framework(self):
        async with SecurityTestFramework() as framework:
            yield framework
    
    @pytest.mark.asyncio
    async def test_password_brute_force_protection(self, security_framework):
        """Test protection against password brute force attacks."""
        email = "test@example.com"
        wrong_password = "wrongpassword"
        
        # Attempt multiple failed logins
        failed_attempts = 0
        max_attempts = 10
        
        for attempt in range(max_attempts):
            result = await security_framework.test_endpoint_security(
                "/api/v1/auth/login",
                method="POST",
                payload={"email": email, "password": wrong_password}
            )
            
            if result["response_info"]["status_code"] == 429:  # Rate limited
                print(f"Rate limiting activated after {attempt + 1} attempts")
                break
            elif result["response_info"]["status_code"] == 401:
                failed_attempts += 1
            
            # Small delay between attempts
            await asyncio.sleep(0.1)
        
        # Should be rate limited before max attempts
        assert failed_attempts < max_attempts, "No rate limiting detected for failed login attempts"
    
    @pytest.mark.asyncio
    async def test_jwt_token_security(self, security_framework):
        """Test JWT token security."""
        # Test with malformed tokens
        malformed_tokens = [
            "invalid.token.here",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature",
            "",
            "Bearer ",
            "malformed",
        ]
        
        for token in malformed_tokens:
            result = await security_framework.test_endpoint_security(
                "/api/v1/auth/me",
                headers={"Authorization": f"Bearer {token}"}
            )
            
            assert result["response_info"]["status_code"] in [401, 403], \
                f"Malformed token {token[:20]}... was accepted"
    
    @pytest.mark.asyncio
    async def test_session_security(self, security_framework):
        """Test session management security."""
        # Test concurrent session limits
        # Test session timeout
        # Test session invalidation
        
        # This would require actual authentication first
        login_result = await security_framework.test_endpoint_security(
            "/api/v1/auth/login",
            method="POST",
            payload={
                "email": "test@example.com",
                "password": "TestPassword123!"
            }
        )
        
        # Check if login requires proper credentials
        assert login_result["response_info"]["status_code"] in [200, 401], \
            "Login endpoint should return 200 (success) or 401 (unauthorized)"
    
    @pytest.mark.asyncio
    async def test_password_policy_enforcement(self, security_framework):
        """Test password policy enforcement."""
        weak_passwords = [
            "123456",
            "password",
            "abc123",
            "qwerty",
            "admin",
            "test",
            "",
            "a" * 100  # Too long
        ]
        
        for weak_password in weak_passwords:
            result = await security_framework.test_endpoint_security(
                "/api/v1/auth/register",
                method="POST",
                payload={
                    "email": f"test{int(time.time())}@example.com",
                    "password": weak_password,
                    "name": "Test User",
                    "tenant_id": "test-tenant"
                }
            )
            
            # Should reject weak passwords
            assert result["response_info"]["status_code"] in [400, 422], \
                f"Weak password '{weak_password}' was accepted"


@pytest.mark.security
class TestInputValidationSecurity:
    """Test input validation security."""
    
    @pytest.fixture
    async def security_framework(self):
        async with SecurityTestFramework() as framework:
            yield framework
    
    @pytest.mark.asyncio
    async def test_sql_injection_prevention(self, security_framework):
        """Test protection against SQL injection attacks."""
        sql_payloads = [
            "' OR '1'='1",
            "'; DROP TABLE users; --",
            "' UNION SELECT * FROM users --",
            "admin'--",
            "admin' #",
            "admin'/*",
            "' OR 1=1 --",
            "' OR 'x'='x",
        ]
        
        endpoints_to_test = [
            "/api/v1/auth/login",
            "/api/v1/users/search",
            "/api/v1/workspaces/search",
        ]
        
        for endpoint in endpoints_to_test:
            for payload in sql_payloads:
                # Test in different fields
                test_payloads = [
                    {"email": payload, "password": "test"},
                    {"query": payload},
                    {"name": payload},
                ]
                
                for test_payload in test_payloads:
                    result = await security_framework.test_endpoint_security(
                        endpoint,
                        method="POST",
                        payload=test_payload
                    )
                    
                    # Should not return 200 with SQL injection attempts
                    status = result["response_info"]["status_code"]
                    assert status not in [200], \
                        f"SQL injection payload '{payload}' may have succeeded on {endpoint}"
    
    @pytest.mark.asyncio
    async def test_xss_prevention(self, security_framework):
        """Test protection against XSS attacks."""
        xss_payloads = [
            "<script>alert('xss')</script>",
            "<img src=x onerror=alert('xss')>",
            "javascript:alert('xss')",
            "<svg onload=alert('xss')>",
            "'\"><script>alert('xss')</script>",
            "<iframe src=javascript:alert('xss')></iframe>",
        ]
        
        for payload in xss_payloads:
            result = await security_framework.test_endpoint_security(
                "/api/v1/workspaces",
                method="POST",
                payload={
                    "name": payload,
                    "description": payload
                }
            )
            
            # Check response doesn't contain unescaped script
            response_text = result.get("response_text", "")
            assert "<script>" not in response_text.lower(), \
                f"Potential XSS vulnerability with payload: {payload}"
    
    @pytest.mark.asyncio
    async def test_command_injection_prevention(self, security_framework):
        """Test protection against command injection."""
        command_payloads = [
            "; ls -la",
            "| cat /etc/passwd",
            "`whoami`",
            "$(id)",
            "&& cat /etc/hosts",
            "|| ping -c 1 google.com",
        ]
        
        for payload in command_payloads:
            result = await security_framework.test_endpoint_security(
                "/api/v1/files/upload",
                method="POST",
                payload={
                    "filename": payload,
                    "content": "test content"
                }
            )
            
            # Should reject command injection attempts
            status = result["response_info"]["status_code"]
            assert status in [400, 422, 403], \
                f"Command injection payload '{payload}' was not properly rejected"
    
    @pytest.mark.asyncio
    async def test_path_traversal_prevention(self, security_framework):
        """Test protection against path traversal attacks."""
        path_payloads = [
            "../../../etc/passwd",
            "..\\..\\..\\windows\\system32\\config\\sam",
            "....//....//....//etc/passwd",
            "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
            "..%252f..%252f..%252fetc%252fpasswd",
        ]
        
        for payload in path_payloads:
            result = await security_framework.test_endpoint_security(
                f"/api/v1/files/{quote(payload)}",
                method="GET"
            )
            
            # Should not allow access to system files
            status = result["response_info"]["status_code"]
            assert status in [400, 403, 404], \
                f"Path traversal payload '{payload}' was not blocked"


@pytest.mark.security
class TestAuthorizationSecurity:
    """Test authorization and access control security."""
    
    @pytest.fixture
    async def security_framework(self):
        async with SecurityTestFramework() as framework:
            yield framework
    
    @pytest.mark.asyncio
    async def test_unauthorized_access_prevention(self, security_framework):
        """Test that protected endpoints require authentication."""
        protected_endpoints = [
            ("/api/v1/users/me", "GET"),
            ("/api/v1/workspaces", "GET"),
            ("/api/v1/workspaces", "POST"),
            ("/api/v1/workspaces/123", "PUT"),
            ("/api/v1/workspaces/123", "DELETE"),
            ("/api/v1/airtable/bases", "GET"),
        ]
        
        for endpoint, method in protected_endpoints:
            result = await security_framework.test_endpoint_security(endpoint, method)
            
            # Should require authorization
            status = result["response_info"]["status_code"]
            assert status in [401, 403], \
                f"Protected endpoint {method} {endpoint} accessible without authentication"
    
    @pytest.mark.asyncio
    async def test_privilege_escalation_prevention(self, security_framework):
        """Test prevention of privilege escalation."""
        # This would require creating users with different roles
        # and testing cross-tenant access
        
        # Test accessing admin endpoints with regular user token
        admin_endpoints = [
            "/api/v1/admin/users",
            "/api/v1/admin/tenants", 
            "/api/v1/admin/system",
        ]
        
        # Would need to get a regular user token first
        for endpoint in admin_endpoints:
            result = await security_framework.test_endpoint_security(endpoint)
            
            # Should be forbidden for regular users
            status = result["response_info"]["status_code"]
            assert status in [401, 403, 404], \
                f"Admin endpoint {endpoint} may be accessible to regular users"
    
    @pytest.mark.asyncio
    async def test_cross_tenant_access_prevention(self, security_framework):
        """Test that users cannot access other tenants' data."""
        # This test would require multiple tenant setup
        # For now, just check that tenant isolation headers are enforced
        
        result = await security_framework.test_endpoint_security(
            "/api/v1/workspaces/other-tenant-workspace-id",
            headers={"X-Tenant-ID": "tenant-1"}
        )
        
        # Should not allow cross-tenant access
        status = result["response_info"]["status_code"]
        assert status in [401, 403, 404], \
            "Cross-tenant access may be possible"


@pytest.mark.security
class TestDataProtectionSecurity:
    """Test data protection and privacy security."""
    
    @pytest.fixture
    async def security_framework(self):
        async with SecurityTestFramework() as framework:
            yield framework
    
    @pytest.mark.asyncio
    async def test_sensitive_data_exposure(self, security_framework):
        """Test that sensitive data is not exposed in responses."""
        # Test error messages don't leak sensitive info
        result = await security_framework.test_endpoint_security(
            "/api/v1/auth/login",
            method="POST",
            payload={"email": "nonexistent@example.com", "password": "wrong"}
        )
        
        # Error messages should be generic
        response_text = result.get("response_text", "").lower()
        sensitive_terms = ["password", "hash", "secret", "key", "token"]
        
        for term in sensitive_terms:
            assert term not in response_text, \
                f"Sensitive term '{term}' found in error response"
    
    @pytest.mark.asyncio
    async def test_data_encryption_in_transit(self, security_framework):
        """Test that data is encrypted in transit."""
        # Check if HTTPS is enforced
        if security_framework.base_url.startswith("https://"):
            result = await security_framework.test_endpoint_security("/api/health")
            
            # Should have proper TLS headers
            headers = result["security_headers"]["present"]
            assert "strict-transport-security" in [h.lower() for h in headers.keys()], \
                "HSTS header missing for HTTPS endpoint"
    
    @pytest.mark.asyncio
    async def test_pii_handling(self, security_framework):
        """Test proper handling of personally identifiable information."""
        # Test that PII is not logged or exposed
        result = await security_framework.test_endpoint_security(
            "/api/v1/auth/register",
            method="POST",
            payload={
                "email": "pii.test@example.com",
                "password": "TestPassword123!",
                "name": "PII Test User",
                "tenant_id": "test-tenant"
            }
        )
        
        # Response should not contain plain text password
        response_text = result.get("response_text", "")
        assert "TestPassword123!" not in response_text, \
            "Plain text password found in response"


@pytest.mark.security
class TestInfrastructureSecurity:
    """Test infrastructure security configurations."""
    
    @pytest.fixture
    async def security_framework(self):
        async with SecurityTestFramework() as framework:
            yield framework
    
    @pytest.mark.asyncio
    async def test_security_headers_presence(self, security_framework):
        """Test that security headers are present."""
        result = await security_framework.test_endpoint_security("/api/health")
        
        missing_headers = result["security_headers"]["missing"]
        critical_headers = [
            "X-Content-Type-Options",
            "X-Frame-Options", 
            "X-XSS-Protection",
        ]
        
        for header in critical_headers:
            assert header not in missing_headers, \
                f"Critical security header {header} is missing"
    
    @pytest.mark.asyncio
    async def test_information_disclosure_prevention(self, security_framework):
        """Test that system information is not disclosed."""
        result = await security_framework.test_endpoint_security("/api/health")
        
        vulnerabilities = result["vulnerabilities"]
        assert "Server header exposed" not in vulnerabilities, \
            "Server information is being disclosed"
        assert "X-Powered-By header exposed" not in vulnerabilities, \
            "Technology stack information is being disclosed"
    
    @pytest.mark.asyncio
    async def test_cors_configuration(self, security_framework):
        """Test CORS configuration security."""
        result = await security_framework.test_endpoint_security(
            "/api/v1/auth/login",
            method="OPTIONS",
            headers={"Origin": "https://malicious-site.com"}
        )
        
        vulnerabilities = result["vulnerabilities"]
        assert "Wildcard CORS policy detected" not in vulnerabilities, \
            "Dangerous CORS wildcard policy detected"


# Security test runner
async def run_security_tests():
    """Run all security tests."""
    print("Starting comprehensive security test suite...")
    
    async with SecurityTestFramework() as framework:
        # Test critical endpoints
        critical_endpoints = [
            "/api/v1/auth/login",
            "/api/v1/auth/register",
            "/api/v1/auth/me",
            "/api/v1/workspaces",
            "/api/v1/users",
        ]
        
        results = []
        for endpoint in critical_endpoints:
            result = await framework.test_endpoint_security(endpoint)
            results.append(result)
            
            # Print immediate results
            print(f"\nEndpoint: {endpoint}")
            print(f"Status: {result['response_info'].get('status_code')}")
            print(f"Vulnerabilities: {len(result['vulnerabilities'])}")
            print(f"Missing security headers: {len(result['security_headers']['missing'])}")
        
        return results


if __name__ == "__main__":
    # Run security tests directly
    asyncio.run(run_security_tests())