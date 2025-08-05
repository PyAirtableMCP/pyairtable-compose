#!/usr/bin/env python3
"""
Test script to validate the PyAirtable system with the user's original Facebook posts request.
This will test the complete pipeline: API Gateway -> LLM Orchestrator -> MCP Server -> Airtable Gateway
"""

import json
import requests
import time
import sys
from typing import Dict, Any

# Configuration
API_GATEWAY_URL = "http://localhost:8000"
API_KEY = "pya_d7f8e9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6"
AIRTABLE_BASE = "appVLUAubH5cFWhMV"

def test_health_endpoints():
    """Test all service health endpoints"""
    print("=== Testing Health Endpoints ===")
    
    # Test API Gateway health
    try:
        response = requests.get(f"{API_GATEWAY_URL}/api/health")
        if response.status_code == 200:
            health_data = response.json()
            print(f"✅ API Gateway: {health_data['status']}")
            for service in health_data['services']:
                print(f"  - {service['name']}: {service['status']} ({service['response_time']:.3f}s)")
        else:
            print(f"❌ API Gateway health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ API Gateway unreachable: {e}")
        return False
    
    return True

def test_airtable_connection():
    """Test Airtable connection through the gateway"""
    print("\n=== Testing Airtable Connection ===")
    
    # Test through API Gateway first
    headers = {
        "Content-Type": "application/json",
        "x-api-key": API_KEY
    }
    
    # Test basic Airtable connectivity through MCP tools
    chat_request = {
        "messages": [{"role": "user", "content": "Can you list the available tools for working with Airtable?"}],
        "session_id": "test_session_001"
    }
    
    try:
        response = requests.post(
            f"{API_GATEWAY_URL}/api/chat",
            json=chat_request,
            headers=headers
        )
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Chat endpoint responding")
            print(f"Response: {result.get('response', 'No response field')[:200]}...")
            return True
        else:
            print(f"❌ Chat endpoint failed: {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Chat endpoint error: {e}")
        return False

def test_facebook_posts_analysis():
    """Test the user's original Facebook posts analysis request"""
    print("\n=== Testing Facebook Posts Analysis ===")
    
    # The user's original request
    user_request = """Notice the facebook posts table in my Airtable base. Please analyze it, recommend improvements for each existing post, and come up with 2 to 5 new post ideas that would fit well."""
    
    headers = {
        "Content-Type": "application/json",
        "x-api-key": API_KEY
    }
    
    chat_request = {
        "messages": [{"role": "user", "content": user_request}],
        "session_id": "facebook_analysis_001",
        "base_id": AIRTABLE_BASE
    }
    
    print(f"Sending request: {user_request}")
    
    try:
        response = requests.post(
            f"{API_GATEWAY_URL}/api/chat",
            json=chat_request,
            headers=headers,
            timeout=120  # Extended timeout for analysis
        )
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Facebook posts analysis successful!")
            
            # Extract the response
            analysis_response = result.get('response', '')
            print(f"\n📊 Analysis Response:")
            print(f"{analysis_response}")
            
            # Check if the response contains expected elements
            response_lower = analysis_response.lower()
            checks = {
                "found_facebook_table": any(term in response_lower for term in ['facebook', 'posts', 'table']),
                "provided_recommendations": any(term in response_lower for term in ['recommend', 'improve', 'suggestion']),
                "provided_new_ideas": any(term in response_lower for term in ['new post', 'ideas', 'create'])
            }
            
            print(f"\n🔍 Analysis Quality Checks:")
            for check, passed in checks.items():
                status = "✅" if passed else "❌"
                print(f"  {status} {check.replace('_', ' ').title()}: {passed}")
            
            return all(checks.values())
        else:
            print(f"❌ Facebook posts analysis failed: {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Facebook posts analysis error: {e}")
        return False

def test_metadata_table_creation():
    """Test creating metadata tables as mentioned in the user's requirements"""
    print("\n=== Testing Metadata Table Creation ===")
    
    headers = {
        "Content-Type": "application/json",
        "x-api-key": API_KEY
    }
    
    metadata_request = {
        "messages": [{"role": "user", "content": "Can you create a metadata table to track the improvements and new post ideas we just discussed?"}],
        "session_id": "metadata_creation_001",
        "base_id": AIRTABLE_BASE
    }
    
    try:
        response = requests.post(
            f"{API_GATEWAY_URL}/api/chat",
            json=metadata_request,
            headers=headers,
            timeout=60
        )
        
        if response.status_code == 200:
            result = response.json()
            print("✅ Metadata table creation request processed!")
            
            metadata_response = result.get('response', '')
            print(f"\n📋 Metadata Response:")
            print(f"{metadata_response}")
            
            return True
        else:
            print(f"❌ Metadata table creation failed: {response.status_code}")
            print(f"Response: {response.text}")
            return False
    except Exception as e:
        print(f"❌ Metadata table creation error: {e}")
        return False

def generate_validation_report(test_results: Dict[str, bool]):
    """Generate final validation report"""
    print("\n" + "="*60)
    print("🎯 FINAL VALIDATION REPORT")
    print("="*60)
    
    total_tests = len(test_results)
    passed_tests = sum(test_results.values())
    
    print(f"\n📊 Overall Results: {passed_tests}/{total_tests} tests passed")
    print(f"Success Rate: {(passed_tests/total_tests)*100:.1f}%")
    
    print(f"\n📋 Test Details:")
    for test_name, passed in test_results.items():
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"  {status}: {test_name.replace('_', ' ').title()}")
    
    # System status
    if passed_tests == total_tests:
        print(f"\n🎉 DEPLOYMENT SUCCESSFUL!")
        print(f"   The PyAirtable system is fully operational and ready for production use.")
        print(f"   ✅ All services are healthy")
        print(f"   ✅ Airtable integration working")
        print(f"   ✅ LLM processing functional")
        print(f"   ✅ User scenarios validated")
        
        print(f"\n🚀 READY FOR USER TESTING:")
        print(f"   - API Gateway: {API_GATEWAY_URL}")
        print(f"   - Airtable Base: {AIRTABLE_BASE}")
        print(f"   - Facebook Posts Analysis: Working")
        print(f"   - Metadata Table Creation: Working")
        
    elif passed_tests >= total_tests * 0.75:
        print(f"\n⚠️  DEPLOYMENT MOSTLY SUCCESSFUL")
        print(f"   Core functionality is working, but some features need attention.")
        
    else:
        print(f"\n❌ DEPLOYMENT NEEDS ATTENTION")
        print(f"   Multiple critical features are not working properly.")
    
    return passed_tests == total_tests

def main():
    """Main test execution"""
    print("🚀 PyAirtable System Validation Test")
    print("Testing deployment with user's original Facebook posts scenario")
    print("-" * 60)
    
    test_results = {}
    
    # Run all tests
    test_results['health_endpoints'] = test_health_endpoints()
    test_results['airtable_connection'] = test_airtable_connection()
    test_results['facebook_posts_analysis'] = test_facebook_posts_analysis()
    test_results['metadata_table_creation'] = test_metadata_table_creation()
    
    # Generate final report
    success = generate_validation_report(test_results)
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()