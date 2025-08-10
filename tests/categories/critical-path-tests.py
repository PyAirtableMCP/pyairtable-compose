"""
Critical Path Test Suite for PyAirtable
======================================

This module contains the most important tests that MUST pass for system deployment.
These tests cover the core user journeys and essential functionality that would
render the system unusable if failing.

Test Categories:
1. User Authentication & Authorization (Must Pass: 8 tests)
2. Airtable Integration Core Functions (Must Pass: 6 tests) 
3. AI Chat Functionality (Must Pass: 4 tests)
4. Service Health & Communication (Must Pass: 2 tests)

Total Critical Tests: 20 tests
Target Pass Rate: 100% (All critical tests must pass)
"""

import pytest
import asyncio
import httpx
import json
from datetime import datetime, timedelta
from typing import Dict, Any, List
import logging

from ..factories.test_data_factory import TestDataFactory
from ..helpers.auth_test_helpers import AuthTestHelpers
from ..helpers.service_test_helpers import ServiceTestHelpers

logger = logging.getLogger(__name__)

class CriticalPathTestSuite:
    """Critical path tests that must pass for deployment readiness"""
    
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=30.0)
        self.auth_helper = AuthTestHelpers()
        self.service_helper = ServiceTestHelpers()
        self.test_data = TestDataFactory()
    
    async def __aenter__(self):
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.client.aclose()

# =============================================================================
# 1. CRITICAL: User Authentication & Authorization (8 tests)
# =============================================================================

