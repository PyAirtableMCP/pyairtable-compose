#!/usr/bin/env python3
"""Debug script to find the base_id KeyError"""

import requests
import json

def test_mcp_direct():
    """Test MCP server directly to debug the error"""
    print("Testing MCP server list_tables tool...")
    
    # Test with empty arguments
    print("\n1. Testing with empty arguments object:")
    response = requests.post(
        "http://localhost:8001/tools/call",
        json={"name": "list_tables", "arguments": {}},
        headers={"Content-Type": "application/json"}
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    # Test with None arguments
    print("\n2. Testing with null arguments:")
    response = requests.post(
        "http://localhost:8001/tools/call",
        json={"name": "list_tables", "arguments": None},
        headers={"Content-Type": "application/json"}
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    # Test without arguments key
    print("\n3. Testing without arguments key:")
    response = requests.post(
        "http://localhost:8001/tools/call",
        json={"name": "list_tables"},
        headers={"Content-Type": "application/json"}
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")

if __name__ == "__main__":
    test_mcp_direct()