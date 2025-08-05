#!/usr/bin/env python3
"""
Deployment Validation Test for PyAirtable
Tests basic connectivity and health of all deployed services
"""

import asyncio
import httpx
import json
import time
from typing import Dict, Any
import subprocess
import os

class DeploymentValidator:
    def __init__(self):
        self.services = {
            "airtable-gateway": {"port": 8002, "health_path": "/health"},
            "mcp-server": {"port": 8001, "health_path": "/health"},
            "llm-orchestrator": {"port": 8003, "health_path": "/health"},
            "platform-services": {"port": 8007, "health_path": "/health"},
            "automation-services": {"port": 8006, "health_path": "/health"}
        }
        self.port_forwards = []
        
    async def setup_port_forwarding(self):
        """Set up port forwarding for all services"""
        print("🔗 Setting up port forwarding...")
        
        for service, config in self.services.items():
            port = config["port"]
            cmd = f"kubectl port-forward -n pyairtable-dev service/{service} {port}:{port}"
            print(f"  Setting up port forward for {service} on port {port}")
            
            # Start port forwarding in background
            process = subprocess.Popen(
                cmd.split(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            self.port_forwards.append(process)
        
        # Wait for port forwards to establish
        print("  Waiting for port forwards to establish...")
        await asyncio.sleep(10)
        
    def cleanup_port_forwarding(self):
        """Clean up port forwarding processes"""
        print("🧹 Cleaning up port forwarding...")
        for process in self.port_forwards:
            process.terminate()
        
        # Also kill any existing port-forward processes
        subprocess.run(["pkill", "-f", "port-forward"], stderr=subprocess.DEVNULL)
        
    async def test_service_health(self, service_name: str, config: Dict[str, Any]) -> Dict[str, Any]:
        """Test health endpoint of a single service"""
        port = config["port"]
        health_path = config["health_path"]
        url = f"http://localhost:{port}{health_path}"
        
        result = {
            "service": service_name,
            "url": url,
            "status": "unknown",
            "response": None,
            "error": None,
            "response_time": None
        }
        
        try:
            start_time = time.time()
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(url)
                end_time = time.time()
                
                result["response_time"] = round((end_time - start_time) * 1000, 2)  # ms
                result["status"] = "healthy" if response.status_code == 200 else "unhealthy"
                result["response"] = response.json() if response.status_code == 200 else response.text
                
        except Exception as e:
            result["status"] = "error"
            result["error"] = str(e)
            
        return result
    
    async def test_kubernetes_pods(self) -> Dict[str, Any]:
        """Test Kubernetes pod status"""
        print("🔍 Checking Kubernetes pod status...")
        
        try:
            # Get pod status
            cmd = ["kubectl", "get", "pods", "-n", "pyairtable-dev", "-o", "json"]
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                pods_data = json.loads(result.stdout)
                pod_status = {}
                
                for pod in pods_data.get("items", []):
                    pod_name = pod["metadata"]["name"]
                    pod_phase = pod["status"]["phase"]
                    ready_conditions = [
                        condition for condition in pod["status"].get("conditions", [])
                        if condition["type"] == "Ready"
                    ]
                    is_ready = ready_conditions[0]["status"] == "True" if ready_conditions else False
                    
                    pod_status[pod_name] = {
                        "phase": pod_phase,
                        "ready": is_ready,
                        "restart_count": sum(
                            container.get("restartCount", 0)
                            for container in pod["status"].get("containerStatuses", [])
                        )
                    }
                
                return {"status": "success", "pods": pod_status}
            else:
                return {"status": "error", "error": result.stderr}
                
        except Exception as e:
            return {"status": "error", "error": str(e)}
    
    async def test_service_connectivity(self) -> Dict[str, Any]:
        """Test connectivity to platform services chat endpoint"""
        print("💬 Testing service-to-service connectivity...")
        
        try:
            url = "http://localhost:8007/api/chat"
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(url)
                
                return {
                    "status": "success" if response.status_code == 200 else "failed",
                    "response": response.json() if response.status_code == 200 else response.text,
                    "status_code": response.status_code
                }
        except Exception as e:
            return {"status": "error", "error": str(e)}
    
    async def run_validation(self) -> Dict[str, Any]:
        """Run complete deployment validation"""
        print("🚀 Starting PyAirtable Deployment Validation")
        print("=" * 60)
        
        start_time = time.time()
        
        # Set up port forwarding
        await self.setup_port_forwarding()
        
        try:
            # Test Kubernetes pods
            k8s_results = await self.test_kubernetes_pods()
            
            # Test service health
            print("🏥 Testing service health endpoints...")
            health_results = {}
            
            for service_name, config in self.services.items():
                result = await self.test_service_health(service_name, config)
                health_results[service_name] = result
                
                status_emoji = "✅" if result["status"] == "healthy" else "❌"
                print(f"  {status_emoji} {service_name}: {result['status']}")
                if result.get("response_time"):
                    print(f"     Response time: {result['response_time']}ms")
            
            # Test service connectivity
            connectivity_result = await self.test_service_connectivity()
            
            # Generate summary
            healthy_services = sum(1 for r in health_results.values() if r["status"] == "healthy")
            total_services = len(health_results)
            
            end_time = time.time()
            total_duration = round(end_time - start_time, 2)
            
            validation_result = {
                "timestamp": int(time.time()),
                "duration_seconds": total_duration,
                "kubernetes": k8s_results,
                "service_health": health_results,
                "service_connectivity": connectivity_result,
                "summary": {
                    "total_services": total_services,
                    "healthy_services": healthy_services,
                    "overall_status": "healthy" if healthy_services == total_services else "partial",
                    "success_rate": round((healthy_services / total_services) * 100, 1)
                }
            }
            
            return validation_result
            
        finally:
            self.cleanup_port_forwarding()
    
    def print_results(self, results: Dict[str, Any]):
        """Print validation results in a readable format"""
        print("\n" + "=" * 60)
        print("🎯 DEPLOYMENT VALIDATION RESULTS")
        print("=" * 60)
        
        # Overall status
        summary = results["summary"]
        status_emoji = "✅" if summary["overall_status"] == "healthy" else "⚠️"
        print(f"\n{status_emoji} Overall Status: {summary['overall_status'].upper()}")
        print(f"📊 Success Rate: {summary['success_rate']}% ({summary['healthy_services']}/{summary['total_services']} services)")
        print(f"⏱️  Validation Duration: {results['duration_seconds']}s")
        
        # Service details
        print(f"\n📋 Service Health Status:")
        for service, health in results["service_health"].items():
            status_emoji = "✅" if health["status"] == "healthy" else "❌"
            print(f"  {status_emoji} {service}: {health['status']}")
            if health.get("response_time"):
                print(f"     Response time: {health['response_time']}ms")
            if health.get("error"):
                print(f"     Error: {health['error']}")
        
        # Kubernetes status
        print(f"\n☸️  Kubernetes Pod Status:")
        k8s_status = results["kubernetes"]
        if k8s_status["status"] == "success":
            for pod_name, pod_info in k8s_status["pods"].items():
                ready_emoji = "✅" if pod_info["ready"] else "❌"
                print(f"  {ready_emoji} {pod_name}: {pod_info['phase']} (Ready: {pod_info['ready']})")
                if pod_info["restart_count"] > 0:
                    print(f"     Restarts: {pod_info['restart_count']}")
        else:
            print(f"  ❌ Error: {k8s_status['error']}")
        
        # Service connectivity
        print(f"\n🔗 Service Connectivity:")
        connectivity = results["service_connectivity"]
        if connectivity["status"] == "success":
            print(f"  ✅ Platform services chat endpoint: working")
        else:
            print(f"  ❌ Platform services chat endpoint: {connectivity.get('error', 'failed')}")
        
        # Recommendations
        print(f"\n💡 Next Steps:")
        if summary["overall_status"] == "healthy":
            print("  🎉 Deployment is healthy and ready for integration testing!")
            print("  🔬 Run full E2E tests with real API keys")
            print("  📊 Set up monitoring and observability")
        else:
            print("  🔧 Fix unhealthy services before proceeding")
            print("  📝 Check logs for failing services")
            print("  🔄 Consider redeploying failed components")


async def main():
    """Main validation function"""
    validator = DeploymentValidator()
    
    try:
        results = await validator.run_validation()
        validator.print_results(results)
        
        # Save results to file
        results_file = "tests/reports/deployment_validation_results.json"
        os.makedirs(os.path.dirname(results_file), exist_ok=True)
        
        with open(results_file, "w") as f:
            json.dump(results, f, indent=2)
        
        print(f"\n📄 Results saved to: {results_file}")
        
        # Return appropriate exit code
        return 0 if results["summary"]["overall_status"] == "healthy" else 1
        
    except Exception as e:
        print(f"\n❌ Validation failed with error: {e}")
        return 1


if __name__ == "__main__":
    import sys
    exit_code = asyncio.run(main())
    sys.exit(exit_code)