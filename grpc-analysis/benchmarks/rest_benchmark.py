#!/usr/bin/env python3
"""
REST API Performance Benchmark Tool for PyAirtable
Measures current HTTP/JSON performance characteristics
"""

import asyncio
import aiohttp
import json
import time
import statistics
import sys
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from concurrent.futures import ThreadPoolExecutor
import argparse
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class BenchmarkResult:
    operation: str
    total_requests: int
    successful_requests: int
    failed_requests: int
    total_time_ms: float
    avg_response_time_ms: float
    min_response_time_ms: float
    max_response_time_ms: float
    p50_response_time_ms: float
    p95_response_time_ms: float
    p99_response_time_ms: float
    requests_per_second: float
    avg_payload_size_bytes: int
    total_bytes_transferred: int
    error_rate_percent: float
    connection_errors: int
    timeout_errors: int
    
    def to_dict(self):
        return asdict(self)

@dataclass
class PayloadSizeResult:
    payload_size_bytes: int
    serialization_time_ms: float
    deserialization_time_ms: float
    network_time_ms: float
    total_time_ms: float
    compression_ratio: Optional[float] = None

class RESTBenchmark:
    def __init__(self, base_url: str, api_key: str):
        self.base_url = base_url.rstrip('/')
        self.api_key = api_key
        self.session: Optional[aiohttp.ClientSession] = None
        
    async def __aenter__(self):
        connector = aiohttp.TCPConnector(
            limit=100,  # Connection pool size
            limit_per_host=20,
            keepalive_timeout=60,
            enable_cleanup_closed=True
        )
        
        timeout = aiohttp.ClientTimeout(total=30, connect=10)
        
        self.session = aiohttp.ClientSession(
            connector=connector,
            timeout=timeout,
            headers={
                'Authorization': f'Bearer {self.api_key}',
                'Content-Type': 'application/json',
                'Accept': 'application/json'
            }
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()

    async def make_request(self, method: str, endpoint: str, data: Optional[Dict] = None) -> Dict[str, Any]:
        """Make a single HTTP request and measure performance"""
        url = f"{self.base_url}{endpoint}"
        
        # Measure serialization time for POST/PUT requests
        serialization_start = time.perf_counter()
        json_data = json.dumps(data) if data else None
        serialization_time = (time.perf_counter() - serialization_start) * 1000
        
        # Measure network request time
        request_start = time.perf_counter()
        
        try:
            async with self.session.request(method, url, data=json_data) as response:
                response_text = await response.text()
                network_time = (time.perf_counter() - request_start) * 1000
                
                # Measure deserialization time
                deserialization_start = time.perf_counter()
                try:
                    response_data = json.loads(response_text) if response_text else {}
                except json.JSONDecodeError:
                    response_data = {"raw_response": response_text}
                deserialization_time = (time.perf_counter() - deserialization_start) * 1000
                
                payload_size = len(response_text.encode('utf-8'))
                
                return {
                    'success': response.status < 400,
                    'status_code': response.status,
                    'data': response_data,
                    'serialization_time_ms': serialization_time,
                    'network_time_ms': network_time,
                    'deserialization_time_ms': deserialization_time,
                    'total_time_ms': serialization_time + network_time + deserialization_time,
                    'payload_size_bytes': payload_size,
                    'error_type': None
                }
                
        except asyncio.TimeoutError:
            return {
                'success': False,
                'error_type': 'timeout',
                'total_time_ms': (time.perf_counter() - request_start) * 1000,
                'payload_size_bytes': 0
            }
        except aiohttp.ClientError as e:
            return {
                'success': False,
                'error_type': 'connection',
                'error_message': str(e),
                'total_time_ms': (time.perf_counter() - request_start) * 1000,
                'payload_size_bytes': 0
            }

    async def run_load_test(self, method: str, endpoint: str, num_requests: int, 
                           concurrency: int, data: Optional[Dict] = None) -> BenchmarkResult:
        """Run a load test with specified concurrency"""
        
        logger.info(f"Running load test: {method} {endpoint} - {num_requests} requests, {concurrency} concurrent")
        
        semaphore = asyncio.Semaphore(concurrency)
        results = []
        
        async def single_request():
            async with semaphore:
                return await self.make_request(method, endpoint, data)
        
        start_time = time.perf_counter()
        
        # Execute all requests
        tasks = [single_request() for _ in range(num_requests)]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        total_time = (time.perf_counter() - start_time) * 1000
        
        # Process results
        successful_results = [r for r in results if isinstance(r, dict) and r.get('success', False)]
        failed_results = [r for r in results if isinstance(r, dict) and not r.get('success', False)]
        exception_results = [r for r in results if isinstance(r, Exception)]
        
        if not successful_results:
            # Handle case where all requests failed
            return BenchmarkResult(
                operation=f"{method} {endpoint}",
                total_requests=num_requests,
                successful_requests=0,
                failed_requests=len(failed_results) + len(exception_results),
                total_time_ms=total_time,
                avg_response_time_ms=0,
                min_response_time_ms=0,
                max_response_time_ms=0,
                p50_response_time_ms=0,
                p95_response_time_ms=0,
                p99_response_time_ms=0,
                requests_per_second=0,
                avg_payload_size_bytes=0,
                total_bytes_transferred=0,
                error_rate_percent=100.0,
                connection_errors=len([r for r in failed_results if r.get('error_type') == 'connection']),
                timeout_errors=len([r for r in failed_results if r.get('error_type') == 'timeout'])
            )
        
        # Calculate timing statistics
        response_times = [r['total_time_ms'] for r in successful_results]
        payload_sizes = [r['payload_size_bytes'] for r in successful_results]
        
        return BenchmarkResult(
            operation=f"{method} {endpoint}",
            total_requests=num_requests,
            successful_requests=len(successful_results),
            failed_requests=len(failed_results) + len(exception_results),
            total_time_ms=total_time,
            avg_response_time_ms=statistics.mean(response_times),
            min_response_time_ms=min(response_times),
            max_response_time_ms=max(response_times),
            p50_response_time_ms=statistics.median(response_times),
            p95_response_time_ms=self._percentile(response_times, 95),
            p99_response_time_ms=self._percentile(response_times, 99),
            requests_per_second=(len(successful_results) / total_time) * 1000,
            avg_payload_size_bytes=int(statistics.mean(payload_sizes)) if payload_sizes else 0,
            total_bytes_transferred=sum(payload_sizes),
            error_rate_percent=(len(failed_results) + len(exception_results)) / num_requests * 100,
            connection_errors=len([r for r in failed_results if r.get('error_type') == 'connection']),
            timeout_errors=len([r for r in failed_results if r.get('error_type') == 'timeout'])
        )

    def _percentile(self, data: List[float], percentile: int) -> float:
        """Calculate percentile value"""
        if not data:
            return 0
        sorted_data = sorted(data)
        index = int((percentile / 100) * len(sorted_data))
        if index >= len(sorted_data):
            index = len(sorted_data) - 1
        return sorted_data[index]

    async def test_payload_sizes(self, endpoint: str, base_payload: Dict) -> List[PayloadSizeResult]:
        """Test performance with different payload sizes"""
        results = []
        
        # Test different payload sizes by duplicating data
        multipliers = [1, 2, 5, 10, 25, 50, 100]
        
        for multiplier in multipliers:
            # Create larger payload by repeating the base data
            large_payload = {}
            for key, value in base_payload.items():
                if isinstance(value, str):
                    large_payload[f"{key}_{i}"] = value * multiplier for i in range(multiplier)
                elif isinstance(value, dict):
                    large_payload[f"{key}_{i}"] = value for i in range(multiplier)
                else:
                    large_payload[f"{key}_{i}"] = value for i in range(multiplier)
            
            # Flatten the structure
            if multiplier > 1:
                flattened = {}
                for key, value_list in large_payload.items():
                    if isinstance(value_list, list):
                        for i, value in enumerate(value_list):
                            flattened[f"{key}_{i}"] = value
                    else:
                        flattened[key] = value_list
                large_payload = flattened
            
            result = await self.make_request('POST', endpoint, large_payload)
            
            if result.get('success'):
                payload_size = len(json.dumps(large_payload).encode('utf-8'))
                results.append(PayloadSizeResult(
                    payload_size_bytes=payload_size,
                    serialization_time_ms=result['serialization_time_ms'],
                    deserialization_time_ms=result['deserialization_time_ms'],
                    network_time_ms=result['network_time_ms'],
                    total_time_ms=result['total_time_ms']
                ))
            
        return results

    async def benchmark_authentication_flows(self) -> List[BenchmarkResult]:
        """Benchmark authentication-related operations"""
        results = []
        
        # Test user registration
        register_data = {
            "email": f"bench_user_{int(time.time())}@test.com",
            "password": "testpass123",
            "first_name": "Benchmark",
            "last_name": "User"
        }
        
        result = await self.run_load_test('POST', '/api/v1/auth/register', 10, 2, register_data)
        results.append(result)
        
        # Test user login
        login_data = {
            "email": "admin@alpha.test.com",
            "password": "testpass123"
        }
        
        result = await self.run_load_test('POST', '/api/v1/auth/login', 100, 10, login_data)
        results.append(result)
        
        # Test token validation (high frequency operation)
        result = await self.run_load_test('GET', '/api/v1/auth/me', 500, 25)
        results.append(result)
        
        return results

    async def benchmark_workspace_operations(self) -> List[BenchmarkResult]:
        """Benchmark workspace-related operations"""
        results = []
        
        # Test workspace listing (common operation)
        result = await self.run_load_test('GET', '/api/v1/workspaces', 200, 20)
        results.append(result)
        
        # Test workspace creation
        workspace_data = {
            "name": f"Benchmark Workspace {int(time.time())}",
            "description": "Workspace created for performance benchmarking"
        }
        
        result = await self.run_load_test('POST', '/api/v1/workspaces', 20, 5, workspace_data)
        results.append(result)
        
        # Test workspace retrieval
        result = await self.run_load_test('GET', '/api/v1/workspaces/00000000-0000-0000-0000-000000000001', 100, 10)
        results.append(result)
        
        return results

    async def benchmark_airtable_operations(self) -> List[BenchmarkResult]:
        """Benchmark Airtable API integration operations"""
        results = []
        
        # Test base listing
        result = await self.run_load_test('GET', '/api/v1/airtable/bases', 50, 10)
        results.append(result)
        
        # Test table listing
        result = await self.run_load_test('GET', '/api/v1/airtable/bases/test_base/tables', 100, 15)
        results.append(result)
        
        # Test record listing (potentially large responses)
        result = await self.run_load_test('GET', '/api/v1/airtable/bases/test_base/tables/test_table/records', 75, 10)
        results.append(result)
        
        # Test record creation
        record_data = {
            "fields": {
                "Name": f"Benchmark Record {int(time.time())}",
                "Description": "Record created for performance testing",
                "Status": "Active",
                "Priority": "High",
                "Created Date": "2024-01-01"
            }
        }
        
        result = await self.run_load_test('POST', '/api/v1/airtable/bases/test_base/tables/test_table/records', 30, 5, record_data)
        results.append(result)
        
        return results

    async def benchmark_bulk_operations(self) -> List[BenchmarkResult]:
        """Benchmark bulk operations that handle multiple records"""
        results = []
        
        # Test bulk record creation (simulated)
        bulk_data = {
            "records": [
                {
                    "fields": {
                        "Name": f"Bulk Record {i}",
                        "Description": f"Bulk test record number {i}",
                        "Status": "Active" if i % 2 == 0 else "Inactive",
                        "Priority": ["Low", "Medium", "High"][i % 3],
                        "Value": i * 100
                    }
                } for i in range(10)
            ]
        }
        
        result = await self.run_load_test('POST', '/api/v1/airtable/bases/test_base/tables/test_table/batch', 20, 3, bulk_data)
        results.append(result)
        
        # Test large payload operations
        large_bulk_data = {
            "records": [
                {
                    "fields": {
                        "Name": f"Large Bulk Record {i}",
                        "Description": f"Large bulk test record with extensive data. " * 50,  # ~2KB per description
                        "Status": "Active",
                        "Large_Text_Field": "X" * 1000,  # 1KB of data
                        "Metadata": {
                            "created_by": "benchmark_system",
                            "tags": [f"tag_{j}" for j in range(20)],
                            "properties": {f"prop_{k}": f"value_{k}" for k in range(10)}
                        }
                    }
                } for i in range(5)  # ~15KB total payload
            ]
        }
        
        result = await self.run_load_test('POST', '/api/v1/airtable/bases/test_base/tables/test_table/large_batch', 10, 2, large_bulk_data)
        results.append(result)
        
        return results

    async def benchmark_real_time_operations(self) -> List[BenchmarkResult]:
        """Benchmark operations that might be used in real-time scenarios"""
        results = []
        
        # Test permission checks (high frequency)
        permission_data = {
            "user_id": "00000000-0000-0000-0000-000000000001",
            "resource_type": "workspace",
            "resource_id": "00000000-0000-0000-0000-000000000001",
            "action": "read",
            "tenant_id": "00000000-0000-0000-0000-000000000001"
        }
        
        result = await self.run_load_test('POST', '/api/v1/permissions/check', 1000, 50, permission_data)
        results.append(result)
        
        # Test notification sending
        notification_data = {
            "recipient": "test@example.com",
            "subject": "Benchmark Notification",
            "message": "This is a benchmark notification",
            "type": "email"
        }
        
        result = await self.run_load_test('POST', '/api/v1/notifications/send', 50, 10, notification_data)
        results.append(result)
        
        return results

async def run_comprehensive_benchmark(base_url: str, api_key: str) -> Dict[str, Any]:
    """Run comprehensive REST API benchmark"""
    
    async with RESTBenchmark(base_url, api_key) as benchmark:
        all_results = []
        
        logger.info("Starting authentication flow benchmarks...")
        auth_results = await benchmark.benchmark_authentication_flows()
        all_results.extend(auth_results)
        
        logger.info("Starting workspace operation benchmarks...")
        workspace_results = await benchmark.benchmark_workspace_operations()
        all_results.extend(workspace_results)
        
        logger.info("Starting Airtable operation benchmarks...")
        airtable_results = await benchmark.benchmark_airtable_operations()
        all_results.extend(airtable_results)
        
        logger.info("Starting bulk operation benchmarks...")
        bulk_results = await benchmark.benchmark_bulk_operations()
        all_results.extend(bulk_results)
        
        logger.info("Starting real-time operation benchmarks...")
        realtime_results = await benchmark.benchmark_real_time_operations()
        all_results.extend(realtime_results)
        
        # Test payload size impact
        logger.info("Testing payload size impact...")
        base_payload = {"name": "test", "description": "test description", "data": {"key": "value"}}
        payload_results = await benchmark.test_payload_sizes('/api/v1/test/payload', base_payload)
        
        # Calculate aggregate statistics
        total_requests = sum(r.total_requests for r in all_results)
        total_successful = sum(r.successful_requests for r in all_results)
        total_failed = sum(r.failed_requests for r in all_results)
        avg_response_time = statistics.mean([r.avg_response_time_ms for r in all_results if r.successful_requests > 0])
        total_throughput = sum(r.requests_per_second for r in all_results)
        total_data_transferred = sum(r.total_bytes_transferred for r in all_results)
        
        return {
            "summary": {
                "total_requests": total_requests,
                "successful_requests": total_successful,
                "failed_requests": total_failed,
                "overall_success_rate": (total_successful / total_requests) * 100 if total_requests > 0 else 0,
                "average_response_time_ms": avg_response_time,
                "total_requests_per_second": total_throughput,
                "total_data_transferred_mb": total_data_transferred / (1024 * 1024),
                "benchmark_timestamp": time.time()
            },
            "detailed_results": [r.to_dict() for r in all_results],
            "payload_size_analysis": [asdict(r) for r in payload_results],
            "performance_bottlenecks": analyze_bottlenecks(all_results),
            "recommendations": generate_recommendations(all_results)
        }

def analyze_bottlenecks(results: List[BenchmarkResult]) -> Dict[str, Any]:
    """Analyze performance results to identify bottlenecks"""
    
    # Find operations with highest response times
    slow_operations = sorted(results, key=lambda r: r.avg_response_time_ms, reverse=True)[:5]
    
    # Find operations with highest error rates
    error_prone_operations = sorted(results, key=lambda r: r.error_rate_percent, reverse=True)[:5]
    
    # Find operations with lowest throughput
    low_throughput_operations = sorted(results, key=lambda r: r.requests_per_second)[:5]
    
    # Analyze response time distribution
    all_avg_times = [r.avg_response_time_ms for r in results if r.successful_requests > 0]
    all_p95_times = [r.p95_response_time_ms for r in results if r.successful_requests > 0]
    
    return {
        "slowest_operations": [
            {"operation": r.operation, "avg_response_time_ms": r.avg_response_time_ms, "p95_response_time_ms": r.p95_response_time_ms}
            for r in slow_operations
        ],
        "highest_error_rate_operations": [
            {"operation": r.operation, "error_rate_percent": r.error_rate_percent, "failed_requests": r.failed_requests}
            for r in error_prone_operations
        ],
        "lowest_throughput_operations": [
            {"operation": r.operation, "requests_per_second": r.requests_per_second}
            for r in low_throughput_operations
        ],
        "response_time_analysis": {
            "avg_response_time_ms": statistics.mean(all_avg_times) if all_avg_times else 0,
            "median_response_time_ms": statistics.median(all_avg_times) if all_avg_times else 0,
            "p95_response_time_ms": statistics.mean(all_p95_times) if all_p95_times else 0,
            "max_response_time_ms": max(all_avg_times) if all_avg_times else 0
        }
    }

def generate_recommendations(results: List[BenchmarkResult]) -> List[str]:
    """Generate performance improvement recommendations based on results"""
    recommendations = []
    
    # Analyze response times
    avg_response_times = [r.avg_response_time_ms for r in results if r.successful_requests > 0]
    if avg_response_times:
        avg_response_time = statistics.mean(avg_response_times)
        
        if avg_response_time > 500:
            recommendations.append("High average response times detected (>500ms). Consider implementing caching, database query optimization, or moving to gRPC for better performance.")
        
        if max(avg_response_times) > 2000:
            recommendations.append("Some operations exceed 2 seconds response time. These operations should be prioritized for optimization or moved to async processing.")
    
    # Analyze error rates
    high_error_operations = [r for r in results if r.error_rate_percent > 5]
    if high_error_operations:
        recommendations.append(f"{len(high_error_operations)} operations have error rates above 5%. Investigate connection pooling, timeout settings, and service stability.")
    
    # Analyze throughput
    low_throughput_operations = [r for r in results if r.requests_per_second < 10 and r.successful_requests > 0]
    if low_throughput_operations:
        recommendations.append("Several operations have low throughput (<10 req/s). Consider connection pooling optimization, HTTP/2, or gRPC for better concurrency.")
    
    # Analyze payload sizes
    large_payload_operations = [r for r in results if r.avg_payload_size_bytes > 50000]  # >50KB
    if large_payload_operations:
        recommendations.append("Large payloads detected (>50KB). Consider implementing response compression, field filtering, or streaming APIs.")
    
    return recommendations

def main():
    parser = argparse.ArgumentParser(description='REST API Performance Benchmark')
    parser.add_argument('--url', default='http://localhost:8000', help='Base URL of the API')
    parser.add_argument('--api-key', required=True, help='API key for authentication')
    parser.add_argument('--output', default='rest_benchmark_results.json', help='Output file for results')
    
    args = parser.parse_args()
    
    # Run the benchmark
    results = asyncio.run(run_comprehensive_benchmark(args.url, args.api_key))
    
    # Save results to file
    with open(args.output, 'w') as f:
        json.dump(results, f, indent=2)
    
    # Print summary
    summary = results['summary']
    print("\n" + "="*80)
    print("REST API PERFORMANCE BENCHMARK RESULTS")
    print("="*80)
    print(f"Total Requests: {summary['total_requests']:,}")
    print(f"Successful Requests: {summary['successful_requests']:,}")
    print(f"Failed Requests: {summary['failed_requests']:,}")
    print(f"Success Rate: {summary['overall_success_rate']:.2f}%")
    print(f"Average Response Time: {summary['average_response_time_ms']:.2f}ms")
    print(f"Total Throughput: {summary['total_requests_per_second']:.2f} req/s")
    print(f"Data Transferred: {summary['total_data_transferred_mb']:.2f} MB")
    
    print("\nTOP PERFORMANCE BOTTLENECKS:")
    for bottleneck in results['performance_bottlenecks']['slowest_operations'][:3]:
        print(f"  - {bottleneck['operation']}: {bottleneck['avg_response_time_ms']:.2f}ms avg, {bottleneck['p95_response_time_ms']:.2f}ms P95")
    
    print("\nRECOMMENDations:")
    for i, rec in enumerate(results['recommendations'][:5], 1):
        print(f"  {i}. {rec}")
    
    print(f"\nDetailed results saved to: {args.output}")

if __name__ == '__main__':
    main()