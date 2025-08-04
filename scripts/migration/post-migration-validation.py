#!/usr/bin/env python3
"""
PyAirtable Post-Migration Validation Suite
==========================================

Comprehensive validation suite for post-migration verification including:
- Performance baseline validation
- Security audit verification
- Backup system validation
- Monitoring system validation
- Data consistency checks
- Service integration tests
"""

import asyncio
import aiohttp
import time
import json
import logging
import subprocess
import psutil
import boto3
import redis
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass
import yaml
import statistics

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class ValidationConfig:
    """Validation configuration"""
    api_base_url: str
    api_key: str
    database_url: str
    redis_url: str
    aws_region: str
    cluster_name: str
    performance_thresholds: Dict[str, float]
    monitoring_endpoints: Dict[str, str]
    
    @classmethod
    def from_file(cls, config_path: str) -> 'ValidationConfig':
        with open(config_path, 'r') as f:
            config_data = yaml.safe_load(f)
        return cls(**config_data)

@dataclass
class ValidationResult:
    """Validation result container"""
    test_name: str
    status: str  # PASS, FAIL, WARNING
    details: str
    metrics: Dict[str, Any]
    timestamp: datetime
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'test_name': self.test_name,
            'status': self.status,
            'details': self.details,
            'metrics': self.metrics,
            'timestamp': self.timestamp.isoformat()
        }

