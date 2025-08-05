#\!/usr/bin/env python3
"""
Validation script to verify AIRTABLE_BASE environment variable fix
Validates the code changes without requiring external dependencies
"""

import os
import re
from pathlib import Path

def validate_mcp_server():
    """Validate MCP server implementation"""
    print("🔍 Validating MCP Server...")
    
    # Check config loads AIRTABLE_BASE
    config_file = Path("/Users/kg/IdeaProjects/mcp-server-py/src/config.py")
    if not config_file.exists():
        print("❌ Config file not found")
        return False
    
    config_content = config_file.read_text()
    if 'AIRTABLE_BASE = os.getenv("AIRTABLE_BASE")' not in config_content:
        print("❌ Config doesn't load AIRTABLE_BASE from environment")
        return False
    
    print("✅ Config loads AIRTABLE_BASE from environment")
    
    # Check handlers use fallback
    handlers_dir = Path("/Users/kg/IdeaProjects/mcp-server-py/src/handlers")
    handler_files = [
        "record_handlers.py",
        "table_handlers.py", 
        "analysis_handlers.py",
        "utility_handlers.py"
    ]
    
    for handler_file in handler_files:
        handler_path = handlers_dir / handler_file
        if not handler_path.exists():
            print(f"❌ Handler file {handler_file} not found")
            return False
        
        content = handler_path.read_text()
        
        # Check for proper fallback pattern
        fallback_pattern = r'base_id = arguments\.get\("base_id"\) or AIRTABLE_BASE'
        if not re.search(fallback_pattern, content):
            print(f"❌ {handler_file} doesn't use proper base_id fallback")
            return False
        
        # Check for proper error message
        error_pattern = r'No base ID provided and no default AIRTABLE_BASE configured'
        if not re.search(error_pattern, content):
            print(f"❌ {handler_file} doesn't have proper error message")
            return False
        
        print(f"✅ {handler_file} properly implements base_id fallback")
    
    # Check tool schemas mark base_id as optional
    server_file = Path("/Users/kg/IdeaProjects/mcp-server-py/src/server.py")
    if not server_file.exists():
        print("❌ Server file not found")
        return False
    
    server_content = server_file.read_text()
    
    # Check that base_id is not in required arrays (except for sync_tables which needs specific base IDs)
    required_pattern = r'"required":\s*\[[^\]]*"base_id"[^\]]*\]'
    required_matches = re.findall(required_pattern, server_content)
    
    # Filter out sync_tables which legitimately requires base_id parameters
    non_sync_required = [m for m in required_matches if 'sync_tables' not in server_content[server_content.find(m)-200:server_content.find(m)+200]]
    
    if non_sync_required:
        print(f"❌ Found {len(non_sync_required)} tools that still require base_id")
        return False
    
    print("✅ Tool schemas properly mark base_id as optional")
    
    return True

def validate_llm_orchestrator():
    """Validate LLM orchestrator implementation"""
    print("\n🔍 Validating LLM Orchestrator...")
    
    function_calling_file = Path("/Users/kg/IdeaProjects/llm-orchestrator-py/src/chat/function_calling.py")
    if not function_calling_file.exists():
        print("❌ Function calling file not found")
        return False
    
    content = function_calling_file.read_text()
    
    # Check imports os
    if 'import os' not in content:
        print("❌ Missing 'import os' statement")
        return False
    
    # Check uses environment variable fallback
    fallback_pattern = r'os\.getenv\("AIRTABLE_BASE"\)'
    if not re.search(fallback_pattern, content):
        print("❌ Doesn't use os.getenv('AIRTABLE_BASE') fallback")
        return False
    
    # Check updated error message mentions environment variable
    error_pattern = r'set the AIRTABLE_BASE environment variable'
    if not re.search(error_pattern, content):
        print("❌ Error message doesn't mention AIRTABLE_BASE environment variable")
        return False
    
    print("✅ LLM Orchestrator properly uses environment variable fallback")
    return True

def validate_pyairtable_ai():
    """Validate PyAirtable AI implementation"""
    print("\n🔍 Validating PyAirtable AI...")
    
    # Check config loads from environment
    config_file = Path("/Users/kg/IdeaProjects/pyairtable-ai/src/config.py")
    if not config_file.exists():
        print("❌ Config file not found")
        return False
    
    config_content = config_file.read_text()
    if 'airtable_base: str = ""' not in config_content:
        print("❌ Config doesn't define airtable_base field")
        return False
    
    print("✅ Config defines airtable_base field for environment loading")
    
    # Check tool executor uses fallback
    tool_executor_file = Path("/Users/kg/IdeaProjects/pyairtable-ai/src/services/tool_executor.py")
    if not tool_executor_file.exists():
        print("❌ Tool executor file not found")
        return False
    
    executor_content = tool_executor_file.read_text()
    
    # Check for proper fallback pattern in multiple tools
    fallback_pattern = r'args\.get\("base_id"\) or self\.settings\.airtable_base'
    fallback_matches = re.findall(fallback_pattern, executor_content)
    
    if len(fallback_matches) < 3:  # Should be in multiple airtable tools
        print(f"❌ Tool executor doesn't have enough base_id fallback implementations (found {len(fallback_matches)})")
        return False
    
    # Check for proper error messages
    error_pattern = r'No base ID provided and no default AIRTABLE_BASE configured'
    if not re.search(error_pattern, executor_content):
        print("❌ Tool executor doesn't have proper error messages")
        return False
    
    print("✅ Tool executor properly uses environment variable fallback")
    return True

def main():
    """Run all validations"""
    print("🧪 Validating AIRTABLE_BASE environment variable fix")
    print("=" * 60)
    
    results = []
    
    # Validate each service
    results.append(validate_mcp_server())
    results.append(validate_llm_orchestrator())
    results.append(validate_pyairtable_ai())
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 VALIDATION SUMMARY")
    print("=" * 60)
    
    passed = sum(results)
    total = len(results)
    
    if passed == total:
        print(f"✅ ALL VALIDATIONS PASSED ({passed}/{total})")
        print("\n🎉 Code properly implements AIRTABLE_BASE environment variable fallback!")
        print("   Key improvements:")
        print("   • MCP Server handlers use environment variable when base_id not provided")
        print("   • LLM Orchestrator checks environment variable before asking user")
        print("   • PyAirtable AI loads base_id from settings (populated from env)")
        print("   • Tool schemas mark base_id as optional where appropriate")
        print("   • Error messages guide users to set environment variable")
        
        print(f"\n🚀 Users can now set: export AIRTABLE_BASE=appVLUAubH5cFWhMV")
        print("   And avoid specifying base_id in every request!")
        return True
    else:
        print(f"❌ VALIDATIONS FAILED ({passed}/{total})")
        return False

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)