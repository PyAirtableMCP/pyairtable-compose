#!/usr/bin/env python3
"""Test CORS configuration for SAGA orchestrator."""

import asyncio
import json
import requests
from typing import Dict, Any

def test_cors_preflight(url: str, origin: str) -> Dict[str, Any]:
    """Test CORS preflight request."""
    headers = {
        'Origin': origin,
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'Content-Type,Authorization,X-API-Key'
    }
    
    try:
        response = requests.options(url, headers=headers, timeout=10)
        return {
            'success': True,
            'status_code': response.status_code,
            'headers': dict(response.headers),
            'allowed_origin': response.headers.get('Access-Control-Allow-Origin'),
            'allowed_methods': response.headers.get('Access-Control-Allow-Methods'),
            'allowed_headers': response.headers.get('Access-Control-Allow-Headers'),
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def test_cors_request(url: str, origin: str) -> Dict[str, Any]:
    """Test actual CORS request."""
    headers = {
        'Origin': origin,
        'Content-Type': 'application/json'
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        return {
            'success': True,
            'status_code': response.status_code,
            'headers': dict(response.headers),
            'allowed_origin': response.headers.get('Access-Control-Allow-Origin'),
            'content': response.text[:200] if response.text else None
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def main():
    """Run CORS tests."""
    base_url = "http://localhost:8008"
    health_url = f"{base_url}/health"
    
    # Test origins
    test_origins = [
        "http://localhost:3000",
        "http://localhost:8000",
        "http://auth-service:8009",
        "http://user-service:8082",
        "https://example.com",  # Should be rejected
    ]
    
    print("🧪 Testing SAGA Orchestrator CORS Configuration")
    print("=" * 60)
    
    for origin in test_origins:
        print(f"\n🔍 Testing origin: {origin}")
        print("-" * 40)
        
        # Test preflight
        preflight_result = test_cors_preflight(health_url, origin)
        if preflight_result['success']:
            print(f"  ✅ Preflight: {preflight_result['status_code']}")
            print(f"  🌐 Allowed Origin: {preflight_result.get('allowed_origin', 'None')}")
            print(f"  📋 Allowed Methods: {preflight_result.get('allowed_methods', 'None')}")
            print(f"  📝 Allowed Headers: {preflight_result.get('allowed_headers', 'None')}")
        else:
            print(f"  ❌ Preflight failed: {preflight_result['error']}")
        
        # Test actual request
        request_result = test_cors_request(health_url, origin)
        if request_result['success']:
            print(f"  ✅ Request: {request_result['status_code']}")
            print(f"  🌐 Response Origin: {request_result.get('allowed_origin', 'None')}")
        else:
            print(f"  ❌ Request failed: {request_result['error']}")

if __name__ == "__main__":
    main()