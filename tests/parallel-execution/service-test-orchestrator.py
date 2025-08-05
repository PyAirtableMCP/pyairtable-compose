"""
Service Test Orchestrator for Parallel Execution
================================================

This module orchestrates parallel test execution across PyAirtable's 6-service architecture:
- Frontend Services (3): tenant-dashboard, admin-dashboard, auth-frontend  
- Backend Services (6): API Gateway, Auth Service, Platform Services, LLM Orchestrator, MCP Server, Airtable Gateway

Features:
- Service-specific test isolation
- Parallel execution with dependency management
- Real-time test monitoring and reporting
- Failure isolation and recovery
- Performance metrics collection
"""

import asyncio
import json
import logging
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any, Set
from enum import Enum
import threading
import uuid
import subprocess
import signal
import sys

logger = logging.getLogger(__name__)

class ServiceType(Enum):
    FRONTEND = "frontend"
    GO_SERVICE = "go_service"
    PYTHON_SERVICE = "python_service"
    INFRASTRUCTURE = "infrastructure"

class TestCategory(Enum):
    CRITICAL = "critical"
    REGRESSION = "regression"
    PERFORMANCE = "performance"
    SECURITY = "security"
    EDGE_CASE = "edge_case"
    INTEGRATION = "integration"

class TestStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    PASSED = "passed"
    FAILED = "failed"
    SKIPPED = "skipped"
    TIMEOUT = "timeout"

@dataclass
class ServiceConfig:
    name: str
    type: ServiceType
    port: int
    health_endpoint: str
    dependencies: List[str]
    test_command: str
    test_timeout: int = 300
    max_retries: int = 2

@dataclass
class TestResult:
    service: str
    category: TestCategory
    test_name: str
    status: TestStatus
    duration: float
    error_message: Optional[str] = None
    performance_metrics: Optional[Dict[str, Any]] = None
    coverage: Optional[float] = None
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None

@dataclass
class ExecutionSummary:
    total_tests: int
    passed_tests: int
    failed_tests: int
    skipped_tests: int
    total_duration: float
    pass_rate: float
    services_tested: List[str]
    categories_tested: List[TestCategory]
    performance_summary: Dict[str, Any]
    coverage_summary: Dict[str, float]

