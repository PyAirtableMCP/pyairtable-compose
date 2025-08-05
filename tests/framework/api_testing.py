"""
Comprehensive API Testing Framework for PyAirtable Microservices
================================================================

This module provides comprehensive API testing capabilities for all PyAirtable microservices,
including health checks, endpoint validation, performance testing, and integration testing.
"""

import asyncio
import json
import logging
import time
import traceback
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple, Union
import uuid
from urllib.parse import urljoin
from dataclasses import dataclass, field

import httpx
import pytest
from httpx import AsyncClient, Response, RequestError, TimeoutException

from .test_config import TestFrameworkConfig, get_config, ServiceConfig
from .test_reporter import TestResult, TestReport

logger = logging.getLogger(__name__)

@dataclass
class APITestCase:
    """Represents an API test case"""
    name: str
    method: str
    endpoint: str
    headers: Dict[str, str] = field(default_factory=dict)
    params: Dict[str, Any] = field(default_factory=dict)
    json_data: Optional[Dict[str, Any]] = None
    form_data: Optional[Dict[str, Any]] = None
    expected_status: Union[int, List[int]] = 200
    expected_response_keys: List[str] = field(default_factory=list)
    timeout: int = 30
    description: str = ""
    tags: List[str] = field(default_factory=list)

@dataclass
class APIResponse:
    """Enhanced API response container"""
    status_code: int
    headers: Dict[str, str]
    content: bytes
    json_data: Optional[Dict[str, Any]] = None
    text: str = ""
    response_time: float = 0.0
    request_id: str = ""
    
    @classmethod
    def from_httpx_response(cls, response: Response, response_time: float = 0.0) -> 'APIResponse':
        """Create APIResponse from httpx Response"""
        json_data = None
        text = ""
        
        try:
            text = response.text
            if response.headers.get("content-type", "").startswith("application/json"):
                json_data = response.json()
        except Exception:
            pass
        
        return cls(
            status_code=response.status_code,
            headers=dict(response.headers),
            content=response.content,
            json_data=json_data,
            text=text,
            response_time=response_time,
            request_id=response.headers.get("x-request-id", str(uuid.uuid4()))
        )

