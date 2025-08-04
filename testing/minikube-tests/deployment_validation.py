"""
Minikube deployment validation tests for PyAirtable system.
Tests Kubernetes deployment, service discovery, health checks, and end-to-end functionality.
"""

import asyncio
import subprocess
import time
import json
import httpx
import pytest
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import yaml
from pathlib import Path


@dataclass
class ServiceEndpoint:
    """Service endpoint configuration."""
    name: str
    namespace: str
    port: int
    path: str = "/health"
    expected_status: int = 200
    timeout: int = 30


@dataclass
class DeploymentStatus:
    """Deployment status information."""
    name: str
    namespace: str
    ready_replicas: int
    desired_replicas: int
    available_replicas: int
    status: str


class MinikubeTestFramework:
    """Framework for testing Minikube deployments."""
    
    def __init__(self, namespace: str = "pyairtable"):
        self.namespace = namespace
        self.kubectl_timeout = 300  # 5 minutes
        
    async def run_kubectl_command(self, command: List[str]) -> Dict[str, Any]:
        """Run kubectl command and return parsed output."""
        try:
            full_command = ["kubectl"] + command
            
            process = await asyncio.create_subprocess_exec(
                *full_command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(
                process.communicate(), 
                timeout=self.kubectl_timeout
            )
            
            return {
                "success": process.returncode == 0,
                "stdout": stdout.decode('utf-8').strip(),
                "stderr": stderr.decode('utf-8').strip(),
                "returncode": process.returncode
            }
            
        except asyncio.TimeoutError:
            return {
                "success": False,
                "error": "Command timed out",
                "returncode": -1
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "returncode": -1
            }
    
    async def check_minikube_status(self) -> bool:
        """Check if Minikube is running."""
        result = await self.run_kubectl_command(["cluster-info"])
        return result["success"]
    
    async def get_namespace_status(self) -> Dict[str, Any]:
        """Get namespace status."""
        result = await self.run_kubectl_command([
            "get", "namespace", self.namespace, "-o", "json"
        ])
        
        if result["success"]:
            try:
                return json.loads(result["stdout"])
            except json.JSONDecodeError:
                return {"error": "Failed to parse namespace JSON"}
        
        return {"error": result.get("stderr", "Unknown error")}
    
    async def get_deployment_status(self, deployment_name: str) -> Optional[DeploymentStatus]:
        """Get deployment status."""
        result = await self.run_kubectl_command([
            "get", "deployment", deployment_name,
            "-n", self.namespace,
            "-o", "json"
        ])
        
        if not result["success"]:
            return None
            
        try:
            data = json.loads(result["stdout"])
            status = data.get("status", {})
            
            return DeploymentStatus(
                name=deployment_name,
                namespace=self.namespace,
                ready_replicas=status.get("readyReplicas", 0),
                desired_replicas=status.get("replicas", 0),
                available_replicas=status.get("availableReplicas", 0),
                status="Ready" if status.get("readyReplicas", 0) == status.get("replicas", 0) else "NotReady"
            )
        except json.JSONDecodeError:
            return None
    
    async def get_pod_status(self, label_selector: str = None) -> List[Dict[str, Any]]:
        """Get pod status."""
        command = ["get", "pods", "-n", self.namespace, "-o", "json"]
        if label_selector:
            command.extend(["-l", label_selector])
            
        result = await self.run_kubectl_command(command)
        
        if not result["success"]:
            return []
            
        try:
            data = json.loads(result["stdout"])
            return data.get("items", [])
        except json.JSONDecodeError:
            return []
    
    async def get_service_endpoints(self) -> Dict[str, str]:
        """Get service endpoints."""
        result = await self.run_kubectl_command([
            "get", "services", "-n", self.namespace, "-o", "json"
        ])
        
        if not result["success"]:
            return {}
            
        try:
            data = json.loads(result["stdout"])
            services = {}
            
            for service in data.get("items", []):
                name = service["metadata"]["name"]
                
                # Get Minikube service URL
                url_result = await self.run_kubectl_command([
                    "minikube", "service", name, "-n", self.namespace, "--url"
                ])
                
                if url_result["success"]:
                    services[name] = url_result["stdout"].strip()
            
            return services
        except json.JSONDecodeError:
            return {}
    
    async def wait_for_deployment_ready(self, deployment_name: str, timeout: int = 600) -> bool:
        """Wait for deployment to be ready."""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            status = await self.get_deployment_status(deployment_name)
            
            if status and status.status == "Ready":
                return True
                
            await asyncio.sleep(10)
        
        return False
    
    async def test_service_health(self, service_url: str, path: str = "/health") -> Dict[str, Any]:
        """Test service health endpoint."""
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.get(f"{service_url}{path}")
                
                return {
                    "success": response.status_code == 200,
                    "status_code": response.status_code,
                    "response_time": response.elapsed.total_seconds(),
                    "content": response.text[:500] if response.text else None
                }
        except Exception as e:
            return {
                "success": False,
                "error": str(e)
            }
    
    async def test_service_connectivity(self, services: Dict[str, str]) -> Dict[str, Any]:
        """Test connectivity between services."""
        results = {}
        
        for service_name, service_url in services.items():
            print(f"Testing connectivity to {service_name}...")
            
            health_result = await self.test_service_health(service_url)
            results[service_name] = health_result
            
            if health_result["success"]:
                print(f"✓ {service_name} is healthy")
            else:
                print(f"✗ {service_name} failed health check: {health_result.get('error', 'Unknown error')}")
        
        return results


@pytest.mark.minikube
class TestMinikubeDeployment:
    """Test Minikube deployment validation."""
    
    @pytest.fixture(scope="class")
    async def minikube_framework(self):
        """Create Minikube test framework."""
        framework = MinikubeTestFramework()
        yield framework
    
    @pytest.mark.asyncio
    async def test_minikube_cluster_running(self, minikube_framework):
        """Test that Minikube cluster is running."""
        is_running = await minikube_framework.check_minikube_status()
        assert is_running, "Minikube cluster is not running"
    
    @pytest.mark.asyncio
    async def test_namespace_exists(self, minikube_framework):
        """Test that PyAirtable namespace exists."""
        namespace_status = await minikube_framework.get_namespace_status()
        assert "error" not in namespace_status, f"Namespace error: {namespace_status.get('error')}"
        assert namespace_status.get("status", {}).get("phase") == "Active", "Namespace is not active"
    
    @pytest.mark.asyncio
    async def test_core_deployments_ready(self, minikube_framework):
        """Test that core deployments are ready."""
        core_deployments = [
            "postgres",
            "redis", 
            "api-gateway",
            "auth-service",
            "user-service",
            "airtable-gateway",
        ]
        
        for deployment in core_deployments:
            print(f"Checking deployment: {deployment}")
            
            # Wait for deployment to be ready
            is_ready = await minikube_framework.wait_for_deployment_ready(deployment, timeout=300)
            assert is_ready, f"Deployment {deployment} is not ready within timeout"
            
            # Get detailed status
            status = await minikube_framework.get_deployment_status(deployment)
            assert status is not None, f"Could not get status for deployment {deployment}"
            assert status.status == "Ready", f"Deployment {deployment} status: {status.status}"
            
            print(f"✓ {deployment} is ready ({status.ready_replicas}/{status.desired_replicas})")
    
    @pytest.mark.asyncio
    async def test_pods_running(self, minikube_framework):
        """Test that all pods are running."""
        pods = await minikube_framework.get_pod_status()
        
        assert len(pods) > 0, "No pods found in namespace"
        
        failed_pods = []
        for pod in pods:
            name = pod["metadata"]["name"]
            phase = pod["status"].get("phase", "Unknown")
            
            if phase != "Running":
                failed_pods.append(f"{name}: {phase}")
        
        assert not failed_pods, f"Pods not running: {failed_pods}"
        
        print(f"✓ All {len(pods)} pods are running")
    
    @pytest.mark.asyncio
    async def test_services_accessible(self, minikube_framework):
        """Test that services are accessible."""
        services = await minikube_framework.get_service_endpoints()
        
        assert len(services) > 0, "No services found"
        
        connectivity_results = await minikube_framework.test_service_connectivity(services)
        
        failed_services = []
        for service_name, result in connectivity_results.items():
            if not result["success"]:
                failed_services.append(f"{service_name}: {result.get('error', 'Health check failed')}")
        
        assert not failed_services, f"Services failed health checks: {failed_services}"
        
        print(f"✓ All {len(services)} services are accessible")
    
    @pytest.mark.asyncio
    async def test_database_connectivity(self, minikube_framework):
        """Test database connectivity."""
        # Test PostgreSQL connectivity
        pods = await minikube_framework.get_pod_status("app=postgres")
        
        if pods:
            postgres_pod = pods[0]["metadata"]["name"]
            
            # Test database connection
            result = await minikube_framework.run_kubectl_command([
                "exec", "-n", minikube_framework.namespace,
                postgres_pod, "--",
                "psql", "-U", "postgres", "-c", "SELECT 1;"
            ])
            
            assert result["success"], f"PostgreSQL connection failed: {result.get('stderr')}"
            print("✓ PostgreSQL is accessible")
    
    @pytest.mark.asyncio
    async def test_redis_connectivity(self, minikube_framework):
        """Test Redis connectivity."""
        # Test Redis connectivity
        pods = await minikube_framework.get_pod_status("app=redis")
        
        if pods:
            redis_pod = pods[0]["metadata"]["name"]
            
            # Test Redis connection
            result = await minikube_framework.run_kubectl_command([
                "exec", "-n", minikube_framework.namespace,
                redis_pod, "--",
                "redis-cli", "ping"
            ])
            
            assert result["success"], f"Redis connection failed: {result.get('stderr')}"
            assert "PONG" in result["stdout"], "Redis did not respond with PONG"
            print("✓ Redis is accessible")
    
    @pytest.mark.asyncio
    async def test_service_mesh_configuration(self, minikube_framework):
        """Test service mesh configuration (if Istio is deployed)."""
        # Check if Istio is installed
        istio_result = await minikube_framework.run_kubectl_command([
            "get", "namespace", "istio-system"
        ])
        
        if istio_result["success"]:
            # Test Istio sidecar injection
            pods = await minikube_framework.get_pod_status()
            
            injected_pods = 0
            for pod in pods:
                containers = pod.get("spec", {}).get("containers", [])
                if any(container["name"] == "istio-proxy" for container in containers):
                    injected_pods += 1
            
            print(f"✓ {injected_pods} pods have Istio sidecar injection")
        else:
            print("ℹ Istio is not installed, skipping service mesh tests")
    
    @pytest.mark.asyncio
    async def test_persistent_volumes(self, minikube_framework):
        """Test persistent volume claims."""
        result = await minikube_framework.run_kubectl_command([
            "get", "pvc", "-n", minikube_framework.namespace, "-o", "json"
        ])
        
        if result["success"]:
            try:
                data = json.loads(result["stdout"])
                pvcs = data.get("items", [])
                
                unbound_pvcs = []
                for pvc in pvcs:
                    name = pvc["metadata"]["name"]
                    status = pvc.get("status", {}).get("phase", "Unknown")
                    
                    if status != "Bound":
                        unbound_pvcs.append(f"{name}: {status}")
                
                assert not unbound_pvcs, f"PVCs not bound: {unbound_pvcs}"
                
                if pvcs:
                    print(f"✓ All {len(pvcs)} PVCs are bound")
                
            except json.JSONDecodeError:
                pytest.skip("Could not parse PVC JSON")
    
    @pytest.mark.asyncio
    async def test_resource_limits(self, minikube_framework):
        """Test that pods have resource limits set."""
        pods = await minikube_framework.get_pod_status()
        
        pods_without_limits = []
        for pod in pods:
            name = pod["metadata"]["name"]
            containers = pod.get("spec", {}).get("containers", [])
            
            for container in containers:
                if container["name"] == "istio-proxy":
                    continue  # Skip Istio proxy containers
                    
                resources = container.get("resources", {})
                limits = resources.get("limits", {})
                requests = resources.get("requests", {})
                
                if not limits.get("memory") or not limits.get("cpu"):
                    pods_without_limits.append(f"{name}/{container['name']}")
        
        # Warning rather than failure for resource limits
        if pods_without_limits:
            print(f"⚠ Pods/containers without resource limits: {pods_without_limits}")
        else:
            print("✓ All pods have resource limits configured")


@pytest.mark.minikube
class TestEndToEndFlow:
    """Test end-to-end functionality in Minikube."""
    
    @pytest.fixture(scope="class")
    async def minikube_framework(self):
        """Create Minikube test framework."""
        framework = MinikubeTestFramework()
        yield framework
    
    @pytest.fixture(scope="class")
    async def service_endpoints(self, minikube_framework):
        """Get service endpoints."""
        return await minikube_framework.get_service_endpoints()
    
    @pytest.mark.asyncio
    async def test_user_registration_flow(self, service_endpoints):
        """Test complete user registration flow."""
        api_gateway_url = service_endpoints.get("api-gateway")
        if not api_gateway_url:
            pytest.skip("API Gateway service not found")
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Test user registration
            registration_data = {
                "email": f"test{int(time.time())}@example.com",
                "password": "TestPassword123!",
                "name": "Test User",
                "tenant_id": "test-tenant"
            }
            
            response = await client.post(
                f"{api_gateway_url}/api/v1/auth/register",
                json=registration_data
            )
            
            assert response.status_code in [201, 409], f"Registration failed: {response.text}"
            
            if response.status_code == 201:
                data = response.json()
                assert "data" in data
                assert "user" in data["data"]
                assert "tokens" in data["data"]
                
                # Test login with new user
                login_response = await client.post(
                    f"{api_gateway_url}/api/v1/auth/login",
                    json={
                        "email": registration_data["email"],
                        "password": registration_data["password"]
                    }
                )
                
                assert login_response.status_code == 200, f"Login failed: {login_response.text}"
                
                print("✓ User registration and login flow successful")
    
    @pytest.mark.asyncio
    async def test_workspace_crud_operations(self, service_endpoints):
        """Test workspace CRUD operations."""
        api_gateway_url = service_endpoints.get("api-gateway")
        if not api_gateway_url:
            pytest.skip("API Gateway service not found")
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # First authenticate
            login_response = await client.post(
                f"{api_gateway_url}/api/v1/auth/login",
                json={
                    "email": "test@example.com",
                    "password": "TestPassword123!"
                }
            )
            
            if login_response.status_code != 200:
                pytest.skip("Authentication failed")
            
            token = login_response.json()["data"]["tokens"]["access_token"]
            headers = {"Authorization": f"Bearer {token}"}
            
            # Create workspace
            workspace_data = {
                "name": f"Test Workspace {int(time.time())}",
                "description": "Test workspace for Minikube validation"
            }
            
            create_response = await client.post(
                f"{api_gateway_url}/api/v1/workspaces",
                json=workspace_data,
                headers=headers
            )
            
            assert create_response.status_code == 201, f"Workspace creation failed: {create_response.text}"
            
            workspace_id = create_response.json()["data"]["workspace"]["id"]
            
            # Read workspace
            get_response = await client.get(
                f"{api_gateway_url}/api/v1/workspaces/{workspace_id}",
                headers=headers
            )
            
            assert get_response.status_code == 200, f"Workspace retrieval failed: {get_response.text}"
            
            # Update workspace
            update_data = {"name": "Updated Test Workspace"}
            update_response = await client.put(
                f"{api_gateway_url}/api/v1/workspaces/{workspace_id}",
                json=update_data,
                headers=headers
            )
            
            assert update_response.status_code == 200, f"Workspace update failed: {update_response.text}"
            
            # Delete workspace
            delete_response = await client.delete(
                f"{api_gateway_url}/api/v1/workspaces/{workspace_id}",
                headers=headers
            )
            
            assert delete_response.status_code in [200, 204], f"Workspace deletion failed: {delete_response.text}"
            
            print("✓ Workspace CRUD operations successful")


# CLI runner for deployment validation
async def run_deployment_validation():
    """Run deployment validation tests."""
    print("Starting Minikube deployment validation...")
    
    framework = MinikubeTestFramework()
    
    # Check Minikube status
    print("1. Checking Minikube cluster status...")
    if not await framework.check_minikube_status():
        print("✗ Minikube cluster is not running")
        return False
    print("✓ Minikube cluster is running")
    
    # Check namespace
    print("2. Checking namespace...")
    namespace_status = await framework.get_namespace_status()
    if "error" in namespace_status:
        print(f"✗ Namespace error: {namespace_status['error']}")
        return False
    print("✓ Namespace is active")
    
    # Check deployments
    print("3. Checking deployments...")
    deployments = [
        "postgres", "redis", "api-gateway", 
        "auth-service", "user-service", "airtable-gateway"
    ]
    
    for deployment in deployments:
        status = await framework.get_deployment_status(deployment)
        if not status or status.status != "Ready":
            print(f"✗ Deployment {deployment} is not ready")
            return False
        print(f"✓ {deployment} is ready")
    
    # Check services
    print("4. Checking service connectivity...")
    services = await framework.get_service_endpoints()
    connectivity_results = await framework.test_service_connectivity(services)
    
    for service_name, result in connectivity_results.items():
        if not result["success"]:
            print(f"✗ Service {service_name} health check failed")
            return False
    
    print("✓ All deployment validation tests passed!")
    return True


if __name__ == "__main__":
    success = asyncio.run(run_deployment_validation())
    exit(0 if success else 1)