@pytest.mark.critical
@pytest.mark.asyncio
class TestCriticalAuthentication:
    """Critical authentication flows that must work"""
    
    async def test_user_can_login_successfully(self):
        """CRITICAL: Users must be able to log in to access the system"""
        async with CriticalPathTestSuite() as suite:
            # Setup test user
            test_user = TestDataFactory.createTestUser({
                'email': 'critical.test@example.com',
                'roles': ['user']
            })
            
            # Mock successful authentication
            await suite.auth_helper.mock_successful_login(test_user)
            
            # Attempt login
            login_response = await suite.client.post('/api/auth/signin', json={
                'email': test_user['email'],
                'password': 'validpassword123'
            })
            
            assert login_response.status_code == 200
            response_data = login_response.json()
            assert 'user' in response_data
            assert 'accessToken' in response_data
            assert response_data['user']['email'] == test_user['email']
    
    async def test_authenticated_user_can_access_dashboard(self):
        """CRITICAL: Authenticated users must be able to access the main dashboard"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated session
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            
            # Access dashboard with valid token
            headers = {'Authorization': f'Bearer {access_token}'}
            dashboard_response = await suite.client.get('/dashboard', headers=headers)
            
            assert dashboard_response.status_code == 200
            assert 'dashboard' in dashboard_response.text.lower()
    
    async def test_user_sessions_persist_across_requests(self):
        """CRITICAL: User sessions must maintain state across multiple requests"""
        async with CriticalPathTestSuite() as suite:
            # Login and get session
            test_user = TestDataFactory.createTestUser()
            await suite.auth_helper.mock_successful_login(test_user)
            
            login_response = await suite.client.post('/api/auth/signin', json={
                'email': test_user['email'],
                'password': 'password'
            })
            
            # Extract session info
            session_data = login_response.json()
            access_token = session_data['accessToken']
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Make multiple requests - session should persist
            for i in range(3):
                response = await suite.client.get('/api/user/profile', headers=headers)
                assert response.status_code == 200
                user_data = response.json()
                assert user_data['id'] == test_user['id']
    
    async def test_invalid_credentials_are_rejected(self):
        """CRITICAL: System must reject invalid login attempts"""
        async with CriticalPathTestSuite() as suite:
            # Mock authentication failure
            await suite.auth_helper.mock_failed_login()
            
            # Attempt login with invalid credentials
            invalid_login = await suite.client.post('/api/auth/signin', json={
                'email': 'invalid@example.com',
                'password': 'wrongpassword'
            })
            
            assert invalid_login.status_code == 401
            error_data = invalid_login.json()
            assert 'error' in error_data
            assert 'invalid' in error_data['error'].lower()
    
    async def test_expired_sessions_require_reauth(self):
        """CRITICAL: Expired sessions must be handled properly"""
        async with CriticalPathTestSuite() as suite:
            # Create expired token
            expired_token = TestDataFactory.createJWTToken({
                'exp': int((datetime.now() - timedelta(hours=1)).timestamp())
            })
            
            # Attempt to access protected resource with expired token
            headers = {'Authorization': f'Bearer {expired_token}'}
            response = await suite.client.get('/api/user/profile', headers=headers)
            
            assert response.status_code == 401
            error_data = response.json()
            assert 'expired' in error_data.get('error', '').lower()
    
    async def test_unauthorized_access_is_blocked(self):
        """CRITICAL: Unauthenticated users cannot access protected resources"""
        async with CriticalPathTestSuite() as suite:
            # Attempt to access protected endpoints without authentication
            protected_endpoints = [
                '/api/user/profile',
                '/api/airtable/tables',
                '/api/chat',
                '/dashboard'
            ]
            
            for endpoint in protected_endpoints:
                response = await suite.client.get(endpoint)
                assert response.status_code in [401, 403], f"Endpoint {endpoint} should require authentication"
    
    async def test_user_can_logout_securely(self):
        """CRITICAL: Users must be able to log out and invalidate sessions"""
        async with CriticalPathTestSuite() as suite:
            # Login first
            test_user = TestDataFactory.createTestUser()
            await suite.auth_helper.mock_successful_login(test_user)
            
            login_response = await suite.client.post('/api/auth/signin', json={
                'email': test_user['email'],
                'password': 'password'
            })
            
            access_token = login_response.json()['accessToken']
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Verify authenticated access works
            profile_response = await suite.client.get('/api/user/profile', headers=headers)
            assert profile_response.status_code == 200
            
            # Logout
            await suite.auth_helper.mock_successful_logout()
            logout_response = await suite.client.post('/api/auth/signout', headers=headers)
            assert logout_response.status_code == 200
            
            # Verify token is invalidated
            post_logout_response = await suite.client.get('/api/user/profile', headers=headers)
            assert post_logout_response.status_code == 401
    
    async def test_role_based_access_control_works(self):
        """CRITICAL: Users with different roles have appropriate access levels"""
        async with CriticalPathTestSuite() as suite:
            # Test regular user
            regular_user = TestDataFactory.createTestUser({'roles': ['user']})
            user_token = TestDataFactory.createJWTToken({
                'userId': regular_user['id'],
                'roles': ['user']
            })
            
            # Test admin user
            admin_user = TestDataFactory.createTestUser({'roles': ['admin', 'user']})
            admin_token = TestDataFactory.createJWTToken({
                'userId': admin_user['id'],
                'roles': ['admin', 'user']
            })
            
            # Regular user should NOT access admin endpoints
            user_headers = {'Authorization': f'Bearer {user_token}'}
            admin_response = await suite.client.get('/api/admin/users', headers=user_headers)
            assert admin_response.status_code == 403
            
            # Admin user SHOULD access admin endpoints
            admin_headers = {'Authorization': f'Bearer {admin_token}'}
            admin_response = await suite.client.get('/api/admin/users', headers=admin_headers)
            assert admin_response.status_code == 200

# =============================================================================
# 2. CRITICAL: Airtable Integration Core Functions (6 tests)
# =============================================================================

@pytest.mark.critical
@pytest.mark.asyncio
class TestCriticalAirtableIntegration:
    """Critical Airtable integration functionality"""
    
    async def test_can_connect_to_airtable_with_valid_credentials(self):
        """CRITICAL: System must connect to Airtable with valid API credentials"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock successful Airtable connection
            await suite.service_helper.mock_airtable_connection_success()
            
            # Test Airtable connection
            connection_response = await suite.client.post('/api/airtable/connect', 
                headers=headers,
                json={
                    'apiKey': 'patValidAPIKey123456789',
                    'baseId': 'appValidBase123456789'
                }
            )
            
            assert connection_response.status_code == 200
            connection_data = connection_response.json()
            assert connection_data['connected'] == True
            assert 'baseId' in connection_data
    
    async def test_can_list_tables_from_connected_base(self):
        """CRITICAL: System must be able to retrieve table list from Airtable base"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user with Airtable connection
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock Airtable tables response
            test_base = TestDataFactory.createTestAirtableBase()
            await suite.service_helper.mock_airtable_tables_response(test_base)
            
            # Request table list
            tables_response = await suite.client.get('/api/airtable/tables', headers=headers)
            
            assert tables_response.status_code == 200
            tables_data = tables_response.json()
            assert 'tables' in tables_data
            assert len(tables_data['tables']) > 0
            
            # Verify expected tables are present
            table_names = [table['name'] for table in tables_data['tables']]
            assert 'Projects' in table_names
            assert 'Tasks' in table_names
    
    async def test_can_read_records_from_airtable_table(self):
        """CRITICAL: System must be able to read record data from Airtable tables"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock Airtable records response
            test_table = TestDataFactory.createProjectsTable()
            await suite.service_helper.mock_airtable_records_response(test_table)
            
            # Request records from table
            records_response = await suite.client.get(
                '/api/airtable/tables/Projects/records', 
                headers=headers
            )
            
            assert records_response.status_code == 200
            records_data = records_response.json()
            assert 'records' in records_data
            assert len(records_data['records']) >= 2  # Test data should have 2 projects
            
            # Verify record structure
            first_record = records_data['records'][0]
            assert 'id' in first_record
            assert 'fields' in first_record
            assert 'Name' in first_record['fields']
    
    async def test_handles_invalid_airtable_credentials_gracefully(self):
        """CRITICAL: System must handle invalid Airtable credentials without crashing"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock Airtable authentication failure
            await suite.service_helper.mock_airtable_auth_failure()
            
            # Attempt connection with invalid credentials
            connection_response = await suite.client.post('/api/airtable/connect',
                headers=headers,
                json={
                    'apiKey': 'invalidkey',
                    'baseId': 'invalidbase'
                }
            )
            
            assert connection_response.status_code == 401
            error_data = connection_response.json()
            assert 'error' in error_data
            assert 'invalid' in error_data['error'].lower() or 'unauthorized' in error_data['error'].lower()
    
    async def test_handles_airtable_rate_limits_properly(self):
        """CRITICAL: System must handle Airtable API rate limits gracefully"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock Airtable rate limit response
            await suite.service_helper.mock_airtable_rate_limit()
            
            # Make request that triggers rate limit
            rate_limit_response = await suite.client.get('/api/airtable/tables', headers=headers)
            
            # Should handle rate limit gracefully (429 or retry logic)
            assert rate_limit_response.status_code in [429, 503]
            error_data = rate_limit_response.json()
            assert 'rate limit' in error_data.get('error', '').lower()
    
    async def test_airtable_connection_status_is_trackable(self):
        """CRITICAL: Users must be able to check their Airtable connection status"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Check initial connection status (should be disconnected)
            status_response = await suite.client.get('/api/airtable/status', headers=headers)
            assert status_response.status_code == 200
            status_data = status_response.json()
            assert 'connected' in status_data
            
            # Connect to Airtable
            await suite.service_helper.mock_airtable_connection_success()
            connect_response = await suite.client.post('/api/airtable/connect',
                headers=headers,
                json={
                    'apiKey': 'patValidKey',
                    'baseId': 'appValidBase'
                }
            )
            assert connect_response.status_code == 200
            
            # Check updated connection status (should be connected)
            updated_status = await suite.client.get('/api/airtable/status', headers=headers)
            assert updated_status.status_code == 200
            updated_data = updated_status.json()
            assert updated_data['connected'] == True

# =============================================================================
# 3. CRITICAL: AI Chat Functionality (4 tests)
# =============================================================================

@pytest.mark.critical
@pytest.mark.asyncio
class TestCriticalAIChat:
    """Critical AI chat functionality that enables core user experience"""
    
    async def test_can_send_message_and_receive_ai_response(self):
        """CRITICAL: Users must be able to chat with AI and get responses"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock AI service response
            await suite.service_helper.mock_ai_chat_response()
            
            # Send chat message
            chat_response = await suite.client.post('/api/chat',
                headers=headers,
                json={
                    'message': 'Hello, can you help me with my Airtable data?',
                    'sessionId': 'test-session-123'
                }
            )
            
            assert chat_response.status_code == 200
            response_data = chat_response.json()
            assert 'response' in response_data
            assert 'sessionId' in response_data
            assert len(response_data['response']) > 10  # Should be substantial response
    
    async def test_chat_maintains_conversation_context(self):
        """CRITICAL: AI chat must maintain conversation context across messages"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            session_id = 'context-test-session'
            
            # Mock AI responses with context
            await suite.service_helper.mock_ai_contextual_responses()
            
            # First message
            first_response = await suite.client.post('/api/chat',
                headers=headers,
                json={
                    'message': 'My name is John and I have a project management base',
                    'sessionId': session_id
                }
            )
            assert first_response.status_code == 200
            
            # Second message referencing context
            second_response = await suite.client.post('/api/chat',
                headers=headers,
                json={
                    'message': 'What projects do I have?',
                    'sessionId': session_id
                }
            )
            assert second_response.status_code == 200
            response_data = second_response.json()
            
            # Response should acknowledge context (name and base type)
            assert 'john' in response_data['response'].lower() or 'project' in response_data['response'].lower()
    
    async def test_ai_can_access_airtable_data_through_chat(self):
        """CRITICAL: AI must be able to query and analyze user's Airtable data"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user with Airtable connection
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock Airtable data access
            test_base = TestDataFactory.createTestAirtableBase()
            await suite.service_helper.mock_airtable_data_access(test_base)
            await suite.service_helper.mock_ai_data_analysis_response()
            
            # Ask AI to analyze Airtable data
            analysis_response = await suite.client.post('/api/chat',
                headers=headers,
                json={
                    'message': 'Analyze my projects and tell me the total budget',
                    'sessionId': 'analysis-test-session'
                }
            )
            
            assert analysis_response.status_code == 200
            response_data = analysis_response.json()
            
            # Response should contain analysis of the data
            response_text = response_data['response'].lower()
            assert any(word in response_text for word in ['project', 'budget', 'total', 'analysis'])
    
    async def test_chat_handles_ai_service_failures_gracefully(self):
        """CRITICAL: Chat must handle AI service failures without breaking user experience"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock AI service failure
            await suite.service_helper.mock_ai_service_failure()
            
            # Send chat message during AI service failure
            chat_response = await suite.client.post('/api/chat',
                headers=headers,
                json={
                    'message': 'Hello, are you working?',
                    'sessionId': 'failure-test-session'
                }
            )
            
            # Should return graceful error response, not crash
            assert chat_response.status_code in [200, 503]
            response_data = chat_response.json()
            
            if chat_response.status_code == 200:
                # Graceful degradation - return error message to user
                assert 'response' in response_data
                assert any(word in response_data['response'].lower() 
                          for word in ['unavailable', 'error', 'try again', 'sorry'])
            else:
                # Service unavailable
                assert 'error' in response_data

# =============================================================================
# 4. CRITICAL: Service Health & Communication (2 tests)
# =============================================================================

@pytest.mark.critical
@pytest.mark.asyncio
class TestCriticalServiceHealth:
    """Critical service health and communication tests"""
    
    async def test_all_core_services_are_healthy(self):
        """CRITICAL: All core services must be running and healthy"""
        async with CriticalPathTestSuite() as suite:
            core_services = [
                ('API Gateway', 'http://localhost:8000/health'),
                ('Auth Service', 'http://localhost:8004/health'),  
                ('LLM Orchestrator', 'http://localhost:8003/health'),
                ('MCP Server', 'http://localhost:8001/health'),
                ('Airtable Gateway', 'http://localhost:8002/health')
            ]
            
            health_results = {}
            
            for service_name, health_url in core_services:
                try:
                    response = await suite.client.get(health_url, timeout=10.0)
                    health_results[service_name] = {
                        'status_code': response.status_code,
                        'healthy': response.status_code == 200
                    }
                    
                    if response.status_code == 200:
                        health_data = response.json()
                        health_results[service_name]['response'] = health_data
                        
                except Exception as e:
                    health_results[service_name] = {
                        'status_code': None,
                        'healthy': False,
                        'error': str(e)
                    }
            
            # All services must be healthy
            unhealthy_services = [
                name for name, result in health_results.items() 
                if not result['healthy']
            ]
            
            assert len(unhealthy_services) == 0, f"Unhealthy services: {unhealthy_services}"
    
    async def test_service_to_service_communication_works(self):
        """CRITICAL: Services must be able to communicate with each other"""
        async with CriticalPathTestSuite() as suite:
            # Setup authenticated user
            test_user = TestDataFactory.createTestUser()
            access_token = TestDataFactory.createJWTToken({'userId': test_user['id']})
            headers = {'Authorization': f'Bearer {access_token}'}
            
            # Mock service chain response
            await suite.service_helper.mock_service_chain_communication()
            
            # Test service chain: API Gateway -> LLM Orchestrator -> MCP Server -> Airtable Gateway
            # This is triggered by a chat request that requires Airtable data
            service_chain_response = await suite.client.post('/api/chat',
                headers=headers,
                json={
                    'message': 'List my Airtable tables',
                    'sessionId': 'service-chain-test'
                }
            )
            
            assert service_chain_response.status_code == 200
            response_data = service_chain_response.json()
            
            # Response should indicate successful service communication
            assert 'response' in response_data
            # Should contain reference to tables (indicating Airtable service was reached)
            assert any(word in response_data['response'].lower() 
                      for word in ['table', 'airtable', 'data', 'base'])

# =============================================================================
# Test Suite Runner and Reporting
# =============================================================================

class CriticalPathTestRunner:
    """Runner for critical path tests with detailed reporting"""
    
    def __init__(self):
        self.test_results = []
        self.start_time = None
        self.end_time = None
    
    async def run_all_critical_tests(self) -> Dict[str, Any]:
        """Run all critical path tests and return detailed results"""
        self.start_time = datetime.now()
        
        critical_test_classes = [
            TestCriticalAuthentication,
            TestCriticalAirtableIntegration,
            TestCriticalAIChat,
            TestCriticalServiceHealth
        ]
        
        total_tests = 0
        passed_tests = 0
        failed_tests = []
        
        for test_class in critical_test_classes:
            class_name = test_class.__name__
            
            # Get all test methods
            test_methods = [method for method in dir(test_class) if method.startswith('test_')]
            
            for method_name in test_methods:
                total_tests += 1
                test_name = f"{class_name}.{method_name}"
                
                try:
                    # Create test instance and run test
                    test_instance = test_class()
                    test_method = getattr(test_instance, method_name)
                    
                    test_start = datetime.now()
                    await test_method()
                    test_end = datetime.now()
                    
                    passed_tests += 1
                    self.test_results.append({
                        'test': test_name,
                        'status': 'PASSED',
                        'duration': (test_end - test_start).total_seconds(),
                        'error': None
                    })
                    
                    logger.info(f"✅ {test_name} - PASSED")
                    
                except Exception as e:
                    test_end = datetime.now()
                    failed_tests.append(test_name)
                    
                    self.test_results.append({
                        'test': test_name,
                        'status': 'FAILED',
                        'duration': (test_end - test_start).total_seconds(),
                        'error': str(e)
                    })
                    
                    logger.error(f"❌ {test_name} - FAILED: {e}")
        
        self.end_time = datetime.now()
        total_duration = (self.end_time - self.start_time).total_seconds()
        pass_rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
        
        summary = {
            'execution_id': str(id(self)),
            'timestamp': self.start_time.isoformat(),
            'duration': total_duration,
            'total_tests': total_tests,
            'passed_tests': passed_tests,
            'failed_tests': len(failed_tests),
            'pass_rate': pass_rate,
            'status': 'PASSED' if pass_rate == 100 else 'FAILED',
            'failed_test_names': failed_tests,
            'detailed_results': self.test_results
        }
        
        return summary
    
    def generate_report(self, summary: Dict[str, Any]) -> str:
        """Generate markdown report for critical path test results"""
        
        status_emoji = "✅" if summary['status'] == 'PASSED' else "❌"
        
        report = f"""# Critical Path Test Results {status_emoji}

