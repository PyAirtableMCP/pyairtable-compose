#!/usr/bin/env python3
"""
Performance Test Orchestrator for PyAirtable Platform
Coordinates and manages comprehensive performance testing across all tools and scenarios
"""

import asyncio
import json
import logging
import os
import subprocess
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import yaml
from dataclasses import dataclass, asdict
from enum import Enum

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/reports/orchestrator.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class TestStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"

class TestPriority(Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4

@dataclass
class TestConfiguration:
    name: str
    tool: str  # k6, jmeter, locust, artillery
    script_path: str
    duration: str
    max_users: int
    rps_target: int
    environment: Dict[str, str]
    priority: TestPriority
    depends_on: List[str] = None
    timeout_minutes: int = 60
    retry_count: int = 1

@dataclass
class TestResult:
    test_name: str
    status: TestStatus
    start_time: datetime
    end_time: Optional[datetime]
    duration_seconds: float
    metrics: Dict[str, float]
    errors: List[str]
    artifacts: List[str]
    resource_usage: Dict[str, float]

class PerformanceTestOrchestrator:
    def __init__(self):
        self.test_results: Dict[str, TestResult] = {}
        self.reports_dir = Path("/reports")
        self.reports_dir.mkdir(exist_ok=True)
        
    async def run_test_suite(self, suite_name: str, environment: str = 'development') -> Dict[str, TestResult]:
        """Run a complete test suite"""
        logger.info(f"Starting test suite: {suite_name} in {environment}")
        
        # Define test suites
        test_suites = {
            'smoke_tests': [
                TestConfiguration(
                    name='api_smoke_test',
                    tool='k6',
                    script_path='k6/api-endpoint-tests.js',
                    duration='2m',
                    max_users=5,
                    rps_target=10,
                    environment={'TEST_INTENSITY': 'light'},
                    priority=TestPriority.HIGH
                )
            ],
            'load_tests': [
                TestConfiguration(
                    name='k6_load_test',
                    tool='k6',
                    script_path='k6-load-tests.js',
                    duration='10m',
                    max_users=50,
                    rps_target=300,
                    environment={'K6_SCENARIO': 'load_test'},
                    priority=TestPriority.HIGH
                ),
                TestConfiguration(
                    name='locust_user_journey',
                    tool='locust',
                    script_path='locust/locustfile.py',
                    duration='10m',
                    max_users=50,
                    rps_target=200,
                    environment={'LOCUST_MODE': 'distributed'},
                    priority=TestPriority.MEDIUM
                )
            ],
            'stress_tests': [
                TestConfiguration(
                    name='k6_stress_test',
                    tool='k6',
                    script_path='stress-tests/k6-stress-scenarios.js',
                    duration='15m',
                    max_users=200,
                    rps_target=1000,
                    environment={'STRESS_LEVEL': 'high'},
                    priority=TestPriority.MEDIUM
                )
            ],
            'soak_tests': [
                TestConfiguration(
                    name='k6_soak_test',
                    tool='k6',
                    script_path='soak-tests/k6-soak-test.js',
                    duration='2h',
                    max_users=30,
                    rps_target=100,
                    environment={'SOAK_DURATION': '2h'},
                    priority=TestPriority.LOW
                )
            ],
            'database_tests': [
                TestConfiguration(
                    name='database_performance',
                    tool='k6',
                    script_path='k6/database-performance-tests.js',
                    duration='15m',
                    max_users=50,
                    rps_target=200,
                    environment={'DB_TEST_MODE': 'comprehensive'},
                    priority=TestPriority.HIGH
                )
            ]
        }
        
        if suite_name not in test_suites:
            raise ValueError(f"Unknown test suite: {suite_name}")
        
        # Execute tests
        results = {}
        for test_config in test_suites[suite_name]:
            result = await self._execute_test(test_config, environment)
            results[test_config.name] = result
        
        # Generate report
        await self._generate_suite_report(suite_name, environment, results)
        
        return results
    
    async def _execute_test(self, config: TestConfiguration, environment: str) -> TestResult:
        """Execute a single performance test"""
        logger.info(f"Starting test: {config.name}")
        
        start_time = datetime.now()
        result = TestResult(
            test_name=config.name,
            status=TestStatus.RUNNING,
            start_time=start_time,
            end_time=None,
            duration_seconds=0,
            metrics={},
            errors=[],
            artifacts=[],
            resource_usage={}
        )
        
        try:
            if config.tool == 'k6':
                result = await self._execute_k6_test(config, result, environment)
            elif config.tool == 'locust':
                result = await self._execute_locust_test(config, result, environment)
            elif config.tool == 'jmeter':
                result = await self._execute_jmeter_test(config, result, environment)
            else:
                raise ValueError(f"Unsupported test tool: {config.tool}")
            
            result.status = TestStatus.COMPLETED
            
        except Exception as e:
            logger.error(f"Test {config.name} failed: {e}")
            result.status = TestStatus.FAILED
            result.errors.append(str(e))
        
        finally:
            result.end_time = datetime.now()
            result.duration_seconds = (result.end_time - result.start_time).total_seconds()
        
        return result
    
    async def _execute_k6_test(self, config: TestConfiguration, result: TestResult, environment: str) -> TestResult:
        """Execute K6 performance test"""
        env_vars = {
            'BASE_URL': f'http://api-gateway:8000',
            'ENVIRONMENT': environment,
            **config.environment
        }
        
        # Build K6 command
        cmd = [
            'docker', 'run', '--rm',
            '--network', 'pyairtable-network',
            '-v', '/app/performance-testing:/scripts:ro',
            '-v', '/app/performance-testing/reports:/reports:rw'
        ]
        
        # Add environment variables
        for key, value in env_vars.items():
            cmd.extend(['-e', f'{key}={value}'])
        
        cmd.extend([
            'grafana/k6:latest',
            'run',
            '--out', f'json=/reports/{config.name}-{datetime.now().strftime("%Y%m%d_%H%M%S")}.json',
            f'/scripts/{config.script_path}'
        ])
        
        # Execute command
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            result.errors.append(f"K6 test failed with return code {process.returncode}")
            result.errors.append(stderr.decode('utf-8'))
        
        # Parse results
        result.metrics = self._parse_k6_output(stdout.decode('utf-8'))
        result.artifacts = [f'/reports/{config.name}-*.json']
        
        return result
    
    async def _execute_locust_test(self, config: TestConfiguration, result: TestResult, environment: str) -> TestResult:
        """Execute Locust performance test"""
        # Simplified Locust execution
        cmd = [
            'docker', 'run', '--rm',
            '--network', 'pyairtable-network',
            '-v', '/app/performance-testing/locust:/mnt/locust:ro',
            '-v', '/app/performance-testing/reports:/reports:rw',
            '-e', f'BASE_URL=http://api-gateway:8000',
            '-e', f'ENVIRONMENT={environment}',
            'locustio/locust:latest',
            'locust',
            '-f', f'/mnt/locust/{config.script_path.replace("locust/", "")}',
            '--headless',
            '--users', str(config.max_users),
            '--spawn-rate', str(config.rps_target // 10),
            '--run-time', config.duration,
            '--html', f'/reports/{config.name}-report.html'
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            result.errors.append(f"Locust test failed with return code {process.returncode}")
            result.errors.append(stderr.decode('utf-8'))
        
        result.metrics = self._parse_locust_output(stdout.decode('utf-8'))
        result.artifacts = [f'/reports/{config.name}-report.html']
        
        return result
    
    async def _execute_jmeter_test(self, config: TestConfiguration, result: TestResult, environment: str) -> TestResult:
        """Execute JMeter performance test"""
        cmd = [
            'docker', 'run', '--rm',
            '--network', 'pyairtable-network',
            '-v', '/app/performance-testing/jmeter:/tests:ro',
            '-v', '/app/performance-testing/reports:/reports:rw',
            'justb4/jmeter:latest',
            'jmeter',
            '-n',
            '-t', f'/tests/{config.script_path.replace("jmeter/", "")}',
            '-l', f'/reports/{config.name}-results.jtl',
            '-e', '-o', f'/reports/{config.name}-report',
            f'-Jthreads={config.max_users}',
            f'-Jduration={self._duration_to_seconds(config.duration)}'
        ]
        
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await process.communicate()
        
        if process.returncode != 0:
            result.errors.append(f"JMeter test failed with return code {process.returncode}")
            result.errors.append(stderr.decode('utf-8'))
        
        result.metrics = self._parse_jmeter_output(stdout.decode('utf-8'))
        result.artifacts = [f'/reports/{config.name}-results.jtl', f'/reports/{config.name}-report/']
        
        return result
    
    def _parse_k6_output(self, output: str) -> Dict[str, float]:
        """Parse K6 output for metrics"""
        metrics = {}
        lines = output.split('\n')
        
        for line in lines:
            if 'http_req_duration' in line and 'avg=' in line:
                # Extract average response time
                parts = line.split('avg=')[1].split('ms')[0]
                try:
                    metrics['response_time_avg'] = float(parts)
                except ValueError:
                    pass
            elif 'http_req_failed' in line and 'rate=' in line:
                # Extract error rate
                parts = line.split('rate=')[1].split('%')[0]
                try:
                    metrics['error_rate'] = float(parts)
                except ValueError:
                    pass
            elif 'http_reqs' in line:
                # Extract total requests
                parts = line.split()
                if len(parts) > 1:
                    try:
                        metrics['total_requests'] = float(parts[1])
                    except ValueError:
                        pass
        
        return metrics
    
    def _parse_locust_output(self, output: str) -> Dict[str, float]:
        """Parse Locust output for metrics"""
        metrics = {}
        lines = output.split('\n')
        
        for line in lines:
            if 'Aggregated' in line and 'GET' in line:
                # Parse aggregated statistics line
                parts = line.split()
                try:
                    if len(parts) >= 10:
                        metrics['total_requests'] = float(parts[2])
                        metrics['error_count'] = float(parts[3])
                        metrics['response_time_avg'] = float(parts[5])
                        metrics['response_time_min'] = float(parts[6])
                        metrics['response_time_max'] = float(parts[7])
                except (ValueError, IndexError):
                    pass
        
        return metrics
    
    def _parse_jmeter_output(self, output: str) -> Dict[str, float]:
        """Parse JMeter output for metrics"""
        metrics = {}
        lines = output.split('\n')
        
        for line in lines:
            if 'summary =' in line:
                # Parse JMeter summary line
                try:
                    if 'Avg:' in line:
                        avg_part = line.split('Avg:')[1].split()[0]
                        metrics['response_time_avg'] = float(avg_part)
                    if 'Err:' in line:
                        err_part = line.split('Err:')[1].split()[0].replace('(', '').replace('%)', '')
                        metrics['error_rate'] = float(err_part)
                except (ValueError, IndexError):
                    pass
        
        return metrics
    
    def _duration_to_seconds(self, duration: str) -> int:
        """Convert duration string to seconds"""
        if duration.endswith('s'):
            return int(duration[:-1])
        elif duration.endswith('m'):
            return int(duration[:-1]) * 60
        elif duration.endswith('h'):
            return int(duration[:-1]) * 3600
        else:
            return int(duration)
    
    async def _generate_suite_report(self, suite_name: str, environment: str, results: Dict[str, TestResult]):
        """Generate test suite report"""
        report_data = {
            'suite_name': suite_name,
            'environment': environment,
            'execution_time': datetime.now().isoformat(),
            'summary': {
                'total_tests': len(results),
                'passed': len([r for r in results.values() if r.status == TestStatus.COMPLETED]),
                'failed': len([r for r in results.values() if r.status == TestStatus.FAILED]),
                'total_duration': sum(r.duration_seconds for r in results.values()),
            },
            'results': {name: asdict(result) for name, result in results.items()}
        }
        
        # Save JSON report
        report_file = self.reports_dir / f"{suite_name}_{environment}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2, default=str)
        
        logger.info(f"Report generated: {report_file}")

async def main():
    """Main orchestrator function"""
    orchestrator = PerformanceTestOrchestrator()
    
    # Get test suite from command line or environment
    import sys
    suite_name = sys.argv[1] if len(sys.argv) > 1 else os.getenv('TEST_SUITE', 'smoke_tests')
    environment = sys.argv[2] if len(sys.argv) > 2 else os.getenv('TEST_ENVIRONMENT', 'development')
    
    try:
        results = await orchestrator.run_test_suite(suite_name, environment)
        
        # Check results
        failed = len([r for r in results.values() if r.status == TestStatus.FAILED])
        passed = len([r for r in results.values() if r.status == TestStatus.COMPLETED])
        
        logger.info(f"Test suite completed: {passed} passed, {failed} failed")
        sys.exit(0 if failed == 0 else 1)
        
    except Exception as e:
        logger.error(f"Orchestrator failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())