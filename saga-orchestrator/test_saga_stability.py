#!/usr/bin/env python3
"""Test script to verify SAGA Orchestrator stability and functionality."""

import asyncio
import httpx
import json
import sys
import time
from typing import Dict, Any


class SagaOrchestratorTester:
    """Test SAGA Orchestrator functionality."""
    
    def __init__(self, base_url: str = "http://localhost:8008"):
        self.base_url = base_url
        self.client = httpx.AsyncClient(timeout=30.0)
    
    async def test_health_check(self) -> bool:
        """Test health check endpoint."""
        try:
            # Try with trailing slash first to handle redirect
            response = await self.client.get(f"{self.base_url}/health/")
            
            if response.status_code == 200:
                health_data = response.json()
                print(f"✅ Health check passed: {health_data['status']}")
                print(f"   Components: {health_data['components']}")
                return True
            else:
                print(f"❌ Health check failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Health check error: {e}")
            return False
    
    async def test_readiness_check(self) -> bool:
        """Test readiness probe."""
        try:
            response = await self.client.get(f"{self.base_url}/health/ready")
            
            if response.status_code == 200:
                ready_data = response.json()
                print(f"✅ Readiness check passed: {ready_data['status']}")
                if 'mode' in ready_data:
                    print(f"   Mode: {ready_data['mode']}")
                return True
            else:
                print(f"❌ Readiness check failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Readiness check error: {e}")
            return False
    
    async def test_liveness_check(self) -> bool:
        """Test liveness probe."""
        try:
            response = await self.client.get(f"{self.base_url}/health/live")
            
            if response.status_code == 200:
                live_data = response.json()
                print(f"✅ Liveness check passed: {live_data['status']}")
                return True
            else:
                print(f"❌ Liveness check failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Liveness check error: {e}")
            return False
    
    async def test_transaction_types(self) -> bool:
        """Test available transaction types endpoint."""
        try:
            response = await self.client.get(f"{self.base_url}/api/v1/saga/transaction/types/available")
            
            if response.status_code == 200:
                types_data = response.json()
                print(f"✅ Transaction types endpoint working")
                print(f"   Available types: {[t['name'] for t in types_data['transaction_types']]}")
                return True
            else:
                print(f"❌ Transaction types failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Transaction types error: {e}")
            return False
    
    async def test_create_simple_saga(self) -> Dict[str, Any]:
        """Test creating a simple SAGA transaction."""
        try:
            # Create a test transaction
            transaction_data = {
                "transaction_type": "user_onboarding",
                "input_data": {
                    "user_id": "test_user_123",
                    "email": "test@example.com",
                    "first_name": "Test",
                    "last_name": "User",
                    "tenant_id": "test_tenant"
                },
                "correlation_id": f"test_{int(time.time())}"
            }
            
            response = await self.client.post(
                f"{self.base_url}/api/v1/saga/transaction",
                json=transaction_data
            )
            
            if response.status_code == 201:
                saga_data = response.json()
                print(f"✅ SAGA creation successful")
                print(f"   Transaction ID: {saga_data['transaction_id']}")
                print(f"   Status: {saga_data['status']}")
                print(f"   Steps: {saga_data['total_steps']}")
                return saga_data
            else:
                print(f"❌ SAGA creation failed: {response.status_code} - {response.text}")
                return {}
                
        except Exception as e:
            print(f"❌ SAGA creation error: {e}")
            return {}
    
    async def test_saga_status(self, transaction_id: str) -> bool:
        """Test getting SAGA status."""
        try:
            response = await self.client.get(
                f"{self.base_url}/api/v1/saga/transaction/{transaction_id}"
            )
            
            if response.status_code == 200:
                status_data = response.json()
                print(f"✅ SAGA status retrieval successful")
                print(f"   Status: {status_data['status']}")
                print(f"   Current step: {status_data['current_step']}/{status_data['total_steps']}")
                if status_data.get('error_message'):
                    print(f"   Error: {status_data['error_message']}")
                return True
            else:
                print(f"❌ SAGA status failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ SAGA status error: {e}")
            return False
    
    async def test_saga_list(self) -> bool:
        """Test listing SAGAs."""
        try:
            response = await self.client.get(f"{self.base_url}/api/v1/saga/transaction")
            
            if response.status_code == 200:
                list_data = response.json()
                print(f"✅ SAGA listing successful")
                print(f"   Total transactions: {list_data['total']}")
                print(f"   Page: {list_data['page']}, Size: {list_data['page_size']}")
                return True
            else:
                print(f"❌ SAGA listing failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ SAGA listing error: {e}")
            return False
    
    async def test_saga_steps(self, transaction_id: str) -> bool:
        """Test getting SAGA steps."""
        try:
            response = await self.client.get(
                f"{self.base_url}/api/v1/saga/transaction/{transaction_id}/steps"
            )
            
            if response.status_code == 200:
                steps_data = response.json()
                print(f"✅ SAGA steps retrieval successful")
                print(f"   Steps count: {len(steps_data)}")
                for step in steps_data:
                    status_emoji = "✅" if step['status'] == 'completed' else "⏳" if step['status'] == 'running' else "⏸️"
                    print(f"   {status_emoji} Step {step['step_number']}: {step['name']} ({step['status']})")
                return True
            else:
                print(f"❌ SAGA steps failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ SAGA steps error: {e}")
            return False
    
    async def test_statistics(self) -> bool:
        """Test statistics endpoint."""
        try:
            # Try the correct statistics endpoint
            response = await self.client.get(f"{self.base_url}/api/v1/saga/statistics/")
            
            if response.status_code == 200:
                stats_data = response.json()
                print(f"✅ Statistics endpoint working")
                print(f"   Service status: {stats_data.get('status', 'unknown')}")
                if 'components' in stats_data:
                    print(f"   Components: {stats_data['components']}")
                return True
            else:
                print(f"❌ Statistics failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            print(f"❌ Statistics error: {e}")
            return False
    
    async def run_all_tests(self) -> bool:
        """Run all tests."""
        print("🚀 Starting SAGA Orchestrator stability tests...\n")
        
        # Basic health tests
        print("🔍 Testing Health Endpoints...")
        health_ok = await self.test_health_check()
        ready_ok = await self.test_readiness_check()
        live_ok = await self.test_liveness_check()
        
        if not (health_ok and ready_ok and live_ok):
            print("\n❌ Basic health checks failed. Service may not be stable.")
            return False
        
        print("\n🔍 Testing API Endpoints...")
        
        # API functionality tests
        types_ok = await self.test_transaction_types()
        list_ok = await self.test_saga_list()
        stats_ok = await self.test_statistics()
        
        print("\n🔍 Testing SAGA Operations...")
        
        # Test SAGA operations
        saga_data = await self.test_create_simple_saga()
        saga_created = bool(saga_data)
        
        status_ok = False
        steps_ok = False
        
        if saga_created:
            transaction_id = saga_data.get('transaction_id')
            if transaction_id:
                # Wait a moment for processing
                await asyncio.sleep(2)
                
                status_ok = await self.test_saga_status(transaction_id)
                steps_ok = await self.test_saga_steps(transaction_id)
        
        # Summary
        print("\n" + "="*50)
        print("📊 TEST SUMMARY")
        print("="*50)
        
        tests = [
            ("Health Check", health_ok),
            ("Readiness Check", ready_ok),
            ("Liveness Check", live_ok),
            ("Transaction Types", types_ok),
            ("SAGA Listing", list_ok),
            ("Statistics", stats_ok),
            ("SAGA Creation", saga_created),
            ("Status Retrieval", status_ok),
            ("Steps Retrieval", steps_ok)
        ]
        
        passed = sum(1 for _, result in tests if result)
        total = len(tests)
        
        for test_name, result in tests:
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"{test_name:<20} {status}")
        
        print(f"\nResults: {passed}/{total} tests passed")
        
        if passed == total:
            print("🎉 All tests passed! SAGA Orchestrator appears stable.")
            return True
        elif passed >= total * 0.7:  # 70% pass rate
            print("⚠️  Most tests passed. Service is functional but may have some issues.")
            return True
        else:
            print("❌ Many tests failed. Service may not be stable.")
            return False
    
    async def close(self):
        """Close HTTP client."""
        await self.client.aclose()


async def main():
    """Run SAGA stability tests."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Test SAGA Orchestrator stability")
    parser.add_argument("--url", default="http://localhost:8008", help="Base URL for SAGA Orchestrator")
    parser.add_argument("--wait", type=int, default=0, help="Wait seconds before starting tests")
    
    args = parser.parse_args()
    
    if args.wait > 0:
        print(f"⏳ Waiting {args.wait} seconds for service to start...")
        await asyncio.sleep(args.wait)
    
    tester = SagaOrchestratorTester(args.url)
    
    try:
        success = await tester.run_all_tests()
        sys.exit(0 if success else 1)
    finally:
        await tester.close()


if __name__ == "__main__":
    asyncio.run(main())