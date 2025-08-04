"""
Health monitoring and deployment validation tests.
Tests system health, monitoring endpoints, and observability.
"""

import pytest
import asyncio
import httpx
import time
import json
import psutil
import logging
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import os
import re

logger = logging.getLogger(__name__)


@dataclass
class HealthCheckResult:
    """Health check result"""
    service_name: str
    endpoint: str
    status: str  # "healthy", "degraded", "unhealthy"
    response_time: float
    details: Dict[str, Any]
    dependencies: List[Dict[str, Any]]


@pytest.mark.deployment
@pytest.mark.monitoring
class TestHealthMonitoring:
    """Test health monitoring and observability"""

    @pytest.fixture(autouse=True)
    async def setup_health_monitoring(self, test_environment):
        """Setup health monitoring tests"""
        self.test_environment = test_environment
        self.health_results = []
        
        yield
        
        # Generate health monitoring report
        await self.generate_health_report()

    async def test_comprehensive_health_checks(self):
        """Test comprehensive health checks for all services"""
        services = {
            "API Gateway": {
                "url": self.test_environment.api_gateway_url,
                "health_endpoints": ["/health", "/api/health", "/healthz"],
                "critical": True
            },
            "Auth Service": {
                "url": self.test_environment.auth_service_url,
                "health_endpoints": ["/health", "/healthz"],
                "critical": True
            },
            "LLM Orchestrator": {
                "url": self.test_environment.llm_orchestrator_url,
                "health_endpoints": ["/health", "/api/health"],
                "critical": False
            },
            "Airtable Gateway": {
                "url": self.test_environment.airtable_gateway_url,
                "health_endpoints": ["/health", "/status"],
                "critical": False
            },
            "MCP Server": {
                "url": self.test_environment.mcp_server_url,
                "health_endpoints": ["/health", "/api/health"],
                "critical": False
            }
        }
        
        async with httpx.AsyncClient(timeout=15.0) as client:
            for service_name, service_config in services.items():
                await self._check_service_health(client, service_name, service_config)

    async def _check_service_health(self, client: httpx.AsyncClient, service_name: str, service_config: Dict):
        """Check health of a specific service"""
        health_result = None
        
        for health_endpoint in service_config["health_endpoints"]:
            start_time = time.time()
            
            try:
                response = await client.get(f"{service_config['url']}{health_endpoint}")
                response_time = time.time() - start_time
                
                # Parse health response
                health_data = await self._parse_health_response(response)
                
                # Determine health status
                status = self._determine_health_status(response.status_code, health_data, response_time)
                
                health_result = HealthCheckResult(
                    service_name=service_name,
                    endpoint=f"{service_config['url']}{health_endpoint}",
                    status=status,
                    response_time=response_time,
                    details=health_data,
                    dependencies=health_data.get("dependencies", [])
                )
                
                # If we got a response, use this result
                break
                
            except Exception as e:
                response_time = time.time() - start_time
                
                # Continue trying other endpoints
                health_result = HealthCheckResult(
                    service_name=service_name,
                    endpoint=f"{service_config['url']}{health_endpoint}",
                    status="unhealthy",
                    response_time=response_time,
                    details={"error": str(e), "exception": type(e).__name__},
                    dependencies=[]
                )
        
        if health_result:
            self.health_results.append(health_result)
            
            # Assert critical services are healthy
            if service_config["critical"]:
                assert health_result.status in ["healthy", "degraded"], \
                    f"Critical service {service_name} is {health_result.status}: {health_result.details}"

    async def _parse_health_response(self, response: httpx.Response) -> Dict[str, Any]:
        """Parse health check response"""
        try:
            if response.headers.get("content-type", "").startswith("application/json"):
                return response.json()
            else:
                # Try to extract useful info from text response
                text = response.text
                return {
                    "status_code": response.status_code,
                    "response_text": text[:200],  # First 200 chars
                    "content_type": response.headers.get("content-type", ""),
                    "content_length": len(text)
                }
        except Exception as e:
            return {
                "status_code": response.status_code,
                "parse_error": str(e),
                "response_length": len(response.text)
            }

    def _determine_health_status(self, status_code: int, health_data: Dict, response_time: float) -> str:
        """Determine health status from response"""
        if status_code == 200:
            # Check response time
            if response_time > 5.0:
                return "degraded"
            
            # Check if health data indicates issues
            if isinstance(health_data, dict):
                status = health_data.get("status", "").lower()
                if status in ["healthy", "ok", "up"]:
                    return "healthy"
                elif status in ["degraded", "warning"]:
                    return "degraded"
                elif status in ["unhealthy", "down", "error"]:
                    return "unhealthy"
            
            return "healthy"
        
        elif status_code in [503, 429]:
            return "degraded"
        else:
            return "unhealthy"

    async def test_dependency_health_checks(self, db_connection, redis_client):
        """Test health of system dependencies"""
        dependencies = []
        
        # Database health
        db_start = time.time()
        try:
            if db_connection:
                await db_connection.fetchval("SELECT 1")
                db_status = "healthy"
                db_error = None
            else:
                # Try direct connection
                import asyncpg
                conn = await asyncpg.connect(self.test_environment.database_url)
                await conn.fetchval("SELECT 1")
                await conn.close()
                db_status = "healthy"
                db_error = None
        except Exception as e:
            db_status = "unhealthy"
            db_error = str(e)
        
        db_response_time = time.time() - db_start
        
        dependencies.append({
            "name": "PostgreSQL Database",
            "status": db_status,
            "response_time": db_response_time,
            "error": db_error,
            "critical": True
        })
        
        # Redis health
        redis_start = time.time()
        try:
            if redis_client:
                await redis_client.ping()
                redis_status = "healthy"
                redis_error = None
            else:
                import redis.asyncio as redis
                client = redis.Redis.from_url(self.test_environment.redis_url)
                await client.ping()
                await client.close()
                redis_status = "healthy"
                redis_error = None
        except Exception as e:
            redis_status = "unhealthy"
            redis_error = str(e)
        
        redis_response_time = time.time() - redis_start
        
        dependencies.append({
            "name": "Redis Cache",
            "status": redis_status,
            "response_time": redis_response_time,
            "error": redis_error,
            "critical": False  # Redis is important but not critical for basic functionality
        })
        
        # External API health (Airtable API)
        external_start = time.time()
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                # Test external API connectivity
                response = await client.get("https://api.airtable.com/v0/meta/whoami", 
                                          headers={"Authorization": "Bearer test_token"})
                # 401 is expected with test token, but indicates API is reachable
                external_status = "healthy" if response.status_code in [200, 401, 403] else "degraded"
                external_error = None if response.status_code in [200, 401, 403] else f"HTTP {response.status_code}"
        except Exception as e:
            external_status = "unhealthy"
            external_error = str(e)
        
        external_response_time = time.time() - external_start
        
        dependencies.append({
            "name": "Airtable API",
            "status": external_status,
            "response_time": external_response_time,
            "error": external_error,
            "critical": False
        })
        
        # Store dependency health results
        dependency_health = HealthCheckResult(
            service_name="System Dependencies",
            endpoint="internal",
            status=self._aggregate_dependency_status(dependencies),
            response_time=max(dep["response_time"] for dep in dependencies),
            details={"dependency_count": len(dependencies)},
            dependencies=dependencies
        )
        
        self.health_results.append(dependency_health)
        
        # Assert critical dependencies are healthy
        critical_deps = [dep for dep in dependencies if dep["critical"]]
        unhealthy_critical = [dep for dep in critical_deps if dep["status"] == "unhealthy"]
        
        assert len(unhealthy_critical) == 0, \
            f"Critical dependencies unhealthy: {[dep['name'] for dep in unhealthy_critical]}"

    def _aggregate_dependency_status(self, dependencies: List[Dict]) -> str:
        """Aggregate dependency status into overall status"""
        statuses = [dep["status"] for dep in dependencies]
        
        if any(dep["critical"] and dep["status"] == "unhealthy" for dep in dependencies):
            return "unhealthy"
        elif "unhealthy" in statuses or "degraded" in statuses:
            return "degraded"
        else:
            return "healthy"

    async def test_metrics_endpoints(self):
        """Test metrics and observability endpoints"""
        metrics_endpoints = [
            {
                "service": "API Gateway",
                "urls": [
                    f"{self.test_environment.api_gateway_url}/metrics",
                    f"{self.test_environment.api_gateway_url}/api/metrics",
                    f"{self.test_environment.api_gateway_url}/prometheus"
                ]
            },
            {
                "service": "Auth Service", 
                "urls": [
                    f"{self.test_environment.auth_service_url}/metrics",
                    f"{self.test_environment.auth_service_url}/api/metrics"
                ]
            }
        ]
        
        metrics_results = []
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for service_config in metrics_endpoints:
                service_name = service_config["service"]
                metrics_available = False
                metrics_format = None
                
                for url in service_config["urls"]:
                    try:
                        response = await client.get(url)
                        
                        if response.status_code == 200:
                            metrics_available = True
                            
                            # Determine metrics format
                            content_type = response.headers.get("content-type", "").lower()
                            if "prometheus" in content_type or "text/plain" in content_type:
                                metrics_format = "prometheus"
                            elif "application/json" in content_type:
                                metrics_format = "json"
                            else:
                                metrics_format = "unknown"
                            
                            # Analyze metrics content
                            metrics_content = self._analyze_metrics_content(response.text, metrics_format)
                            
                            break
                    
                    except Exception:
                        continue
                
                metrics_results.append({
                    "service": service_name,
                    "metrics_available": metrics_available,
                    "format": metrics_format,
                    "endpoint": url if metrics_available else None,
                    "content_analysis": metrics_content if metrics_available else None
                })
        
        # Store metrics results
        metrics_health = HealthCheckResult(
            service_name="Metrics and Observability",
            endpoint="various",
            status="healthy" if any(r["metrics_available"] for r in metrics_results) else "degraded",
            response_time=0.0,
            details={
                "services_with_metrics": len([r for r in metrics_results if r["metrics_available"]]),
                "total_services": len(metrics_results),
                "results": metrics_results
            },
            dependencies=[]
        )
        
        self.health_results.append(metrics_health)

    def _analyze_metrics_content(self, content: str, format_type: str) -> Dict[str, Any]:
        """Analyze metrics content for useful information"""
        analysis = {
            "format": format_type,
            "size": len(content),
            "line_count": len(content.split('\n')) if content else 0
        }
        
        if format_type == "prometheus":
            # Count different metric types
            lines = content.split('\n')
            metric_names = set()
            
            for line in lines:
                if line and not line.startswith('#'):
                    # Extract metric name
                    match = re.match(r'^([a-zA-Z_:][a-zA-Z0-9_:]*)', line)
                    if match:
                        metric_names.add(match.group(1))
            
            analysis.update({
                "metric_count": len(metric_names),
                "sample_metrics": list(metric_names)[:10]  # First 10 metrics
            })
        
        elif format_type == "json":
            try:
                data = json.loads(content)
                if isinstance(data, dict):
                    analysis.update({
                        "keys": list(data.keys())[:10],  # First 10 keys
                        "nested_structure": isinstance(list(data.values())[0], dict) if data else False
                    })
            except:
                analysis["parse_error"] = True
        
        return analysis

    async def test_logging_configuration(self):
        """Test logging configuration and accessibility"""
        # Test if services provide log information in health checks
        log_config_results = []
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            services = [
                ("API Gateway", self.test_environment.api_gateway_url),
                ("Auth Service", self.test_environment.auth_service_url)
            ]
            
            for service_name, base_url in services:
                log_endpoints = [
                    f"{base_url}/api/logs/level",
                    f"{base_url}/debug/logs",
                    f"{base_url}/api/debug/logging"
                ]
                
                logging_info_available = False
                
                for endpoint in log_endpoints:
                    try:
                        response = await client.get(endpoint)
                        
                        if response.status_code == 200:
                            logging_info_available = True
                            break
                    
                    except Exception:
                        continue
                
                log_config_results.append({
                    "service": service_name,
                    "logging_info_available": logging_info_available
                })
        
        # Store logging results
        logging_health = HealthCheckResult(
            service_name="Logging Configuration",
            endpoint="various",
            status="healthy",  # Logging info is nice-to-have, not critical
            response_time=0.0,
            details={
                "services_with_logging_info": len([r for r in log_config_results if r["logging_info_available"]]),
                "results": log_config_results
            },
            dependencies=[]
        )
        
        self.health_results.append(logging_health)

    async def test_system_resource_monitoring(self):
        """Test system resource monitoring"""
        # Get system resource information
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            # Check for resource thresholds
            resource_status = "healthy"
            resource_warnings = []
            
            if cpu_percent > 80:
                resource_status = "degraded"
                resource_warnings.append(f"High CPU usage: {cpu_percent:.1f}%")
            
            if memory.percent > 85:
                resource_status = "degraded"
                resource_warnings.append(f"High memory usage: {memory.percent:.1f}%")
            
            if disk.percent > 90:
                resource_status = "unhealthy"
                resource_warnings.append(f"High disk usage: {disk.percent:.1f}%")
            
            resource_details = {
                "cpu_percent": cpu_percent,
                "memory_percent": memory.percent,
                "memory_available_gb": memory.available / (1024**3),
                "disk_percent": disk.percent,
                "disk_free_gb": disk.free / (1024**3),
                "warnings": resource_warnings
            }
            
        except Exception as e:
            resource_status = "unhealthy"
            resource_details = {"error": str(e)}
        
        # Store resource monitoring results
        resource_health = HealthCheckResult(
            service_name="System Resources",
            endpoint="local",
            status=resource_status,
            response_time=0.0,
            details=resource_details,
            dependencies=[]
        )
        
        self.health_results.append(resource_health)
        
        # Warn if resources are constrained
        if resource_status != "healthy":
            logger.warning(f"System resource issues: {resource_details.get('warnings', [])}")

    async def test_readiness_vs_liveness(self):
        """Test readiness vs liveness probe endpoints"""
        probe_tests = []
        
        services = [
            ("API Gateway", self.test_environment.api_gateway_url),
            ("Auth Service", self.test_environment.auth_service_url)
        ]
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for service_name, base_url in services:
                probe_results = {
                    "service": service_name,
                    "readiness": None,
                    "liveness": None
                }
                
                # Test readiness probe
                readiness_endpoints = ["/ready", "/readiness", "/api/ready"]
                for endpoint in readiness_endpoints:
                    try:
                        response = await client.get(f"{base_url}{endpoint}")
                        if response.status_code in [200, 404]:  # 404 is ok if endpoint doesn't exist
                            probe_results["readiness"] = {
                                "endpoint": endpoint,
                                "status_code": response.status_code,
                                "available": response.status_code == 200
                            }
                            break
                    except:
                        continue
                
                # Test liveness probe
                liveness_endpoints = ["/live", "/liveness", "/api/live"]
                for endpoint in liveness_endpoints:
                    try:
                        response = await client.get(f"{base_url}{endpoint}")
                        if response.status_code in [200, 404]:
                            probe_results["liveness"] = {
                                "endpoint": endpoint,
                                "status_code": response.status_code,
                                "available": response.status_code == 200
                            }
                            break
                    except:
                        continue
                
                probe_tests.append(probe_results)
        
        # Store probe results
        probe_health = HealthCheckResult(
            service_name="Kubernetes Probes",
            endpoint="various",
            status="healthy",  # Probe endpoints are deployment-specific
            response_time=0.0,
            details={
                "probe_results": probe_tests,
                "services_with_readiness": len([p for p in probe_tests if p["readiness"] and p["readiness"]["available"]]),
                "services_with_liveness": len([p for p in probe_tests if p["liveness"] and p["liveness"]["available"]])
            },
            dependencies=[]
        )
        
        self.health_results.append(probe_health)

    async def generate_health_report(self):
        """Generate comprehensive health monitoring report"""
        if not self.health_results:
            return
        
        # Categorize results by status
        healthy_services = [r for r in self.health_results if r.status == "healthy"]
        degraded_services = [r for r in self.health_results if r.status == "degraded"]
        unhealthy_services = [r for r in self.health_results if r.status == "unhealthy"]
        
        # Calculate overall system health
        if unhealthy_services:
            overall_status = "unhealthy"
        elif degraded_services:
            overall_status = "degraded"
        else:
            overall_status = "healthy"
        
        # Create comprehensive report
        report = {
            "timestamp": time.time(),
            "overall_status": overall_status,
            "summary": {
                "total_services": len(self.health_results),
                "healthy": len(healthy_services),
                "degraded": len(degraded_services),
                "unhealthy": len(unhealthy_services),
                "average_response_time": sum(r.response_time for r in self.health_results) / len(self.health_results)
            },
            "services": []
        }
        
        for result in self.health_results:
            service_data = {
                "service_name": result.service_name,
                "endpoint": result.endpoint,
                "status": result.status,
                "response_time": f"{result.response_time:.3f}s",
                "details": result.details,
                "dependencies": result.dependencies
            }
            report["services"].append(service_data)
        
        # Save report
        os.makedirs("tests/reports/deployment", exist_ok=True)
        
        import aiofiles
        async with aiofiles.open("tests/reports/deployment/health_monitoring_report.json", 'w') as f:
            await f.write(json.dumps(report, indent=2))
        
        # Log summary
        logger.info("Health Monitoring Report:")
        logger.info(f"  Overall Status: {overall_status.upper()}")
        logger.info(f"  Services: {len(healthy_services)} healthy, {len(degraded_services)} degraded, {len(unhealthy_services)} unhealthy")
        logger.info(f"  Average Response Time: {report['summary']['average_response_time']:.3f}s")
        
        for result in self.health_results:
            status_emoji = {"healthy": "✅", "degraded": "⚠️", "unhealthy": "❌"}[result.status]
            logger.info(f"  {status_emoji} {result.service_name}: {result.status} ({result.response_time:.3f}s)")
            
            if result.dependencies:
                for dep in result.dependencies:
                    dep_emoji = {"healthy": "✅", "degraded": "⚠️", "unhealthy": "❌"}[dep["status"]]
                    logger.info(f"    {dep_emoji} {dep['name']}: {dep['status']}")

        return report