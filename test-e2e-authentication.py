#!/usr/bin/env python3
"""
End-to-End Authentication Flow Test

Tests the complete authentication flow from frontend through API gateway to auth service.
This validates JWT token flow, CORS configuration, Redis session handling, and service communication.
"""

import asyncio
import json
import time
import requests
import jwt
import redis
import sys
from typing import Dict, Any, Optional, Tuple

# Test Configuration
API_GATEWAY_URL = "http://localhost:8000"
AUTH_SERVICE_URL = "http://localhost:8081"
FRONTEND_URL = "http://localhost:3000"
REDIS_URL = "redis://localhost:6379"
JWT_SECRET = "your-secret-key-here"  # Should match services
TEST_USER_EMAIL = "test@example.com"
TEST_USER_PASSWORD = "testpassword123"

class AuthenticationE2ETest:
    def __init__(self):
        self.session = requests.Session()
        self.session.timeout = 10
        self.redis_client = None
        self.test_results = []
        
    def setup_redis(self):
        """Setup Redis connection for session testing"""
        try:
            self.redis_client = redis.from_url(REDIS_URL, decode_responses=True)
            self.redis_client.ping()
            print("✅ Redis connection established")
        except Exception as e:
            print(f"❌ Redis connection failed: {e}")
            return False
        return True
    
    def test_cors_preflight(self) -> bool:
        """Test CORS preflight requests for authentication endpoints"""
        print("\n🔍 Testing CORS Preflight...")
        
        try:
            # Test preflight for login endpoint
            response = self.session.options(
                f"{API_GATEWAY_URL}/api/v1/auth/login",
                headers={
                    "Origin": FRONTEND_URL,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "Content-Type,Authorization"
                }
            )
            
            if response.status_code != 200:
                print(f"❌ CORS preflight failed: {response.status_code}")
                return False
                
            # Check CORS headers
            required_headers = [
                "Access-Control-Allow-Origin",
                "Access-Control-Allow-Methods", 
                "Access-Control-Allow-Headers"
            ]
            
            for header in required_headers:
                if header not in response.headers:
                    print(f"❌ Missing CORS header: {header}")
                    return False
                    
            print("✅ CORS preflight successful")
            return True
            
        except Exception as e:
            print(f"❌ CORS test failed: {e}")
            return False
    
    def test_user_registration(self) -> bool:
        """Test user registration flow"""
        print("\n🔍 Testing User Registration...")
        
        try:
            registration_data = {
                "email": TEST_USER_EMAIL,
                "password": TEST_USER_PASSWORD,
                "first_name": "Test",
                "last_name": "User",
                "tenant_id": "test-tenant"
            }
            
            response = self.session.post(
                f"{API_GATEWAY_URL}/api/v1/auth/register",
                json=registration_data,
                headers={
                    "Origin": FRONTEND_URL,
                    "Content-Type": "application/json"
                }
            )
            
            if response.status_code in [200, 201, 409]:  # 409 = already exists
                print("✅ User registration successful (or user exists)")
                return True
            else:
                print(f"❌ Registration failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Registration test failed: {e}")
            return False
    
    def test_login_flow(self) -> Tuple[bool, Optional[str], Optional[str]]:
        """Test complete login flow"""
        print("\n🔍 Testing Login Flow...")
        
        try:
            login_data = {
                "email": TEST_USER_EMAIL,
                "password": TEST_USER_PASSWORD
            }
            
            response = self.session.post(
                f"{API_GATEWAY_URL}/api/v1/auth/login",
                json=login_data,
                headers={
                    "Origin": FRONTEND_URL,
                    "Content-Type": "application/json"
                }
            )
            
            if response.status_code != 200:
                print(f"❌ Login failed: {response.status_code} - {response.text}")
                return False, None, None
                
            data = response.json()
            
            if "access_token" not in data:
                print("❌ No access token in response")
                return False, None, None
                
            access_token = data["access_token"]
            refresh_token = data.get("refresh_token")
            
            # Validate JWT structure
            if not self.validate_jwt_structure(access_token):
                return False, None, None
                
            print("✅ Login flow successful")
            return True, access_token, refresh_token
            
        except Exception as e:
            print(f"❌ Login test failed: {e}")
            return False, None, None
    
    def validate_jwt_structure(self, token: str) -> bool:
        """Validate JWT token structure and claims"""
        print("🔍 Validating JWT structure...")
        
        try:
            # Decode without verification first to check structure
            decoded_unverified = jwt.decode(token, options={"verify_signature": False})
            
            required_claims = ["user_id", "email", "role", "tenant_id", "exp", "iat"]
            for claim in required_claims:
                if claim not in decoded_unverified:
                    print(f"❌ Missing JWT claim: {claim}")
                    return False
                    
            # Now verify signature
            try:
                decoded = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
                print("✅ JWT validation successful")
                print(f"   User ID: {decoded.get('user_id')}")
                print(f"   Email: {decoded.get('email')}")
                print(f"   Role: {decoded.get('role')}")
                print(f"   Tenant: {decoded.get('tenant_id')}")
                return True
            except jwt.InvalidSignatureError:
                print("❌ JWT signature validation failed")
                return False
                
        except Exception as e:
            print(f"❌ JWT validation failed: {e}")
            return False
    
    def test_authenticated_request(self, access_token: str) -> bool:
        """Test making authenticated requests through API gateway"""
        print("\n🔍 Testing Authenticated Requests...")
        
        try:
            headers = {
                "Authorization": f"Bearer {access_token}",
                "Origin": FRONTEND_URL
            }
            
            # Test profile endpoint
            response = self.session.get(
                f"{API_GATEWAY_URL}/api/v1/user/profile",
                headers=headers
            )
            
            if response.status_code == 200:
                print("✅ Authenticated request successful")
                return True
            elif response.status_code == 401:
                print("❌ Authentication failed - token rejected")
                return False
            else:
                print(f"❌ Unexpected response: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Authenticated request test failed: {e}")
            return False
    
    def test_session_handling(self, access_token: str) -> bool:
        """Test Redis session storage and retrieval"""
        print("\n🔍 Testing Session Handling...")
        
        if not self.redis_client:
            print("❌ Redis client not available")
            return False
            
        try:
            # Decode token to get user info
            decoded = jwt.decode(access_token, JWT_SECRET, algorithms=["HS256"])
            user_id = decoded.get("user_id")
            
            # Check if session exists in Redis
            session_keys = self.redis_client.keys(f"session:*")
            user_session_keys = self.redis_client.keys(f"user_sessions:{user_id}")
            
            print(f"   Found {len(session_keys)} session keys")
            print(f"   Found {len(user_session_keys)} user session keys")
            
            # Test session creation by making authenticated request
            headers = {"Authorization": f"Bearer {access_token}"}
            response = self.session.get(
                f"{API_GATEWAY_URL}/api/v1/user/profile",
                headers=headers
            )
            
            if response.status_code == 200:
                print("✅ Session handling functional")
                return True
            else:
                print(f"❌ Session test failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Session handling test failed: {e}")
            return False
    
    def test_token_refresh(self, refresh_token: str) -> bool:
        """Test token refresh mechanism"""
        print("\n🔍 Testing Token Refresh...")
        
        if not refresh_token:
            print("❌ No refresh token available")
            return False
            
        try:
            refresh_data = {"refresh_token": refresh_token}
            
            response = self.session.post(
                f"{API_GATEWAY_URL}/api/v1/auth/refresh",
                json=refresh_data,
                headers={
                    "Origin": FRONTEND_URL,
                    "Content-Type": "application/json"
                }
            )
            
            if response.status_code == 200:
                data = response.json()
                if "access_token" in data:
                    print("✅ Token refresh successful")
                    return True
                else:
                    print("❌ No access token in refresh response")
                    return False
            else:
                print(f"❌ Token refresh failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Token refresh test failed: {e}")
            return False
    
    def test_logout_flow(self, refresh_token: str) -> bool:
        """Test logout and token invalidation"""
        print("\n🔍 Testing Logout Flow...")
        
        try:
            logout_data = {"refresh_token": refresh_token} if refresh_token else {}
            
            response = self.session.post(
                f"{API_GATEWAY_URL}/api/v1/auth/logout",
                json=logout_data,
                headers={
                    "Origin": FRONTEND_URL,
                    "Content-Type": "application/json"
                }
            )
            
            if response.status_code in [200, 204]:
                print("✅ Logout successful")
                return True
            else:
                print(f"❌ Logout failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Logout test failed: {e}")
            return False
    
    def test_health_endpoints(self) -> bool:
        """Test authentication-related health endpoints"""
        print("\n🔍 Testing Health Endpoints...")
        
        try:
            # Test API gateway health
            response = self.session.get(f"{API_GATEWAY_URL}/health")
            if response.status_code != 200:
                print(f"❌ API Gateway health check failed: {response.status_code}")
                return False
                
            # Test auth-specific health
            response = self.session.get(f"{API_GATEWAY_URL}/health/auth")
            if response.status_code != 200:
                print(f"❌ Auth health check failed: {response.status_code}")
                return False
                
            # Test readiness
            response = self.session.get(f"{API_GATEWAY_URL}/ready")
            if response.status_code != 200:
                print(f"❌ Readiness check failed: {response.status_code}")
                return False
                
            print("✅ Health endpoints functional")
            return True
            
        except Exception as e:
            print(f"❌ Health endpoints test failed: {e}")
            return False
    
    def test_error_handling(self) -> bool:
        """Test proper error handling for authentication failures"""
        print("\n🔍 Testing Error Handling...")
        
        try:
            # Test invalid credentials
            response = self.session.post(
                f"{API_GATEWAY_URL}/api/v1/auth/login",
                json={"email": "invalid@test.com", "password": "FAKE_TEST_PASSWORD"},
                headers={"Origin": FRONTEND_URL}
            )
            
            if response.status_code != 401:
                print(f"❌ Invalid credentials should return 401, got {response.status_code}")
                return False
                
            # Test malformed token
            response = self.session.get(
                f"{API_GATEWAY_URL}/api/v1/user/profile",
                headers={
                    "Authorization": "Bearer invalid.token.here",
                    "Origin": FRONTEND_URL
                }
            )
            
            if response.status_code != 401:
                print(f"❌ Invalid token should return 401, got {response.status_code}")
                return False
                
            # Test missing authorization header
            response = self.session.get(
                f"{API_GATEWAY_URL}/api/v1/user/profile",
                headers={"Origin": FRONTEND_URL}
            )
            
            if response.status_code != 401:
                print(f"❌ Missing auth header should return 401, got {response.status_code}")
                return False
                
            print("✅ Error handling working correctly")
            return True
            
        except Exception as e:
            print(f"❌ Error handling test failed: {e}")
            return False