class ServiceTestOrchestrator:
    """Orchestrates parallel test execution across all PyAirtable services"""
    
    def __init__(self, config_path: Optional[Path] = None):
        self.config_path = config_path or Path("tests/config/services.json")
        self.services = self._load_service_configurations()
        self.test_results: List[TestResult] = []
        self.execution_id = str(uuid.uuid4())
        self.start_time = datetime.now()
        self.stop_event = threading.Event()
        
        # Initialize execution tracking
        self.running_tests: Set[str] = set()
        self.completed_tests: Set[str] = set()
        self.lock = threading.Lock()
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _load_service_configurations(self) -> Dict[str, ServiceConfig]:
        """Load service configurations for test orchestration"""
        
        # Default service configurations
        default_services = {
            # Frontend Services
            "tenant-dashboard": ServiceConfig(
                name="tenant-dashboard",
                type=ServiceType.FRONTEND,
                port=3002,
                health_endpoint="/api/health",
                dependencies=[],
                test_command="cd frontend-services/tenant-dashboard && npm test",
                test_timeout=300
            ),
            "admin-dashboard": ServiceConfig(
                name="admin-dashboard", 
                type=ServiceType.FRONTEND,
                port=3001,
                health_endpoint="/api/health",
                dependencies=[],
                test_command="cd frontend-services/admin-dashboard && npm test",
                test_timeout=300
            ),
            "auth-frontend": ServiceConfig(
                name="auth-frontend",
                type=ServiceType.FRONTEND, 
                port=3003,
                health_endpoint="/api/health",
                dependencies=[],
                test_command="cd frontend-services/auth-frontend && npm test",
                test_timeout=300
            ),
            
            # Go Services
            "api-gateway": ServiceConfig(
                name="api-gateway",
                type=ServiceType.GO_SERVICE,
                port=8000,
                health_endpoint="/health",
                dependencies=["auth-service"],
                test_command="cd go-services/api-gateway && go test ./... -v",
                test_timeout=180
            ),
            "auth-service": ServiceConfig(
                name="auth-service",
                type=ServiceType.GO_SERVICE,
                port=8004,
                health_endpoint="/health", 
                dependencies=["postgres", "redis"],
                test_command="cd go-services/auth-service && go test ./... -v",
                test_timeout=180
            ),
            "platform-services": ServiceConfig(
                name="platform-services",
                type=ServiceType.GO_SERVICE,
                port=8005,
                health_endpoint="/health",
                dependencies=["postgres", "redis", "auth-service"],
                test_command="cd go-services/pyairtable-platform && go test ./... -v",
                test_timeout=180
            ),
            
            # Python Services
            "llm-orchestrator": ServiceConfig(
                name="llm-orchestrator",
                type=ServiceType.PYTHON_SERVICE,
                port=8003,
                health_endpoint="/health",
                dependencies=["mcp-server"],
                test_command="cd python-services/llm-orchestrator && python -m pytest tests/ -v",
                test_timeout=240
            ),
            "mcp-server": ServiceConfig(
                name="mcp-server",
                type=ServiceType.PYTHON_SERVICE,
                port=8001,
                health_endpoint="/health", 
                dependencies=["airtable-gateway"],
                test_command="cd python-services/mcp-server && python -m pytest tests/ -v",
                test_timeout=240
            ),
            "airtable-gateway": ServiceConfig(
                name="airtable-gateway",
                type=ServiceType.PYTHON_SERVICE,
                port=8002,
                health_endpoint="/health",
                dependencies=[],
                test_command="cd python-services/airtable-gateway && python -m pytest tests/ -v",
                test_timeout=240
            )
        }
        
        # Load from config file if exists
        if self.config_path.exists():
            try:
                with open(self.config_path, 'r') as f:
                    config_data = json.load(f)
                    for service_name, service_data in config_data.items():
                        if service_name in default_services:
                            # Update default with loaded config
                            for key, value in service_data.items():
                                if key == 'type':
                                    value = ServiceType(value)
                                setattr(default_services[service_name], key, value)
            except Exception as e:
                logger.warning(f"Could not load service config: {e}, using defaults")
        
        return default_services

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.stop_event.set()
        sys.exit(0)

    async def check_service_health(self, service: ServiceConfig) -> bool:
        """Check if a service is healthy and ready for testing"""
        try:
            import httpx
            async with httpx.AsyncClient(timeout=10.0) as client:
                response = await client.get(f"http://localhost:{service.port}{service.health_endpoint}")
                return response.status_code == 200
        except Exception as e:
            logger.warning(f"Health check failed for {service.name}: {e}")
            return False

    async def wait_for_dependencies(self, service: ServiceConfig, max_wait: int = 120) -> bool:
        """Wait for service dependencies to be ready"""
        if not service.dependencies:
            return True
            
        logger.info(f"Waiting for dependencies of {service.name}: {service.dependencies}")
        start_time = time.time()
        
        while time.time() - start_time < max_wait:
            if self.stop_event.is_set():
                return False
                
            all_ready = True
            for dep_name in service.dependencies:
                if dep_name in self.services:
                    dep_service = self.services[dep_name]
                    if not await self.check_service_health(dep_service):
                        all_ready = False
                        break
                else:
                    # Infrastructure dependencies (postgres, redis)
                    if not await self._check_infrastructure_health(dep_name):
                        all_ready = False
                        break
            
            if all_ready:
                logger.info(f"All dependencies ready for {service.name}")
                return True
                
            await asyncio.sleep(2)
        
        logger.error(f"Timeout waiting for dependencies of {service.name}")
        return False

    async def _check_infrastructure_health(self, service_name: str) -> bool:
        """Check health of infrastructure services"""
        try:
            if service_name == "postgres":
                # Check PostgreSQL connection
                import asyncpg
                conn = await asyncpg.connect("postgresql://postgres:postgres@localhost:5432/pyairtable")
                await conn.close()
                return True
            elif service_name == "redis":
                # Check Redis connection
                import redis.asyncio as redis
                r = redis.Redis(host='localhost', port=6379, db=0)
                await r.ping()
                await r.close()
                return True
        except Exception as e:
            logger.debug(f"Infrastructure health check failed for {service_name}: {e}")
            return False
        
        return False

    async def run_service_tests(self, service: ServiceConfig, categories: List[TestCategory]) -> List[TestResult]:
        """Run tests for a specific service"""
        results = []
        
        # Wait for dependencies
        if not await self.wait_for_dependencies(service):
            result = TestResult(
                service=service.name,
                category=TestCategory.CRITICAL,
                test_name="dependency_check",
                status=TestStatus.FAILED,
                duration=0.0,
                error_message="Service dependencies not ready"
            )
            return [result]
        
        # Check service health
        if not await self.check_service_health(service):
            logger.warning(f"Service {service.name} not healthy, attempting to test anyway")
        
        # Run tests for each category
        for category in categories:
            if self.stop_event.is_set():
                break
                
            test_result = await self._execute_service_category_test(service, category)
            results.append(test_result)
            
            with self.lock:
                self.test_results.append(test_result)
                self.completed_tests.add(f"{service.name}:{category.value}")
        
        return results

    async def _execute_service_category_test(self, service: ServiceConfig, category: TestCategory) -> TestResult:
        """Execute tests for a specific service and category"""
        test_id = f"{service.name}:{category.value}"
        
        with self.lock:
            self.running_tests.add(test_id)
        
        start_time = datetime.now()
        
        try:
            # Build test command based on service type and category
            test_command = self._build_test_command(service, category)
            
            logger.info(f"Running {category.value} tests for {service.name}: {test_command}")
            
            # Execute test command
            process = await asyncio.create_subprocess_shell(
                test_command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=Path.cwd()
            )
            
            try:
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(),
                    timeout=service.test_timeout
                )
                
                end_time = datetime.now()
                duration = (end_time - start_time).total_seconds()
                
                # Parse test results
                test_status = TestStatus.PASSED if process.returncode == 0 else TestStatus.FAILED
                error_message = stderr.decode() if stderr else None
                
                # Extract performance metrics if available
                performance_metrics = self._extract_performance_metrics(stdout.decode())
                
                # Extract coverage if available
                coverage = self._extract_coverage(stdout.decode())
                
                result = TestResult(
                    service=service.name,
                    category=category,
                    test_name=f"{service.name}_{category.value}_tests",
                    status=test_status,
                    duration=duration,
                    error_message=error_message,
                    performance_metrics=performance_metrics,
                    coverage=coverage,
                    start_time=start_time,
                    end_time=end_time
                )
                
                logger.info(f"Completed {test_id}: {test_status.value} in {duration:.2f}s")
                return result
                
            except asyncio.TimeoutError:
                process.kill()
                await process.wait()
                
                end_time = datetime.now()
                duration = (end_time - start_time).total_seconds()
                
                result = TestResult(
                    service=service.name,
                    category=category,
                    test_name=f"{service.name}_{category.value}_tests",
                    status=TestStatus.TIMEOUT,
                    duration=duration,
                    error_message=f"Test timeout after {service.test_timeout}s",
                    start_time=start_time,
                    end_time=end_time
                )
                
                logger.error(f"Test timeout for {test_id}")
                return result
                
        except Exception as e:
            end_time = datetime.now()
            duration = (end_time - start_time).total_seconds()
            
            result = TestResult(
                service=service.name,
                category=category,
                test_name=f"{service.name}_{category.value}_tests",
                status=TestStatus.FAILED,
                duration=duration,
                error_message=str(e),
                start_time=start_time,
                end_time=end_time
            )
            
            logger.error(f"Test execution failed for {test_id}: {e}")
            return result
        
        finally:
            with self.lock:
                self.running_tests.discard(test_id)

    def _build_test_command(self, service: ServiceConfig, category: TestCategory) -> str:
        """Build test command based on service type and category"""
        base_command = service.test_command
        
        # Add category-specific test patterns
        if service.type == ServiceType.FRONTEND:
            if category == TestCategory.CRITICAL:
                return f"{base_command} --testNamePattern='critical|auth|login'"
            elif category == TestCategory.PERFORMANCE:
                return f"{base_command} --testNamePattern='performance|load'"
            elif category == TestCategory.SECURITY:
                return f"{base_command} --testNamePattern='security|auth|xss|csrf'"
            else:
                return base_command
                
        elif service.type in [ServiceType.GO_SERVICE, ServiceType.PYTHON_SERVICE]:
            if category == TestCategory.CRITICAL:
                return f"{base_command} -run TestCritical"
            elif category == TestCategory.PERFORMANCE:
                return f"{base_command} -run TestPerformance -bench=."
            elif category == TestCategory.SECURITY:
                return f"{base_command} -run TestSecurity"
            else:
                return base_command
        
        return base_command

    def _extract_performance_metrics(self, output: str) -> Optional[Dict[str, Any]]:
        """Extract performance metrics from test output"""
        metrics = {}
        
        # Look for common performance indicators
        lines = output.split('\n')
        for line in lines:
            if 'response time' in line.lower():
                try:
                    # Extract numeric value
                    import re
                    match = re.search(r'(\d+(?:\.\d+)?)\s*ms', line)
                    if match:
                        metrics['response_time_ms'] = float(match.group(1))
                except:
                    pass
            
            if 'memory usage' in line.lower():
                try:
                    match = re.search(r'(\d+(?:\.\d+)?)\s*mb', line)
                    if match:
                        metrics['memory_usage_mb'] = float(match.group(1))
                except:
                    pass
        
        return metrics if metrics else None

    def _extract_coverage(self, output: str) -> Optional[float]:
        """Extract test coverage from output"""
        try:
            import re
            # Look for coverage percentage
            match = re.search(r'coverage[:\s]+(\d+(?:\.\d+)?)%', output, re.IGNORECASE)
            if match:
                return float(match.group(1))
        except:
            pass
        
        return None

    async def run_parallel_tests(self, 
                                services: Optional[List[str]] = None,
                                categories: Optional[List[TestCategory]] = None,
                                max_parallel: int = 6) -> ExecutionSummary:
        """Run tests in parallel across specified services and categories"""
        
        # Default to all services and critical/regression categories
        if services is None:
            services = list(self.services.keys())
        if categories is None:
            categories = [TestCategory.CRITICAL, TestCategory.REGRESSION]
        
        logger.info(f"Starting parallel test execution:")
        logger.info(f"  Services: {services}")
        logger.info(f"  Categories: {[c.value for c in categories]}")
        logger.info(f"  Max parallel: {max_parallel}")
        logger.info(f"  Execution ID: {self.execution_id}")
        
        # Filter services to only those that exist
        valid_services = [s for s in services if s in self.services]
        if len(valid_services) != len(services):
            missing = set(services) - set(valid_services)
            logger.warning(f"Unknown services skipped: {missing}")
        
        # Create execution plan
        execution_tasks = []
        for service_name in valid_services:
            service = self.services[service_name]
            task = self.run_service_tests(service, categories)
            execution_tasks.append((service_name, task))
        
        # Execute tests with limited concurrency
        semaphore = asyncio.Semaphore(max_parallel)
        
        async def run_with_semaphore(service_name: str, task):
            async with semaphore:
                return await task
        
        # Start all tasks
        running_tasks = [
            run_with_semaphore(service_name, task) 
            for service_name, task in execution_tasks
        ]
        
        # Wait for completion with progress monitoring
        completed_results = []
        progress_task = asyncio.create_task(self._monitor_progress())
        
        try:
            results = await asyncio.gather(*running_tasks, return_exceptions=True)
            
            for i, result in enumerate(results):
                service_name = valid_services[i]
                if isinstance(result, Exception):
                    logger.error(f"Service {service_name} failed: {result}")
                    # Create failure result
                    failure_result = TestResult(
                        service=service_name,
                        category=TestCategory.CRITICAL,
                        test_name="execution_error",
                        status=TestStatus.FAILED,
                        duration=0.0,
                        error_message=str(result)
                    )
                    completed_results.append([failure_result])
                else:
                    completed_results.extend(result)
        
        finally:
            progress_task.cancel()
        
        # Generate execution summary
        summary = self._generate_execution_summary(completed_results)
        
        # Save results
        await self._save_results(summary)
        
        return summary

    async def _monitor_progress(self):
        """Monitor and log test execution progress"""
        try:
            while not self.stop_event.is_set():
                with self.lock:
                    running_count = len(self.running_tests)
                    completed_count = len(self.completed_tests)
                    total_expected = len(self.services) * 2  # Assuming 2 categories on average
                
                if running_count > 0 or completed_count < total_expected:
                    logger.info(f"Progress: {completed_count} completed, {running_count} running")
                    if self.running_tests:
                        logger.debug(f"Currently running: {list(self.running_tests)}")
                
                await asyncio.sleep(10)
        except asyncio.CancelledError:
            pass

    def _generate_execution_summary(self, all_results: List[List[TestResult]]) -> ExecutionSummary:
        """Generate execution summary from all test results"""
        
        # Flatten results
        flat_results = []
        for result_list in all_results:
            if isinstance(result_list, list):
                flat_results.extend(result_list)
            else:
                flat_results.append(result_list)
        
        # Calculate metrics
        total_tests = len(flat_results)
        passed_tests = len([r for r in flat_results if r.status == TestStatus.PASSED])
        failed_tests = len([r for r in flat_results if r.status == TestStatus.FAILED])
        skipped_tests = len([r for r in flat_results if r.status == TestStatus.SKIPPED])
        
        total_duration = sum(r.duration for r in flat_results)
        pass_rate = (passed_tests / total_tests * 100) if total_tests > 0 else 0
        
        # Collect services and categories tested
        services_tested = list(set(r.service for r in flat_results))
        categories_tested = list(set(r.category for r in flat_results))
        
        # Performance summary
        performance_metrics = [r.performance_metrics for r in flat_results if r.performance_metrics]
        performance_summary = {}
        if performance_metrics:
            # Average response times
            response_times = [m.get('response_time_ms', 0) for m in performance_metrics if 'response_time_ms' in m]
            if response_times:
                performance_summary['avg_response_time_ms'] = sum(response_times) / len(response_times)
        
        # Coverage summary
        coverage_results = [(r.service, r.coverage) for r in flat_results if r.coverage is not None]
        coverage_summary = {service: coverage for service, coverage in coverage_results}
        
        return ExecutionSummary(
            total_tests=total_tests,
            passed_tests=passed_tests,
            failed_tests=failed_tests,
            skipped_tests=skipped_tests,
            total_duration=total_duration,
            pass_rate=pass_rate,
            services_tested=services_tested,
            categories_tested=categories_tested,
            performance_summary=performance_summary,
            coverage_summary=coverage_summary
        )

    async def _save_results(self, summary: ExecutionSummary):
        """Save test results and summary to files"""
        
        # Ensure results directory exists
        results_dir = Path("tests/reports/parallel-execution")
        results_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save detailed results
        results_file = results_dir / f"results_{self.execution_id}_{timestamp}.json"
        with open(results_file, 'w') as f:
            json.dump({
                'execution_id': self.execution_id,
                'timestamp': timestamp,
                'summary': asdict(summary),
                'detailed_results': [asdict(r) for r in self.test_results]
            }, f, indent=2, default=str)
        
        # Save summary report
        summary_file = results_dir / f"summary_{self.execution_id}_{timestamp}.md"
        with open(summary_file, 'w') as f:
            f.write(self._generate_markdown_report(summary))
        
        logger.info(f"Results saved:")
        logger.info(f"  Detailed: {results_file}")
        logger.info(f"  Summary: {summary_file}")

    def _generate_markdown_report(self, summary: ExecutionSummary) -> str:
        """Generate markdown report from execution summary"""
        
        report = f"""# PyAirtable Parallel Test Execution Report

## Execution Summary
- **Execution ID**: {self.execution_id}
- **Timestamp**: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
- **Duration**: {summary.total_duration:.2f} seconds

## Test Results
- **Total Tests**: {summary.total_tests}
- **Passed**: {summary.passed_tests} ✅
- **Failed**: {summary.failed_tests} ❌
- **Skipped**: {summary.skipped_tests} ⏭️
- **Pass Rate**: {summary.pass_rate:.1f}%

## Services Tested
{chr(10).join(f"- {service}" for service in summary.services_tested)}

## Categories Tested  
{chr(10).join(f"- {category.value}" for category in summary.categories_tested)}

## Performance Summary
"""
        
        if summary.performance_summary:
            for metric, value in summary.performance_summary.items():
                report += f"- **{metric}**: {value:.2f}\n"
        else:
            report += "- No performance metrics collected\n"
        
        report += "\n## Coverage Summary\n"
        if summary.coverage_summary:
            for service, coverage in summary.coverage_summary.items():
                report += f"- **{service}**: {coverage:.1f}%\n"
        else:
            report += "- No coverage data collected\n"
        
        # Add individual test results
        report += "\n## Detailed Results\n"
        for result in self.test_results:
            status_emoji = "✅" if result.status == TestStatus.PASSED else "❌"
            report += f"- {status_emoji} **{result.service}** - {result.category.value} - {result.duration:.2f}s"
            if result.error_message:
                report += f" - Error: {result.error_message[:100]}..."
            report += "\n"
        
        return report

