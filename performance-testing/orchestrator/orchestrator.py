#!/usr/bin/env python3
"""
Performance Test Orchestrator for PyAirtable
Coordinates load testing, monitoring, and reporting
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import docker
import requests
import yaml
from dataclasses import dataclass
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class TestConfig:
    """Configuration for a performance test"""
    name: str
    type: str  # k6, jmeter, locust, artillery
    duration: int  # seconds
    virtual_users: int
    ramp_up_time: int
    target_rps: Optional[int] = None
    scenario: str = "default"
    thresholds: Dict[str, float] = None
    
    def __post_init__(self):
        if self.thresholds is None:
            self.thresholds = {
                'response_time_p95': 2000,  # ms
                'error_rate': 0.05,         # 5%
                'throughput_min': 100,      # rps
            }

@dataclass
class TestResult:
    """Results from a performance test"""
    test_name: str
    start_time: datetime
    end_time: datetime
    duration: float
    virtual_users: int
    total_requests: int
    failed_requests: int
    error_rate: float
    response_times: Dict[str, float]
    throughput: float
    passed: bool
    metrics: Dict[str, Any]

class PerformanceOrchestrator:
    """Orchestrates performance testing across multiple tools"""
    
    def __init__(self):
        self.docker_client = docker.from_env()
        self.influxdb_client = self._init_influxdb()
        self.test_configs = self._load_test_configs()
        self.results_storage = "/reports"
        
    def _init_influxdb(self) -> InfluxDBClient:
        """Initialize InfluxDB client for metrics storage"""
        url = os.getenv('INFLUXDB_URL', 'http://localhost:8086')
        token = os.getenv('INFLUXDB_TOKEN', 'k6-performance-token')
        org = os.getenv('INFLUXDB_ORG', 'pyairtable')
        
        return InfluxDBClient(url=url, token=token, org=org)
    
    def _load_test_configs(self) -> List[TestConfig]:
        """Load test configurations from file"""
        config_file = "/app/test-configs.yml"
        
        if not os.path.exists(config_file):
            # Return default configurations
            return [
                TestConfig(
                    name="smoke_test",
                    type="k6",
                    duration=60,
                    virtual_users=1,
                    ramp_up_time=10
                ),
                TestConfig(
                    name="load_test", 
                    type="k6",
                    duration=600,
                    virtual_users=50,
                    ramp_up_time=300
                ),
                TestConfig(
                    name="stress_test",
                    type="k6", 
                    duration=600,
                    virtual_users=200,
                    ramp_up_time=120
                ),
            ]
        
        with open(config_file, 'r') as f:
            config_data = yaml.safe_load(f)
            
        return [TestConfig(**config) for config in config_data.get('tests', [])]
    
    async def run_test_suite(self, suite_name: str = "full") -> List[TestResult]:
        """Run a complete test suite"""
        logger.info(f"Starting performance test suite: {suite_name}")
        
        # Pre-test system check
        if not await self._system_health_check():
            raise RuntimeError("System health check failed")
        
        results = []
        
        # Run tests based on suite
        if suite_name == "smoke":
            test_configs = [c for c in self.test_configs if c.name == "smoke_test"]
        elif suite_name == "regression":
            test_configs = [c for c in self.test_configs if c.type == "k6"]
        else:  # full suite
            test_configs = self.test_configs
        
        for config in test_configs:
            logger.info(f"Running test: {config.name}")
            
            try:
                result = await self._run_single_test(config)
                results.append(result)
                
                # Store results in InfluxDB
                await self._store_test_metrics(result)
                
                # Wait between tests
                await asyncio.sleep(30)
                
            except Exception as e:
                logger.error(f"Test {config.name} failed: {e}")
                continue
        
        # Generate comprehensive report
        await self._generate_test_report(results, suite_name)
        
        return results
    
    async def _system_health_check(self) -> bool:
        """Verify system is ready for testing"""
        logger.info("Performing system health check")
        
        checks = [
            self._check_api_gateway(),
            self._check_database(),
            self._check_redis(),
            self._check_kafka(),
        ]
        
        results = await asyncio.gather(*checks, return_exceptions=True)
        
        all_passed = all(
            result is True for result in results 
            if not isinstance(result, Exception)
        )
        
        if not all_passed:
            logger.error("System health check failed")
            for i, result in enumerate(results):
                if isinstance(result, Exception):
                    logger.error(f"Health check {i} failed: {result}")
        
        return all_passed
    
    async def _check_api_gateway(self) -> bool:
        """Check API Gateway health"""
        try:
            response = requests.get(
                "http://api-gateway:8000/api/health",
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"API Gateway health check failed: {e}")
            return False
    
    async def _check_database(self) -> bool:
        """Check database connectivity"""
        try:
            response = requests.get(
                "http://api-gateway:8000/api/health/database",
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            return False
    
    async def _check_redis(self) -> bool:
        """Check Redis connectivity"""
        try:
            response = requests.get(
                "http://api-gateway:8000/api/health/redis",
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Redis health check failed: {e}")
            return False
    
    async def _check_kafka(self) -> bool:
        """Check Kafka connectivity"""
        try:
            response = requests.get(
                "http://api-gateway:8000/api/health/kafka",
                timeout=10
            )
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Kafka health check failed: {e}")
            return False
    
    async def _run_single_test(self, config: TestConfig) -> TestResult:
        """Run a single performance test"""
        start_time = datetime.now()
        
        if config.type == "k6":
            result = await self._run_k6_test(config)
        elif config.type == "jmeter":
            result = await self._run_jmeter_test(config)
        elif config.type == "locust":
            result = await self._run_locust_test(config)
        elif config.type == "artillery":
            result = await self._run_artillery_test(config)
        else:
            raise ValueError(f"Unsupported test type: {config.type}")
        
        end_time = datetime.now()
        
        # Evaluate test results against thresholds
        passed = self._evaluate_test_results(result, config.thresholds)
        
        return TestResult(
            test_name=config.name,
            start_time=start_time,
            end_time=end_time,
            duration=(end_time - start_time).total_seconds(),
            virtual_users=config.virtual_users,
            total_requests=result.get('total_requests', 0),
            failed_requests=result.get('failed_requests', 0),
            error_rate=result.get('error_rate', 0),
            response_times=result.get('response_times', {}),
            throughput=result.get('throughput', 0),
            passed=passed,
            metrics=result
        )
    
    async def _run_k6_test(self, config: TestConfig) -> Dict[str, Any]:
        """Run K6 load test"""
        logger.info(f"Running K6 test: {config.name}")
        
        # Create K6 container with specific configuration
        container = self.docker_client.containers.run(
            "grafana/k6:latest",
            command=[
                "run",
                "/scripts/load-tests.js",
                f"--vus={config.virtual_users}",
                f"--duration={config.duration}s",
                f"--scenario={config.scenario}",
                "--out", "json=/reports/k6-results.json",
                "--out", "influxdb=http://influxdb:8086/k6-metrics"
            ],
            volumes={
                "/app/k6-load-tests.js": {"bind": "/scripts/load-tests.js", "mode": "ro"},
                "/app/test-data": {"bind": "/scripts/test-data", "mode": "ro"},
                "/reports": {"bind": "/reports", "mode": "rw"}
            },
            environment={
                "BASE_URL": "http://api-gateway:8000",
                "K6_SCENARIO": config.scenario,
                "API_KEY": os.getenv("API_KEY", "test-key")
            },
            network="pyairtable-network",
            detach=True,
            remove=True
        )
        
        # Wait for test completion
        container.wait()
        
        # Parse results
        results_file = f"{self.results_storage}/k6-results.json"
        return self._parse_k6_results(results_file)
    
    async def _run_jmeter_test(self, config: TestConfig) -> Dict[str, Any]:
        """Run JMeter load test"""
        logger.info(f"Running JMeter test: {config.name}")
        
        container = self.docker_client.containers.run(
            "justb4/jmeter:latest",
            command=[
                "-n", "-t", "/tests/pyairtable-load-test.jmx",
                "-l", "/reports/jmeter-results.jtl",
                "-e", "-o", "/reports/jmeter-report",
                f"-Jthreads={config.virtual_users}",
                f"-Jramptime={config.ramp_up_time}",
                f"-Jduration={config.duration}",
                "-Jhost=api-gateway",
                "-Jport=8000"
            ],
            volumes={
                "/app/jmeter": {"bind": "/tests", "mode": "ro"},
                "/reports": {"bind": "/reports", "mode": "rw"}
            },
            network="pyairtable-network",
            detach=True,
            remove=True
        )
        
        container.wait()
        
        # Parse JMeter results
        results_file = f"{self.results_storage}/jmeter-results.jtl"
        return self._parse_jmeter_results(results_file)
    
    async def _run_locust_test(self, config: TestConfig) -> Dict[str, Any]:
        """Run Locust load test"""
        logger.info(f"Running Locust test: {config.name}")
        
        # Use existing Locust master/worker setup
        # Send test configuration via API
        locust_api = "http://locust-master:8089"
        
        # Start test
        start_response = requests.post(f"{locust_api}/swarm", data={
            "user_count": config.virtual_users,
            "spawn_rate": config.virtual_users / config.ramp_up_time,
            "host": "http://api-gateway:8000"
        })
        
        if start_response.status_code != 200:
            raise RuntimeError("Failed to start Locust test")
        
        # Wait for test duration
        await asyncio.sleep(config.duration)
        
        # Stop test
        requests.get(f"{locust_api}/stop")
        
        # Get results
        stats_response = requests.get(f"{locust_api}/stats/requests")
        return stats_response.json()
    
    async def _run_artillery_test(self, config: TestConfig) -> Dict[str, Any]:
        """Run Artillery load test"""
        logger.info(f"Running Artillery test: {config.name}")
        
        # Create Artillery configuration
        artillery_config = {
            "config": {
                "target": "http://api-gateway:8000",
                "phases": [
                    {
                        "duration": config.ramp_up_time,
                        "arrivalRate": 1,
                        "rampTo": config.virtual_users
                    },
                    {
                        "duration": config.duration - config.ramp_up_time,
                        "arrivalRate": config.virtual_users
                    }
                ]
            },
            "scenarios": [
                {
                    "name": "Load test scenario",
                    "flow": [
                        {"get": {"url": "/api/health"}},
                        {"get": {"url": "/api/users/profile"}},
                        {"get": {"url": "/api/workspaces"}}
                    ]
                }
            ]
        }
        
        # Write config file
        config_file = f"{self.results_storage}/artillery-config.yml"
        with open(config_file, 'w') as f:
            yaml.dump(artillery_config, f)
        
        # Run Artillery
        container = self.docker_client.containers.run(
            "node:16-alpine",
            command=[
                "sh", "-c",
                "npm install -g artillery && "
                f"artillery run /reports/artillery-config.yml "
                f"--output /reports/artillery-results.json"
            ],
            volumes={
                "/reports": {"bind": "/reports", "mode": "rw"}
            },
            network="pyairtable-network",
            detach=True,
            remove=True
        )
        
        container.wait()
        
        # Parse results
        results_file = f"{self.results_storage}/artillery-results.json"
        return self._parse_artillery_results(results_file)
    
    def _parse_k6_results(self, results_file: str) -> Dict[str, Any]:
        """Parse K6 JSON results"""
        if not os.path.exists(results_file):
            return {}
        
        with open(results_file, 'r') as f:
            lines = f.readlines()
        
        # Parse K6 JSON lines format
        metrics = {}
        total_requests = 0
        failed_requests = 0
        response_times = []
        
        for line in lines:
            try:
                data = json.loads(line.strip())
                if data.get('type') == 'Point':
                    metric_name = data.get('metric')
                    value = data.get('data', {}).get('value', 0)
                    
                    if metric_name == 'http_reqs':
                        total_requests += value
                    elif metric_name == 'http_req_failed':
                        failed_requests += value
                    elif metric_name == 'http_req_duration':
                        response_times.append(value)
                        
            except json.JSONDecodeError:
                continue
        
        if response_times:
            response_times.sort()
            n = len(response_times)
            metrics['response_times'] = {
                'min': response_times[0],
                'max': response_times[-1],
                'mean': sum(response_times) / n,
                'p50': response_times[int(n * 0.5)],
                'p95': response_times[int(n * 0.95)],
                'p99': response_times[int(n * 0.99)]
            }
        
        metrics.update({
            'total_requests': total_requests,
            'failed_requests': failed_requests,
            'error_rate': failed_requests / total_requests if total_requests > 0 else 0,
            'throughput': total_requests / 600  # requests per second
        })
        
        return metrics
    
    def _parse_jmeter_results(self, results_file: str) -> Dict[str, Any]:
        """Parse JMeter JTL results"""
        if not os.path.exists(results_file):
            return {}
        
        # Simple JTL parsing (CSV format)
        metrics = {
            'total_requests': 0,
            'failed_requests': 0,
            'response_times': []
        }
        
        with open(results_file, 'r') as f:
            lines = f.readlines()[1:]  # Skip header
            
            for line in lines:
                parts = line.strip().split(',')
                if len(parts) >= 8:
                    elapsed = int(parts[1])
                    success = parts[7].lower() == 'true'
                    
                    metrics['total_requests'] += 1
                    if not success:
                        metrics['failed_requests'] += 1
                    metrics['response_times'].append(elapsed)
        
        if metrics['response_times']:
            response_times = sorted(metrics['response_times'])
            n = len(response_times)
            metrics['response_times'] = {
                'min': response_times[0],
                'max': response_times[-1],
                'mean': sum(response_times) / n,
                'p50': response_times[int(n * 0.5)],
                'p95': response_times[int(n * 0.95)],
                'p99': response_times[int(n * 0.99)]
            }
        
        metrics['error_rate'] = (
            metrics['failed_requests'] / metrics['total_requests'] 
            if metrics['total_requests'] > 0 else 0
        )
        
        return metrics
    
    def _parse_artillery_results(self, results_file: str) -> Dict[str, Any]:
        """Parse Artillery JSON results"""
        if not os.path.exists(results_file):
            return {}
        
        with open(results_file, 'r') as f:
            data = json.load(f)
        
        aggregate = data.get('aggregate', {})
        
        return {
            'total_requests': aggregate.get('requestsCompleted', 0),
            'failed_requests': aggregate.get('errors', {}).get('total', 0),
            'error_rate': aggregate.get('errors', {}).get('rate', 0),
            'response_times': {
                'min': aggregate.get('latency', {}).get('min', 0),
                'max': aggregate.get('latency', {}).get('max', 0),
                'mean': aggregate.get('latency', {}).get('mean', 0),
                'p50': aggregate.get('latency', {}).get('median', 0),
                'p95': aggregate.get('latency', {}).get('p95', 0),
                'p99': aggregate.get('latency', {}).get('p99', 0)
            },
            'throughput': aggregate.get('rps', {}).get('mean', 0)
        }
    
    def _evaluate_test_results(self, results: Dict[str, Any], thresholds: Dict[str, float]) -> bool:
        """Evaluate test results against thresholds"""
        passed = True
        
        # Check response time threshold
        response_times = results.get('response_times', {})
        if isinstance(response_times, dict):
            p95_time = response_times.get('p95', 0)
            if p95_time > thresholds.get('response_time_p95', 2000):
                passed = False
                logger.warning(f"P95 response time {p95_time}ms exceeds threshold {thresholds['response_time_p95']}ms")
        
        # Check error rate threshold
        error_rate = results.get('error_rate', 0)
        if error_rate > thresholds.get('error_rate', 0.05):
            passed = False
            logger.warning(f"Error rate {error_rate:.2%} exceeds threshold {thresholds['error_rate']:.2%}")
        
        # Check minimum throughput
        throughput = results.get('throughput', 0)
        min_throughput = thresholds.get('throughput_min', 0)
        if throughput < min_throughput:
            passed = False
            logger.warning(f"Throughput {throughput} RPS below minimum {min_throughput} RPS")
        
        return passed
    
    async def _store_test_metrics(self, result: TestResult):
        """Store test metrics in InfluxDB"""
        write_api = self.influxdb_client.write_api(write_options=SYNCHRONOUS)
        
        # Create points for different metrics
        points = []
        
        # Test summary point
        summary_point = Point("performance_test_summary") \
            .tag("test_name", result.test_name) \
            .tag("passed", str(result.passed)) \
            .field("duration", result.duration) \
            .field("virtual_users", result.virtual_users) \
            .field("total_requests", result.total_requests) \
            .field("failed_requests", result.failed_requests) \
            .field("error_rate", result.error_rate) \
            .field("throughput", result.throughput) \
            .time(result.start_time)
        
        points.append(summary_point)
        
        # Response time metrics
        if isinstance(result.response_times, dict):
            for percentile, value in result.response_times.items():
                rt_point = Point("response_time") \
                    .tag("test_name", result.test_name) \
                    .tag("percentile", percentile) \
                    .field("value", value) \
                    .time(result.start_time)
                points.append(rt_point)
        
        # Write points to InfluxDB
        write_api.write(bucket="k6-metrics", record=points)
        logger.info(f"Stored metrics for test: {result.test_name}")
    
    async def _generate_test_report(self, results: List[TestResult], suite_name: str):
        """Generate comprehensive test report"""
        report_data = {
            "suite_name": suite_name,
            "execution_time": datetime.now().isoformat(),
            "total_tests": len(results),
            "passed_tests": sum(1 for r in results if r.passed),
            "failed_tests": sum(1 for r in results if not r.passed),
            "overall_pass_rate": sum(1 for r in results if r.passed) / len(results) if results else 0,
            "results": []
        }
        
        for result in results:
            report_data["results"].append({
                "test_name": result.test_name,
                "passed": result.passed,
                "duration": result.duration,
                "virtual_users": result.virtual_users,
                "total_requests": result.total_requests,
                "error_rate": result.error_rate,
                "response_times": result.response_times,
                "throughput": result.throughput
            })
        
        # Save JSON report
        report_file = f"{self.results_storage}/performance-report-{suite_name}-{int(time.time())}.json"
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        # Generate HTML report
        html_report = self._generate_html_report(report_data)
        html_file = f"{self.results_storage}/performance-report-{suite_name}-{int(time.time())}.html"
        with open(html_file, 'w') as f:
            f.write(html_report)
        
        logger.info(f"Generated performance reports: {report_file}, {html_file}")
    
    def _generate_html_report(self, report_data: Dict[str, Any]) -> str:
        """Generate HTML performance report"""
        html_template = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>PyAirtable Performance Test Report</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 20px; }
                .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
                .summary { display: flex; gap: 20px; margin: 20px 0; }
                .metric { background: #fff; border: 1px solid #ddd; padding: 15px; border-radius: 5px; flex: 1; }
                .passed { border-left: 5px solid #28a745; }
                .failed { border-left: 5px solid #dc3545; }
                table { width: 100%; border-collapse: collapse; margin: 20px 0; }
                th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
                th { background: #f8f9fa; }
                .pass { color: #28a745; }
                .fail { color: #dc3545; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>PyAirtable Performance Test Report</h1>
                <p><strong>Suite:</strong> {suite_name}</p>
                <p><strong>Execution Time:</strong> {execution_time}</p>
                <p><strong>Overall Pass Rate:</strong> {overall_pass_rate:.1%}</p>
            </div>
            
            <div class="summary">
                <div class="metric passed">
                    <h3>Total Tests</h3>
                    <p style="font-size: 2em; margin: 0;">{total_tests}</p>
                </div>
                <div class="metric passed">
                    <h3>Passed</h3>
                    <p style="font-size: 2em; margin: 0; color: #28a745;">{passed_tests}</p>
                </div>
                <div class="metric failed">
                    <h3>Failed</h3>
                    <p style="font-size: 2em; margin: 0; color: #dc3545;">{failed_tests}</p>
                </div>
            </div>
            
            <h2>Test Results</h2>
            <table>
                <thead>
                    <tr>
                        <th>Test Name</th>
                        <th>Status</th>
                        <th>Duration (s)</th>
                        <th>Virtual Users</th>
                        <th>Total Requests</th>
                        <th>Error Rate</th>
                        <th>P95 Response Time (ms)</th>
                        <th>Throughput (RPS)</th>
                    </tr>
                </thead>
                <tbody>
                    {test_rows}
                </tbody>
            </table>
        </body>
        </html>
        """
        
        # Generate test rows
        test_rows = ""
        for result in report_data["results"]:
            status_class = "pass" if result["passed"] else "fail"
            status_text = "PASS" if result["passed"] else "FAIL"
            
            p95_time = "N/A"
            if isinstance(result["response_times"], dict):
                p95_time = f"{result['response_times'].get('p95', 0):.0f}"
            
            test_rows += f"""
            <tr>
                <td>{result['test_name']}</td>
                <td class="{status_class}"><strong>{status_text}</strong></td>
                <td>{result['duration']:.1f}</td>
                <td>{result['virtual_users']}</td>
                <td>{result['total_requests']}</td>
                <td>{result['error_rate']:.2%}</td>
                <td>{p95_time}</td>
                <td>{result['throughput']:.1f}</td>
            </tr>
            """
        
        return html_template.format(
            suite_name=report_data["suite_name"],
            execution_time=report_data["execution_time"],
            overall_pass_rate=report_data["overall_pass_rate"],
            total_tests=report_data["total_tests"],
            passed_tests=report_data["passed_tests"],
            failed_tests=report_data["failed_tests"],
            test_rows=test_rows
        )

async def main():
    """Main orchestrator function"""
    orchestrator = PerformanceOrchestrator()
    
    # Determine test suite to run
    suite_name = os.getenv('TEST_SUITE', 'smoke')
    
    try:
        results = await orchestrator.run_test_suite(suite_name)
        
        # Exit with appropriate code
        failed_tests = sum(1 for r in results if not r.passed)
        exit_code = 0 if failed_tests == 0 else 1
        
        logger.info(f"Performance test suite completed. Exit code: {exit_code}")
        exit(exit_code)
        
    except Exception as e:
        logger.error(f"Performance test suite failed: {e}")
        exit(1)

if __name__ == "__main__":
    asyncio.run(main())