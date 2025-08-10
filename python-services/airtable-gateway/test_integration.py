#!/usr/bin/env python3
"""
Integration test script for Airtable Gateway service

This script tests the Airtable integration with a real API token.
You'll need to:
1. Set AIRTABLE_TOKEN environment variable with a valid token
2. Have Redis running on localhost:6379
3. Install dependencies: pip install -r requirements.txt

Usage:
    python test_integration.py
"""

import asyncio
import os
import sys
from typing import List, Dict, Any

# Add src to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from redis import asyncio as aioredis
from config import Settings, get_settings
from services.airtable import AirtableService, AirtableAuthError


async def test_airtable_integration():
    """Test Airtable integration with real API"""
    
    print("🧪 Starting Airtable Integration Tests")
    print("=" * 50)
    
    # Check if token is provided
    token = os.getenv('AIRTABLE_TOKEN')
    if not token:
        print("❌ AIRTABLE_TOKEN environment variable not set")
        print("Please set your Airtable token: export AIRTABLE_TOKEN='your_token_here'")
        return False
    
    try:
        # Initialize settings
        settings = Settings(airtable_token=token)
        print(f"✅ Configuration loaded successfully")
        print(f"   Token: {settings.get_masked_token()}")
        print(f"   Rate limit: {settings.airtable_rate_limit}/s")
        print(f"   Retry attempts: {settings.airtable_retry_attempts}")
        
    except Exception as e:
        print(f"❌ Configuration validation failed: {e}")
        return False
    
    # Connect to Redis
    try:
        redis = await aioredis.from_url(settings.redis_url, decode_responses=True)
        await redis.ping()
        print(f"✅ Connected to Redis at {settings.redis_url}")
    except Exception as e:
        print(f"⚠️  Redis connection failed (continuing without cache): {e}")
        redis = None
    
    # Initialize Airtable service
    try:
        service = AirtableService(redis)
        print("✅ Airtable service initialized")
    except Exception as e:
        print(f"❌ Failed to initialize Airtable service: {e}")
        return False
    
    test_results = []
    
    # Test 1: API Key Validation
    print("\n📋 Test 1: API Key Validation")
    try:
        is_valid = await service.validate_api_key()
        if is_valid:
            print("✅ API key validation successful")
            test_results.append(("API Key Validation", True))
        else:
            print("❌ API key validation failed")
            test_results.append(("API Key Validation", False))
            return False
    except Exception as e:
        print(f"❌ API key validation error: {e}")
        test_results.append(("API Key Validation", False))
        return False
    
    # Test 2: List Bases
    print("\n📋 Test 2: List Bases")
    try:
        bases = await service.list_bases()
        if bases:
            print(f"✅ Found {len(bases)} base(s)")
            for base in bases[:3]:  # Show first 3 bases
                print(f"   - {base.get('name', 'Unnamed')} ({base.get('id', 'No ID')})")
            if len(bases) > 3:
                print(f"   ... and {len(bases) - 3} more")
            test_results.append(("List Bases", True))
        else:
            print("⚠️  No bases found (this might be expected)")
            test_results.append(("List Bases", True))
    except AirtableAuthError as e:
        print(f"❌ Authentication error: {e}")
        test_results.append(("List Bases", False))
        return False
    except Exception as e:
        print(f"❌ Error listing bases: {e}")
        test_results.append(("List Bases", False))
    
    # Test 3: Get Base Schema (if we have bases)
    if bases:
        print("\n📋 Test 3: Get Base Schema")
        try:
            first_base_id = bases[0]['id']
            schema = await service.get_base_schema(first_base_id)
            
            tables = schema.get('tables', [])
            if tables:
                print(f"✅ Retrieved schema for base '{bases[0].get('name', 'Unnamed')}'")
                print(f"   Found {len(tables)} table(s)")
                for table in tables[:3]:  # Show first 3 tables
                    print(f"   - {table.get('name', 'Unnamed')} ({table.get('id', 'No ID')})")
                if len(tables) > 3:
                    print(f"   ... and {len(tables) - 3} more")
                test_results.append(("Get Base Schema", True))
            else:
                print("⚠️  Base has no tables")
                test_results.append(("Get Base Schema", True))
                
        except Exception as e:
            print(f"❌ Error getting base schema: {e}")
            test_results.append(("Get Base Schema", False))
        
        # Test 4: List Records (if we have tables)
        if tables:
            print("\n📋 Test 4: List Records")
            try:
                first_table_id = tables[0]['id']
                records_response = await service.list_records(
                    base_id=first_base_id,
                    table_id=first_table_id,
                    max_records=5  # Limit to 5 records for testing
                )
                
                records = records_response.get('records', [])
                print(f"✅ Retrieved {len(records)} record(s) from table '{tables[0].get('name', 'Unnamed')}'")
                
                if records:
                    # Show first record structure (without sensitive data)
                    first_record = records[0]
                    field_names = list(first_record.get('fields', {}).keys())
                    print(f"   Record fields: {', '.join(field_names[:5])}")
                    if len(field_names) > 5:
                        print(f"   ... and {len(field_names) - 5} more fields")
                
                test_results.append(("List Records", True))
                
            except Exception as e:
                print(f"❌ Error listing records: {e}")
                test_results.append(("List Records", False))
    
    # Test 5: Cache Operations (if Redis is available)
    if redis:
        print("\n📋 Test 5: Cache Operations")
        try:
            # Test cache invalidation
            await service.invalidate_cache()
            print("✅ Cache invalidation successful")
            test_results.append(("Cache Operations", True))
        except Exception as e:
            print(f"❌ Cache operation error: {e}")
            test_results.append(("Cache Operations", False))
    
    # Test Summary
    print("\n" + "=" * 50)
    print("📊 Test Summary")
    print("=" * 50)
    
    passed = sum(1 for _, result in test_results if result)
    total = len(test_results)
    
    for test_name, result in test_results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status} {test_name}")
    
    print(f"\nResult: {passed}/{total} tests passed")
    
    if redis:
        await redis.close()
    
    return passed == total


async def main():
    """Main function"""
    try:
        success = await test_airtable_integration()
        if success:
            print("\n🎉 All tests passed! Airtable integration is working correctly.")
            sys.exit(0)
        else:
            print("\n❌ Some tests failed. Please check your configuration and try again.")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n⚠️  Tests interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n💥 Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())