#!/usr/bin/env python3
"""
PyAirtable Performance Baseline Analysis Script
Comprehensive performance profiling for MacBook Air M2 deployment
"""

import asyncio
import aiohttp
import psutil
import docker
import json
import time
import logging
import subprocess
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Any
import statistics
import sqlite3

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('performance-baseline.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class PerformanceAnalyzer:
    """Comprehensive performance analysis for PyAirtable services"""
    
    def __init__(self):
        self.base_url = "http://localhost:8000"
        self.services = {
            'api-gateway': 'http://localhost:8000',
            'llm-orchestrator': 'http://localhost:8003',
            'mcp-server': 'http://localhost:8001',
            'airtable-gateway': 'http://localhost:8002',
            'platform-services': 'http://localhost:8007',
            'automation-services': 'http://localhost:8006',
            'saga-orchestrator': 'http://localhost:8008',
            'frontend': 'http://localhost:3000'
        }
        self.docker_client = docker.from_env()
        self.results = {
            'timestamp': datetime.now().isoformat(),
            'system_info': {},
            'service_performance': {},
            'resource_utilization': {},
            'database_performance': {},
            'cache_performance': {},
            'network_performance': {},
            'recommendations': []
        }
        
    async def run_complete_analysis(self):
        """Run comprehensive performance analysis"""
        logger.info("Starting PyAirtable Performance Baseline Analysis")
        
        # System information
        await self.analyze_system_info()
        
        # Service startup analysis
        await self.analyze_service_startup_times()
        
        # API performance analysis
        await self.analyze_api_performance()
        
        # Resource utilization analysis
        await self.analyze_resource_utilization()
        
        # Database performance analysis
        await self.analyze_database_performance()
        
        # Cache performance analysis
        await self.analyze_cache_performance()
        
        # Network performance analysis
        await self.analyze_network_performance()
        
        # Generate recommendations
        await self.generate_recommendations()
        
        # Save results
        await self.save_results()
        
        logger.info("Performance baseline analysis completed")
        
    async def analyze_system_info(self):
        """Analyze system information and capabilities"""
        logger.info("Analyzing system information...")
        
        # CPU information
        cpu_info = {
            'physical_cores': psutil.cpu_count(logical=False),
            'logical_cores': psutil.cpu_count(logical=True),
            'cpu_freq': psutil.cpu_freq()._asdict() if psutil.cpu_freq() else {},
            'cpu_percent': psutil.cpu_percent(interval=1),
            'architecture': subprocess.check_output(['uname', '-m']).decode().strip()
        }
        
        # Memory information
        memory = psutil.virtual_memory()
        memory_info = {
            'total': memory.total,
            'available': memory.available,
            'percent': memory.percent,
            'used': memory.used,
            'free': memory.free
        }
        
        # Disk information
        disk = psutil.disk_usage('/')
        disk_info = {
            'total': disk.total,
            'used': disk.used,
            'free': disk.free,
            'percent': (disk.used / disk.total) * 100
        }
        
        # Docker information
        try:
            docker_info = self.docker_client.info()
            docker_stats = {
                'containers_running': docker_info.get('ContainersRunning', 0),
                'containers_total': docker_info.get('Containers', 0),
                'images': docker_info.get('Images', 0),
                'memory_limit': docker_info.get('MemTotal', 0),
                'cpu_count': docker_info.get('NCPU', 0)
            }
        except Exception as e:
            logger.warning(f"Failed to get Docker info: {e}")
            docker_stats = {}
        
        self.results['system_info'] = {
            'cpu': cpu_info,
            'memory': memory_info,
            'disk': disk_info,
            'docker': docker_stats,
            'timestamp': datetime.now().isoformat()
        }
        
    async def analyze_service_startup_times(self):
        """Analyze service startup and readiness times"""
        logger.info("Analyzing service startup times...")
        
        startup_times = {}
        
        try:
            containers = self.docker_client.containers.list()
            for container in containers:
                if any(service in container.name for service in self.services.keys()):
                    try:
                        # Get container stats
                        stats = container.stats(stream=False)
                        created_at = container.attrs['Created']
                        started_at = container.attrs['State']['StartedAt']
                        
                        # Calculate startup time
                        if created_at and started_at:
                            created = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                            started = datetime.fromisoformat(started_at.replace('Z', '+00:00'))
                            startup_time = (started - created).total_seconds()
                        else:
                            startup_time = None
                            
                        startup_times[container.name] = {
                            'startup_time_seconds': startup_time,
                            'status': container.status,
                            'cpu_usage': self._calculate_cpu_usage(stats),
                            'memory_usage': stats['memory_stats'].get('usage', 0),
                            'memory_limit': stats['memory_stats'].get('limit', 0),
                            'network_rx': stats['networks']['eth0']['rx_bytes'] if 'networks' in stats else 0,
                            'network_tx': stats['networks']['eth0']['tx_bytes'] if 'networks' in stats else 0
                        }
                    except Exception as e:
                        logger.warning(f"Failed to get stats for {container.name}: {e}")
                        startup_times[container.name] = {'error': str(e)}
                        
        except Exception as e:
            logger.error(f"Failed to analyze startup times: {e}")
            
        self.results['service_startup'] = startup_times
        
    async def analyze_api_performance(self):
        """Analyze API endpoint performance"""
        logger.info("Analyzing API performance...")
        
        # Test endpoints with various scenarios
        test_endpoints = [
            {'url': '/api/health', 'method': 'GET', 'expected_status': 200},
            {'url': '/api/users/profile', 'method': 'GET', 'expected_status': 401},  # No auth
            {'url': '/api/workspaces', 'method': 'GET', 'expected_status': 401},    # No auth
        ]
        
        performance_results = {}
        
        async with aiohttp.ClientSession() as session:
            for service_name, service_url in self.services.items():
                if service_name == 'frontend':
                    continue  # Skip frontend for API tests
                    
                service_results = {}
                
                for endpoint in test_endpoints:
                    try:
                        # Run multiple requests to get statistical data
                        response_times = []
                        status_codes = []
                        
                        for _ in range(10):  # 10 requests per endpoint
                            start_time = time.time()
                            
                            try:
                                async with session.request(
                                    endpoint['method'],
                                    f"{service_url}{endpoint['url']}",
                                    timeout=aiohttp.ClientTimeout(total=30)
                                ) as response:
                                    end_time = time.time()
                                    response_time = (end_time - start_time) * 1000  # Convert to ms
                                    
                                    response_times.append(response_time)
                                    status_codes.append(response.status)
                                    
                            except asyncio.TimeoutError:
                                response_times.append(30000)  # 30s timeout
                                status_codes.append(0)
                            except Exception as e:
                                logger.warning(f"Request failed for {service_url}{endpoint['url']}: {e}")
                                response_times.append(30000)
                                status_codes.append(0)
                                
                            await asyncio.sleep(0.1)  # Small delay between requests
                        
                        # Calculate statistics
                        if response_times:
                            service_results[endpoint['url']] = {
                                'avg_response_time_ms': statistics.mean(response_times),
                                'min_response_time_ms': min(response_times),
                                'max_response_time_ms': max(response_times),
                                'p95_response_time_ms': self._percentile(response_times, 95),
                                'p99_response_time_ms': self._percentile(response_times, 99),
                                'success_rate': len([s for s in status_codes if 200 <= s < 300]) / len(status_codes),
                                'status_codes': list(set(status_codes)),
                                'total_requests': len(response_times)
                            }
                        
                    except Exception as e:
                        logger.error(f"Failed to test {service_url}{endpoint['url']}: {e}")
                        service_results[endpoint['url']] = {'error': str(e)}
                
                performance_results[service_name] = service_results
        
        self.results['service_performance'] = performance_results
        
    async def analyze_resource_utilization(self):
        """Analyze system and container resource utilization"""
        logger.info("Analyzing resource utilization...")
        
        # System-wide resource usage
        system_resources = {
            'cpu_percent': psutil.cpu_percent(interval=5),
            'memory': psutil.virtual_memory()._asdict(),
            'disk': psutil.disk_usage('/')._asdict(),
            'network': psutil.net_io_counters()._asdict(),
            'processes': len(psutil.pids())
        }
        
        # Container resource usage
        container_resources = {}
        
        try:
            containers = self.docker_client.containers.list()
            for container in containers:
                if any(service in container.name for service in self.services.keys()):
                    try:
                        stats = container.stats(stream=False)
                        
                        # CPU usage calculation
                        cpu_usage = self._calculate_cpu_usage(stats)
                        
                        # Memory usage
                        memory_stats = stats['memory_stats']
                        memory_usage = memory_stats.get('usage', 0)
                        memory_limit = memory_stats.get('limit', 0)
                        memory_percent = (memory_usage / memory_limit * 100) if memory_limit > 0 else 0
                        
                        # Network usage
                        network_stats = stats.get('networks', {})
                        network_rx = sum(net['rx_bytes'] for net in network_stats.values())
                        network_tx = sum(net['tx_bytes'] for net in network_stats.values())
                        
                        container_resources[container.name] = {
                            'cpu_percent': cpu_usage,
                            'memory_usage_bytes': memory_usage,
                            'memory_limit_bytes': memory_limit,
                            'memory_percent': memory_percent,
                            'network_rx_bytes': network_rx,
                            'network_tx_bytes': network_tx,
                            'status': container.status
                        }
                        
                    except Exception as e:
                        logger.warning(f"Failed to get resource stats for {container.name}: {e}")
                        container_resources[container.name] = {'error': str(e)}
                        
        except Exception as e:
            logger.error(f"Failed to analyze container resources: {e}")
        
        self.results['resource_utilization'] = {
            'system': system_resources,
            'containers': container_resources,
            'timestamp': datetime.now().isoformat()
        }
        
    async def analyze_database_performance(self):
        """Analyze PostgreSQL database performance"""
        logger.info("Analyzing database performance...")
        
        # Try to connect to PostgreSQL and get performance metrics
        try:
            # This would need actual database credentials
            # For now, we'll simulate or use Docker stats for postgres container
            postgres_container = None
            
            containers = self.docker_client.containers.list()
            for container in containers:
                if 'postgres' in container.name.lower():
                    postgres_container = container
                    break
            
            if postgres_container:
                stats = postgres_container.stats(stream=False)
                
                # Basic container stats for database
                database_stats = {
                    'container_name': postgres_container.name,
                    'status': postgres_container.status,
                    'cpu_usage': self._calculate_cpu_usage(stats),
                    'memory_usage': stats['memory_stats'].get('usage', 0),
                    'memory_limit': stats['memory_stats'].get('limit', 0),
                    'disk_io': stats.get('blkio_stats', {}),
                    'uptime': datetime.now().isoformat()
                }
                
                # Additional analysis would require database connection
                database_stats['notes'] = 'Detailed query analysis requires database connection'
                
                self.results['database_performance'] = database_stats
            else:
                self.results['database_performance'] = {'error': 'PostgreSQL container not found'}
                
        except Exception as e:
            logger.error(f"Failed to analyze database performance: {e}")
            self.results['database_performance'] = {'error': str(e)}
    
    async def analyze_cache_performance(self):
        """Analyze Redis cache performance"""
        logger.info("Analyzing cache performance...")
        
        try:
            redis_container = None
            
            containers = self.docker_client.containers.list()
            for container in containers:
                if 'redis' in container.name.lower():
                    redis_container = container
                    break
            
            if redis_container:
                stats = redis_container.stats(stream=False)
                
                cache_stats = {
                    'container_name': redis_container.name,
                    'status': redis_container.status,
                    'cpu_usage': self._calculate_cpu_usage(stats),
                    'memory_usage': stats['memory_stats'].get('usage', 0),
                    'memory_limit': stats['memory_stats'].get('limit', 0),
                    'network_io': stats.get('networks', {}),
                    'uptime': datetime.now().isoformat()
                }
                
                # Additional Redis-specific metrics would require Redis connection
                cache_stats['notes'] = 'Detailed Redis metrics require direct connection'
                
                self.results['cache_performance'] = cache_stats
            else:
                self.results['cache_performance'] = {'error': 'Redis container not found'}
                
        except Exception as e:
            logger.error(f"Failed to analyze cache performance: {e}")
            self.results['cache_performance'] = {'error': str(e)}
    
    async def analyze_network_performance(self):
        """Analyze network performance between services"""
        logger.info("Analyzing network performance...")
        
        network_stats = {
            'system_network': psutil.net_io_counters()._asdict(),
            'network_connections': len(psutil.net_connections()),
            'inter_service_latency': {}
        }
        
        # Test inter-service communication latency
        async with aiohttp.ClientSession() as session:
            for service_name, service_url in self.services.items():
                if service_name == 'frontend':
                    continue
                    
                try:
                    latencies = []
                    for _ in range(5):  # 5 requests per service
                        start_time = time.time()
                        try:
                            async with session.get(
                                f"{service_url}/health",
                                timeout=aiohttp.ClientTimeout(total=10)
                            ) as response:
                                end_time = time.time()
                                latency = (end_time - start_time) * 1000
                                latencies.append(latency)
                        except:
                            latencies.append(10000)  # 10s timeout
                        
                        await asyncio.sleep(0.1)
                    
                    if latencies:
                        network_stats['inter_service_latency'][service_name] = {
                            'avg_latency_ms': statistics.mean(latencies),
                            'min_latency_ms': min(latencies),
                            'max_latency_ms': max(latencies)
                        }
                        
                except Exception as e:
                    logger.warning(f"Failed to test network latency for {service_name}: {e}")
        
        self.results['network_performance'] = network_stats
    
    async def generate_recommendations(self):
        """Generate performance optimization recommendations"""
        logger.info("Generating performance recommendations...")
        
        recommendations = []
        
        # Analyze API performance
        if 'service_performance' in self.results:
            for service, endpoints in self.results['service_performance'].items():
                for endpoint, metrics in endpoints.items():
                    if isinstance(metrics, dict) and 'avg_response_time_ms' in metrics:
                        if metrics['avg_response_time_ms'] > 200:  # Target: <200ms
                            recommendations.append({
                                'type': 'API_PERFORMANCE',
                                'severity': 'HIGH' if metrics['avg_response_time_ms'] > 1000 else 'MEDIUM',
                                'service': service,
                                'endpoint': endpoint,
                                'issue': f"High response time: {metrics['avg_response_time_ms']:.1f}ms",
                                'recommendation': 'Implement caching, optimize database queries, or add connection pooling'
                            })
        
        # Analyze resource utilization
        if 'resource_utilization' in self.results:
            system = self.results['resource_utilization'].get('system', {})
            
            if system.get('cpu_percent', 0) > 80:
                recommendations.append({
                    'type': 'RESOURCE_UTILIZATION',
                    'severity': 'HIGH',
                    'issue': f"High CPU usage: {system.get('cpu_percent', 0):.1f}%",
                    'recommendation': 'Optimize CPU-intensive operations, implement async processing, or scale horizontally'
                })
            
            memory = system.get('memory', {})
            if memory.get('percent', 0) > 80:
                recommendations.append({
                    'type': 'RESOURCE_UTILIZATION',
                    'severity': 'HIGH',
                    'issue': f"High memory usage: {memory.get('percent', 0):.1f}%",
                    'recommendation': 'Implement memory optimization, garbage collection tuning, or increase memory allocation'
                })
        
        # Analyze container resources
        if 'resource_utilization' in self.results and 'containers' in self.results['resource_utilization']:
            for container, stats in self.results['resource_utilization']['containers'].items():
                if isinstance(stats, dict) and 'memory_percent' in stats:
                    if stats['memory_percent'] > 80:
                        recommendations.append({
                            'type': 'CONTAINER_RESOURCES',
                            'severity': 'MEDIUM',
                            'container': container,
                            'issue': f"High container memory usage: {stats['memory_percent']:.1f}%",
                            'recommendation': 'Increase container memory limits or optimize application memory usage'
                        })
        
        # Network performance recommendations
        if 'network_performance' in self.results and 'inter_service_latency' in self.results['network_performance']:
            for service, latency in self.results['network_performance']['inter_service_latency'].items():
                if latency.get('avg_latency_ms', 0) > 50:  # >50ms inter-service latency
                    recommendations.append({
                        'type': 'NETWORK_PERFORMANCE',
                        'severity': 'MEDIUM',
                        'service': service,
                        'issue': f"High inter-service latency: {latency.get('avg_latency_ms', 0):.1f}ms",
                        'recommendation': 'Optimize network configuration, implement service mesh, or use connection pooling'
                    })
        
        self.results['recommendations'] = recommendations
        logger.info(f"Generated {len(recommendations)} performance recommendations")
    
    async def save_results(self):
        """Save analysis results to files"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save JSON results
        json_filename = f"performance-baseline-{timestamp}.json"
        with open(json_filename, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        
        # Save SQLite database for historical tracking
        db_filename = "performance-baseline.db"
        self._save_to_database(db_filename)
        
        # Generate summary report
        report_filename = f"performance-baseline-report-{timestamp}.md"
        self._generate_summary_report(report_filename)
        
        logger.info(f"Results saved to {json_filename}, {db_filename}, and {report_filename}")
    
    def _save_to_database(self, db_filename):
        """Save results to SQLite database for historical tracking"""
        conn = sqlite3.connect(db_filename)
        cursor = conn.cursor()
        
        # Create tables if they don't exist
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS performance_runs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT,
                results TEXT
            )
        ''')
        
        # Insert current results
        cursor.execute(
            'INSERT INTO performance_runs (timestamp, results) VALUES (?, ?)',
            (self.results['timestamp'], json.dumps(self.results, default=str))
        )
        
        conn.commit()
        conn.close()
    
    def _generate_summary_report(self, filename):
        """Generate human-readable summary report"""
        with open(filename, 'w') as f:
            f.write("# PyAirtable Performance Baseline Report\n\n")
            f.write(f"**Generated:** {self.results['timestamp']}\n\n")
            
            # System Information
            f.write("## System Information\n\n")
            if 'system_info' in self.results:
                sys_info = self.results['system_info']
                f.write(f"- **CPU Cores:** {sys_info.get('cpu', {}).get('logical_cores', 'N/A')}\n")
                f.write(f"- **Memory:** {sys_info.get('memory', {}).get('total', 0) / (1024**3):.1f} GB\n")
                f.write(f"- **Architecture:** {sys_info.get('cpu', {}).get('architecture', 'N/A')}\n")
                f.write(f"- **Docker Containers:** {sys_info.get('docker', {}).get('containers_running', 0)}\n\n")
            
            # Performance Summary
            f.write("## Performance Summary\n\n")
            if 'service_performance' in self.results:
                f.write("### API Response Times\n\n")
                for service, endpoints in self.results['service_performance'].items():
                    f.write(f"**{service}:**\n")
                    for endpoint, metrics in endpoints.items():
                        if isinstance(metrics, dict) and 'avg_response_time_ms' in metrics:
                            f.write(f"- {endpoint}: {metrics['avg_response_time_ms']:.1f}ms avg, "
                                   f"{metrics['p95_response_time_ms']:.1f}ms p95\n")
                    f.write("\n")
            
            # Resource Utilization
            f.write("## Resource Utilization\n\n")
            if 'resource_utilization' in self.results:
                system = self.results['resource_utilization'].get('system', {})
                f.write(f"- **CPU Usage:** {system.get('cpu_percent', 0):.1f}%\n")
                f.write(f"- **Memory Usage:** {system.get('memory', {}).get('percent', 0):.1f}%\n")
                f.write(f"- **Disk Usage:** {system.get('disk', {}).get('percent', 0):.1f}%\n\n")
            
            # Recommendations
            f.write("## Recommendations\n\n")
            if 'recommendations' in self.results:
                high_priority = [r for r in self.results['recommendations'] if r.get('severity') == 'HIGH']
                medium_priority = [r for r in self.results['recommendations'] if r.get('severity') == 'MEDIUM']
                
                if high_priority:
                    f.write("### High Priority\n\n")
                    for rec in high_priority:
                        f.write(f"- **{rec.get('type', 'UNKNOWN')}**: {rec.get('issue', 'N/A')}\n")
                        f.write(f"  - *Recommendation*: {rec.get('recommendation', 'N/A')}\n\n")
                
                if medium_priority:
                    f.write("### Medium Priority\n\n")
                    for rec in medium_priority:
                        f.write(f"- **{rec.get('type', 'UNKNOWN')}**: {rec.get('issue', 'N/A')}\n")
                        f.write(f"  - *Recommendation*: {rec.get('recommendation', 'N/A')}\n\n")
    
    def _calculate_cpu_usage(self, stats):
        """Calculate CPU usage percentage from Docker stats"""
        try:
            cpu_stats = stats['cpu_stats']
            precpu_stats = stats['precpu_stats']
            
            cpu_delta = cpu_stats['cpu_usage']['total_usage'] - precpu_stats['cpu_usage']['total_usage']
            system_delta = cpu_stats['system_cpu_usage'] - precpu_stats['system_cpu_usage']
            
            if system_delta > 0 and cpu_delta > 0:
                cpu_usage = (cpu_delta / system_delta) * len(cpu_stats['cpu_usage']['percpu_usage']) * 100
                return round(cpu_usage, 2)
        except:
            pass
        return 0
    
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
            upper = sorted_data[int(index) + 1]
            return lower + (upper - lower) * (index - int(index))

async def main():
    """Main function to run performance analysis"""
    analyzer = PerformanceAnalyzer()
    await analyzer.run_complete_analysis()

if __name__ == "__main__":
    asyncio.run(main())