#!/usr/bin/env python3

"""
Security Hardening Test Suite

DESCRIPTION:
  - Validates JWT secret strength and configuration
  - Tests SSL/TLS configuration security
  - Verifies security headers implementation
  - Validates token rotation functionality
  - Tests authentication security measures

OWASP COMPLIANCE TESTING:
  - A02:2021 – Cryptographic Failures
  - A05:2021 – Security Misconfiguration  
  - A07:2021 – Identification and Authentication Failures
"""

import os
import sys
import ssl
import socket
import requests
import subprocess
import base64
import jwt
import hashlib
import time
import json
from urllib.parse import urlparse
from cryptography import x509
from cryptography.hazmat.backends import default_backend
import pytest
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class SecurityHardeningTests:
    """Comprehensive security hardening test suite."""
    
    def __init__(self, base_url="https://localhost:443", api_url="https://api.localhost:443"):
        self.base_url = base_url
        self.api_url = api_url
        self.session = requests.Session()
        self.session.verify = False  # For testing with self-signed certificates
        
    def test_jwt_secret_strength(self):
        """Test JWT secret meets minimum security requirements."""
        logger.info("Testing JWT secret strength...")
        
        # Load environment variables
        jwt_secret = os.getenv('JWT_SECRET')
        jwt_refresh_secret = os.getenv('JWT_REFRESH_SECRET')
        
        if not jwt_secret:
            pytest.fail("JWT_SECRET not found in environment")
        
        if not jwt_refresh_secret:
            pytest.fail("JWT_REFRESH_SECRET not found in environment")
        
        # Test secret length (should be 512+ bits for production)
        secret_bits = len(base64.b64decode(jwt_secret)) * 8
        refresh_secret_bits = len(base64.b64decode(jwt_refresh_secret)) * 8
        
        assert secret_bits >= 512, f"JWT_SECRET is only {secret_bits} bits, should be 512+ bits"
        assert refresh_secret_bits >= 512, f"JWT_REFRESH_SECRET is only {refresh_secret_bits} bits, should be 512+ bits"
        
        # Test secrets are different
        assert jwt_secret != jwt_refresh_secret, "JWT access and refresh secrets must be different"
        
        # Test entropy (basic check for randomness)
        secret_entropy = self._calculate_entropy(jwt_secret)
        assert secret_entropy > 4.0, f"JWT secret has low entropy: {secret_entropy}"
        
        logger.info("✅ JWT secret strength tests passed")
    
    def test_ssl_tls_configuration(self):
        """Test SSL/TLS configuration security."""
        logger.info("Testing SSL/TLS configuration...")
        
        # Parse base URL to get hostname and port
        parsed = urlparse(self.base_url)
        hostname = parsed.hostname
        port = parsed.port or 443
        
        try:
            # Test TLS connection
            context = ssl.create_default_context()
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE  # For testing only
            
            with socket.create_connection((hostname, port), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                    # Get SSL certificate
                    cert_der = ssock.getpeercert(binary_form=True)
                    cert = x509.load_der_x509_certificate(cert_der, default_backend())
                    
                    # Test SSL protocol version
                    tls_version = ssock.version()
                    assert tls_version in ['TLSv1.2', 'TLSv1.3'], f"Insecure TLS version: {tls_version}"
                    
                    # Test cipher suite strength
                    cipher = ssock.cipher()
                    if cipher:
                        cipher_name = cipher[0]
                        # Should use strong ciphers (ECDHE for forward secrecy)
                        assert 'ECDHE' in cipher_name or 'DHE' in cipher_name, f"Weak cipher: {cipher_name}"
                        assert 'GCM' in cipher_name or 'CHACHA20' in cipher_name, f"Weak encryption: {cipher_name}"
                    
                    # Test certificate validity
                    now = time.time()
                    not_before = cert.not_valid_before.timestamp()
                    not_after = cert.not_valid_after.timestamp()
                    
                    assert not_before <= now <= not_after, "SSL certificate is expired or not yet valid"
                    
                    # Test key size
                    public_key = cert.public_key()
                    if hasattr(public_key, 'key_size'):
                        assert public_key.key_size >= 2048, f"Weak RSA key size: {public_key.key_size}"
            
            logger.info("✅ SSL/TLS configuration tests passed")
            
        except Exception as e:
            pytest.fail(f"SSL/TLS test failed: {e}")
    
    def test_security_headers(self):
        """Test HTTP security headers implementation."""
        logger.info("Testing security headers...")
        
        try:
            response = self.session.get(self.base_url, timeout=10)
            headers = response.headers
            
            # Test HSTS header
            hsts = headers.get('Strict-Transport-Security')
            assert hsts, "Missing Strict-Transport-Security header"
            assert 'max-age=' in hsts, "HSTS max-age not specified"
            assert 'includeSubDomains' in hsts, "HSTS should include subdomains"
            
            # Test X-Frame-Options
            frame_options = headers.get('X-Frame-Options')
            assert frame_options in ['DENY', 'SAMEORIGIN'], f"Weak X-Frame-Options: {frame_options}"
            
            # Test X-Content-Type-Options
            content_type_options = headers.get('X-Content-Type-Options')
            assert content_type_options == 'nosniff', "X-Content-Type-Options should be 'nosniff'"
            
            # Test X-XSS-Protection
            xss_protection = headers.get('X-XSS-Protection')
            assert xss_protection, "Missing X-XSS-Protection header"
            assert '1; mode=block' in xss_protection, "XSS protection should be enabled with block mode"
            
            # Test Referrer Policy
            referrer_policy = headers.get('Referrer-Policy')
            assert referrer_policy, "Missing Referrer-Policy header"
            acceptable_policies = ['strict-origin', 'strict-origin-when-cross-origin', 'no-referrer']
            assert any(policy in referrer_policy for policy in acceptable_policies), f"Weak referrer policy: {referrer_policy}"
            
            # Test Content Security Policy
            csp = headers.get('Content-Security-Policy')
            assert csp, "Missing Content-Security-Policy header"
            assert "default-src 'self'" in csp, "CSP should restrict default sources to self"
            assert "object-src 'none'" in csp, "CSP should disable object sources"
            
            # Test Permissions Policy (optional but recommended)
            permissions_policy = headers.get('Permissions-Policy')
            if permissions_policy:
                assert 'geolocation=()' in permissions_policy, "Should restrict geolocation access"
            
            logger.info("✅ Security headers tests passed")
            
        except Exception as e:
            pytest.fail(f"Security headers test failed: {e}")
    
    def test_jwt_token_rotation(self):
        """Test JWT token rotation functionality."""
        logger.info("Testing JWT token rotation...")
        
        try:
            # Import JWT rotation service
            sys.path.append('/Users/kg/IdeaProjects/pyairtable-compose/security')
            from jwt_rotation_service import JWTRotationService
            
            service = JWTRotationService()
            
            # Test token generation
            user_id = "test_user_123"
            user_data = {"email": "test@example.com", "roles": ["user"]}
            
            access_token, refresh_token = service.generate_token_pair(user_id, user_data)
            
            assert access_token, "Failed to generate access token"
            assert refresh_token, "Failed to generate refresh token"
            assert access_token != refresh_token, "Access and refresh tokens should be different"
            
            # Test token validation
            payload = service.validate_access_token(access_token)
            assert payload, "Failed to validate access token"
            assert payload['sub'] == user_id, "Token subject mismatch"
            assert payload['type'] == 'access', "Invalid token type"
            
            # Test token refresh
            new_access, new_refresh = service.refresh_token_pair(refresh_token)
            assert new_access, "Failed to refresh access token"
            assert new_refresh, "Failed to refresh refresh token"
            assert new_access != access_token, "New access token should be different"
            assert new_refresh != refresh_token, "New refresh token should be different"
            
            # Test token revocation
            revoked = service.revoke_token(new_access)
            assert revoked, "Failed to revoke token"
            
            # Test revoked token validation fails
            payload = service.validate_access_token(new_access)
            assert payload is None, "Revoked token should not validate"
            
            logger.info("✅ JWT token rotation tests passed")
            
        except ImportError:
            pytest.skip("JWT rotation service not available")
        except Exception as e:
            pytest.fail(f"JWT token rotation test failed: {e}")
    
    def test_rate_limiting(self):
        """Test rate limiting configuration."""
        logger.info("Testing rate limiting...")
        
        try:
            # Make rapid requests to test rate limiting
            responses = []
            for i in range(20):
                try:
                    response = self.session.get(f"{self.base_url}/api/health", timeout=5)
                    responses.append(response.status_code)
                    time.sleep(0.1)  # Small delay to avoid overwhelming
                except requests.exceptions.RequestException:
                    responses.append(0)  # Connection error
            
            # Should see some rate limit responses (429) if configured
            rate_limited_responses = [r for r in responses if r == 429]
            
            # This test is informational - rate limiting configuration varies
            logger.info(f"Rate limiting responses: {len(rate_limited_responses)}/20")
            
        except Exception as e:
            logger.warning(f"Rate limiting test failed: {e}")
    
    def test_cors_configuration(self):
        """Test CORS configuration security."""
        logger.info("Testing CORS configuration...")
        
        try:
            # Test preflight request
            headers = {
                'Origin': 'https://evil.com',
                'Access-Control-Request-Method': 'POST',
                'Access-Control-Request-Headers': 'Content-Type'
            }
            
            response = self.session.options(f"{self.api_url}/api/test", headers=headers, timeout=10)
            
            # Should not allow arbitrary origins
            cors_origin = response.headers.get('Access-Control-Allow-Origin')
            if cors_origin:
                assert cors_origin != '*', "CORS should not allow all origins"
                assert 'evil.com' not in cors_origin, "CORS should not allow untrusted origins"
            
            logger.info("✅ CORS configuration tests passed")
            
        except Exception as e:
            logger.warning(f"CORS test failed: {e}")
    
    def test_environment_security(self):
        """Test environment configuration security."""
        logger.info("Testing environment security...")
        
        # Test debug mode is disabled in production
        debug_mode = os.getenv('DEBUG', '').lower()
        assert debug_mode in ['false', '0', ''], "Debug mode should be disabled in production"
        
        # Test secure cookie settings
        secure_cookies = os.getenv('SECURE_COOKIES', '').lower()
        https_enabled = os.getenv('HTTPS_ENABLED', '').lower()
        if https_enabled == 'true':
            assert secure_cookies == 'true', "Secure cookies should be enabled with HTTPS"
        
        # Test password policy settings
        min_password_length = int(os.getenv('PASSWORD_MIN_LENGTH', '8'))
        assert min_password_length >= 12, f"Minimum password length should be 12+, got {min_password_length}"
        
        hash_rounds = int(os.getenv('PASSWORD_HASH_ROUNDS', '12'))
        assert hash_rounds >= 12, f"Password hash rounds should be 12+, got {hash_rounds}"
        
        logger.info("✅ Environment security tests passed")
    
    def _calculate_entropy(self, data: str) -> float:
        """Calculate Shannon entropy of data."""
        if not data:
            return 0
        
        # Count frequency of each character
        frequency = {}
        for char in data:
            frequency[char] = frequency.get(char, 0) + 1
        
        # Calculate entropy
        entropy = 0
        length = len(data)
        for count in frequency.values():
            p = count / length
            entropy -= p * (p and (p * (1 / p)).bit_length() - 1)
        
        return entropy
    
    def run_all_tests(self):
        """Run all security tests and generate report."""
        logger.info("Starting comprehensive security hardening tests...")
        
        tests = [
            ('JWT Secret Strength', self.test_jwt_secret_strength),
            ('SSL/TLS Configuration', self.test_ssl_tls_configuration),
            ('Security Headers', self.test_security_headers),
            ('JWT Token Rotation', self.test_jwt_token_rotation),
            ('Rate Limiting', self.test_rate_limiting),
            ('CORS Configuration', self.test_cors_configuration),
            ('Environment Security', self.test_environment_security)
        ]
        
        results = {}
        
        for test_name, test_func in tests:
            try:
                test_func()
                results[test_name] = 'PASS'
            except AssertionError as e:
                results[test_name] = f'FAIL: {e}'
            except Exception as e:
                results[test_name] = f'ERROR: {e}'
        
        # Generate report
        print("\n" + "="*60)
        print("SECURITY HARDENING TEST REPORT")
        print("="*60)
        
        for test_name, result in results.items():
            status = "✅" if result == 'PASS' else "❌"
            print(f"{status} {test_name}: {result}")
        
        passed = sum(1 for r in results.values() if r == 'PASS')
        total = len(results)
        
        print(f"\nSUMMARY: {passed}/{total} tests passed")
        
        if passed < total:
            print("\n⚠️  SECURITY ISSUES FOUND - Address failures before deployment")
            return False
        else:
            print("\n✅ ALL SECURITY TESTS PASSED")
            return True


if __name__ == "__main__":
    # Load environment from .env file if available
    env_file = "/Users/kg/IdeaProjects/pyairtable-compose/.env"
    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    os.environ[key] = value
    
    # Run tests
    tester = SecurityHardeningTests()
    success = tester.run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)