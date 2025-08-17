#!/usr/bin/env python3
"""
Auth Monitor Service - Tests authentication every 60 seconds and reports to Prometheus
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime
from typing import Dict, Any

import httpx
import prometheus_client
from prometheus_client import Counter, Gauge, Histogram, start_http_server

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
auth_attempts_total = Counter(
    'auth_attempts_total',
    'Total number of authentication attempts',
    ['service', 'status']
)

auth_success_gauge = Gauge(
    'auth_success_status',
    'Current authentication status (1=success, 0=failure)',
    ['service']
)

auth_response_time = Histogram(
    'auth_response_time_seconds',
    'Authentication response time in seconds',
    ['service']
)

auth_last_success_timestamp = Gauge(
    'auth_last_success_timestamp',
    'Timestamp of last successful authentication',
    ['service']
)

auth_consecutive_failures = Gauge(
    'auth_consecutive_failures',
    'Number of consecutive authentication failures',
    ['service']
)

class AuthMonitor:
    def __init__(self):
        self.services = {
            'platform-services': 'http://localhost:8007',
            'api-gateway': 'http://localhost:8000',
            'airtable-gateway': 'http://localhost:8002'
        }
        self.consecutive_failures = {service: 0 for service in self.services}
        self.last_success = {service: 0 for service in self.services}
        
    async def test_auth_endpoint(self, service_name: str, base_url: str) -> Dict[str, Any]:
        """Test authentication endpoint for a specific service"""
        start_time = time.time()
        
        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                # Test health endpoint first
                health_response = await client.get(f"{base_url}/health")
                
                if health_response.status_code != 200:
                    raise httpx.HTTPError(f"Health check failed: {health_response.status_code}")
                
                # Test auth endpoint based on service
                if service_name == 'platform-services':
                    # Test login endpoint
                    auth_data = {
                        "email": os.getenv("TEST_USER_EMAIL", "test@example.com"),
                        "password": os.getenv("TEST_USER_PASSWORD", "change_me_in_env")
                    }
                    response = await client.post(f"{base_url}/api/auth/login", json=auth_data)
                    
                elif service_name == 'api-gateway':
                    # Test protected endpoint without auth (should return 401)
                    response = await client.get(f"{base_url}/api/user/profile")
                    # 401 is expected for this test
                    if response.status_code == 401:
                        response.status_code = 200  # Mark as success since 401 is expected
                        
                elif service_name == 'airtable-gateway':
                    # Test auth validation endpoint
                    headers = {"Authorization": "Bearer invalid-token"}
                    response = await client.get(f"{base_url}/api/validate", headers=headers)
                    # 401 is expected for invalid token
                    if response.status_code == 401:
                        response.status_code = 200  # Mark as success since 401 is expected
                
                response_time = time.time() - start_time
                
                # Record metrics
                auth_response_time.labels(service=service_name).observe(response_time)
                
                if response.status_code in [200, 201]:
                    # Success
                    auth_attempts_total.labels(service=service_name, status='success').inc()
                    auth_success_gauge.labels(service=service_name).set(1)
                    auth_last_success_timestamp.labels(service=service_name).set(time.time())
                    self.consecutive_failures[service_name] = 0
                    self.last_success[service_name] = time.time()
                    
                    return {
                        'service': service_name,
                        'status': 'success',
                        'response_time': response_time,
                        'status_code': response.status_code,
                        'timestamp': datetime.now().isoformat()
                    }
                else:
                    # Failure
                    auth_attempts_total.labels(service=service_name, status='failure').inc()
                    auth_success_gauge.labels(service=service_name).set(0)
                    self.consecutive_failures[service_name] += 1
                    
                    return {
                        'service': service_name,
                        'status': 'failure',
                        'response_time': response_time,
                        'status_code': response.status_code,
                        'error': f"HTTP {response.status_code}",
                        'timestamp': datetime.now().isoformat()
                    }
                    
            except Exception as e:
                response_time = time.time() - start_time
                
                # Record error metrics
                auth_attempts_total.labels(service=service_name, status='error').inc()
                auth_success_gauge.labels(service=service_name).set(0)
                self.consecutive_failures[service_name] += 1
                auth_response_time.labels(service=service_name).observe(response_time)
                
                return {
                    'service': service_name,
                    'status': 'error',
                    'response_time': response_time,
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                }
            finally:
                # Update consecutive failures metric
                auth_consecutive_failures.labels(service=service_name).set(
                    self.consecutive_failures[service_name]
                )
    
    async def run_monitoring_cycle(self):
        """Run one complete monitoring cycle for all services"""
        logger.info("Starting authentication monitoring cycle")
        
        tasks = []
        for service_name, base_url in self.services.items():
            task = self.test_auth_endpoint(service_name, base_url)
            tasks.append(task)
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Log results
        for result in results:
            if isinstance(result, Exception):
                logger.error(f"Monitoring task failed: {result}")
            else:
                status = result.get('status', 'unknown')
                service = result.get('service', 'unknown')
                response_time = result.get('response_time', 0)
                
                if status == 'success':
                    logger.info(f"✅ {service}: {status} ({response_time:.3f}s)")
                else:
                    error = result.get('error', 'Unknown error')
                    logger.warning(f"❌ {service}: {status} - {error} ({response_time:.3f}s)")
        
        return results
    
    async def start_monitoring(self, interval: int = 60):
        """Start continuous monitoring with specified interval"""
        logger.info(f"Starting auth monitor service (interval: {interval}s)")
        
        while True:
            try:
                await self.run_monitoring_cycle()
                await asyncio.sleep(interval)
            except Exception as e:
                logger.error(f"Monitoring cycle failed: {e}")
                await asyncio.sleep(10)  # Short delay before retry

async def main():
    # Start Prometheus metrics server
    start_http_server(8090)
    logger.info("Prometheus metrics server started on port 8090")
    
    # Initialize and start monitoring
    monitor = AuthMonitor()
    await monitor.start_monitoring(interval=60)

if __name__ == "__main__":
    asyncio.run(main())