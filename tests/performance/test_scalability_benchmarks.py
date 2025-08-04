"""
Scalability benchmarks for PyAirtable services.
Tests system behavior as load increases and identifies bottlenecks.
"""

import pytest
import asyncio
import httpx
import time
import statistics
import json
import psutil
import logging
from typing import Dict, List, Any, Tuple
from dataclasses import dataclass, field
from concurrent.futures import ThreadPoolExecutor
import aiofiles
import os

logger = logging.getLogger(__name__)


@dataclass
class ScalabilityMetrics:
    """Scalability test metrics"""
    concurrent_users: int
    requests_per_second: float
    avg_response_time: float
    p95_response_time: float
    error_rate: float
    cpu_usage: float
    memory_usage: float
    throughput_efficiency: float  # requests/second per CPU core


@pytest.mark.performance
class TestScalabilityBenchmarks:
    """Scalability benchmarking for PyAirtable services"""

    @pytest.fixture(autouse=True)
    async def setup_scalability_test(self, test_environment, performance_config):
        """Setup scalability testing environment"""
        self.test_environment = test_environment
        self.performance_config = performance_config
        self.scalability_results = []
        
        # Create results directory
        os.makedirs("tests/reports/performance", exist_ok=True)
        
        yield
        
        # Generate scalability report
        await self.generate_scalability_report()

    async def test_horizontal_scaling_simulation(self, performance_config):
        """Test how system performance scales with increasing load"""
        # Test different load levels to find scaling characteristics
        load_levels = [5, 10, 20, 50, 100, 200]  # Concurrent users
        
        for users in load_levels:
            logger.info(f"Testing scalability with {users} concurrent users")
            
            # Run benchmark at this load level
            metrics = await self._run_scalability_benchmark(users)
            self.scalability_results.append(metrics)
            
            # Stop if system is degrading significantly
            if metrics.error_rate > 0.50:  # 50% error rate
                logger.warning(f"System degradation detected at {users} users")
                break
            
            # Brief pause between tests
            await asyncio.sleep(5)
        
        # Analyze scaling characteristics
        await self._analyze_scaling_characteristics()

    async def test_vertical_scaling_cpu_bound(self, performance_config):
        """Test CPU-bound operations scaling"""
        cpu_intensive_scenarios = [
            {
                "name": "data_processing",
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/process-data",
                "json": {
                    "data": list(range(1000)),  # Process 1000 numbers
                    "operation": "sort_and_analyze"
                }
            },
            {
                "name": "ai_inference",
                "method": "POST",
                "url": f"{self.test_environment.llm_orchestrator_url}/chat/analyze",
                "json": {
                    "message": "Analyze this complex data pattern and provide insights",
                    "data": {"values": list(range(100))}
                }
            }
        ]
        
        # Test with increasing computational load
        for concurrent_requests in [1, 5, 10, 20]:
            logger.info(f"Testing CPU scaling with {concurrent_requests} concurrent CPU-intensive requests")
            
            cpu_metrics = await self._benchmark_cpu_intensive_operations(
                cpu_intensive_scenarios, 
                concurrent_requests
            )
            
            cpu_metrics.concurrent_users = concurrent_requests
            self.scalability_results.append(cpu_metrics)

    async def test_io_bound_scaling(self, performance_config):
        """Test I/O-bound operations scaling"""
        io_intensive_scenarios = [
            {
                "name": "database_query",
                "method": "GET",
                "url": f"{self.test_environment.api_gateway_url}/api/tables",
                "params": {"limit": 1000}
            },
            {
                "name": "external_api_call",
                "method": "GET",
                "url": f"{self.test_environment.airtable_gateway_url}/tables/records",
                "params": {"table_id": "test_table", "limit": 500}
            },
            {
                "name": "file_upload",
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/files/upload",
                "files": {"file": ("test.txt", "x" * 1024 * 100)}  # 100KB file
            }
        ]
        
        # Test with increasing I/O load
        for concurrent_requests in [10, 25, 50, 100]:
            logger.info(f"Testing I/O scaling with {concurrent_requests} concurrent I/O requests")
            
            io_metrics = await self._benchmark_io_intensive_operations(
                io_intensive_scenarios,
                concurrent_requests
            )
            
            io_metrics.concurrent_users = concurrent_requests
            self.scalability_results.append(io_metrics)

    async def test_memory_scaling_patterns(self, performance_config):
        """Test memory usage scaling patterns"""
        memory_intensive_scenarios = [
            {
                "name": "large_dataset_processing",
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/process-large-dataset",
                "json": {
                    "dataset": [{"id": i, "data": "x" * 1000} for i in range(1000)]
                }
            },
            {
                "name": "cache_population",
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/cache-populate",
                "json": {
                    "size": "10MB",
                    "entries": 10000
                }
            }
        ]
        
        # Monitor memory usage patterns
        initial_memory = psutil.virtual_memory().percent
        
        for data_size_mb in [1, 5, 10, 20, 50]:
            logger.info(f"Testing memory scaling with {data_size_mb}MB data operations")
            
            # Adjust scenario data size
            adjusted_scenarios = []
            for scenario in memory_intensive_scenarios:
                scenario_copy = scenario.copy()
                if "dataset" in scenario_copy.get("json", {}):
                    # Adjust dataset size
                    records_per_mb = 100
                    num_records = data_size_mb * records_per_mb
                    scenario_copy["json"]["dataset"] = [
                        {"id": i, "data": "x" * 1000} for i in range(num_records)
                    ]
                adjusted_scenarios.append(scenario_copy)
            
            memory_metrics = await self._benchmark_memory_operations(adjusted_scenarios)
            memory_metrics.concurrent_users = data_size_mb  # Using as size indicator
            
            self.scalability_results.append(memory_metrics)
            
            # Check for memory leaks
            current_memory = psutil.virtual_memory().percent
            memory_increase = current_memory - initial_memory
            
            if memory_increase > 20:  # 20% memory increase
                logger.warning(f"Significant memory increase detected: {memory_increase:.1f}%")

    async def test_connection_pool_scaling(self, db_connection, performance_config):
        """Test database connection pool scaling"""
        if db_connection is None:
            pytest.skip("Database not available")
        
        # Test with increasing concurrent database operations
        connection_loads = [5, 10, 25, 50, 100, 200]
        
        for concurrent_connections in connection_loads:
            logger.info(f"Testing connection pool with {concurrent_connections} concurrent connections")
            
            pool_metrics = await self._benchmark_connection_pool(concurrent_connections)
            pool_metrics.concurrent_users = concurrent_connections
            
            self.scalability_results.append(pool_metrics)
            
            # Stop if connection pool is exhausted
            if pool_metrics.error_rate > 0.30:  # 30% connection failures
                logger.warning(f"Connection pool exhaustion at {concurrent_connections} connections")
                break

    async def test_cache_scaling_efficiency(self, redis_client, performance_config):
        """Test cache scaling efficiency"""
        if redis_client is None:
            pytest.skip("Redis not available")
        
        cache_operations = ["SET", "GET", "DEL", "INCR"]
        
        for operations_per_second in [100, 500, 1000, 2000, 5000]:
            logger.info(f"Testing cache scaling at {operations_per_second} ops/sec")
            
            cache_metrics = await self._benchmark_cache_operations(
                redis_client,
                operations_per_second
            )
            
            cache_metrics.concurrent_users = operations_per_second  # Using as ops indicator
            self.scalability_results.append(cache_metrics)

    async def _run_scalability_benchmark(self, concurrent_users: int) -> ScalabilityMetrics:
        """Run scalability benchmark with specified number of users"""
        token = await self._get_test_token()
        
        # Mixed workload scenarios
        scenarios = [
            {
                "name": "api_read",
                "method": "GET",
                "url": f"{self.test_environment.api_gateway_url}/health",
                "weight": 0.4
            },
            {
                "name": "api_write",
                "method": "POST",
                "url": f"{self.test_environment.api_gateway_url}/api/test-data",
                "json": {"test": True, "timestamp": time.time()},
                "headers": {"Authorization": f"Bearer {token}"},
                "weight": 0.3
            },
            {
                "name": "auth_check",
                "method": "GET",
                "url": f"{self.test_environment.api_gateway_url}/auth/profile",
                "headers": {"Authorization": f"Bearer {token}"},
                "weight": 0.3
            }
        ]
        
        # Run benchmark
        start_time = time.time()
        cpu_before = psutil.cpu_percent(interval=1)
        memory_before = psutil.virtual_memory().percent
        
        results = await self._execute_concurrent_requests(scenarios, concurrent_users, 30)  # 30 second test
        
        end_time = time.time()
        cpu_after = psutil.cpu_percent(interval=1)
        memory_after = psutil.virtual_memory().percent
        
        # Calculate metrics
        total_requests = len(results)
        successful_requests = len([r for r in results if r.get("success", False)])
        response_times = [r.get("response_time", 0) for r in results if r.get("success", False)]
        
        test_duration = end_time - start_time
        requests_per_second = total_requests / test_duration if test_duration > 0 else 0
        error_rate = (total_requests - successful_requests) / total_requests if total_requests > 0 else 0
        
        avg_response_time = statistics.mean(response_times) if response_times else 0
        p95_response_time = statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0
        
        cpu_usage = (cpu_before + cpu_after) / 2
        memory_usage = (memory_before + memory_after) / 2
        
        # Throughput efficiency (requests per second per CPU core)
        cpu_cores = psutil.cpu_count()
        throughput_efficiency = requests_per_second / cpu_cores if cpu_cores > 0 else 0
        
        return ScalabilityMetrics(
            concurrent_users=concurrent_users,
            requests_per_second=requests_per_second,
            avg_response_time=avg_response_time,
            p95_response_time=p95_response_time,
            error_rate=error_rate,
            cpu_usage=cpu_usage,
            memory_usage=memory_usage,
            throughput_efficiency=throughput_efficiency
        )

    async def _benchmark_cpu_intensive_operations(self, scenarios: List[Dict], concurrent_requests: int) -> ScalabilityMetrics:
        """Benchmark CPU-intensive operations"""
        start_time = time.time()
        cpu_before = psutil.cpu_percent(interval=1)
        
        results = await self._execute_concurrent_requests(scenarios, concurrent_requests, 60)
        
        end_time = time.time()
        cpu_after = psutil.cpu_percent(interval=1)
        
        # Calculate CPU-specific metrics
        total_requests = len(results)
        successful_requests = len([r for r in results if r.get("success", False)])
        response_times = [r.get("response_time", 0) for r in results if r.get("success", False)]
        
        test_duration = end_time - start_time
        requests_per_second = total_requests / test_duration if test_duration > 0 else 0
        error_rate = (total_requests - successful_requests) / total_requests if total_requests > 0 else 0
        
        avg_response_time = statistics.mean(response_times) if response_times else 0
        p95_response_time = statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0
        
        cpu_usage = (cpu_before + cpu_after) / 2
        cpu_cores = psutil.cpu_count()
        throughput_efficiency = requests_per_second / cpu_cores if cpu_cores > 0 else 0
        
        return ScalabilityMetrics(
            concurrent_users=concurrent_requests,
            requests_per_second=requests_per_second,
            avg_response_time=avg_response_time,
            p95_response_time=p95_response_time,
            error_rate=error_rate,
            cpu_usage=cpu_usage,
            memory_usage=psutil.virtual_memory().percent,
            throughput_efficiency=throughput_efficiency
        )

    async def _benchmark_io_intensive_operations(self, scenarios: List[Dict], concurrent_requests: int) -> ScalabilityMetrics:
        """Benchmark I/O-intensive operations"""
        start_time = time.time()
        
        results = await self._execute_concurrent_requests(scenarios, concurrent_requests, 45)
        
        end_time = time.time()
        
        # Calculate I/O-specific metrics
        total_requests = len(results)
        successful_requests = len([r for r in results if r.get("success", False)])
        response_times = [r.get("response_time", 0) for r in results if r.get("success", False)]
        
        test_duration = end_time - start_time
        requests_per_second = total_requests / test_duration if test_duration > 0 else 0
        error_rate = (total_requests - successful_requests) / total_requests if total_requests > 0 else 0
        
        avg_response_time = statistics.mean(response_times) if response_times else 0
        p95_response_time = statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0
        
        return ScalabilityMetrics(
            concurrent_users=concurrent_requests,
            requests_per_second=requests_per_second,
            avg_response_time=avg_response_time,
            p95_response_time=p95_response_time,
            error_rate=error_rate,
            cpu_usage=psutil.cpu_percent(interval=1),
            memory_usage=psutil.virtual_memory().percent,
            throughput_efficiency=requests_per_second / psutil.cpu_count()
        )

    async def _benchmark_memory_operations(self, scenarios: List[Dict]) -> ScalabilityMetrics:
        """Benchmark memory-intensive operations"""
        memory_before = psutil.virtual_memory().percent
        start_time = time.time()
        
        results = await self._execute_concurrent_requests(scenarios, 10, 30)  # Lower concurrency for memory ops
        
        end_time = time.time()
        memory_after = psutil.virtual_memory().percent
        
        total_requests = len(results)
        successful_requests = len([r for r in results if r.get("success", False)])
        response_times = [r.get("response_time", 0) for r in results if r.get("success", False)]
        
        test_duration = end_time - start_time
        requests_per_second = total_requests / test_duration if test_duration > 0 else 0
        error_rate = (total_requests - successful_requests) / total_requests if total_requests > 0 else 0
        
        avg_response_time = statistics.mean(response_times) if response_times else 0
        p95_response_time = statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0
        
        return ScalabilityMetrics(
            concurrent_users=10,
            requests_per_second=requests_per_second,
            avg_response_time=avg_response_time,
            p95_response_time=p95_response_time,
            error_rate=error_rate,
            cpu_usage=psutil.cpu_percent(interval=1),
            memory_usage=memory_after,
            throughput_efficiency=requests_per_second / psutil.cpu_count()
        )

    async def _benchmark_connection_pool(self, concurrent_connections: int) -> ScalabilityMetrics:
        """Benchmark database connection pool scaling"""
        import asyncpg
        
        start_time = time.time()
        results = []
        
        async def database_operation():
            """Single database operation"""
            operation_start = time.time()
            try:
                conn = await asyncpg.connect(self.test_environment.database_url)
                
                # Simple query operation
                await conn.fetchval("SELECT 1")
                await conn.close()
                
                return {
                    "success": True,
                    "response_time": time.time() - operation_start
                }
            except Exception as e:
                return {
                    "success": False,
                    "response_time": time.time() - operation_start,
                    "error": str(e)
                }
        
        # Execute concurrent database operations
        tasks = [database_operation() for _ in range(concurrent_connections)]
        results = await asyncio.gather(*tasks)
        
        end_time = time.time()
        
        total_requests = len(results)
        successful_requests = len([r for r in results if r.get("success", False)])
        response_times = [r.get("response_time", 0) for r in results if r.get("success", False)]
        
        test_duration = end_time - start_time
        requests_per_second = total_requests / test_duration if test_duration > 0 else 0
        error_rate = (total_requests - successful_requests) / total_requests if total_requests > 0 else 0
        
        avg_response_time = statistics.mean(response_times) if response_times else 0
        p95_response_time = statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0
        
        return ScalabilityMetrics(
            concurrent_users=concurrent_connections,
            requests_per_second=requests_per_second,
            avg_response_time=avg_response_time,
            p95_response_time=p95_response_time,
            error_rate=error_rate,
            cpu_usage=psutil.cpu_percent(interval=1),
            memory_usage=psutil.virtual_memory().percent,
            throughput_efficiency=requests_per_second / psutil.cpu_count()
        )

    async def _benchmark_cache_operations(self, redis_client, target_ops_per_second: int) -> ScalabilityMetrics:
        """Benchmark cache operations scaling"""
        start_time = time.time()
        operations_completed = 0
        errors = 0
        response_times = []
        
        # Run for 30 seconds
        test_duration = 30
        end_time = start_time + test_duration
        
        while time.time() < end_time:
            operation_start = time.time()
            
            try:
                # Mix of cache operations
                operation = operations_completed % 4
                key = f"benchmark_key_{operations_completed}"
                
                if operation == 0:  # SET
                    await redis_client.set(key, f"value_{operations_completed}")
                elif operation == 1:  # GET
                    await redis_client.get(key)
                elif operation == 2:  # DEL
                    await redis_client.delete(key)
                elif operation == 3:  # INCR
                    await redis_client.incr(f"counter_{operations_completed % 100}")
                
                response_times.append(time.time() - operation_start)
                operations_completed += 1
                
                # Rate limiting to target ops/sec
                target_interval = 1.0 / target_ops_per_second
                actual_interval = time.time() - operation_start
                if actual_interval < target_interval:
                    await asyncio.sleep(target_interval - actual_interval)
                
            except Exception as e:
                errors += 1
                response_times.append(time.time() - operation_start)
        
        actual_duration = time.time() - start_time
        actual_ops_per_second = operations_completed / actual_duration
        error_rate = errors / operations_completed if operations_completed > 0 else 0
        
        avg_response_time = statistics.mean(response_times) if response_times else 0
        p95_response_time = statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0
        
        return ScalabilityMetrics(
            concurrent_users=target_ops_per_second,
            requests_per_second=actual_ops_per_second,
            avg_response_time=avg_response_time,
            p95_response_time=p95_response_time,
            error_rate=error_rate,
            cpu_usage=psutil.cpu_percent(interval=1),
            memory_usage=psutil.virtual_memory().percent,
            throughput_efficiency=actual_ops_per_second / psutil.cpu_count()
        )

    async def _execute_concurrent_requests(self, scenarios: List[Dict], concurrent_users: int, duration_seconds: int) -> List[Dict]:
        """Execute concurrent requests for specified duration"""
        results = []
        end_time = time.time() + duration_seconds
        
        async def user_session():
            """Simulate user session making requests"""
            async with httpx.AsyncClient(timeout=30.0) as client:
                while time.time() < end_time:
                    # Select random scenario
                    import random
                    scenario = random.choice(scenarios)
                    
                    request_start = time.time()
                    
                    try:
                        if scenario["method"] == "GET":
                            response = await client.get(
                                scenario["url"],
                                headers=scenario.get("headers", {}),
                                params=scenario.get("params", {})
                            )
                        elif scenario["method"] == "POST":
                            if "files" in scenario:
                                response = await client.post(
                                    scenario["url"],
                                    headers=scenario.get("headers", {}),
                                    files=scenario["files"]
                                )
                            else:
                                response = await client.post(
                                    scenario["url"],
                                    headers=scenario.get("headers", {}),
                                    json=scenario.get("json", {})
                                )
                        
                        request_time = time.time() - request_start
                        
                        results.append({
                            "scenario": scenario["name"],
                            "success": response.status_code < 400,
                            "status_code": response.status_code,
                            "response_time": request_time
                        })
                        
                    except Exception as e:
                        request_time = time.time() - request_start
                        results.append({
                            "scenario": scenario["name"],
                            "success": False,
                            "status_code": 0,
                            "response_time": request_time,
                            "error": str(e)
                        })
                    
                    # Small delay between requests
                    await asyncio.sleep(0.1)
        
        # Start concurrent user sessions
        tasks = [user_session() for _ in range(concurrent_users)]
        await asyncio.gather(*tasks, return_exceptions=True)
        
        return results

    async def _analyze_scaling_characteristics(self):
        """Analyze scaling characteristics from test results"""
        if len(self.scalability_results) < 2:
            return
        
        logger.info("Scaling Analysis:")
        
        # Find optimal performance point
        optimal_throughput = 0
        optimal_users = 0
        
        for metrics in self.scalability_results:
            efficiency_score = (
                metrics.requests_per_second * 
                (1 - metrics.error_rate) * 
                (2.0 / max(metrics.avg_response_time, 0.1))  # Favor low response times
            )
            
            if efficiency_score > optimal_throughput:
                optimal_throughput = efficiency_score
                optimal_users = metrics.concurrent_users
            
            logger.info(f"  {metrics.concurrent_users} users: "
                       f"{metrics.requests_per_second:.1f} req/s, "
                       f"{metrics.avg_response_time:.3f}s avg, "
                       f"{metrics.error_rate:.1%} errors, "
                       f"Efficiency: {efficiency_score:.1f}")
        
        logger.info(f"Optimal performance: {optimal_users} concurrent users")
        
        # Identify scaling bottlenecks
        cpu_bottleneck = any(m.cpu_usage > 80 for m in self.scalability_results)
        memory_bottleneck = any(m.memory_usage > 85 for m in self.scalability_results)
        
        if cpu_bottleneck:
            logger.warning("CPU bottleneck detected - consider vertical scaling")
        if memory_bottleneck:
            logger.warning("Memory bottleneck detected - monitor memory usage")

    async def _get_test_token(self) -> str:
        """Get authentication token for testing"""
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.test_environment.auth_service_url}/auth/login",
                    json={
                        "email": "test@example.com",
                        "password": "test_password"
                    }
                )
                if response.status_code == 200:
                    return response.json().get("access_token", "mock_token")
        except Exception:
            pass
        
        return "mock_token_for_testing"

    async def generate_scalability_report(self):
        """Generate comprehensive scalability report"""
        if not self.scalability_results:
            return
        
        report_data = []
        
        for metrics in self.scalability_results:
            report_data.append({
                "Concurrent Users": metrics.concurrent_users,
                "Requests/sec": f"{metrics.requests_per_second:.2f}",
                "Avg Response Time (s)": f"{metrics.avg_response_time:.3f}",
                "P95 Response Time (s)": f"{metrics.p95_response_time:.3f}",
                "Error Rate (%)": f"{metrics.error_rate * 100:.2f}",
                "CPU Usage (%)": f"{metrics.cpu_usage:.1f}",
                "Memory Usage (%)": f"{metrics.memory_usage:.1f}",
                "Throughput Efficiency": f"{metrics.throughput_efficiency:.2f}"
            })
        
        # Save report
        report_file = "tests/reports/performance/scalability_report.json"
        async with aiofiles.open(report_file, 'w') as f:
            await f.write(json.dumps(report_data, indent=2))
        
        logger.info("Scalability report generated:")
        for data in report_data:
            logger.info(f"  {data['Concurrent Users']} users: "
                       f"{data['Requests/sec']} req/s, "
                       f"{data['Avg Response Time (s)']}s avg, "
                       f"{data['Error Rate (%)']}% errors")