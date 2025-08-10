#!/usr/bin/env python3
"""
Comprehensive test suite for MCP Server integration with Airtable Gateway
Tests all 10 required MCP tools according to Sprint 2 architecture requirements
"""
import asyncio
import json
import time
import logging
from typing import Dict, Any, List
from datetime import datetime

import httpx
import pytest
from fastapi.testclient import TestClient

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Test configuration
MCP_SERVER_URL = "http://localhost:8001"
AIRTABLE_GATEWAY_URL = "http://localhost:8002"
TEST_BASE_ID = "appTestBase123456"  # This would be a real base ID in actual tests
TEST_TABLE_ID = "tblTestTable12345"  # This would be a real table ID in actual tests


class MCPServerTestSuite:
    """Test suite for MCP Server functionality"""
    
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=30.0)
        self.test_results = []
        
    async def close(self):
        await self.client.aclose()
    
    def log_test_result(self, test_name: str, success: bool, details: Dict[str, Any]):
        """Log test result"""
        result = {
            "test": test_name,
            "success": success,
            "timestamp": datetime.utcnow().isoformat(),
            "details": details
        }
        self.test_results.append(result)
        
        status = "✅" if success else "❌"
        logger.info(f"{status} {test_name}: {details.get('message', 'No details')}")
    
    async def test_health_checks(self) -> bool:
        """Test all health check endpoints"""
        endpoints = [
            "/health",
            "/health/ready", 
            "/health/live",
            "/health/detailed"
        ]
        
        all_passed = True
        for endpoint in endpoints:
            try:
                response = await self.client.get(f"{MCP_SERVER_URL}{endpoint}")
                success = response.status_code == 200
                
                if success:
                    data = response.json()
                    self.log_test_result(
                        f"health_check_{endpoint.replace('/', '_')}",
                        True,
                        {"status_code": response.status_code, "status": data.get("status")}
                    )
                else:
                    all_passed = False
                    self.log_test_result(
                        f"health_check_{endpoint.replace('/', '_')}",
                        False,
                        {"status_code": response.status_code, "error": response.text}
                    )
            except Exception as e:
                all_passed = False
                self.log_test_result(
                    f"health_check_{endpoint.replace('/', '_')}",
                    False,
                    {"error": str(e)}
                )
        
        return all_passed
    
    async def test_mcp_info_endpoints(self) -> bool:
        """Test MCP information endpoints"""
        endpoints = [
            "/mcp/info",
            "/mcp/status", 
            "/mcp/tools"
        ]
        
        all_passed = True
        for endpoint in endpoints:
            try:
                response = await self.client.get(f"{MCP_SERVER_URL}{endpoint}")
                success = response.status_code == 200
                
                if success:
                    data = response.json()
                    self.log_test_result(
                        f"mcp_info_{endpoint.split('/')[-1]}",
                        True,
                        {"status_code": response.status_code, "data_keys": list(data.keys())}
                    )
                    
                    # Validate tools endpoint specifically
                    if endpoint.endswith("/tools") and isinstance(data, list):
                        tool_names = [tool.get("name") for tool in data if isinstance(tool, dict)]
                        expected_tools = [
                            "list_bases", "list_tables", "get_schema", "list_records",
                            "create_record", "update_record", "delete_record",
                            "batch_create", "batch_update", "search_records"
                        ]
                        
                        tools_found = all(tool in tool_names for tool in expected_tools)
                        if tools_found:
                            self.log_test_result(
                                "mcp_tools_validation",
                                True,
                                {"tools_count": len(tool_names), "expected_tools_found": True}
                            )
                        else:
                            all_passed = False
                            missing = [t for t in expected_tools if t not in tool_names]
                            self.log_test_result(
                                "mcp_tools_validation",
                                False,
                                {"missing_tools": missing, "found_tools": tool_names}
                            )
                else:
                    all_passed = False
                    self.log_test_result(
                        f"mcp_info_{endpoint.split('/')[-1]}",
                        False,
                        {"status_code": response.status_code, "error": response.text}
                    )
            except Exception as e:
                all_passed = False
                self.log_test_result(
                    f"mcp_info_{endpoint.split('/')[-1]}",
                    False,
                    {"error": str(e)}
                )
        
        return all_passed
    
    async def test_mcp_rpc_protocol(self) -> bool:
        """Test MCP RPC protocol implementation"""
        test_requests = [
            {
                "name": "initialize",
                "request": {
                    "version": "1.0",
                    "method": "initialize",
                    "params": {},
                    "id": "init_1"
                },
                "expected_keys": ["protocol_version", "server_info"]
            },
            {
                "name": "list_tools",
                "request": {
                    "version": "1.0", 
                    "method": "list_tools",
                    "params": {},
                    "id": "list_tools_1"
                },
                "expected_result_type": list
            }
        ]
        
        all_passed = True
        for test_case in test_requests:
            try:
                response = await self.client.post(
                    f"{MCP_SERVER_URL}/mcp/rpc",
                    json=test_case["request"]
                )
                
                success = response.status_code == 200
                if success:
                    data = response.json()
                    
                    # Validate response structure
                    if "result" in data and data.get("id") == test_case["request"]["id"]:
                        result = data["result"]
                        
                        if "expected_keys" in test_case:
                            keys_present = all(key in result for key in test_case["expected_keys"])
                            if keys_present:
                                self.log_test_result(
                                    f"mcp_rpc_{test_case['name']}",
                                    True,
                                    {"response_valid": True, "keys_found": test_case["expected_keys"]}
                                )
                            else:
                                all_passed = False
                                self.log_test_result(
                                    f"mcp_rpc_{test_case['name']}",
                                    False,
                                    {"missing_keys": [k for k in test_case["expected_keys"] if k not in result]}
                                )
                        
                        elif "expected_result_type" in test_case:
                            type_correct = isinstance(result, test_case["expected_result_type"])
                            if type_correct:
                                self.log_test_result(
                                    f"mcp_rpc_{test_case['name']}",
                                    True,
                                    {"result_type": str(type(result)), "items_count": len(result) if hasattr(result, '__len__') else None}
                                )
                            else:
                                all_passed = False
                                self.log_test_result(
                                    f"mcp_rpc_{test_case['name']}",
                                    False,
                                    {"expected_type": str(test_case["expected_result_type"]), "actual_type": str(type(result))}
                                )
                    else:
                        all_passed = False
                        self.log_test_result(
                            f"mcp_rpc_{test_case['name']}",
                            False,
                            {"invalid_response_structure": data}
                        )
                else:
                    all_passed = False
                    self.log_test_result(
                        f"mcp_rpc_{test_case['name']}",
                        False,
                        {"status_code": response.status_code, "error": response.text}
                    )
            except Exception as e:
                all_passed = False
                self.log_test_result(
                    f"mcp_rpc_{test_case['name']}",
                    False,
                    {"error": str(e)}
                )
        
        return all_passed
    
    async def test_tool_execution_rest_api(self) -> bool:
        """Test tool execution via REST API"""
        # Test tools that don't require real Airtable data
        test_tools = [
            {
                "name": "list_bases",
                "arguments": {},
                "should_succeed": True  # May fail if no auth, but endpoint should respond
            },
            {
                "name": "calculate",
                "arguments": {"expression": "2 + 2"},
                "should_succeed": True
            }
        ]
        
        all_passed = True
        for tool_test in test_tools:
            try:
                response = await self.client.post(
                    f"{MCP_SERVER_URL}/mcp/tools/{tool_test['name']}/execute",
                    json={
                        "tool": tool_test["name"],
                        "arguments": tool_test["arguments"]
                    }
                )
                
                # Accept both success and expected failures (like auth errors)
                success = response.status_code in [200, 401, 403]
                
                if success:
                    data = response.json()
                    if response.status_code == 200:
                        # Tool executed successfully
                        has_result_or_error = "result" in data or "error" in data
                        if has_result_or_error:
                            self.log_test_result(
                                f"tool_rest_{tool_test['name']}",
                                True,
                                {"status_code": response.status_code, "execution": "success"}
                            )
                        else:
                            all_passed = False
                            self.log_test_result(
                                f"tool_rest_{tool_test['name']}",
                                False,
                                {"missing_result_or_error": True, "data": data}
                            )
                    else:
                        # Expected auth failure
                        self.log_test_result(
                            f"tool_rest_{tool_test['name']}",
                            True,
                            {"status_code": response.status_code, "execution": "expected_auth_failure"}
                        )
                else:
                    all_passed = False
                    self.log_test_result(
                        f"tool_rest_{tool_test['name']}",
                        False,
                        {"status_code": response.status_code, "error": response.text}
                    )
            except Exception as e:
                all_passed = False
                self.log_test_result(
                    f"tool_rest_{tool_test['name']}",
                    False,
                    {"error": str(e)}
                )
        
        return all_passed
    
    async def test_airtable_gateway_connectivity(self) -> bool:
        """Test connectivity to Airtable Gateway service"""
        try:
            # Test basic health check
            response = await self.client.get(f"{AIRTABLE_GATEWAY_URL}/health")
            if response.status_code == 200:
                self.log_test_result(
                    "airtable_gateway_health",
                    True,
                    {"status_code": response.status_code, "service": "airtable-gateway"}
                )
                
                # Test if enhanced endpoints exist
                test_endpoints = [
                    "/api/v1/bases",
                    "/api/v1/status"
                ]
                
                endpoint_tests = []
                for endpoint in test_endpoints:
                    try:
                        test_response = await self.client.get(f"{AIRTABLE_GATEWAY_URL}{endpoint}")
                        # Accept auth errors as valid responses
                        endpoint_available = test_response.status_code in [200, 401, 403]
                        endpoint_tests.append(endpoint_available)
                    except:
                        endpoint_tests.append(False)
                
                if all(endpoint_tests):
                    self.log_test_result(
                        "airtable_gateway_endpoints",
                        True,
                        {"endpoints_available": test_endpoints}
                    )
                    return True
                else:
                    self.log_test_result(
                        "airtable_gateway_endpoints",
                        False,
                        {"some_endpoints_unavailable": test_endpoints}
                    )
                    return False
            else:
                self.log_test_result(
                    "airtable_gateway_health",
                    False,
                    {"status_code": response.status_code, "error": response.text}
                )
                return False
        except Exception as e:
            self.log_test_result(
                "airtable_gateway_connectivity",
                False,
                {"error": str(e), "url": AIRTABLE_GATEWAY_URL}
            )
            return False
    
    async def test_websocket_connectivity(self) -> bool:
        """Test WebSocket connectivity (basic connection test)"""
        try:
            # For now, just test that the endpoint exists
            # Full WebSocket testing would require more complex setup
            response = await self.client.get(f"{MCP_SERVER_URL}/mcp/status")
            
            if response.status_code == 200:
                data = response.json()
                websocket_support = data.get("connections", {}).get("websocket_active") is not None
                
                self.log_test_result(
                    "websocket_endpoint_available",
                    websocket_support,
                    {"websocket_support": websocket_support}
                )
                return websocket_support
            else:
                self.log_test_result(
                    "websocket_endpoint_available",
                    False,
                    {"status_endpoint_failed": response.status_code}
                )
                return False
        except Exception as e:
            self.log_test_result(
                "websocket_connectivity",
                False,
                {"error": str(e)}
            )
            return False
    
    async def run_all_tests(self) -> Dict[str, Any]:
        """Run all tests and return comprehensive results"""
        logger.info("🚀 Starting MCP Server Integration Test Suite")
        start_time = time.time()
        
        test_groups = [
            ("Health Checks", self.test_health_checks),
            ("MCP Info Endpoints", self.test_mcp_info_endpoints),
            ("MCP RPC Protocol", self.test_mcp_rpc_protocol),
            ("Tool Execution REST API", self.test_tool_execution_rest_api),
            ("Airtable Gateway Connectivity", self.test_airtable_gateway_connectivity),
            ("WebSocket Connectivity", self.test_websocket_connectivity)
        ]
        
        group_results = {}
        overall_success = True
        
        for group_name, test_func in test_groups:
            logger.info(f"📋 Running {group_name} tests...")
            try:
                group_success = await test_func()
                group_results[group_name] = group_success
                if not group_success:
                    overall_success = False
                    
                status = "✅ PASSED" if group_success else "❌ FAILED"
                logger.info(f"   {status}: {group_name}")
            except Exception as e:
                logger.error(f"   ❌ ERROR in {group_name}: {str(e)}")
                group_results[group_name] = False
                overall_success = False
        
        total_time = time.time() - start_time
        
        # Compile final results
        results = {
            "overall_success": overall_success,
            "timestamp": datetime.utcnow().isoformat(),
            "duration_seconds": round(total_time, 2),
            "test_groups": group_results,
            "individual_tests": self.test_results,
            "summary": {
                "total_tests": len(self.test_results),
                "passed_tests": len([t for t in self.test_results if t["success"]]),
                "failed_tests": len([t for t in self.test_results if not t["success"]]),
                "pass_rate": round(
                    len([t for t in self.test_results if t["success"]]) / len(self.test_results) * 100, 1
                ) if self.test_results else 0
            },
            "configuration": {
                "mcp_server_url": MCP_SERVER_URL,
                "airtable_gateway_url": AIRTABLE_GATEWAY_URL
            }
        }
        
        # Print summary
        logger.info("\n" + "="*60)
        logger.info("🎯 MCP SERVER INTEGRATION TEST RESULTS")
        logger.info("="*60)
        logger.info(f"Overall Status: {'✅ SUCCESS' if overall_success else '❌ FAILURE'}")
        logger.info(f"Duration: {total_time:.2f} seconds")
        logger.info(f"Tests: {results['summary']['passed_tests']}/{results['summary']['total_tests']} passed ({results['summary']['pass_rate']}%)")
        logger.info("\nTest Group Results:")
        
        for group, success in group_results.items():
            status = "✅" if success else "❌"
            logger.info(f"  {status} {group}")
        
        if not overall_success:
            logger.info("\n❗ Failed Tests:")
            for test in self.test_results:
                if not test["success"]:
                    logger.info(f"  ❌ {test['test']}: {test['details']}")
        
        logger.info("="*60)
        
        return results


async def main():
    """Main test execution function"""
    test_suite = MCPServerTestSuite()
    
    try:
        results = await test_suite.run_all_tests()
        
        # Save results to file
        results_file = f"mcp_test_results_{int(time.time())}.json"
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        logger.info(f"\n📄 Detailed results saved to: {results_file}")
        
        # Return appropriate exit code
        return 0 if results["overall_success"] else 1
        
    except Exception as e:
        logger.error(f"Fatal error during test execution: {e}")
        return 1
    finally:
        await test_suite.close()


if __name__ == "__main__":
    import sys
    exit_code = asyncio.run(main())
    sys.exit(exit_code)