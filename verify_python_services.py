#!/usr/bin/env python3
"""
Verification script to test Python services after import fixes.
Run this after starting the infrastructure to verify services are working.
"""

import asyncio
import aiohttp
import json
from typing import Dict, List
import time


class ServiceTester:
    def __init__(self):
        self.services = {
            'mcp-server': 'http://localhost:8001',
            'airtable-gateway': 'http://localhost:8002', 
            'llm-orchestrator': 'http://localhost:8003',
            'automation-services': 'http://localhost:8006',
            'saga-orchestrator': 'http://localhost:8008',
        }
    
    async def test_service_health(self, session: aiohttp.ClientSession, name: str, url: str) -> Dict:
        """Test a single service's health endpoint."""
        try:
            health_url = f"{url}/health"
            async with session.get(health_url, timeout=5) as response:
                if response.status == 200:
                    data = await response.json()
                    return {
                        'name': name,
                        'status': 'healthy',
                        'url': url,
                        'response': data
                    }
                else:
                    return {
                        'name': name, 
                        'status': 'unhealthy',
                        'url': url,
                        'error': f"HTTP {response.status}"
                    }
        except asyncio.TimeoutError:
            return {
                'name': name,
                'status': 'timeout', 
                'url': url,
                'error': 'Request timeout'
            }
        except Exception as e:
            return {
                'name': name,
                'status': 'error',
                'url': url, 
                'error': str(e)
            }
    
    async def test_service_info(self, session: aiohttp.ClientSession, name: str, url: str) -> Dict:
        """Test a service's info endpoint."""
        try:
            info_url = f"{url}/api/v1/info"
            async with session.get(info_url, timeout=5) as response:
                if response.status == 200:
                    data = await response.json()
                    return {
                        'name': name,
                        'info_status': 'available',
                        'service_info': data
                    }
                else:
                    return {
                        'name': name,
                        'info_status': 'unavailable',
                        'error': f"HTTP {response.status}"
                    }
        except Exception as e:
            return {
                'name': name,
                'info_status': 'error',
                'error': str(e)
            }
    
    async def run_tests(self) -> List[Dict]:
        """Run all service tests."""
        print("🔍 Testing Python Services After Import Fixes")
        print("=" * 60)
        
        results = []
        
        async with aiohttp.ClientSession() as session:
            # Test health endpoints
            print("\n📊 Testing Health Endpoints...")
            health_tasks = [
                self.test_service_health(session, name, url) 
                for name, url in self.services.items()
            ]
            health_results = await asyncio.gather(*health_tasks)
            
            # Test info endpoints
            print("\n📋 Testing Service Info Endpoints...")
            info_tasks = [
                self.test_service_info(session, name, url)
                for name, url in self.services.items()
            ]
            info_results = await asyncio.gather(*info_tasks)
            
            # Combine results
            for health, info in zip(health_results, info_results):
                combined = {**health, **info}
                results.append(combined)
                
                # Print individual results
                status_icon = "✅" if health['status'] == 'healthy' else "❌"
                info_icon = "✅" if info.get('info_status') == 'available' else "⚠️"
                
                print(f"{status_icon} {name}: {health['status']}")
                if health['status'] != 'healthy':
                    print(f"   Error: {health.get('error', 'Unknown')}")
                else:
                    print(f"   {info_icon} Info endpoint: {info.get('info_status', 'unknown')}")
                    if 'service_info' in info:
                        service_name = info['service_info'].get('service', 'unknown')
                        version = info['service_info'].get('version', 'unknown')
                        print(f"   📦 Service: {service_name} v{version}")
        
        return results
    
    def print_summary(self, results: List[Dict]):
        """Print test summary."""
        print("\n" + "=" * 60)
        print("📊 SUMMARY")
        print("=" * 60)
        
        healthy_count = sum(1 for r in results if r['status'] == 'healthy')
        total_count = len(results)
        
        print(f"Services tested: {total_count}")
        print(f"Healthy services: {healthy_count}")
        print(f"Success rate: {healthy_count/total_count*100:.1f}%")
        
        if healthy_count == total_count:
            print("\n🎉 All Python services are running successfully!")
            print("✅ Import fixes have been verified and are working correctly.")
        else:
            print(f"\n⚠️  {total_count - healthy_count} services are not responding correctly.")
            print("This could be due to:")
            print("- Services not started yet")
            print("- Missing external dependencies (Redis, PostgreSQL)")
            print("- Network connectivity issues")
            print("- Configuration problems")


async def main():
    """Main function."""
    tester = ServiceTester()
    
    print("⏳ Waiting a moment for services to be ready...")
    await asyncio.sleep(2)
    
    results = await tester.run_tests()
    tester.print_summary(results)
    
    # Save results to file
    with open('service_test_results.json', 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\n📄 Detailed results saved to: service_test_results.json")
    
    return len([r for r in results if r['status'] == 'healthy']) == len(results)


if __name__ == '__main__':
    try:
        import aiohttp
        success = asyncio.run(main())
        exit(0 if success else 1)
    except ImportError:
        print("❌ aiohttp not installed. Install with: pip install aiohttp")
        print("🔍 Testing connectivity with basic requests...")
        
        # Fallback using urllib
        import urllib.request
        import urllib.error
        
        services = {
            'mcp-server': 'http://localhost:8001',
            'airtable-gateway': 'http://localhost:8002', 
            'llm-orchestrator': 'http://localhost:8003',
            'automation-services': 'http://localhost:8006',
            'saga-orchestrator': 'http://localhost:8008',
        }
        
        healthy_count = 0
        for name, url in services.items():
            try:
                with urllib.request.urlopen(f"{url}/health", timeout=5) as response:
                    if response.status == 200:
                        print(f"✅ {name}: healthy")
                        healthy_count += 1
                    else:
                        print(f"❌ {name}: HTTP {response.status}")
            except Exception as e:
                print(f"❌ {name}: {str(e)}")
        
        print(f"\nHealthy services: {healthy_count}/{len(services)}")
        exit(0 if healthy_count == len(services) else 1)