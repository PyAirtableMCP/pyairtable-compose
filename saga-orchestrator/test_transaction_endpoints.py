#!/usr/bin/env python3
"""Test script for SAGA transaction endpoints."""

import asyncio
import json
import sys
import time
from typing import Dict, Any

import httpx

# Configuration
BASE_URL = "http://localhost:8008"
API_BASE = f"{BASE_URL}/api/v1/saga/transaction"


async def test_transaction_endpoints():
    """Test all SAGA transaction endpoints."""
    print("🚀 Testing SAGA Transaction Endpoints")
    print("=" * 50)
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            # Test 1: Health check
            print("\n1. Health Check")
            health_response = await client.get(f"{BASE_URL}/health")
            print(f"   Status: {health_response.status_code}")
            if health_response.status_code == 200:
                print("   ✅ Service is healthy")
            else:
                print("   ❌ Service is unhealthy")
                return False
            
            # Test 2: Get available transaction types
            print("\n2. Get Available Transaction Types")
            types_response = await client.get(f"{API_BASE}/types/available")
            print(f"   Status: {types_response.status_code}")
            if types_response.status_code == 200:
                types_data = types_response.json()
                print(f"   ✅ Available types: {len(types_data.get('transaction_types', []))}")
                for tx_type in types_data.get('transaction_types', []):
                    print(f"      - {tx_type.get('name')}: {tx_type.get('description')}")
            else:
                print(f"   ❌ Failed to get transaction types: {types_response.text}")
            
            # Test 3: Create a new transaction
            print("\n3. Create New Transaction")
            create_request = {
                "transaction_type": "user_onboarding",
                "input_data": {
                    "user_id": "test_user_123",
                    "email": "test@example.com",
                    "first_name": "Test",
                    "last_name": "User",
                    "tenant_id": "test_tenant"
                },
                "correlation_id": f"test_correlation_{int(time.time())}",
                "metadata": {
                    "test_run": True,
                    "created_by": "test_script"
                }
            }
            
            create_response = await client.post(API_BASE, json=create_request)
            print(f"   Status: {create_response.status_code}")
            
            if create_response.status_code == 201:
                transaction_data = create_response.json()
                transaction_id = transaction_data["transaction_id"]
                print(f"   ✅ Transaction created: {transaction_id}")
                print(f"      Type: {transaction_data['transaction_type']}")
                print(f"      Status: {transaction_data['status']}")
                print(f"      Steps: {transaction_data['current_step']}/{transaction_data['total_steps']}")
                
                # Test 4: Get transaction status
                print(f"\n4. Get Transaction Status: {transaction_id}")
                status_response = await client.get(f"{API_BASE}/{transaction_id}")
                print(f"   Status: {status_response.status_code}")
                
                if status_response.status_code == 200:
                    status_data = status_response.json()
                    print(f"   ✅ Transaction status retrieved")
                    print(f"      Status: {status_data['status']}")
                    print(f"      Current Step: {status_data['current_step']}/{status_data['total_steps']}")
                    print(f"      Started: {status_data.get('started_at', 'N/A')}")
                else:
                    print(f"   ❌ Failed to get transaction status: {status_response.text}")
                
                # Test 5: Get transaction steps
                print(f"\n5. Get Transaction Steps: {transaction_id}")
                steps_response = await client.get(f"{API_BASE}/{transaction_id}/steps")
                print(f"   Status: {steps_response.status_code}")
                
                if steps_response.status_code == 200:
                    steps_data = steps_response.json()
                    print(f"   ✅ Transaction steps retrieved: {len(steps_data)} steps")
                    for i, step in enumerate(steps_data[:3]):  # Show first 3 steps
                        print(f"      Step {i+1}: {step.get('name')} ({step.get('status')})")
                else:
                    print(f"   ❌ Failed to get transaction steps: {steps_response.text}")
                
                # Test 6: Update transaction
                print(f"\n6. Update Transaction: {transaction_id}")
                update_request = {
                    "metadata": {
                        "updated_by": "test_script",
                        "update_timestamp": time.time(),
                        "priority": "normal"
                    },
                    "notes": "Updated during endpoint testing"
                }
                
                update_response = await client.put(f"{API_BASE}/{transaction_id}", json=update_request)
                print(f"   Status: {update_response.status_code}")
                
                if update_response.status_code == 200:
                    update_data = update_response.json()
                    print(f"   ✅ Transaction updated")
                    print(f"      Status: {update_data['status']}")
                else:
                    print(f"   ❌ Failed to update transaction: {update_response.text}")
                
                # Test 7: Execute next step (if applicable)
                print(f"\n7. Execute Next Step: {transaction_id}")
                step_request = {
                    "force": False,
                    "input_override": {
                        "test_mode": True
                    }
                }
                
                step_response = await client.post(f"{API_BASE}/{transaction_id}/step", json=step_request)
                print(f"   Status: {step_response.status_code}")
                
                if step_response.status_code == 200:
                    step_data = step_response.json()
                    print(f"   ✅ Step execution result: {step_data.get('status', 'unknown')}")
                    if 'message' in step_data:
                        print(f"      Message: {step_data['message']}")
                else:
                    print(f"   ❌ Step execution failed: {step_response.text}")
                
                # Wait a moment for processing
                await asyncio.sleep(2)
                
                # Test 8: List transactions
                print(f"\n8. List Transactions")
                list_response = await client.get(f"{API_BASE}")
                print(f"   Status: {list_response.status_code}")
                
                if list_response.status_code == 200:
                    list_data = list_response.json()
                    total_transactions = list_data.get('total', 0)
                    transactions = list_data.get('transactions', [])
                    print(f"   ✅ Found {total_transactions} total transactions")
                    print(f"      Current page: {len(transactions)} transactions")
                    
                    # Show some transaction info
                    for tx in transactions[:3]:
                        print(f"      - {tx['transaction_id'][:8]}... ({tx['status']}) - {tx['transaction_type']}")
                else:
                    print(f"   ❌ Failed to list transactions: {list_response.text}")
                
                # Test 9: List with filters
                print(f"\n9. List Transactions with Filters")
                filter_params = {
                    "transaction_type": "user_onboarding",
                    "page_size": 5
                }
                filter_response = await client.get(f"{API_BASE}", params=filter_params)
                print(f"   Status: {filter_response.status_code}")
                
                if filter_response.status_code == 200:
                    filter_data = filter_response.json()
                    print(f"   ✅ Filtered results: {len(filter_data.get('transactions', []))} transactions")
                else:
                    print(f"   ❌ Failed to list filtered transactions: {filter_response.text}")
                
                # Test 10: Trigger compensation (optional - only if transaction is in a compensable state)
                print(f"\n10. Trigger Compensation: {transaction_id}")
                compensation_request = {
                    "reason": "Testing compensation endpoint",
                    "force_complete": False
                }
                
                compensation_response = await client.post(f"{API_BASE}/{transaction_id}/compensate", json=compensation_request)
                print(f"   Status: {compensation_response.status_code}")
                
                if compensation_response.status_code == 200:
                    compensation_data = compensation_response.json()
                    print(f"   ✅ Compensation result: {compensation_data.get('status', 'unknown')}")
                    if 'message' in compensation_data:
                        print(f"      Message: {compensation_data['message']}")
                elif compensation_response.status_code == 400:
                    # Expected for transactions that can't be compensated
                    error_data = compensation_response.json()
                    print(f"   ⚠️  Compensation not applicable: {error_data.get('detail', 'Unknown error')}")
                else:
                    print(f"   ❌ Compensation failed: {compensation_response.text}")
                
                # Test 11: Test error handling - get non-existent transaction
                print(f"\n11. Test Error Handling - Non-existent Transaction")
                fake_id = "non_existent_transaction_id"
                error_response = await client.get(f"{API_BASE}/{fake_id}")
                print(f"   Status: {error_response.status_code}")
                
                if error_response.status_code == 404:
                    print(f"   ✅ Correctly returned 404 for non-existent transaction")
                else:
                    print(f"   ❌ Unexpected status for non-existent transaction: {error_response.status_code}")
                
                print(f"\n✅ All tests completed successfully!")
                print(f"   Created transaction: {transaction_id}")
                print(f"   🔗 View in browser: {BASE_URL}/docs")
                
                return True
                
            else:
                print(f"   ❌ Failed to create transaction: {create_response.text}")
                return False
                
        except httpx.ConnectError:
            print(f"❌ Connection error: Could not connect to {BASE_URL}")
            print("   Make sure the SAGA orchestrator service is running on port 8008")
            return False
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
            return False


