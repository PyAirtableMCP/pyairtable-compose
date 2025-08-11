#!/usr/bin/env python3
"""Test SAGA orchestrator service health and basic functionality."""

import requests
import json
from typing import Dict, Any

def test_service_health(base_url: str = "http://localhost:8008") -> Dict[str, Any]:
    """Test service health endpoint."""
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        return {
            'success': True,
            'status_code': response.status_code,
            'response': response.json() if response.headers.get('content-type', '').startswith('application/json') else response.text
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def test_service_endpoints(base_url: str = "http://localhost:8008") -> Dict[str, Any]:
    """Test various service endpoints."""
    endpoints = [
        "/health",
        "/sagas",
        "/events",
        "/metrics",
    ]
    
    results = {}
    for endpoint in endpoints:
        try:
            response = requests.get(f"{base_url}{endpoint}", timeout=10)
            results[endpoint] = {
                'success': True,
                'status_code': response.status_code,
                'content_type': response.headers.get('content-type', ''),
                'response_size': len(response.content)
            }
        except Exception as e:
            results[endpoint] = {
                'success': False,
                'error': str(e)
            }
    
    return results

def main():
    """Run service tests."""
    base_url = "http://localhost:8008"
    
    print("🏥 Testing SAGA Orchestrator Service Health")
    print("=" * 50)
    
    # Test health endpoint
    health_result = test_service_health(base_url)
    if health_result['success']:
        print(f"✅ Health check passed: {health_result['status_code']}")
        print(f"📋 Response: {json.dumps(health_result['response'], indent=2)}")
    else:
        print(f"❌ Health check failed: {health_result['error']}")
        print("🔍 Make sure the SAGA orchestrator is running on port 8008")
        return
    
    print("\n🔍 Testing Service Endpoints")
    print("-" * 30)
    
    # Test endpoints
    endpoint_results = test_service_endpoints(base_url)
    for endpoint, result in endpoint_results.items():
        if result['success']:
            status_icon = "✅" if result['status_code'] < 400 else "⚠️"
            print(f"{status_icon} {endpoint}: {result['status_code']} ({result['content_type']})")
        else:
            print(f"❌ {endpoint}: {result['error']}")

if __name__ == "__main__":
    main()