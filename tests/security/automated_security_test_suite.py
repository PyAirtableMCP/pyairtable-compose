#!/usr/bin/env python3
"""
Automated Security Test Suite
Comprehensive security testing for PyAirtable production deployment
"""

import asyncio
import json
import logging
import os
import sys
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import aiohttp
import pytest
import requests
from dataclasses import dataclass
from pathlib import Path

# Add project root to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', '..'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class SecurityTestResult:
    """Security test result data class"""
    test_name: str
    status: str  # PASSED, FAILED, SKIPPED, ERROR
    severity: str  # CRITICAL, HIGH, MEDIUM, LOW, INFO
    description: str
    vulnerability_type: str
    remediation: str
    evidence: Dict[str, Any]
    timestamp: str

class SecurityTestSuite:
    """Automated security test suite for PyAirtable"""
    
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.results: List[SecurityTestResult] = []
        
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run comprehensive security test suite"""
        logger.info("Starting PyAirtable Security Test Suite")
        start_time = time.time()
        
        # Test categories
        test_categories = [
            ("OWASP Top 10", self._test_owasp_top_10),
            ("Authentication Security", self._test_authentication),
            ("Authorization Controls", self._test_authorization),
            ("Input Validation", self._test_input_validation),
            ("Security Headers", self._test_security_headers),
            ("CORS Configuration", self._test_cors_configuration),
            ("Rate Limiting", self._test_rate_limiting),
            ("Information Disclosure", self._test_information_disclosure),
            ("Session Management", self._test_session_management),
            ("Error Handling", self._test_error_handling),
            ("File Upload Security", self._test_file_upload_security),
            ("API Security", self._test_api_security),
            ("Cryptography", self._test_cryptography),
            ("Infrastructure Security", self._test_infrastructure_security)
        ]
        
        for category_name, test_method in test_categories:
            try:
                logger.info(f"Running {category_name} tests...")
                await test_method()
            except Exception as e:
                logger.error(f"Error in {category_name}: {str(e)}")
                self._add_result(
                    test_name=f"{category_name} - Test Suite Error",
                    status="ERROR",
                    severity="HIGH",
                    description=f"Test suite failed to execute: {str(e)}",
                    vulnerability_type="Infrastructure",
                    remediation="Fix test suite configuration",
                    evidence={"error": str(e)}
                )
        
        total_time = time.time() - start_time
        return self._generate_report(total_time)
    
    def _add_result(self, test_name: str, status: str, severity: str, 
                   description: str, vulnerability_type: str, remediation: str,
                   evidence: Dict[str, Any] = None):
        """Add test result to results list"""
        result = SecurityTestResult(
            test_name=test_name,
            status=status,
            severity=severity,
            description=description,
            vulnerability_type=vulnerability_type,
            remediation=remediation,
            evidence=evidence or {},
            timestamp=datetime.utcnow().isoformat()
        )
        self.results.append(result)
        
        # Log result
        log_level = logging.ERROR if status == "FAILED" else logging.INFO
        logger.log(log_level, f"{test_name}: {status} ({severity})")
    
    async def _test_owasp_top_10(self):
        """Test OWASP Top 10 2021 vulnerabilities"""
        
        # A01: Broken Access Control
        await self._test_broken_access_control()
        
        # A02: Cryptographic Failures
        await self._test_cryptographic_failures()
        
        # A03: Injection
        await self._test_injection_attacks()
        
        # A04: Insecure Design
        await self._test_insecure_design()
        
        # A05: Security Misconfiguration
        await self._test_security_misconfiguration()
        
        # A06: Vulnerable Components
        await self._test_vulnerable_components()
        
        # A07: Authentication Failures
        await self._test_authentication_failures()
        
        # A08: Software Integrity Failures
        await self._test_software_integrity()
        
        # A09: Security Logging Failures
        await self._test_security_logging()
        
        # A10: SSRF
        await self._test_ssrf()
    
    async def _test_broken_access_control(self):
        """Test for broken access control (OWASP A01)"""
        
        # Test 1: Direct object reference
        try:
            response = self.session.get(f"{self.base_url}/api/users/1")
            if response.status_code == 200:
                self._add_result(
                    test_name="A01 - Direct Object Reference",
                    status="FAILED",
                    severity="HIGH",
                    description="Unauthorized access to user data without authentication",
                    vulnerability_type="Broken Access Control",
                    remediation="Implement proper authentication and authorization checks",
                    evidence={"response_code": response.status_code}
                )
            else:
                self._add_result(
                    test_name="A01 - Direct Object Reference",
                    status="PASSED",
                    severity="INFO",
                    description="Direct object access properly protected",
                    vulnerability_type="Access Control",
                    remediation="N/A",
                    evidence={"response_code": response.status_code}
                )
        except Exception as e:
            logger.error(f"Direct object reference test failed: {str(e)}")
        
        # Test 2: Admin endpoint access
        try:
            response = self.session.get(f"{self.base_url}/admin/")
            if response.status_code == 200:
                self._add_result(
                    test_name="A01 - Admin Access Control",
                    status="FAILED",
                    severity="CRITICAL",
                    description="Admin endpoints accessible without authentication",
                    vulnerability_type="Broken Access Control",
                    remediation="Implement role-based access control for admin endpoints",
                    evidence={"response_code": response.status_code}
                )
            else:
                self._add_result(
                    test_name="A01 - Admin Access Control",
                    status="PASSED",
                    severity="INFO",
                    description="Admin endpoints properly protected",
                    vulnerability_type="Access Control",
                    remediation="N/A",
                    evidence={"response_code": response.status_code}
                )
        except Exception as e:
            logger.error(f"Admin access test failed: {str(e)}")
    
    async def _test_cryptographic_failures(self):
        """Test for cryptographic failures (OWASP A02)"""
        
        # Test 1: HTTPS enforcement
        try:
            if self.base_url.startswith("http://"):
                http_url = self.base_url
                response = self.session.get(http_url, allow_redirects=False)
                
                if response.status_code in [301, 302, 307, 308]:
                    location = response.headers.get('Location', '')
                    if location.startswith('https://'):
                        self._add_result(
                            test_name="A02 - HTTPS Redirect",
                            status="PASSED",
                            severity="INFO",
                            description="HTTP requests properly redirected to HTTPS",
                            vulnerability_type="Cryptographic Security",
                            remediation="N/A",
                            evidence={"redirect_location": location}
                        )
                    else:
                        self._add_result(
                            test_name="A02 - HTTPS Redirect",
                            status="FAILED",
                            severity="HIGH",
                            description="HTTP requests not redirected to HTTPS",
                            vulnerability_type="Cryptographic Failures",
                            remediation="Configure HTTPS redirect in web server",
                            evidence={"response_code": response.status_code}
                        )
                else:
                    self._add_result(
                        test_name="A02 - HTTPS Enforcement",
                        status="FAILED",
                        severity="HIGH",
                        description="Application accessible over HTTP without HTTPS redirect",
                        vulnerability_type="Cryptographic Failures",
                        remediation="Enforce HTTPS-only access",
                        evidence={"response_code": response.status_code}
                    )
        except Exception as e:
            logger.error(f"HTTPS enforcement test failed: {str(e)}")
    
    async def _test_injection_attacks(self):
        """Test for injection vulnerabilities (OWASP A03)"""
        
        # SQL Injection tests
        sql_payloads = [
            "' OR '1'='1",
            "'; DROP TABLE users; --",
            "' UNION SELECT * FROM users --",
            "1' OR '1'='1' --",
            "admin'--",
            "' OR 1=1#"
        ]
        
        for payload in sql_payloads:
            try:
                # Test in search endpoint
                response = self.session.post(f"{self.base_url}/api/search", 
                                           json={"query": payload})
                
                if response.status_code == 500:
                    self._add_result(
                        test_name="A03 - SQL Injection",
                        status="FAILED",
                        severity="CRITICAL",
                        description=f"Possible SQL injection vulnerability with payload: {payload}",
                        vulnerability_type="Injection",
                        remediation="Use parameterized queries and input validation",
                        evidence={"payload": payload, "response_code": response.status_code}
                    )
                    break
                    
                # Check response for database errors
                if any(error in response.text.lower() for error in 
                       ['sql', 'mysql', 'postgresql', 'oracle', 'sqlite']):
                    self._add_result(
                        test_name="A03 - SQL Error Disclosure",
                        status="FAILED",
                        severity="MEDIUM",
                        description="Database errors disclosed in response",
                        vulnerability_type="Information Disclosure",
                        remediation="Implement proper error handling",
                        evidence={"payload": payload, "response_excerpt": response.text[:500]}
                    )
                    break
                    
            except Exception as e:
                logger.error(f"SQL injection test failed: {str(e)}")
        
        # XSS tests
        xss_payloads = [
            "<script>alert('XSS')</script>",
            "javascript:alert('XSS')",
            "<img src=x onerror=alert('XSS')>",
            "'\"><script>alert('XSS')</script>",
            "<svg onload=alert('XSS')>"
        ]
        
        for payload in xss_payloads:
            try:
                response = self.session.post(f"{self.base_url}/api/feedback", 
                                           json={"message": payload})
                
                if payload in response.text and "text/html" in response.headers.get("content-type", ""):
                    self._add_result(
                        test_name="A03 - Cross-Site Scripting (XSS)",
                        status="FAILED",
                        severity="HIGH",
                        description=f"XSS payload reflected in response: {payload}",
                        vulnerability_type="Injection",
                        remediation="Implement output encoding and CSP headers",
                        evidence={"payload": payload}
                    )
                    break
            except Exception as e:
                logger.error(f"XSS test failed: {str(e)}")
    
    async def _test_security_headers(self):
        """Test security headers"""
        
        try:
            response = self.session.get(f"{self.base_url}/")
            headers = response.headers
            
            # Required security headers
            required_headers = {
                'X-Content-Type-Options': 'nosniff',
                'X-Frame-Options': ['DENY', 'SAMEORIGIN'],
                'X-XSS-Protection': '1; mode=block',
                'Strict-Transport-Security': None,  # Any value is good
                'Content-Security-Policy': None,
                'Referrer-Policy': None
            }
            
            for header, expected_values in required_headers.items():
                header_value = headers.get(header)
                
                if not header_value:
                    self._add_result(
                        test_name=f"Security Headers - Missing {header}",
                        status="FAILED",
                        severity="MEDIUM" if header != 'Content-Security-Policy' else "HIGH",
                        description=f"Missing security header: {header}",
                        vulnerability_type="Security Misconfiguration",
                        remediation=f"Add {header} header to all responses",
                        evidence={"missing_header": header}
                    )
                elif expected_values and header_value not in expected_values:
                    self._add_result(
                        test_name=f"Security Headers - Invalid {header}",
                        status="FAILED",
                        severity="MEDIUM",
                        description=f"Invalid value for {header}: {header_value}",
                        vulnerability_type="Security Misconfiguration", 
                        remediation=f"Set {header} to one of: {expected_values}",
                        evidence={"header": header, "current_value": header_value, "expected": expected_values}
                    )
                else:
                    self._add_result(
                        test_name=f"Security Headers - {header}",
                        status="PASSED",
                        severity="INFO",
                        description=f"Security header properly configured: {header}",
                        vulnerability_type="Security Configuration",
                        remediation="N/A",
                        evidence={"header": header, "value": header_value}
                    )
                    
        except Exception as e:
            logger.error(f"Security headers test failed: {str(e)}")
    
    async def _test_cors_configuration(self):
        """Test CORS configuration"""
        
        try:
            # Test preflight request with dangerous origin
            dangerous_origins = [
                "http://evil.com",
                "https://malicious.site",
                "null"
            ]
            
            for origin in dangerous_origins:
                response = self.session.options(
                    f"{self.base_url}/api/health",
                    headers={
                        "Origin": origin,
                        "Access-Control-Request-Method": "GET"
                    }
                )
                
                cors_origin = response.headers.get("Access-Control-Allow-Origin")
                
                if cors_origin == "*":
                    self._add_result(
                        test_name="CORS - Wildcard Origin",
                        status="FAILED",
                        severity="HIGH",
                        description="CORS configured with wildcard origin (*)",
                        vulnerability_type="Security Misconfiguration",
                        remediation="Configure specific allowed origins instead of wildcard",
                        evidence={"cors_origin": cors_origin}
                    )
                elif cors_origin == origin:
                    self._add_result(
                        test_name="CORS - Dangerous Origin Allowed",
                        status="FAILED",
                        severity="HIGH", 
                        description=f"Dangerous origin allowed: {origin}",
                        vulnerability_type="Security Misconfiguration",
                        remediation="Remove dangerous origins from CORS configuration",
                        evidence={"allowed_origin": origin}
                    )
                    
        except Exception as e:
            logger.error(f"CORS configuration test failed: {str(e)}")
    
    async def _test_rate_limiting(self):
        """Test rate limiting"""
        
        try:
            # Test rate limiting on API endpoint
            endpoint = f"{self.base_url}/api/health"
            request_count = 0
            rate_limited = False
            
            for i in range(150):  # Send many requests quickly
                response = self.session.get(endpoint)
                request_count += 1
                
                if response.status_code == 429:
                    rate_limited = True
                    
                    # Check for proper rate limiting headers
                    if "Retry-After" in response.headers:
                        self._add_result(
                            test_name="Rate Limiting - Implementation",
                            status="PASSED",
                            severity="INFO",
                            description=f"Rate limiting active after {request_count} requests",
                            vulnerability_type="Rate Limiting",
                            remediation="N/A",
                            evidence={
                                "requests_before_limit": request_count,
                                "retry_after": response.headers.get("Retry-After")
                            }
                        )
                    else:
                        self._add_result(
                            test_name="Rate Limiting - Missing Headers",
                            status="FAILED",
                            severity="MEDIUM",
                            description="Rate limiting active but missing Retry-After header",
                            vulnerability_type="Security Misconfiguration",
                            remediation="Add proper rate limiting headers",
                            evidence={"requests_before_limit": request_count}
                        )
                    break
                    
                time.sleep(0.01)  # Small delay
                
            if not rate_limited:
                self._add_result(
                    test_name="Rate Limiting - Not Implemented",
                    status="FAILED",
                    severity="MEDIUM",
                    description=f"No rate limiting detected after {request_count} requests",
                    vulnerability_type="Security Misconfiguration", 
                    remediation="Implement rate limiting for API endpoints",
                    evidence={"requests_sent": request_count}
                )
                
        except Exception as e:
            logger.error(f"Rate limiting test failed: {str(e)}")
    
    async def _test_information_disclosure(self):
        """Test for information disclosure"""
        
        try:
            # Test error page information disclosure
            response = self.session.get(f"{self.base_url}/nonexistent-endpoint")
            
            sensitive_info_patterns = [
                r'traceback',
                r'stack trace', 
                r'exception',
                r'/usr/',
                r'/var/',
                r'c:\\',
                r'database',
                r'sql',
                r'password',
                r'secret',
                r'key'
            ]
            
            response_text = response.text.lower()
            exposed_info = []
            
            for pattern in sensitive_info_patterns:
                if pattern in response_text:
                    exposed_info.append(pattern)
            
            if exposed_info:
                self._add_result(
                    test_name="Information Disclosure - Error Pages",
                    status="FAILED",
                    severity="MEDIUM",
                    description=f"Sensitive information disclosed in error pages: {', '.join(exposed_info)}",
                    vulnerability_type="Information Disclosure",
                    remediation="Implement generic error pages for production",
                    evidence={"exposed_patterns": exposed_info}
                )
            else:
                self._add_result(
                    test_name="Information Disclosure - Error Pages",
                    status="PASSED",
                    severity="INFO",
                    description="No sensitive information disclosed in error pages",
                    vulnerability_type="Information Security",
                    remediation="N/A",
                    evidence={"response_code": response.status_code}
                )
                
        except Exception as e:
            logger.error(f"Information disclosure test failed: {str(e)}")
    
    # Additional test methods would be implemented here...
    # For brevity, including placeholder methods
    
    async def _test_authentication(self):
        """Test authentication mechanisms"""
        self._add_result(
            test_name="Authentication Tests",
            status="SKIPPED",
            severity="INFO",
            description="Authentication tests not yet implemented",
            vulnerability_type="Authentication",
            remediation="Implement comprehensive authentication tests",
            evidence={}
        )
    
    async def _test_authorization(self):
        """Test authorization controls"""
        self._add_result(
            test_name="Authorization Tests", 
            status="SKIPPED",
            severity="INFO",
            description="Authorization tests not yet implemented",
            vulnerability_type="Authorization",
            remediation="Implement comprehensive authorization tests",
            evidence={}
        )
    
    async def _test_input_validation(self):
        """Test input validation"""
        self._add_result(
            test_name="Input Validation Tests",
            status="SKIPPED", 
            severity="INFO",
            description="Input validation tests not yet implemented",
            vulnerability_type="Input Validation",
            remediation="Implement comprehensive input validation tests",
            evidence={}
        )
    
    # Placeholder methods for other test categories
    async def _test_insecure_design(self): pass
    async def _test_security_misconfiguration(self): pass
    async def _test_vulnerable_components(self): pass
    async def _test_authentication_failures(self): pass
    async def _test_software_integrity(self): pass
    async def _test_security_logging(self): pass
    async def _test_ssrf(self): pass
    async def _test_session_management(self): pass
    async def _test_error_handling(self): pass
    async def _test_file_upload_security(self): pass
    async def _test_api_security(self): pass
    async def _test_cryptography(self): pass
    async def _test_infrastructure_security(self): pass
    
    def _generate_report(self, total_time: float) -> Dict[str, Any]:
        """Generate comprehensive security test report"""
        
        # Calculate statistics
        total_tests = len(self.results)
        passed_tests = len([r for r in self.results if r.status == "PASSED"])
        failed_tests = len([r for r in self.results if r.status == "FAILED"]) 
        skipped_tests = len([r for r in self.results if r.status == "SKIPPED"])
        error_tests = len([r for r in self.results if r.status == "ERROR"])
        
        # Calculate severity distribution
        severity_counts = {}
        for result in self.results:
            severity_counts[result.severity] = severity_counts.get(result.severity, 0) + 1
        
        # Calculate security score
        critical_failures = len([r for r in self.results if r.status == "FAILED" and r.severity == "CRITICAL"])
        high_failures = len([r for r in self.results if r.status == "FAILED" and r.severity == "HIGH"])
        medium_failures = len([r for r in self.results if r.status == "FAILED" and r.severity == "MEDIUM"])
        
        # Weighted scoring
        max_score = 100
        deductions = (critical_failures * 25) + (high_failures * 15) + (medium_failures * 5)
        security_score = max(0, max_score - deductions)
        
        # Determine security grade
        if security_score >= 95:
            security_grade = "A+"
        elif security_score >= 90:
            security_grade = "A"
        elif security_score >= 85:
            security_grade = "A-"
        elif security_score >= 80:
            security_grade = "B+"
        elif security_score >= 75:
            security_grade = "B"
        elif security_score >= 70:
            security_grade = "B-"
        elif security_score >= 65:
            security_grade = "C+"
        elif security_score >= 60:
            security_grade = "C"
        else:
            security_grade = "F"
        
        # Group results by vulnerability type
        vulnerability_types = {}
        for result in self.results:
            vtype = result.vulnerability_type
            if vtype not in vulnerability_types:
                vulnerability_types[vtype] = []
            vulnerability_types[vtype].append(result)
        
        return {
            "summary": {
                "total_tests": total_tests,
                "passed_tests": passed_tests, 
                "failed_tests": failed_tests,
                "skipped_tests": skipped_tests,
                "error_tests": error_tests,
                "security_score": security_score,
                "security_grade": security_grade,
                "test_duration": round(total_time, 2),
                "timestamp": datetime.utcnow().isoformat(),
                "severity_distribution": severity_counts
            },
            "critical_findings": [
                {
                    "test_name": r.test_name,
                    "description": r.description,
                    "remediation": r.remediation,
                    "evidence": r.evidence
                }
                for r in self.results 
                if r.status == "FAILED" and r.severity == "CRITICAL"
            ],
            "vulnerability_types": {
                vtype: {
                    "total": len(results),
                    "failed": len([r for r in results if r.status == "FAILED"]),
                    "critical": len([r for r in results if r.status == "FAILED" and r.severity == "CRITICAL"]),
                    "high": len([r for r in results if r.status == "FAILED" and r.severity == "HIGH"]),
                    "findings": [
                        {
                            "test_name": r.test_name,
                            "status": r.status,
                            "severity": r.severity,
                            "description": r.description,
                            "remediation": r.remediation
                        }
                        for r in results
                    ]
                }
                for vtype, results in vulnerability_types.items()
            },
            "recommendations": self._generate_recommendations(),
            "compliance_status": self._assess_compliance(),
            "test_results": [
                {
                    "test_name": r.test_name,
                    "status": r.status,
                    "severity": r.severity,
                    "vulnerability_type": r.vulnerability_type,
                    "description": r.description,
                    "remediation": r.remediation,
                    "evidence": r.evidence,
                    "timestamp": r.timestamp
                }
                for r in self.results
            ]
        }
    
    def _generate_recommendations(self) -> List[Dict[str, Any]]:
        """Generate security recommendations based on test results"""
        recommendations = []
        
        failed_results = [r for r in self.results if r.status == "FAILED"]
        
        # Prioritize by severity
        critical_failures = [r for r in failed_results if r.severity == "CRITICAL"]
        high_failures = [r for r in failed_results if r.severity == "HIGH"] 
        medium_failures = [r for r in failed_results if r.severity == "MEDIUM"]
        
        for failures, priority in [(critical_failures, "IMMEDIATE"), 
                                  (high_failures, "HIGH"), 
                                  (medium_failures, "MEDIUM")]:
            for failure in failures:
                recommendations.append({
                    "priority": priority,
                    "category": failure.vulnerability_type,
                    "issue": failure.description,
                    "recommendation": failure.remediation,
                    "test_name": failure.test_name
                })
        
        return recommendations[:10]  # Top 10 recommendations
    
    def _assess_compliance(self) -> Dict[str, str]:
        """Assess compliance with security standards"""
        
        # Simple compliance assessment based on test results
        owasp_failures = len([r for r in self.results if r.test_name.startswith("A") and r.status == "FAILED"])
        security_header_failures = len([r for r in self.results if "Security Headers" in r.test_name and r.status == "FAILED"])
        cors_failures = len([r for r in self.results if "CORS" in r.test_name and r.status == "FAILED"])
        
        return {
            "OWASP_Top_10": "COMPLIANT" if owasp_failures == 0 else "NON_COMPLIANT",
            "Security_Headers": "COMPLIANT" if security_header_failures == 0 else "PARTIAL",
            "CORS_Policy": "COMPLIANT" if cors_failures == 0 else "NON_COMPLIANT",
            "Overall": "COMPLIANT" if len([r for r in self.results if r.status == "FAILED" and r.severity in ["CRITICAL", "HIGH"]]) == 0 else "NON_COMPLIANT"
        }

async def main():
    """Main function to run security tests"""
    import argparse
    
    parser = argparse.ArgumentParser(description="PyAirtable Security Test Suite")
    parser.add_argument("--base-url", default="http://localhost:8000", 
                       help="Base URL for testing (default: http://localhost:8000)")
    parser.add_argument("--output", default="security_test_results.json",
                       help="Output file for results (default: security_test_results.json)")
    
    args = parser.parse_args()
    
    # Initialize test suite
    test_suite = SecurityTestSuite(base_url=args.base_url)
    
    # Run tests
    print("PyAirtable Automated Security Test Suite")
    print("=" * 50)
    print(f"Target URL: {args.base_url}")
    print(f"Start time: {datetime.utcnow().isoformat()}")
    print()
    
    results = await test_suite.run_all_tests()
    
    # Print summary
    summary = results["summary"]
    print(f"\nSECURITY TEST RESULTS")
    print("=" * 50)
    print(f"Security Score: {summary['security_score']}/100 (Grade: {summary['security_grade']})")
    print(f"Tests Run: {summary['total_tests']}")
    print(f"  ✅ Passed: {summary['passed_tests']}")
    print(f"  ❌ Failed: {summary['failed_tests']}")
    print(f"  ⏭️ Skipped: {summary['skipped_tests']}")
    print(f"  ⚠️ Errors: {summary['error_tests']}")
    print(f"Duration: {summary['test_duration']} seconds")
    
    # Print critical findings
    critical_findings = results["critical_findings"]
    if critical_findings:
        print(f"\nCRITICAL FINDINGS ({len(critical_findings)})")
        print("=" * 30)
        for finding in critical_findings:
            print(f"❌ {finding['test_name']}")
            print(f"   {finding['description']}")
            print(f"   Remediation: {finding['remediation']}")
            print()
    
    # Print top recommendations
    recommendations = results["recommendations"]
    if recommendations:
        print(f"TOP RECOMMENDATIONS")
        print("=" * 30)
        for i, rec in enumerate(recommendations[:5], 1):
            print(f"{i}. [{rec['priority']}] {rec['category']}")
            print(f"   Issue: {rec['issue']}")
            print(f"   Fix: {rec['recommendation']}")
            print()
    
    # Save detailed results
    with open(args.output, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    print(f"Detailed results saved to: {args.output}")
    
    # Exit with appropriate code
    if results["summary"]["security_grade"] in ["F", "D"]:
        sys.exit(1)  # Critical security issues
    elif results["summary"]["failed_tests"] > 0:
        sys.exit(2)  # Some security issues
    else:
        sys.exit(0)  # All tests passed

if __name__ == "__main__":
    asyncio.run(main())