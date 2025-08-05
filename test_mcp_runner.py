#!/usr/bin/env python3
"""
Simple MCP Test Runner
======================

Simplified test runner for MCP tools testing without complex import dependencies.
This runs the core MCP test scenarios directly.
"""

import asyncio
import sys
import logging
import json
import time
from datetime import datetime
from pathlib import Path

# Add tests framework to path
tests_path = Path(__file__).parent / "tests" / "framework"
sys.path.insert(0, str(tests_path))

# Import after path modification
from test_config import TestFrameworkConfig, TestEnvironment, get_config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def test_health_check():
    """Test health check for all services"""
    config = get_config()
    
    results = {}
    
    for service_name, service_config in config.services.items():
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                url = f"{service_config.url}{service_config.health_endpoint}"
                logger.info(f"Testing {service_name}: {url}")
                
                async with session.get(url, timeout=10) as response:
                    if response.status == 200:
                        data = await response.json()
                        results[service_name] = {
                            "status": "healthy",
                            "response": data,
                            "url": url
                        }
                        logger.info(f"✅ {service_name} is healthy")
                    else:
                        results[service_name] = {
                            "status": "unhealthy",
                            "error": f"HTTP {response.status}",
                            "url": url
                        }
                        logger.error(f"❌ {service_name} returned {response.status}")
        except Exception as e:
            results[service_name] = {
                "status": "error",
                "error": str(e),
                "url": f"{service_config.url}{service_config.health_endpoint}"
            }
            logger.error(f"❌ {service_name} error: {e}")
    
    return results

async def test_api_gateway_chat():
    """Test basic chat functionality through API Gateway"""
    config = get_config()
    api_gateway_url = config.services["api_gateway"].url
    
    try:
        import aiohttp
        async with aiohttp.ClientSession() as session:
            # Test chat endpoint
            chat_url = f"{api_gateway_url}/api/chat"
            payload = {
                "messages": [
                    {
                        "role": "user",
                        "content": "Hello, can you help me analyze my Airtable data?"
                    }
                ],
                "session_id": f"test-session-{int(time.time())}"
            }
            
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": "pya_efe1764855b2300ebc87363fb26b71da645a1e6c"
            }
            
            logger.info(f"Testing chat endpoint: {chat_url}")
            
            async with session.post(chat_url, json=payload, headers=headers, timeout=30) as response:
                if response.status == 200:
                    data = await response.json()
                    logger.info(f"✅ Chat endpoint working - received response")
                    return {
                        "status": "success",
                        "response": data,
                        "url": chat_url
                    }
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Chat endpoint failed: HTTP {response.status} - {error_text}")
                    return {
                        "status": "failed",
                        "error": f"HTTP {response.status}: {error_text}",
                        "url": chat_url
                    }
    except Exception as e:
        logger.error(f"❌ Chat test error: {e}")
        return {
            "status": "error",
            "error": str(e),
            "url": chat_url
        }

async def test_mcp_tools():
    """Test MCP tools functionality"""
    config = get_config()
    api_gateway_url = config.services["api_gateway"].url
    
    try:
        import aiohttp
        async with aiohttp.ClientSession() as session:
            # Test available tools
            tools_url = f"{api_gateway_url}/api/tools"
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": "pya_efe1764855b2300ebc87363fb26b71da645a1e6c"
            }
            
            logger.info(f"Testing tools endpoint: {tools_url}")
            
            async with session.get(tools_url, headers=headers, timeout=30) as response:
                if response.status == 200:
                    data = await response.json()
                    logger.info(f"✅ Tools endpoint working - found {len(data.get('tools', []))} tools")
                    return {
                        "status": "success",
                        "tools": data.get('tools', []),
                        "url": tools_url
                    }
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Tools endpoint failed: HTTP {response.status} - {error_text}")
                    return {
                        "status": "failed",
                        "error": f"HTTP {response.status}: {error_text}",
                        "url": tools_url
                    }
    except Exception as e:
        logger.error(f"❌ Tools test error: {e}")
        return {
            "status": "error",
            "error": str(e),
            "url": f"{api_gateway_url}/api/tools"
        }

