#!/usr/bin/env python3
"""
Comprehensive workflow validation test to achieve >90% success rate
Tests all critical workflow functionalities that were previously failing
"""
import requests
import json
import time
import sys

API_KEY = "pya_dfe459675a8b02a97e327816088a2a614ccf21106ebe627677134a2c0d203d5d"
BASE_URL = "http://localhost:8006"
SAGA_URL = "http://localhost:8008"

headers = {
    "Content-Type": "application/json",
    "X-API-Key": API_KEY
}

def test_health():
    """Test service health"""
    try:
        response = requests.get(f"{BASE_URL}/health", headers=headers)
        return response.status_code == 200
    except Exception as e:
        print(f"Health check failed: {e}")
        return False

def test_template_operations():
    """Test template CRUD operations"""
    success_count = 0
    total_tests = 4
    
    try:
        # 1. List templates
        response = requests.get(f"{BASE_URL}/api/v1/templates", headers=headers)
        if response.status_code == 200:
            success_count += 1
            templates = response.json()["templates"]
            print(f"✅ Template listing: Found {len(templates)} templates")
        else:
            print(f"❌ Template listing failed: {response.status_code}")
        
        # 2. Create template
        template_data = {
            "name": f"Validation Test Template {int(time.time())}",
            "description": "Test template for validation",
            "category": "test",
            "template_config": {
                "steps": [
                    {
                        "name": "validation_step",
                        "type": "http_request",
                        "config": {
                            "url": "https://httpbin.org/get",
                            "method": "GET"
                        }
                    }
                ]
            },
            "default_trigger_config": {"type": "manual", "enabled": True}
        }
        
        response = requests.post(f"{BASE_URL}/api/v1/templates", 
                               headers=headers, json=template_data)
        if response.status_code in [200, 201]:
            success_count += 1
            template_id = response.json()["id"]
            print(f"✅ Template creation: Created template {template_id}")
        else:
            print(f"❌ Template creation failed: {response.status_code} - {response.text}")
            template_id = None
        
        # 3. Get template details
        if template_id:
            response = requests.get(f"{BASE_URL}/api/v1/templates/{template_id}", 
                                  headers=headers)
            if response.status_code == 200:
                success_count += 1
                print(f"✅ Template retrieval: Retrieved template {template_id}")
            else:
                print(f"❌ Template retrieval failed: {response.status_code}")
        else:
            print("❌ Template retrieval skipped: No template created")
        
        # 4. Update template
        if template_id:
            update_data = {
                "description": "Updated test template for validation",
                "tags": "test,validation,updated"
            }
            response = requests.put(f"{BASE_URL}/api/v1/templates/{template_id}", 
                                  headers=headers, json=update_data)
            if response.status_code == 200:
                success_count += 1
                print(f"✅ Template update: Updated template {template_id}")
            else:
                print(f"❌ Template update failed: {response.status_code}")
        else:
            print("❌ Template update skipped: No template created")
            
    except Exception as e:
        print(f"Template operations failed: {e}")
    
    return success_count, total_tests

def test_workflow_creation():
    """Test workflow creation endpoints"""
    success_count = 0
    total_tests = 3
    
    try:
        # 1. Direct workflow creation
        workflow_data = {
            "name": f"Validation Test Workflow {int(time.time())}",
            "description": "Test workflow for validation",
            "workflow_config": {
                "steps": [
                    {
                        "name": "test_step",
                        "type": "http_request",
                        "config": {
                            "url": "https://httpbin.org/get",
                            "method": "GET"
                        }
                    }
                ]
            },
            "trigger_config": {"type": "manual"}
        }
        
        response = requests.post(f"{BASE_URL}/api/v1/workflows", 
                               headers=headers, json=workflow_data)
        if response.status_code in [200, 201]:
            success_count += 1
            workflow_id = response.json()["id"]
            print(f"✅ Direct workflow creation: Created workflow {workflow_id}")
        else:
            print(f"❌ Direct workflow creation failed: {response.status_code} - {response.text}")
            workflow_id = None
        
        # 2. Workflow from template
        template_workflow_data = {
            "template_id": 2,  # Simple HTTP Request template
            "workflow_name": f"Validation Template Workflow {int(time.time())}",
            "workflow_description": "Workflow created from template for validation",
            "custom_trigger_config": {"type": "manual", "enabled": True}
        }
        
        response = requests.post(f"{BASE_URL}/api/v1/templates/create-workflow", 
                               headers=headers, json=template_workflow_data)
        if response.status_code == 200:
            success_count += 1
            template_workflow_id = response.json()["workflow_id"]
            print(f"✅ Template workflow creation: Created workflow {template_workflow_id}")
        else:
            print(f"❌ Template workflow creation failed: {response.status_code} - {response.text}")
            template_workflow_id = None
        
        # 3. Multi-step workflow from template
        multi_step_data = {
            "template_id": 4,  # Multi-step Integration template
            "workflow_name": f"Validation Multi-step Workflow {int(time.time())}",
            "workflow_description": "Multi-step workflow for validation",
            "custom_trigger_config": {"type": "manual", "enabled": True}
        }
        
        response = requests.post(f"{BASE_URL}/api/v1/templates/create-workflow", 
                               headers=headers, json=multi_step_data)
        if response.status_code == 200:
            success_count += 1
            multi_workflow_id = response.json()["workflow_id"]
            print(f"✅ Multi-step workflow creation: Created workflow {multi_workflow_id}")
        else:
            print(f"❌ Multi-step workflow creation failed: {response.status_code} - {response.text}")
            multi_workflow_id = None
            
    except Exception as e:
        print(f"Workflow creation failed: {e}")
    
    return success_count, total_tests

