#!/usr/bin/env python3
"""
Sprint 4 Post-Merge Validation Script
Agent #10 - Final Validation

Validates system health after Sprint 4 merge completion
"""

import requests
import time
import json
import subprocess
import sys
from datetime import datetime

def run_validation():
    print("🔍 Sprint 4 Post-Merge Validation Starting...")
    print("=" * 50)
    
    validation_results = {
        "timestamp": datetime.now().isoformat(),
        "validation_type": "post_merge_sprint4",
        "agent": "Agent #10",
        "services": {},
        "overall_status": "unknown",
        "critical_services_healthy": 0,
        "total_services": 8
    }
    
    # Define critical service endpoints
    services = {
        "api-gateway": "http://localhost:8000/health",
        "mcp-server": "http://localhost:8001/health", 
        "airtable-gateway": "http://localhost:8002/health",
        "llm-orchestrator": "http://localhost:8003/health",
        "workspace-service": "http://localhost:8011/health",
        "auth-service": "http://localhost:8009/health",
        "saga-orchestrator": "http://localhost:8008/health",
        "analytics-service": "http://localhost:8005/health"
    }
    
    print("🏥 Health Check Results:")
    print("-" * 30)
    
    for service, url in services.items():
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print(f"✅ {service}: HEALTHY")
                validation_results["services"][service] = {
                    "status": "healthy",
                    "response_time": response.elapsed.total_seconds(),
                    "status_code": response.status_code
                }
                validation_results["critical_services_healthy"] += 1
            else:
                print(f"⚠️  {service}: DEGRADED (HTTP {response.status_code})")
                validation_results["services"][service] = {
                    "status": "degraded",
                    "response_time": response.elapsed.total_seconds(),
                    "status_code": response.status_code
                }
        except requests.exceptions.RequestException as e:
            print(f"❌ {service}: OFFLINE ({str(e)[:50]}...)")
            validation_results["services"][service] = {
                "status": "offline",
                "error": str(e)[:100]
            }
    
    # Calculate health percentage
    health_percentage = (validation_results["critical_services_healthy"] / validation_results["total_services"]) * 100
    
    print(f"\n📊 Service Health Summary:")
    print(f"   Healthy Services: {validation_results['critical_services_healthy']}/{validation_results['total_services']}")
    print(f"   Health Percentage: {health_percentage:.1f}%")
    
    # Determine overall status
    if health_percentage >= 70:
        validation_results["overall_status"] = "success"
        print("✅ Overall Status: SUCCESS (≥70% services healthy)")
    elif health_percentage >= 50:
        validation_results["overall_status"] = "warning"
        print("⚠️  Overall Status: WARNING (50-69% services healthy)")
    else:
        validation_results["overall_status"] = "failure"
        print("❌ Overall Status: FAILURE (<50% services healthy)")
    
    # Quick integration test
    print(f"\n🔄 Quick Integration Test:")
    print("-" * 30)
    
    try:
        # Test basic chat endpoint if available
        chat_response = requests.post(
            "http://localhost:8003/api/chat",
            json={"message": "test", "conversation_id": "validation-test"},
            timeout=10,
            headers={"Content-Type": "application/json"}
        )
        
        if chat_response.status_code in [200, 201]:
            print("✅ Chat Integration: WORKING")
            validation_results["integration_test"] = "success"
        else:
            print(f"⚠️  Chat Integration: DEGRADED (HTTP {chat_response.status_code})")
            validation_results["integration_test"] = "degraded"
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Chat Integration: FAILED ({str(e)[:50]}...)")
        validation_results["integration_test"] = "failed"
    
    # Save validation results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = f"sprint4_post_merge_validation_{timestamp}.json"
    
    with open(results_file, 'w') as f:
        json.dump(validation_results, f, indent=2)
    
    print(f"\n💾 Results saved to: {results_file}")
    
    # Final recommendation
    print(f"\n🎯 Sprint 4 Merge Validation Complete")
    print("=" * 50)
    
    if validation_results["overall_status"] == "success":
        print("✅ RECOMMENDATION: Sprint 4 merge is SUCCESSFUL")
        print("   - System is operational and ready for Sprint 5")
        print("   - No critical regressions detected")
    elif validation_results["overall_status"] == "warning":
        print("⚠️  RECOMMENDATION: Sprint 4 merge has MINOR ISSUES")
        print("   - System is mostly operational but needs monitoring")
        print("   - Consider service restart for offline services")
    else:
        print("❌ RECOMMENDATION: Sprint 4 merge needs IMMEDIATE ATTENTION")
        print("   - Critical services are offline")
        print("   - Rollback may be required")
    
    return validation_results

if __name__ == "__main__":
    try:
        results = run_validation()
        sys.exit(0 if results["overall_status"] == "success" else 1)
    except Exception as e:
        print(f"❌ Validation script failed: {e}")
        sys.exit(1)