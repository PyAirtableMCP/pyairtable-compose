#!/usr/bin/env python3
"""
Emergency Stabilization Day 5: Health Check Monitoring
Real-time health monitoring for all PyAirtable services.
"""

import asyncio
import aiohttp
import json
import time
import logging
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
import argparse

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/tmp/health-monitor.log')
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class ServiceHealth:
    name: str
    url: str
    status: str  # UP, DOWN, DEGRADED
    response_time_ms: Optional[float]
    last_check: str
    error_message: Optional[str] = None
    status_code: Optional[int] = None

@dataclass
class HealthSummary:
    timestamp: str
    total_services: int
    healthy_services: int
    degraded_services: int
    failed_services: int
    services: List[ServiceHealth]

class HealthChecker:
    def __init__(self):
        # Service definitions based on docker-compose.yml
        self.services = {
            # Core Application Services
            'api-gateway': {
                'url': 'http://localhost:8000/api/health',
                'timeout': 5,
                'critical': True
            },
            'llm-orchestrator': {
                'url': 'http://localhost:8003/health',
                'timeout': 10,
                'critical': True
            },
            'mcp-server': {
                'url': 'http://localhost:8001/health',
                'timeout': 5,
                'critical': True
            },
            'airtable-gateway': {
                'url': 'http://localhost:8002/health',
                'timeout': 5,
                'critical': True
            },
            'platform-services': {
                'url': 'http://localhost:8007/health',
                'timeout': 5,
                'critical': True
            },
            'automation-services': {
                'url': 'http://localhost:8006/health',
                'timeout': 5,
                'critical': True
            },
            'saga-orchestrator': {
                'url': 'http://localhost:8008/health/',
                'timeout': 5,
                'critical': True
            },
            'frontend': {
                'url': 'http://localhost:3000/api/health',
                'timeout': 10,
                'critical': False  # Frontend less critical than backend
            },
            'frontend-ready': {
                'url': 'http://localhost:3000/health/ready',
                'timeout': 10,
                'critical': False
            }
        }
        
        # Response time thresholds (milliseconds)
        self.thresholds = {
            'healthy': 1000,    # < 1s = healthy
            'degraded': 5000,   # 1-5s = degraded
            # > 5s = down
        }
        
        self.session: Optional[aiohttp.ClientSession] = None
    
    async def __aenter__(self):
        """Async context manager entry"""
        connector = aiohttp.TCPConnector(limit=10, limit_per_host=5)
        self.session = aiohttp.ClientSession(
            connector=connector,
            timeout=aiohttp.ClientTimeout(total=30)
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        if self.session:
            await self.session.close()

    async def check_service_health(self, name: str, config: Dict) -> ServiceHealth:
        """Check health of a single service"""
        url = config['url']
        timeout = config.get('timeout', 5)
        
        start_time = time.time()
        
        try:
            async with self.session.get(
                url,
                timeout=aiohttp.ClientTimeout(total=timeout)
            ) as response:
                response_time_ms = (time.time() - start_time) * 1000
                
                # Determine status based on HTTP code and response time
                if response.status == 200:
                    if response_time_ms < self.thresholds['healthy']:
                        status = "UP"
                    elif response_time_ms < self.thresholds['degraded']:
                        status = "DEGRADED"
                    else:
                        status = "DOWN"
                else:
                    status = "DOWN"
                
                # Try to get response text for additional info
                try:
                    response_text = await response.text()
                    error_message = None if status == "UP" else f"HTTP {response.status}: {response_text[:200]}"
                except:
                    error_message = None if status == "UP" else f"HTTP {response.status}"
                
                return ServiceHealth(
                    name=name,
                    url=url,
                    status=status,
                    response_time_ms=round(response_time_ms, 2),
                    last_check=datetime.now().isoformat(),
                    error_message=error_message,
                    status_code=response.status
                )
                
        except asyncio.TimeoutError:
            response_time_ms = (time.time() - start_time) * 1000
            return ServiceHealth(
                name=name,
                url=url,
                status="DOWN",
                response_time_ms=round(response_time_ms, 2),
                last_check=datetime.now().isoformat(),
                error_message=f"Timeout after {timeout}s",
                status_code=None
            )
            
        except Exception as e:
            response_time_ms = (time.time() - start_time) * 1000
            return ServiceHealth(
                name=name,
                url=url,
                status="DOWN",
                response_time_ms=round(response_time_ms, 2),
                last_check=datetime.now().isoformat(),
                error_message=str(e),
                status_code=None
            )

    async def check_all_services(self) -> HealthSummary:
        """Check health of all services concurrently"""
        logger.info("Starting health check for all services...")
        
        # Create tasks for all service health checks
        tasks = []
        for name, config in self.services.items():
            task = self.check_service_health(name, config)
            tasks.append(task)
        
        # Execute all checks concurrently
        service_healths = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Filter out exceptions and convert to ServiceHealth objects
        valid_healths = []
        for i, health in enumerate(service_healths):
            if isinstance(health, Exception):
                service_name = list(self.services.keys())[i]
                logger.error(f"Failed to check {service_name}: {health}")
                # Create a DOWN service health for failed checks
                valid_healths.append(ServiceHealth(
                    name=service_name,
                    url=self.services[service_name]['url'],
                    status="DOWN",
                    response_time_ms=None,
                    last_check=datetime.now().isoformat(),
                    error_message=f"Check failed: {str(health)}"
                ))
            else:
                valid_healths.append(health)
        
        # Calculate summary statistics
        healthy_count = sum(1 for h in valid_healths if h.status == "UP")
        degraded_count = sum(1 for h in valid_healths if h.status == "DEGRADED")
        failed_count = sum(1 for h in valid_healths if h.status == "DOWN")
        
        summary = HealthSummary(
            timestamp=datetime.now().isoformat(),
            total_services=len(valid_healths),
            healthy_services=healthy_count,
            degraded_services=degraded_count,
            failed_services=failed_count,
            services=valid_healths
        )
        
        logger.info(f"Health check complete: {healthy_count}/{len(valid_healths)} services healthy")
        return summary

    def save_results(self, summary: HealthSummary, output_file: str = '/tmp/health-status.json'):
        """Save health check results to JSON file"""
        try:
            with open(output_file, 'w') as f:
                json.dump(asdict(summary), f, indent=2, default=str)
            logger.info(f"Health status saved to {output_file}")
        except Exception as e:
            logger.error(f"Failed to save health status: {e}")

    def print_summary(self, summary: HealthSummary):
        """Print human-readable summary to console"""
        print(f"\n{'='*60}")
        print(f"PyAirtable Service Health Status")
        print(f"{'='*60}")
        print(f"Timestamp: {summary.timestamp}")
        print(f"Total Services: {summary.total_services}")
        print(f"✅ Healthy: {summary.healthy_services}")
        print(f"⚠️  Degraded: {summary.degraded_services}")
        print(f"❌ Failed: {summary.failed_services}")
        print(f"{'='*60}")
        
        # Group services by status for better readability
        up_services = [s for s in summary.services if s.status == "UP"]
        degraded_services = [s for s in summary.services if s.status == "DEGRADED"]
        down_services = [s for s in summary.services if s.status == "DOWN"]
        
        if up_services:
            print(f"\n✅ HEALTHY SERVICES ({len(up_services)}):")
            for service in up_services:
                print(f"  • {service.name:<20} {service.response_time_ms:>6.1f}ms")
        
        if degraded_services:
            print(f"\n⚠️  DEGRADED SERVICES ({len(degraded_services)}):")
            for service in degraded_services:
                print(f"  • {service.name:<20} {service.response_time_ms:>6.1f}ms")
                if service.error_message:
                    print(f"    └─ {service.error_message}")
        
        if down_services:
            print(f"\n❌ FAILED SERVICES ({len(down_services)}):")
            for service in down_services:
                rt = f"{service.response_time_ms:.1f}ms" if service.response_time_ms else "N/A"
                print(f"  • {service.name:<20} {rt:>6}")
                if service.error_message:
                    print(f"    └─ {service.error_message}")
        
        print(f"\n{'='*60}")

async def run_single_check():
    """Run a single health check"""
    async with HealthChecker() as checker:
        summary = await checker.check_all_services()
        checker.save_results(summary)
        checker.print_summary(summary)
        return summary

async def run_continuous_monitoring(interval: int = 30):
    """Run continuous health monitoring with specified interval"""
    logger.info(f"Starting continuous health monitoring (interval: {interval}s)")
    
    async with HealthChecker() as checker:
        while True:
            try:
                summary = await checker.check_all_services()
                checker.save_results(summary)
                checker.print_summary(summary)
                
                # Sleep for the specified interval
                logger.info(f"Sleeping for {interval} seconds...")
                await asyncio.sleep(interval)
                
            except KeyboardInterrupt:
                logger.info("Monitoring stopped by user")
                break
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")
                await asyncio.sleep(5)  # Short sleep before retry

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="PyAirtable Service Health Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run single health check
  python health-check.py --once
  
  # Run continuous monitoring (default: 30s interval)
  python health-check.py --continuous
  
  # Run continuous monitoring with custom interval
  python health-check.py --continuous --interval 60
        """
    )
    
    parser.add_argument(
        '--once', 
        action='store_true',
        help='Run single health check and exit'
    )
    
    parser.add_argument(
        '--continuous', 
        action='store_true',
        help='Run continuous health monitoring'
    )
    
    parser.add_argument(
        '--interval', 
        type=int, 
        default=30,
        help='Monitoring interval in seconds (default: 30)'
    )
    
    args = parser.parse_args()
    
    # Default to single check if no mode specified
    if not args.once and not args.continuous:
        args.once = True
    
    try:
        if args.once:
            asyncio.run(run_single_check())
        elif args.continuous:
            asyncio.run(run_continuous_monitoring(args.interval))
    except KeyboardInterrupt:
        logger.info("Health monitoring stopped by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()