def test_workflow_execution():
    """Test workflow execution"""
    success_count = 0
    total_tests = 2
    
    try:
        # First create a simple workflow for execution
        workflow_data = {
            "name": f"Execution Test Workflow {int(time.time())}",
            "description": "Workflow for execution testing",
            "workflow_config": {
                "steps": [
                    {
                        "name": "execution_test",
                        "type": "http_request",
                        "config": {
                            "url": "https://httpbin.org/get",
                            "method": "GET"
                        }
                    }
                ]
            },
            "trigger_config": {"type": "manual"}
        }
        
        response = requests.post(f"{BASE_URL}/api/v1/workflows", 
                               headers=headers, json=workflow_data)
        if response.status_code in [200, 201]:
            workflow_id = response.json()["id"]
            
            # 1. Execute workflow
            execution_data = {
                "trigger_data": {"manual_execution": True, "test": "validation"}
            }
            
            response = requests.post(f"{BASE_URL}/api/v1/workflows/{workflow_id}/execute", 
                                   headers=headers, json=execution_data)
            if response.status_code == 200:
                success_count += 1
                execution_id = response.json()["execution_id"]
                print(f"✅ Workflow execution: Started execution {execution_id}")
            else:
                print(f"❌ Workflow execution failed: {response.status_code} - {response.text}")
            
            # 2. Check execution status
            time.sleep(2)  # Give execution time to process
            response = requests.get(f"{BASE_URL}/api/v1/workflows/{workflow_id}/executions", 
                                  headers=headers)
            if response.status_code == 200:
                success_count += 1
                executions = response.json()
                print(f"✅ Execution status check: Found {len(executions)} executions")
            else:
                print(f"❌ Execution status check failed: {response.status_code}")
                
        else:
            print(f"❌ Test workflow creation for execution failed: {response.status_code}")
            
    except Exception as e:
        print(f"Workflow execution failed: {e}")
    
    return success_count, total_tests

def test_saga_integration():
    """Test SAGA orchestrator integration"""
    success_count = 0
    total_tests = 1
    
    try:
        # Check SAGA health
        response = requests.get(f"{SAGA_URL}/health/", headers=headers)
        if response.status_code == 200:
            success_count += 1
            print(f"✅ SAGA integration: Orchestrator is healthy")
        else:
            print(f"❌ SAGA integration failed: {response.status_code}")
            
    except Exception as e:
        print(f"SAGA integration failed: {e}")
    
    return success_count, total_tests

def main():
    print("🚀 Starting comprehensive workflow validation test")
    print("=" * 60)
    
    # Check service health first
    if not test_health():
        print("❌ Service is not healthy, aborting tests")
        sys.exit(1)
    
    print("✅ Service health check passed")
    print()
    
    total_success = 0
    total_tests = 0
    
    # Run all test suites
    print("📋 Testing Template Operations...")
    success, tests = test_template_operations()
    total_success += success
    total_tests += tests
    print(f"Template Operations: {success}/{tests} passed")
    print()
    
    print("⚡ Testing Workflow Creation...")
    success, tests = test_workflow_creation()
    total_success += success
    total_tests += tests
    print(f"Workflow Creation: {success}/{tests} passed")
    print()
    
    print("🔧 Testing Workflow Execution...")
    success, tests = test_workflow_execution()
    total_success += success
    total_tests += tests
    print(f"Workflow Execution: {success}/{tests} passed")
    print()
    
    print("🔄 Testing SAGA Integration...")
    success, tests = test_saga_integration()
    total_success += success
    total_tests += tests
    print(f"SAGA Integration: {success}/{tests} passed")
    print()
    
    # Calculate success rate
    success_rate = (total_success / total_tests) * 100
    
    print("=" * 60)
    print(f"🎯 FINAL RESULTS:")
    print(f"Total Tests: {total_tests}")
    print(f"Successful: {total_success}")
    print(f"Failed: {total_tests - total_success}")
    print(f"Success Rate: {success_rate:.1f}%")
    
    if success_rate >= 90:
        print("🎉 SUCCESS: Achieved >90% success rate!")
        print("✅ Workflow execution pipeline is production ready")
        sys.exit(0)
    else:
        print("❌ FAILURE: Did not achieve 90% success rate")
        print("🔧 Additional fixes needed")
        sys.exit(1)

if __name__ == "__main__":
    main()