class PostMigrationValidator:
    """Main post-migration validation orchestrator"""
    
    def __init__(self, config: ValidationConfig):
        self.config = config
        self.results: List[ValidationResult] = []
        self.aws_clients = {
            'cloudwatch': boto3.client('cloudwatch', region_name=config.aws_region),
            'rds': boto3.client('rds', region_name=config.aws_region),
            'elbv2': boto3.client('elbv2', region_name=config.aws_region),
            'eks': boto3.client('eks', region_name=config.aws_region)
        }
    
    async def run_all_validations(self) -> Dict[str, Any]:
        """Run all post-migration validations"""
        logger.info("🚀 Starting post-migration validation suite")
        
        validation_suites = [
            ("Performance Baseline", self.validate_performance_baseline),
            ("Security Configuration", self.validate_security_configuration),
            ("Backup Systems", self.validate_backup_systems),
            ("Monitoring & Alerting", self.validate_monitoring_alerting),
            ("Data Consistency", self.validate_data_consistency),
            ("Service Integration", self.validate_service_integration),
            ("Infrastructure Health", self.validate_infrastructure_health),
            ("Disaster Recovery", self.validate_disaster_recovery),
        ]
        
        for suite_name, validation_func in validation_suites:
            logger.info(f"Running {suite_name} validation...")
            try:
                await validation_func()
                logger.info(f"✅ {suite_name} validation completed")
            except Exception as e:
                logger.error(f"❌ {suite_name} validation failed: {e}")
                self.results.append(ValidationResult(
                    test_name=suite_name,
                    status="FAIL",
                    details=f"Validation failed with exception: {e}",
                    metrics={},
                    timestamp=datetime.now(timezone.utc)
                ))
        
        return self.generate_validation_report()
    
    async def validate_performance_baseline(self):
        """Validate performance against baseline metrics"""
        logger.info("Validating performance baseline...")
        
        # API Response Time Tests
        await self.test_api_response_times()
        
        # Database Performance Tests
        await self.test_database_performance()
        
        # Cache Performance Tests
        await self.test_cache_performance()
        
        # Load Testing
        await self.run_load_tests()
    
    async def test_api_response_times(self):
        """Test API response times against thresholds"""
        endpoints = [
            ('/health', 'GET'),
            ('/api/v1/auth/validate', 'GET'),
            ('/api/v1/users/profile', 'GET'),
            ('/api/v1/workspaces', 'GET'),
            ('/api/v1/airtable/bases', 'GET'),
        ]
        
        response_times = []
        
        async with aiohttp.ClientSession() as session:
            for endpoint, method in endpoints:
                times = []
                
                # Run 10 requests per endpoint
                for _ in range(10):
                    start_time = time.time()
                    
                    headers = {'Authorization': f'Bearer {self.config.api_key}'}
                    
                    try:
                        async with session.request(
                            method, 
                            f"{self.config.api_base_url}{endpoint}",
                            headers=headers
                        ) as response:
                            await response.read()
                            end_time = time.time()
                            times.append((end_time - start_time) * 1000)  # Convert to ms
                    except Exception as e:
                        logger.warning(f"Request failed for {endpoint}: {e}")
                        times.append(float('inf'))
                
                avg_time = statistics.mean(times) if times else float('inf')
                p95_time = statistics.quantiles(times, n=20)[18] if len(times) >= 5 else avg_time
                
                response_times.append({
                    'endpoint': endpoint,
                    'avg_ms': avg_time,
                    'p95_ms': p95_time,
                    'samples': len(times)
                })
        
        # Validate against thresholds
        threshold = self.config.performance_thresholds.get('api_response_time_ms', 500)
        failed_endpoints = []
        
        for rt in response_times:
            if rt['p95_ms'] > threshold:
                failed_endpoints.append(f"{rt['endpoint']}: {rt['p95_ms']:.2f}ms > {threshold}ms")
        
        status = "PASS" if not failed_endpoints else "FAIL"
        details = f"API response times validated. Failed: {len(failed_endpoints)}"
        
        self.results.append(ValidationResult(
            test_name="API Response Times",
            status=status,
            details=details,
            metrics={'response_times': response_times, 'failures': failed_endpoints},
            timestamp=datetime.now(timezone.utc)
        ))
    
    async def test_database_performance(self):
        """Test database performance metrics"""
        import asyncpg
        
        try:
            conn = await asyncpg.connect(self.config.database_url)
            
            # Test query performance
            test_queries = [
                ("SELECT COUNT(*) FROM users", "user_count"),
                ("SELECT COUNT(*) FROM workspaces", "workspace_count"),
                ("SELECT COUNT(*) FROM events ORDER BY created_at DESC LIMIT 1000", "recent_events"),
            ]
            
            query_times = {}
            
            for query, query_name in test_queries:
                start_time = time.time()
                await conn.fetchval(query)
                query_times[query_name] = (time.time() - start_time) * 1000
            
            # Test connection pool performance
            pool_start = time.time()
            pool = await asyncpg.create_pool(
                self.config.database_url,
                min_size=1,
                max_size=10
            )
            pool_creation_time = (time.time() - pool_start) * 1000
            
            await pool.close()
            await conn.close()
            
            # Validate against thresholds
            db_threshold = self.config.performance_thresholds.get('db_query_time_ms', 100)
            slow_queries = []
            
            for query_name, query_time in query_times.items():
                if query_time > db_threshold:
                    slow_queries.append(f"{query_name}: {query_time:.2f}ms > {db_threshold}ms")
            
            status = "PASS" if not slow_queries else "WARNING"
            details = f"Database performance validated. Slow queries: {len(slow_queries)}"
            
            self.results.append(ValidationResult(
                test_name="Database Performance",
                status=status,
                details=details,
                metrics={
                    'query_times': query_times,
                    'pool_creation_time_ms': pool_creation_time,
                    'slow_queries': slow_queries
                },
                timestamp=datetime.now(timezone.utc)
            ))
            
        except Exception as e:
            self.results.append(ValidationResult(
                test_name="Database Performance",
                status="FAIL",
                details=f"Database performance test failed: {e}",
                metrics={},
                timestamp=datetime.now(timezone.utc)
            ))
    
    async def test_cache_performance(self):
        """Test Redis cache performance"""
        try:
            redis_client = redis.from_url(self.config.redis_url)
            
            # Test basic operations
            operations = {
                'set': lambda: redis_client.set('test_key', 'test_value'),
                'get': lambda: redis_client.get('test_key'),
                'delete': lambda: redis_client.delete('test_key'),
                'ping': lambda: redis_client.ping()
            }
            
            operation_times = {}
            
            for op_name, operation in operations.items():
                times = []
                for _ in range(100):  # Run 100 times for better average
                    start_time = time.time()
                    operation()
                    times.append((time.time() - start_time) * 1000)
                
                operation_times[op_name] = {
                    'avg_ms': statistics.mean(times),
                    'p95_ms': statistics.quantiles(times, n=20)[18] if len(times) >= 5 else statistics.mean(times)
                }
            
            # Test connection info
            info = redis_client.info()
            
            redis_client.close()
            
            # Validate performance
            cache_threshold = self.config.performance_thresholds.get('cache_operation_time_ms', 10)
            slow_operations = []
            
            for op_name, metrics in operation_times.items():
                if metrics['p95_ms'] > cache_threshold:
                    slow_operations.append(f"{op_name}: {metrics['p95_ms']:.2f}ms > {cache_threshold}ms")
            
            status = "PASS" if not slow_operations else "WARNING"
            details = f"Cache performance validated. Slow operations: {len(slow_operations)}"
            
            self.results.append(ValidationResult(
                test_name="Cache Performance",
                status=status,
                details=details,
                metrics={
                    'operation_times': operation_times,
                    'redis_info': {
                        'connected_clients': info.get('connected_clients'),
                        'used_memory_human': info.get('used_memory_human'),
                        'keyspace_hits': info.get('keyspace_hits'),
                        'keyspace_misses': info.get('keyspace_misses')
                    },
                    'slow_operations': slow_operations
                },
                timestamp=datetime.now(timezone.utc)
            ))
            
        except Exception as e:
            self.results.append(ValidationResult(
                test_name="Cache Performance",
                status="FAIL",
                details=f"Cache performance test failed: {e}",
                metrics={},
                timestamp=datetime.now(timezone.utc)
            ))
    
    async def run_load_tests(self):
        """Run load tests using k6 or similar tools"""
        try:
            # Run k6 load test if available
            k6_script = f"""
            import http from 'k6/http';
            import {{ check }} from 'k6';
            
            export let options = {{
                vus: 50,
                duration: '2m',
            }};
            
            export default function () {{
                let response = http.get('{self.config.api_base_url}/health');
                check(response, {{
                    'status is 200': (r) => r.status === 200,
                    'response time < 500ms': (r) => r.timings.duration < 500,
                }});
            }}
            """
            
            # Write k6 script to temp file
            with open('/tmp/load_test.js', 'w') as f:
                f.write(k6_script)
            
            # Run k6 if available
            try:
                result = subprocess.run([
                    'k6', 'run', '--out', 'json=/tmp/k6_results.json', '/tmp/load_test.js'
                ], capture_output=True, text=True, timeout=180)
                
                if result.returncode == 0:
                    # Parse k6 results
                    with open('/tmp/k6_results.json', 'r') as f:
                        k6_results = [json.loads(line) for line in f if line.strip()]
                    
                    # Extract metrics
                    metrics = self.parse_k6_results(k6_results)
                    
                    # Validate load test results
                    error_rate = metrics.get('error_rate', 0)
                    avg_response_time = metrics.get('avg_response_time', 0)
                    
                    error_threshold = self.config.performance_thresholds.get('load_test_error_rate', 0.01)
                    response_threshold = self.config.performance_thresholds.get('load_test_response_time_ms', 1000)
                    
                    issues = []
                    if error_rate > error_threshold:
                        issues.append(f"Error rate too high: {error_rate:.2%} > {error_threshold:.2%}")
                    if avg_response_time > response_threshold:
                        issues.append(f"Response time too high: {avg_response_time:.2f}ms > {response_threshold}ms")
                    
                    status = "PASS" if not issues else "FAIL"
                    details = f"Load test completed. Issues: {len(issues)}"
                    
                    self.results.append(ValidationResult(
                        test_name="Load Testing",
                        status=status,
                        details=details,
                        metrics={'k6_metrics': metrics, 'issues': issues},
                        timestamp=datetime.now(timezone.utc)
                    ))
                else:
                    raise Exception(f"k6 failed: {result.stderr}")
                    
            except FileNotFoundError:
                logger.warning("k6 not available, skipping load tests")
                self.results.append(ValidationResult(
                    test_name="Load Testing",
                    status="WARNING",
                    details="k6 load testing tool not available",
                    metrics={},
                    timestamp=datetime.now(timezone.utc)
                ))
            
        except Exception as e:
            self.results.append(ValidationResult(
                test_name="Load Testing",
                status="FAIL",
                details=f"Load test failed: {e}",
                metrics={},
                timestamp=datetime.now(timezone.utc)
            ))
    
    def parse_k6_results(self, k6_results: List[Dict]) -> Dict[str, Any]:
        """Parse k6 results into summary metrics"""
        http_reqs = [r for r in k6_results if r.get('metric') == 'http_reqs']
        http_req_duration = [r for r in k6_results if r.get('metric') == 'http_req_duration']
        http_req_failed = [r for r in k6_results if r.get('metric') == 'http_req_failed']
        
        total_requests = sum(r.get('value', 0) for r in http_reqs)
        failed_requests = sum(r.get('value', 0) for r in http_req_failed)
        
        durations = [r.get('value', 0) for r in http_req_duration]
        avg_duration = statistics.mean(durations) if durations else 0
        p95_duration = statistics.quantiles(durations, n=20)[18] if len(durations) >= 5 else avg_duration
        
        return {
            'total_requests': total_requests,
            'failed_requests': failed_requests,
            'error_rate': failed_requests / total_requests if total_requests > 0 else 0,
            'avg_response_time': avg_duration,
            'p95_response_time': p95_duration
        }
    
    async def validate_security_configuration(self):
        """Validate security configuration"""
        logger.info("Validating security configuration...")
        
        # Test SSL/TLS configuration
        await self.test_ssl_configuration()
        
        # Test authentication
        await self.test_authentication_security()
        
        # Test authorization
        await self.test_authorization_security()
        
        # Test network security
        await self.test_network_security()
    
    async def test_ssl_configuration(self):
        """Test SSL/TLS configuration"""
        try:
            import ssl
            import socket
            from urllib.parse import urlparse
            
            parsed_url = urlparse(self.config.api_base_url)
            hostname = parsed_url.hostname
            port = parsed_url.port or (443 if parsed_url.scheme == 'https' else 80)
            
            # Test SSL connection
            context = ssl.create_default_context()
            
            with socket.create_connection((hostname, port)) as sock:
                with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                    cert = ssock.getpeercert()
                    cipher = ssock.cipher()
                    version = ssock.version()
            
            # Validate certificate
            issues = []
            
            # Check expiration
            not_after = datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
            days_until_expiry = (not_after - datetime.now()).days
            
            if days_until_expiry < 30:
                issues.append(f"Certificate expires in {days_until_expiry} days")
            
            # Check cipher strength
            if cipher and cipher[1] < 256:
                issues.append(f"Weak cipher: {cipher[0]} ({cipher[1]} bits)")
                
            # Check TLS version
            if version and version < 'TLSv1.2':
                issues.append(f"Old TLS version: {version}")
            
            status = "PASS" if not issues else "WARNING"
            details = f"SSL configuration validated. Issues: {len(issues)}"
            
            self.results.append(ValidationResult(
                test_name="SSL Configuration",
                status=status,
                details=details,
                metrics={
                    'certificate': {
                        'subject': cert.get('subject'),
                        'issuer': cert.get('issuer'),
                        'not_after': cert.get('notAfter'),
                        'days_until_expiry': days_until_expiry
                    },
                    'cipher': cipher,
                    'tls_version': version,
                    'issues': issues
                },
                timestamp=datetime.now(timezone.utc)
            ))
            
        except Exception as e:
            self.results.append(ValidationResult(
                test_name="SSL Configuration",
                status="FAIL",
                details=f"SSL configuration test failed: {e}",
                metrics={},
                timestamp=datetime.now(timezone.utc)
            ))
    
    async def validate_backup_systems(self):
        """Validate backup systems"""
        logger.info("Validating backup systems...")
        
        # Test database backups
        await self.test_database_backups()
        
        # Test configuration backups
        await self.test_configuration_backups()
        
        # Test backup restoration procedures
        await self.test_backup_restoration()
    
    async def test_database_backups(self):
        """Test database backup systems"""
        try:
            # Check RDS automated backups
            db_clusters = self.aws_clients['rds'].describe_db_clusters()
            
            backup_issues = []
            backup_info = []
            
            for cluster in db_clusters['DBClusters']:
                if 'prod' in cluster['DBClusterIdentifier'].lower():
                    backup_retention = cluster.get('BackupRetentionPeriod', 0)
                    
                    if backup_retention < 7:
                        backup_issues.append(f"Short backup retention: {backup_retention} days")
                    
                    # Check recent backups
                    snapshots = self.aws_clients['rds'].describe_db_cluster_snapshots(
                        DBClusterIdentifier=cluster['DBClusterIdentifier'],
                        SnapshotType='automated',
                        MaxRecords=5
                    )
                    
                    recent_snapshots = [
                        s for s in snapshots['DBClusterSnapshots']
                        if (datetime.now(timezone.utc) - s['SnapshotCreateTime']).days <= 1
                    ]
                    
                    if not recent_snapshots:
                        backup_issues.append(f"No recent backups for {cluster['DBClusterIdentifier']}")
                    
                    backup_info.append({
                        'cluster': cluster['DBClusterIdentifier'],
                        'retention_days': backup_retention,
                        'recent_snapshots': len(recent_snapshots)
                    })
            
            status = "PASS" if not backup_issues else "FAIL"
            details = f"Database backup validation. Issues: {len(backup_issues)}"
            
            self.results.append(ValidationResult(
                test_name="Database Backups",
                status=status,
                details=details,
                metrics={'backup_info': backup_info, 'issues': backup_issues},
                timestamp=datetime.now(timezone.utc)
            ))
            
        except Exception as e:
            self.results.append(ValidationResult(
                test_name="Database Backups",
                status="FAIL",
                details=f"Database backup validation failed: {e}",
                metrics={},
                timestamp=datetime.now(timezone.utc)
            ))
    
    async def validate_monitoring_alerting(self):
        """Validate monitoring and alerting systems"""
        logger.info("Validating monitoring and alerting...")
        
        # Test monitoring endpoints
        await self.test_monitoring_endpoints()
        
        # Test alerting rules
        await self.test_alerting_rules()
        
        # Test log aggregation
        await self.test_log_aggregation()
    
    async def test_monitoring_endpoints(self):
        """Test monitoring system endpoints"""
        monitoring_tests = []
        
        async with aiohttp.ClientSession() as session:
            for endpoint_name, endpoint_url in self.config.monitoring_endpoints.items():
                try:
                    start_time = time.time()
                    async with session.get(endpoint_url, timeout=10) as response:
                        response_time = (time.time() - start_time) * 1000
                        
                        monitoring_tests.append({
                            'endpoint': endpoint_name,
                            'url': endpoint_url,
                            'status_code': response.status,
                            'response_time_ms': response_time,
                            'accessible': response.status == 200
                        })
                        
                except Exception as e:
                    monitoring_tests.append({
                        'endpoint': endpoint_name,
                        'url': endpoint_url,
                        'error': str(e),
                        'accessible': False
                    })
        
        failed_endpoints = [t for t in monitoring_tests if not t.get('accessible', False)]
        
        status = "PASS" if not failed_endpoints else "FAIL"
        details = f"Monitoring endpoints validated. Failed: {len(failed_endpoints)}"
        
        self.results.append(ValidationResult(
            test_name="Monitoring Endpoints",
            status=status,
            details=details,
            metrics={'tests': monitoring_tests, 'failed': failed_endpoints},
            timestamp=datetime.now(timezone.utc)
        ))
    
    def generate_validation_report(self) -> Dict[str, Any]:
        """Generate comprehensive validation report"""
        total_tests = len(self.results)
        passed_tests = len([r for r in self.results if r.status == "PASS"])
        failed_tests = len([r for r in self.results if r.status == "FAIL"])
        warning_tests = len([r for r in self.results if r.status == "WARNING"])
        
        overall_status = "PASS"
        if failed_tests > 0:
            overall_status = "FAIL"
        elif warning_tests > 0:
            overall_status = "WARNING"
        
        report = {
            'validation_summary': {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'overall_status': overall_status,
                'total_tests': total_tests,
                'passed_tests': passed_tests,
                'failed_tests': failed_tests,
                'warning_tests': warning_tests,
                'success_rate': (passed_tests / total_tests * 100) if total_tests > 0 else 0
            },
            'test_results': [result.to_dict() for result in self.results],
            'recommendations': self.generate_recommendations()
        }
        
        return report
    
    def generate_recommendations(self) -> List[str]:
        """Generate recommendations based on validation results"""
        recommendations = []
        
        failed_results = [r for r in self.results if r.status == "FAIL"]
        warning_results = [r for r in self.results if r.status == "WARNING"]
        
        if failed_results:
            recommendations.append("⚠️  Critical issues found - address failed tests before proceeding")
            
        if warning_results:
            recommendations.append("📋 Review warning tests and consider improvements")
            
        # Specific recommendations based on test results
        performance_issues = [r for r in self.results if "Performance" in r.test_name and r.status != "PASS"]
        if performance_issues:
            recommendations.append("🚀 Performance optimization needed - review slow queries and API responses")
            
        security_issues = [r for r in self.results if "Security" in r.test_name and r.status != "PASS"]
        if security_issues:
            recommendations.append("🔒 Security improvements needed - review SSL and authentication configuration")
            
        backup_issues = [r for r in self.results if "Backup" in r.test_name and r.status != "PASS"]
        if backup_issues:
            recommendations.append("💾 Backup system issues - ensure proper backup retention and testing")
            
        monitoring_issues = [r for r in self.results if "Monitoring" in r.test_name and r.status != "PASS"]
        if monitoring_issues:
            recommendations.append("📊 Monitoring system issues - verify alerting and dashboards")
        
        if not recommendations:
            recommendations.append("✅ All validations passed - system ready for production")
            
        return recommendations