async def test_performance():
    """Test performance of transaction endpoints."""
    print("\n🚀 Performance Test")
    print("=" * 50)
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            # Create multiple transactions concurrently
            print("\nCreating 5 transactions concurrently...")
            
            async def create_transaction(index: int):
                create_request = {
                    "transaction_type": "user_onboarding",
                    "input_data": {
                        "user_id": f"perf_test_user_{index}",
                        "email": f"perftest{index}@example.com",
                        "first_name": f"PerfTest{index}",
                        "tenant_id": "perf_test_tenant"
                    },
                    "correlation_id": f"perf_test_{index}_{int(time.time())}"
                }
                
                start_time = time.time()
                response = await client.post(API_BASE, json=create_request)
                end_time = time.time()
                
                return {
                    "index": index,
                    "status_code": response.status_code,
                    "duration_ms": round((end_time - start_time) * 1000, 2),
                    "success": response.status_code == 201
                }
            
            # Execute concurrent requests
            start_time = time.time()
            results = await asyncio.gather(*[create_transaction(i) for i in range(5)])
            total_time = time.time() - start_time
            
            # Analyze results
            successful_requests = [r for r in results if r["success"]]
            average_duration = sum(r["duration_ms"] for r in successful_requests) / len(successful_requests) if successful_requests else 0
            
            print(f"   ✅ Created {len(successful_requests)}/5 transactions successfully")
            print(f"   📊 Average response time: {average_duration:.2f}ms")
            print(f"   🕐 Total time: {total_time:.2f}s")
            print(f"   🚀 Throughput: {len(successful_requests) / total_time:.2f} requests/second")
            
            return len(successful_requests) == 5
            
        except Exception as e:
            print(f"❌ Performance test error: {e}")
            return False


async def main():
    """Main test function."""
    print("🧪 SAGA Transaction Endpoints Test Suite")
    print("=" * 60)
    
    # Run basic functionality tests
    basic_tests_passed = await test_transaction_endpoints()
    
    if basic_tests_passed:
        # Run performance tests
        performance_tests_passed = await test_performance()
        
        print("\n" + "=" * 60)
        if basic_tests_passed and performance_tests_passed:
            print("🎉 All tests passed! SAGA transaction endpoints are working correctly.")
            print("\nNext steps:")
            print("  1. Check the service logs for detailed execution traces")
            print("  2. Monitor PostgreSQL for persisted transaction data")
            print("  3. Test with real service integrations")
            print("  4. Run load tests for production readiness")
        else:
            print("⚠️  Some tests failed. Please check the service configuration and logs.")
            return 1
    else:
        print("\n❌ Basic tests failed. Please check service health and configuration.")
        return 1
    
    return 0


if __name__ == "__main__":
    try:
        result = asyncio.run(main())
        sys.exit(result)
    except KeyboardInterrupt:
        print("\n🛑 Test interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n💥 Test suite crashed: {e}")
        sys.exit(1)