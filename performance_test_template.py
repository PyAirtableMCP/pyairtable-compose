# PyAirtable Performance Test Suite
# Run with: pytest performance_tests.py

import time
import requests
import statistics
from concurrent.futures import ThreadPoolExecutor, as_completed

class TestPyAirtablePerformance:
    def setup_method(self):
        self.base_url = "http://localhost:3000"
        self.api_url = "http://localhost:8000"
    
    def test_page_load_performance(self):
        """Test page load times"""
        pages = [
            "/", "/login", "/dashboard", "/chat", "/workflows"
        ]
        
        load_times = {}
        for page in pages:
            start_time = time.time()
            response = requests.get(f"{self.base_url}{page}")
            load_time = time.time() - start_time
            
            load_times[page] = {
                "load_time_seconds": load_time,
                "status_code": response.status_code,
                "content_size": len(response.content)
            }
            
            # Assert load time is under 2 seconds
            assert load_time < 2.0, f"Page {page} loaded too slowly: {load_time}s"
    
    def test_api_response_times(self):
        """Test API endpoint response times"""
        endpoints = [
            "/api/health", "/api/auth/me", "/api/workflows", "/api/costs"
        ]
        
        for endpoint in endpoints:
            start_time = time.time()
            response = requests.get(f"{self.api_url}{endpoint}")
            response_time = time.time() - start_time
            
            # Assert response time is under 500ms
            assert response_time < 0.5, f"API {endpoint} too slow: {response_time}s"
    
    def test_concurrent_load(self):
        """Test system under concurrent load"""
        def make_request(url):
            start_time = time.time()
            response = requests.get(url)
            return time.time() - start_time, response.status_code
        
        # Test with 10 concurrent requests
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [
                executor.submit(make_request, f"{self.base_url}/")
                for _ in range(10)
            ]
            
            results = [future.result() for future in as_completed(futures)]
            
        # Check that all requests succeeded
        response_times = [result[0] for result in results]
        status_codes = [result[1] for result in results]
        
        assert all(code == 200 for code in status_codes), "Some requests failed"
        assert statistics.mean(response_times) < 1.0, "Average response time too high"
    
    def test_memory_usage(self):
        """Test for memory leaks during extended usage"""
        # This would require monitoring tools in a real implementation
        pass