async def test_metadata_table_creation():
    """Test creating metadata table through chat interface"""
    config = get_config()
    api_gateway_url = config.services["api_gateway"].url
    
    try:
        import aiohttp
        async with aiohttp.ClientSession() as session:
            chat_url = f"{api_gateway_url}/api/chat"
            
            # Create metadata table prompt
            payload = {
                "messages": [
                    {
                        "role": "user",
                        "content": """Create a new Airtable table called "Table_Metadata" with the following structure:
                        
                        Fields:
                        - table_name (Single line text) - Primary field
                        - table_id (Single line text) 
                        - record_count (Number)
                        - field_count (Number)
                        - created_date (Date)
                        - last_updated (Date and time)
                        - description (Long text)
                        - primary_field (Single line text)
                        - field_types (Multiple select)
                        - data_quality_score (Number with 2 decimal places, 0-100 scale)
                        - usage_frequency (Single select: High, Medium, Low, Inactive)
                        - owner (Single line text)
                        - tags (Multiple select)
                        
                        Please create this table and confirm it was created successfully."""
                    }
                ],
                "session_id": f"metadata-test-{int(time.time())}"
            }
            
            headers = {
                "Content-Type": "application/json", 
                "X-API-Key": "pya_efe1764855b2300ebc87363fb26b71da645a1e6c"
            }
            
            logger.info(f"Testing metadata table creation...")
            
            async with session.post(chat_url, json=payload, headers=headers, timeout=60) as response:
                if response.status == 200:
                    data = await response.json()
                    response_text = data.get('response', '').lower()
                    
                    # Check for success indicators
                    success_indicators = [
                        'table.*created', 'successfully.*created', 'table_metadata.*created',
                        'created.*successfully', 'table.*added'
                    ]
                    
                    import re
                    success = any(re.search(pattern, response_text) for pattern in success_indicators)
                    
                    if success:
                        logger.info(f"✅ Metadata table creation appears successful")
                        return {
                            "status": "success",
                            "response": data,
                            "url": chat_url
                        }
                    else:
                        logger.warning(f"⚠️ Metadata table creation unclear - response: {response_text[:200]}")
                        return {
                            "status": "unclear",
                            "response": data,
                            "url": chat_url
                        }
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Metadata table creation failed: HTTP {response.status} - {error_text}")
                    return {
                        "status": "failed",
                        "error": f"HTTP {response.status}: {error_text}",
                        "url": chat_url
                    }
    except Exception as e:
        logger.error(f"❌ Metadata table creation error: {e}")
        return {
            "status": "error",
            "error": str(e),
            "url": f"{api_gateway_url}/api/chat"
        }

async def test_table_list():
    """Test getting list of tables"""
    config = get_config()
    api_gateway_url = config.services["api_gateway"].url
    
    try:
        import aiohttp
        async with aiohttp.ClientSession() as session:
            chat_url = f"{api_gateway_url}/api/chat"
            
            payload = {
                "messages": [
                    {
                        "role": "user",
                        "content": "Please list all tables in this Airtable base. For each table, show the table name, ID if available, and a brief description."
                    }
                ],
                "session_id": f"table-list-test-{int(time.time())}"
            }
            
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": "pya_efe1764855b2300ebc87363fb26b71da645a1e6c"
            }
            
            logger.info(f"Testing table list...")
            
            async with session.post(chat_url, json=payload, headers=headers, timeout=30) as response:
                if response.status == 200:
                    data = await response.json()
                    logger.info(f"✅ Table list request successful")
                    return {
                        "status": "success",
                        "response": data,
                        "url": chat_url
                    }
                else:
                    error_text = await response.text()
                    logger.error(f"❌ Table list failed: HTTP {response.status} - {error_text}")
                    return {
                        "status": "failed",
                        "error": f"HTTP {response.status}: {error_text}",
                        "url": chat_url
                    }
    except Exception as e:
        logger.error(f"❌ Table list error: {e}")
        return {
            "status": "error",
            "error": str(e),
            "url": f"{api_gateway_url}/api/chat"
        }

