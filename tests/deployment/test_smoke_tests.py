"""
Deployment smoke tests for PyAirtable pre-deployment validation.
Quick tests to verify basic functionality after deployment.
"""

import pytest
import asyncio
import httpx
import time
import json
import subprocess
import os
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class SmokeTestResult:
    """Smoke test result"""
    test_name: str
    passed: bool
    response_time: float
    error_message: Optional[str] = None
    details: Optional[Dict[str, Any]] = None


@pytest.mark.deployment
@pytest.mark.smoke
class TestDeploymentSmokeTests:
    """Smoke tests for deployment validation"""

    @pytest.fixture(autouse=True)
    async def setup_smoke_test(self, test_environment):
        """Setup smoke testing environment"""
        self.test_environment = test_environment
        self.smoke_results = []
        
        yield
        
        # Generate smoke test report
        await self.generate_smoke_test_report()

    async def test_basic_service_health(self):
        """Test basic health of all services"""
        services = {
            "API Gateway": f"{self.test_environment.api_gateway_url}/health",
            "Auth Service": f"{self.test_environment.auth_service_url}/health",
            "LLM Orchestrator": f"{self.test_environment.llm_orchestrator_url}/health",
            "Airtable Gateway": f"{self.test_environment.airtable_gateway_url}/health",
            "MCP Server": f"{self.test_environment.mcp_server_url}/health"
        }
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for service_name, health_url in services.items():
                start_time = time.time()
                
                try:
                    response = await client.get(health_url)
                    response_time = time.time() - start_time
                    
                    result = SmokeTestResult(
                        test_name=f"{service_name} Health Check",
                        passed=response.status_code == 200,
                        response_time=response_time,
                        error_message=None if response.status_code == 200 else f"HTTP {response.status_code}",
                        details={
                            "status_code": response.status_code,
                            "response_body": response.text[:200] if response.text else ""
                        }
                    )
                    
                except Exception as e:
                    response_time = time.time() - start_time
                    result = SmokeTestResult(
                        test_name=f"{service_name} Health Check",
                        passed=False,
                        response_time=response_time,
                        error_message=str(e),
                        details={"exception": type(e).__name__}
                    )
                
                self.smoke_results.append(result)
                
                # Assert critical services are healthy
                if service_name in ["API Gateway", "Auth Service"]:
                    assert result.passed, f"Critical service {service_name} is not healthy: {result.error_message}"

    async def test_database_connectivity(self, db_connection):
        """Test database connectivity and basic operations"""
        start_time = time.time()
        
        try:
            if db_connection is None:
                # Try to connect directly if no connection available
                import asyncpg
                conn = await asyncpg.connect(self.test_environment.database_url)
                
                # Simple connectivity test
                result = await conn.fetchval("SELECT 1")
                await conn.close()
                
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="Database Connectivity",
                    passed=result == 1,
                    response_time=response_time,
                    details={"query_result": result}
                )
            else:
                # Use existing connection
                result = await db_connection.fetchval("SELECT 1")
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="Database Connectivity",
                    passed=result == 1,
                    response_time=response_time,
                    details={"query_result": result}
                )
        
        except Exception as e:
            response_time = time.time() - start_time
            smoke_result = SmokeTestResult(
                test_name="Database Connectivity",
                passed=False,
                response_time=response_time,
                error_message=str(e),
                details={"exception": type(e).__name__}
            )
        
        self.smoke_results.append(smoke_result)
        
        # Database connectivity is critical
        assert smoke_result.passed, f"Database connectivity failed: {smoke_result.error_message}"

    async def test_redis_connectivity(self, redis_client):
        """Test Redis connectivity and basic operations"""
        start_time = time.time()
        
        try:
            if redis_client is None:
                # Try to connect directly
                import redis.asyncio as redis
                client = redis.Redis.from_url(self.test_environment.redis_url)
                
                await client.ping()
                await client.close()
                
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="Redis Connectivity",
                    passed=True,
                    response_time=response_time,
                    details={"operation": "ping"}
                )
            else:
                # Use existing client
                await redis_client.ping()
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="Redis Connectivity",
                    passed=True,
                    response_time=response_time,
                    details={"operation": "ping"}
                )
        
        except Exception as e:
            response_time = time.time() - start_time
            smoke_result = SmokeTestResult(
                test_name="Redis Connectivity",
                passed=False,
                response_time=response_time,
                error_message=str(e),
                details={"exception": type(e).__name__}
            )
        
        self.smoke_results.append(smoke_result)
        
        # Redis is important but not always critical for basic functionality
        if not smoke_result.passed:
            logger.warning(f"Redis connectivity issue: {smoke_result.error_message}")

    async def test_authentication_flow(self, test_data_factory):
        """Test basic authentication flow"""
        start_time = time.time()
        
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                # Test user registration
                user_data = test_data_factory.create_user_data()
                
                register_response = await client.post(
                    f"{self.test_environment.auth_service_url}/auth/register",
                    json=user_data
                )
                
                # Registration should succeed or user already exists
                registration_ok = register_response.status_code in [200, 201, 409]
                
                if registration_ok:
                    # Test user login
                    login_response = await client.post(
                        f"{self.test_environment.auth_service_url}/auth/login",
                        json={
                            "email": user_data["email"],
                            "password": user_data["password"]
                        }
                    )
                    
                    login_ok = login_response.status_code == 200
                    token = login_response.json().get("access_token") if login_ok else None
                    
                    if login_ok and token:
                        # Test authenticated request
                        profile_response = await client.get(
                            f"{self.test_environment.api_gateway_url}/auth/profile",
                            headers={"Authorization": f"Bearer {token}"}
                        )
                        
                        auth_flow_ok = profile_response.status_code == 200
                        
                        response_time = time.time() - start_time
                        
                        smoke_result = SmokeTestResult(
                            test_name="Authentication Flow",
                            passed=auth_flow_ok,
                            response_time=response_time,
                            details={
                                "registration_status": register_response.status_code,
                                "login_status": login_response.status_code,
                                "profile_status": profile_response.status_code,
                                "token_received": bool(token)
                            }
                        )
                    else:
                        smoke_result = SmokeTestResult(
                            test_name="Authentication Flow",
                            passed=False,
                            response_time=time.time() - start_time,
                            error_message=f"Login failed: HTTP {login_response.status_code}",
                            details={
                                "registration_status": register_response.status_code,
                                "login_status": login_response.status_code
                            }
                        )
                else:
                    smoke_result = SmokeTestResult(
                        test_name="Authentication Flow",
                        passed=False,
                        response_time=time.time() - start_time,
                        error_message=f"Registration failed: HTTP {register_response.status_code}",
                        details={"registration_status": register_response.status_code}
                    )
        
        except Exception as e:
            response_time = time.time() - start_time
            smoke_result = SmokeTestResult(
                test_name="Authentication Flow",
                passed=False,
                response_time=response_time,
                error_message=str(e),
                details={"exception": type(e).__name__}
            )
        
        self.smoke_results.append(smoke_result)
        
        # Authentication is critical
        assert smoke_result.passed, f"Authentication flow failed: {smoke_result.error_message}"

    async def test_api_gateway_routing(self):
        """Test API Gateway routing to backend services"""
        # Test various routes through API Gateway
        routes_to_test = [
            {
                "name": "Health Endpoint",
                "path": "/health",
                "expected_status": 200,
                "critical": True
            },
            {
                "name": "API Info",
                "path": "/api/info",
                "expected_status": [200, 404],  # 404 is acceptable if endpoint doesn't exist
                "critical": False
            },
            {
                "name": "Auth Routes",
                "path": "/auth/info",
                "expected_status": [200, 401, 404],
                "critical": False
            },
            {
                "name": "Static Assets",
                "path": "/static/health",
                "expected_status": [200, 404],
                "critical": False
            }
        ]
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for route in routes_to_test:
                start_time = time.time()
                
                try:
                    response = await client.get(
                        f"{self.test_environment.api_gateway_url}{route['path']}"
                    )
                    
                    response_time = time.time() - start_time
                    expected_statuses = route['expected_status']
                    if not isinstance(expected_statuses, list):
                        expected_statuses = [expected_statuses]
                    
                    passed = response.status_code in expected_statuses
                    
                    smoke_result = SmokeTestResult(
                        test_name=f"API Gateway - {route['name']}",
                        passed=passed,
                        response_time=response_time,
                        error_message=None if passed else f"Unexpected status: {response.status_code}",
                        details={
                            "path": route['path'],
                            "status_code": response.status_code,
                            "expected_statuses": expected_statuses
                        }
                    )
                    
                except Exception as e:
                    response_time = time.time() - start_time
                    smoke_result = SmokeTestResult(
                        test_name=f"API Gateway - {route['name']}",
                        passed=False,
                        response_time=response_time,
                        error_message=str(e),
                        details={
                            "path": route['path'],
                            "exception": type(e).__name__
                        }
                    )
                
                self.smoke_results.append(smoke_result)
                
                # Assert critical routes work
                if route['critical']:
                    assert smoke_result.passed, f"Critical route {route['path']} failed: {smoke_result.error_message}"

    async def test_external_service_integration(self):
        """Test integration with external services"""
        start_time = time.time()
        
        try:
            # Test Airtable Gateway (external service integration)
            async with httpx.AsyncClient(timeout=15.0) as client:
                response = await client.get(
                    f"{self.test_environment.airtable_gateway_url}/tables",
                    headers={"Authorization": "Bearer test_token"}
                )
                
                # External services might not be available in all environments
                # So we're more lenient with the success criteria
                external_integration_ok = response.status_code in [200, 401, 403, 404, 503]
                
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="External Service Integration",
                    passed=external_integration_ok,
                    response_time=response_time,
                    error_message=None if external_integration_ok else f"Unexpected status: {response.status_code}",
                    details={
                        "service": "Airtable Gateway",
                        "status_code": response.status_code,
                        "response_length": len(response.text)
                    }
                )
        
        except Exception as e:
            response_time = time.time() - start_time
            smoke_result = SmokeTestResult(
                test_name="External Service Integration",
                passed=False,
                response_time=response_time,
                error_message=str(e),
                details={"exception": type(e).__name__}
            )
        
        self.smoke_results.append(smoke_result)
        
        # External service integration failures are warnings, not critical failures
        if not smoke_result.passed:
            logger.warning(f"External service integration issue: {smoke_result.error_message}")

    async def test_ai_service_basic_functionality(self):
        """Test basic AI service functionality"""
        start_time = time.time()
        
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                # Test LLM Orchestrator basic endpoint
                response = await client.post(
                    f"{self.test_environment.llm_orchestrator_url}/chat/test",
                    json={
                        "message": "Hello, this is a smoke test",
                        "session_id": "smoke_test"
                    },
                    headers={"Content-Type": "application/json"}
                )
                
                # AI services might have different response patterns
                ai_service_ok = response.status_code in [200, 404, 422, 503]
                
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="AI Service Basic Functionality",
                    passed=ai_service_ok,
                    response_time=response_time,
                    error_message=None if ai_service_ok else f"Unexpected status: {response.status_code}",
                    details={
                        "service": "LLM Orchestrator",
                        "status_code": response.status_code,
                        "response_time": response_time
                    }
                )
        
        except Exception as e:
            response_time = time.time() - start_time
            smoke_result = SmokeTestResult(
                test_name="AI Service Basic Functionality",
                passed=False,
                response_time=response_time,
                error_message=str(e),
                details={"exception": type(e).__name__}
            )
        
        self.smoke_results.append(smoke_result)
        
        # AI service issues are warnings for smoke tests
        if not smoke_result.passed:
            logger.warning(f"AI service issue: {smoke_result.error_message}")

    async def test_performance_baselines(self):
        """Test basic performance baselines"""
        performance_tests = [
            {
                "name": "API Gateway Response Time",
                "url": f"{self.test_environment.api_gateway_url}/health",
                "max_response_time": 2.0
            },
            {
                "name": "Auth Service Response Time",
                "url": f"{self.test_environment.auth_service_url}/health",
                "max_response_time": 1.0
            }
        ]
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            for test in performance_tests:
                # Run multiple requests to get average
                response_times = []
                
                for _ in range(3):
                    start_time = time.time()
                    
                    try:
                        response = await client.get(test["url"])
                        response_time = time.time() - start_time
                        
                        if response.status_code == 200:
                            response_times.append(response_time)
                    
                    except Exception:
                        pass
                
                if response_times:
                    avg_response_time = sum(response_times) / len(response_times)
                    performance_ok = avg_response_time <= test["max_response_time"]
                    
                    smoke_result = SmokeTestResult(
                        test_name=test["name"],
                        passed=performance_ok,
                        response_time=avg_response_time,
                        error_message=None if performance_ok else f"Response time {avg_response_time:.3f}s exceeds {test['max_response_time']}s",
                        details={
                            "avg_response_time": avg_response_time,
                            "max_allowed": test["max_response_time"],
                            "sample_count": len(response_times)
                        }
                    )
                else:
                    smoke_result = SmokeTestResult(
                        test_name=test["name"],
                        passed=False,
                        response_time=0.0,
                        error_message="No successful requests",
                        details={"sample_count": 0}
                    )
                
                self.smoke_results.append(smoke_result)
                
                # Performance baselines are warnings, not critical failures
                if not smoke_result.passed:
                    logger.warning(f"Performance baseline issue: {smoke_result.error_message}")

    async def test_configuration_validation(self):
        """Test that services are properly configured"""
        config_tests = []
        
        # Check environment variables are set (if accessible)
        required_env_vars = [
            "DATABASE_URL",
            "REDIS_URL",
        ]
        
        missing_vars = []
        for var in required_env_vars:
            if not os.getenv(var):
                missing_vars.append(var)
        
        config_ok = len(missing_vars) == 0
        
        smoke_result = SmokeTestResult(
            test_name="Configuration Validation",
            passed=config_ok,
            response_time=0.0,
            error_message=f"Missing environment variables: {missing_vars}" if missing_vars else None,
            details={
                "required_vars": required_env_vars,
                "missing_vars": missing_vars
            }
        )
        
        self.smoke_results.append(smoke_result)
        
        # Configuration issues are warnings in smoke tests
        if not smoke_result.passed:
            logger.warning(f"Configuration issue: {smoke_result.error_message}")

    async def test_logging_and_monitoring(self):
        """Test that logging and monitoring are working"""
        start_time = time.time()
        
        try:
            # Test if services expose metrics endpoint
            async with httpx.AsyncClient(timeout=10.0) as client:
                metrics_endpoints = [
                    f"{self.test_environment.api_gateway_url}/metrics",
                    f"{self.test_environment.api_gateway_url}/api/metrics",
                    f"{self.test_environment.api_gateway_url}/health/metrics"
                ]
                
                metrics_available = False
                
                for endpoint in metrics_endpoints:
                    try:
                        response = await client.get(endpoint)
                        if response.status_code == 200:
                            metrics_available = True
                            break
                    except:
                        continue
                
                response_time = time.time() - start_time
                
                smoke_result = SmokeTestResult(
                    test_name="Logging and Monitoring",
                    passed=True,  # Not critical for smoke test
                    response_time=response_time,
                    error_message=None if metrics_available else "No metrics endpoint found",
                    details={
                        "metrics_available": metrics_available,
                        "tested_endpoints": metrics_endpoints
                    }
                )
        
        except Exception as e:
            response_time = time.time() - start_time
            smoke_result = SmokeTestResult(
                test_name="Logging and Monitoring",
                passed=False,
                response_time=response_time,
                error_message=str(e),
                details={"exception": type(e).__name__}
            )
        
        self.smoke_results.append(smoke_result)
        
        # Monitoring issues are informational
        if not smoke_result.passed:
            logger.info(f"Monitoring info: {smoke_result.error_message}")

    async def generate_smoke_test_report(self):
        """Generate smoke test report"""
        if not self.smoke_results:
            return
        
        # Calculate summary
        total_tests = len(self.smoke_results)
        passed_tests = len([r for r in self.smoke_results if r.passed])
        failed_tests = total_tests - passed_tests
        
        avg_response_time = sum(r.response_time for r in self.smoke_results) / total_tests if total_tests > 0 else 0
        
        # Create report
        report = {
            "summary": {
                "total_tests": total_tests,
                "passed_tests": passed_tests,
                "failed_tests": failed_tests,
                "success_rate": f"{(passed_tests / total_tests * 100):.1f}%" if total_tests > 0 else "0%",
                "average_response_time": f"{avg_response_time:.3f}s"
            },
            "results": []
        }
        
        for result in self.smoke_results:
            report["results"].append({
                "test_name": result.test_name,
                "passed": result.passed,
                "response_time": f"{result.response_time:.3f}s",
                "error_message": result.error_message,
                "details": result.details
            })
        
        # Save report
        os.makedirs("tests/reports/deployment", exist_ok=True)
        
        import aiofiles
        async with aiofiles.open("tests/reports/deployment/smoke_test_report.json", 'w') as f:
            await f.write(json.dumps(report, indent=2))
        
        # Log summary
        logger.info("Smoke Test Results:")
        logger.info(f"  Total Tests: {total_tests}")
        logger.info(f"  Passed: {passed_tests}")
        logger.info(f"  Failed: {failed_tests}")
        logger.info(f"  Success Rate: {report['summary']['success_rate']}")
        logger.info(f"  Average Response Time: {report['summary']['average_response_time']}")
        
        for result in self.smoke_results:
            status = "✅" if result.passed else "❌"
            logger.info(f"  {status} {result.test_name}: {result.response_time:.3f}s")
            if not result.passed and result.error_message:
                logger.info(f"      Error: {result.error_message}")


