#!/usr/bin/env python3
"""
PyAirtable Performance Test Suite
Comprehensive performance testing for PyAirtable services
"""

import time
import requests
import statistics
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

class PyAirtablePerformanceTest:
    def __init__(self):
        self.services = {
            "mcp-server": "http://localhost:8001",
            "airtable-gateway": "http://localhost:8002", 
            "llm-orchestrator": "http://localhost:8003",
            "automation-services": "http://localhost:8006",
            "platform-services": "http://localhost:8007",
            "saga-orchestrator": "http://localhost:8008"
        }
        self.results = {}
        
    def test_health_endpoint_performance(self):
        """Test health endpoint response times across all services"""
        print("Testing health endpoint performance...")
        health_results = {}
        
        for service_name, base_url in self.services.items():
            try:
                start_time = time.time()
                response = requests.get(f"{base_url}/health", timeout=5)
                response_time = time.time() - start_time
                
                health_results[service_name] = {
                    "response_time_ms": round(response_time * 1000, 2),
                    "status_code": response.status_code,
                    "success": response.status_code == 200
                }
                print(f"  ✓ {service_name}: {response_time * 1000:.2f}ms")
                
            except Exception as e:
                health_results[service_name] = {
                    "response_time_ms": None,
                    "status_code": None,
                    "success": False,
                    "error": str(e)
                }
                print(f"  ✗ {service_name}: Failed - {e}")
                
        self.results["health_endpoints"] = health_results
        return health_results
    
    def test_concurrent_load(self):
        """Test services under concurrent load"""
        print("Testing concurrent load performance...")
        
        def make_health_request(service_name, base_url):
            start_time = time.time()
            try:
                response = requests.get(f"{base_url}/health", timeout=10)
                return {
                    "service": service_name,
                    "response_time": time.time() - start_time,
                    "status_code": response.status_code,
                    "success": response.status_code == 200
                }
            except Exception as e:
                return {
                    "service": service_name,
                    "response_time": time.time() - start_time,
                    "status_code": None,
                    "success": False,
                    "error": str(e)
                }
        
        # Test with 20 concurrent requests across all services
        with ThreadPoolExecutor(max_workers=20) as executor:
            futures = []
            for _ in range(4):  # 4 rounds of requests
                for service_name, base_url in self.services.items():
                    futures.append(
                        executor.submit(make_health_request, service_name, base_url)
                    )
            
            results = [future.result() for future in as_completed(futures)]
        
        # Analyze results
        load_test_results = {
            "total_requests": len(results),
            "successful_requests": sum(1 for r in results if r["success"]),
            "failed_requests": sum(1 for r in results if not r["success"]),
            "success_rate": sum(1 for r in results if r["success"]) / len(results) * 100,
            "average_response_time_ms": statistics.mean([r["response_time"] * 1000 for r in results]),
            "max_response_time_ms": max([r["response_time"] * 1000 for r in results]),
            "min_response_time_ms": min([r["response_time"] * 1000 for r in results])
        }
        
        self.results["concurrent_load"] = load_test_results
        print(f"  Success rate: {load_test_results['success_rate']:.1f}%")
        print(f"  Average response time: {load_test_results['average_response_time_ms']:.2f}ms")
        return load_test_results
    
    def test_api_endpoints(self):
        """Test specific API endpoints if available"""
        print("Testing API endpoint performance...")
        api_results = {}
        
        # Test platform services endpoints
        platform_endpoints = [
            "/auth/profile", "/analytics/metrics", "/gdpr/consent"
        ]
        
        for endpoint in platform_endpoints:
            try:
                start_time = time.time()
                response = requests.get(f"{self.services['platform-services']}{endpoint}", timeout=5)
                response_time = time.time() - start_time
                
                api_results[f"platform{endpoint}"] = {
                    "response_time_ms": round(response_time * 1000, 2),
                    "status_code": response.status_code,
                    "success": response.status_code in [200, 401, 403]  # Auth may require tokens
                }
                print(f"  Platform {endpoint}: {response_time * 1000:.2f}ms (HTTP {response.status_code})")
                
            except Exception as e:
                api_results[f"platform{endpoint}"] = {
                    "response_time_ms": None,
                    "status_code": None,
                    "success": False,
                    "error": str(e)
                }
                print(f"  Platform {endpoint}: Failed - {e}")
        
        self.results["api_endpoints"] = api_results
        return api_results
    
    def test_throughput(self):
        """Test service throughput over sustained period"""
        print("Testing sustained throughput...")
        
        def sustained_requests(duration_seconds=30):
            start_time = time.time()
            requests_made = 0
            successful_requests = 0
            response_times = []
            
            while time.time() - start_time < duration_seconds:
                request_start = time.time()
                try:
                    response = requests.get(f"{self.services['mcp-server']}/health", timeout=2)
                    response_time = time.time() - request_start
                    response_times.append(response_time)
                    
                    if response.status_code == 200:
                        successful_requests += 1
                        
                except Exception:
                    response_times.append(time.time() - request_start)
                
                requests_made += 1
                time.sleep(0.1)  # Small delay between requests
            
            return {
                "duration_seconds": duration_seconds,
                "total_requests": requests_made,
                "successful_requests": successful_requests,
                "requests_per_second": requests_made / duration_seconds,
                "success_rate": successful_requests / requests_made * 100,
                "average_response_time_ms": statistics.mean(response_times) * 1000
            }
        
        throughput_result = sustained_requests(15)  # 15 second test
        self.results["throughput"] = throughput_result
        
        print(f"  Requests per second: {throughput_result['requests_per_second']:.1f}")
        print(f"  Success rate: {throughput_result['success_rate']:.1f}%")
        
        return throughput_result
    
    def run_all_tests(self):
        """Run all performance tests"""
        print("=" * 60)
        print("PYAIRTABLE PERFORMANCE TEST SUITE")
        print("=" * 60)
        
        start_time = datetime.now()
        
        # Run all tests
        self.test_health_endpoint_performance()
        print()
        self.test_concurrent_load() 
        print()
        self.test_api_endpoints()
        print()
        self.test_throughput()
        
        end_time = datetime.now()
        self.results["test_duration"] = str(end_time - start_time)
        self.results["timestamp"] = start_time.isoformat()
        
        # Save results
        results_filename = f"performance_test_results_{start_time.strftime('%Y%m%d_%H%M%S')}.json"
        with open(results_filename, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        # Print summary
        self.print_summary()
        
        return self.results
    
    def print_summary(self):
        """Print performance test summary"""
        print("\n" + "=" * 60)
        print("PERFORMANCE TEST SUMMARY")
        print("=" * 60)
        
        # Health endpoint summary
        health_success = sum(1 for r in self.results["health_endpoints"].values() if r.get("success"))
        total_services = len(self.results["health_endpoints"])
        print(f"Health Endpoints: {health_success}/{total_services} services responding")
        
        # Concurrent load summary
        load_results = self.results["concurrent_load"]
        print(f"Concurrent Load: {load_results['success_rate']:.1f}% success rate")
        print(f"Average Response Time: {load_results['average_response_time_ms']:.2f}ms")
        
        # Throughput summary
        throughput = self.results["throughput"]
        print(f"Throughput: {throughput['requests_per_second']:.1f} req/sec")
        
        # Overall assessment
        overall_health = health_success / total_services * 100
        if overall_health >= 80 and load_results['success_rate'] >= 90:
            print("\n✅ SYSTEM PERFORMANCE: EXCELLENT")
        elif overall_health >= 60 and load_results['success_rate'] >= 75:
            print("\n⚠️  SYSTEM PERFORMANCE: GOOD")
        else:
            print("\n❌ SYSTEM PERFORMANCE: NEEDS ATTENTION")

if __name__ == "__main__":
    tester = PyAirtablePerformanceTest()
    tester.run_all_tests()