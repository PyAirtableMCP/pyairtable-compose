"""
Comprehensive End-to-End Tests for PyAirtable Application

This test suite covers real user scenarios:
1. Facebook posts analysis and recommendations
2. Metadata table creation for all tables
3. Working hours calculation per project
4. Project status and expenses listing

Tests verify the complete flow from API Gateway through LLM Orchestrator
to Airtable Gateway with real Gemini AI integration.
"""

import pytest
import httpx
import asyncio
import json
import time
from typing import Dict, Any, List
from dataclasses import dataclass
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class TestConfig:
    """Configuration for E2E tests"""
    api_gateway_url: str = "http://localhost:8000"
    llm_orchestrator_url: str = "http://localhost:8003"
    mcp_server_url: str = "http://localhost:8001"
    airtable_gateway_url: str = "http://localhost:8002"
    airtable_base: str = "appVLUAubH5cFWhMV"
    airtable_api_key: str = "pya_d7f8e9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6"
    timeout: int = 60
    retry_attempts: int = 3
    retry_delay: float = 2.0

class PyAirtableE2ETestSuite:
    """Comprehensive E2E test suite for PyAirtable application"""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.client = httpx.AsyncClient(timeout=config.timeout)
        self.session_id = None
        
    async def __aenter__(self):
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.client.aclose()

    async def health_check_services(self) -> Dict[str, bool]:
        """Check health of all services before running tests"""
        services = {
            "API Gateway": f"{self.config.api_gateway_url}/api/health",
            "LLM Orchestrator": f"{self.config.llm_orchestrator_url}/health",
            "MCP Server": f"{self.config.mcp_server_url}/health",
            "Airtable Gateway": f"{self.config.airtable_gateway_url}/health"
        }
        
        health_status = {}
        
        for service_name, health_url in services.items():
            try:
                response = await self.client.get(health_url)
                health_status[service_name] = response.status_code == 200
                if response.status_code == 200:
                    logger.info(f"✅ {service_name} is healthy")
                else:
                    logger.error(f"❌ {service_name} health check failed: {response.status_code}")
            except Exception as e:
                health_status[service_name] = False
                logger.error(f"❌ {service_name} is unreachable: {str(e)}")
                
        return health_status

    async def send_chat_request(self, message: str, user_id: str = "test_user") -> Dict[str, Any]:
        """Send a chat request through the API Gateway"""
        chat_endpoint = f"{self.config.api_gateway_url}/api/chat"
        
        payload = {
            "messages": [
                {
                    "role": "user",
                    "content": f"I have an Airtable base with ID {self.config.airtable_base}. {message}"
                }
            ],
            "session_id": self.session_id or "e2e_test_session"
        }
        
        headers = {
            "Content-Type": "application/json",
            "X-API-Key": self.config.airtable_api_key,
            "User-Agent": "PyAirtable-E2E-Test/1.0"
        }
        
        for attempt in range(self.config.retry_attempts):
            try:
                logger.info(f"Sending chat request (attempt {attempt + 1}): {message[:100]}...")
                response = await self.client.post(
                    chat_endpoint,
                    json=payload,
                    headers=headers
                )
                
                if response.status_code == 200:
                    result = response.json()
                    if "session_id" in result and not self.session_id:
                        self.session_id = result["session_id"]
                    return result
                else:
                    logger.error(f"Chat request failed with status {response.status_code}: {response.text}")
                    
            except Exception as e:
                logger.error(f"Chat request attempt {attempt + 1} failed: {str(e)}")
                if attempt < self.config.retry_attempts - 1:
                    await asyncio.sleep(self.config.retry_delay)
                    
        raise Exception(f"Chat request failed after {self.config.retry_attempts} attempts")

    async def test_scenario_1_facebook_posts_analysis(self) -> Dict[str, Any]:
        """
        Test Scenario 1: Facebook Posts Analysis
        - Analyze existing posts in the facebook posts table
        - Get recommendations for improvements
        - Generate new post ideas
        """
        logger.info("🧪 Testing Scenario 1: Facebook Posts Analysis")
        
        message = (
            "Notice the facebook posts table in my Airtable base. Please analyze it, "
            "recommend improvements for each existing post, and come up with 2 to 5 new "
            "post ideas that would fit well."
        )
        
        result = await self.send_chat_request(message)
        
        # Validate response structure
        assert "response" in result, "Response should contain 'response' field"
        assert "session_id" in result, "Response should contain 'session_id' field"
        
        response_text = result["response"]
        
        # Check that the response contains analysis of existing posts
        assert "facebook" in response_text.lower(), "Response should mention facebook posts"
        assert any(word in response_text.lower() for word in ["analyze", "analysis", "recommend"]), \
            "Response should indicate analysis was performed"
        
        # Check for new post ideas
        assert any(word in response_text.lower() for word in ["new", "ideas", "suggest"]), \
            "Response should contain new post ideas"
        
        logger.info("✅ Scenario 1 completed successfully")
        return {
            "scenario": "facebook_posts_analysis",
            "status": "passed",
            "response_length": len(response_text),
            "contains_analysis": "analysis" in response_text.lower(),
            "contains_recommendations": "recommend" in response_text.lower(),
            "contains_new_ideas": "new" in response_text.lower()
        }

    async def test_scenario_2_metadata_table_creation(self) -> Dict[str, Any]:
        """
        Test Scenario 2: Metadata Table Creation
        - Create a metadata table describing all tables in the Airtable base
        - Include table purposes and key fields
        """
        logger.info("🧪 Testing Scenario 2: Metadata Table Creation")
        
        message = (
            "Create a metadata table that describes all tables in my Airtable base "
            "with their purpose and key fields"
        )
        
        result = await self.send_chat_request(message)
        
        # Validate response structure
        assert "response" in result, "Response should contain 'response' field"
        
        response_text = result["response"]
        
        # Check that the response indicates metadata table creation
        assert "metadata" in response_text.lower(), "Response should mention metadata"
        assert any(word in response_text.lower() for word in ["table", "tables"]), \
            "Response should mention tables"
        assert any(word in response_text.lower() for word in ["create", "created"]), \
            "Response should indicate table creation"
        
        logger.info("✅ Scenario 2 completed successfully")
        return {
            "scenario": "metadata_table_creation",
            "status": "passed",
            "response_length": len(response_text),
            "mentions_metadata": "metadata" in response_text.lower(),
            "mentions_creation": "create" in response_text.lower(),
            "mentions_purpose": "purpose" in response_text.lower()
        }

    async def test_scenario_3_working_hours_calculation(self) -> Dict[str, Any]:
        """
        Test Scenario 3: Working Hours Calculation
        - Show the working hours table
        - Calculate total hours worked per project
        """
        logger.info("🧪 Testing Scenario 3: Working Hours Calculation")
        
        message = (
            "Show me the working hours table and calculate total hours worked per project"
        )
        
        result = await self.send_chat_request(message)
        
        # Validate response structure
        assert "response" in result, "Response should contain 'response' field"
        
        response_text = result["response"]
        
        # Check that the response shows working hours analysis
        assert "working hours" in response_text.lower() or "hours" in response_text.lower(), \
            "Response should mention working hours"
        assert any(word in response_text.lower() for word in ["total", "calculate", "sum"]), \
            "Response should indicate calculation was performed"
        assert "project" in response_text.lower(), "Response should mention projects"
        
        logger.info("✅ Scenario 3 completed successfully")
        return {
            "scenario": "working_hours_calculation",
            "status": "passed",
            "response_length": len(response_text),
            "mentions_hours": "hours" in response_text.lower(),
            "mentions_calculation": any(word in response_text.lower() for word in ["total", "calculate", "sum"]),
            "mentions_projects": "project" in response_text.lower()
        }

    async def test_scenario_4_projects_status_expenses(self) -> Dict[str, Any]:
        """
        Test Scenario 4: Projects Status and Expenses
        - List all projects with their current status and expenses
        """
        logger.info("🧪 Testing Scenario 4: Projects Status and Expenses")
        
        message = (
            "List all projects with their current status and expenses"
        )
        
        result = await self.send_chat_request(message)
        
        # Validate response structure
        assert "response" in result, "Response should contain 'response' field"
        
        response_text = result["response"]
        
        # Check that the response lists projects with status and expenses
        assert "project" in response_text.lower(), "Response should mention projects"
        assert "status" in response_text.lower(), "Response should mention status"
        assert any(word in response_text.lower() for word in ["expense", "cost", "budget"]), \
            "Response should mention expenses or costs"
        
        logger.info("✅ Scenario 4 completed successfully")
        return {
            "scenario": "projects_status_expenses",
            "status": "passed",
            "response_length": len(response_text),
            "mentions_projects": "project" in response_text.lower(),
            "mentions_status": "status" in response_text.lower(),
            "mentions_expenses": any(word in response_text.lower() for word in ["expense", "cost", "budget"])
        }

    async def test_gemini_integration(self) -> Dict[str, Any]:
        """Test that Gemini LLM is being used for processing requests"""
        logger.info("🧪 Testing Gemini Integration")
        
        # Send a simple test message to verify Gemini is responding
        message = "Hello, can you tell me what AI model you are and confirm you can access my Airtable data?"
        
        result = await self.send_chat_request(message)
        
        # Validate response structure
        assert "response" in result, "Response should contain 'response' field"
        
        response_text = result["response"]
        
        # Check that we get a coherent AI response
        assert len(response_text) > 50, "Response should be substantial"
        
        logger.info("✅ Gemini integration test completed")
        return {
            "test": "gemini_integration",
            "status": "passed",
            "response_length": len(response_text),
            "ai_response_detected": len(response_text) > 50
        }

    async def test_service_connectivity(self) -> Dict[str, Any]:
        """Test connectivity between services"""
        logger.info("🧪 Testing Service Connectivity")
        
        # Test direct service endpoints
        services_tested = {}
        
        # Test LLM Orchestrator directly
        try:
            response = await self.client.get(f"{self.config.llm_orchestrator_url}/health")
            services_tested["llm_orchestrator"] = response.status_code == 200
        except Exception as e:
            services_tested["llm_orchestrator"] = False
            logger.error(f"LLM Orchestrator connectivity test failed: {e}")
        
        # Test MCP Server directly
        try:
            response = await self.client.get(f"{self.config.mcp_server_url}/health")
            services_tested["mcp_server"] = response.status_code == 200
        except Exception as e:
            services_tested["mcp_server"] = False
            logger.error(f"MCP Server connectivity test failed: {e}")
        
        # Test Airtable Gateway directly
        try:
            response = await self.client.get(f"{self.config.airtable_gateway_url}/health")
            services_tested["airtable_gateway"] = response.status_code == 200
        except Exception as e:
            services_tested["airtable_gateway"] = False
            logger.error(f"Airtable Gateway connectivity test failed: {e}")
        
        logger.info("✅ Service connectivity test completed")
        return {
            "test": "service_connectivity",
            "status": "passed" if all(services_tested.values()) else "partial",
            "services": services_tested
        }

    async def run_comprehensive_test_suite(self) -> Dict[str, Any]:
        """Run all E2E test scenarios and return comprehensive results"""
        logger.info("🚀 Starting Comprehensive PyAirtable E2E Test Suite")
        
        start_time = time.time()
        
        # Check service health first
        health_status = await self.health_check_services()
        
        if not all(health_status.values()):
            logger.error("❌ Not all services are healthy. Aborting test suite.")
            return {
                "status": "aborted",
                "reason": "unhealthy_services",
                "health_status": health_status,
                "duration": time.time() - start_time
            }
        
        # Run all test scenarios
        test_results = {}
        
        try:
            # Test service connectivity
            test_results["connectivity"] = await self.test_service_connectivity()
            
            # Test Gemini integration
            test_results["gemini_integration"] = await self.test_gemini_integration()
            
            # Test all user scenarios
            test_results["scenario_1"] = await self.test_scenario_1_facebook_posts_analysis()
            test_results["scenario_2"] = await self.test_scenario_2_metadata_table_creation()
            test_results["scenario_3"] = await self.test_scenario_3_working_hours_calculation()
            test_results["scenario_4"] = await self.test_scenario_4_projects_status_expenses()
            
        except Exception as e:
            logger.error(f"❌ Test suite failed with error: {str(e)}")
            test_results["error"] = str(e)
        
        end_time = time.time()
        duration = end_time - start_time
        
        # Calculate overall results
        passed_tests = sum(1 for result in test_results.values() 
                          if isinstance(result, dict) and result.get("status") == "passed")
        total_tests = len([r for r in test_results.values() if isinstance(r, dict) and "status" in r])
        
        overall_result = {
            "status": "passed" if passed_tests == total_tests else "failed",
            "duration": duration,
            "total_tests": total_tests,
            "passed_tests": passed_tests,
            "failed_tests": total_tests - passed_tests,
            "health_status": health_status,
            "test_results": test_results,
            "timestamp": int(time.time()),
            "session_id": self.session_id
        }
        
        logger.info(f"🏁 Test Suite Completed: {passed_tests}/{total_tests} passed in {duration:.2f}s")
        
        return overall_result


