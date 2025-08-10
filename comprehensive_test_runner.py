#!/usr/bin/env python3
"""
Comprehensive Testing Suite for PyAirtable
Executes systematic testing of all available services
"""
import asyncio
import json
import time
import os
import sys
import subprocess
import requests
from datetime import datetime
from typing import Dict, List, Any, Optional

class TestRunner:
    def __init__(self):
        self.results = {
            "test_start": datetime.now().isoformat(),
            "infrastructure": {},
            "services": {},
            "endpoints": {},
            "monitoring": {},
            "errors": [],
            "summary": {}
        }
        self.base_url = "http://localhost"
        
    def log(self, message: str, level: str = "INFO"):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")
        
    def test_infrastructure(self) -> Dict[str, Any]:
        """Test infrastructure services (PostgreSQL, Redis)"""
        self.log("Testing infrastructure services...")
        infrastructure_results = {}
        
        # Test PostgreSQL
        try:
            result = subprocess.run([
                "docker", "exec", "pyairtable-compose-postgres-1", 
                "pg_isready", "-U", "postgres"
            ], capture_output=True, text=True, timeout=10)
            
            infrastructure_results["postgresql"] = {
                "status": "healthy" if result.returncode == 0 else "unhealthy",
                "details": result.stdout.strip() if result.stdout else result.stderr.strip()
            }
        except Exception as e:
            infrastructure_results["postgresql"] = {
                "status": "error",
                "details": str(e)
            }
        
        # Test Redis
        try:
            result = subprocess.run([
                "docker", "exec", "pyairtable-compose-redis-1", 
                "redis-cli", "-a", "gxPAS8DaSRkm4hgy", "ping"
            ], capture_output=True, text=True, timeout=10)
            
            infrastructure_results["redis"] = {
                "status": "healthy" if "PONG" in result.stdout else "unhealthy",
                "details": result.stdout.strip() if result.stdout else result.stderr.strip()
            }
        except Exception as e:
            infrastructure_results["redis"] = {
                "status": "error", 
                "details": str(e)
            }
            
        self.results["infrastructure"] = infrastructure_results
        return infrastructure_results
    
    def test_docker_services(self) -> Dict[str, Any]:
        """Check Docker service status"""
        self.log("Checking Docker service status...")
        services_results = {}
        
        try:
            result = subprocess.run([
                "docker", "ps", "--filter", "name=pyairtable-compose", 
                "--format", "{{.Names}}:{{.Status}}"
            ], capture_output=True, text=True)
            
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    if ':' in line:
                        name, status = line.split(':', 1)
                        services_results[name.replace('pyairtable-compose-', '')] = {
                            "docker_status": status.strip(),
                            "container_name": name
                        }
        except Exception as e:
            services_results["error"] = str(e)
            
        self.results["services"] = services_results
        return services_results
    
    def test_service_endpoints(self) -> Dict[str, Any]:
        """Test service HTTP endpoints"""
        self.log("Testing service endpoints...")
        endpoints_results = {}
        
        services_to_test = [
            {"name": "airtable-gateway", "port": 8002, "health_path": "/health"},
            {"name": "mcp-server", "port": 8001, "health_path": "/health"},
            {"name": "llm-orchestrator", "port": 8003, "health_path": "/health"},
            {"name": "automation-services", "port": 8006, "health_path": "/health"},
            {"name": "saga-orchestrator", "port": 8008, "health_path": "/health"}
        ]
        
        for service in services_to_test:
            self.log(f"Testing {service['name']} on port {service['port']}")
            try:
                url = f"{self.base_url}:{service['port']}{service['health_path']}"
                response = requests.get(url, timeout=5)
                
                endpoints_results[service["name"]] = {
                    "status_code": response.status_code,
                    "response_time": response.elapsed.total_seconds(),
                    "healthy": response.status_code == 200,
                    "response": response.json() if response.headers.get('content-type', '').startswith('application/json') else response.text[:200]
                }
                
            except requests.exceptions.ConnectionError:
                endpoints_results[service["name"]] = {
                    "status": "connection_refused",
                    "healthy": False,
                    "error": "Service not accepting connections"
                }
            except requests.exceptions.Timeout:
                endpoints_results[service["name"]] = {
                    "status": "timeout",
                    "healthy": False,
                    "error": "Service response timeout"
                }
            except Exception as e:
                endpoints_results[service["name"]] = {
                    "status": "error",
                    "healthy": False,
                    "error": str(e)
                }
        
        self.results["endpoints"] = endpoints_results
        return endpoints_results
    
    def test_monitoring_services(self) -> Dict[str, Any]:
        """Test available monitoring services"""
        self.log("Testing monitoring services...")
        monitoring_results = {}
        
        monitoring_services = [
            {"name": "grafana-basic", "port": 3002, "path": "/api/health"},
            {"name": "prometheus-basic", "port": 9091, "path": "/api/v1/status/config"},
            {"name": "loki-basic", "port": 3101, "path": "/ready"}
        ]
        
        for service in monitoring_services:
            try:
                url = f"{self.base_url}:{service['port']}{service['path']}"
                response = requests.get(url, timeout=5)
                
                monitoring_results[service["name"]] = {
                    "status_code": response.status_code,
                    "healthy": response.status_code == 200,
                    "available": True
                }
                
            except Exception as e:
                monitoring_results[service["name"]] = {
                    "healthy": False,
                    "available": False,
                    "error": str(e)
                }
        
        self.results["monitoring"] = monitoring_results
        return monitoring_results
    
    def collect_service_logs(self) -> Dict[str, Any]:
        """Collect recent logs from services"""
        self.log("Collecting service logs...")
        logs_results = {}
        
        services = [
            "pyairtable-compose-airtable-gateway-1",
            "pyairtable-compose-mcp-server-1", 
            "pyairtable-compose-llm-orchestrator-1",
            "pyairtable-compose-automation-services-1",
            "pyairtable-compose-saga-orchestrator-1"
        ]
        
        for service in services:
            try:
                result = subprocess.run([
                    "docker", "logs", service, "--tail", "10"
                ], capture_output=True, text=True, timeout=10)
                
                logs_results[service] = {
                    "recent_logs": result.stdout[-500:] if result.stdout else result.stderr[-500:],
                    "has_errors": "error" in result.stderr.lower() or "failed" in result.stderr.lower()
                }
                
            except Exception as e:
                logs_results[service] = {
                    "error": str(e),
                    "has_errors": True
                }
        
        return logs_results
    
    def run_database_tests(self) -> Dict[str, Any]:
        """Test database connectivity and basic operations"""
        self.log("Testing database operations...")
        db_results = {}
        
        try:
            # Test basic SQL connection
            result = subprocess.run([
                "docker", "exec", "pyairtable-compose-postgres-1",
                "psql", "-U", "postgres", "-d", "pyairtable", "-c", "SELECT version();"
            ], capture_output=True, text=True, timeout=10)
            
            db_results["connection"] = {
                "successful": result.returncode == 0,
                "version_info": result.stdout.strip() if result.stdout else result.stderr.strip()
            }
            
            # Test table creation
            result = subprocess.run([
                "docker", "exec", "pyairtable-compose-postgres-1",
                "psql", "-U", "postgres", "-d", "pyairtable", "-c", 
                "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, created_at TIMESTAMP DEFAULT NOW());"
            ], capture_output=True, text=True, timeout=10)
            
            db_results["table_creation"] = {
                "successful": result.returncode == 0,
                "details": result.stderr.strip() if result.stderr else "Table created successfully"
            }
            
        except Exception as e:
            db_results["error"] = str(e)
            
        return db_results
    
    def generate_summary(self) -> Dict[str, Any]:
        """Generate test summary"""
        self.log("Generating test summary...")
        
        # Count healthy services
        healthy_infrastructure = sum(1 for service in self.results.get("infrastructure", {}).values() 
                                   if isinstance(service, dict) and service.get("status") == "healthy")
        total_infrastructure = len(self.results.get("infrastructure", {}))
        
        healthy_endpoints = sum(1 for endpoint in self.results.get("endpoints", {}).values()
                              if isinstance(endpoint, dict) and endpoint.get("healthy"))
        total_endpoints = len(self.results.get("endpoints", {}))
        
        healthy_monitoring = sum(1 for monitor in self.results.get("monitoring", {}).values()
                               if isinstance(monitor, dict) and monitor.get("healthy"))
        total_monitoring = len(self.results.get("monitoring", {}))
        
        summary = {
            "test_completion": datetime.now().isoformat(),
            "infrastructure_health": f"{healthy_infrastructure}/{total_infrastructure}",
            "endpoints_health": f"{healthy_endpoints}/{total_endpoints}",
            "monitoring_health": f"{healthy_monitoring}/{total_monitoring}",
            "overall_status": "PARTIAL" if (healthy_infrastructure + healthy_endpoints) > 0 else "FAILED",
            "recommendations": []
        }
        
        # Add recommendations
        if healthy_infrastructure < total_infrastructure:
            summary["recommendations"].append("Fix infrastructure services (PostgreSQL/Redis)")
        
        if healthy_endpoints == 0:
            summary["recommendations"].append("Investigate application service startup issues")
            summary["recommendations"].append("Check Docker logs for import/configuration errors")
        
        if healthy_monitoring < total_monitoring:
            summary["recommendations"].append("Verify monitoring stack configuration")
        
        self.results["summary"] = summary
        return summary
    
    def run_all_tests(self) -> Dict[str, Any]:
        """Run all tests and generate comprehensive report"""
        self.log("=== Starting PyAirtable Comprehensive Testing ===")
        
        # Run infrastructure tests
        self.test_infrastructure()
        
        # Check Docker services
        self.test_docker_services()
        
        # Test service endpoints
        self.test_service_endpoints()
        
        # Test monitoring
        self.test_monitoring_services()
        
        # Collect logs
        logs = self.collect_service_logs()
        self.results["logs"] = logs
        
        # Database tests
        db_results = self.run_database_tests()
        self.results["database"] = db_results
        
        # Generate summary
        self.generate_summary()
        
        # Save results to file
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"pyairtable_test_results_{timestamp}.json"
        
        with open(filename, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        self.log(f"=== Test Results Saved to {filename} ===")
        
        return self.results

def main():
    """Main execution"""
    runner = TestRunner()
    results = runner.run_all_tests()
    
    # Print summary
    print("\n" + "="*60)
    print("PYAIRTABLE TEST SUMMARY")
    print("="*60)
    summary = results.get("summary", {})
    
    print(f"Overall Status: {summary.get('overall_status', 'UNKNOWN')}")
    print(f"Infrastructure: {summary.get('infrastructure_health', 'N/A')}")
    print(f"Endpoints: {summary.get('endpoints_health', 'N/A')}")
    print(f"Monitoring: {summary.get('monitoring_health', 'N/A')}")
    
    if summary.get("recommendations"):
        print("\nRecommendations:")
        for rec in summary["recommendations"]:
            print(f"  • {rec}")
    
    print("="*60)
    
    return 0 if summary.get('overall_status') != 'FAILED' else 1

if __name__ == "__main__":
    sys.exit(main())