async def run_comprehensive_test():
    """Run comprehensive MCP test scenarios"""
    logger.info("Starting comprehensive MCP test scenarios")
    logger.info("="*80)
    
    results = {
        "test_run_id": f"mcp_test_{int(time.time())}",
        "timestamp": datetime.now().isoformat(),
        "tests": {}
    }
    
    # Test 1: Health Check
    logger.info("🏥 Running health check...")
    results["tests"]["health_check"] = await test_health_check()
    
    # Test 2: API Gateway Chat
    logger.info("💬 Testing API Gateway chat functionality...")
    results["tests"]["api_chat"] = await test_api_gateway_chat()
    
    # Test 3: MCP Tools
    logger.info("🔧 Testing MCP tools availability...")
    results["tests"]["mcp_tools"] = await test_mcp_tools()
    
    # Test 4: Table List
    logger.info("📋 Testing table list functionality...")
    results["tests"]["table_list"] = await test_table_list()
    
    # Test 5: Metadata Table Creation (if previous tests passed)
    health_ok = results["tests"]["health_check"].get("api_gateway", {}).get("status") == "healthy"
    chat_ok = results["tests"]["api_chat"].get("status") == "success"
    
    if health_ok and chat_ok:
        logger.info("🏗️ Testing metadata table creation...")
        results["tests"]["metadata_table_creation"] = await test_metadata_table_creation()
    else:
        logger.warning("⚠️ Skipping metadata table creation due to prerequisite failures")
        results["tests"]["metadata_table_creation"] = {
            "status": "skipped",
            "reason": "Prerequisites not met"
        }
    
    # Calculate summary
    total_tests = len(results["tests"])
    passed_tests = sum(1 for test in results["tests"].values() 
                      if isinstance(test, dict) and test.get("status") in ["success", "healthy"])
    
    results["summary"] = {
        "total_tests": total_tests,
        "passed_tests": passed_tests,
        "failed_tests": total_tests - passed_tests,
        "success_rate": passed_tests / total_tests if total_tests > 0 else 0
    }
    
    return results

def print_results(results):
    """Print formatted test results"""
    print("\n" + "="*80)
    print("MCP TOOLS COMPREHENSIVE TEST RESULTS")
    print("="*80)
    
    summary = results.get("summary", {})
    print(f"Test Run ID: {results.get('test_run_id', 'unknown')}")
    print(f"Timestamp: {results.get('timestamp', 'unknown')}")
    print(f"Total Tests: {summary.get('total_tests', 0)}")
    print(f"Passed: {summary.get('passed_tests', 0)}")
    print(f"Failed: {summary.get('failed_tests', 0)}")
    print(f"Success Rate: {summary.get('success_rate', 0):.1%}")
    
    print("\nDETAILED RESULTS:")
    print("-" * 80)
    
    for test_name, test_result in results.get("tests", {}).items():
        status = test_result.get("status", "unknown") if isinstance(test_result, dict) else "unknown"
        
        if status in ["success", "healthy"]:
            print(f"✅ {test_name.upper()}: PASSED")
        elif status == "skipped":
            print(f"⏭️ {test_name.upper()}: SKIPPED - {test_result.get('reason', 'No reason given')}")
        else:
            print(f"❌ {test_name.upper()}: FAILED")
            if isinstance(test_result, dict) and "error" in test_result:
                print(f"   Error: {test_result['error']}")
    
    print("="*80)

async def main():
    """Main entry point"""
    try:
        # Set environment variables for config
        import os
        os.environ['TEST_ENVIRONMENT'] = 'local'
        os.environ['AIRTABLE_TOKEN'] = 'patewow2oXotOdgpz.c7e78f8a5d17f20dfcbe7d32736dd06f56916af7e1549d88ed8f6791a2eaf654'
        os.environ['AIRTABLE_BASE'] = 'appVLUAubH5cFWhMV'
        os.environ['GEMINI_API_KEY'] = 'AIzaSyCwAGazN5GMCu03ZYLFWWTkdLRKFQb-OxU'
        
        # Run comprehensive tests
        results = await run_comprehensive_test()
        
        # Print results
        print_results(results)
        
        # Save results to file
        results_file = Path(f"mcp_test_results_{int(time.time())}.json")
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        logger.info(f"Test results saved to: {results_file}")
        
        # Return appropriate exit code
        success_rate = results.get("summary", {}).get("success_rate", 0)
        if success_rate >= 0.8:  # 80% success rate
            sys.exit(0)
        elif success_rate >= 0.5:  # 50% success rate
            sys.exit(1)
        else:
            sys.exit(2)
            
    except Exception as e:
        logger.error(f"Test execution failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(3)

if __name__ == "__main__":
    asyncio.run(main())