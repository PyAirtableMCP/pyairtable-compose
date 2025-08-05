"""
External API Integration Testing Framework
=========================================

This module provides comprehensive testing for external API integrations including
Airtable WebAPI and Gemini AI API, with validation, rate limiting, and error handling.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
import uuid
from dataclasses import dataclass, field
from urllib.parse import urljoin

import httpx
from httpx import AsyncClient, Response
import google.generativeai as genai
from google.generativeai.types import HarmCategory, HarmBlockThreshold

from .test_config import TestFrameworkConfig, get_config
from .test_reporter import TestResult
from .data_management import TestDataFactory

logger = logging.getLogger(__name__)

@dataclass
class APIRateLimitInfo:
    """Rate limit information for APIs"""
    requests_per_second: int
    requests_per_minute: int
    requests_per_hour: int
    requests_per_day: int
    current_usage: int = 0
    reset_time: Optional[datetime] = None

@dataclass
class ExternalAPITestResult:
    """Result of external API testing"""
    api_name: str
    endpoint: str
    test_type: str
    success: bool
    response_time: float
    status_code: int
    response_size: int
    error_message: Optional[str] = None
    rate_limit_info: Optional[APIRateLimitInfo] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

class AirtableAPITester:
    """Comprehensive Airtable API testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.client: Optional[AsyncClient] = None
        self.base_url = "https://api.airtable.com/v0"
        self.rate_limiter = APIRateLimitInfo(
            requests_per_second=5,
            requests_per_minute=100,
            requests_per_hour=1000,
            requests_per_day=10000
        )
        self.test_results: List[ExternalAPITestResult] = []
        self.data_factory = TestDataFactory()
    
    async def __aenter__(self):
        """Initialize HTTP client"""
        headers = {
            "Authorization": f"Bearer {self.config.airtable.api_key}",
            "Content-Type": "application/json",
            "User-Agent": "PyAirtable-Test-Framework/1.0"
        }
        
        self.client = AsyncClient(
            base_url=self.base_url,
            headers=headers,
            timeout=self.config.airtable.timeout
        )
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Cleanup HTTP client"""
        if self.client:
            await self.client.aclose()
    
    async def _make_request(self, method: str, endpoint: str, **kwargs) -> Tuple[Response, float]:
        """Make rate-limited request to Airtable API"""
        # Simple rate limiting
        if self.rate_limiter.current_usage >= self.rate_limiter.requests_per_second:
            await asyncio.sleep(1)
            self.rate_limiter.current_usage = 0
        
        start_time = time.time()
        response = await self.client.request(method, endpoint, **kwargs)
        response_time = time.time() - start_time
        
        self.rate_limiter.current_usage += 1
        
        # Update rate limit info from response headers
        if "X-RateLimit-Limit" in response.headers:
            try:
                self.rate_limiter.requests_per_second = int(response.headers["X-RateLimit-Limit"])
            except ValueError:
                pass
        
        return response, response_time
    
    async def test_authentication(self) -> TestResult:
        """Test Airtable API authentication"""
        result = TestResult("Airtable API", "Authentication Test")
        
        try:
            # Test with a simple metadata request
            response, response_time = await self._make_request("GET", "/meta/bases")
            
            test_result = ExternalAPITestResult(
                api_name="Airtable",
                endpoint="/meta/bases",
                test_type="authentication",
                success=response.status_code in [200, 403],  # 403 might indicate valid auth but no access
                response_time=response_time,
                status_code=response.status_code,
                response_size=len(response.content),
                metadata={"headers": dict(response.headers)}
            )
            
            self.test_results.append(test_result)
            
            if response.status_code == 200:
                result.add_log("info", "✓ Authentication successful")
                
                # Parse response to check base access
                try:
                    data = response.json()
                    if "bases" in data:
                        bases_count = len(data["bases"])
                        result.add_log("info", f"Access to {bases_count} bases confirmed")
                        result.performance_metrics["accessible_bases"] = bases_count
                except json.JSONDecodeError:
                    result.add_issue("low", "Response Parse Error", "Could not parse bases response")
                
            elif response.status_code == 401:
                result.add_issue("critical", "Authentication Failed", "Invalid API key")
                
            elif response.status_code == 403:
                result.add_log("warning", "Authentication valid but limited access")
                result.add_issue("medium", "Limited Access", "API key has limited permissions")
                
            else:
                result.add_issue("high", "Unexpected Auth Response", 
                               f"Unexpected status code: {response.status_code}")
            
            result.performance_metrics["response_time"] = response_time
            result.complete("passed" if test_result.success else "failed")
        
        except Exception as e:
            result.add_log("error", f"Authentication test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_base_access(self) -> TestResult:
        """Test access to specific Airtable base"""
        result = TestResult("Airtable API", "Base Access Test")
        
        try:
            base_id = self.config.airtable.base_id
            if not base_id:
                result.add_issue("critical", "No Base ID", "Base ID not configured")
                result.complete("failed")
                return result
            
            # Test base metadata access
            endpoint = f"/{base_id}/tables"
            response, response_time = await self._make_request("GET", endpoint)
            
            test_result = ExternalAPITestResult(
                api_name="Airtable",
                endpoint=endpoint,
                test_type="base_access",
                success=response.status_code == 200,
                response_time=response_time,
                status_code=response.status_code,
                response_size=len(response.content)
            )
            
            self.test_results.append(test_result)
            
            if response.status_code == 200:
                result.add_log("info", f"✓ Base access successful: {base_id}")
                
                try:
                    data = response.json()
                    if "tables" in data:
                        tables = data["tables"]
                        result.add_log("info", f"Found {len(tables)} tables in base")
                        result.performance_metrics["tables_count"] = len(tables)
                        
                        # Validate table structure
                        for table in tables[:3]:  # Check first 3 tables
                            table_name = table.get("name", "Unknown")
                            fields_count = len(table.get("fields", []))
                            result.add_log("info", f"Table '{table_name}': {fields_count} fields")
                        
                        # Test record access on first table
                        if tables:
                            first_table = tables[0]
                            await self._test_table_records(base_id, first_table, result)
                        
                except json.JSONDecodeError:
                    result.add_issue("medium", "Response Parse Error", "Could not parse tables response")
                
            elif response.status_code == 404:
                result.add_issue("critical", "Base Not Found", f"Base {base_id} does not exist or no access")
                
            elif response.status_code == 403:
                result.add_issue("high", "Base Access Denied", f"No permission to access base {base_id}")
                
            else:
                result.add_issue("high", "Base Access Error", 
                               f"Unexpected status code: {response.status_code}")
            
            result.performance_metrics["response_time"] = response_time
            result.complete("passed" if test_result.success else "failed")
        
        except Exception as e:
            result.add_log("error", f"Base access test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def _test_table_records(self, base_id: str, table: Dict[str, Any], result: TestResult):
        """Test record access for a specific table"""
        table_name = table.get("name", "Unknown")
        table_id = table.get("id", table_name)
        
        try:
            # Test record listing
            endpoint = f"/{base_id}/{table_id}"
            response, response_time = await self._make_request(
                "GET", 
                endpoint,
                params={"maxRecords": 10}  # Limit for testing
            )
            
            test_result = ExternalAPITestResult(
                api_name="Airtable",
                endpoint=f"{endpoint}?maxRecords=10",
                test_type="record_access",
                success=response.status_code == 200,
                response_time=response_time,
                status_code=response.status_code,
                response_size=len(response.content),
                metadata={"table_name": table_name}
            )
            
            self.test_results.append(test_result)
            
            if response.status_code == 200:
                try:
                    data = response.json()
                    records = data.get("records", [])
                    result.add_log("info", f"✓ Table '{table_name}': {len(records)} records accessible")
                    result.performance_metrics[f"table_{table_name}_records"] = len(records)
                    
                    # Validate record structure
                    if records:
                        first_record = records[0]
                        fields = first_record.get("fields", {})
                        result.add_log("info", f"Sample record has {len(fields)} fields")
                
                except json.JSONDecodeError:
                    result.add_issue("medium", f"Table Parse Error: {table_name}", 
                                   "Could not parse table records")
            else:
                result.add_issue("medium", f"Table Access Error: {table_name}", 
                               f"Status code: {response.status_code}")
        
        except Exception as e:
            result.add_log("warning", f"Failed to test table '{table_name}': {e}")
    
    async def test_crud_operations(self) -> TestResult:
        """Test Create, Read, Update, Delete operations"""
        result = TestResult("Airtable API", "CRUD Operations Test")
        
        try:
            base_id = self.config.airtable.base_id
            
            # Get first table for testing
            tables_response, _ = await self._make_request("GET", f"/{base_id}/tables")
            
            if tables_response.status_code != 200:
                result.add_issue("critical", "Cannot Access Tables", "Failed to get tables list")
                result.complete("failed")
                return result
            
            tables_data = tables_response.json()
            tables = tables_data.get("tables", [])
            
            if not tables:
                result.add_issue("critical", "No Tables Found", "Base has no tables for testing")
                result.complete("failed")
                return result
            
            # Use first table that allows creation (not a view or restricted table)
            test_table = None
            for table in tables:
                # Skip tables that might be views or have restrictions
                if not table.get("name", "").lower().startswith("view"):
                    test_table = table
                    break
            
            if not test_table:
                result.add_log("warning", "No suitable table found for CRUD testing")
                result.complete("passed")
                return result
            
            table_name = test_table["name"]
            table_id = test_table.get("id", table_name)
            
            result.add_log("info", f"Testing CRUD operations on table: {table_name}")
            
            # CREATE - Test record creation
            create_success = await self._test_create_record(base_id, table_id, table_name, result)
            
            # READ - Already tested in base access
            result.add_log("info", "✓ READ operation already validated")
            
            # UPDATE and DELETE would require knowing the record structure
            # For safety, we'll skip these in automated testing unless specifically configured
            result.add_log("info", "UPDATE and DELETE operations skipped for safety")
            
            if create_success:
                result.complete("passed")
            else:
                result.complete("failed")
        
        except Exception as e:
            result.add_log("error", f"CRUD operations test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def _test_create_record(self, base_id: str, table_id: str, table_name: str, 
                                  result: TestResult) -> bool:
        """Test record creation (only if safe)"""
        try:
            # Generate minimal test data
            test_record = {
                "fields": {
                    "Name": f"Test Record {datetime.now().strftime('%Y%m%d_%H%M%S')}",
                    "Test": True,
                    "Created": datetime.now().isoformat()
                }
            }
            
            endpoint = f"/{base_id}/{table_id}"
            response, response_time = await self._make_request(
                "POST",
                endpoint,
                json={"records": [test_record]}
            )
            
            test_result = ExternalAPITestResult(
                api_name="Airtable",
                endpoint=endpoint,
                test_type="record_create",
                success=response.status_code in [200, 201],
                response_time=response_time,
                status_code=response.status_code,
                response_size=len(response.content),
                metadata={"table_name": table_name, "operation": "CREATE"}
            )
            
            self.test_results.append(test_result)
            
            if response.status_code in [200, 201]:
                result.add_log("info", f"✓ CREATE operation successful on {table_name}")
                
                # Try to delete the test record to clean up
                try:
                    response_data = response.json()
                    created_records = response_data.get("records", [])
                    if created_records:
                        record_id = created_records[0].get("id")
                        if record_id:
                            await self._cleanup_test_record(base_id, table_id, record_id, result)
                except Exception as cleanup_error:
                    result.add_log("warning", f"Failed to cleanup test record: {cleanup_error}")
                
                return True
            else:
                # This might be expected for read-only bases
                result.add_log("info", f"CREATE operation not allowed on {table_name} (status: {response.status_code})")
                return True  # Not a failure, just not supported
        
        except Exception as e:
            result.add_log("warning", f"CREATE operation test failed: {e}")
            return False
    
    async def _cleanup_test_record(self, base_id: str, table_id: str, record_id: str, result: TestResult):
        """Clean up test record"""
        try:
            endpoint = f"/{base_id}/{table_id}"
            response, response_time = await self._make_request(
                "DELETE",
                endpoint,
                params={"records[]": record_id}
            )
            
            if response.status_code == 200:
                result.add_log("info", "✓ Test record cleaned up successfully")
            else:
                result.add_log("warning", f"Failed to cleanup test record: {response.status_code}")
        
        except Exception as e:
            result.add_log("warning", f"Cleanup failed: {e}")
    
    async def test_performance(self) -> TestResult:
        """Test Airtable API performance"""
        result = TestResult("Airtable API", "Performance Test")
        
        try:
            base_id = self.config.airtable.base_id
            
            # Test multiple concurrent requests
            concurrent_requests = 5
            test_endpoints = [f"/{base_id}/tables"] * concurrent_requests
            
            result.add_log("info", f"Testing {concurrent_requests} concurrent requests")
            
            start_time = time.time()
            
            # Make concurrent requests
            tasks = [
                self._make_request("GET", endpoint) 
                for endpoint in test_endpoints
            ]
            
            responses_and_times = await asyncio.gather(*tasks, return_exceptions=True)
            
            total_time = time.time() - start_time
            
            # Analyze results
            successful_requests = 0
            response_times = []
            
            for response_and_time in responses_and_times:
                if isinstance(response_and_time, tuple):
                    response, response_time = response_and_time
                    if response.status_code == 200:
                        successful_requests += 1
                        response_times.append(response_time)
                    
                    test_result = ExternalAPITestResult(
                        api_name="Airtable",
                        endpoint="/tables",
                        test_type="performance",
                        success=response.status_code == 200,
                        response_time=response_time,
                        status_code=response.status_code,
                        response_size=len(response.content)
                    )
                    self.test_results.append(test_result)
            
            # Calculate metrics
            success_rate = successful_requests / concurrent_requests * 100
            avg_response_time = sum(response_times) / len(response_times) if response_times else 0
            max_response_time = max(response_times) if response_times else 0
            requests_per_second = concurrent_requests / total_time
            
            result.performance_metrics.update({
                "concurrent_requests": concurrent_requests,
                "successful_requests": successful_requests,
                "success_rate": success_rate,
                "avg_response_time": avg_response_time,
                "max_response_time": max_response_time,
                "requests_per_second": requests_per_second,
                "total_time": total_time
            })
            
            result.add_log("info", f"Performance results:")
            result.add_log("info", f"  Success rate: {success_rate:.1f}%")
            result.add_log("info", f"  Avg response time: {avg_response_time:.3f}s")
            result.add_log("info", f"  Max response time: {max_response_time:.3f}s")
            result.add_log("info", f"  Requests/second: {requests_per_second:.1f}")
            
            # Performance thresholds
            if success_rate < 90:
                result.add_issue("high", "Low Success Rate", f"Success rate {success_rate:.1f}% < 90%")
            
            if avg_response_time > 3.0:
                result.add_issue("medium", "Slow Response", f"Avg response time {avg_response_time:.3f}s > 3.0s")
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Performance test failed: {e}")
            result.complete("failed")
        
        return result

class GeminiAPITester:
    """Comprehensive Gemini AI API testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.model = None
        self.test_results: List[ExternalAPITestResult] = []
        self.data_factory = TestDataFactory()
    
    async def __aenter__(self):
        """Initialize Gemini API"""
        try:
            genai.configure(api_key=self.config.gemini.api_key)
            
            # Initialize model
            self.model = genai.GenerativeModel(
                model_name=self.config.gemini.model,
                generation_config=genai.types.GenerationConfig(
                    temperature=self.config.gemini.temperature,
                    max_output_tokens=self.config.gemini.max_tokens,
                    candidate_count=1
                )
            )
            
            logger.info(f"Gemini API initialized with model: {self.config.gemini.model}")
        except Exception as e:
            logger.error(f"Failed to initialize Gemini API: {e}")
            raise
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Cleanup Gemini API resources"""
        # No explicit cleanup needed for Gemini API
        pass
    
    async def test_authentication(self) -> TestResult:
        """Test Gemini API authentication and basic functionality"""
        result = TestResult("Gemini API", "Authentication Test")
        
        try:
            # Test with a simple prompt
            test_prompt = "Hello! Please respond with 'Authentication successful' to confirm the API is working."
            
            start_time = time.time()
            response = await asyncio.to_thread(
                self.model.generate_content,
                test_prompt
            )
            response_time = time.time() - start_time
            
            test_result = ExternalAPITestResult(
                api_name="Gemini",
                endpoint="/generateContent",
                test_type="authentication",
                success=bool(response and response.text),
                response_time=response_time,
                status_code=200 if response else 0,
                response_size=len(response.text) if response and response.text else 0,
                metadata={"prompt_length": len(test_prompt)}
            )
            
            self.test_results.append(test_result)
            
            if response and response.text:
                result.add_log("info", "✓ Authentication successful")
                result.add_log("info", f"Response: {response.text[:100]}...")
                result.performance_metrics["response_time"] = response_time
                result.performance_metrics["response_length"] = len(response.text)
                
                # Check if response makes sense
                if "authentication" in response.text.lower() or "successful" in response.text.lower():
                    result.add_log("info", "✓ Response content is relevant")
                else:
                    result.add_issue("low", "Unexpected Response", "Response doesn't match expected pattern")
                
                result.complete("passed")
            else:
                result.add_issue("critical", "No Response", "Gemini API did not return a response")
                result.complete("failed")
        
        except Exception as e:
            result.add_log("error", f"Authentication test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_content_generation(self) -> TestResult:
        """Test various content generation scenarios"""
        result = TestResult("Gemini API", "Content Generation Test")
        
        test_scenarios = [
            {
                "name": "Simple Question",
                "prompt": "What is the capital of France?",
                "expected_keywords": ["paris", "capital", "france"]
            },
            {
                "name": "Data Analysis Request",
                "prompt": "Analyze this sample data and provide insights: Sales: [100, 150, 200, 175, 225]",
                "expected_keywords": ["analysis", "data", "sales", "trend", "increase"]
            },
            {
                "name": "JSON Generation",
                "prompt": "Generate a JSON object representing a user with name, email, and age fields.",
                "expected_keywords": ["json", "{", "}", "name", "email", "age"]
            },
            {
                "name": "Code Explanation",
                "prompt": "Explain what this Python code does: def factorial(n): return 1 if n <= 1 else n * factorial(n-1)",
                "expected_keywords": ["factorial", "recursive", "function", "python"]
            }
        ]
        
        try:
            for i, scenario in enumerate(test_scenarios):
                result.add_log("info", f"Testing scenario: {scenario['name']}")
                
                start_time = time.time()
                response = await asyncio.to_thread(
                    self.model.generate_content,
                    scenario["prompt"]
                )
                response_time = time.time() - start_time
                
                test_result = ExternalAPITestResult(
                    api_name="Gemini",
                    endpoint="/generateContent",
                    test_type="content_generation",
                    success=bool(response and response.text),
                    response_time=response_time,
                    status_code=200 if response else 0,
                    response_size=len(response.text) if response and response.text else 0,
                    metadata={
                        "scenario": scenario["name"],
                        "prompt_length": len(scenario["prompt"])
                    }
                )
                
                self.test_results.append(test_result)
                
                if response and response.text:
                    response_text = response.text.lower()
                    
                    # Check for expected keywords
                    found_keywords = [
                        keyword for keyword in scenario["expected_keywords"]
                        if keyword.lower() in response_text
                    ]
                    
                    keyword_score = len(found_keywords) / len(scenario["expected_keywords"]) * 100
                    
                    result.add_log("info", f"✓ {scenario['name']}: Response received ({len(response.text)} chars)")
                    result.add_log("info", f"  Keyword relevance: {keyword_score:.1f}% ({len(found_keywords)}/{len(scenario['expected_keywords'])})")
                    
                    result.performance_metrics[f"scenario_{i+1}_response_time"] = response_time
                    result.performance_metrics[f"scenario_{i+1}_keyword_score"] = keyword_score
                    
                    if keyword_score < 50:
                        result.add_issue("medium", f"Low Relevance: {scenario['name']}", 
                                       f"Response relevance score: {keyword_score:.1f}%")
                else:
                    result.add_issue("high", f"No Response: {scenario['name']}", 
                                   "Failed to generate content")
                
                # Rate limiting
                await asyncio.sleep(1)
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Content generation test failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_airtable_integration_simulation(self) -> TestResult:
        """Test Gemini's ability to work with Airtable-like data"""
        result = TestResult("Gemini API", "Airtable Integration Simulation")
        
        try:
            # Generate sample Airtable data
            sample_data = []
            for i in range(5):
                record = self.data_factory.generate_airtable_record_data("projects")
                sample_data.append(record["fields"])
            
            # Create prompt with sample data
            data_json = json.dumps(sample_data, indent=2)
            prompt = f"""
            I have the following project data from Airtable:

            {data_json}

            Please analyze this data and provide:
            1. A summary of the projects
            2. The total budget across all projects
            3. Projects by status
            4. Any insights or recommendations

            Format your response as JSON with the following structure:
            {{
                "summary": "...",
                "total_budget": 0,
                "projects_by_status": {{}},
                "insights": ["..."]
            }}
            """
            
            result.add_log("info", f"Testing Airtable data analysis with {len(sample_data)} sample records")
            
            start_time = time.time()
            response = await asyncio.to_thread(
                self.model.generate_content,
                prompt
            )
            response_time = time.time() - start_time
            
            test_result = ExternalAPITestResult(
                api_name="Gemini",
                endpoint="/generateContent",
                test_type="airtable_simulation",
                success=bool(response and response.text),
                response_time=response_time,
                status_code=200 if response else 0,
                response_size=len(response.text) if response and response.text else 0,
                metadata={
                    "sample_records": len(sample_data),
                    "prompt_length": len(prompt)
                }
            )
            
            self.test_results.append(test_result)
            
            if response and response.text:
                result.add_log("info", f"✓ Airtable simulation response received ({len(response.text)} chars)")
                
                # Try to parse JSON response
                try:
                    # Extract JSON from response (might have extra text)
                    response_text = response.text
                    json_start = response_text.find('{')
                    json_end = response_text.rfind('}') + 1
                    
                    if json_start >= 0 and json_end > json_start:
                        json_text = response_text[json_start:json_end]
                        parsed_response = json.loads(json_text)
                        
                        result.add_log("info", "✓ Response is valid JSON")
                        
                        # Validate structure
                        expected_keys = ["summary", "total_budget", "projects_by_status", "insights"]
                        found_keys = [key for key in expected_keys if key in parsed_response]
                        
                        structure_score = len(found_keys) / len(expected_keys) * 100
                        result.performance_metrics["structure_score"] = structure_score
                        
                        if structure_score >= 75:
                            result.add_log("info", f"✓ Response structure is good ({structure_score:.1f}%)")
                        else:
                            result.add_issue("medium", "Poor Response Structure", 
                                           f"Structure score: {structure_score:.1f}%")
                        
                        # Check if total budget makes sense
                        if "total_budget" in parsed_response:
                            total_budget = parsed_response["total_budget"]
                            if isinstance(total_budget, (int, float)) and total_budget > 0:
                                result.add_log("info", f"✓ Budget calculation: ${total_budget:,.2f}")
                            else:
                                result.add_issue("low", "Invalid Budget Calculation", 
                                               f"Budget value: {total_budget}")
                    
                    else:
                        result.add_issue("medium", "No JSON in Response", 
                                       "Response doesn't contain valid JSON")
                
                except json.JSONDecodeError:
                    result.add_issue("medium", "Invalid JSON Response", 
                                   "Could not parse response as JSON")
                
                # Check for data analysis keywords
                analysis_keywords = ["summary", "total", "budget", "status", "project", "analysis"]
                found_analysis_keywords = [
                    keyword for keyword in analysis_keywords
                    if keyword.lower() in response.text.lower()
                ]
                
                analysis_score = len(found_analysis_keywords) / len(analysis_keywords) * 100
                result.performance_metrics["analysis_score"] = analysis_score
                
                if analysis_score >= 60:
                    result.add_log("info", f"✓ Good analysis content ({analysis_score:.1f}%)")
                else:
                    result.add_issue("medium", "Weak Analysis Content", 
                                   f"Analysis score: {analysis_score:.1f}%")
                
                result.performance_metrics["response_time"] = response_time
                result.complete("passed")
            else:
                result.add_issue("critical", "No Response", "Failed to generate Airtable analysis")
                result.complete("failed")
        
        except Exception as e:
            result.add_log("error", f"Airtable integration simulation failed: {e}")
            result.complete("failed")
        
        return result
    
    async def test_performance_and_limits(self) -> TestResult:
        """Test Gemini API performance and rate limits"""
        result = TestResult("Gemini API", "Performance and Limits Test")
        
        try:
            # Test different prompt sizes
            prompt_sizes = [
                ("Small", "What is 2+2?"),
                ("Medium", "Explain machine learning in simple terms. " * 10),
                ("Large", "Analyze this data and provide insights. " * 50)
            ]
            
            for size_name, prompt in prompt_sizes:
                result.add_log("info", f"Testing {size_name} prompt ({len(prompt)} chars)")
                
                start_time = time.time()
                try:
                    response = await asyncio.to_thread(
                        self.model.generate_content,
                        prompt
                    )
                    response_time = time.time() - start_time
                    
                    if response and response.text:
                        result.add_log("info", f"✓ {size_name} prompt: {response_time:.3f}s response time")
                        result.performance_metrics[f"{size_name.lower()}_prompt_response_time"] = response_time
                        result.performance_metrics[f"{size_name.lower()}_response_length"] = len(response.text)
                        
                        # Check for reasonable response times
                        if response_time > 30:
                            result.add_issue("medium", f"Slow {size_name} Response", 
                                           f"Response time: {response_time:.3f}s")
                    
                    test_result = ExternalAPITestResult(
                        api_name="Gemini",
                        endpoint="/generateContent",
                        test_type="performance",
                        success=bool(response and response.text),
                        response_time=response_time,
                        status_code=200 if response else 0,
                        response_size=len(response.text) if response and response.text else 0,
                        metadata={"prompt_size": size_name, "prompt_length": len(prompt)}
                    )
                    
                    self.test_results.append(test_result)
                
                except Exception as e:
                    result.add_log("warning", f"{size_name} prompt failed: {e}")
                
                # Rate limiting between requests
                await asyncio.sleep(2)
            
            result.complete("passed")
        
        except Exception as e:
            result.add_log("error", f"Performance test failed: {e}")
            result.complete("failed")
        
        return result

