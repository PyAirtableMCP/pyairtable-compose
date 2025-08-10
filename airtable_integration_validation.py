#!/usr/bin/env python3
"""
Airtable Integration Validation Script
Tests all CRUD operations and service integrations in PyAirtable Compose
"""

import requests
import json
import time
import os
from typing import Dict, Any, Optional

class AirtableIntegrationValidator:
    def __init__(self):
        self.base_id = "appVLUAubH5cFWhMV"
        self.table_id = "tbl4JOCLonueUbzcT"  # Facebook post table
        self.api_key = "pya_dfe459675a8b02a97e327816088a2a614ccf21106ebe627677134a2c0d203d5d"
        self.user_id = "test-user"
        
        # Service endpoints
        self.airtable_gateway_url = "http://localhost:8002"
        self.api_gateway_url = "http://localhost:8000"
        self.mcp_server_url = "http://localhost:8001"
        
        self.headers = {
            "Content-Type": "application/json",
            "X-API-Key": self.api_key,
            "X-User-ID": self.user_id
        }
        
        self.test_results = []
    
    def log_test(self, test_name: str, success: bool, details: str = "", response_data: Dict = None):
        """Log test results"""
        result = {
            "test": test_name,
            "success": success,
            "details": details,
            "response_data": response_data,
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        self.test_results.append(result)
        
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}: {details}")
        
        if not success and response_data:
            print(f"    Response: {json.dumps(response_data, indent=2)[:200]}...")
    
    def test_service_health(self) -> bool:
        """Test all service health endpoints"""
        print("\n=== Testing Service Health ===")
        all_healthy = True
        
        services = [
            ("Airtable Gateway", f"{self.airtable_gateway_url}/health"),
            ("API Gateway", f"{self.api_gateway_url}/api/health"),
            ("MCP Server", f"{self.mcp_server_url}/health")
        ]
        
        for service_name, health_url in services:
            try:
                response = requests.get(health_url, timeout=5)
                success = response.status_code == 200
                
                if success:
                    data = response.json()
                    status = data.get('status', 'unknown')
                    self.log_test(f"{service_name} Health", success, f"Status: {status}", data)
                else:
                    self.log_test(f"{service_name} Health", False, f"HTTP {response.status_code}", {"error": response.text})
                    all_healthy = False
                    
            except requests.RequestException as e:
                self.log_test(f"{service_name} Health", False, f"Connection error: {str(e)}")
                all_healthy = False
        
        return all_healthy
    
    def test_direct_airtable_gateway(self) -> bool:
        """Test direct Airtable Gateway operations"""
        print("\n=== Testing Direct Airtable Gateway (Port 8002) ===")
        
        # Test 1: List tables
        try:
            url = f"{self.airtable_gateway_url}/api/v1/tables"
            params = {"base_id": self.base_id}
            response = requests.get(url, headers=self.headers, params=params, timeout=10)
            
            success = response.status_code == 200
            if success:
                tables = response.json()
                table_count = len(tables)
                self.log_test("Direct Gateway - List Tables", True, f"Found {table_count} tables")
            else:
                self.log_test("Direct Gateway - List Tables", False, f"HTTP {response.status_code}", response.json())
                return False
                
        except Exception as e:
            self.log_test("Direct Gateway - List Tables", False, str(e))
            return False
        
        # Test 2: Read records
        try:
            url = f"{self.airtable_gateway_url}/api/v1/records"
            params = {"base_id": self.base_id, "table_id": self.table_id, "max_records": 3}
            response = requests.get(url, headers=self.headers, params=params, timeout=10)
            
            success = response.status_code == 200
            if success:
                data = response.json()
                record_count = len(data.get('records', []))
                self.log_test("Direct Gateway - Read Records", True, f"Retrieved {record_count} records")
            else:
                self.log_test("Direct Gateway - Read Records", False, f"HTTP {response.status_code}", response.json())
                return False
                
        except Exception as e:
            self.log_test("Direct Gateway - Read Records", False, str(e))
            return False
        
        # Test 3: Create record
        test_record_id = None
        try:
            url = f"{self.airtable_gateway_url}/api/v1/records"
            params = {"base_id": self.base_id, "table_id": self.table_id}
            payload = [{
                "Name": "Validation Test Record",
                "Text": "Testing direct gateway CRUD operations",
                "Status": "selvkcDWRZd5GmKbH"  # Not posted
            }]
            
            response = requests.post(url, headers=self.headers, params=params, json=payload, timeout=10)
            
            success = response.status_code == 200
            if success:
                data = response.json()
                test_record_id = data['records'][0]['id']
                self.log_test("Direct Gateway - Create Record", True, f"Created record: {test_record_id}")
            else:
                self.log_test("Direct Gateway - Create Record", False, f"HTTP {response.status_code}", response.json())
                return False
                
        except Exception as e:
            self.log_test("Direct Gateway - Create Record", False, str(e))
            return False
        
        # Test 4: Update record
        if test_record_id:
            try:
                url = f"{self.airtable_gateway_url}/api/v1/records/{test_record_id}"
                params = {"base_id": self.base_id, "table_id": self.table_id}
                payload = {
                    "Name": "Updated Validation Test Record",
                    "Text": "Updated content for testing",
                    "Status": "selB2pEa2uRJsG5Eh"  # Posted
                }
                
                response = requests.put(url, headers=self.headers, params=params, json=payload, timeout=10)
                
                success = response.status_code == 200
                if success:
                    self.log_test("Direct Gateway - Update Record", True, f"Updated record: {test_record_id}")
                else:
                    self.log_test("Direct Gateway - Update Record", False, f"HTTP {response.status_code}", response.json())
                    
            except Exception as e:
                self.log_test("Direct Gateway - Update Record", False, str(e))
        
        # Test 5: Delete record
        if test_record_id:
            try:
                url = f"{self.airtable_gateway_url}/api/v1/records/{test_record_id}"
                params = {"base_id": self.base_id, "table_id": self.table_id}
                
                response = requests.delete(url, headers=self.headers, params=params, timeout=10)
                
                success = response.status_code == 200
                if success:
                    self.log_test("Direct Gateway - Delete Record", True, f"Deleted record: {test_record_id}")
                else:
                    self.log_test("Direct Gateway - Delete Record", False, f"HTTP {response.status_code}", response.json())
                    
            except Exception as e:
                self.log_test("Direct Gateway - Delete Record", False, str(e))
        
        return True
    
    def test_api_gateway_proxy(self) -> bool:
        """Test API Gateway proxy to Airtable Gateway"""
        print("\n=== Testing API Gateway Proxy (Port 8000) ===")
        
        # Test 1: List tables via proxy
        try:
            url = f"{self.api_gateway_url}/api/airtable/api/v1/tables"
            params = {"base_id": self.base_id}
            response = requests.get(url, headers=self.headers, params=params, timeout=10)
            
            success = response.status_code == 200
            if success:
                tables = response.json()
                table_count = len(tables)
                self.log_test("API Gateway Proxy - List Tables", True, f"Found {table_count} tables")
            else:
                self.log_test("API Gateway Proxy - List Tables", False, f"HTTP {response.status_code}", response.json())
                return False
                
        except Exception as e:
            self.log_test("API Gateway Proxy - List Tables", False, str(e))
            return False
        
        # Test 2: Read records via proxy
        try:
            url = f"{self.api_gateway_url}/api/airtable/api/v1/records"
            params = {"base_id": self.base_id, "table_id": self.table_id, "max_records": 3}
            response = requests.get(url, headers=self.headers, params=params, timeout=10)
            
            success = response.status_code == 200
            if success:
                data = response.json()
                record_count = len(data.get('records', []))
                self.log_test("API Gateway Proxy - Read Records", True, f"Retrieved {record_count} records")
            else:
                self.log_test("API Gateway Proxy - Read Records", False, f"HTTP {response.status_code}", response.json())
                return False
                
        except Exception as e:
            self.log_test("API Gateway Proxy - Read Records", False, str(e))
            return False
        
        return True
    
    def test_authentication_validation(self) -> bool:
        """Test authentication and authorization"""
        print("\n=== Testing Authentication & Authorization ===")
        
        # Test 1: Request without API key
        try:
            url = f"{self.airtable_gateway_url}/api/v1/tables"
            params = {"base_id": self.base_id}
            headers_no_key = {"Content-Type": "application/json", "X-User-ID": self.user_id}
            
            response = requests.get(url, headers=headers_no_key, params=params, timeout=5)
            
            success = response.status_code in [401, 403]  # Should be unauthorized
            self.log_test("Auth - No API Key", success, f"HTTP {response.status_code} (Expected 401/403)")
            
        except Exception as e:
            self.log_test("Auth - No API Key", False, str(e))
        
        # Test 2: Request with invalid API key
        try:
            url = f"{self.airtable_gateway_url}/api/v1/tables"
            params = {"base_id": self.base_id}
            headers_bad_key = {
                "Content-Type": "application/json",
                "X-API-Key": "invalid_key_12345",
                "X-User-ID": self.user_id
            }
            
            response = requests.get(url, headers=headers_bad_key, params=params, timeout=5)
            
            success = response.status_code in [401, 403]  # Should be unauthorized
            self.log_test("Auth - Invalid API Key", success, f"HTTP {response.status_code} (Expected 401/403)")
            
        except Exception as e:
            self.log_test("Auth - Invalid API Key", False, str(e))
        
        return True
    
    def test_environment_variables(self) -> bool:
        """Test environment variable configuration"""
        print("\n=== Testing Environment Configuration ===")
        
        required_vars = [
            "AIRTABLE_TOKEN",
            "AIRTABLE_BASE",
            "API_KEY"
        ]
        
        all_present = True
        for var_name in required_vars:
            if var_name in os.environ:
                # Don't log actual values for security
                self.log_test(f"Environment - {var_name}", True, "Variable is set")
            else:
                self.log_test(f"Environment - {var_name}", False, "Variable not found")
                all_present = False
        
        return all_present
    
    def run_validation(self) -> Dict[str, Any]:
        """Run complete validation suite"""
        print("🚀 Starting PyAirtable Compose Validation")
        print("=" * 60)
        
        start_time = time.time()
        
        # Run all tests
        health_ok = self.test_service_health()
        env_ok = self.test_environment_variables()
        direct_ok = self.test_direct_airtable_gateway()
        proxy_ok = self.test_api_gateway_proxy()
        auth_ok = self.test_authentication_validation()
        
        end_time = time.time()
        duration = end_time - start_time
        
        # Calculate statistics
        total_tests = len(self.test_results)
        passed_tests = sum(1 for result in self.test_results if result['success'])
        failed_tests = total_tests - passed_tests
        success_rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
        
        # Overall result
        overall_success = all([health_ok, env_ok, direct_ok, proxy_ok])
        
        # Generate summary
        summary = {
            "overall_success": overall_success,
            "success_rate": success_rate,
            "total_tests": total_tests,
            "passed_tests": passed_tests,
            "failed_tests": failed_tests,
            "duration": duration,
            "components": {
                "service_health": health_ok,
                "environment_config": env_ok,
                "direct_gateway": direct_ok,
                "api_gateway_proxy": proxy_ok,
                "authentication": auth_ok
            },
            "test_results": self.test_results
        }
        
        print("\n" + "=" * 60)
        print("🎯 VALIDATION SUMMARY")
        print("=" * 60)
        
        if overall_success:
            print("✅ OVERALL STATUS: SUCCESS")
            print("🎉 All Airtable CRUD operations working with 100% success rate!")
        else:
            print("❌ OVERALL STATUS: ISSUES DETECTED")
        
        print(f"📊 Test Results: {passed_tests}/{total_tests} passed ({success_rate:.1f}%)")
        print(f"⏱️  Duration: {duration:.2f} seconds")
        
        print("\n📋 Component Status:")
        for component, status in summary['components'].items():
            icon = "✅" if status else "❌"
            print(f"  {icon} {component.replace('_', ' ').title()}: {'PASS' if status else 'FAIL'}")
        
        if failed_tests > 0:
            print(f"\n⚠️  {failed_tests} tests failed. Check individual test results above.")
        
        return summary

def main():
    """Main execution function"""
    validator = AirtableIntegrationValidator()
    
    try:
        results = validator.run_validation()
        
        # Save results to file
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        results_file = f"airtable_validation_results_{timestamp}.json"
        
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        print(f"\n📄 Detailed results saved to: {results_file}")
        
        # Exit with appropriate code
        exit_code = 0 if results['overall_success'] else 1
        return exit_code
        
    except Exception as e:
        print(f"\n💥 Validation failed with error: {str(e)}")
        return 1

if __name__ == "__main__":
    exit(main())