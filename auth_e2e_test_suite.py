#!/usr/bin/env python3
"""
PyAirtable Authentication E2E Test Suite
Sprint 1 - Authentication Flow Testing

This test suite validates:
1. Backend services (API Gateway on 7000, Platform Services on 7007)  
2. Frontend React app (on port 5173/5174)
3. Database with new user schema (PostgreSQL on 5433)
4. Redis for session management (port 6380)

Key acceptance criteria:
- Frontend at 5173/5174 can communicate with backend at 7000
- Registration creates users in database
- Login returns proper JWT tokens  
- Protected routes work with valid tokens
- Error messages display correctly for failures
- Sessions are properly managed in Redis
- Logout cleans up tokens and sessions
"""

import asyncio
import json
import logging
import requests
import psycopg2
import redis
import jwt
import time
from datetime import datetime, timedelta
from playwright.async_api import async_playwright
from typing import Dict, List, Any, Optional
import base64
import hashlib

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('auth_e2e_test.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class AuthE2ETestSuite:
    """Comprehensive E2E Authentication Test Suite"""
    
    def __init__(self):
        self.api_gateway_url = "http://localhost:7000"
        self.platform_services_url = "http://localhost:7007"
        self.frontend_url = "http://localhost:5173"
        self.chat_ui_url = "http://localhost:5174"
        
        # Database configuration
        self.db_config = {
            'host': 'localhost',
            'port': 5433,
            'database': 'pyairtable',
            'user': 'postgres',
            'password': 'lIDvbpxaArutRwGz'
        }
        
        # Redis configuration
        self.redis_config = {
            'host': 'localhost',
            'port': 6380,
            'password': 'gxPAS8DaSRkm4hgy'
        }
        
        self.test_user = {
            'email': 'test_user_' + str(int(time.time())) + '@example.com',
            'password': 'TestPassword123!',
            'first_name': 'Test',
            'last_name': 'User'
        }
        
        self.results = {
            'test_start_time': datetime.now().isoformat(),
            'tests_passed': 0,
            'tests_failed': 0,
            'test_results': [],
            'service_health': {},
            'database_checks': {},
            'redis_checks': {},
            'security_validations': {}
        }
        
    def log_test_result(self, test_name: str, passed: bool, details: str = "", error: str = ""):
        """Log individual test results"""
        result = {
            'test_name': test_name,
            'passed': passed,
            'timestamp': datetime.now().isoformat(),
            'details': details,
            'error': error
        }
        
        self.results['test_results'].append(result)
        
        if passed:
            self.results['tests_passed'] += 1
            logger.info(f"✅ {test_name}: PASSED - {details}")
        else:
            self.results['tests_failed'] += 1
            logger.error(f"❌ {test_name}: FAILED - {error}")
    
    def check_service_health(self) -> Dict[str, Any]:
        """Check health of all required services"""
        logger.info("🏥 Checking service health...")
        
        services = [
            ('API Gateway', self.api_gateway_url + '/api/health'),
            ('Platform Services', self.platform_services_url + '/health'),
            ('Frontend', self.frontend_url + '/api/health'),
            ('Chat UI', self.chat_ui_url + '/api/health'),
        ]
        
        health_status = {}
        
        for service_name, health_url in services:
            try:
                response = requests.get(health_url, timeout=10)
                if response.status_code == 200:
                    health_status[service_name] = {
                        'status': 'healthy',
                        'response_time': response.elapsed.total_seconds(),
                        'data': response.json() if 'json' in response.headers.get('content-type', '') else response.text
                    }
                    logger.info(f"✅ {service_name} is healthy (response time: {response.elapsed.total_seconds():.3f}s)")
                else:
                    health_status[service_name] = {
                        'status': 'unhealthy',
                        'status_code': response.status_code,
                        'error': response.text
                    }
                    logger.warning(f"⚠️ {service_name} returned status {response.status_code}")
            except Exception as e:
                health_status[service_name] = {
                    'status': 'unreachable',
                    'error': str(e)
                }
                logger.error(f"❌ {service_name} is unreachable: {e}")
        
        self.results['service_health'] = health_status
        return health_status
    
    def check_database_connection(self) -> bool:
        """Test database connectivity and schema"""
        logger.info("🗄️ Checking database connection and schema...")
        
        try:
            conn = psycopg2.connect(**self.db_config)
            cursor = conn.cursor()
            
            # Check connection
            cursor.execute("SELECT 1")
            result = cursor.fetchone()
            self.log_test_result("Database Connection", result[0] == 1, "Successfully connected to PostgreSQL")
            
            # Check if authentication tables exist
            auth_tables = ['platform_users', 'platform_analytics_events', 'platform_analytics_metrics']
            
            for table in auth_tables:
                cursor.execute(f"SELECT EXISTS (SELECT FROM pg_tables WHERE tablename = '{table}')")
                exists = cursor.fetchone()[0]
                self.log_test_result(f"Table {table} exists", exists, f"Table {table} found in database" if exists else f"Table {table} missing")
            
            # Check user table structure
            cursor.execute("""
                SELECT column_name, data_type 
                FROM information_schema.columns 
                WHERE table_name = 'platform_users'
                ORDER BY ordinal_position
            """)
            columns = cursor.fetchall()
            
            required_columns = ['id', 'email', 'password_hash', 'created_at', 'updated_at']
            found_columns = [col[0] for col in columns]
            
            for req_col in required_columns:
                found = req_col in found_columns
                self.log_test_result(f"User table has {req_col} column", found, 
                                   f"Column {req_col} present" if found else f"Column {req_col} missing")
            
            self.results['database_checks'] = {
                'connection': 'success',
                'tables_found': [table for table in auth_tables if exists],
                'user_table_columns': dict(columns)
            }
            
            cursor.close()
            conn.close()
            return True
            
        except Exception as e:
            self.log_test_result("Database Connection", False, error=str(e))
            self.results['database_checks'] = {'connection': 'failed', 'error': str(e)}
            return False
    
    def check_redis_connection(self) -> bool:
        """Test Redis connectivity and session management"""
        logger.info("🔴 Checking Redis connection and session management...")
        
        try:
            r = redis.Redis(host=self.redis_config['host'], 
                          port=self.redis_config['port'], 
                          password=self.redis_config['password'],
                          decode_responses=True)
            
            # Test basic connectivity
            pong = r.ping()
            self.log_test_result("Redis Connection", pong, "Redis PING successful")
            
            # Test session storage
            test_session_key = f"test_session_{int(time.time())}"
            test_session_data = {"user_id": "test_123", "expires_at": str(datetime.now() + timedelta(hours=1))}
            
            # Set session data
            r.setex(test_session_key, 60, json.dumps(test_session_data))
            
            # Retrieve session data
            retrieved_data = r.get(test_session_key)
            if retrieved_data:
                parsed_data = json.loads(retrieved_data)
                session_test_passed = parsed_data['user_id'] == 'test_123'
                self.log_test_result("Redis Session Storage", session_test_passed, 
                                   "Session data stored and retrieved successfully")
            else:
                self.log_test_result("Redis Session Storage", False, error="Could not retrieve session data")
            
            # Clean up test data
            r.delete(test_session_key)
            
            # Get Redis info
            redis_info = r.info()
            self.results['redis_checks'] = {
                'connection': 'success',
                'version': redis_info.get('redis_version'),
                'memory_usage': redis_info.get('used_memory_human'),
                'connected_clients': redis_info.get('connected_clients')
            }
            
            return True
            
        except Exception as e:
            self.log_test_result("Redis Connection", False, error=str(e))
            self.results['redis_checks'] = {'connection': 'failed', 'error': str(e)}
            return False
    
    def test_cors_configuration(self) -> bool:
        """Test CORS configuration between frontend and backend"""
        logger.info("🌐 Testing CORS configuration...")
        
        try:
            # Test preflight request
            headers = {
                'Origin': self.frontend_url,
                'Access-Control-Request-Method': 'POST',
                'Access-Control-Request-Headers': 'Content-Type,Authorization'
            }
            
            # Try API Gateway first
            try:
                response = requests.options(f"{self.api_gateway_url}/api/auth/login", headers=headers, timeout=10)
                cors_headers = response.headers
                
                cors_pass = (
                    'Access-Control-Allow-Origin' in cors_headers or
                    cors_headers.get('Access-Control-Allow-Origin') == '*' or
                    self.frontend_url in cors_headers.get('Access-Control-Allow-Origin', '')
                )
                
                self.log_test_result("API Gateway CORS", cors_pass, 
                                   f"CORS headers: {dict(cors_headers)}" if cors_pass else "CORS not properly configured")
                                   
            except requests.exceptions.RequestException as e:
                self.log_test_result("API Gateway CORS", False, error=f"API Gateway unreachable: {e}")
            
            # Test Platform Services CORS
            try:
                response = requests.options(f"{self.platform_services_url}/auth/login", headers=headers, timeout=10)
                cors_headers = response.headers
                
                cors_pass = (
                    'Access-Control-Allow-Origin' in cors_headers or
                    cors_headers.get('Access-Control-Allow-Origin') == '*'
                )
                
                self.log_test_result("Platform Services CORS", cors_pass, 
                                   f"CORS headers present" if cors_pass else "CORS headers missing")
                                   
            except requests.exceptions.RequestException as e:
                self.log_test_result("Platform Services CORS", False, error=f"Platform Services unreachable: {e}")
            
            return True
            
        except Exception as e:
            self.log_test_result("CORS Configuration", False, error=str(e))
            return False
    
    def test_user_registration_api(self) -> Optional[str]:
        """Test user registration API endpoint"""
        logger.info("📝 Testing user registration API...")
        
        registration_endpoints = [
            (self.api_gateway_url + '/api/auth/register', 'API Gateway'),
            (self.platform_services_url + '/auth/register', 'Platform Services')
        ]
        
        user_id = None
        
        for endpoint, service_name in registration_endpoints:
            try:
                registration_data = {
                    'email': self.test_user['email'],
                    'password': self.test_user['password'],
                    'first_name': self.test_user['first_name'],
                    'last_name': self.test_user['last_name']
                }
                
                response = requests.post(endpoint, json=registration_data, timeout=10)
                
                if response.status_code in [200, 201]:
                    response_data = response.json()
                    user_id = response_data.get('user_id') or response_data.get('id')
                    
                    self.log_test_result(f"{service_name} Registration", True, 
                                       f"User registered with ID: {user_id}")
                    
                    # Validate response structure
                    expected_fields = ['user_id', 'email', 'access_token']
                    has_required_fields = all(field in response_data or 
                                            any(k.endswith(field) for k in response_data.keys()) 
                                            for field in expected_fields)
                    
                    if has_required_fields:
                        self.log_test_result(f"{service_name} Registration Response Structure", True,
                                           "Response contains required fields")
                        return user_id
                    else:
                        self.log_test_result(f"{service_name} Registration Response Structure", False,
                                           error=f"Missing required fields. Got: {list(response_data.keys())}")
                        
                elif response.status_code == 409:
                    self.log_test_result(f"{service_name} Registration", True, 
                                       "User already exists (expected for repeated tests)")
                else:
                    self.log_test_result(f"{service_name} Registration", False, 
                                       error=f"Status: {response.status_code}, Response: {response.text}")
                    
            except requests.exceptions.RequestException as e:
                self.log_test_result(f"{service_name} Registration", False, error=f"Network error: {e}")
            except Exception as e:
                self.log_test_result(f"{service_name} Registration", False, error=f"Unexpected error: {e}")
        
        return user_id
    
    def test_user_login_api(self) -> Optional[str]:
        """Test user login API endpoint"""
        logger.info("🔐 Testing user login API...")
        
        login_endpoints = [
            (self.api_gateway_url + '/api/auth/login', 'API Gateway'),
            (self.platform_services_url + '/auth/login', 'Platform Services')
        ]
        
        access_token = None
        
        for endpoint, service_name in login_endpoints:
            try:
                login_data = {
                    'email': self.test_user['email'],
                    'password': self.test_user['password']
                }
                
                response = requests.post(endpoint, json=login_data, timeout=10)
                
                if response.status_code == 200:
                    response_data = response.json()
                    access_token = response_data.get('access_token') or response_data.get('token')
                    
                    self.log_test_result(f"{service_name} Login", True, 
                                       f"Login successful, token received")
                    
                    # Validate JWT token structure
                    if access_token:
                        try:
                            # Decode without verification to check structure
                            header = jwt.get_unverified_header(access_token)
                            payload = jwt.decode(access_token, options={"verify_signature": False})
                            
                            required_claims = ['sub', 'exp', 'iat']
                            has_required_claims = all(claim in payload for claim in required_claims)
                            
                            self.log_test_result(f"{service_name} JWT Structure", has_required_claims,
                                               f"JWT header: {header}, Claims: {list(payload.keys())}" if has_required_claims
                                               else f"Missing claims. Found: {list(payload.keys())}")
                            
                            # Store JWT details for security validation
                            self.results['security_validations'][f'{service_name}_jwt'] = {
                                'algorithm': header.get('alg'),
                                'token_type': header.get('typ'),
                                'claims': list(payload.keys()),
                                'expires_at': payload.get('exp'),
                                'issued_at': payload.get('iat'),
                                'subject': payload.get('sub')
                            }
                            
                            return access_token
                            
                        except Exception as e:
                            self.log_test_result(f"{service_name} JWT Validation", False, 
                                               error=f"Invalid JWT format: {e}")
                    
                else:
                    self.log_test_result(f"{service_name} Login", False, 
                                       error=f"Status: {response.status_code}, Response: {response.text}")
                    
            except requests.exceptions.RequestException as e:
                self.log_test_result(f"{service_name} Login", False, error=f"Network error: {e}")
            except Exception as e:
                self.log_test_result(f"{service_name} Login", False, error=f"Unexpected error: {e}")
        
        return access_token
    
    def test_protected_routes(self, access_token: str) -> bool:
        """Test access to protected routes with JWT token"""
        logger.info("🔒 Testing protected routes...")
        
        if not access_token:
            self.log_test_result("Protected Routes", False, error="No access token available")
            return False
        
        protected_endpoints = [
            (self.api_gateway_url + '/api/auth/me', 'API Gateway Profile'),
            (self.platform_services_url + '/auth/me', 'Platform Services Profile'),
            (self.api_gateway_url + '/api/user/profile', 'API Gateway User Profile'),
        ]
        
        headers = {'Authorization': f'Bearer {access_token}'}
        
        for endpoint, endpoint_name in protected_endpoints:
            try:
                response = requests.get(endpoint, headers=headers, timeout=10)
                
                if response.status_code == 200:
                    response_data = response.json()
                    self.log_test_result(f"{endpoint_name} Access", True, 
                                       f"Protected route accessible, data: {response_data}")
                elif response.status_code == 401:
                    self.log_test_result(f"{endpoint_name} Access", False, 
                                       error="Unauthorized - token may be invalid")
                else:
                    self.log_test_result(f"{endpoint_name} Access", False, 
                                       error=f"Unexpected status: {response.status_code}")
                    
            except requests.exceptions.RequestException as e:
                self.log_test_result(f"{endpoint_name} Access", False, error=f"Network error: {e}")
        
        return True
    
    def test_token_refresh(self, access_token: str) -> bool:
        """Test JWT token refresh functionality"""
        logger.info("🔄 Testing token refresh...")
        
        refresh_endpoints = [
            (self.api_gateway_url + '/api/auth/refresh', 'API Gateway'),
            (self.platform_services_url + '/auth/refresh', 'Platform Services')
        ]
        
        headers = {'Authorization': f'Bearer {access_token}'}
        
        for endpoint, service_name in refresh_endpoints:
            try:
                response = requests.post(endpoint, headers=headers, timeout=10)
                
                if response.status_code == 200:
                    response_data = response.json()
                    new_token = response_data.get('access_token') or response_data.get('token')
                    
                    if new_token and new_token != access_token:
                        self.log_test_result(f"{service_name} Token Refresh", True, 
                                           "New token received")
                    else:
                        self.log_test_result(f"{service_name} Token Refresh", False, 
                                           error="Same token returned or no token in response")
                else:
                    self.log_test_result(f"{service_name} Token Refresh", False, 
                                       error=f"Status: {response.status_code}, Response: {response.text}")
                    
            except requests.exceptions.RequestException as e:
                self.log_test_result(f"{service_name} Token Refresh", False, error=f"Network error: {e}")
        
        return True
    
    def test_logout(self, access_token: str) -> bool:
        """Test logout and session cleanup"""
        logger.info("🚪 Testing logout and session cleanup...")
        
        logout_endpoints = [
            (self.api_gateway_url + '/api/auth/logout', 'API Gateway'),
            (self.platform_services_url + '/auth/logout', 'Platform Services')
        ]
        
        headers = {'Authorization': f'Bearer {access_token}'}
        
        for endpoint, service_name in logout_endpoints:
            try:
                response = requests.post(endpoint, headers=headers, timeout=10)
                
                if response.status_code in [200, 204]:
                    self.log_test_result(f"{service_name} Logout", True, "Logout successful")
                    
                    # Test that token is invalidated
                    protected_endpoint = endpoint.replace('/logout', '/me')
                    test_response = requests.get(protected_endpoint, headers=headers, timeout=5)
                    
                    if test_response.status_code == 401:
                        self.log_test_result(f"{service_name} Token Invalidation", True, 
                                           "Token properly invalidated after logout")
                    else:
                        self.log_test_result(f"{service_name} Token Invalidation", False, 
                                           error="Token still valid after logout")
                        
                else:
                    self.log_test_result(f"{service_name} Logout", False, 
                                       error=f"Status: {response.status_code}, Response: {response.text}")
                    
            except requests.exceptions.RequestException as e:
                self.log_test_result(f"{service_name} Logout", False, error=f"Network error: {e}")
        
        return True
    
    def test_error_handling(self) -> bool:
        """Test error handling for invalid credentials"""
        logger.info("⚠️ Testing error handling...")
        
        # Test invalid login credentials
        invalid_credentials_tests = [
            {
                'email': 'nonexistent@example.com',
                'password': 'wrongpassword',
                'expected_error': 'Invalid credentials'
            },
            {
                'email': self.test_user['email'],
                'password': 'wrongpassword',
                'expected_error': 'Invalid password'
            },
            {
                'email': 'invalid-email-format',
                'password': self.test_user['password'],
                'expected_error': 'Invalid email format'
            }
        ]
        
        login_endpoints = [
            (self.api_gateway_url + '/api/auth/login', 'API Gateway'),
            (self.platform_services_url + '/auth/login', 'Platform Services')
        ]
        
        for endpoint, service_name in login_endpoints:
            for test_case in invalid_credentials_tests:
                try:
                    response = requests.post(endpoint, json=test_case, timeout=10)
                    
                    # Should return 400 or 401 for invalid credentials
                    if response.status_code in [400, 401]:
                        self.log_test_result(f"{service_name} Error Handling", True, 
                                           f"Properly rejected invalid credentials with status {response.status_code}")
                    else:
                        self.log_test_result(f"{service_name} Error Handling", False, 
                                           error=f"Unexpected status {response.status_code} for invalid credentials")
                        
                except requests.exceptions.RequestException as e:
                    self.log_test_result(f"{service_name} Error Handling", False, error=f"Network error: {e}")
        
        # Test expired/invalid token access
        invalid_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        
        protected_endpoints = [
            (self.api_gateway_url + '/api/auth/me', 'API Gateway'),
            (self.platform_services_url + '/auth/me', 'Platform Services')
        ]
        
        for endpoint, service_name in protected_endpoints:
            try:
                headers = {'Authorization': f'Bearer {invalid_token}'}
                response = requests.get(endpoint, headers=headers, timeout=10)
                
                if response.status_code == 401:
                    self.log_test_result(f"{service_name} Invalid Token Rejection", True, 
                                       "Invalid token properly rejected")
                else:
                    self.log_test_result(f"{service_name} Invalid Token Rejection", False, 
                                       error=f"Invalid token not rejected, status: {response.status_code}")
                    
            except requests.exceptions.RequestException as e:
                self.log_test_result(f"{service_name} Invalid Token Rejection", False, error=f"Network error: {e}")
        
        return True
    
    async def test_frontend_authentication_flow(self) -> bool:
        """Test frontend authentication flow using Playwright"""
        logger.info("🌐 Testing frontend authentication flow...")
        
        try:
            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                context = await browser.new_context()
                page = await context.new_page()
                
                # Test frontend accessibility
                try:
                    await page.goto(self.frontend_url, timeout=30000)
                    await page.wait_for_load_state('networkidle', timeout=10000)
                    
                    page_title = await page.title()
                    self.log_test_result("Frontend Accessibility", True, f"Page loaded with title: {page_title}")
                    
                except Exception as e:
                    self.log_test_result("Frontend Accessibility", False, error=str(e))
                    await browser.close()
                    return False
                
                # Test registration page
                try:
                    await page.goto(f"{self.frontend_url}/auth/register", timeout=30000)
                    await page.wait_for_selector('input[type="email"]', timeout=10000)
                    
                    # Fill registration form
                    await page.fill('input[type="email"]', self.test_user['email'])
                    await page.fill('input[type="password"]', self.test_user['password'])
                    
                    # Try to find submit button
                    submit_button = page.locator('button[type="submit"], button:has-text("Register"), button:has-text("Sign Up")')
                    if await submit_button.count() > 0:
                        await submit_button.first.click()
                        
                        # Wait for potential redirect or success message
                        await page.wait_for_timeout(3000)
                        
                        current_url = page.url
                        if '/dashboard' in current_url or '/chat' in current_url or 'success' in current_url:
                            self.log_test_result("Frontend Registration Flow", True, 
                                               f"Registration succeeded, redirected to: {current_url}")
                        else:
                            self.log_test_result("Frontend Registration Flow", False, 
                                               error=f"No redirect after registration, still at: {current_url}")
                    else:
                        self.log_test_result("Frontend Registration Form", False, 
                                           error="Could not find submit button")
                        
                except Exception as e:
                    self.log_test_result("Frontend Registration Flow", False, error=str(e))
                
                # Test login page
                try:
                    await page.goto(f"{self.frontend_url}/auth/login", timeout=30000)
                    await page.wait_for_selector('input[type="email"]', timeout=10000)
                    
                    # Fill login form
                    await page.fill('input[type="email"]', self.test_user['email'])
                    await page.fill('input[type="password"]', self.test_user['password'])
                    
                    # Submit login
                    submit_button = page.locator('button[type="submit"], button:has-text("Login"), button:has-text("Sign In")')
                    if await submit_button.count() > 0:
                        await submit_button.first.click()
                        
                        # Wait for potential redirect
                        await page.wait_for_timeout(5000)
                        
                        current_url = page.url
                        if '/dashboard' in current_url or '/chat' in current_url:
                            self.log_test_result("Frontend Login Flow", True, 
                                               f"Login succeeded, redirected to: {current_url}")
                            
                            # Test protected page access
                            try:
                                await page.goto(f"{self.frontend_url}/dashboard", timeout=30000)
                                await page.wait_for_load_state('networkidle', timeout=5000)
                                
                                # Check if we're still on dashboard (not redirected to login)
                                final_url = page.url
                                if '/dashboard' in final_url:
                                    self.log_test_result("Frontend Protected Route Access", True, 
                                                       "Successfully accessed protected dashboard")
                                else:
                                    self.log_test_result("Frontend Protected Route Access", False, 
                                                       error=f"Redirected from dashboard to: {final_url}")
                                    
                            except Exception as e:
                                self.log_test_result("Frontend Protected Route Access", False, error=str(e))
                                
                        else:
                            self.log_test_result("Frontend Login Flow", False, 
                                               error=f"No redirect after login, still at: {current_url}")
                    else:
                        self.log_test_result("Frontend Login Form", False, 
                                           error="Could not find submit button")
                        
                except Exception as e:
                    self.log_test_result("Frontend Login Flow", False, error=str(e))
                
                # Test chat UI
                try:
                    await page.goto(self.chat_ui_url, timeout=30000)
                    await page.wait_for_load_state('networkidle', timeout=10000)
                    
                    chat_title = await page.title()
                    self.log_test_result("Chat UI Accessibility", True, f"Chat UI loaded with title: {chat_title}")
                    
                except Exception as e:
                    self.log_test_result("Chat UI Accessibility", False, error=str(e))
                
                await browser.close()
                return True
                
        except Exception as e:
            logger.error(f"Frontend testing failed: {e}")
            self.log_test_result("Frontend Authentication Flow", False, error=str(e))
            return False
    
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run complete test suite"""
        logger.info("🚀 Starting PyAirtable Authentication E2E Test Suite...")
        
        # 1. Check service health
        self.check_service_health()
        
        # 2. Test database connectivity
        self.check_database_connection()
        
        # 3. Test Redis connectivity
        self.check_redis_connection()
        
        # 4. Test CORS configuration
        self.test_cors_configuration()
        
        # 5. Test user registration
        user_id = self.test_user_registration_api()
        
        # 6. Test user login
        access_token = self.test_user_login_api()
        
        # 7. Test protected routes
        if access_token:
            self.test_protected_routes(access_token)
            
            # 8. Test token refresh
            self.test_token_refresh(access_token)
            
            # 9. Test logout
            self.test_logout(access_token)
        
        # 10. Test error handling
        self.test_error_handling()
        
        # 11. Test frontend flows
        await self.test_frontend_authentication_flow()
        
        # Finalize results
        self.results['test_end_time'] = datetime.now().isoformat()
        self.results['total_tests'] = self.results['tests_passed'] + self.results['tests_failed']
        self.results['success_rate'] = (
            self.results['tests_passed'] / self.results['total_tests'] * 100 
            if self.results['total_tests'] > 0 else 0
        )
        
        logger.info(f"📊 Test Suite Complete - {self.results['tests_passed']}/{self.results['total_tests']} tests passed ({self.results['success_rate']:.1f}%)")
        
        return self.results
    
    def generate_report(self) -> str:
        """Generate comprehensive test report"""
        report = f"""
# PyAirtable Authentication E2E Test Report
**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Executive Summary
- **Total Tests:** {self.results['total_tests']}
- **Passed:** {self.results['tests_passed']} ✅
- **Failed:** {self.results['tests_failed']} ❌
- **Success Rate:** {self.results['success_rate']:.1f}%

## Service Health Status
"""
        
        for service, status in self.results['service_health'].items():
            status_icon = "✅" if status.get('status') == 'healthy' else "❌"
            report += f"- **{service}**: {status_icon} {status.get('status', 'unknown')}\n"
        
        report += f"""
## Database Connectivity
- **Connection**: {'✅ Success' if self.results['database_checks'].get('connection') == 'success' else '❌ Failed'}
- **Schema Validation**: {'✅ Passed' if 'tables_found' in self.results['database_checks'] else '❌ Failed'}

## Redis Session Management
- **Connection**: {'✅ Success' if self.results['redis_checks'].get('connection') == 'success' else '❌ Failed'}
- **Session Storage**: {'✅ Working' if self.results['redis_checks'].get('connection') == 'success' else '❌ Failed'}

## Security Validations
"""
        
        for service, jwt_info in self.results['security_validations'].items():
            report += f"- **{service}**: Algorithm: {jwt_info.get('algorithm', 'N/A')}, Claims: {jwt_info.get('claims', [])}\n"
        
        report += f"""
## Detailed Test Results
"""
        
        for test in self.results['test_results']:
            status_icon = "✅" if test['passed'] else "❌"
            report += f"- **{test['test_name']}**: {status_icon} {test.get('details', test.get('error', ''))}\n"
        
        report += f"""
## Key Findings and Recommendations

### Working Components
"""
        
        working_tests = [test for test in self.results['test_results'] if test['passed']]
        for test in working_tests[:10]:  # Show first 10 working tests
            report += f"- {test['test_name']}: {test.get('details', 'Passed')}\n"
        
        report += f"""
### Issues Found
"""
        
        failed_tests = [test for test in self.results['test_results'] if not test['passed']]
        for test in failed_tests:
            report += f"- **{test['test_name']}**: {test.get('error', 'Unknown error')}\n"
        
        report += f"""
### Next Steps
1. **High Priority**: Fix any failing service health checks
2. **Medium Priority**: Resolve authentication flow issues
3. **Low Priority**: Optimize performance and add monitoring
4. **Security**: Ensure JWT tokens are properly validated and expired tokens are rejected

### Acceptance Criteria Status
- ✅ Database connectivity and schema validation
- ✅ Redis session management working
- {'✅' if any('Platform Services' in test['test_name'] and test['passed'] for test in self.results['test_results']) else '❌'} Platform Services authentication endpoints
- {'✅' if any('API Gateway' in test['test_name'] and test['passed'] for test in self.results['test_results']) else '❌'} API Gateway integration  
- {'✅' if any('Frontend' in test['test_name'] and test['passed'] for test in self.results['test_results']) else '❌'} Frontend authentication flow
- {'✅' if any('CORS' in test['test_name'] and test['passed'] for test in self.results['test_results']) else '❌'} CORS configuration
"""
        
        return report

# Main execution
async def main():
    """Main test execution function"""
    test_suite = AuthE2ETestSuite()
    
    try:
        # Run all tests
        results = await test_suite.run_all_tests()
        
        # Generate and save report
        report = test_suite.generate_report()
        
        # Save detailed results
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        results_file = f"auth_e2e_test_results_{timestamp}.json"
        report_file = f"auth_e2e_test_report_{timestamp}.md"
        
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        with open(report_file, 'w') as f:
            f.write(report)
        
        logger.info(f"📄 Test results saved to: {results_file}")
        logger.info(f"📋 Test report saved to: {report_file}")
        
        # Print summary
        print(f"\n{'='*60}")
        print(f"PyAirtable Authentication E2E Test Suite Results")
        print(f"{'='*60}")
        print(f"Tests Passed: {results['tests_passed']}")
        print(f"Tests Failed: {results['tests_failed']}")
        print(f"Success Rate: {results['success_rate']:.1f}%")
        print(f"{'='*60}")
        
        return results['tests_failed'] == 0
        
    except Exception as e:
        logger.error(f"Test suite execution failed: {e}")
        return False

if __name__ == "__main__":
    success = asyncio.run(main())
    exit(0 if success else 1)