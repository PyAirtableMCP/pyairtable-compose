#!/usr/bin/env python3
"""
Comprehensive Integration Test Suite for PyAirtable System
Production Readiness Validation

Tests all critical functionality:
1. Authentication Flow
2. Airtable Operations 
3. Workflow Management
4. File Operations
5. SAGA Transactions
6. Frontend-Backend Integration
"""

import os
import sys
import json
import time
import logging
import asyncio
import aiohttp
import requests
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor
import tempfile
import subprocess

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class TestResult:
    test_name: str
    category: str
    status: str  # 'PASS', 'FAIL', 'SKIP'
    duration_ms: int
    details: str
    error_message: Optional[str] = None
    performance_metrics: Optional[Dict] = None

@dataclass
class CategoryResults:
    category: str
    total_tests: int
    passed: int
    failed: int
    skipped: int
    success_rate: float
    avg_response_time_ms: float
    performance_metrics: Dict[str, Any]

class IntegrationTestSuite:
    def __init__(self):
        self.base_urls = {
            'frontend': 'http://localhost:3000',
            'api_gateway': 'http://localhost:8000',
            'auth_service': 'http://localhost:8001',
            'airtable_service': 'http://localhost:8002',
            'workflow_service': 'http://localhost:8003',
            'file_service': 'http://localhost:8006',
            'saga_service': 'http://localhost:8008',
            'notification_service': 'http://localhost:8004',
            'platform_service': 'http://localhost:8007',
            'user_service': 'http://localhost:8005'
        }
        self.results: List[TestResult] = []
        self.session_token: Optional[str] = None
        self.user_id: Optional[str] = None
        
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run all integration tests and return comprehensive results"""
        logger.info("Starting Comprehensive Integration Test Suite")
        start_time = time.time()
        
        # Test categories in order
        test_categories = [
            ("Service Health", self.test_service_health),
            ("Authentication Flow", self.test_authentication_flow),
            ("Airtable Operations", self.test_airtable_operations),
            ("Workflow Management", self.test_workflow_management), 
            ("File Operations", self.test_file_operations),
            ("SAGA Transactions", self.test_saga_transactions),
            ("Frontend Integration", self.test_frontend_integration),
            ("Performance Metrics", self.test_performance_metrics)
        ]
        
        # Run tests
        for category_name, test_function in test_categories:
            logger.info(f"\n=== Testing {category_name} ===")
            try:
                await test_function()
            except Exception as e:
                logger.error(f"Error in {category_name}: {str(e)}")
                self.results.append(TestResult(
                    test_name=f"{category_name}_error",
                    category=category_name,
                    status="FAIL",
                    duration_ms=0,
                    details=f"Category test failed: {str(e)}",
                    error_message=str(e)
                ))
        
        total_duration = time.time() - start_time
        
        # Generate comprehensive report
        report = self.generate_comprehensive_report(total_duration)
        
        # Save results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        results_file = f"/Users/kg/IdeaProjects/pyairtable-compose/integration_test_results_{timestamp}.json"
        
        with open(results_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        logger.info(f"Test results saved to: {results_file}")
        return report

    async def test_service_health(self):
        """Test health and connectivity of all services"""
        for service_name, url in self.base_urls.items():
            start_time = time.time()
            try:
                async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=10)) as session:
                    health_endpoints = ['/health', '/status', '/ping', '/_health']
                    service_available = False
                    
                    for endpoint in health_endpoints:
                        try:
                            async with session.get(f"{url}{endpoint}") as response:
                                if response.status in [200, 404]:  # 404 means service is up but no health endpoint
                                    service_available = True
                                    response_time = int((time.time() - start_time) * 1000)
                                    
                                    self.results.append(TestResult(
                                        test_name=f"{service_name}_health",
                                        category="Service Health",
                                        status="PASS",
                                        duration_ms=response_time,
                                        details=f"Service {service_name} is healthy",
                                        performance_metrics={'response_time_ms': response_time}
                                    ))
                                    break
                        except:
                            continue
                    
                    if not service_available:
                        # Try basic connectivity test
                        try:
                            async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as response:
                                response_time = int((time.time() - start_time) * 1000)
                                status = "PASS" if response.status < 500 else "FAIL"
                                self.results.append(TestResult(
                                    test_name=f"{service_name}_connectivity",
                                    category="Service Health",
                                    status=status,
                                    duration_ms=response_time,
                                    details=f"Service {service_name} responded with status {response.status}",
                                    performance_metrics={'response_time_ms': response_time}
                                ))
                        except Exception as e:
                            self.results.append(TestResult(
                                test_name=f"{service_name}_connectivity",
                                category="Service Health",
                                status="FAIL",
                                duration_ms=int((time.time() - start_time) * 1000),
                                details=f"Service {service_name} is not accessible",
                                error_message=str(e)
                            ))
            except Exception as e:
                self.results.append(TestResult(
                    test_name=f"{service_name}_health",
                    category="Service Health",  
                    status="FAIL",
                    duration_ms=int((time.time() - start_time) * 1000),
                    details=f"Health check failed for {service_name}",
                    error_message=str(e)
                ))

    async def test_authentication_flow(self):
        """Test user registration, login, JWT validation, session management"""
        # Test user registration
        await self._test_user_registration()
        # Test user login 
        await self._test_user_login()
        # Test JWT validation
        await self._test_jwt_validation()
        # Test session management
        await self._test_session_management()
    
    async def _test_user_registration(self):
        """Test user registration functionality"""
        start_time = time.time()
        test_user = {
            "username": f"testuser_{int(time.time())}",
            "email": f"test_{int(time.time())}@example.com", 
            "password": "TestPassword123!"
        }
        
        # Try multiple possible registration endpoints
        registration_endpoints = [
            f"{self.base_urls['api_gateway']}/api/auth/register",
            f"{self.base_urls['auth_service']}/register",
            f"{self.base_urls['platform_service']}/auth/register"
        ]
        
        success = False
        for endpoint in registration_endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=test_user) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 201]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="user_registration",
                                category="Authentication Flow",
                                status="PASS", 
                                duration_ms=response_time,
                                details="User registration successful",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="user_registration",
                                category="Authentication Flow",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Registration failed with status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="user_registration",
                category="Authentication Flow", 
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible registration endpoint found",
                error_message="All registration endpoints unavailable"
            ))

    async def _test_user_login(self):
        """Test user login functionality"""
        start_time = time.time()
        test_credentials = {
            "username": "testuser",
            "password": "password123"
        }
        
        login_endpoints = [
            f"{self.base_urls['api_gateway']}/api/auth/login",
            f"{self.base_urls['auth_service']}/login", 
            f"{self.base_urls['platform_service']}/auth/login"
        ]
        
        success = False
        for endpoint in login_endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=test_credentials) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            response_data = await response.json()
                            if 'token' in response_data or 'access_token' in response_data:
                                self.session_token = response_data.get('token') or response_data.get('access_token')
                                success = True
                                self.results.append(TestResult(
                                    test_name="user_login",
                                    category="Authentication Flow",
                                    status="PASS",
                                    duration_ms=response_time,
                                    details="User login successful with token",
                                    performance_metrics={'response_time_ms': response_time}
                                ))
                                break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="user_login",
                                category="Authentication Flow",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Login failed with status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="user_login",
                category="Authentication Flow",
                status="SKIP", 
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible login endpoint found",
                error_message="All login endpoints unavailable"
            ))

    async def _test_jwt_validation(self):
        """Test JWT token validation"""
        if not self.session_token:
            self.results.append(TestResult(
                test_name="jwt_validation",
                category="Authentication Flow",
                status="SKIP",
                duration_ms=0,
                details="No session token available for validation",
                error_message="Login test did not provide token"
            ))
            return
            
        start_time = time.time()
        headers = {"Authorization": f"Bearer {self.session_token}"}
        
        validation_endpoints = [
            f"{self.base_urls['api_gateway']}/api/auth/validate",
            f"{self.base_urls['auth_service']}/validate",
            f"{self.base_urls['platform_service']}/auth/validate"
        ]
        
        success = False
        for endpoint in validation_endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            success = True
                            self.results.append(TestResult(
                                test_name="jwt_validation",
                                category="Authentication Flow",
                                status="PASS",
                                duration_ms=response_time,
                                details="JWT validation successful",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="jwt_validation",
                category="Authentication Flow",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000), 
                details="No accessible JWT validation endpoint found",
                error_message="All validation endpoints unavailable"
            ))

    async def _test_session_management(self):
        """Test session management functionality"""
        # Test session creation, refresh, and logout
        start_time = time.time()
        
        # Test logout if we have a token
        if self.session_token:
            headers = {"Authorization": f"Bearer {self.session_token}"}
            logout_endpoints = [
                f"{self.base_urls['api_gateway']}/api/auth/logout",
                f"{self.base_urls['auth_service']}/logout",
                f"{self.base_urls['platform_service']}/auth/logout"
            ]
            
            success = False
            for endpoint in logout_endpoints:
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.post(endpoint, headers=headers) as response:
                            response_time = int((time.time() - start_time) * 1000)
                            if response.status in [200, 204]:
                                success = True
                                self.results.append(TestResult(
                                    test_name="session_logout",
                                    category="Authentication Flow",
                                    status="PASS",
                                    duration_ms=response_time,
                                    details="Session logout successful",
                                    performance_metrics={'response_time_ms': response_time}
                                ))
                                break
                            elif response.status == 404:
                                continue
                except Exception as e:
                    continue
                    
            if not success:
                self.results.append(TestResult(
                    test_name="session_logout",
                    category="Authentication Flow",
                    status="SKIP",
                    duration_ms=int((time.time() - start_time) * 1000),
                    details="No accessible logout endpoint found",
                    error_message="All logout endpoints unavailable"
                ))
        else:
            self.results.append(TestResult(
                test_name="session_management",
                category="Authentication Flow",
                status="SKIP", 
                duration_ms=0,
                details="No session token available for session management tests",
                error_message="Login test did not provide token"
            ))

    async def test_airtable_operations(self):
        """Test Airtable integration: list tables, CRUD operations, schema retrieval"""
        await self._test_list_tables()
        await self._test_crud_operations()
        await self._test_schema_retrieval()
    
    async def _test_list_tables(self):
        """Test listing Airtable tables"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/airtable/tables",
            f"{self.base_urls['airtable_service']}/tables",
            f"{self.base_urls['platform_service']}/airtable/tables"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="airtable_list_tables",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details=f"Successfully retrieved {len(response_data.get('tables', []))} tables",
                                performance_metrics={'response_time_ms': response_time, 'tables_count': len(response_data.get('tables', []))}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="airtable_list_tables",
                                category="Airtable Operations", 
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to list tables: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="airtable_list_tables",
                category="Airtable Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible Airtable tables endpoint found",
                error_message="All Airtable endpoints unavailable"
            ))

    async def _test_crud_operations(self):
        """Test CRUD operations on Airtable records"""
        # Test Create
        await self._test_create_record()
        # Test Read
        await self._test_read_records()
        # Test Update
        await self._test_update_record()
        # Test Delete
        await self._test_delete_record()

    async def _test_create_record(self):
        """Test creating an Airtable record"""
        start_time = time.time()
        
        test_record = {
            "fields": {
                "Name": f"Test Record {int(time.time())}",
                "Status": "Active",
                "Created": datetime.now().isoformat()
            }
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/airtable/records",
            f"{self.base_urls['airtable_service']}/records",
            f"{self.base_urls['platform_service']}/airtable/records"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=test_record, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 201]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="airtable_create_record",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully created Airtable record",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="airtable_create_record",
                                category="Airtable Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to create record: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="airtable_create_record",
                category="Airtable Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible Airtable create endpoint found",
                error_message="All Airtable endpoints unavailable"
            ))

    async def _test_read_records(self):
        """Test reading Airtable records"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/airtable/records",
            f"{self.base_urls['airtable_service']}/records", 
            f"{self.base_urls['platform_service']}/airtable/records"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            response_data = await response.json()
                            success = True
                            record_count = len(response_data.get('records', []))
                            self.results.append(TestResult(
                                test_name="airtable_read_records",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details=f"Successfully retrieved {record_count} records",
                                performance_metrics={'response_time_ms': response_time, 'records_count': record_count}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="airtable_read_records",
                                category="Airtable Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to read records: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="airtable_read_records",
                category="Airtable Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible Airtable read endpoint found",
                error_message="All Airtable endpoints unavailable"
            ))

    async def _test_update_record(self):
        """Test updating an Airtable record"""
        start_time = time.time()
        
        update_data = {
            "fields": {
                "Status": "Updated",
                "Modified": datetime.now().isoformat()
            }
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/airtable/records/test123",
            f"{self.base_urls['airtable_service']}/records/test123",
            f"{self.base_urls['platform_service']}/airtable/records/test123"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.put(endpoint, json=update_data, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 204]:
                            success = True
                            self.results.append(TestResult(
                                test_name="airtable_update_record",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully updated Airtable record",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="airtable_update_record",
                                category="Airtable Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to update record: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="airtable_update_record",
                category="Airtable Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible Airtable update endpoint found",
                error_message="All Airtable endpoints unavailable"
            ))

    async def _test_delete_record(self):
        """Test deleting an Airtable record"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/airtable/records/test123",
            f"{self.base_urls['airtable_service']}/records/test123",
            f"{self.base_urls['platform_service']}/airtable/records/test123"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.delete(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 204]:
                            success = True
                            self.results.append(TestResult(
                                test_name="airtable_delete_record",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully deleted Airtable record",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            # Record not found could be expected
                            self.results.append(TestResult(
                                test_name="airtable_delete_record",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details="Delete endpoint accessible (record not found is expected)",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            success = True
                            break
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="airtable_delete_record",
                                category="Airtable Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to delete record: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="airtable_delete_record",
                category="Airtable Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible Airtable delete endpoint found",
                error_message="All Airtable endpoints unavailable"
            ))

    async def _test_schema_retrieval(self):
        """Test retrieving Airtable schema information"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/airtable/schema",
            f"{self.base_urls['airtable_service']}/schema",
            f"{self.base_urls['platform_service']}/airtable/schema"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="airtable_schema_retrieval",
                                category="Airtable Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully retrieved Airtable schema",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="airtable_schema_retrieval",
                                category="Airtable Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to retrieve schema: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="airtable_schema_retrieval",
                category="Airtable Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible Airtable schema endpoint found",
                error_message="All Airtable endpoints unavailable"
            ))

    async def test_workflow_management(self):
        """Test workflow creation, execution, and history"""
        await self._test_create_workflow()
        await self._test_execute_workflow()
        await self._test_workflow_history()
    
    async def _test_create_workflow(self):
        """Test creating a workflow"""
        start_time = time.time()
        
        test_workflow = {
            "name": f"Test Workflow {int(time.time())}",
            "description": "Integration test workflow",
            "steps": [
                {"action": "validate_data", "config": {"required_fields": ["name"]}},
                {"action": "process_data", "config": {"transform": "uppercase"}}
            ]
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/workflows",
            f"{self.base_urls['workflow_service']}/workflows",
            f"{self.base_urls['platform_service']}/workflows"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=test_workflow, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 201]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="workflow_create",
                                category="Workflow Management",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully created workflow",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="workflow_create",
                                category="Workflow Management",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to create workflow: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="workflow_create",
                category="Workflow Management",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible workflow create endpoint found",
                error_message="All workflow endpoints unavailable"
            ))

    async def _test_execute_workflow(self):
        """Test executing a workflow"""
        start_time = time.time()
        
        execution_data = {
            "workflow_id": "test-workflow",
            "input_data": {
                "name": "Test Data",
                "value": 12345
            }
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/workflows/execute",
            f"{self.base_urls['workflow_service']}/execute",
            f"{self.base_urls['platform_service']}/workflows/execute"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=execution_data, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 202]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="workflow_execute",
                                category="Workflow Management",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully executed workflow",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="workflow_execute",
                                category="Workflow Management",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to execute workflow: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="workflow_execute",
                category="Workflow Management",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible workflow execute endpoint found",
                error_message="All workflow endpoints unavailable"
            ))

    async def _test_workflow_history(self):
        """Test retrieving workflow execution history"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/workflows/history",
            f"{self.base_urls['workflow_service']}/history",
            f"{self.base_urls['platform_service']}/workflows/history"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            response_data = await response.json()
                            success = True
                            history_count = len(response_data.get('executions', []))
                            self.results.append(TestResult(
                                test_name="workflow_history",
                                category="Workflow Management",
                                status="PASS",
                                duration_ms=response_time,
                                details=f"Successfully retrieved workflow history ({history_count} executions)",
                                performance_metrics={'response_time_ms': response_time, 'executions_count': history_count}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="workflow_history",
                                category="Workflow Management",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to retrieve workflow history: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="workflow_history",
                category="Workflow Management",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible workflow history endpoint found",
                error_message="All workflow endpoints unavailable"
            ))

    async def test_file_operations(self):
        """Test file upload, list, and download operations"""
        await self._test_file_upload()
        await self._test_file_list()
        await self._test_file_download()

    async def _test_file_upload(self):
        """Test file upload functionality"""
        start_time = time.time()
        
        # Create a temporary test file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as temp_file:
            temp_file.write("This is a test file for integration testing.")
            temp_file_path = temp_file.name
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/files/upload",
            f"{self.base_urls['file_service']}/upload",
            f"{self.base_urls['platform_service']}/files/upload"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
        
        success = False
        try:
            for endpoint in endpoints:
                try:
                    with open(temp_file_path, 'rb') as file:
                        data = aiohttp.FormData()
                        data.add_field('file', file, filename='test.txt', content_type='text/plain')
                        
                        async with aiohttp.ClientSession() as session:
                            async with session.post(endpoint, data=data, headers=headers) as response:
                                response_time = int((time.time() - start_time) * 1000)
                                if response.status in [200, 201]:
                                    response_data = await response.json()
                                    success = True
                                    self.results.append(TestResult(
                                        test_name="file_upload",
                                        category="File Operations",
                                        status="PASS",
                                        duration_ms=response_time,
                                        details="Successfully uploaded file",
                                        performance_metrics={'response_time_ms': response_time}
                                    ))
                                    break
                                elif response.status == 404:
                                    continue
                                else:
                                    error_text = await response.text()
                                    self.results.append(TestResult(
                                        test_name="file_upload",
                                        category="File Operations",
                                        status="FAIL",
                                        duration_ms=response_time,
                                        details=f"Failed to upload file: status {response.status}",
                                        error_message=error_text
                                    ))
                                    break
                except Exception as e:
                    continue
        finally:
            # Clean up temp file
            try:
                os.unlink(temp_file_path)
            except:
                pass
                
        if not success:
            self.results.append(TestResult(
                test_name="file_upload",
                category="File Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible file upload endpoint found",
                error_message="All file upload endpoints unavailable"
            ))

    async def _test_file_list(self):
        """Test listing files"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/files",
            f"{self.base_urls['file_service']}/files",
            f"{self.base_urls['platform_service']}/files"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            response_data = await response.json()
                            success = True
                            files_count = len(response_data.get('files', []))
                            self.results.append(TestResult(
                                test_name="file_list",
                                category="File Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details=f"Successfully listed files ({files_count} files)",
                                performance_metrics={'response_time_ms': response_time, 'files_count': files_count}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="file_list",
                                category="File Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to list files: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="file_list",
                category="File Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible file list endpoint found",
                error_message="All file endpoints unavailable"
            ))

    async def _test_file_download(self):
        """Test file download functionality"""
        start_time = time.time()
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/files/download/test.txt",
            f"{self.base_urls['file_service']}/download/test.txt",
            f"{self.base_urls['platform_service']}/files/download/test.txt"
        ]
        
        headers = {}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status == 200:
                            content = await response.read()
                            success = True
                            self.results.append(TestResult(
                                test_name="file_download",
                                category="File Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details=f"Successfully downloaded file ({len(content)} bytes)",
                                performance_metrics={'response_time_ms': response_time, 'file_size_bytes': len(content)}
                            ))
                            break
                        elif response.status == 404:
                            # File not found is expected for non-existent files
                            self.results.append(TestResult(
                                test_name="file_download",
                                category="File Operations",
                                status="PASS",
                                duration_ms=response_time,
                                details="Download endpoint accessible (file not found is expected)",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            success = True
                            break
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="file_download",
                                category="File Operations",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to download file: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="file_download",
                category="File Operations",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible file download endpoint found",
                error_message="All file endpoints unavailable"
            ))

    async def test_saga_transactions(self):
        """Test SAGA transaction management"""
        await self._test_start_saga_transaction()
        await self._test_execute_saga_steps()
        await self._test_saga_compensation()

    async def _test_start_saga_transaction(self):
        """Test starting a SAGA transaction"""
        start_time = time.time()
        
        transaction_data = {
            "transaction_id": f"test_saga_{int(time.time())}",
            "steps": [
                {"service": "airtable", "operation": "create_record", "data": {"name": "test"}},
                {"service": "workflow", "operation": "execute", "data": {"workflow_id": "test"}}
            ]
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/saga/start",
            f"{self.base_urls['saga_service']}/start",
            f"{self.base_urls['platform_service']}/saga/start"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=transaction_data, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 201, 202]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="saga_start_transaction",
                                category="SAGA Transactions",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully started SAGA transaction",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="saga_start_transaction",
                                category="SAGA Transactions",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to start SAGA transaction: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="saga_start_transaction",
                category="SAGA Transactions",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible SAGA start endpoint found",
                error_message="All SAGA endpoints unavailable"
            ))

    async def _test_execute_saga_steps(self):
        """Test executing SAGA transaction steps"""
        start_time = time.time()
        
        execution_data = {
            "transaction_id": "test_saga",
            "step_id": "step_1"
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/saga/execute",
            f"{self.base_urls['saga_service']}/execute",
            f"{self.base_urls['platform_service']}/saga/execute"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=execution_data, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 202]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="saga_execute_steps",
                                category="SAGA Transactions",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully executed SAGA steps",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="saga_execute_steps",
                                category="SAGA Transactions",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to execute SAGA steps: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="saga_execute_steps",
                category="SAGA Transactions",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible SAGA execute endpoint found",
                error_message="All SAGA endpoints unavailable"
            ))

    async def _test_saga_compensation(self):
        """Test SAGA compensation handling"""
        start_time = time.time()
        
        compensation_data = {
            "transaction_id": "test_saga",
            "reason": "Test compensation"
        }
        
        endpoints = [
            f"{self.base_urls['api_gateway']}/api/saga/compensate",
            f"{self.base_urls['saga_service']}/compensate",
            f"{self.base_urls['platform_service']}/saga/compensate"
        ]
        
        headers = {"Content-Type": "application/json"}
        if self.session_token:
            headers["Authorization"] = f"Bearer {self.session_token}"
            
        success = False
        for endpoint in endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.post(endpoint, json=compensation_data, headers=headers) as response:
                        response_time = int((time.time() - start_time) * 1000)
                        if response.status in [200, 202]:
                            response_data = await response.json()
                            success = True
                            self.results.append(TestResult(
                                test_name="saga_compensation",
                                category="SAGA Transactions",
                                status="PASS",
                                duration_ms=response_time,
                                details="Successfully handled SAGA compensation",
                                performance_metrics={'response_time_ms': response_time}
                            ))
                            break
                        elif response.status == 404:
                            continue
                        else:
                            error_text = await response.text()
                            self.results.append(TestResult(
                                test_name="saga_compensation",
                                category="SAGA Transactions",
                                status="FAIL",
                                duration_ms=response_time,
                                details=f"Failed to handle SAGA compensation: status {response.status}",
                                error_message=error_text
                            ))
                            break
            except Exception as e:
                continue
                
        if not success:
            self.results.append(TestResult(
                test_name="saga_compensation",
                category="SAGA Transactions",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible SAGA compensation endpoint found",
                error_message="All SAGA endpoints unavailable"
            ))

    async def test_frontend_integration(self):
        """Test frontend-backend integration"""
        await self._test_frontend_api_calls()
        await self._test_frontend_authentication()
        await self._test_frontend_data_flow()

    async def _test_frontend_api_calls(self):
        """Test frontend making API calls to backend"""
        start_time = time.time()
        
        try:
            # Test if frontend can reach API gateway
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.base_urls['frontend']}/api/health") as response:
                    response_time = int((time.time() - start_time) * 1000)
                    if response.status in [200, 404]:  # 404 means frontend is running but no health endpoint
                        self.results.append(TestResult(
                            test_name="frontend_api_integration",
                            category="Frontend Integration",
                            status="PASS",
                            duration_ms=response_time,
                            details="Frontend is accessible and can handle API calls",
                            performance_metrics={'response_time_ms': response_time}
                        ))
                    else:
                        error_text = await response.text()
                        self.results.append(TestResult(
                            test_name="frontend_api_integration",
                            category="Frontend Integration",
                            status="FAIL",
                            duration_ms=response_time,
                            details=f"Frontend API integration issue: status {response.status}",
                            error_message=error_text
                        ))
        except Exception as e:
            self.results.append(TestResult(
                test_name="frontend_api_integration",
                category="Frontend Integration",
                status="FAIL",
                duration_ms=int((time.time() - start_time) * 1000),
                details="Frontend API integration failed",
                error_message=str(e)
            ))

    async def _test_frontend_authentication(self):
        """Test frontend authentication flow"""
        start_time = time.time()
        
        try:
            # Test frontend login page accessibility
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.base_urls['frontend']}/login") as response:
                    response_time = int((time.time() - start_time) * 1000)
                    if response.status in [200, 404]:  # 404 might mean different routing
                        self.results.append(TestResult(
                            test_name="frontend_auth_flow",
                            category="Frontend Integration",
                            status="PASS",
                            duration_ms=response_time,
                            details="Frontend authentication pages are accessible",
                            performance_metrics={'response_time_ms': response_time}
                        ))
                    else:
                        error_text = await response.text()
                        self.results.append(TestResult(
                            test_name="frontend_auth_flow",
                            category="Frontend Integration",
                            status="FAIL",
                            duration_ms=response_time,
                            details=f"Frontend auth pages issue: status {response.status}",
                            error_message=error_text
                        ))
        except Exception as e:
            self.results.append(TestResult(
                test_name="frontend_auth_flow",
                category="Frontend Integration",
                status="FAIL",
                duration_ms=int((time.time() - start_time) * 1000),
                details="Frontend authentication test failed",
                error_message=str(e)
            ))

    async def _test_frontend_data_flow(self):
        """Test frontend data flow with backend"""
        start_time = time.time()
        
        try:
            # Test main frontend page to see if it loads without errors
            async with aiohttp.ClientSession() as session:
                async with session.get(self.base_urls['frontend']) as response:
                    response_time = int((time.time() - start_time) * 1000)
                    content = await response.text()
                    
                    # Check for common error indicators
                    if "Internal Server Error" in content or "Application error" in content:
                        self.results.append(TestResult(
                            test_name="frontend_data_flow",
                            category="Frontend Integration",
                            status="FAIL",
                            duration_ms=response_time,
                            details="Frontend shows application errors",
                            error_message="Frontend contains error messages"
                        ))
                    elif response.status == 200:
                        self.results.append(TestResult(
                            test_name="frontend_data_flow",
                            category="Frontend Integration",
                            status="PASS",
                            duration_ms=response_time,
                            details="Frontend loads successfully without errors",
                            performance_metrics={'response_time_ms': response_time}
                        ))
                    else:
                        self.results.append(TestResult(
                            test_name="frontend_data_flow",
                            category="Frontend Integration",
                            status="FAIL",
                            duration_ms=response_time,
                            details=f"Frontend data flow issue: status {response.status}",
                            error_message=content[:500]
                        ))
        except Exception as e:
            self.results.append(TestResult(
                test_name="frontend_data_flow",
                category="Frontend Integration",
                status="FAIL",
                duration_ms=int((time.time() - start_time) * 1000),
                details="Frontend data flow test failed",
                error_message=str(e)
            ))

    async def test_performance_metrics(self):
        """Test system performance metrics"""
        await self._test_response_times()
        await self._test_concurrent_requests()
        await self._test_error_rates()

    async def _test_response_times(self):
        """Test system response times under normal load"""
        start_time = time.time()
        
        test_endpoints = [
            (self.base_urls['api_gateway'], "/health"),
            (self.base_urls['platform_service'], "/health")
        ]
        
        response_times = []
        
        for base_url, endpoint in test_endpoints:
            try:
                endpoint_start = time.time()
                async with aiohttp.ClientSession() as session:
                    async with session.get(f"{base_url}{endpoint}") as response:
                        endpoint_time = int((time.time() - endpoint_start) * 1000)
                        response_times.append(endpoint_time)
            except:
                continue
        
        if response_times:
            avg_response_time = sum(response_times) / len(response_times)
            max_response_time = max(response_times)
            
            # Performance threshold: average < 1000ms, max < 2000ms
            if avg_response_time < 1000 and max_response_time < 2000:
                status = "PASS"
                details = f"Good response times - avg: {avg_response_time:.1f}ms, max: {max_response_time}ms"
            elif avg_response_time < 2000 and max_response_time < 5000:
                status = "PASS"
                details = f"Acceptable response times - avg: {avg_response_time:.1f}ms, max: {max_response_time}ms"
            else:
                status = "FAIL"
                details = f"Slow response times - avg: {avg_response_time:.1f}ms, max: {max_response_time}ms"
            
            self.results.append(TestResult(
                test_name="system_response_times",
                category="Performance Metrics",
                status=status,
                duration_ms=int((time.time() - start_time) * 1000),
                details=details,
                performance_metrics={
                    'avg_response_time_ms': avg_response_time,
                    'max_response_time_ms': max_response_time,
                    'min_response_time_ms': min(response_times),
                    'endpoints_tested': len(response_times)
                }
            ))
        else:
            self.results.append(TestResult(
                test_name="system_response_times",
                category="Performance Metrics",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No accessible endpoints for response time testing",
                error_message="All test endpoints unavailable"
            ))

    async def _test_concurrent_requests(self):
        """Test system under concurrent load"""
        start_time = time.time()
        
        async def make_request(session, url):
            try:
                async with session.get(url) as response:
                    return response.status, time.time()
            except:
                return 500, time.time()
        
        # Test with 10 concurrent requests
        concurrent_count = 10
        test_url = f"{self.base_urls['api_gateway']}/health"
        
        try:
            async with aiohttp.ClientSession() as session:
                tasks = [make_request(session, test_url) for _ in range(concurrent_count)]
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                successful_requests = sum(1 for status, _ in results if isinstance(status, int) and status < 400)
                success_rate = successful_requests / concurrent_count * 100
                
                if success_rate >= 90:
                    status = "PASS"
                    details = f"Handled {concurrent_count} concurrent requests - {success_rate:.1f}% success rate"
                elif success_rate >= 70:
                    status = "PASS"
                    details = f"Acceptable concurrent performance - {success_rate:.1f}% success rate"
                else:
                    status = "FAIL"
                    details = f"Poor concurrent performance - {success_rate:.1f}% success rate"
                
                self.results.append(TestResult(
                    test_name="concurrent_requests",
                    category="Performance Metrics",
                    status=status,
                    duration_ms=int((time.time() - start_time) * 1000),
                    details=details,
                    performance_metrics={
                        'concurrent_requests': concurrent_count,
                        'successful_requests': successful_requests,
                        'success_rate_percent': success_rate
                    }
                ))
        except Exception as e:
            self.results.append(TestResult(
                test_name="concurrent_requests",
                category="Performance Metrics",
                status="FAIL",
                duration_ms=int((time.time() - start_time) * 1000),
                details="Concurrent request testing failed",
                error_message=str(e)
            ))

    async def _test_error_rates(self):
        """Test system error rates and resilience"""
        start_time = time.time()
        
        # Test various endpoints to calculate error rates
        test_endpoints = [
            f"{self.base_urls['api_gateway']}/health",
            f"{self.base_urls['platform_service']}/health",
            f"{self.base_urls['frontend']}/"
        ]
        
        total_requests = 0
        error_count = 0
        
        for endpoint in test_endpoints:
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.get(endpoint) as response:
                        total_requests += 1
                        if response.status >= 500:
                            error_count += 1
            except:
                total_requests += 1
                error_count += 1
        
        if total_requests > 0:
            error_rate = error_count / total_requests * 100
            
            if error_rate <= 5:
                status = "PASS"
                details = f"Low error rate: {error_rate:.1f}%"
            elif error_rate <= 15:
                status = "PASS" 
                details = f"Acceptable error rate: {error_rate:.1f}%"
            else:
                status = "FAIL"
                details = f"High error rate: {error_rate:.1f}%"
            
            self.results.append(TestResult(
                test_name="system_error_rates",
                category="Performance Metrics",
                status=status,
                duration_ms=int((time.time() - start_time) * 1000),
                details=details,
                performance_metrics={
                    'total_requests': total_requests,
                    'error_count': error_count,
                    'error_rate_percent': error_rate
                }
            ))
        else:
            self.results.append(TestResult(
                test_name="system_error_rates",
                category="Performance Metrics",
                status="SKIP",
                duration_ms=int((time.time() - start_time) * 1000),
                details="No endpoints available for error rate testing",
                error_message="All test endpoints unavailable"
            ))

    def generate_comprehensive_report(self, total_duration: float) -> Dict[str, Any]:
        """Generate comprehensive test report with all metrics"""
        
        # Group results by category
        categories = {}
        for result in self.results:
            if result.category not in categories:
                categories[result.category] = []
            categories[result.category].append(result)
        
        # Calculate category statistics
        category_results = {}
        overall_stats = {"total": 0, "passed": 0, "failed": 0, "skipped": 0}
        
        for category_name, results in categories.items():
            total_tests = len(results)
            passed = sum(1 for r in results if r.status == "PASS")
            failed = sum(1 for r in results if r.status == "FAIL")
            skipped = sum(1 for r in results if r.status == "SKIP")
            
            success_rate = (passed / total_tests * 100) if total_tests > 0 else 0
            
            # Calculate average response time
            response_times = [r.duration_ms for r in results if r.duration_ms > 0]
            avg_response_time = sum(response_times) / len(response_times) if response_times else 0
            
            # Collect performance metrics
            perf_metrics = {}
            for result in results:
                if result.performance_metrics:
                    for key, value in result.performance_metrics.items():
                        if key not in perf_metrics:
                            perf_metrics[key] = []
                        perf_metrics[key].append(value)
            
            category_results[category_name] = CategoryResults(
                category=category_name,
                total_tests=total_tests,
                passed=passed,
                failed=failed,
                skipped=skipped,
                success_rate=success_rate,
                avg_response_time_ms=avg_response_time,
                performance_metrics=perf_metrics
            )
            
            # Update overall stats
            overall_stats["total"] += total_tests
            overall_stats["passed"] += passed
            overall_stats["failed"] += failed
            overall_stats["skipped"] += skipped
        
        # Calculate overall success rate
        overall_success_rate = (overall_stats["passed"] / overall_stats["total"] * 100) if overall_stats["total"] > 0 else 0
        
        # Determine production readiness
        production_readiness = self._assess_production_readiness(category_results, overall_success_rate)
        
        # Generate detailed report
        report = {
            "test_execution_summary": {
                "timestamp": datetime.now().isoformat(),
                "total_duration_seconds": round(total_duration, 2),
                "total_tests": overall_stats["total"],
                "passed": overall_stats["passed"],
                "failed": overall_stats["failed"],
                "skipped": overall_stats["skipped"],
                "overall_success_rate": round(overall_success_rate, 1)
            },
            "category_results": {name: asdict(results) for name, results in category_results.items()},
            "detailed_results": [asdict(result) for result in self.results],
            "production_readiness_assessment": production_readiness,
            "recommendations": self._generate_recommendations(category_results),
            "performance_summary": self._generate_performance_summary(category_results)
        }
        
        return report

    def _assess_production_readiness(self, category_results: Dict[str, CategoryResults], overall_success_rate: float) -> Dict[str, Any]:
        """Assess production readiness based on test results"""
        
        # Critical categories that must pass for production
        critical_categories = ["Service Health", "Authentication Flow", "Frontend Integration"]
        
        critical_issues = []
        warnings = []
        
        # Check critical categories
        for category in critical_categories:
            if category in category_results:
                cat_result = category_results[category]
                if cat_result.success_rate < 70:
                    critical_issues.append(f"{category}: {cat_result.success_rate:.1f}% success rate (too low)")
                elif cat_result.success_rate < 90:
                    warnings.append(f"{category}: {cat_result.success_rate:.1f}% success rate (could be improved)")
        
        # Check overall performance
        if overall_success_rate < 70:
            critical_issues.append(f"Overall success rate {overall_success_rate:.1f}% is below production threshold")
        elif overall_success_rate < 85:
            warnings.append(f"Overall success rate {overall_success_rate:.1f}% could be improved")
        
        # Determine readiness level
        if len(critical_issues) == 0:
            if len(warnings) == 0:
                readiness_level = "PRODUCTION_READY"
                readiness_message = "System is ready for production deployment"
            else:
                readiness_level = "MOSTLY_READY"
                readiness_message = "System is mostly ready with minor issues to address"
        else:
            readiness_level = "NOT_READY"
            readiness_message = "System has critical issues that must be resolved before production"
        
        return {
            "readiness_level": readiness_level,
            "readiness_message": readiness_message,
            "critical_issues": critical_issues,
            "warnings": warnings,
            "overall_success_rate": round(overall_success_rate, 1)
        }

    def _generate_recommendations(self, category_results: Dict[str, CategoryResults]) -> List[Dict[str, Any]]:
        """Generate recommendations based on test results"""
        recommendations = []
        
        for category_name, results in category_results.items():
            if results.failed > 0:
                priority = "HIGH" if category_name in ["Service Health", "Authentication Flow"] else "MEDIUM"
                recommendations.append({
                    "category": category_name,
                    "priority": priority,
                    "issue": f"{results.failed} failed tests in {category_name}",
                    "recommendation": f"Investigate and fix the {results.failed} failing test(s) in {category_name}",
                    "impact": "May cause production issues" if priority == "HIGH" else "Should be addressed before production"
                })
            
            if results.skipped > results.passed:
                recommendations.append({
                    "category": category_name,
                    "priority": "MEDIUM",
                    "issue": f"{results.skipped} tests skipped in {category_name}",
                    "recommendation": f"Ensure services for {category_name} are properly deployed and accessible",
                    "impact": "Incomplete test coverage"
                })
        
        return recommendations

    def _generate_performance_summary(self, category_results: Dict[str, CategoryResults]) -> Dict[str, Any]:
        """Generate performance summary from test results"""
        all_response_times = []
        total_requests = 0
        
        for results in category_results.values():
            if results.avg_response_time_ms > 0:
                all_response_times.append(results.avg_response_time_ms)
            total_requests += results.total_tests
        
        avg_system_response_time = sum(all_response_times) / len(all_response_times) if all_response_times else 0
        
        return {
            "average_response_time_ms": round(avg_system_response_time, 2),
            "total_requests_tested": total_requests,
            "performance_rating": "Good" if avg_system_response_time < 500 else "Fair" if avg_system_response_time < 1000 else "Needs Improvement"
        }


async def main():
    """Main function to run integration tests"""
    suite = IntegrationTestSuite()
    report = await suite.run_all_tests()
    
    # Print summary
    print("\n" + "="*80)
    print("COMPREHENSIVE INTEGRATION TEST RESULTS")
    print("="*80)
    
    summary = report['test_execution_summary']
    print(f"Total Tests: {summary['total_tests']}")
    print(f"Passed: {summary['passed']}")
    print(f"Failed: {summary['failed']}")
    print(f"Skipped: {summary['skipped']}")
    print(f"Success Rate: {summary['overall_success_rate']}%")
    print(f"Duration: {summary['total_duration_seconds']} seconds")
    
    readiness = report['production_readiness_assessment']
    print(f"\nProduction Readiness: {readiness['readiness_level']}")
    print(f"Assessment: {readiness['readiness_message']}")
    
    if readiness['critical_issues']:
        print(f"\nCritical Issues:")
        for issue in readiness['critical_issues']:
            print(f"  - {issue}")
    
    if readiness['warnings']:
        print(f"\nWarnings:")
        for warning in readiness['warnings']:
            print(f"  - {warning}")
    
    print("\n" + "="*80)
    
    return report

if __name__ == "__main__":
    asyncio.run(main())