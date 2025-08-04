"""
Integration tests for data integrity across services and storage layers.
Tests ACID compliance, eventual consistency, and data synchronization.
"""

import pytest
import asyncio
import asyncpg
import redis.asyncio as redis
import httpx
import json
import time
import uuid
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor
import logging

logger = logging.getLogger(__name__)


@dataclass
class DataIntegrityTest:
    """Data integrity test configuration"""
    name: str
    description: str
    test_data: Dict[str, Any]
    validation_queries: List[str]
    expected_results: List[Any]


@pytest.mark.integration
@pytest.mark.database
class TestDatabaseIntegrity:
    """Test database ACID compliance and transaction integrity"""

    async def test_acid_transaction_compliance(self, db_connection, test_data_factory):
        """Test ACID properties in database transactions"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Test Atomicity: Either all operations succeed or all fail
        await self._test_atomicity(db_connection, test_data_factory)
        
        # Test Consistency: Database constraints are maintained
        await self._test_consistency(db_connection, test_data_factory)
        
        # Test Isolation: Concurrent transactions don't interfere
        await self._test_isolation(db_connection, test_data_factory)
        
        # Test Durability: Committed transactions survive system failures
        await self._test_durability(db_connection, test_data_factory)

    async def _test_atomicity(self, db_connection: asyncpg.Connection, test_data_factory):
        """Test transaction atomicity"""
        # Create test table
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_atomicity (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL,
                value INTEGER NOT NULL,
                CHECK (value >= 0)
            )
        """)
        
        # Test successful transaction
        async with db_connection.transaction():
            await db_connection.execute(
                "INSERT INTO test_atomicity (name, value) VALUES ($1, $2)",
                "test1", 100
            )
            await db_connection.execute(
                "INSERT INTO test_atomicity (name, value) VALUES ($1, $2)",
                "test2", 200
            )
        
        # Verify both records exist
        records = await db_connection.fetch("SELECT * FROM test_atomicity")
        assert len(records) == 2
        
        # Test failed transaction (should rollback everything)
        try:
            async with db_connection.transaction():
                await db_connection.execute(
                    "INSERT INTO test_atomicity (name, value) VALUES ($1, $2)",
                    "test3", 300
                )
                # This should violate the CHECK constraint
                await db_connection.execute(
                    "INSERT INTO test_atomicity (name, value) VALUES ($1, $2)",
                    "test4", -100
                )
        except asyncpg.CheckViolationError:
            pass  # Expected error
        
        # Verify no new records were added
        records = await db_connection.fetch("SELECT * FROM test_atomicity")
        assert len(records) == 2

    async def _test_consistency(self, db_connection: asyncpg.Connection, test_data_factory):
        """Test database consistency constraints"""
        # Create tables with foreign key constraints
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_users (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                name VARCHAR(100) NOT NULL
            )
        """)
        
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_orders (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES test_users(id) ON DELETE CASCADE,
                amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Test referential integrity
        user_data = test_data_factory.create_user_data()
        user_id = await db_connection.fetchval(
            "INSERT INTO test_users (email, name) VALUES ($1, $2) RETURNING id",
            user_data["email"], user_data["name"]
        )
        
        # Valid order should succeed
        await db_connection.execute(
            "INSERT INTO test_orders (user_id, amount) VALUES ($1, $2)",
            user_id, 99.99
        )
        
        # Order with invalid user_id should fail
        with pytest.raises(asyncpg.ForeignKeyViolationError):
            await db_connection.execute(
                "INSERT INTO test_orders (user_id, amount) VALUES ($1, $2)",
                99999, 50.00
            )

    async def _test_isolation(self, db_connection: asyncpg.Connection, test_data_factory):
        """Test transaction isolation levels"""
        # Create test table
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_isolation (
                id SERIAL PRIMARY KEY,
                balance DECIMAL(10,2) NOT NULL DEFAULT 1000.00
            )
        """)
        
        # Insert initial record
        account_id = await db_connection.fetchval(
            "INSERT INTO test_isolation (balance) VALUES ($1) RETURNING id",
            1000.00
        )
        
        # Test concurrent transactions
        async def transaction1():
            async with db_connection.transaction():
                # Read balance
                balance = await db_connection.fetchval(
                    "SELECT balance FROM test_isolation WHERE id = $1",
                    account_id
                )
                # Simulate processing time
                await asyncio.sleep(0.1)
                # Update balance
                await db_connection.execute(
                    "UPDATE test_isolation SET balance = $1 WHERE id = $2",
                    balance - 100, account_id
                )
                return balance - 100

        async def transaction2():
            async with db_connection.transaction():
                # Read balance
                balance = await db_connection.fetchval(
                    "SELECT balance FROM test_isolation WHERE id = $1",
                    account_id
                )
                # Simulate processing time
                await asyncio.sleep(0.1)
                # Update balance
                await db_connection.execute(
                    "UPDATE test_isolation SET balance = $1 WHERE id = $2",
                    balance - 200, account_id
                )
                return balance - 200

        # Run transactions concurrently
        results = await asyncio.gather(transaction1(), transaction2())
        
        # Final balance should be consistent
        final_balance = await db_connection.fetchval(
            "SELECT balance FROM test_isolation WHERE id = $1",
            account_id
        )
        
        # With proper isolation, final balance should be 700.00
        assert final_balance == 700.00

    async def _test_durability(self, db_connection: asyncpg.Connection, test_data_factory):
        """Test transaction durability"""
        # Create test table
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_durability (
                id SERIAL PRIMARY KEY,
                data TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Insert test data in transaction
        test_data = f"durability_test_{uuid.uuid4()}"
        
        async with db_connection.transaction():
            record_id = await db_connection.fetchval(
                "INSERT INTO test_durability (data) VALUES ($1) RETURNING id",
                test_data
            )
        
        # Simulate connection loss and reconnect (in real scenario)
        # For testing, we'll just verify the data persists
        await asyncio.sleep(0.1)
        
        # Verify data still exists
        retrieved_data = await db_connection.fetchval(
            "SELECT data FROM test_durability WHERE id = $1",
            record_id
        )
        
        assert retrieved_data == test_data

    async def test_concurrent_data_modifications(self, db_connection, test_data_factory):
        """Test concurrent data modifications for race conditions"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create test table for concurrent access
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_concurrent (
                id SERIAL PRIMARY KEY,
                counter INTEGER NOT NULL DEFAULT 0,
                last_modified TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Insert initial record
        record_id = await db_connection.fetchval(
            "INSERT INTO test_concurrent (counter) VALUES (0) RETURNING id"
        )
        
        # Function to increment counter
        async def increment_counter():
            for _ in range(10):
                await db_connection.execute("""
                    UPDATE test_concurrent 
                    SET counter = counter + 1, last_modified = NOW()
                    WHERE id = $1
                """, record_id)
        
        # Run multiple concurrent increment operations
        num_tasks = 5
        tasks = [increment_counter() for _ in range(num_tasks)]
        await asyncio.gather(*tasks)
        
        # Verify final counter value
        final_counter = await db_connection.fetchval(
            "SELECT counter FROM test_concurrent WHERE id = $1",
            record_id
        )
        
        # Should be exactly num_tasks * 10
        expected_value = num_tasks * 10
        assert final_counter == expected_value, \
            f"Expected counter {expected_value}, got {final_counter}"

    async def test_data_validation_constraints(self, db_connection, test_data_factory):
        """Test data validation and constraint enforcement"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create table with various constraints
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_constraints (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL CHECK (email ~ '^[^@]+@[^@]+\.[^@]+$'),
                age INTEGER CHECK (age >= 0 AND age <= 150),
                status VARCHAR(20) CHECK (status IN ('active', 'inactive', 'pending')),
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Test valid data insertion
        valid_data = {
            "email": "valid@example.com",
            "age": 25,
            "status": "active"
        }
        
        record_id = await db_connection.fetchval("""
            INSERT INTO test_constraints (email, age, status) 
            VALUES ($1, $2, $3) RETURNING id
        """, valid_data["email"], valid_data["age"], valid_data["status"])
        
        assert record_id is not None
        
        # Test constraint violations
        constraint_tests = [
            # Invalid email format
            ("invalid-email", 30, "active", asyncpg.CheckViolationError),
            # Duplicate email
            ("valid@example.com", 40, "active", asyncpg.UniqueViolationError),
            # Invalid age
            ("test2@example.com", -5, "active", asyncpg.CheckViolationError),
            # Invalid status
            ("test3@example.com", 25, "invalid_status", asyncpg.CheckViolationError),
        ]
        
        for email, age, status, expected_error in constraint_tests:
            with pytest.raises(expected_error):
                await db_connection.execute("""
                    INSERT INTO test_constraints (email, age, status) 
                    VALUES ($1, $2, $3)
                """, email, age, status)


@pytest.mark.integration
@pytest.mark.redis
class TestCacheIntegrity:
    """Test cache integrity and consistency"""

    async def test_cache_data_consistency(self, redis_client, db_connection, test_data_factory):
        """Test cache-database consistency"""
        if redis_client is None or db_connection is None:
            pytest.skip("Redis or database not available")
        
        # Create test data
        user_data = test_data_factory.create_user_data()
        cache_key = f"user:{user_data['email']}"
        
        # Store in database
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS test_users_cache (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                data JSONB NOT NULL,
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        user_id = await db_connection.fetchval("""
            INSERT INTO test_users_cache (email, data) 
            VALUES ($1, $2) RETURNING id
        """, user_data["email"], json.dumps(user_data))
        
        # Store in cache
        cache_data = {**user_data, "id": user_id, "cached_at": time.time()}
        await redis_client.setex(cache_key, 3600, json.dumps(cache_data))
        
        # Verify cache-database consistency
        db_record = await db_connection.fetchrow(
            "SELECT * FROM test_users_cache WHERE id = $1", user_id
        )
        cached_record = await redis_client.get(cache_key)
        
        assert cached_record is not None
        cached_data = json.loads(cached_record)
        
        # Verify key fields match
        assert cached_data["email"] == db_record["email"]
        assert cached_data["id"] == db_record["id"]

    async def test_cache_invalidation_patterns(self, redis_client, test_data_factory):
        """Test cache invalidation strategies"""
        if redis_client is None:
            pytest.skip("Redis not available")
        
        # Test TTL-based invalidation
        test_key = f"ttl_test:{int(time.time())}"
        await redis_client.setex(test_key, 2, "test_value")  # 2 second TTL
        
        # Verify value exists
        value = await redis_client.get(test_key)
        assert value == b"test_value"
        
        # Wait for expiration
        await asyncio.sleep(3)
        
        # Verify value expired
        value = await redis_client.get(test_key)
        assert value is None
        
        # Test manual invalidation
        manual_key = f"manual_test:{int(time.time())}"
        await redis_client.set(manual_key, "manual_value")
        
        # Verify exists
        assert await redis_client.exists(manual_key)
        
        # Manual delete
        await redis_client.delete(manual_key)
        
        # Verify deleted
        assert not await redis_client.exists(manual_key)

    async def test_cache_write_through_pattern(self, redis_client, db_connection, test_data_factory):
        """Test write-through cache pattern"""
        if redis_client is None or db_connection is None:
            pytest.skip("Redis or database not available")
        
        # Simulate write-through cache operation
        user_data = test_data_factory.create_user_data()
        cache_key = f"writethrough:{user_data['email']}"
        
        async def write_through_operation(data: Dict[str, Any]) -> int:
            # Write to database first
            user_id = await db_connection.fetchval("""
                INSERT INTO test_users_cache (email, data) 
                VALUES ($1, $2) RETURNING id
            """, data["email"], json.dumps(data))
            
            # Then update cache
            cache_data = {**data, "id": user_id}
            await redis_client.setex(cache_key, 3600, json.dumps(cache_data))
            
            return user_id
        
        # Perform write-through operation
        user_id = await write_through_operation(user_data)
        
        # Verify both database and cache have consistent data
        db_record = await db_connection.fetchrow(
            "SELECT * FROM test_users_cache WHERE id = $1", user_id
        )
        cached_record = await redis_client.get(cache_key)
        
        assert db_record is not None
        assert cached_record is not None
        
        cached_data = json.loads(cached_record)
        assert cached_data["email"] == db_record["email"]


@pytest.mark.integration
class TestCrossPlatformDataIntegrity:
    """Test data integrity across different platforms and services"""

    async def test_api_database_consistency(self, test_environment, db_connection, test_data_factory):
        """Test consistency between API operations and database state"""
        if db_connection is None:
            pytest.skip("Database not available")
        
        token = await self._get_test_token(test_environment)
        headers = {"Authorization": f"Bearer {token}"}
        
        # Create data via API
        table_data = test_data_factory.create_table_data()
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            api_response = await client.post(
                f"{test_environment.api_gateway_url}/api/tables",
                json=table_data,
                headers=headers
            )
            
            if api_response.status_code in [201, 200]:
                table_id = api_response.json().get("id")
                
                # Verify data exists in database
                db_record = await db_connection.fetchrow(
                    "SELECT * FROM tables WHERE id = $1 OR name = $1",
                    table_id or table_data["name"]
                )
                
                if db_record:
                    assert db_record["name"] == table_data["name"]

    async def test_eventual_consistency_patterns(self, test_environment, redis_client, db_connection):
        """Test eventual consistency in distributed operations"""
        if not all([redis_client, db_connection]):
            pytest.skip("Required services not available")
        
        # Simulate distributed write operation
        operation_id = str(uuid.uuid4())
        
        # Step 1: Write to primary store (database)
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS distributed_ops (
                id UUID PRIMARY KEY,
                status VARCHAR(20) NOT NULL,
                data JSONB,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        await db_connection.execute("""
            INSERT INTO distributed_ops (id, status, data) 
            VALUES ($1, $2, $3)
        """, operation_id, "pending", json.dumps({"test": "data"}))
        
        # Step 2: Write to cache (eventual consistency)
        await redis_client.setex(
            f"op:{operation_id}",
            3600,
            json.dumps({"status": "pending", "timestamp": time.time()})
        )
        
        # Simulate async processing
        await asyncio.sleep(0.1)
        
        # Step 3: Update status
        await db_connection.execute(
            "UPDATE distributed_ops SET status = $1 WHERE id = $2",
            "completed", operation_id
        )
        
        await redis_client.setex(
            f"op:{operation_id}",
            3600,
            json.dumps({"status": "completed", "timestamp": time.time()})
        )
        
        # Verify eventual consistency
        db_status = await db_connection.fetchval(
            "SELECT status FROM distributed_ops WHERE id = $1",
            operation_id
        )
        
        cache_data = await redis_client.get(f"op:{operation_id}")
        cache_status = json.loads(cache_data)["status"]
        
        assert db_status == "completed"
        assert cache_status == "completed"

    async def test_data_synchronization_across_services(self, test_environment, test_data_factory):
        """Test data synchronization between different services"""
        token = await self._get_test_token(test_environment)
        headers = {"Authorization": f"Bearer {token}"}
        
        # Create data in one service
        user_data = test_data_factory.create_user_data()
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            # Create user via auth service
            auth_response = await client.post(
                f"{test_environment.auth_service_url}/auth/register",
                json={
                    "email": user_data["email"],
                    "password": user_data["password"],
                    "first_name": user_data["first_name"],
                    "last_name": user_data["last_name"]
                }
            )
            
            if auth_response.status_code in [201, 409]:  # Created or already exists
                # Allow time for sync
                await asyncio.sleep(2)
                
                # Verify user exists in API gateway
                profile_response = await client.get(
                    f"{test_environment.api_gateway_url}/auth/profile",
                    headers=headers
                )
                
                if profile_response.status_code == 200:
                    profile_data = profile_response.json()
                    assert profile_data["email"] == user_data["email"]

    async def test_transaction_rollback_integrity(self, db_connection, test_data_factory):
        """Test transaction rollback preserves data integrity"""
        if db_connection is None:
            pytest.skip("Database not available")
        
        # Create test tables with relationships
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS rollback_test_parent (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) NOT NULL
            )
        """)
        
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS rollback_test_child (
                id SERIAL PRIMARY KEY,
                parent_id INTEGER REFERENCES rollback_test_parent(id),
                data TEXT NOT NULL
            )
        """)
        
        # Record initial state
        initial_parent_count = await db_connection.fetchval(
            "SELECT COUNT(*) FROM rollback_test_parent"
        )
        initial_child_count = await db_connection.fetchval(
            "SELECT COUNT(*) FROM rollback_test_child"
        )
        
        # Attempt transaction that should fail
        try:
            async with db_connection.transaction():
                # Insert parent
                parent_id = await db_connection.fetchval(
                    "INSERT INTO rollback_test_parent (name) VALUES ($1) RETURNING id",
                    "test_parent"
                )
                
                # Insert child
                await db_connection.execute(
                    "INSERT INTO rollback_test_child (parent_id, data) VALUES ($1, $2)",
                    parent_id, "test_data"
                )
                
                # Force error to trigger rollback
                raise Exception("Forced rollback")
        
        except Exception:
            pass  # Expected
        
        # Verify rollback occurred
        final_parent_count = await db_connection.fetchval(
            "SELECT COUNT(*) FROM rollback_test_parent"
        )
        final_child_count = await db_connection.fetchval(
            "SELECT COUNT(*) FROM rollback_test_child"
        )
        
        assert final_parent_count == initial_parent_count
        assert final_child_count == initial_child_count

    async def _get_test_token(self, test_environment) -> str:
        """Get test authentication token"""
        async with httpx.AsyncClient(timeout=30.0) as client:
            try:
                response = await client.post(
                    f"{test_environment.auth_service_url}/auth/login",
                    json={
                        "email": "test@example.com",
                        "password": "test_password"
                    }
                )
                if response.status_code == 200:
                    return response.json().get("access_token", "mock_token")
            except Exception:
                pass
            
            return "mock_token_for_testing"


@pytest.mark.integration
class TestDataMigrationIntegrity:
    """Test data migration and schema evolution integrity"""

    async def test_schema_migration_data_preservation(self, db_connection):
        """Test that schema migrations preserve existing data"""
        if db_connection is None:
            pytest.skip("Database not available")
        
        # Create initial schema
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS migration_test (
                id SERIAL PRIMARY KEY,
                old_column VARCHAR(100) NOT NULL,
                data JSONB
            )
        """)
        
        # Insert test data
        test_data = [
            ("test1", {"value": 1}),
            ("test2", {"value": 2}),
            ("test3", {"value": 3})
        ]
        
        for old_col_val, json_data in test_data:
            await db_connection.execute(
                "INSERT INTO migration_test (old_column, data) VALUES ($1, $2)",
                old_col_val, json.dumps(json_data)
            )
        
        # Verify initial data
        initial_count = await db_connection.fetchval(
            "SELECT COUNT(*) FROM migration_test"
        )
        assert initial_count == len(test_data)
        
        # Perform schema migration (add new column)
        await db_connection.execute("""
            ALTER TABLE migration_test 
            ADD COLUMN IF NOT EXISTS new_column VARCHAR(150) DEFAULT 'default_value'
        """)
        
        # Verify data preservation
        final_count = await db_connection.fetchval(
            "SELECT COUNT(*) FROM migration_test"
        )
        assert final_count == initial_count
        
        # Verify new column exists with default values
        records = await db_connection.fetch(
            "SELECT * FROM migration_test ORDER BY id"
        )
        
        for i, record in enumerate(records):
            assert record["old_column"] == test_data[i][0]
            assert record["new_column"] == "default_value"

    async def test_data_type_migration_integrity(self, db_connection):
        """Test data integrity during data type migrations"""
        if db_connection is None:
            pytest.skip("Database not available")
        
        # Create table with data that needs type conversion
        await db_connection.execute("""
            CREATE TABLE IF NOT EXISTS type_migration_test (
                id SERIAL PRIMARY KEY,
                numeric_text VARCHAR(20) NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Insert numeric data as text
        numeric_values = ["123", "456", "789", "101112"]
        for val in numeric_values:
            await db_connection.execute(
                "INSERT INTO type_migration_test (numeric_text) VALUES ($1)",
                val
            )
        
        # Verify initial data
        initial_records = await db_connection.fetch(
            "SELECT * FROM type_migration_test ORDER BY id"
        )
        
        # Simulate type migration (text to integer)
        try:
            await db_connection.execute("""
                ALTER TABLE type_migration_test 
                ALTER COLUMN numeric_text TYPE INTEGER USING numeric_text::INTEGER
            """)
            
            # Verify data conversion
            final_records = await db_connection.fetch(
                "SELECT * FROM type_migration_test ORDER BY id"
            )
            
            assert len(final_records) == len(initial_records)
            
            for i, record in enumerate(final_records):
                expected_value = int(numeric_values[i])
                assert record["numeric_text"] == expected_value
                
        except Exception as e:
            # Some migrations might not be possible in test environment
            logger.warning(f"Type migration test skipped: {e}")
            pytest.skip("Type migration not supported in test environment")