#!/usr/bin/env python3
"""
Test script to verify AIRTABLE_BASE configuration is working correctly
"""

import requests
import json
import time
import os
from typing import Dict, Any

# Configuration
BASE_URL = "http://localhost"
AIRTABLE_BASE = os.getenv("AIRTABLE_BASE", "appVLUAubH5cFWhMV")
API_KEY = os.getenv("API_KEY", "pya_d7f8e9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6")

# Service endpoints
SERVICES = {
    "api_gateway": {"port": 8000, "health": "/health"},
    "mcp_server": {"port": 8001, "health": "/health"},
    "airtable_gateway": {"port": 8002, "health": "/health"}, 
    "llm_orchestrator": {"port": 8003, "health": "/health"}
}

def check_service_health(service_name: str, service_info: Dict[str, Any]) -> bool:
    """Check if a service is healthy"""
    try:
        url = f"{BASE_URL}:{service_info['port']}{service_info['health']}"
        response = requests.get(url, timeout=5)
        if response.status_code == 200:
            print(f"✅ {service_name}: Healthy")
            return True
        else:
            print(f"❌ {service_name}: Unhealthy (status: {response.status_code})")
            return False
    except Exception as e:
        print(f"❌ {service_name}: Failed to connect - {str(e)}")
        return False

def test_mcp_list_tables_without_base_id():
    """Test MCP list_tables tool without providing base_id"""
    print("\n🧪 Testing MCP list_tables WITHOUT base_id (should use AIRTABLE_BASE)...")
    
    url = f"{BASE_URL}:8001/tools/call"
    headers = {
        "Content-Type": "application/json"
    }
    
    # Deliberately NOT providing base_id to test environment fallback
    data = {
        "name": "list_tables",
        "arguments": {}  # No base_id provided
    }
    
    try:
        response = requests.post(url, json=data, headers=headers, timeout=10)
        print(f"Response status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            result_text = str(result.get("result", [{}])[0].get("text", ""))
            
            # Check if it's an error asking for base_id
            if "error" in result_text.lower() and "base_id" in result_text.lower():
                print("❌ FAILED: Still asking for base_id despite AIRTABLE_BASE being set")
                print(f"Response: {json.dumps(result, indent=2)}")
                return False
            # Check if we got actual table data (indicating success)
            elif "table_count" in result_text and "tables" in result_text:
                print("✅ SUCCESS: Tool executed without requiring base_id - used AIRTABLE_BASE from environment!")
                print(f"Response preview: {result_text[:200]}...")
                return True
            else:
                print("❌ FAILED: Unexpected response")
                print(f"Response: {json.dumps(result, indent=2)}")
                return False
        else:
            print(f"❌ FAILED: Status code {response.status_code}")
            print(f"Response: {response.text[:500]}")
            return False
            
    except Exception as e:
        print(f"❌ FAILED: {str(e)}")
        return False

def test_mcp_list_tables_with_base_id():
    """Test MCP list_tables tool with explicit base_id"""
    print("\n🧪 Testing MCP list_tables WITH explicit base_id...")
    
    url = f"{BASE_URL}:8001/tools/call"
    headers = {
        "Content-Type": "application/json"
    }
    
    data = {
        "name": "list_tables",
        "arguments": {"base_id": AIRTABLE_BASE}
    }
    
    try:
        response = requests.post(url, json=data, headers=headers, timeout=10)
        print(f"Response status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("✅ SUCCESS: Tool executed with explicit base_id")
            print(f"Response: {json.dumps(result, indent=2)[:500]}...")
            return True
        else:
            print(f"❌ FAILED: Status code {response.status_code}")
            print(f"Response: {response.text[:500]}")
            return False
            
    except Exception as e:
        print(f"❌ FAILED: {str(e)}")
        return False

def test_llm_orchestrator_chat():
    """Test LLM orchestrator chat without providing base_id"""
    print("\n🧪 Testing LLM Orchestrator chat WITHOUT base_id...")
    
    url = f"{BASE_URL}:8003/chat"
    headers = {
        "Content-Type": "application/json"
    }
    
    data = {
        "message": "List all tables in my Airtable base",
        "session_id": "test-session-001"
    }
    
    try:
        response = requests.post(url, json=data, headers=headers, timeout=30)
        print(f"Response status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            response_text = result.get("response", "")
            
            if "base id" in response_text.lower() or "base_id" in response_text.lower():
                print("❌ FAILED: LLM is asking for base ID despite AIRTABLE_BASE being set")
                print(f"Response: {response_text}")
                return False
            else:
                print("✅ SUCCESS: LLM processed request without asking for base_id")
                print(f"Response: {response_text[:500]}...")
                return True
        else:
            print(f"❌ FAILED: Status code {response.status_code}")
            print(f"Response: {response.text[:500]}")
            return False
            
    except Exception as e:
        print(f"❌ FAILED: {str(e)}")
        return False

def check_environment_variables():
    """Check if environment variables are set"""
    print("\n🔍 Checking environment variables...")
    print(f"AIRTABLE_BASE: {AIRTABLE_BASE or 'NOT SET'}")
    print(f"API_KEY: {'SET' if API_KEY else 'NOT SET'}")
    
    # Check if services can see the env vars
    print("\n🔍 Checking service configurations...")
    
    # Check docker-compose env injection
    try:
        response = requests.get(f"{BASE_URL}:8001/api/v1/mcp/config", timeout=5)
        if response.status_code == 200:
            config = response.json()
            print(f"MCP Server config: {json.dumps(config, indent=2)}")
    except:
        print("Unable to fetch MCP server config (endpoint may not exist)")

def main():
    print("🚀 PyAirtable Base Configuration Test")
    print("=" * 50)
    
    # Check environment
    check_environment_variables()
    
    # Wait for services to be ready
    print("\n⏳ Waiting for services to start...")
    time.sleep(5)
    
    # Check service health
    print("\n🏥 Checking service health...")
    all_healthy = True
    for service_name, service_info in SERVICES.items():
        if not check_service_health(service_name, service_info):
            all_healthy = False
    
    if not all_healthy:
        print("\n⚠️  Some services are not healthy. Waiting 10 more seconds...")
        time.sleep(10)
    
    # Run tests
    print("\n🧪 Running configuration tests...")
    
    tests_passed = 0
    tests_total = 3
    
    # Test 1: MCP without base_id
    if test_mcp_list_tables_without_base_id():
        tests_passed += 1
    
    # Test 2: MCP with base_id
    if test_mcp_list_tables_with_base_id():
        tests_passed += 1
    
    # Test 3: LLM orchestrator
    if test_llm_orchestrator_chat():
        tests_passed += 1
    
    # Summary
    print("\n" + "=" * 50)
    print(f"📊 Test Results: {tests_passed}/{tests_total} passed")
    
    if tests_passed == tests_total:
        print("✅ All tests passed! AIRTABLE_BASE configuration is working correctly.")
    else:
        print("❌ Some tests failed. The system is still asking for base_id.")
        print("\nPossible issues:")
        print("1. Environment variables not passed to Docker containers")
        print("2. Services not reading AIRTABLE_BASE from environment")
        print("3. Tool schemas still requiring base_id as mandatory")
        print("4. Missing fallback logic in handlers")

if __name__ == "__main__":
    main()