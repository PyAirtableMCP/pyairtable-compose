"""
Security validation tests for authentication and authorization.
Tests security vulnerabilities, attack vectors, and compliance.
"""

import pytest
import asyncio
import httpx
import jwt
import hashlib
import base64
import time
import json
import secrets
import string
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class SecurityTestResult:
    """Security test result"""
    test_name: str
    vulnerability_found: bool
    severity: str  # "low", "medium", "high", "critical"
    description: str
    evidence: Optional[Dict[str, Any]] = None
    recommendation: Optional[str] = None


@pytest.mark.security
class TestAuthenticationSecurity:
    """Test authentication security vulnerabilities"""

    @pytest.fixture(autouse=True)
    async def setup_security_test(self, test_environment):
        """Setup security testing environment"""
        self.test_environment = test_environment
        self.security_results = []
        
        yield
        
        # Generate security report
        await self.generate_security_report()

    async def test_password_policy_enforcement(self, test_data_factory):
        """Test password policy enforcement"""
        weak_passwords = [
            "123456",
            "password",
            "abc123",
            "qwerty",
            "admin",
            "12345678",
            "",
            "a",
            "aa",
            "password123"
        ]
        
        security_issues = []
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for weak_password in weak_passwords:
                user_data = test_data_factory.create_user_data()
                user_data["password"] = weak_password
                
                try:
                    response = await client.post(
                        f"{self.test_environment.auth_service_url}/auth/register",
                        json=user_data
                    )
                    
                    # Registration should fail for weak passwords
                    if response.status_code in [200, 201]:
                        security_issues.append({
                            "password": weak_password,
                            "accepted": True,
                            "response": response.json()
                        })
                
                except Exception as e:
                    logger.warning(f"Password test error for '{weak_password}': {e}")
        
        result = SecurityTestResult(
            test_name="Password Policy Enforcement",
            vulnerability_found=len(security_issues) > 0,
            severity="high" if security_issues else "low",
            description=f"Weak passwords accepted: {len(security_issues)}/{len(weak_passwords)}",
            evidence={"weak_passwords_accepted": security_issues},
            recommendation="Implement strong password policy with minimum length, complexity requirements"
        )
        
        self.security_results.append(result)
        
        # Assert no weak passwords are accepted
        assert len(security_issues) == 0, f"Weak passwords were accepted: {[issue['password'] for issue in security_issues]}"

    async def test_brute_force_protection(self, test_data_factory):
        """Test brute force attack protection"""
        user_data = test_data_factory.create_user_data()
        
        # First, create a test user
        async with httpx.AsyncClient(timeout=30.0) as client:
            await client.post(
                f"{self.test_environment.auth_service_url}/auth/register",
                json=user_data
            )
            
            # Attempt multiple failed logins
            failed_attempts = 0
            locked_out = False
            
            for attempt in range(20):  # Try 20 failed login attempts
                login_response = await client.post(
                    f"{self.test_environment.auth_service_url}/auth/login",
                    json={
                        "email": user_data["email"],
                        "password": "wrong_password"
                    }
                )
                
                if login_response.status_code == 429:  # Too Many Requests
                    locked_out = True
                    break
                elif login_response.status_code in [401, 403]:
                    failed_attempts += 1
                
                # Small delay between attempts
                await asyncio.sleep(0.1)
        
        result = SecurityTestResult(
            test_name="Brute Force Protection",
            vulnerability_found=not locked_out,
            severity="high" if not locked_out else "low",
            description=f"Account lockout after {failed_attempts} attempts: {'Yes' if locked_out else 'No'}",
            evidence={"failed_attempts": failed_attempts, "locked_out": locked_out},
            recommendation="Implement account lockout after 5-10 failed attempts with exponential backoff"
        )
        
        self.security_results.append(result)
        
        # Should have brute force protection
        assert locked_out or failed_attempts < 15, "No brute force protection detected"

    async def test_jwt_token_security(self, test_data_factory):
        """Test JWT token security vulnerabilities"""
        # Get a valid token
        token = await self._create_test_user_and_login(test_data_factory)
        
        if not token or token == "mock_token_for_testing":
            pytest.skip("Cannot obtain real JWT token for security testing")
        
        security_issues = []
        
        # Test 1: JWT Algorithm Confusion Attack
        try:
            # Decode token without verification to inspect
            unverified_payload = jwt.decode(token, options={"verify_signature": False})
            
            # Try to create token with "none" algorithm
            none_token = jwt.encode(unverified_payload, "", algorithm="none")
            
            # Test if server accepts "none" algorithm token
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(
                    f"{self.test_environment.api_gateway_url}/auth/profile",
                    headers={"Authorization": f"Bearer {none_token}"}
                )
                
                if response.status_code == 200:
                    security_issues.append({
                        "vulnerability": "JWT None Algorithm",
                        "description": "Server accepts JWT tokens with 'none' algorithm"
                    })
        
        except Exception as e:
            logger.warning(f"JWT none algorithm test failed: {e}")
        
        # Test 2: JWT Token Manipulation
        try:
            # Try to modify token payload
            payload = jwt.decode(token, options={"verify_signature": False})
            
            # Modify user role or permissions if present
            modified_payload = payload.copy()
            if "role" in modified_payload:
                modified_payload["role"] = "admin"
            if "permissions" in modified_payload:
                modified_payload["permissions"] = ["admin", "superuser"]
            if "user_id" in modified_payload:
                modified_payload["user_id"] = "1"  # Try to become user 1
            
            # Create token with modified payload (without proper signature)
            modified_token = jwt.encode(modified_payload, "wrong_secret", algorithm="HS256")
            
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(
                    f"{self.test_environment.api_gateway_url}/auth/profile",
                    headers={"Authorization": f"Bearer {modified_token}"}
                )
                
                if response.status_code == 200:
                    security_issues.append({
                        "vulnerability": "JWT Token Manipulation",
                        "description": "Server accepts manipulated JWT tokens"
                    })
        
        except Exception as e:
            logger.warning(f"JWT manipulation test failed: {e}")
        
        # Test 3: JWT Secret Brute Force (weak secrets)
        weak_secrets = ["secret", "123456", "password", "key", "jwt", "token"]
        
        try:
            payload = jwt.decode(token, options={"verify_signature": False})
            
            for weak_secret in weak_secrets:
                try:
                    # Try to verify token with weak secret
                    jwt.decode(token, weak_secret, algorithms=["HS256"])
                    security_issues.append({
                        "vulnerability": "Weak JWT Secret",
                        "description": f"JWT signed with weak secret: {weak_secret}"
                    })
                    break
                except jwt.InvalidTokenError:
                    continue
        
        except Exception as e:
            logger.warning(f"JWT weak secret test failed: {e}")
        
        result = SecurityTestResult(
            test_name="JWT Token Security",
            vulnerability_found=len(security_issues) > 0,
            severity="critical" if security_issues else "low",
            description=f"JWT vulnerabilities found: {len(security_issues)}",
            evidence={"vulnerabilities": security_issues},
            recommendation="Use strong JWT secrets, validate algorithms, implement proper signature verification"
        )
        
        self.security_results.append(result)
        
        # Assert no JWT vulnerabilities
        assert len(security_issues) == 0, f"JWT security vulnerabilities found: {security_issues}"

    async def test_session_management_security(self, test_data_factory):
        """Test session management security"""
        token = await self._create_test_user_and_login(test_data_factory)
        
        if not token or token == "mock_token_for_testing":
            pytest.skip("Cannot obtain real token for session testing")
        
        security_issues = []
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Test 1: Session Fixation
            # Try to use the same token from different IPs/User-Agents
            headers_variants = [
                {"Authorization": f"Bearer {token}", "User-Agent": "AttackerBrowser/1.0"},
                {"Authorization": f"Bearer {token}", "X-Forwarded-For": "192.168.1.100"},
                {"Authorization": f"Bearer {token}", "X-Real-IP": "10.0.0.1"}
            ]
            
            for headers in headers_variants:
                response = await client.get(
                    f"{self.test_environment.api_gateway_url}/auth/profile",
                    headers=headers
                )
                
                # Should potentially detect suspicious activity
                if response.status_code == 200:
                    # This might not be a vulnerability depending on architecture
                    pass
            
            # Test 2: Token doesn't expire
            # Wait and check if token is still valid (this is a time-based test)
            await asyncio.sleep(2)  # Short wait for testing
            
            response = await client.get(
                f"{self.test_environment.api_gateway_url}/auth/profile",
                headers={"Authorization": f"Bearer {token}"}
            )
            
            # Long-lived tokens might be a security concern
            if response.status_code == 200:
                # Check if token has reasonable expiry
                try:
                    payload = jwt.decode(token, options={"verify_signature": False})
                    if "exp" not in payload:
                        security_issues.append({
                            "vulnerability": "No Token Expiry",
                            "description": "JWT token has no expiration time"
                        })
                    else:
                        exp_time = payload["exp"]
                        current_time = time.time()
                        time_to_expiry = exp_time - current_time
                        
                        # Tokens should expire within reasonable time (e.g., 24 hours)
                        if time_to_expiry > 86400:  # 24 hours
                            security_issues.append({
                                "vulnerability": "Long Token Expiry",
                                "description": f"Token expires in {time_to_expiry/3600:.1f} hours"
                            })
                
                except Exception as e:
                    logger.warning(f"Token expiry check failed: {e}")
        
        result = SecurityTestResult(
            test_name="Session Management Security",
            vulnerability_found=len(security_issues) > 0,
            severity="medium" if security_issues else "low",
            description=f"Session security issues: {len(security_issues)}",
            evidence={"issues": security_issues},
            recommendation="Implement proper session management with reasonable token expiry and activity monitoring"
        )
        
        self.security_results.append(result)

    async def test_authorization_bypass(self, test_data_factory):
        """Test authorization bypass vulnerabilities"""
        # Create two users with different privileges
        user1_data = test_data_factory.create_user_data()
        user2_data = test_data_factory.create_user_data()
        
        security_issues = []
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Create users
            await client.post(
                f"{self.test_environment.auth_service_url}/auth/register",
                json=user1_data
            )
            await client.post(
                f"{self.test_environment.auth_service_url}/auth/register",
                json=user2_data
            )
            
            # Get tokens for both users
            user1_token = await self._login_user(user1_data["email"], user1_data["password"])
            user2_token = await self._login_user(user2_data["email"], user2_data["password"])
            
            if user1_token and user2_token:
                # Test 1: Try to access other user's resources
                protected_endpoints = [
                    "/auth/profile",
                    "/api/user/settings",
                    "/api/user/data",
                    f"/api/users/{user1_data['email']}/profile"
                ]
                
                for endpoint in protected_endpoints:
                    # User 2 tries to access User 1's resources
                    response = await client.get(
                        f"{self.test_environment.api_gateway_url}{endpoint}",
                        headers={"Authorization": f"Bearer {user2_token}"}
                    )
                    
                    # Check if response contains user1's data
                    if response.status_code == 200:
                        response_data = response.json()
                        if isinstance(response_data, dict):
                            # Check if response contains user1's email or data
                            response_text = json.dumps(response_data).lower()
                            if user1_data["email"].lower() in response_text:
                                security_issues.append({
                                    "vulnerability": "Authorization Bypass",
                                    "endpoint": endpoint,
                                    "description": "User can access another user's data"
                                })
                
                # Test 2: Parameter pollution for user ID bypass
                bypass_attempts = [
                    {"user_id": "1", "user": "admin"},
                    {"id": "0", "user_id": "1"},
                    {"user": "admin", "role": "administrator"}
                ]
                
                for params in bypass_attempts:
                    response = await client.get(
                        f"{self.test_environment.api_gateway_url}/auth/profile",
                        headers={"Authorization": f"Bearer {user2_token}"},
                        params=params
                    )
                    
                    if response.status_code == 200:
                        response_data = response.json()
                        # Check if elevated privileges were granted
                        if isinstance(response_data, dict):
                            if response_data.get("role") == "admin" or response_data.get("user_id") == "1":
                                security_issues.append({
                                    "vulnerability": "Parameter Pollution",
                                    "params": params,
                                    "description": "Parameter manipulation grants elevated privileges"
                                })
        
        result = SecurityTestResult(
            test_name="Authorization Bypass",
            vulnerability_found=len(security_issues) > 0,
            severity="critical" if security_issues else "low",
            description=f"Authorization bypass vulnerabilities: {len(security_issues)}",
            evidence={"vulnerabilities": security_issues},
            recommendation="Implement proper authorization checks and user context validation"
        )
        
        self.security_results.append(result)
        
        # Critical security issue if authorization can be bypassed
        assert len(security_issues) == 0, f"Authorization bypass vulnerabilities found: {security_issues}"

    async def test_input_validation_authentication(self, test_data_factory):
        """Test input validation in authentication endpoints"""
        security_issues = []
        
        # SQL Injection attempts in authentication
        sql_injection_payloads = [
            "admin'--",
            "admin'/*",
            "' OR '1'='1",
            "' OR 1=1--",
            "admin'; DROP TABLE users;--",
            "' UNION SELECT * FROM users--"
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for payload in sql_injection_payloads:
                try:
                    response = await client.post(
                        f"{self.test_environment.auth_service_url}/auth/login",
                        json={
                            "email": payload,
                            "password": "test_password"
                        }
                    )
                    
                    # Should not return 200 for SQL injection attempts
                    if response.status_code == 200:
                        security_issues.append({
                            "vulnerability": "SQL Injection",
                            "payload": payload,
                            "endpoint": "/auth/login",
                            "response": response.json()
                        })
                    
                    # Check error messages for information disclosure
                    if response.status_code >= 400:
                        error_text = response.text.lower()
                        sensitive_keywords = ["sql", "database", "mysql", "postgresql", "error", "exception"]
                        
                        for keyword in sensitive_keywords:
                            if keyword in error_text:
                                security_issues.append({
                                    "vulnerability": "Information Disclosure",
                                    "payload": payload,
                                    "keyword": keyword,
                                    "description": "Error messages reveal sensitive information"
                                })
                                break
                
                except Exception as e:
                    logger.warning(f"SQL injection test failed for payload '{payload}': {e}")
            
            # NoSQL Injection attempts
            nosql_payloads = [
                {"$ne": ""},
                {"$gt": ""},
                {"$regex": ".*"},
                {"$where": "return true"}
            ]
            
            for payload in nosql_payloads:
                try:
                    response = await client.post(
                        f"{self.test_environment.auth_service_url}/auth/login",
                        json={
                            "email": payload,
                            "password": "test_password"
                        }
                    )
                    
                    if response.status_code == 200:
                        security_issues.append({
                            "vulnerability": "NoSQL Injection",
                            "payload": str(payload),
                            "endpoint": "/auth/login"
                        })
                
                except Exception as e:
                    logger.warning(f"NoSQL injection test failed for payload '{payload}': {e}")
        
        result = SecurityTestResult(
            test_name="Input Validation - Authentication",
            vulnerability_found=len(security_issues) > 0,
            severity="critical" if any("Injection" in issue["vulnerability"] for issue in security_issues) else "medium",
            description=f"Input validation issues: {len(security_issues)}",
            evidence={"vulnerabilities": security_issues},
            recommendation="Implement proper input validation and parameterized queries"
        )
        
        self.security_results.append(result)
        
        # Critical if injection vulnerabilities found
        injection_issues = [issue for issue in security_issues if "Injection" in issue["vulnerability"]]
        assert len(injection_issues) == 0, f"Injection vulnerabilities found: {injection_issues}"

    async def test_rate_limiting_authentication(self, test_data_factory):
        """Test rate limiting on authentication endpoints"""
        security_issues = []
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Test rate limiting on login endpoint
            login_attempts = []
            
            for i in range(50):  # Make 50 rapid requests
                start_time = time.time()
                
                try:
                    response = await client.post(
                        f"{self.test_environment.auth_service_url}/auth/login",
                        json={
                            "email": "test@example.com",
                            "password": "wrong_password"
                        }
                    )
                    
                    request_time = time.time() - start_time
                    
                    login_attempts.append({
                        "attempt": i,
                        "status_code": response.status_code,
                        "response_time": request_time
                    })
                    
                    # Check if rate limiting kicks in
                    if response.status_code == 429:  # Too Many Requests
                        break
                
                except Exception as e:
                    logger.warning(f"Rate limiting test attempt {i} failed: {e}")
            
            # Analyze rate limiting behavior
            rate_limited = any(attempt["status_code"] == 429 for attempt in login_attempts)
            
            if not rate_limited and len(login_attempts) >= 20:
                security_issues.append({
                    "vulnerability": "No Rate Limiting",
                    "endpoint": "/auth/login",
                    "attempts": len(login_attempts),
                    "description": "No rate limiting detected on authentication endpoint"
                })
            
            # Test registration rate limiting
            registration_attempts = []
            
            for i in range(20):
                user_data = test_data_factory.create_user_data()
                user_data["email"] = f"test{i}@example.com"
                
                try:
                    response = await client.post(
                        f"{self.test_environment.auth_service_url}/auth/register",
                        json=user_data
                    )
                    
                    registration_attempts.append({
                        "attempt": i,
                        "status_code": response.status_code
                    })
                    
                    if response.status_code == 429:
                        break
                
                except Exception as e:
                    logger.warning(f"Registration rate limiting test {i} failed: {e}")
            
            registration_rate_limited = any(attempt["status_code"] == 429 for attempt in registration_attempts)
            
            if not registration_rate_limited and len(registration_attempts) >= 15:
                security_issues.append({
                    "vulnerability": "No Registration Rate Limiting",
                    "endpoint": "/auth/register",
                    "attempts": len(registration_attempts),
                    "description": "No rate limiting on user registration"
                })
        
        result = SecurityTestResult(
            test_name="Rate Limiting - Authentication",
            vulnerability_found=len(security_issues) > 0,
            severity="medium" if security_issues else "low",
            description=f"Rate limiting issues: {len(security_issues)}",
            evidence={"issues": security_issues},
            recommendation="Implement rate limiting on all authentication endpoints"
        )
        
        self.security_results.append(result)

    async def _create_test_user_and_login(self, test_data_factory) -> str:
        """Create test user and return login token"""
        user_data = test_data_factory.create_user_data()
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Register user
            await client.post(
                f"{self.test_environment.auth_service_url}/auth/register",
                json=user_data
            )
            
            # Login user
            login_response = await client.post(
                f"{self.test_environment.auth_service_url}/auth/login",
                json={
                    "email": user_data["email"],
                    "password": user_data["password"]
                }
            )
            
            if login_response.status_code == 200:
                return login_response.json().get("access_token", "")
        
        return ""

    async def _login_user(self, email: str, password: str) -> str:
        """Login user and return token"""
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{self.test_environment.auth_service_url}/auth/login",
                json={"email": email, "password": password}
            )
            
            if response.status_code == 200:
                return response.json().get("access_token", "")
        
        return ""

    async def generate_security_report(self):
        """Generate comprehensive security report"""
        if not self.security_results:
            return
        
        # Categorize by severity
        critical_issues = [r for r in self.security_results if r.severity == "critical"]
        high_issues = [r for r in self.security_results if r.severity == "high"]
        medium_issues = [r for r in self.security_results if r.severity == "medium"]
        low_issues = [r for r in self.security_results if r.severity == "low"]
        
        # Create report
        report = {
            "summary": {
                "total_tests": len(self.security_results),
                "vulnerabilities_found": len([r for r in self.security_results if r.vulnerability_found]),
                "critical": len(critical_issues),
                "high": len(high_issues),
                "medium": len(medium_issues),
                "low": len(low_issues)
            },
            "results": []
        }
        
        for result in self.security_results:
            report["results"].append({
                "test_name": result.test_name,
                "vulnerability_found": result.vulnerability_found,
                "severity": result.severity,
                "description": result.description,
                "evidence": result.evidence,
                "recommendation": result.recommendation
            })
        
        # Save report
        import os
        os.makedirs("tests/reports/security", exist_ok=True)
        
        import aiofiles
        async with aiofiles.open("tests/reports/security/authentication_security_report.json", 'w') as f:
            await f.write(json.dumps(report, indent=2))
        
        # Log summary
        logger.info("Security Test Results:")
        logger.info(f"  Total Tests: {report['summary']['total_tests']}")
        logger.info(f"  Vulnerabilities Found: {report['summary']['vulnerabilities_found']}")
        logger.info(f"  Critical: {report['summary']['critical']}")
        logger.info(f"  High: {report['summary']['high']}")
        logger.info(f"  Medium: {report['summary']['medium']}")
        logger.info(f"  Low: {report['summary']['low']}")
        
        for result in self.security_results:
            if result.vulnerability_found:
                logger.warning(f"  ⚠️  {result.test_name}: {result.description}")
            else:
                logger.info(f"  ✅ {result.test_name}: Passed")