## Summary
- **Status**: {summary['status']}
- **Pass Rate**: {summary['pass_rate']:.1f}%
- **Total Tests**: {summary['total_tests']}
- **Passed**: {summary['passed_tests']}
- **Failed**: {summary['failed_tests']}
- **Duration**: {summary['duration']:.2f} seconds
- **Timestamp**: {summary['timestamp']}

## Test Categories

### 1. Authentication Tests (8 tests)
Target: 100% pass rate (All must pass for deployment)

### 2. Airtable Integration Tests (6 tests)  
Target: 100% pass rate (Core functionality)

### 3. AI Chat Tests (4 tests)
Target: 100% pass rate (Primary user interface)

### 4. Service Health Tests (2 tests)
Target: 100% pass rate (System availability)

## Detailed Results

"""
        
        for result in summary['detailed_results']:
            status_emoji = "✅" if result['status'] == 'PASSED' else "❌"
            report += f"- {status_emoji} **{result['test']}** - {result['duration']:.2f}s"
            if result['error']:
                report += f"\n  - Error: {result['error']}"
            report += "\n"
        
        if summary['failed_tests'] > 0:
            report += f"""
## ⚠️ DEPLOYMENT BLOCKED

Critical tests are failing. Deployment should be **BLOCKED** until all critical tests pass.

