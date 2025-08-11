#!/usr/bin/env python3
"""
Automated Performance Validation Script for PyAirtable
Validates performance targets and generates comprehensive reports
"""

import asyncio
import aiohttp
import subprocess
import json
import time
import logging
import sys
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple
import statistics
import yaml
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('performance-validation.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class PerformanceValidator:
    """Automated performance validation and testing"""
    
    def __init__(self, config_path: str = None):
        self.config = self.load_config(config_path or 'performance-targets.yml')
        self.base_url = self.config.get('base_url', 'http://localhost:8000')
        self.services = self.config.get('services', {})
        self.targets = self.config.get('performance_targets', {})
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'validation_results': {},
            'performance_metrics': {},
            'load_test_results': {},
            'recommendations': [],
            'passed': False,
            'failed_tests': []
        }
        
    def load_config(self, config_path: str) -> Dict[str, Any]:
        """Load performance validation configuration"""
        default_config = {
            'base_url': 'http://localhost:8000',
            'services': {
                'api-gateway': 'http://localhost:8000',
                'llm-orchestrator': 'http://localhost:8003',
                'mcp-server': 'http://localhost:8001',
                'airtable-gateway': 'http://localhost:8002',
                'platform-services': 'http://localhost:8007',
                'automation-services': 'http://localhost:8006',
                'saga-orchestrator': 'http://localhost:8008',
                'frontend': 'http://localhost:3000'
            },
            'performance_targets': {
                'api_response_time_ms': 200,
                'frontend_load_time_ms': 3000,
                'max_concurrent_users': 1000,
                'error_rate_threshold': 0.05,
                'throughput_rps': 500,
                'database_query_time_ms': 100,
                'cache_hit_rate': 0.80,
                'cpu_utilization_threshold': 0.80,
                'memory_utilization_threshold': 0.80
            },
            'test_scenarios': {
                'smoke_test': {'users': 1, 'duration': '1m'},
                'load_test': {'users': 100, 'duration': '5m'},
                'stress_test': {'users': 500, 'duration': '10m'},
                'spike_test': {'users': 1000, 'duration': '2m'},
                'endurance_test': {'users': 200, 'duration': '30m'}
            }
        }
        
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    user_config = yaml.safe_load(f)
                    default_config.update(user_config)
            except Exception as e:
                logger.warning(f"Failed to load config from {config_path}: {e}")
        
        return default_config
    
    async def run_full_validation(self) -> Dict[str, Any]:
        """Run complete performance validation suite"""
        logger.info("Starting PyAirtable Performance Validation Suite")
        
        try:
            # Phase 1: Basic connectivity and health checks
            await self.validate_service_health()
            
            # Phase 2: API performance validation
            await self.validate_api_performance()
            
            # Phase 3: Frontend performance validation
            await self.validate_frontend_performance()
            
            # Phase 4: Load testing validation
            await self.run_load_tests()
            
            # Phase 5: Database performance validation
            await self.validate_database_performance()
            
            # Phase 6: Cache performance validation
            await self.validate_cache_performance()
            
            # Phase 7: System resource validation
            await self.validate_system_resources()
            
            # Phase 8: Generate recommendations
            await self.generate_recommendations()
            
            # Phase 9: Create performance report
            await self.generate_performance_report()
            
            # Determine overall validation result
            self.results['passed'] = len(self.results['failed_tests']) == 0
            
            logger.info(f"Performance validation completed. Passed: {self.results['passed']}")
            
        except Exception as e:
            logger.error(f"Performance validation failed: {e}")
            self.results['error'] = str(e)
            self.results['passed'] = False
        
        return self.results
    
    async def validate_service_health(self):
        """Validate that all services are healthy and responsive"""
        logger.info("Validating service health...")
        
        health_results = {}
        
        async with aiohttp.ClientSession() as session:
            for service_name, service_url in self.services.items():
                try:
                    start_time = time.time()
                    async with session.get(f"{service_url}/health", timeout=aiohttp.ClientTimeout(total=10)) as response:
                        response_time = (time.time() - start_time) * 1000
                        
                        health_results[service_name] = {
                            'status': response.status,
                            'response_time_ms': response_time,
                            'healthy': response.status == 200,
                            'response_time_ok': response_time < 1000  # 1s health check limit
                        }
                        
                        if response.status != 200:
                            self.results['failed_tests'].append(f"{service_name} health check failed")
                        
                        if response_time > 1000:
                            self.results['failed_tests'].append(f"{service_name} health check too slow")
                            
                except Exception as e:
                    logger.error(f"Health check failed for {service_name}: {e}")
                    health_results[service_name] = {
                        'error': str(e),
                        'healthy': False
                    }
                    self.results['failed_tests'].append(f"{service_name} health check error")
        
        self.results['validation_results']['service_health'] = health_results
    
    async def validate_api_performance(self):
        """Validate API endpoint performance against targets"""
        logger.info("Validating API performance...")
        
        # Test endpoints with authentication simulation
        test_endpoints = [
            {'url': '/api/health', 'method': 'GET', 'auth_required': False},
            {'url': '/api/users/profile', 'method': 'GET', 'auth_required': True},
            {'url': '/api/workspaces', 'method': 'GET', 'auth_required': True},
            {'url': '/api/search', 'method': 'POST', 'auth_required': True, 'payload': {'query': 'test'}},
        ]
        
        api_results = {}
        
        async with aiohttp.ClientSession() as session:
            for endpoint in test_endpoints:
                endpoint_name = f"{endpoint['method']} {endpoint['url']}"
                response_times = []
                status_codes = []
                
                # Run multiple requests for statistical significance
                for _ in range(20):
                    try:
                        headers = {'Content-Type': 'application/json'}
                        if endpoint.get('auth_required'):
                            headers['Authorization'] = 'Bearer test-token'
                        
                        start_time = time.time()
                        
                        if endpoint['method'] == 'GET':
                            async with session.get(f"{self.base_url}{endpoint['url']}", headers=headers) as response:
                                response_time = (time.time() - start_time) * 1000
                                response_times.append(response_time)
                                status_codes.append(response.status)
                        else:
                            payload = endpoint.get('payload', {})
                            async with session.post(f"{self.base_url}{endpoint['url']}", 
                                                  json=payload, headers=headers) as response:
                                response_time = (time.time() - start_time) * 1000
                                response_times.append(response_time)
                                status_codes.append(response.status)
                                
                    except Exception as e:
                        logger.warning(f"API test failed for {endpoint_name}: {e}")
                        response_times.append(30000)  # 30s timeout
                        status_codes.append(0)
                    
                    await asyncio.sleep(0.1)  # Small delay between requests
                
                # Calculate performance metrics
                if response_times:
                    avg_response_time = statistics.mean(response_times)
                    p95_response_time = self._percentile(response_times, 95)
                    p99_response_time = self._percentile(response_times, 99)
                    success_rate = len([s for s in status_codes if 200 <= s < 300]) / len(status_codes)
                    
                    api_results[endpoint_name] = {
                        'avg_response_time_ms': avg_response_time,
                        'p95_response_time_ms': p95_response_time,
                        'p99_response_time_ms': p99_response_time,
                        'success_rate': success_rate,
                        'total_requests': len(response_times),
                        'target_met': p95_response_time < self.targets['api_response_time_ms']
                    }
                    
                    # Check against targets
                    if p95_response_time >= self.targets['api_response_time_ms']:
                        self.results['failed_tests'].append(
                            f"{endpoint_name} P95 response time {p95_response_time:.1f}ms exceeds target {self.targets['api_response_time_ms']}ms"
                        )
                    
                    if success_rate < (1 - self.targets['error_rate_threshold']):
                        self.results['failed_tests'].append(
                            f"{endpoint_name} success rate {success_rate:.1%} below target"
                        )
        
        self.results['validation_results']['api_performance'] = api_results
    
    async def validate_frontend_performance(self):
        """Validate frontend performance using Lighthouse or similar metrics"""
        logger.info("Validating frontend performance...")
        
        frontend_results = {}
        
        try:
            # Use Lighthouse CLI if available
            lighthouse_cmd = [
                'lighthouse',
                f"{self.services['frontend']}/",
                '--output=json',
                '--only-categories=performance',
                '--chrome-flags="--headless"',
                '--quiet'
            ]
            
            result = subprocess.run(lighthouse_cmd, capture_output=True, text=True, timeout=120)
            
            if result.returncode == 0:
                lighthouse_data = json.loads(result.stdout)
                performance_score = lighthouse_data['categories']['performance']['score'] * 100
                
                audits = lighthouse_data['audits']
                
                frontend_results = {
                    'performance_score': performance_score,
                    'first_contentful_paint': audits.get('first-contentful-paint', {}).get('numericValue', 0) / 1000,
                    'largest_contentful_paint': audits.get('largest-contentful-paint', {}).get('numericValue', 0) / 1000,
                    'first_input_delay': audits.get('max-potential-fid', {}).get('numericValue', 0),
                    'cumulative_layout_shift': audits.get('cumulative-layout-shift', {}).get('numericValue', 0),
                    'speed_index': audits.get('speed-index', {}).get('numericValue', 0) / 1000,
                    'time_to_interactive': audits.get('interactive', {}).get('numericValue', 0) / 1000,
                }
                
                # Check against targets
                if frontend_results['largest_contentful_paint'] > self.targets['frontend_load_time_ms'] / 1000:
                    self.results['failed_tests'].append(
                        f"Frontend LCP {frontend_results['largest_contentful_paint']:.1f}s exceeds target {self.targets['frontend_load_time_ms']/1000}s"
                    )
                
                if performance_score < 90:
                    self.results['failed_tests'].append(
                        f"Frontend performance score {performance_score} below target 90"
                    )
                    
            else:
                logger.warning("Lighthouse not available, performing basic frontend test")
                await self._basic_frontend_test(frontend_results)
                
        except Exception as e:
            logger.warning(f"Lighthouse test failed: {e}, performing basic frontend test")
            await self._basic_frontend_test(frontend_results)
        
        self.results['validation_results']['frontend_performance'] = frontend_results
    
    async def _basic_frontend_test(self, results: Dict):
        """Basic frontend performance test without Lighthouse"""
        async with aiohttp.ClientSession() as session:
            try:
                start_time = time.time()
                async with session.get(self.services['frontend']) as response:
                    load_time = (time.time() - start_time) * 1000
                    
                    results.update({
                        'basic_load_time_ms': load_time,
                        'status_code': response.status,
                        'content_length': len(await response.text()),
                        'target_met': load_time < self.targets['frontend_load_time_ms']
                    })
                    
                    if load_time >= self.targets['frontend_load_time_ms']:
                        self.results['failed_tests'].append(
                            f"Frontend load time {load_time:.1f}ms exceeds target {self.targets['frontend_load_time_ms']}ms"
                        )
                        
            except Exception as e:
                logger.error(f"Basic frontend test failed: {e}")
                results['error'] = str(e)
    
    async def run_load_tests(self):
        """Run K6 load tests to validate concurrent user support"""
        logger.info("Running load tests...")
        
        load_test_results = {}
        
        # Run different load test scenarios
        scenarios = self.config.get('test_scenarios', {})
        
        for scenario_name, scenario_config in scenarios.items():
            logger.info(f"Running {scenario_name}...")
            
            try:
                # Create K6 test script
                k6_script = self._generate_k6_script(scenario_config)
                
                # Run K6 test
                k6_cmd = [
                    'k6', 'run',
                    '--vus', str(scenario_config['users']),
                    '--duration', scenario_config['duration'],
                    '--out', 'json=k6-results.json',
                    '-'
                ]
                
                result = subprocess.run(k6_cmd, input=k6_script, text=True, 
                                      capture_output=True, timeout=1800)  # 30min timeout
                
                if result.returncode == 0:
                    # Parse K6 results
                    k6_results = self._parse_k6_results('k6-results.json')
                    load_test_results[scenario_name] = k6_results
                    
                    # Validate against targets
                    if scenario_name == 'spike_test' and scenario_config['users'] >= self.targets['max_concurrent_users']:
                        error_rate = k6_results.get('error_rate', 1.0)
                        avg_response_time = k6_results.get('avg_response_time', float('inf'))
                        
                        if error_rate > self.targets['error_rate_threshold']:
                            self.results['failed_tests'].append(
                                f"Load test error rate {error_rate:.1%} exceeds target {self.targets['error_rate_threshold']:.1%}"
                            )
                        
                        if avg_response_time > self.targets['api_response_time_ms']:
                            self.results['failed_tests'].append(
                                f"Load test response time {avg_response_time:.1f}ms exceeds target {self.targets['api_response_time_ms']}ms"
                            )
                else:
                    logger.error(f"K6 test failed for {scenario_name}: {result.stderr}")
                    load_test_results[scenario_name] = {'error': result.stderr}
                    
            except Exception as e:
                logger.error(f"Load test {scenario_name} failed: {e}")
                load_test_results[scenario_name] = {'error': str(e)}
        
        self.results['load_test_results'] = load_test_results
    
    def _generate_k6_script(self, scenario_config: Dict) -> str:
        """Generate K6 test script for scenario"""
        return f"""
import http from 'k6/http';
import {{ check }} from 'k6';

export let options = {{
    vus: {scenario_config['users']},
    duration: '{scenario_config['duration']}',
}};

export default function() {{
    let response = http.get('{self.base_url}/api/health');
    check(response, {{
        'status is 200': (r) => r.status === 200,
        'response time < 1000ms': (r) => r.timings.duration < 1000,
    }});
}}
"""
    
    def _parse_k6_results(self, results_file: str) -> Dict:
        """Parse K6 JSON results file"""
        try:
            if not os.path.exists(results_file):
                return {'error': 'Results file not found'}
            
            with open(results_file, 'r') as f:
                lines = f.readlines()
            
            # Parse K6 JSON output (each line is a JSON object)
            metrics = {}
            for line in lines:
                try:
                    data = json.loads(line)
                    if data.get('type') == 'Metric':
                        metric_name = data.get('data', {}).get('name')
                        metric_value = data.get('data', {}).get('value')
                        if metric_name and metric_value is not None:
                            metrics[metric_name] = metric_value
                except:
                    continue
            
            return {
                'avg_response_time': metrics.get('http_req_duration', {}).get('avg', 0),
                'p95_response_time': metrics.get('http_req_duration', {}).get('p(95)', 0),
                'error_rate': metrics.get('http_req_failed', 0),
                'throughput': metrics.get('http_reqs', 0),
                'total_requests': metrics.get('http_reqs', 0)
            }
        except Exception as e:
            return {'error': f'Failed to parse K6 results: {e}'}
    
    async def validate_database_performance(self):
        """Validate database performance metrics"""
        logger.info("Validating database performance...")
        
        # This would require database connection and query analysis
        # For now, we'll simulate based on service response times
        db_results = {
            'note': 'Database performance validation requires direct DB access',
            'estimated_from_api_performance': True
        }
        
        # Estimate based on API performance results
        api_results = self.results.get('validation_results', {}).get('api_performance', {})
        if api_results:
            avg_times = [result.get('avg_response_time_ms', 0) for result in api_results.values()]
            if avg_times:
                estimated_db_time = statistics.mean(avg_times) * 0.6  # Assume 60% of API time is DB
                db_results['estimated_query_time_ms'] = estimated_db_time
                db_results['target_met'] = estimated_db_time < self.targets['database_query_time_ms']
                
                if not db_results['target_met']:
                    self.results['failed_tests'].append(
                        f"Estimated database query time {estimated_db_time:.1f}ms exceeds target {self.targets['database_query_time_ms']}ms"
                    )
        
        self.results['validation_results']['database_performance'] = db_results
    
    async def validate_cache_performance(self):
        """Validate cache performance and hit rates"""
        logger.info("Validating cache performance...")
        
        cache_results = {}
        
        # Test cache behavior with repeated requests
        async with aiohttp.ClientSession() as session:
            cache_endpoints = ['/api/users/profile', '/api/workspaces', '/api/settings']
            
            for endpoint in cache_endpoints:
                try:
                    response_times = []
                    cache_headers = []
                    
                    # Make multiple requests to test caching
                    for i in range(10):
                        start_time = time.time()
                        async with session.get(f"{self.base_url}{endpoint}", 
                                             headers={'Authorization': 'Bearer test-token'}) as response:
                            response_time = (time.time() - start_time) * 1000
                            response_times.append(response_time)
                            
                            # Check for cache headers
                            cache_header = response.headers.get('X-Cache', 'MISS')
                            cache_headers.append(cache_header)
                        
                        await asyncio.sleep(0.1)
                    
                    # Calculate cache hit rate
                    cache_hits = len([h for h in cache_headers if h == 'HIT'])
                    cache_hit_rate = cache_hits / len(cache_headers) if cache_headers else 0
                    
                    cache_results[endpoint] = {
                        'cache_hit_rate': cache_hit_rate,
                        'avg_response_time_ms': statistics.mean(response_times),
                        'cache_headers': cache_headers,
                        'target_met': cache_hit_rate >= self.targets['cache_hit_rate']
                    }
                    
                    if cache_hit_rate < self.targets['cache_hit_rate']:
                        self.results['failed_tests'].append(
                            f"Cache hit rate for {endpoint} {cache_hit_rate:.1%} below target {self.targets['cache_hit_rate']:.1%}"
                        )
                        
                except Exception as e:
                    logger.warning(f"Cache test failed for {endpoint}: {e}")
                    cache_results[endpoint] = {'error': str(e)}
        
        self.results['validation_results']['cache_performance'] = cache_results
    
    async def validate_system_resources(self):
        """Validate system resource utilization"""
        logger.info("Validating system resources...")
        
        try:
            # Get Docker container stats
            docker_cmd = ['docker', 'stats', '--no-stream', '--format', 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}']
            result = subprocess.run(docker_cmd, capture_output=True, text=True, timeout=30)
            
            resource_results = {}
            
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')[1:]  # Skip header
                for line in lines:
                    parts = line.split('\t')
                    if len(parts) >= 4:
                        container_name = parts[0]
                        cpu_percent = float(parts[1].replace('%', ''))
                        memory_usage = parts[2]
                        memory_percent = float(parts[3].replace('%', ''))
                        
                        resource_results[container_name] = {
                            'cpu_percent': cpu_percent,
                            'memory_usage': memory_usage,
                            'memory_percent': memory_percent,
                            'cpu_target_met': cpu_percent < (self.targets['cpu_utilization_threshold'] * 100),
                            'memory_target_met': memory_percent < (self.targets['memory_utilization_threshold'] * 100)
                        }
                        
                        if cpu_percent >= (self.targets['cpu_utilization_threshold'] * 100):
                            self.results['failed_tests'].append(
                                f"{container_name} CPU usage {cpu_percent:.1f}% exceeds target {self.targets['cpu_utilization_threshold']*100:.1f}%"
                            )
                        
                        if memory_percent >= (self.targets['memory_utilization_threshold'] * 100):
                            self.results['failed_tests'].append(
                                f"{container_name} memory usage {memory_percent:.1f}% exceeds target {self.targets['memory_utilization_threshold']*100:.1f}%"
                            )
            
            self.results['validation_results']['system_resources'] = resource_results
            
        except Exception as e:
            logger.error(f"System resource validation failed: {e}")
            self.results['validation_results']['system_resources'] = {'error': str(e)}
    
    async def generate_recommendations(self):
        """Generate performance optimization recommendations"""
        logger.info("Generating performance recommendations...")
        
        recommendations = []
        
        # Analyze failed tests and generate recommendations
        for failed_test in self.results['failed_tests']:
            if 'response time' in failed_test.lower():
                recommendations.append({
                    'category': 'API Performance',
                    'issue': failed_test,
                    'recommendation': 'Implement caching, optimize database queries, or add connection pooling',
                    'priority': 'HIGH'
                })
            elif 'cpu usage' in failed_test.lower():
                recommendations.append({
                    'category': 'Resource Optimization',
                    'issue': failed_test,
                    'recommendation': 'Optimize CPU-intensive operations or increase CPU allocation',
                    'priority': 'HIGH'
                })
            elif 'memory usage' in failed_test.lower():
                recommendations.append({
                    'category': 'Resource Optimization',
                    'issue': failed_test,
                    'recommendation': 'Implement memory optimization or increase memory allocation',
                    'priority': 'HIGH'
                })
            elif 'cache hit rate' in failed_test.lower():
                recommendations.append({
                    'category': 'Caching',
                    'issue': failed_test,
                    'recommendation': 'Review cache TTL settings and implement cache warming strategies',
                    'priority': 'MEDIUM'
                })
            elif 'error rate' in failed_test.lower():
                recommendations.append({
                    'category': 'Reliability',
                    'issue': failed_test,
                    'recommendation': 'Implement circuit breakers, retry logic, and error handling',
                    'priority': 'HIGH'
                })
        
        # Add general recommendations based on results
        api_results = self.results.get('validation_results', {}).get('api_performance', {})
        if api_results:
            avg_response_times = [r.get('avg_response_time_ms', 0) for r in api_results.values()]
            if avg_response_times and statistics.mean(avg_response_times) > 100:
                recommendations.append({
                    'category': 'General Performance',
                    'issue': 'Overall API response times could be improved',
                    'recommendation': 'Consider implementing a comprehensive caching strategy and database optimization',
                    'priority': 'MEDIUM'
                })
        
        self.results['recommendations'] = recommendations
    
    async def generate_performance_report(self):
        """Generate comprehensive performance report"""
        logger.info("Generating performance report...")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # JSON report
        json_report_path = f"performance-validation-report-{timestamp}.json"
        with open(json_report_path, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        
        # Markdown report
        md_report_path = f"performance-validation-report-{timestamp}.md"
        await self._generate_markdown_report(md_report_path)
        
        logger.info(f"Performance reports saved: {json_report_path}, {md_report_path}")
    
    async def _generate_markdown_report(self, report_path: str):
        """Generate markdown performance report"""
        with open(report_path, 'w') as f:
            f.write("# PyAirtable Performance Validation Report\n\n")
            f.write(f"**Generated:** {self.results['timestamp']}\n")
            f.write(f"**Status:** {'✅ PASSED' if self.results['passed'] else '❌ FAILED'}\n\n")
            
            # Performance Targets
            f.write("## Performance Targets\n\n")
            f.write(f"- API Response Time: <{self.targets['api_response_time_ms']}ms\n")
            f.write(f"- Frontend Load Time: <{self.targets['frontend_load_time_ms']}ms\n")
            f.write(f"- Max Concurrent Users: {self.targets['max_concurrent_users']}\n")
            f.write(f"- Error Rate Threshold: <{self.targets['error_rate_threshold']*100:.1f}%\n")
            f.write(f"- Throughput: >{self.targets['throughput_rps']} RPS\n\n")
            
            # Failed Tests
            if self.results['failed_tests']:
                f.write("## Failed Tests ❌\n\n")
                for test in self.results['failed_tests']:
                    f.write(f"- {test}\n")
                f.write("\n")
            
            # Service Health
            health_results = self.results.get('validation_results', {}).get('service_health', {})
            if health_results:
                f.write("## Service Health Status\n\n")
                for service, health in health_results.items():
                    status = "✅" if health.get('healthy', False) else "❌"
                    f.write(f"- **{service}**: {status} ({health.get('response_time_ms', 0):.1f}ms)\n")
                f.write("\n")
            
            # API Performance
            api_results = self.results.get('validation_results', {}).get('api_performance', {})
            if api_results:
                f.write("## API Performance Results\n\n")
                for endpoint, metrics in api_results.items():
                    status = "✅" if metrics.get('target_met', False) else "❌"
                    f.write(f"- **{endpoint}**: {status}\n")
                    f.write(f"  - P95 Response Time: {metrics.get('p95_response_time_ms', 0):.1f}ms\n")
                    f.write(f"  - Success Rate: {metrics.get('success_rate', 0):.1%}\n\n")
            
            # Recommendations
            if self.results.get('recommendations'):
                f.write("## Recommendations\n\n")
                high_priority = [r for r in self.results['recommendations'] if r.get('priority') == 'HIGH']
                medium_priority = [r for r in self.results['recommendations'] if r.get('priority') == 'MEDIUM']
                
                if high_priority:
                    f.write("### High Priority\n\n")
                    for rec in high_priority:
                        f.write(f"- **{rec.get('category')}**: {rec.get('recommendation')}\n")
                        f.write(f"  - Issue: {rec.get('issue')}\n\n")
                
                if medium_priority:
                    f.write("### Medium Priority\n\n")
                    for rec in medium_priority:
                        f.write(f"- **{rec.get('category')}**: {rec.get('recommendation')}\n")
                        f.write(f"  - Issue: {rec.get('issue')}\n\n")
    
    def _percentile(self, data, percentile):
        """Calculate percentile of a dataset"""
        if not data:
            return 0
        sorted_data = sorted(data)
        index = (percentile / 100) * len(sorted_data)
        if index.is_integer():
            return sorted_data[int(index) - 1]
        else:
            lower = sorted_data[int(index)]
            upper = sorted_data[int(index) + 1] if int(index) + 1 < len(sorted_data) else lower
            return lower + (upper - lower) * (index - int(index))

async def main():
    """Main function to run performance validation"""
    import argparse
    
    parser = argparse.ArgumentParser(description='PyAirtable Performance Validation')
    parser.add_argument('--config', help='Configuration file path', default='performance-targets.yml')
    parser.add_argument('--output', help='Output directory', default='.')
    
    args = parser.parse_args()
    
    validator = PerformanceValidator(args.config)
    results = await validator.run_full_validation()
    
    # Exit with appropriate code
    sys.exit(0 if results['passed'] else 1)

if __name__ == "__main__":
    asyncio.run(main())