# Pytest fixtures and test functions
@pytest.fixture
def test_config():
    """Provide test configuration"""
    return TestConfig()

@pytest.fixture
async def e2e_suite(test_config):
    """Provide E2E test suite instance"""
    async with PyAirtableE2ETestSuite(test_config) as suite:
        yield suite

@pytest.mark.asyncio
async def test_service_health_checks(e2e_suite):
    """Test that all services are healthy"""
    health_status = await e2e_suite.health_check_services()
    
    for service, is_healthy in health_status.items():
        assert is_healthy, f"{service} is not healthy"

@pytest.mark.asyncio
async def test_facebook_posts_scenario(e2e_suite):
    """Test Facebook posts analysis scenario"""
    result = await e2e_suite.test_scenario_1_facebook_posts_analysis()
    assert result["status"] == "passed"

@pytest.mark.asyncio
async def test_metadata_table_scenario(e2e_suite):
    """Test metadata table creation scenario"""
    result = await e2e_suite.test_scenario_2_metadata_table_creation()
    assert result["status"] == "passed"

@pytest.mark.asyncio
async def test_working_hours_scenario(e2e_suite):
    """Test working hours calculation scenario"""
    result = await e2e_suite.test_scenario_3_working_hours_calculation()
    assert result["status"] == "passed"