Failed tests that must be fixed:
{chr(10).join(f"- {test}" for test in summary['failed_test_names'])}

## Next Steps
1. Fix all failing critical tests
2. Re-run critical test suite  
3. Ensure 100% pass rate before deployment
"""
        else:
            report += f"""
## ✅ DEPLOYMENT READY

All critical tests are passing. System is ready for deployment.

## Verification Checklist
- [x] User authentication works
- [x] Airtable integration functional
- [x] AI chat responds correctly
- [x] All services healthy
- [x] Service communication verified
"""
        
        return report

# CLI interface for running critical tests
async def run_critical_tests():
    """Run critical path tests from command line"""
    runner = CriticalPathTestRunner()
    summary = await runner.run_all_critical_tests()
    report = runner.generate_report(summary)
    
    print(report)
    
    # Save report to file
    from pathlib import Path
    reports_dir = Path("tests/reports/critical-path")
    reports_dir.mkdir(parents=True, exist_ok=True)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = reports_dir / f"critical_path_results_{timestamp}.md"
    
    with open(report_file, 'w') as f:
        f.write(report)
    
    print(f"\nReport saved to: {report_file}")
    
    # Return appropriate exit code
    return 0 if summary['pass_rate'] == 100 else 1

if __name__ == "__main__":
    exit_code = asyncio.run(run_critical_tests())
    exit(exit_code)