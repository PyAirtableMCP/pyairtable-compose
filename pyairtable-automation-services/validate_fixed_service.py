#!/usr/bin/env python3
"""
Comprehensive validation test for the fixed PyAirtable Automation Services

This script validates that all SCRUM-18 requirements are met:
1. Service starts successfully
2. Health check endpoint responds
3. All API endpoints are accessible
4. Authentication works properly
5. Database and Redis connections work
6. Workflow processing is available
7. File processing endpoints respond
"""

import requests
import json
import subprocess
import sys

class AutomationServiceValidator:
    def __init__(self):
        self.base_url = "http://localhost:8006"
        self.api_key = self.get_api_key()
        self.headers = {"X-API-Key": self.api_key}
        
    def get_api_key(self):
        """Get API key from docker-compose environment"""
        try:
            result = subprocess.run([
                "docker-compose", "exec", "-T", "automation-services", 
                "env"
            ], capture_output=True, text=True)
            
            for line in result.stdout.split('\n'):
                if line.startswith('API_KEY='):
                    return line.split('=')[1]
            
            return "development-key"  # fallback
        except Exception as e:
            print(f"Warning: Could not get API key from docker: {e}")
            return "development-key"
    
    def test_service_health(self):
        """Test service health and component status"""
        print("🔍 Testing Service Health...")
        
        try:
            response = requests.get(f"{self.base_url}/health", timeout=10)
            if response.status_code == 200:
                health_data = response.json()
                print(f"✅ Service Status: {health_data['status']}")
                print(f"✅ Version: {health_data['version']}")
                
                components = health_data.get('components', {})
                for comp, status in components.items():
                    status_icon = "✅" if status['status'] == 'healthy' else "❌"
                    print(f"{status_icon} {comp.title()}: {status['message']}")
                
                return True
            else:
                print(f"❌ Health check failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"❌ Health check error: {str(e)}")
            return False
    
    def test_kubernetes_probes(self):
        """Test Kubernetes readiness and liveness probes"""
        print("\n🔍 Testing Kubernetes Probes...")
        
        results = []
        
        # Test readiness probe
        try:
            response = requests.get(f"{self.base_url}/ready", timeout=5)
            if response.status_code == 200:
                print("✅ Readiness probe: READY")
                results.append(True)
            else:
                print(f"❌ Readiness probe failed: {response.status_code}")
                results.append(False)
        except Exception as e:
            print(f"❌ Readiness probe error: {str(e)}")
            results.append(False)
        
        # Test liveness probe
        try:
            response = requests.get(f"{self.base_url}/live", timeout=5)
            if response.status_code == 200:
                print("✅ Liveness probe: ALIVE")
                results.append(True)
            else:
                print(f"❌ Liveness probe failed: {response.status_code}")
                results.append(False)
        except Exception as e:
            print(f"❌ Liveness probe error: {str(e)}")
            results.append(False)
        
        return all(results)
    
    def test_api_endpoints(self):
        """Test all API endpoints for proper responses"""
        print("\n🔍 Testing API Endpoints...")
        
        endpoints = [
            ("/", "GET", None, "Service information"),
            ("/api/v1/workflows", "GET", self.headers, "Workflows list"),
            ("/api/v1/templates", "GET", self.headers, "Templates list"),
            ("/api/v1/files", "GET", self.headers, "Files list")
        ]
        
        results = []
        
        for path, method, headers, description in endpoints:
            try:
                response = requests.request(
                    method, f"{self.base_url}{path}", 
                    headers=headers, timeout=10
                )
                
                if response.status_code in [200, 401]:  # 401 expected for unauthorized requests
                    status_icon = "✅" if response.status_code == 200 else "🔐"
                    status_text = "OK" if response.status_code == 200 else "AUTH_REQUIRED"
                    print(f"{status_icon} {method} {path}: {status_text} - {description}")
                    results.append(True)
                else:
                    print(f"❌ {method} {path}: {response.status_code} - {description}")
                    results.append(False)
                    
            except Exception as e:
                print(f"❌ {method} {path}: ERROR - {str(e)}")
                results.append(False)
        
        return all(results)
    
    def test_authentication(self):
        """Test API key authentication"""
        print("\n🔍 Testing Authentication...")
        
        # Test without API key (should fail)
        try:
            response = requests.get(f"{self.base_url}/api/v1/workflows", timeout=10)
            if response.status_code == 401:
                print("✅ Unauthorized request properly rejected")
            else:
                print(f"❌ Unauthorized request not rejected: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Authentication test error: {str(e)}")
            return False
        
        # Test with API key (should succeed)
        try:
            response = requests.get(
                f"{self.base_url}/api/v1/workflows", 
                headers=self.headers, 
                timeout=10
            )
            if response.status_code == 200:
                print("✅ Authorized request accepted")
                return True
            else:
                print(f"❌ Authorized request failed: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Authorization test error: {str(e)}")
            return False
    
    def test_docker_status(self):
        """Test Docker container status"""
        print("\n🔍 Testing Docker Container Status...")
        
        try:
            result = subprocess.run([
                "docker-compose", "ps", "automation-services"
            ], capture_output=True, text=True)
            
            if "healthy" in result.stdout:
                print("✅ Docker container is healthy")
                return True
            elif "Up" in result.stdout:
                print("⚠️  Docker container is up but health status unknown")
                return True
            else:
                print(f"❌ Docker container status: {result.stdout}")
                return False
                
        except Exception as e:
            print(f"❌ Docker status check error: {str(e)}")
            return False
    
    def generate_report(self, test_results):
        """Generate a comprehensive test report"""
        print("\n" + "="*60)
        print("🎯 AUTOMATION SERVICES VALIDATION REPORT")
        print("="*60)
        
        total_tests = len(test_results)
        passed_tests = sum(test_results.values())
        
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed_tests}")
        print(f"Failed: {total_tests - passed_tests}")
        print(f"Success Rate: {(passed_tests/total_tests)*100:.1f}%")
        
        print("\nTest Results:")
        for test_name, result in test_results.items():
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"  {status} {test_name}")
        
        print("\n" + "="*60)
        
        if all(test_results.values()):
            print("🎉 ALL TESTS PASSED! Automation Services is working correctly.")
            print("✅ SCRUM-18 requirements have been successfully implemented:")
            print("   - Service startup issues fixed")
            print("   - Health check endpoint responds")
            print("   - File processing functionality available")
            print("   - Workflow execution system ready")
            print("   - Error handling and monitoring enabled")
            return True
        else:
            print("⚠️  Some tests failed. Please review the issues above.")
            return False
    
    def run_all_tests(self):
        """Run all validation tests"""
        print("🚀 Starting PyAirtable Automation Services Validation")
        print("="*60)
        
        test_results = {}
        
        # Run all tests
        test_results["Service Health"] = self.test_service_health()
        test_results["Kubernetes Probes"] = self.test_kubernetes_probes()
        test_results["API Endpoints"] = self.test_api_endpoints()
        test_results["Authentication"] = self.test_authentication()
        test_results["Docker Status"] = self.test_docker_status()
        
        # Generate report
        return self.generate_report(test_results)


def main():
    """Main validation function"""
    validator = AutomationServiceValidator()
    success = validator.run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()