# CLI and utility functions

async def run_critical_tests():
    """Run critical path tests across all services"""
    orchestrator = ServiceTestOrchestrator()
    return await orchestrator.run_parallel_tests(
        categories=[TestCategory.CRITICAL],
        max_parallel=3
    )

async def run_regression_tests():
    """Run regression tests across all services"""
    orchestrator = ServiceTestOrchestrator()
    return await orchestrator.run_parallel_tests(
        categories=[TestCategory.REGRESSION],
        max_parallel=4
    )

async def run_comprehensive_tests():
    """Run comprehensive test suite"""
    orchestrator = ServiceTestOrchestrator()
    return await orchestrator.run_parallel_tests(
        categories=[TestCategory.CRITICAL, TestCategory.REGRESSION, TestCategory.PERFORMANCE],
        max_parallel=6
    )

async def run_service_specific_tests(service_name: str):
    """Run all tests for a specific service"""
    orchestrator = ServiceTestOrchestrator()
    return await orchestrator.run_parallel_tests(
        services=[service_name],
        categories=[TestCategory.CRITICAL, TestCategory.REGRESSION, TestCategory.PERFORMANCE, TestCategory.SECURITY],
        max_parallel=1
    )

if __name__ == "__main__":
    import sys
    
    async def main():
        if len(sys.argv) > 1:
            command = sys.argv[1]
            
            if command == "critical":
                summary = await run_critical_tests()
            elif command == "regression":
                summary = await run_regression_tests()
            elif command == "comprehensive":
                summary = await run_comprehensive_tests()
            elif command.startswith("service:"):
                service_name = command.split(":", 1)[1]
                summary = await run_service_specific_tests(service_name)
            else:
                print("Usage: python service-test-orchestrator.py [critical|regression|comprehensive|service:SERVICE_NAME]")
                return
        else:
            # Default to critical tests
            summary = await run_critical_tests()
        
        print(f"\n{'='*60}")
        print("PARALLEL TEST EXECUTION SUMMARY")
        print(f"{'='*60}")
        print(f"Total Tests: {summary.total_tests}")
        print(f"Passed: {summary.passed_tests}")
        print(f"Failed: {summary.failed_tests}")
        print(f"Pass Rate: {summary.pass_rate:.1f}%")
        print(f"Duration: {summary.total_duration:.2f}s")
        print(f"Services: {', '.join(summary.services_tested)}")
        print(f"{'='*60}")
        
        # Exit with appropriate code
        exit_code = 0 if summary.pass_rate >= 85.0 else 1
        sys.exit(exit_code)
    
    asyncio.run(main())