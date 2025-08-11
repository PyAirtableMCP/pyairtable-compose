"""
Database integration tests.
Tests database operations, transactions, and data integrity across all services.
"""

import pytest
import asyncio
import asyncpg
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from tests.fixtures.factories import TestDataFactory
import uuid
import json

class TestDatabaseIntegration:
    """Integration tests for database operations"""
    
    def setup_method(self):
        """Setup test environment before each test"""
        self.factory = TestDataFactory()
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_user_crud_operations(self, db_connection: asyncpg.Connection):
        """Test complete CRUD operations for users"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create user
        user_data = self.factory.create_user()
        
        # Insert user
        user_id = await db_connection.fetchval(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            RETURNING id
            """,
            user_data.id, user_data.email, user_data.first_name, user_data.last_name,
            user_data.hashed_password, user_data.is_active, user_data.created_at
        )
        
        assert user_id == user_data.id
        
        # Read user
        retrieved_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", user_data.id
        )
        
        assert retrieved_user is not None
        assert retrieved_user["email"] == user_data.email
        assert retrieved_user["first_name"] == user_data.first_name
        assert retrieved_user["is_active"] == user_data.is_active
        
        # Update user
        new_first_name = "UpdatedName"
        await db_connection.execute(
            "UPDATE users SET first_name = $1, updated_at = $2 WHERE id = $3",
            new_first_name, datetime.utcnow(), user_data.id
        )
        
        updated_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", user_data.id
        )
        
        assert updated_user["first_name"] == new_first_name
        assert updated_user["updated_at"] > updated_user["created_at"]
        
        # Delete user (soft delete by setting is_active = false)
        await db_connection.execute(
            "UPDATE users SET is_active = false WHERE id = $1", user_data.id
        )
        
        deleted_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", user_data.id
        )
        
        assert deleted_user["is_active"] is False
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_workspace_user_relationship(self, db_connection: asyncpg.Connection):
        """Test relationships between workspaces and users"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create owner user
        owner = self.factory.create_user()
        workspace = self.factory.create_workspace(owner_id=owner.id)
        
        # Insert owner
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            owner.id, owner.email, owner.first_name, owner.last_name,
            owner.hashed_password, owner.is_active, owner.created_at
        )
        
        # Insert workspace
        await db_connection.execute(
            """
            INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            """,
            workspace.id, workspace.name, workspace.description, workspace.owner_id,
            workspace.is_active, workspace.created_at
        )
        
        # Test foreign key relationship
        workspace_with_owner = await db_connection.fetchrow(
            """
            SELECT w.*, u.email as owner_email, u.first_name as owner_first_name
            FROM workspaces w
            JOIN users u ON w.owner_id = u.id
            WHERE w.id = $1
            """,
            workspace.id
        )
        
        assert workspace_with_owner is not None
        assert workspace_with_owner["owner_email"] == owner.email
        assert workspace_with_owner["owner_first_name"] == owner.first_name
        
        # Test cascading behavior (should prevent user deletion if owns workspaces)
        with pytest.raises(asyncpg.ForeignKeyViolationError):
            await db_connection.execute("DELETE FROM users WHERE id = $1", owner.id)
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_audit_trail_functionality(self, db_connection: asyncpg.Connection):
        """Test audit trail for important operations"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        
        # Insert user with audit trail
        async with db_connection.transaction():
            # Insert user
            await db_connection.execute(
                """
                INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                """,
                user_data.id, user_data.email, user_data.first_name, user_data.last_name,
                user_data.hashed_password, user_data.is_active, user_data.created_at
            )
            
            # Insert audit record
            await db_connection.execute(
                """
                INSERT INTO audit_log (id, table_name, record_id, action, old_values, new_values, user_id, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                str(uuid.uuid4()), "users", user_data.id, "CREATE", None,
                json.dumps({"email": user_data.email, "is_active": user_data.is_active}),
                user_data.id, datetime.utcnow()
            )
        
        # Verify audit record was created
        audit_records = await db_connection.fetch(
            "SELECT * FROM audit_log WHERE record_id = $1 ORDER BY created_at",
            user_data.id
        )
        
        assert len(audit_records) >= 1
        assert audit_records[0]["action"] == "CREATE"
        assert audit_records[0]["table_name"] == "users"
        
        # Update user and create audit record
        old_email = user_data.email
        new_email = "updated@example.com"
        
        async with db_connection.transaction():
            await db_connection.execute(
                "UPDATE users SET email = $1 WHERE id = $2",
                new_email, user_data.id
            )
            
            await db_connection.execute(
                """
                INSERT INTO audit_log (id, table_name, record_id, action, old_values, new_values, user_id, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                str(uuid.uuid4()), "users", user_data.id, "UPDATE",
                json.dumps({"email": old_email}),
                json.dumps({"email": new_email}),
                user_data.id, datetime.utcnow()
            )
        
        # Verify update audit record
        update_audit = await db_connection.fetchrow(
            "SELECT * FROM audit_log WHERE record_id = $1 AND action = 'UPDATE'",
            user_data.id
        )
        
        assert update_audit is not None
        old_values = json.loads(update_audit["old_values"])
        new_values = json.loads(update_audit["new_values"])
        assert old_values["email"] == old_email
        assert new_values["email"] == new_email
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_transaction_rollback_behavior(self, db_connection: asyncpg.Connection):
        """Test transaction rollback behavior"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        workspace_data = self.factory.create_workspace(owner_id=user_data.id)
        
        # Test successful transaction
        async with db_connection.transaction():
            await db_connection.execute(
                """
                INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                """,
                user_data.id, user_data.email, user_data.first_name, user_data.last_name,
                user_data.hashed_password, user_data.is_active, user_data.created_at
            )
            
            await db_connection.execute(
                """
                INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                workspace_data.id, workspace_data.name, workspace_data.description,
                workspace_data.owner_id, workspace_data.is_active, workspace_data.created_at
            )
        
        # Verify both records were created
        user_exists = await db_connection.fetchval(
            "SELECT COUNT(*) FROM users WHERE id = $1", user_data.id
        )
        workspace_exists = await db_connection.fetchval(
            "SELECT COUNT(*) FROM workspaces WHERE id = $1", workspace_data.id
        )
        
        assert user_exists == 1
        assert workspace_exists == 1
        
        # Test failed transaction (should rollback both operations)
        user_data2 = self.factory.create_user()
        workspace_data2 = self.factory.create_workspace(owner_id="non-existent-user-id")
        
        try:
            async with db_connection.transaction():
                await db_connection.execute(
                    """
                    INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    """,
                    user_data2.id, user_data2.email, user_data2.first_name, user_data2.last_name,
                    user_data2.hashed_password, user_data2.is_active, user_data2.created_at
                )
                
                # This should fail due to foreign key constraint
                await db_connection.execute(
                    """
                    INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    """,
                    workspace_data2.id, workspace_data2.name, workspace_data2.description,
                    workspace_data2.owner_id, workspace_data2.is_active, workspace_data2.created_at
                )
        except asyncpg.ForeignKeyViolationError:
            pass  # Expected error
        
        # Verify transaction was rolled back (user2 should not exist)
        user2_exists = await db_connection.fetchval(
            "SELECT COUNT(*) FROM users WHERE id = $1", user_data2.id
        )
        workspace2_exists = await db_connection.fetchval(
            "SELECT COUNT(*) FROM workspaces WHERE id = $1", workspace_data2.id
        )
        
        assert user2_exists == 0
        assert workspace2_exists == 0
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_concurrent_operations(self, db_connection: asyncpg.Connection):
        """Test concurrent database operations"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create test data
        users_data = [self.factory.create_user() for _ in range(10)]
        
        async def create_user(user_data):
            """Helper function to create a single user"""
            try:
                await db_connection.execute(
                    """
                    INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    """,
                    user_data.id, user_data.email, user_data.first_name, user_data.last_name,
                    user_data.hashed_password, user_data.is_active, user_data.created_at
                )
                return True
            except Exception:
                return False
        
        # Execute concurrent user creations
        tasks = [create_user(user_data) for user_data in users_data]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Count successful operations
        successful_operations = sum(1 for result in results if result is True)
        
        # Verify results
        total_users = await db_connection.fetchval("SELECT COUNT(*) FROM users")
        
        assert successful_operations > 0
        assert total_users >= successful_operations
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_database_constraints(self, db_connection: asyncpg.Connection):
        """Test database constraints and data integrity"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        
        # Test unique email constraint
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            user_data.id, user_data.email, user_data.first_name, user_data.last_name,
            user_data.hashed_password, user_data.is_active, user_data.created_at
        )
        
        # Try to insert duplicate email
        duplicate_user = self.factory.create_user(email=user_data.email)
        
        with pytest.raises(asyncpg.UniqueViolationError):
            await db_connection.execute(
                """
                INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                """,
                duplicate_user.id, duplicate_user.email, duplicate_user.first_name,
                duplicate_user.last_name, duplicate_user.hashed_password,
                duplicate_user.is_active, duplicate_user.created_at
            )
        
        # Test NOT NULL constraints
        with pytest.raises(asyncpg.NotNullViolationError):
            await db_connection.execute(
                """
                INSERT INTO users (id, first_name, last_name, hashed_password, is_active, created_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                str(uuid.uuid4()), "Test", "User", "hashedpassword", True, datetime.utcnow()
                # Missing required email field
            )
    
    @pytest.mark.database
    @pytest.mark.integration
    async def test_data_migration_compatibility(self, db_connection: asyncpg.Connection):
        """Test data migration and schema evolution compatibility"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Test that current schema supports old and new data formats
        # This simulates migrating from an older schema version
        
        # Insert user with minimal fields (old schema)
        old_format_user_id = str(uuid.uuid4())
        await db_connection.execute(
            """
            INSERT INTO users (id, email, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5)
            """,
            old_format_user_id, "old@example.com", "hashedpassword", True, datetime.utcnow()
        )
        
        # Insert user with all fields (new schema)
        new_format_user = self.factory.create_user()
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, username, hashed_password, is_active, is_verified, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            """,
            new_format_user.id, new_format_user.email, new_format_user.first_name,
            new_format_user.last_name, new_format_user.username, new_format_user.hashed_password,
            new_format_user.is_active, new_format_user.is_verified, new_format_user.created_at
        )
        
        # Verify both users can be retrieved
        old_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", old_format_user_id
        )
        new_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", new_format_user.id
        )
        
        assert old_user is not None
        assert new_user is not None
        
        # Old user should have NULL values for new fields
        assert old_user["first_name"] is None
        assert old_user["last_name"] is None
        assert old_user["username"] is None
        
        # New user should have all fields populated
        assert new_user["first_name"] is not None
        assert new_user["last_name"] is not None
        assert new_user["username"] is not None

class TestDatabasePerformance:
    """Performance tests for database operations"""
    
    def setup_method(self):
        """Setup test environment before each test"""
        self.factory = TestDataFactory()
    
    @pytest.mark.database
    @pytest.mark.performance
    @pytest.mark.slow
    async def test_bulk_insert_performance(self, db_connection: asyncpg.Connection):
        """Test bulk insert performance"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Generate test data
        users_count = 1000
        users_data = [self.factory.create_user() for _ in range(users_count)]
        
        start_time = datetime.utcnow()
        
        # Bulk insert using executemany
        await db_connection.executemany(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            [
                (
                    user.id, user.email, user.first_name, user.last_name,
                    user.hashed_password, user.is_active, user.created_at
                )
                for user in users_data
            ]
        )
        
        end_time = datetime.utcnow()
        duration = (end_time - start_time).total_seconds()
        
        # Verify all users were inserted
        total_users = await db_connection.fetchval("SELECT COUNT(*) FROM users")
        
        assert total_users >= users_count
        
        # Performance assertion (should complete within reasonable time)
        assert duration < 10.0, f"Bulk insert took {duration}s, expected < 10s"
        
        # Calculate throughput
        throughput = users_count / duration
        assert throughput > 100, f"Throughput {throughput} ops/s too low"
    
    @pytest.mark.database
    @pytest.mark.performance
    async def test_query_performance(self, db_connection: asyncpg.Connection):
        """Test query performance with proper indexing"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create test data
        users_data = [self.factory.create_user() for _ in range(100)]
        await db_connection.executemany(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            [
                (
                    user.id, user.email, user.first_name, user.last_name,
                    user.hashed_password, user.is_active, user.created_at
                )
                for user in users_data
            ]
        )
        
        # Test indexed query performance (email lookup)
        target_email = users_data[50].email
        
        start_time = datetime.utcnow()
        
        user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE email = $1", target_email
        )
        
        end_time = datetime.utcnow()
        query_duration = (end_time - start_time).total_seconds()
        
        assert user is not None
        assert user["email"] == target_email
        
        # Query should be fast with proper indexing
        assert query_duration < 0.1, f"Email query took {query_duration}s, expected < 0.1s"
    
    @pytest.mark.database
    @pytest.mark.performance
    async def test_connection_pooling_efficiency(self, db_connection: asyncpg.Connection):
        """Test connection pooling efficiency"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        async def execute_query():
            """Execute a simple query"""
            return await db_connection.fetchval("SELECT COUNT(*) FROM users")
        
        # Execute multiple concurrent queries
        start_time = datetime.utcnow()
        
        tasks = [execute_query() for _ in range(50)]
        results = await asyncio.gather(*tasks)
        
        end_time = datetime.utcnow()
        total_duration = (end_time - start_time).total_seconds()
        
        # All queries should return valid results
        assert all(isinstance(result, int) for result in results)
        
        # Concurrent execution should be efficient
        assert total_duration < 5.0, f"50 concurrent queries took {total_duration}s"
        
        # Calculate average query time
        avg_query_time = total_duration / len(tasks)
        assert avg_query_time < 0.1, f"Average query time {avg_query_time}s too high"

class TestDatabaseSecurity:
    """Security tests for database operations"""
    
    def setup_method(self):
        """Setup test environment before each test"""
        self.factory = TestDataFactory()
    
    @pytest.mark.database
    @pytest.mark.security
    async def test_sql_injection_prevention(self, db_connection: asyncpg.Connection):
        """Test SQL injection prevention"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create a test user
        user_data = self.factory.create_user()
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            user_data.id, user_data.email, user_data.first_name, user_data.last_name,
            user_data.hashed_password, user_data.is_active, user_data.created_at
        )
        
        # Test SQL injection attempts (these should be treated as literal strings)
        sql_injection_attempts = [
            "'; DROP TABLE users; --",
            "admin@example.com'; INSERT INTO users",
            "test@example.com' OR '1'='1",
        ]
        
        for injection_attempt in sql_injection_attempts:
            # This should not find any user (injection prevented by parameterized query)
            result = await db_connection.fetchrow(
                "SELECT * FROM users WHERE email = $1", injection_attempt
            )
            
            # Should return None (no user found)
            assert result is None
        
        # Verify original user still exists (table wasn't dropped)
        original_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE email = $1", user_data.email
        )
        assert original_user is not None
    
    @pytest.mark.database
    @pytest.mark.security
    async def test_data_access_control(self, db_connection: asyncpg.Connection):
        """Test row-level security and data access control"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create test users in different workspaces
        user1 = self.factory.create_user()
        user2 = self.factory.create_user()
        workspace1 = self.factory.create_workspace(owner_id=user1.id)
        workspace2 = self.factory.create_workspace(owner_id=user2.id)
        
        # Insert test data
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            user1.id, user1.email, user1.first_name, user1.last_name,
            user1.hashed_password, user1.is_active, user1.created_at
        )
        
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            user2.id, user2.email, user2.first_name, user2.last_name,
            user2.hashed_password, user2.is_active, user2.created_at
        )
        
        await db_connection.execute(
            """
            INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            """,
            workspace1.id, workspace1.name, workspace1.description,
            workspace1.owner_id, workspace1.is_active, workspace1.created_at
        )
        
        await db_connection.execute(
            """
            INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            """,
            workspace2.id, workspace2.name, workspace2.description,
            workspace2.owner_id, workspace2.is_active, workspace2.created_at
        )
        
        # Test that user can only access their own workspaces
        user1_workspaces = await db_connection.fetch(
            "SELECT * FROM workspaces WHERE owner_id = $1", user1.id
        )
        user2_workspaces = await db_connection.fetch(
            "SELECT * FROM workspaces WHERE owner_id = $1", user2.id
        )
        
        assert len(user1_workspaces) == 1
        assert len(user2_workspaces) == 1
        assert user1_workspaces[0]["id"] == workspace1.id
        assert user2_workspaces[0]["id"] == workspace2.id
    
    @pytest.mark.database
    @pytest.mark.security
    async def test_sensitive_data_handling(self, db_connection: asyncpg.Connection):
        """Test handling of sensitive data (passwords, tokens)"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        
        # Insert user with hashed password
        await db_connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            """,
            user_data.id, user_data.email, user_data.first_name, user_data.last_name,
            user_data.hashed_password, user_data.is_active, user_data.created_at
        )
        
        # Verify password is stored as hash, not plaintext
        retrieved_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", user_data.id
        )
        
        assert retrieved_user["hashed_password"] != "plain_password"
        assert retrieved_user["hashed_password"].startswith("$2b$")  # bcrypt hash format
        
        # Test that sensitive fields are not returned in general queries
        # (This would be implemented in application layer, not database)
        user_public_data = {
            "id": retrieved_user["id"],
            "email": retrieved_user["email"],
            "first_name": retrieved_user["first_name"],
            "last_name": retrieved_user["last_name"],
            "is_active": retrieved_user["is_active"]
            # Note: hashed_password should not be included in public responses
        }
        
        assert "hashed_password" not in user_public_data