async def main():
    """Main validation execution"""
    import argparse
    
    parser = argparse.ArgumentParser(description='PyAirtable Post-Migration Validation')
    parser.add_argument('--config', required=True, help='Validation configuration file')
    parser.add_argument('--output', default='validation_report.json', help='Output report file')
    
    args = parser.parse_args()
    
    # Load configuration
    config = ValidationConfig.from_file(args.config)
    
    # Run validation
    validator = PostMigrationValidator(config)
    report = await validator.run_all_validations()
    
    # Save report
    with open(args.output, 'w') as f:
        json.dump(report, f, indent=2)
    
    # Print summary
    summary = report['validation_summary']
    logger.info(f"""
📊 Post-Migration Validation Report
==================================
Overall Status: {summary['overall_status']}
Total Tests: {summary['total_tests']}
Passed: {summary['passed_tests']}
Failed: {summary['failed_tests']}
Warnings: {summary['warning_tests']}
Success Rate: {summary['success_rate']:.1f}%

Report saved to: {args.output}
    """)
    
    # Print recommendations
    if report['recommendations']:
        logger.info("📋 Recommendations:")
        for rec in report['recommendations']:
            logger.info(f"  {rec}")
    
    # Exit with appropriate code
    return 0 if summary['overall_status'] == "PASS" else 1

if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)