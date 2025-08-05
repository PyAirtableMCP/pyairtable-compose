#!/usr/bin/env python3
"""
Test script to verify AIRTABLE_BASE environment variable fix
Tests all three services to ensure they properly use the environment variable as fallback
"""

import os
import sys
import json
import asyncio
import tempfile
from pathlib import Path

# Test configuration
TEST_BASE_ID = "appVLUAubH5cFWhMV"  # From the provided environment variable

def setup_test_env():
    """Setup test environment with AIRTABLE_BASE"""
    os.environ["AIRTABLE_BASE"] = TEST_BASE_ID
    print(f"✅ Set AIRTABLE_BASE environment variable to: {TEST_BASE_ID}")

async def test_mcp_server_handlers():
    """Test MCP server handlers use environment variable fallback"""
    print("\n🔍 Testing MCP Server handlers...")
    
    try:
        # Add MCP server to path
        mcp_server_path = Path("/Users/kg/IdeaProjects/mcp-server-py/src")
        sys.path.insert(0, str(mcp_server_path))
        
        from config import AIRTABLE_BASE
        from handlers.record_handlers import handle_create_record
        from handlers.table_handlers import handle_list_tables
        from handlers.analysis_handlers import handle_analyze_table_data
        from handlers.utility_handlers import handle_search_records
        
        # Test environment variable is loaded correctly
        assert AIRTABLE_BASE == TEST_BASE_ID, f"Expected {TEST_BASE_ID}, got {AIRTABLE_BASE}"
        print(f"✅ MCP Server config loads AIRTABLE_BASE: {AIRTABLE_BASE}")
        
        # Test handlers work without base_id parameter
        test_cases = [
            ("handle_list_tables", handle_list_tables, {}),
            ("handle_analyze_table_data", handle_analyze_table_data, {"table_id": "tblTest"}),
            ("handle_search_records", handle_search_records, {"table_id": "tblTest", "query": "test"}),
        ]
        
        for handler_name, handler_func, test_args in test_cases:
            try:
                result = await handler_func(test_args)
                # We expect these to fail with actual API calls, but they should not fail with base_id error
                result_text = result[0].text if result else ""
                
                if "No base ID provided and no default AIRTABLE_BASE configured" in result_text:
                    print(f"❌ {handler_name}: Still asking for base_id despite environment variable")
                    return False
                else:
                    print(f"✅ {handler_name}: Properly uses environment variable fallback")
            except Exception as e:
                # Expected to fail with API calls, but not with base_id errors
                error_msg = str(e)
                if "base_id" in error_msg.lower() and "required" in error_msg.lower():
                    print(f"❌ {handler_name}: base_id error - {error_msg}")
                    return False
                else:
                    print(f"✅ {handler_name}: No base_id errors (API error expected: {type(e).__name__})")
        
        return True
        
    except Exception as e:
        print(f"❌ MCP Server test failed: {e}")
        return False

async def test_llm_orchestrator():
    """Test LLM orchestrator uses environment variable"""
    print("\n🔍 Testing LLM Orchestrator...")
    
    try:
        # Add LLM orchestrator to path
        llm_path = Path("/Users/kg/IdeaProjects/llm-orchestrator-py/src")
        sys.path.insert(0, str(llm_path))
        
        from chat.function_calling import FunctionCallManager
        
        # Create mock MCP client
        class MockMCPClient:
            async def get_tools(self):
                return []
            
            async def call_tool(self, name, args):
                return {"test": "result"}
        
        # Test without configuration
        manager = FunctionCallManager(MockMCPClient(), {})
        result = await manager._handle_tool_request_legacy("list tables", [])
        
        # Should not ask for base ID since environment variable is set
        if "I need your Airtable base ID" in result:
            print(f"❌ LLM Orchestrator: Still asking for base_id despite environment variable")
            return False
        else:
            print(f"✅ LLM Orchestrator: Properly uses environment variable fallback")
            return True
            
    except Exception as e:
        print(f"❌ LLM Orchestrator test failed: {e}")
        return False

async def test_pyairtable_ai():
    """Test PyAirtable AI service uses environment variable"""
    print("\n🔍 Testing PyAirtable AI...")
    
    try:
        # Add PyAirtable AI to path
        ai_path = Path("/Users/kg/IdeaProjects/pyairtable-ai/src")
        sys.path.insert(0, str(ai_path))
        
        from config import get_settings
        from services.tool_executor import ToolExecutor
        from models.mcp import ToolCall
        
        # Test settings load environment variable
        settings = get_settings()
        if not settings.airtable_base:
            print(f"❌ PyAirtable AI: Settings don't load AIRTABLE_BASE environment variable")
            return False
        
        assert settings.airtable_base == TEST_BASE_ID, f"Expected {TEST_BASE_ID}, got {settings.airtable_base}"
        print(f"✅ PyAirtable AI settings load AIRTABLE_BASE: {settings.airtable_base}")
        
        # Test tool executor uses fallback
        executor = ToolExecutor()
        await executor.initialize()
        
        # Create test tool call without base_id
        tool_call = ToolCall(
            id="test-1",
            tool="airtable_get_schema",
            arguments={"table_id": "tblTest"}  # No base_id provided
        )
        
        try:
            result = await executor.execute(tool_call)
            # We expect this to fail with API error, but not base_id error
            if result.error and "No base ID provided and no default AIRTABLE_BASE configured" in result.error:
                print(f"❌ PyAirtable AI: Tool executor not using environment variable")
                return False
            else:
                print(f"✅ PyAirtable AI: Tool executor properly uses environment variable fallback")
                return True
        except Exception as e:
            # API errors are expected, base_id errors are not
            error_msg = str(e)
            if "base_id" in error_msg.lower() and "required" in error_msg.lower():
                print(f"❌ PyAirtable AI: base_id error - {error_msg}")
                return False
            else:
                print(f"✅ PyAirtable AI: No base_id errors (API error expected: {type(e).__name__})")
                return True
        finally:
            await executor.close()
            
    except Exception as e:
        print(f"❌ PyAirtable AI test failed: {e}")
        return False

async def main():
    """Run all tests"""
    print("🧪 Testing AIRTABLE_BASE environment variable fix across all services")
    print("=" * 70)
    
    # Setup test environment
    setup_test_env()
    
    # Run tests
    results = []
    
    # Test each service
    results.append(await test_mcp_server_handlers())
    results.append(await test_llm_orchestrator())
    results.append(await test_pyairtable_ai())
    
    # Summary
    print("\n" + "=" * 70)
    print("📊 TEST SUMMARY")
    print("=" * 70)
    
    passed = sum(results)
    total = len(results)
    
    if passed == total:
        print(f"✅ ALL TESTS PASSED ({passed}/{total})")
        print("\n🎉 AIRTABLE_BASE environment variable is properly configured across all services!")
        print(f"   Users can now set AIRTABLE_BASE={TEST_BASE_ID} and avoid specifying base_id repeatedly")
        return True
    else:
        print(f"❌ TESTS FAILED ({passed}/{total})")
        print("\n❗ Some services still require base_id parameter even when environment variable is set")
        return False

if __name__ == "__main__":
    success = asyncio.run(main())
    sys.exit(0 if success else 1)