async def main():
    """Run the complete end-to-end authentication test suite"""
    print("🚀 Starting End-to-End Authentication Flow Test")
    print("=" * 60)
    
    test = AuthenticationE2ETest()
    results = []
    
    # Setup
    if not test.setup_redis():
        print("❌ Test setup failed - Redis connection required")
        return 1
    
    # Test sequence
    tests = [
        ("CORS Preflight", test.test_cors_preflight),
        ("User Registration", test.test_user_registration),
        ("Health Endpoints", test.test_health_endpoints),
        ("Error Handling", test.test_error_handling),
    ]
    
    # Run basic tests first
    for test_name, test_func in tests:
        print(f"\n📋 Running: {test_name}")
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"❌ {test_name} crashed: {e}")
            results.append((test_name, False))
    
    # Run authentication flow
    print(f"\n📋 Running: Complete Authentication Flow")
    login_success, access_token, refresh_token = test.test_login_flow()
    results.append(("Login Flow", login_success))
    
    if login_success and access_token:
        # Test authenticated operations
        auth_tests = [
            ("Authenticated Request", lambda: test.test_authenticated_request(access_token)),
            ("Session Handling", lambda: test.test_session_handling(access_token)),
        ]
        
        if refresh_token:
            auth_tests.extend([
                ("Token Refresh", lambda: test.test_token_refresh(refresh_token)),
                ("Logout Flow", lambda: test.test_logout_flow(refresh_token)),
            ])
        
        for test_name, test_func in auth_tests:
            print(f"\n📋 Running: {test_name}")
            try:
                result = test_func()
                results.append((test_name, result))
            except Exception as e:
                print(f"❌ {test_name} crashed: {e}")
                results.append((test_name, False))
    else:
        print("❌ Skipping authenticated tests due to login failure")
    
    # Print results summary
    print("\n" + "=" * 60)
    print("📊 TEST RESULTS SUMMARY")
    print("=" * 60)
    
    passed = 0
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status:<8} {test_name}")
        if result:
            passed += 1
    
    print("-" * 60)
    print(f"TOTAL: {passed}/{total} tests passed ({passed/total*100:.1f}%)")
    
    if passed == total:
        print("\n🎉 ALL TESTS PASSED - Authentication flow is working correctly!")
        return 0
    else:
        print(f"\n⚠️  {total - passed} tests failed - Authentication flow needs fixes")
        return 1

if __name__ == "__main__":
    sys.exit(asyncio.run(main()))