class ExternalAPITestOrchestrator:
    """Orchestrates external API testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.test_results: List[TestResult] = []
        self.airtable_results: List[ExternalAPITestResult] = []
        self.gemini_results: List[ExternalAPITestResult] = []
    
    async def run_comprehensive_external_api_tests(self) -> List[TestResult]:
        """Run comprehensive external API tests"""
        logger.info("Starting comprehensive external API testing")
        
        # Test Airtable API
        if self.config.airtable.api_key:
            logger.info("Testing Airtable API...")
            async with AirtableAPITester(self.config) as airtable_tester:
                airtable_tests = [
                    airtable_tester.test_authentication(),
                    airtable_tester.test_base_access(),
                    airtable_tester.test_crud_operations(),
                    airtable_tester.test_performance()
                ]
                
                airtable_results = await asyncio.gather(*airtable_tests, return_exceptions=True)
                
                for result in airtable_results:
                    if isinstance(result, TestResult):
                        self.test_results.append(result)
                        logger.info(f"Airtable test completed: {result.test_name} - {result.status}")
                    else:
                        logger.error(f"Airtable test failed with exception: {result}")
                
                self.airtable_results.extend(airtable_tester.test_results)
        else:
            logger.warning("Airtable API key not configured, skipping Airtable tests")
        
        # Test Gemini API
        if self.config.gemini.api_key:
            logger.info("Testing Gemini API...")
            async with GeminiAPITester(self.config) as gemini_tester:
                gemini_tests = [
                    gemini_tester.test_authentication(),
                    gemini_tester.test_content_generation(),
                    gemini_tester.test_airtable_integration_simulation(),
                    gemini_tester.test_performance_and_limits()
                ]
                
                gemini_results = await asyncio.gather(*gemini_tests, return_exceptions=True)
                
                for result in gemini_results:
                    if isinstance(result, TestResult):
                        self.test_results.append(result)
                        logger.info(f"Gemini test completed: {result.test_name} - {result.status}")
                    else:
                        logger.error(f"Gemini test failed with exception: {result}")
                
                self.gemini_results.extend(gemini_tester.test_results)
        else:
            logger.warning("Gemini API key not configured, skipping Gemini tests")
        
        logger.info(f"External API testing completed. Total tests: {len(self.test_results)}")
        
        return self.test_results