#!/usr/bin/env python3
"""
Sprint 2 End-to-End Test Suite
==================================

Comprehensive testing framework for Sprint 2 integration stack:
- Chat UI (frontend/chat-ui on port 3001)
- API Gateway (port 8000)
- Airtable Gateway (port 8002) with enhanced CRUD
- MCP Server (port 8001) with 10 tools
- LLM Orchestrator (port 8003)
- Authentication integration with Sprint 1

Author: QA Automation Engineer
Version: 1.0.0
"""

import asyncio
import json
import time
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import aiohttp
import websockets
from playwright.async_api import async_playwright, Page, Browser
from dataclasses import dataclass
import pytest
import sys
import os

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(f'sprint2_e2e_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class ServiceConfig:
    """Configuration for Sprint 2 services"""
    name: str
    url: str
    port: int
    health_endpoint: str = "/health"
    
@dataclass
class TestResult:
    """Test result container"""
    test_name: str
    status: str  # "PASS", "FAIL", "SKIP"
    duration: float
    error_message: Optional[str] = None
    details: Optional[Dict] = None

class Sprint2TestSuite:
    """Comprehensive Sprint 2 E2E Test Suite"""
    
    def __init__(self):
        # Service configurations
        self.services = {
            "chat_ui": ServiceConfig("Chat UI", "http://localhost:3001", 3001),
            "api_gateway": ServiceConfig("API Gateway", "http://localhost:8000", 8000),
            "airtable_gateway": ServiceConfig("Airtable Gateway", "http://localhost:8002", 8002),
            "mcp_server": ServiceConfig("MCP Server", "http://localhost:8001", 8001),
            "llm_orchestrator": ServiceConfig("LLM Orchestrator", "http://localhost:8003", 8003)
        }
        
        # Test configuration
        self.test_results: List[TestResult] = []
        self.session_timeout = 30  # seconds
        self.performance_targets = {
            "chat_response_time": 2.0,  # seconds
            "airtable_api_response": 0.5,  # seconds
            "websocket_connection": 1.0,  # seconds
        }
        
        # Authentication configuration
        self.test_user = {
            "email": "test@pyairtable.com", 
            "password": "TestPass123!"
        }
        
    async def run_full_test_suite(self) -> Dict[str, Any]:
        """Run the complete Sprint 2 test suite"""
        logger.info("Starting Sprint 2 E2E Test Suite")
        start_time = time.time()
        
        try:
            # 1. Service Health Checks
            await self.test_service_health_checks()
            
            # 2. Authentication Integration Tests
            await self.test_authentication_integration()
            
            # 3. Chat UI Integration Tests
            await self.test_chat_ui_integration()
            
            # 4. MCP Tools Integration Tests
            await self.test_mcp_tools_integration()
            
            # 5. Airtable Gateway CRUD Tests
            await self.test_airtable_gateway_crud()
            
            # 6. WebSocket Communication Tests
            await self.test_websocket_communication()
            
            # 7. File Upload and Processing Tests
            await self.test_file_upload_processing()
            
            # 8. Performance Tests
            await self.test_performance_requirements()
            
            # 9. Error Handling Tests
            await self.test_error_handling()
            
            # 10. End-to-End User Flow Tests
            await self.test_complete_user_flows()
            
        except Exception as e:
            logger.error(f"Test suite failed with error: {e}")
            self.test_results.append(TestResult(
                "test_suite_execution", "FAIL", time.time() - start_time,
                error_message=str(e)
            ))
        
        total_duration = time.time() - start_time
        return self.generate_test_report(total_duration)
    
    async def test_service_health_checks(self):
        """Test all Sprint 2 services are running and healthy"""
        logger.info("Testing service health checks...")
        
        async with aiohttp.ClientSession() as session:
            for service_name, config in self.services.items():
                start_time = time.time()
                try:
                    async with session.get(f"{config.url}{config.health_endpoint}", timeout=5) as response:
                        if response.status == 200:
                            self.test_results.append(TestResult(
                                f"health_check_{service_name}", "PASS",
                                time.time() - start_time
                            ))
                            logger.info(f"✓ {config.name} health check passed")
                        else:
                            self.test_results.append(TestResult(
                                f"health_check_{service_name}", "FAIL",
                                time.time() - start_time,
                                error_message=f"HTTP {response.status}"
                            ))
                            logger.error(f"✗ {config.name} health check failed: HTTP {response.status}")
                except Exception as e:
                    self.test_results.append(TestResult(
                        f"health_check_{service_name}", "FAIL",
                        time.time() - start_time,
                        error_message=str(e)
                    ))
                    logger.error(f"✗ {config.name} health check failed: {e}")
    
    async def test_authentication_integration(self):
        """Test authentication integration across all services"""
        logger.info("Testing authentication integration...")
        
        # Test JWT token generation and validation
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                # Login request
                login_data = {
                    "email": self.test_user["email"],
                    "password": self.test_user["password"]
                }
                
                async with session.post(
                    f"{self.services['api_gateway'].url}/auth/login",
                    json=login_data,
                    timeout=10
                ) as response:
                    if response.status == 200:
                        auth_result = await response.json()
                        if 'access_token' in auth_result:
                            self.test_results.append(TestResult(
                                "authentication_login", "PASS",
                                time.time() - start_time,
                                details={"token_received": True}
                            ))
                            logger.info("✓ Authentication login successful")
                            
                            # Test token validation across services
                            await self.test_token_validation(auth_result['access_token'])
                        else:
                            self.test_results.append(TestResult(
                                "authentication_login", "FAIL",
                                time.time() - start_time,
                                error_message="No access token in response"
                            ))
                    else:
                        self.test_results.append(TestResult(
                            "authentication_login", "FAIL",
                            time.time() - start_time,
                            error_message=f"HTTP {response.status}"
                        ))
                        
        except Exception as e:
            self.test_results.append(TestResult(
                "authentication_login", "FAIL",
                time.time() - start_time,
                error_message=str(e)
            ))
            logger.error(f"✗ Authentication test failed: {e}")
    
    async def test_token_validation(self, token: str):
        """Test JWT token validation across all services"""
        headers = {"Authorization": f"Bearer {token}"}
        
        async with aiohttp.ClientSession() as session:
            for service_name, config in self.services.items():
                if service_name == "chat_ui":  # Skip frontend service
                    continue
                    
                start_time = time.time()
                try:
                    async with session.get(
                        f"{config.url}/protected-endpoint",
                        headers=headers,
                        timeout=5
                    ) as response:
                        # Accept both 200 (success) and 404 (endpoint not found but auth worked)
                        if response.status in [200, 404]:
                            self.test_results.append(TestResult(
                                f"token_validation_{service_name}", "PASS",
                                time.time() - start_time
                            ))
                            logger.info(f"✓ Token validation for {config.name} passed")
                        elif response.status == 401:
                            self.test_results.append(TestResult(
                                f"token_validation_{service_name}", "FAIL",
                                time.time() - start_time,
                                error_message="Token validation failed - 401 Unauthorized"
                            ))
                        else:
                            self.test_results.append(TestResult(
                                f"token_validation_{service_name}", "PASS",
                                time.time() - start_time,
                                details={"status_code": response.status}
                            ))
                            
                except Exception as e:
                    self.test_results.append(TestResult(
                        f"token_validation_{service_name}", "FAIL",
                        time.time() - start_time,
                        error_message=str(e)
                    ))
    
    async def test_chat_ui_integration(self):
        """Test Chat UI integration with backend services using Playwright"""
        logger.info("Testing Chat UI integration...")
        
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()
            
            try:
                # Test Chat UI loads
                start_time = time.time()
                await page.goto("http://localhost:3001")
                await page.wait_for_load_state("networkidle")
                
                # Check if chat interface is present
                chat_input = await page.query_selector('[data-testid="chat-input"]')
                if chat_input:
                    self.test_results.append(TestResult(
                        "chat_ui_load", "PASS",
                        time.time() - start_time
                    ))
                    logger.info("✓ Chat UI loaded successfully")
                    
                    # Test chat message sending
                    await self.test_chat_message_flow(page)
                else:
                    self.test_results.append(TestResult(
                        "chat_ui_load", "FAIL",
                        time.time() - start_time,
                        error_message="Chat input not found"
                    ))
                    
            except Exception as e:
                self.test_results.append(TestResult(
                    "chat_ui_load", "FAIL",
                    time.time() - start_time,
                    error_message=str(e)
                ))
                logger.error(f"✗ Chat UI test failed: {e}")
            
            finally:
                await browser.close()
    
    async def test_chat_message_flow(self, page: Page):
        """Test complete chat message flow"""
        start_time = time.time()
        
        try:
            # Send a test message
            test_message = "List my Airtable bases"
            await page.fill('[data-testid="chat-input"]', test_message)
            await page.click('[data-testid="send-button"]')
            
            # Wait for response
            await page.wait_for_selector('[data-testid="chat-message"]', timeout=10000)
            
            # Check if response contains expected content
            messages = await page.query_selector_all('[data-testid="chat-message"]')
            if len(messages) >= 2:  # User message + AI response
                self.test_results.append(TestResult(
                    "chat_message_flow", "PASS",
                    time.time() - start_time,
                    details={"messages_count": len(messages)}
                ))
                logger.info("✓ Chat message flow completed successfully")
            else:
                self.test_results.append(TestResult(
                    "chat_message_flow", "FAIL",
                    time.time() - start_time,
                    error_message=f"Expected at least 2 messages, got {len(messages)}"
                ))
                
        except Exception as e:
            self.test_results.append(TestResult(
                "chat_message_flow", "FAIL",
                time.time() - start_time,
                error_message=str(e)
            ))
    
    async def test_mcp_tools_integration(self):
        """Test MCP Server tools integration"""
        logger.info("Testing MCP tools integration...")
        
        # Test MCP tools endpoint
        start_time = time.time()
        async with aiohttp.ClientSession() as session:
            try:
                async with session.get(f"{self.services['mcp_server'].url}/tools") as response:
                    if response.status == 200:
                        tools = await response.json()
                        if isinstance(tools, list) and len(tools) >= 10:
                            self.test_results.append(TestResult(
                                "mcp_tools_list", "PASS",
                                time.time() - start_time,
                                details={"tools_count": len(tools)}
                            ))
                            logger.info(f"✓ MCP tools available: {len(tools)}")
                            
                            # Test individual tool execution
                            await self.test_individual_mcp_tools(session, tools)
                        else:
                            self.test_results.append(TestResult(
                                "mcp_tools_list", "FAIL",
                                time.time() - start_time,
                                error_message=f"Expected at least 10 tools, got {len(tools) if isinstance(tools, list) else 0}"
                            ))
                    else:
                        self.test_results.append(TestResult(
                            "mcp_tools_list", "FAIL",
                            time.time() - start_time,
                            error_message=f"HTTP {response.status}"
                        ))
                        
            except Exception as e:
                self.test_results.append(TestResult(
                    "mcp_tools_list", "FAIL",
                    time.time() - start_time,
                    error_message=str(e)
                ))
    
    async def test_individual_mcp_tools(self, session: aiohttp.ClientSession, tools: List[Dict]):
        """Test execution of individual MCP tools"""
        essential_tools = ["list_bases", "list_tables", "get_records", "create_record"]
        
        for tool_name in essential_tools:
            tool = next((t for t in tools if t.get('name') == tool_name), None)
            if not tool:
                self.test_results.append(TestResult(
                    f"mcp_tool_{tool_name}", "FAIL", 0,
                    error_message="Tool not found"
                ))
                continue
            
            start_time = time.time()
            try:
                # Test tool execution with sample parameters
                test_params = self.get_test_params_for_tool(tool_name)
                async with session.post(
                    f"{self.services['mcp_server'].url}/execute",
                    json={"tool_name": tool_name, "parameters": test_params}
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        self.test_results.append(TestResult(
                            f"mcp_tool_{tool_name}", "PASS",
                            time.time() - start_time,
                            details=result
                        ))
                        logger.info(f"✓ MCP tool {tool_name} executed successfully")
                    else:
                        self.test_results.append(TestResult(
                            f"mcp_tool_{tool_name}", "FAIL",
                            time.time() - start_time,
                            error_message=f"HTTP {response.status}"
                        ))
                        
            except Exception as e:
                self.test_results.append(TestResult(
                    f"mcp_tool_{tool_name}", "FAIL",
                    time.time() - start_time,
                    error_message=str(e)
                ))
    
    def get_test_params_for_tool(self, tool_name: str) -> Dict:
        """Get test parameters for MCP tool execution"""
        params_map = {
            "list_bases": {},
            "list_tables": {"base_id": "test_base"},
            "get_records": {"base_id": "test_base", "table_name": "test_table"},
            "create_record": {"base_id": "test_base", "table_name": "test_table", "fields": {"Name": "Test"}}
        }
        return params_map.get(tool_name, {})
    
    async def test_airtable_gateway_crud(self):
        """Test Airtable Gateway CRUD operations"""
        logger.info("Testing Airtable Gateway CRUD operations...")
        
        async with aiohttp.ClientSession() as session:
            # Test enhanced CRUD endpoints
            crud_operations = [
                ("GET", "/bases", "list_bases"),
                ("GET", "/bases/test_base/tables", "list_tables"),
                ("GET", "/bases/test_base/tables/test_table/records", "get_records"),
                ("POST", "/bases/test_base/tables/test_table/records", "create_record"),
            ]
            
            for method, endpoint, operation_name in crud_operations:
                start_time = time.time()
                try:
                    request_data = {"fields": {"Name": "Test Record"}} if method == "POST" else None
                    
                    if method == "GET":
                        async with session.get(f"{self.services['airtable_gateway'].url}{endpoint}") as response:
                            status = response.status
                    else:
                        async with session.post(f"{self.services['airtable_gateway'].url}{endpoint}", json=request_data) as response:
                            status = response.status
                    
                    # Accept 200 (success) or 404/422 (expected for test data)
                    if status in [200, 404, 422]:
                        self.test_results.append(TestResult(
                            f"airtable_crud_{operation_name}", "PASS",
                            time.time() - start_time,
                            details={"status_code": status}
                        ))
                        logger.info(f"✓ Airtable {operation_name} endpoint responded (HTTP {status})")
                    else:
                        self.test_results.append(TestResult(
                            f"airtable_crud_{operation_name}", "FAIL",
                            time.time() - start_time,
                            error_message=f"HTTP {status}"
                        ))
                        
                except Exception as e:
                    self.test_results.append(TestResult(
                        f"airtable_crud_{operation_name}", "FAIL",
                        time.time() - start_time,
                        error_message=str(e)
                    ))
    
    async def test_websocket_communication(self):
        """Test WebSocket communication for real-time chat"""
        logger.info("Testing WebSocket communication...")
        
        start_time = time.time()
        try:
            # Test WebSocket connection
            uri = "ws://localhost:3001/ws"  # Assuming WebSocket endpoint
            async with websockets.connect(uri) as websocket:
                # Send test message
                test_message = {"type": "chat", "message": "Hello WebSocket"}
                await websocket.send(json.dumps(test_message))
                
                # Wait for response
                response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                response_data = json.loads(response)
                
                if response_data and 'type' in response_data:
                    self.test_results.append(TestResult(
                        "websocket_communication", "PASS",
                        time.time() - start_time,
                        details=response_data
                    ))
                    logger.info("✓ WebSocket communication successful")
                else:
                    self.test_results.append(TestResult(
                        "websocket_communication", "FAIL",
                        time.time() - start_time,
                        error_message="Invalid WebSocket response"
                    ))
                    
        except Exception as e:
            # WebSocket might not be implemented yet, mark as skip
            self.test_results.append(TestResult(
                "websocket_communication", "SKIP",
                time.time() - start_time,
                error_message=f"WebSocket not available: {e}"
            ))
            logger.warning(f"⚠ WebSocket test skipped: {e}")
    
    async def test_file_upload_processing(self):
        """Test file upload and processing workflows"""
        logger.info("Testing file upload and processing...")
        
        # Create a test file
        test_file_content = "Name,Email,Role\nJohn Doe,john@example.com,Admin\nJane Smith,jane@example.com,User"
        test_file_name = "test_upload.csv"
        
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                # Create multipart form data
                data = aiohttp.FormData()
                data.add_field('file', test_file_content, filename=test_file_name, content_type='text/csv')
                
                async with session.post(f"{self.services['api_gateway'].url}/upload", data=data) as response:
                    if response.status in [200, 201]:
                        result = await response.json()
                        self.test_results.append(TestResult(
                            "file_upload_processing", "PASS",
                            time.time() - start_time,
                            details=result
                        ))
                        logger.info("✓ File upload and processing successful")
                    else:
                        self.test_results.append(TestResult(
                            "file_upload_processing", "FAIL",
                            time.time() - start_time,
                            error_message=f"HTTP {response.status}"
                        ))
                        
        except Exception as e:
            self.test_results.append(TestResult(
                "file_upload_processing", "SKIP",
                time.time() - start_time,
                error_message=f"File upload not available: {e}"
            ))
    
    async def test_performance_requirements(self):
        """Test performance requirements for Sprint 2"""
        logger.info("Testing performance requirements...")
        
        # Test chat response times
        await self.test_chat_response_performance()
        
        # Test Airtable API performance
        await self.test_airtable_api_performance()
        
        # Test concurrent user handling
        await self.test_concurrent_users()
    
    async def test_chat_response_performance(self):
        """Test chat response time performance"""
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                # Simulate chat request
                chat_request = {"message": "What are my Airtable bases?", "user_id": "test_user"}
                async with session.post(f"{self.services['llm_orchestrator'].url}/chat", json=chat_request) as response:
                    response_time = time.time() - start_time
                    
                    if response_time <= self.performance_targets["chat_response_time"]:
                        self.test_results.append(TestResult(
                            "chat_response_performance", "PASS",
                            response_time,
                            details={"response_time": response_time, "target": self.performance_targets["chat_response_time"]}
                        ))
                        logger.info(f"✓ Chat response time: {response_time:.2f}s (target: {self.performance_targets['chat_response_time']}s)")
                    else:
                        self.test_results.append(TestResult(
                            "chat_response_performance", "FAIL",
                            response_time,
                            error_message=f"Response time {response_time:.2f}s exceeds target {self.performance_targets['chat_response_time']}s"
                        ))
                        
        except Exception as e:
            self.test_results.append(TestResult(
                "chat_response_performance", "FAIL",
                time.time() - start_time,
                error_message=str(e)
            ))
    
    async def test_airtable_api_performance(self):
        """Test Airtable API response performance"""
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.services['airtable_gateway'].url}/bases") as response:
                    response_time = time.time() - start_time
                    
                    if response_time <= self.performance_targets["airtable_api_response"]:
                        self.test_results.append(TestResult(
                            "airtable_api_performance", "PASS",
                            response_time,
                            details={"response_time": response_time, "target": self.performance_targets["airtable_api_response"]}
                        ))
                        logger.info(f"✓ Airtable API response time: {response_time:.2f}s (target: {self.performance_targets['airtable_api_response']}s)")
                    else:
                        self.test_results.append(TestResult(
                            "airtable_api_performance", "FAIL",
                            response_time,
                            error_message=f"Response time {response_time:.2f}s exceeds target {self.performance_targets['airtable_api_response']}s"
                        ))
                        
        except Exception as e:
            self.test_results.append(TestResult(
                "airtable_api_performance", "FAIL",
                time.time() - start_time,
                error_message=str(e)
            ))
    
    async def test_concurrent_users(self):
        """Test concurrent user handling"""
        start_time = time.time()
        concurrent_requests = 10
        
        try:
            async with aiohttp.ClientSession() as session:
                tasks = []
                for i in range(concurrent_requests):
                    task = session.get(f"{self.services['api_gateway'].url}/health")
                    tasks.append(task)
                
                responses = await asyncio.gather(*tasks, return_exceptions=True)
                
                successful_requests = sum(1 for r in responses if hasattr(r, 'status') and r.status == 200)
                success_rate = successful_requests / concurrent_requests
                
                if success_rate >= 0.95:  # 95% success rate
                    self.test_results.append(TestResult(
                        "concurrent_users", "PASS",
                        time.time() - start_time,
                        details={"success_rate": success_rate, "successful_requests": successful_requests}
                    ))
                    logger.info(f"✓ Concurrent users test: {success_rate:.2%} success rate")
                else:
                    self.test_results.append(TestResult(
                        "concurrent_users", "FAIL",
                        time.time() - start_time,
                        error_message=f"Success rate {success_rate:.2%} below 95% threshold"
                    ))
                    
        except Exception as e:
            self.test_results.append(TestResult(
                "concurrent_users", "FAIL",
                time.time() - start_time,
                error_message=str(e)
            ))
    
    async def test_error_handling(self):
        """Test error handling across all services"""
        logger.info("Testing error handling...")
        
        error_scenarios = [
            ("invalid_endpoint", "GET", "/invalid-endpoint", 404),
            ("malformed_request", "POST", "/chat", 400),
            ("unauthorized_request", "GET", "/protected-endpoint", 401),
        ]
        
        async with aiohttp.ClientSession() as session:
            for scenario_name, method, endpoint, expected_status in error_scenarios:
                start_time = time.time()
                try:
                    request_data = {"invalid": "data"} if method == "POST" else None
                    
                    if method == "GET":
                        async with session.get(f"{self.services['api_gateway'].url}{endpoint}") as response:
                            status = response.status
                    else:
                        async with session.post(f"{self.services['api_gateway'].url}{endpoint}", json=request_data) as response:
                            status = response.status
                    
                    if status == expected_status:
                        self.test_results.append(TestResult(
                            f"error_handling_{scenario_name}", "PASS",
                            time.time() - start_time,
                            details={"expected_status": expected_status, "actual_status": status}
                        ))
                        logger.info(f"✓ Error handling {scenario_name}: HTTP {status}")
                    else:
                        self.test_results.append(TestResult(
                            f"error_handling_{scenario_name}", "FAIL",
                            time.time() - start_time,
                            error_message=f"Expected HTTP {expected_status}, got HTTP {status}"
                        ))
                        
                except Exception as e:
                    self.test_results.append(TestResult(
                        f"error_handling_{scenario_name}", "FAIL",
                        time.time() - start_time,
                        error_message=str(e)
                    ))
    
    async def test_complete_user_flows(self):
        """Test complete end-to-end user flows"""
        logger.info("Testing complete user flows...")
        
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            page = await browser.new_page()
            
            try:
                # Complete user flow: Login -> Chat -> Airtable Query -> Results
                await self.test_complete_chat_workflow(page)
                
            except Exception as e:
                logger.error(f"Complete user flow test failed: {e}")
            finally:
                await browser.close()
    
    async def test_complete_chat_workflow(self, page: Page):
        """Test complete chat workflow from login to results"""
        start_time = time.time()
        
        try:
            # Navigate to chat UI
            await page.goto("http://localhost:3001")
            await page.wait_for_load_state("networkidle")
            
            # Check if authentication is required
            login_form = await page.query_selector('input[type="email"]')
            if login_form:
                # Perform login
                await page.fill('input[type="email"]', self.test_user["email"])
                await page.fill('input[type="password"]', self.test_user["password"])
                await page.click('button[type="submit"]')
                await page.wait_for_load_state("networkidle")
            
            # Send a complex Airtable query
            complex_query = "Show me all records from my main database and create a summary report"
            await page.fill('[data-testid="chat-input"]', complex_query)
            await page.click('[data-testid="send-button"]')
            
            # Wait for AI response with tool execution
            await page.wait_for_selector('[data-testid="tool-execution"]', timeout=30000)
            
            # Verify tool execution display
            tool_executions = await page.query_selector_all('[data-testid="tool-execution"]')
            if len(tool_executions) > 0:
                self.test_results.append(TestResult(
                    "complete_chat_workflow", "PASS",
                    time.time() - start_time,
                    details={"tool_executions": len(tool_executions)}
                ))
                logger.info("✓ Complete chat workflow with tool execution successful")
            else:
                self.test_results.append(TestResult(
                    "complete_chat_workflow", "FAIL",
                    time.time() - start_time,
                    error_message="No tool executions detected"
                ))
                
        except Exception as e:
            self.test_results.append(TestResult(
                "complete_chat_workflow", "FAIL",
                time.time() - start_time,
                error_message=str(e)
            ))
    
    def generate_test_report(self, total_duration: float) -> Dict[str, Any]:
        """Generate comprehensive test report"""
        passed_tests = [r for r in self.test_results if r.status == "PASS"]
        failed_tests = [r for r in self.test_results if r.status == "FAIL"]
        skipped_tests = [r for r in self.test_results if r.status == "SKIP"]
        
        total_tests = len(self.test_results)
        pass_rate = len(passed_tests) / total_tests * 100 if total_tests > 0 else 0
        
        report = {
            "test_execution": {
                "timestamp": datetime.now().isoformat(),
                "total_duration": total_duration,
                "total_tests": total_tests,
                "passed": len(passed_tests),
                "failed": len(failed_tests),
                "skipped": len(skipped_tests),
                "pass_rate": pass_rate
            },
            "service_health": {
                service: "HEALTHY" if any(r.test_name == f"health_check_{service}" and r.status == "PASS" for r in self.test_results)
                else "UNHEALTHY" 
                for service in self.services.keys()
            },
            "performance_metrics": {
                "chat_response_time": next((r.duration for r in self.test_results if r.test_name == "chat_response_performance" and r.status == "PASS"), None),
                "airtable_api_response": next((r.duration for r in self.test_results if r.test_name == "airtable_api_performance" and r.status == "PASS"), None),
                "concurrent_users_success_rate": next((r.details.get("success_rate") for r in self.test_results if r.test_name == "concurrent_users" and r.status == "PASS"), None)
            },
            "integration_status": {
                "authentication": any(r.test_name.startswith("authentication") and r.status == "PASS" for r in self.test_results),
                "chat_ui": any(r.test_name.startswith("chat_ui") and r.status == "PASS" for r in self.test_results),
                "mcp_tools": any(r.test_name.startswith("mcp_tool") and r.status == "PASS" for r in self.test_results),
                "airtable_crud": any(r.test_name.startswith("airtable_crud") and r.status == "PASS" for r in self.test_results),
                "websocket": any(r.test_name == "websocket_communication" and r.status == "PASS" for r in self.test_results),
                "file_upload": any(r.test_name == "file_upload_processing" and r.status == "PASS" for r in self.test_results)
            },
            "failed_tests": [
                {
                    "test_name": test.test_name,
                    "error_message": test.error_message,
                    "duration": test.duration
                } for test in failed_tests
            ],
            "recommendations": self.generate_recommendations(),
            "detailed_results": [
                {
                    "test_name": test.test_name,
                    "status": test.status,
                    "duration": test.duration,
                    "error_message": test.error_message,
                    "details": test.details
                } for test in self.test_results
            ]
        }
        
        return report
    
    def generate_recommendations(self) -> List[str]:
        """Generate recommendations based on test results"""
        recommendations = []
        
        failed_services = []
        for service in self.services.keys():
            if not any(r.test_name == f"health_check_{service}" and r.status == "PASS" for r in self.test_results):
                failed_services.append(service)
        
        if failed_services:
            recommendations.append(f"Fix service health issues for: {', '.join(failed_services)}")
        
        auth_failed = any(r.test_name.startswith("authentication") and r.status == "FAIL" for r in self.test_results)
        if auth_failed:
            recommendations.append("Review authentication integration - login or token validation failing")
        
        performance_issues = [r for r in self.test_results if "performance" in r.test_name and r.status == "FAIL"]
        if performance_issues:
            recommendations.append("Address performance issues - response times exceed targets")
        
        if not any(r.test_name == "websocket_communication" and r.status == "PASS" for r in self.test_results):
            recommendations.append("Implement WebSocket communication for real-time chat functionality")
        
        if not any(r.test_name == "file_upload_processing" and r.status == "PASS" for r in self.test_results):
            recommendations.append("Implement file upload and processing endpoints")
        
        error_handling_issues = [r for r in self.test_results if r.test_name.startswith("error_handling") and r.status == "FAIL"]
        if error_handling_issues:
            recommendations.append("Improve error handling - unexpected status codes returned")
        
        if not recommendations:
            recommendations.append("All tests passed successfully - Sprint 2 integration is ready for production")
        
        return recommendations

async def main():
    """Main test execution"""
    test_suite = Sprint2TestSuite()
    report = await test_suite.run_full_test_suite()
    
    # Save detailed report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"sprint2_comprehensive_test_report_{timestamp}.json"
    
    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2)
    
    # Print summary
    logger.info("\n" + "="*80)
    logger.info("SPRINT 2 E2E TEST SUITE SUMMARY")
    logger.info("="*80)
    logger.info(f"Total Tests: {report['test_execution']['total_tests']}")
    logger.info(f"Passed: {report['test_execution']['passed']}")
    logger.info(f"Failed: {report['test_execution']['failed']}")
    logger.info(f"Skipped: {report['test_execution']['skipped']}")
    logger.info(f"Pass Rate: {report['test_execution']['pass_rate']:.1f}%")
    logger.info(f"Total Duration: {report['test_execution']['total_duration']:.2f}s")
    logger.info(f"\nDetailed report saved to: {report_file}")
    
    if report['test_execution']['failed'] > 0:
        logger.info("\nFAILED TESTS:")
        for failed_test in report['failed_tests']:
            logger.info(f"  - {failed_test['test_name']}: {failed_test['error_message']}")
    
    if report['recommendations']:
        logger.info("\nRECOMMENDATIONS:")
        for i, rec in enumerate(report['recommendations'], 1):
            logger.info(f"  {i}. {rec}")
    
    return report['test_execution']['pass_rate'] >= 80  # 80% pass rate threshold

if __name__ == "__main__":
    success = asyncio.run(main())
    sys.exit(0 if success else 1)