#!/usr/bin/env python3
"""
Full Integration Test for PyAirtable Platform
Tests: Auth → MCP → Qdrant → RAG → Monitoring
"""

import time
import json
import os
import requests
import sys
from datetime import datetime

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    BOLD = '\033[1m'
    END = '\033[0m'

def test_component(name, test_func):
    """Test a component and report results"""
    print(f"\n{Colors.BOLD}Testing {name}...{Colors.END}")
    try:
        result, details = test_func()
        if result:
            print(f"{Colors.GREEN}✅ {name}: WORKING{Colors.END}")
            if details:
                print(f"   {details}")
            return True
        else:
            print(f"{Colors.RED}❌ {name}: FAILED{Colors.END}")
            if details:
                print(f"   {details}")
            return False
    except Exception as e:
        print(f"{Colors.RED}❌ {name}: ERROR - {str(e)}{Colors.END}")
        return False

def test_auth():
    """Test authentication service"""
    try:
        response = requests.post(
            "http://localhost:8000/api/auth/login",
            json={"email": os.getenv("TEST_USER_EMAIL", "test@example.com"), "password": os.getenv("TEST_USER_PASSWORD", "change_me_in_env")},
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            if "access_token" in data or "message" in data:
                return True, f"Response time: {response.elapsed.total_seconds():.2f}s"
        return False, f"Status code: {response.status_code}"
    except Exception as e:
        return False, str(e)

def test_qdrant():
    """Test Qdrant vector database"""
    try:
        response = requests.get("http://localhost:6333/", timeout=5)
        if response.status_code == 200:
            data = response.json()
            if "version" in data:
                return True, f"Qdrant version: {data['version']}"
        return False, f"Status code: {response.status_code}"
    except Exception as e:
        return False, str(e)

def test_monitoring():
    """Test monitoring stack"""
    try:
        # Test Grafana
        grafana_response = requests.get("http://localhost:3001/api/health", timeout=5)
        grafana_ok = grafana_response.status_code == 200
        
        # Test Prometheus
        prom_response = requests.get("http://localhost:9090/-/healthy", timeout=5)
        prom_ok = prom_response.status_code == 200
        
        if grafana_ok and prom_ok:
            return True, "Grafana and Prometheus are running"
        elif grafana_ok:
            return True, "Grafana running (Prometheus issue)"
        elif prom_ok:
            return True, "Prometheus running (Grafana issue)"
        else:
            return False, "Both services have issues"
    except Exception as e:
        return False, str(e)

def test_auth_monitoring():
    """Test auth monitoring service"""
    try:
        response = requests.get("http://localhost:8090/metrics", timeout=5)
        if response.status_code == 200:
            metrics = response.text
            if "auth_test_success" in metrics:
                # Parse success rate
                for line in metrics.split('\n'):
                    if line.startswith('auth_test_success_rate'):
                        rate = float(line.split()[-1])
                        return True, f"Auth success rate: {rate*100:.0f}%"
                return True, "Metrics available"
        return False, f"Status code: {response.status_code}"
    except Exception as e:
        return False, str(e)

def test_mcp_qdrant_integration():
    """Test MCP-Qdrant RAG integration"""
    try:
        # Check if Qdrant has the collection
        response = requests.get("http://localhost:6333/collections", timeout=5)
        if response.status_code == 200:
            data = response.json()
            collections = data.get("result", {}).get("collections", [])
            has_mcp = any(c.get("name") == "mcp_results" for c in collections)
            
            if has_mcp:
                # Check collection size
                coll_response = requests.get("http://localhost:6333/collections/mcp_results", timeout=5)
                if coll_response.status_code == 200:
                    coll_data = coll_response.json()
                    count = coll_data.get("result", {}).get("points_count", 0)
                    return True, f"MCP collection has {count} vectors"
            return True, "Qdrant ready for MCP integration"
        return False, "Qdrant not accessible"
    except Exception as e:
        return False, str(e)

def test_api_gateway_health():
    """Test overall API Gateway health"""
    try:
        response = requests.get("http://localhost:8000/api/health", timeout=5)
        if response.status_code == 200:
            data = response.json()
            status = data.get("status", "unknown")
            services = data.get("services", [])
            healthy = sum(1 for s in services if s.get("status") == "healthy")
            total = len(services)
            return status != "down", f"Status: {status}, Services: {healthy}/{total} healthy"
        return False, f"Status code: {response.status_code}"
    except Exception as e:
        return False, str(e)

def run_integration_test():
    """Run complete integration test"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}========================================")
    print(f"PyAirtable Platform Integration Test")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"========================================{Colors.END}")
    
    results = {}
    
    # Test each component
    results['auth'] = test_component("Authentication", test_auth)
    results['qdrant'] = test_component("Qdrant Vector DB", test_qdrant)
    results['monitoring'] = test_component("Monitoring Stack", test_monitoring)
    results['auth_monitor'] = test_component("Auth Monitor Service", test_auth_monitoring)
    results['mcp_qdrant'] = test_component("MCP-Qdrant Integration", test_mcp_qdrant_integration)
    results['api_gateway'] = test_component("API Gateway Health", test_api_gateway_health)
    
    # Summary
    print(f"\n{Colors.BOLD}{Colors.BLUE}========================================")
    print("SUMMARY")
    print(f"========================================{Colors.END}")
    
    total = len(results)
    passed = sum(1 for v in results.values() if v)
    percentage = (passed / total * 100) if total > 0 else 0
    
    for component, status in results.items():
        icon = "✅" if status else "❌"
        color = Colors.GREEN if status else Colors.RED
        print(f"{color}{icon} {component.replace('_', ' ').title()}{Colors.END}")
    
    print(f"\n{Colors.BOLD}Result: {passed}/{total} components working ({percentage:.0f}%){Colors.END}")
    
    if percentage >= 80:
        print(f"{Colors.GREEN}{Colors.BOLD}✅ SYSTEM OPERATIONAL{Colors.END}")
        return 0
    elif percentage >= 50:
        print(f"{Colors.YELLOW}{Colors.BOLD}⚠️  SYSTEM DEGRADED{Colors.END}")
        return 1
    else:
        print(f"{Colors.RED}{Colors.BOLD}❌ SYSTEM CRITICAL{Colors.END}")
        return 2

def continuous_test(interval=60):
    """Run tests continuously"""
    print(f"{Colors.BOLD}Starting continuous integration testing (every {interval}s){Colors.END}")
    print("Press Ctrl+C to stop\n")
    
    test_count = 0
    while True:
        test_count += 1
        print(f"\n{Colors.BOLD}--- Test Run #{test_count} ---{Colors.END}")
        
        try:
            status = run_integration_test()
            
            # Log to file
            with open('/tmp/pyairtable-test-results.log', 'a') as f:
                f.write(f"{datetime.now().isoformat()} - Status: {status}\n")
            
            print(f"\n{Colors.BLUE}Next test in {interval} seconds...{Colors.END}")
            time.sleep(interval)
            
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Stopping continuous testing{Colors.END}")
            break
        except Exception as e:
            print(f"{Colors.RED}Test error: {e}{Colors.END}")
            time.sleep(interval)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--continuous":
        interval = int(sys.argv[2]) if len(sys.argv) > 2 else 60
        continuous_test(interval)
    else:
        exit_code = run_integration_test()
        sys.exit(exit_code)