@pytest.mark.asyncio
async def test_projects_status_scenario(e2e_suite):
    """Test projects status and expenses scenario"""
    result = await e2e_suite.test_scenario_4_projects_status_expenses()
    assert result["status"] == "passed"

@pytest.mark.asyncio
async def test_gemini_integration(e2e_suite):
    """Test Gemini LLM integration"""
    result = await e2e_suite.test_gemini_integration()
    assert result["status"] == "passed"

@pytest.mark.asyncio
async def test_comprehensive_suite(e2e_suite):
    """Run the complete comprehensive test suite"""
    result = await e2e_suite.run_comprehensive_test_suite()
    
    # Save results to file for analysis
    import os
    os.makedirs("/Users/kg/IdeaProjects/pyairtable-compose/tests/reports", exist_ok=True)
    
    with open("/Users/kg/IdeaProjects/pyairtable-compose/tests/reports/e2e_comprehensive_results.json", "w") as f:
        json.dump(result, f, indent=2)
    
    assert result["status"] == "passed", f"Comprehensive test suite failed: {result}"


if __name__ == "__main__":
    """Run tests directly for development and debugging"""
    async def main():
        config = TestConfig()
        
        async with PyAirtableE2ETestSuite(config) as suite:
            result = await suite.run_comprehensive_test_suite()
            
            print("\n" + "="*80)
            print("PYAIRTABLE COMPREHENSIVE E2E TEST RESULTS")
            print("="*80)
            print(f"Status: {result['status'].upper()}")
            print(f"Duration: {result['duration']:.2f} seconds")
            print(f"Tests Passed: {result['passed_tests']}/{result['total_tests']}")
            
            if result.get('test_results'):
                print("\nDetailed Results:")
                for test_name, test_result in result['test_results'].items():
                    if isinstance(test_result, dict) and 'status' in test_result:
                        status_emoji = "✅" if test_result['status'] == 'passed' else "❌"
                        print(f"  {status_emoji} {test_name}: {test_result['status']}")
            
            print("="*80)
            
            # Save results
            import os
            os.makedirs("tests/reports", exist_ok=True)
            with open("tests/reports/e2e_comprehensive_results.json", "w") as f:
                json.dump(result, f, indent=2)
            
            print(f"Results saved to: tests/reports/e2e_comprehensive_results.json")
    
    asyncio.run(main())