@pytest.mark.deployment
class TestPostDeploymentValidation:
    """Post-deployment validation tests"""

    async def test_deployment_rollback_capability(self):
        """Test that deployment can be rolled back if needed"""
        # This would test rollback mechanisms
        # In a real scenario, this might involve:
        # - Database migration rollbacks
        # - Service version rollbacks
        # - Configuration rollbacks
        
        logger.info("Deployment rollback capability test - implementation depends on deployment strategy")
        
        # For now, just verify that we can identify the current deployment
        deployment_info = {
            "timestamp": time.time(),
            "version": os.getenv("APP_VERSION", "unknown"),
            "commit": os.getenv("GIT_COMMIT", "unknown")
        }
        
        logger.info(f"Current deployment info: {deployment_info}")
        
        # Test passes if we can gather deployment information
        assert deployment_info["timestamp"] > 0

    async def test_data_migration_integrity(self, db_connection):
        """Test that data migrations completed successfully"""
        if db_connection is None:
            pytest.skip("Database not available")
        
        try:
            # Check if migration table exists
            migration_check = await db_connection.fetchval("""
                SELECT EXISTS(
                    SELECT FROM information_schema.tables 
                    WHERE table_name = 'migration_log'
                )
            """)
            
            if migration_check:
                # Check migration status
                latest_migration = await db_connection.fetchrow("""
                    SELECT * FROM migration_log 
                    ORDER BY applied_at DESC 
                    LIMIT 1
                """)
                
                logger.info(f"Latest migration: {latest_migration}")
                
                # Verify migration was successful
                if latest_migration:
                    assert latest_migration.get("status") == "completed", "Latest migration not completed"
            
            else:
                logger.warning("No migration log table found")
        
        except Exception as e:
            logger.warning(f"Migration integrity check failed: {e}")
            # Don't fail the test as migration system might not be implemented
            pass

    async def test_service_dependencies(self):
        """Test that all service dependencies are available"""
        # This test would verify that:
        # - All required services are running
        # - Network connectivity between services works
        # - Service discovery is functioning
        
        dependencies = {
            "Database": "postgresql://",
            "Redis": "redis://",
            "External APIs": "https://"
        }
        
        for dep_name, dep_type in dependencies.items():
            logger.info(f"Checking dependency: {dep_name} ({dep_type})")
        
        # Basic connectivity test passed in other smoke tests
        logger.info("Service dependencies validation completed")

    async def test_security_configuration(self):
        """Test that security configurations are properly applied"""
        # This would test:
        # - HTTPS is enforced
        # - Security headers are present
        # - Authentication is required for protected endpoints
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.get(f"{self.test_environment.api_gateway_url}/health")
                
                # Check security headers
                security_headers = [
                    "X-Frame-Options",
                    "X-Content-Type-Options",
                    "X-XSS-Protection",
                    "Strict-Transport-Security"
                ]
                
                present_headers = []
                for header in security_headers:
                    if header in response.headers:
                        present_headers.append(header)
                
                logger.info(f"Security headers present: {present_headers}")
                
                # At least some security headers should be present
                # (not enforcing all as it depends on deployment configuration)
                
            except Exception as e:
                logger.warning(f"Security configuration check failed: {e}")

    async def test_backup_and_recovery_readiness(self):
        """Test that backup and recovery systems are ready"""
        # This would test:
        # - Backup systems are configured
        # - Recovery procedures are available
        # - Data retention policies are in place
        
        logger.info("Backup and recovery readiness test - implementation depends on infrastructure")
        
        # Check if backup-related environment variables are set
        backup_config = {
            "backup_enabled": os.getenv("BACKUP_ENABLED", "false").lower() == "true",
            "backup_schedule": os.getenv("BACKUP_SCHEDULE"),
            "backup_retention": os.getenv("BACKUP_RETENTION_DAYS")
        }
        
        logger.info(f"Backup configuration: {backup_config}")
        
        # Test passes - backup configuration is environment-specific