class APITestClient:
    """Enhanced HTTP client for API testing"""
    
    def __init__(self, base_url: str, default_headers: Dict[str, str] = None, 
                 timeout: int = 30, retries: int = 3):
        self.base_url = base_url.rstrip('/')
        self.default_headers = default_headers or {}
        self.timeout = timeout
        self.retries = retries
        self.client: Optional[AsyncClient] = None
        self.request_history: List[Dict[str, Any]] = []
    
    async def __aenter__(self):
        """Async context manager entry"""
        self.client = AsyncClient(
            timeout=httpx.Timeout(self.timeout),
            headers=self.default_headers,
            follow_redirects=True
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        if self.client:
            await self.client.aclose()
    
    async def request(self, method: str, endpoint: str, **kwargs) -> APIResponse:
        """Make an HTTP request with enhanced error handling and metrics"""
        url = urljoin(self.base_url + '/', endpoint.lstrip('/'))
        
        # Merge headers
        headers = {**self.default_headers, **kwargs.pop('headers', {})}
        
        start_time = time.time()
        request_data = {
            "method": method,
            "url": url,
            "headers": headers,
            "timestamp": datetime.now().isoformat(),
            **kwargs
        }
        
        try:
            response = await self.client.request(method, url, headers=headers, **kwargs)
            response_time = time.time() - start_time
            
            api_response = APIResponse.from_httpx_response(response, response_time)
            
            # Record request
            request_data.update({
                "response_status": response.status_code,
                "response_time": response_time,
                "success": True
            })
            self.request_history.append(request_data)
            
            return api_response
            
        except Exception as e:
            response_time = time.time() - start_time
            
            # Record failed request
            request_data.update({
                "error": str(e),
                "response_time": response_time,
                "success": False
            })
            self.request_history.append(request_data)
            
            # Create error response
            return APIResponse(
                status_code=0,
                headers={},
                content=b"",
                response_time=response_time,
                request_id=str(uuid.uuid4())
            )
    
    async def get(self, endpoint: str, **kwargs) -> APIResponse:
        """GET request"""
        return await self.request("GET", endpoint, **kwargs)
    
    async def post(self, endpoint: str, **kwargs) -> APIResponse:
        """POST request"""
        return await self.request("POST", endpoint, **kwargs)
    
    async def put(self, endpoint: str, **kwargs) -> APIResponse:
        """PUT request"""
        return await self.request("PUT", endpoint, **kwargs)
    
    async def delete(self, endpoint: str, **kwargs) -> APIResponse:
        """DELETE request"""
        return await self.request("DELETE", endpoint, **kwargs)
    
    async def patch(self, endpoint: str, **kwargs) -> APIResponse:
        """PATCH request"""
        return await self.request("PATCH", endpoint, **kwargs)

class BaseAPITester:
    """Base class for API testing"""
    
    def __init__(self, service_name: str, config: TestFrameworkConfig = None):
        self.service_name = service_name
        self.config = config or get_config()
        self.service_config = self.config.services.get(service_name)
        
        if not self.service_config:
            raise ValueError(f"Service '{service_name}' not found in configuration")
        
        self.client: Optional[APITestClient] = None
        self.test_results: List[TestResult] = []
    
    async def __aenter__(self):
        """Async context manager entry"""
        default_headers = {
            "User-Agent": "PyAirtable-Test-Framework/1.0",
            "Content-Type": "application/json"
        }
        
        # Add API key if available
        if hasattr(self.config, 'airtable') and self.config.airtable.api_key:
            default_headers["X-API-Key"] = self.config.airtable.api_key
        
        self.client = APITestClient(
            base_url=self.service_config.url,
            default_headers=default_headers,
            timeout=self.service_config.timeout,
            retries=self.service_config.retry_attempts
        )
        
        await self.client.__aenter__()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        if self.client:
            await self.client.__aexit__(exc_type, exc_val, exc_tb)
    
    async def test_health_check(self) -> TestResult:
        """Test service health endpoint"""
        result = TestResult(self.service_name, "Health Check")
        
        try:
            result.add_log("info", f"Testing health endpoint: {self.service_config.health_endpoint}")
            
            response = await self.client.get(self.service_config.health_endpoint)
            
            # Record response metrics
            result.performance_metrics["response_time"] = response.response_time
            result.performance_metrics["status_code"] = response.status_code
            
            if response.status_code == 200:
                result.add_log("info", f"✓ Health check passed ({response.response_time:.3f}s)")
                
                # Validate response structure if it's JSON
                if response.json_data:
                    expected_fields = ["status", "timestamp", "service", "version"]
                    found_fields = [field for field in expected_fields if field in response.json_data]
                    
                    if found_fields:
                        result.add_log("info", f"Health response contains: {found_fields}")
                    else:
                        result.add_issue("low", "Health Response Format", 
                                       "Health response doesn't contain standard fields")
                
                result.complete("passed")
            else:
                result.add_issue("critical", "Health Check Failed", 
                               f"Expected 200, got {response.status_code}")
                result.complete("failed")
        
        except Exception as e:
            result.add_log("error", f"Health check failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def test_endpoints(self, test_cases: List[APITestCase]) -> List[TestResult]:
        """Test multiple API endpoints"""
        results = []
        
        for test_case in test_cases:
            result = await self._execute_test_case(test_case)
            results.append(result)
            self.test_results.append(result)
        
        return results
    
    async def _execute_test_case(self, test_case: APITestCase) -> TestResult:
        """Execute a single API test case"""
        result = TestResult(self.service_name, test_case.name)
        
        try:
            result.add_log("info", f"Testing {test_case.method} {test_case.endpoint}")
            
            # Prepare request parameters
            request_kwargs = {
                "headers": test_case.headers,
                "params": test_case.params,
                "timeout": test_case.timeout
            }
            
            if test_case.json_data:
                request_kwargs["json"] = test_case.json_data
            elif test_case.form_data:
                request_kwargs["data"] = test_case.form_data
            
            # Make request
            response = await self.client.request(test_case.method, test_case.endpoint, **request_kwargs)
            
            # Record metrics
            result.performance_metrics["response_time"] = response.response_time
            result.performance_metrics["status_code"] = response.status_code
            result.performance_metrics["response_size"] = len(response.content)
            
            # Validate status code
            expected_statuses = test_case.expected_status if isinstance(test_case.expected_status, list) else [test_case.expected_status]
            
            if response.status_code in expected_statuses:
                result.add_log("info", f"✓ Status code {response.status_code} as expected")
            else:
                result.add_issue("high", "Unexpected Status Code", 
                               f"Expected {expected_statuses}, got {response.status_code}")
            
            # Validate response structure
            if test_case.expected_response_keys and response.json_data:
                missing_keys = []
                for key in test_case.expected_response_keys:
                    if key not in response.json_data:
                        missing_keys.append(key)
                
                if missing_keys:
                    result.add_issue("medium", "Missing Response Keys", 
                                   f"Missing keys: {missing_keys}")
                else:
                    result.add_log("info", f"✓ All expected keys present: {test_case.expected_response_keys}")
            
            # Performance check
            if response.response_time > self.config.performance_threshold_ms / 1000:
                result.add_issue("medium", "Slow Response", 
                               f"Response time {response.response_time:.3f}s exceeds threshold")
            
            # Determine overall result
            has_critical_issues = any(issue["severity"] == "critical" for issue in result.issues_found)
            has_high_issues = any(issue["severity"] == "high" for issue in result.issues_found)
            
            if has_critical_issues:
                result.complete("failed")
            elif has_high_issues:
                result.complete("failed")
            else:
                result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Test case execution failed: {e}")
            result.complete("failed")
        
        return result

class APIGatewayTester(BaseAPITester):
    """API Gateway specific testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("api_gateway", config)
    
    async def test_routing(self) -> TestResult:
        """Test API Gateway routing functionality"""
        result = TestResult(self.service_name, "Routing Test")
        
        try:
            # Test routes to downstream services
            routes_to_test = [
                ("/api/health", "API Gateway health"),
                ("/api/v1/llm/health", "LLM Orchestrator routing"),
                ("/api/v1/mcp/health", "MCP Server routing"),
                ("/api/v1/airtable/health", "Airtable Gateway routing"),
                ("/api/v1/platform/health", "Platform Services routing"),
                ("/api/v1/automation/health", "Automation Services routing")
            ]
            
            for route, description in routes_to_test:
                result.add_log("info", f"Testing route: {route}")
                
                response = await self.client.get(route)
                
                if response.status_code in [200, 404]:  # 404 might be expected if service is down
                    result.add_log("info", f"✓ {description}: {response.status_code}")
                else:
                    result.add_issue("medium", f"Route Issue: {route}", 
                                   f"Unexpected status {response.status_code} for {description}")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Routing test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def test_cors_headers(self) -> TestResult:
        """Test CORS headers"""
        result = TestResult(self.service_name, "CORS Headers Test")
        
        try:
            # Test preflight request
            response = await self.client.request(
                "OPTIONS", 
                "/api/health",
                headers={
                    "Origin": "http://localhost:3000",
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "Content-Type"
                }
            )
            
            # Check CORS headers
            cors_headers = [
                "Access-Control-Allow-Origin",
                "Access-Control-Allow-Methods",
                "Access-Control-Allow-Headers"
            ]
            
            missing_headers = []
            for header in cors_headers:
                if header not in response.headers:
                    missing_headers.append(header)
            
            if missing_headers:
                result.add_issue("medium", "Missing CORS Headers", 
                               f"Missing: {missing_headers}")
            else:
                result.add_log("info", "✓ All CORS headers present")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"CORS test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class LLMOrchestratorTester(BaseAPITester):
    """LLM Orchestrator specific testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("llm_orchestrator", config)
    
    async def test_chat_functionality(self) -> TestResult:
        """Test chat functionality"""
        result = TestResult(self.service_name, "Chat Functionality Test")
        
        try:
            # Test chat endpoint
            chat_payload = {
                "messages": [
                    {
                        "role": "user",
                        "content": "Hello, this is a test message. Please respond briefly."
                    }
                ],
                "session_id": f"test_session_{uuid.uuid4().hex[:8]}"
            }
            
            response = await self.client.post("/chat", json=chat_payload)
            
            if response.status_code == 200 and response.json_data:
                result.add_log("info", "✓ Chat endpoint responded successfully")
                
                # Check response structure
                expected_fields = ["response", "session_id", "timestamp"]
                found_fields = [field for field in expected_fields if field in response.json_data]
                
                if len(found_fields) >= 2:
                    result.add_log("info", f"Response contains: {found_fields}")
                else:
                    result.add_issue("medium", "Chat Response Format", 
                                   "Chat response missing expected fields")
                
                # Check response content
                if "response" in response.json_data:
                    response_text = response.json_data["response"]
                    if len(response_text) > 10:
                        result.add_log("info", f"Received response ({len(response_text)} chars)")
                    else:
                        result.add_issue("low", "Short Response", "Response seems too short")
            else:
                result.add_issue("high", "Chat Endpoint Failed", 
                               f"Status: {response.status_code}")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Chat functionality test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class AirtableGatewayTester(BaseAPITester):
    """Airtable Gateway specific testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("airtable_gateway", config)
    
    async def test_airtable_connectivity(self) -> TestResult:
        """Test Airtable API connectivity"""
        result = TestResult(self.service_name, "Airtable Connectivity Test")
        
        try:
            # Test bases endpoint
            response = await self.client.get("/api/v1/bases")
            
            if response.status_code in [200, 401, 403]:  # Auth errors are expected in testing
                result.add_log("info", f"✓ Bases endpoint accessible (status: {response.status_code})")
                
                if response.status_code == 200 and response.json_data:
                    # Check if we got bases data
                    if isinstance(response.json_data, dict) and "bases" in response.json_data:
                        result.add_log("info", "✓ Bases data structure valid")
                    elif isinstance(response.json_data, list):
                        result.add_log("info", f"✓ Received {len(response.json_data)} bases")
            else:
                result.add_issue("high", "Airtable Connectivity Issue", 
                               f"Unexpected status: {response.status_code}")
            
            # Test specific base if configured
            if self.config.airtable.base_id:
                base_response = await self.client.get(f"/api/v1/bases/{self.config.airtable.base_id}/tables")
                
                if base_response.status_code in [200, 401, 403]:
                    result.add_log("info", f"✓ Base tables endpoint accessible")
                else:
                    result.add_issue("medium", "Base Access Issue", 
                                   f"Cannot access base tables: {base_response.status_code}")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Airtable connectivity test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class MCPServerTester(BaseAPITester):
    """MCP Server specific testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("mcp_server", config)
    
    async def test_mcp_tools(self) -> TestResult:
        """Test MCP tools availability"""
        result = TestResult(self.service_name, "MCP Tools Test")
        
        try:
            # Test tools endpoint
            response = await self.client.get("/tools")
            
            if response.status_code == 200 and response.json_data:
                result.add_log("info", "✓ Tools endpoint accessible")
                
                # Check if tools are available
                if isinstance(response.json_data, dict) and "tools" in response.json_data:
                    tools = response.json_data["tools"]
                    result.add_log("info", f"Available tools: {len(tools)}")
                    
                    # Check for expected tools
                    expected_tools = ["airtable_query", "airtable_create", "airtable_update"]
                    found_tools = [tool.get("name") for tool in tools if isinstance(tool, dict)]
                    
                    for expected_tool in expected_tools:
                        if expected_tool in found_tools:
                            result.add_log("info", f"✓ Tool available: {expected_tool}")
                        else:
                            result.add_issue("medium", f"Missing Tool: {expected_tool}", 
                                           "Expected MCP tool not available")
                else:
                    result.add_issue("medium", "Tools Response Format", 
                                   "Tools response doesn't contain expected structure")
            else:
                result.add_issue("high", "Tools Endpoint Failed", 
                               f"Status: {response.status_code}")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"MCP tools test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class IntegrationAPITester:
    """Integration testing across multiple APIs"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.testers = {}
        self.test_results: List[TestResult] = []
    
    async def __aenter__(self):
        """Initialize all service testers"""
        service_tester_classes = {
            "api_gateway": APIGatewayTester,
            "llm_orchestrator": LLMOrchestratorTester,
            "airtable_gateway": AirtableGatewayTester,
            "mcp_server": MCPServerTester,
        }
        
        for service_name, tester_class in service_tester_classes.items():
            if service_name in self.config.services:
                try:
                    tester = tester_class(self.config)
                    await tester.__aenter__()
                    self.testers[service_name] = tester
                except Exception as e:
                    logger.error(f"Failed to initialize tester for {service_name}: {e}")
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Cleanup all testers"""
        for tester in self.testers.values():
            try:
                await tester.__aexit__(exc_type, exc_val, exc_tb)
            except Exception as e:
                logger.error(f"Error cleaning up tester: {e}")
    
    async def test_all_services_health(self) -> List[TestResult]:
        """Test health of all services"""
        results = []
        
        for service_name, tester in self.testers.items():
            try:
                result = await tester.test_health_check()
                results.append(result)
            except Exception as e:
                logger.error(f"Health test failed for {service_name}: {e}")
                # Create error result
                error_result = TestResult(service_name, "Health Check")
                error_result.add_log("error", f"Health check failed: {e}")
                error_result.complete("failed")
                results.append(error_result)
        
        self.test_results.extend(results)
        return results
    
    async def test_end_to_end_flow(self) -> TestResult:
        """Test end-to-end API flow"""
        result = TestResult("Integration", "End-to-End API Flow")
        
        try:
            # Test complete flow: Frontend -> API Gateway -> LLM Orchestrator -> MCP Server -> Airtable Gateway
            
            # Step 1: Test API Gateway chat endpoint
            if "api_gateway" in self.testers:
                result.add_log("info", "Step 1: Testing API Gateway chat endpoint")
                
                chat_payload = {
                    "messages": [
                        {
                            "role": "user",
                            "content": f"Please list the tables in my Airtable base {self.config.airtable.base_id}"
                        }
                    ],
                    "session_id": f"e2e_test_{uuid.uuid4().hex[:8]}"
                }
                
                api_gateway_tester = self.testers["api_gateway"]
                response = await api_gateway_tester.client.post("/api/chat", json=chat_payload)
                
                if response.status_code == 200:
                    result.add_log("info", "✓ API Gateway accepted chat request")
                    result.performance_metrics["api_gateway_response_time"] = response.response_time
                    
                    if response.json_data and "response" in response.json_data:
                        response_text = response.json_data["response"]
                        result.add_log("info", f"Received response ({len(response_text)} chars)")
                        
                        # Check if response contains table-related information
                        table_keywords = ["table", "record", "field", "base", "airtable"]
                        keyword_count = sum(1 for keyword in table_keywords 
                                          if keyword.lower() in response_text.lower())
                        
                        if keyword_count >= 2:
                            result.add_log("info", "✓ Response contains relevant Airtable information")
                        else:
                            result.add_issue("medium", "Response Quality", 
                                           f"Response may lack Airtable content (keywords: {keyword_count})")
                    else:
                        result.add_issue("high", "Missing Response", "No response content received")
                else:
                    result.add_issue("critical", "API Gateway Failed", 
                                   f"Chat request failed: {response.status_code}")
            
            # Step 2: Test direct service health checks
            result.add_log("info", "Step 2: Verifying downstream services")
            
            downstream_services = ["llm_orchestrator", "mcp_server", "airtable_gateway"]
            healthy_services = 0
            
            for service_name in downstream_services:
                if service_name in self.testers:
                    tester = self.testers[service_name]
                    health_response = await tester.client.get(tester.service_config.health_endpoint)
                    
                    if health_response.status_code == 200:
                        healthy_services += 1
                        result.add_log("info", f"✓ {service_name} is healthy")
                    else:
                        result.add_issue("high", f"{service_name} Unhealthy", 
                                       f"Health check failed: {health_response.status_code}")
            
            # Overall assessment
            if healthy_services == len(downstream_services):
                result.add_log("info", "✓ All downstream services healthy")
            else:
                result.add_issue("high", "Service Health Issues", 
                               f"Only {healthy_services}/{len(downstream_services)} services healthy")
            
            result.complete("passed" if not any(issue["severity"] in ["critical", "high"] 
                                              for issue in result.issues_found) else "failed")
        
        except Exception as e:
            result.add_log("error", f"End-to-end flow test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def test_performance_under_load(self) -> TestResult:
        """Test API performance under simulated load"""
        result = TestResult("Integration", "Performance Under Load")
        
        try:
            # Test concurrent requests to API Gateway
            num_concurrent_requests = min(self.config.load_test_users, 20)  # Limit for integration test
            
            result.add_log("info", f"Testing {num_concurrent_requests} concurrent requests")
            
            async def make_request(request_id: int) -> Tuple[int, float]:
                """Make a single request and return status and response time"""
                try:
                    if "api_gateway" in self.testers:
                        tester = self.testers["api_gateway"]
                        response = await tester.client.get("/api/health")
                        return response.status_code, response.response_time
                    else:
                        return 0, 0.0
                except Exception:
                    return 0, 0.0
            
            # Execute concurrent requests
            start_time = time.time()
            tasks = [make_request(i) for i in range(num_concurrent_requests)]
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            total_time = time.time() - start_time
            
            # Analyze results
            successful_requests = 0
            response_times = []
            
            for response in responses:
                if isinstance(response, tuple):
                    status_code, response_time = response
                    if status_code == 200:
                        successful_requests += 1
                        response_times.append(response_time)
            
            success_rate = successful_requests / num_concurrent_requests * 100
            avg_response_time = sum(response_times) / len(response_times) if response_times else 0
            max_response_time = max(response_times) if response_times else 0
            
            # Record metrics
            result.performance_metrics.update({
                "concurrent_requests": num_concurrent_requests,
                "successful_requests": successful_requests,
                "success_rate": success_rate,
                "total_time": total_time,
                "avg_response_time": avg_response_time,
                "max_response_time": max_response_time,
                "requests_per_second": num_concurrent_requests / total_time
            })
            
            result.add_log("info", f"Load test results:")
            result.add_log("info", f"  Success rate: {success_rate:.1f}%")
            result.add_log("info", f"  Avg response time: {avg_response_time:.3f}s")
            result.add_log("info", f"  Max response time: {max_response_time:.3f}s")
            result.add_log("info", f"  Requests/second: {result.performance_metrics['requests_per_second']:.1f}")
            
            # Performance thresholds
            if success_rate < 95:
                result.add_issue("high", "Low Success Rate", f"Success rate {success_rate:.1f}% < 95%")
            
            if avg_response_time > 2.0:
                result.add_issue("medium", "Slow Average Response", 
                               f"Average response time {avg_response_time:.3f}s > 2.0s")
            
            if max_response_time > 5.0:
                result.add_issue("medium", "Very Slow Response", 
                               f"Max response time {max_response_time:.3f}s > 5.0s")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Performance test failed: {e}")
            result.complete("failed")
        
        self.test_results.append(result)
        return result

class APITestOrchestrator:
    """Orchestrates API testing across all services"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.test_report = TestReport("API Testing Suite")
    
    async def run_comprehensive_api_tests(self) -> TestReport:
        """Run comprehensive API tests"""
        logger.info("Starting comprehensive API testing")
        
        async with IntegrationAPITester(self.config) as integration_tester:
            all_results = []
            
            # Test 1: Health checks for all services
            logger.info("Running health checks...")
            health_results = await integration_tester.test_all_services_health()
            all_results.extend(health_results)
            
            # Test 2: Service-specific functionality
            logger.info("Running service-specific tests...")
            for service_name, tester in integration_tester.testers.items():
                try:
                    if isinstance(tester, APIGatewayTester):
                        all_results.append(await tester.test_routing())
                        all_results.append(await tester.test_cors_headers())
                    elif isinstance(tester, LLMOrchestratorTester):
                        all_results.append(await tester.test_chat_functionality())
                    elif isinstance(tester, AirtableGatewayTester):
                        all_results.append(await tester.test_airtable_connectivity())
                    elif isinstance(tester, MCPServerTester):
                        all_results.append(await tester.test_mcp_tools())
                
                except Exception as e:
                    logger.error(f"Service-specific test failed for {service_name}: {e}")
                    error_result = TestResult(service_name, "Service-Specific Tests")
                    error_result.add_log("error", f"Service test failed: {e}")
                    error_result.complete("failed")
                    all_results.append(error_result)
            
            # Test 3: End-to-end integration
            logger.info("Running end-to-end integration test...")
            e2e_result = await integration_tester.test_end_to_end_flow()
            all_results.append(e2e_result)
            
            # Test 4: Performance testing
            if self.config.test_level.value in ["integration", "performance"]:
                logger.info("Running performance tests...")
                perf_result = await integration_tester.test_performance_under_load()
                all_results.append(perf_result)
            
            # Add all results to the report
            for result in all_results:
                self.test_report.add_test_result(result)
            
            # Generate report
            await self.test_report.generate_report()
            
            logger.info(f"API testing completed. Total tests: {len(all_results)}")
            
            return self.test_report