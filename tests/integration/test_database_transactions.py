"""
Integration tests for database transaction management.
Tests ACID properties, isolation levels, and transaction boundaries.
"""

import pytest
import asyncio
import asyncpg
import httpx
from typing import Dict, Any, List
from datetime import datetime
from tests.fixtures.factories import TestDataFactory
from tests.conftest import skip_if_not_integration

@pytest.mark.integration
@pytest.mark.database
@pytest.mark.asyncio
class TestDatabaseTransactions:
    """Test database transaction patterns and ACID properties"""
    
    @pytest.fixture(autouse=True)
    def setup(self, test_environment):
        """Setup test environment"""
        self.test_env = test_environment
        self.factory = TestDataFactory()
        
        yield
    
    @skip_if_not_integration()
    async def test_acid_atomicity_single_transaction(self, db_connection: asyncpg.Connection):
        """Test atomicity - all operations in transaction succeed or fail together"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        workspace_data = self.factory.create_workspace()
        
        try:
            # Start transaction
            async with db_connection.transaction():
                # Insert user
                user_id = await db_connection.fetchval(
                    """
                    INSERT INTO users (email, username, first_name, last_name, hashed_password)
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING id
                    """,
                    user_data.email, user_data.username, user_data.first_name,
                    user_data.last_name, user_data.hashed_password
                )
                
                # Insert workspace
                workspace_id = await db_connection.fetchval(
                    """
                    INSERT INTO workspaces (name, description, owner_id)
                    VALUES ($1, $2, $3)
                    RETURNING id
                    """,
                    workspace_data.name, workspace_data.description, user_id
                )
                
                # Insert workspace membership
                await db_connection.execute(
                    """
                    INSERT INTO workspace_members (workspace_id, user_id, role)
                    VALUES ($1, $2, 'owner')
                    """,
                    workspace_id, user_id
                )
                
                # Verify data exists within transaction
                user_exists = await db_connection.fetchval(
                    "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
                    user_id
                )
                assert user_exists == True
                
                workspace_exists = await db_connection.fetchval(
                    "SELECT EXISTS(SELECT 1 FROM workspaces WHERE id = $1)",
                    workspace_id
                )
                assert workspace_exists == True
                
                membership_exists = await db_connection.fetchval(
                    "SELECT EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id = $1 AND user_id = $2)",
                    workspace_id, user_id
                )
                assert membership_exists == True
            
            # Verify data persists after transaction commit
            user_after_commit = await db_connection.fetchrow(
                "SELECT * FROM users WHERE id = $1", user_id
            )
            assert user_after_commit is not None
            assert user_after_commit["email"] == user_data.email
            
            workspace_after_commit = await db_connection.fetchrow(
                "SELECT * FROM workspaces WHERE id = $1", workspace_id
            )
            assert workspace_after_commit is not None
            assert workspace_after_commit["owner_id"] == user_id
            
        except Exception as e:
            pytest.fail(f"Transaction should have succeeded: {e}")
    
    @skip_if_not_integration()
    async def test_acid_atomicity_rollback_on_failure(self, db_connection: asyncpg.Connection):
        """Test atomicity - transaction rollback on failure"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        
        # Count existing users before transaction
        users_before = await db_connection.fetchval("SELECT COUNT(*) FROM users")
        
        with pytest.raises(Exception):
            async with db_connection.transaction():
                # Insert user (this should succeed)
                user_id = await db_connection.fetchval(
                    """
                    INSERT INTO users (email, username, first_name, last_name, hashed_password)
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING id
                    """,
                    user_data.email, user_data.username, user_data.first_name,
                    user_data.last_name, user_data.hashed_password
                )
                
                # Verify user was inserted within transaction
                user_exists = await db_connection.fetchval(
                    "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
                    user_id
                )
                assert user_exists == True
                
                # This will cause a constraint violation and rollback
                await db_connection.execute(
                    """
                    INSERT INTO users (email, username, first_name, last_name, hashed_password)
                    VALUES ($1, $2, $3, $4, $5)
                    """,
                    user_data.email,  # Duplicate email - should cause unique constraint violation
                    user_data.username + "_different",
                    user_data.first_name,
                    user_data.last_name,
                    user_data.hashed_password
                )
        
        # Verify rollback - no users should have been inserted
        users_after = await db_connection.fetchval("SELECT COUNT(*) FROM users")
        assert users_after == users_before
        
        # Verify the user from the failed transaction doesn't exist
        user_exists_after_rollback = await db_connection.fetchval(
            "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
            user_data.email
        )
        assert user_exists_after_rollback == False
    
    @skip_if_not_integration()
    async def test_acid_consistency_foreign_key_constraints(self, db_connection: asyncpg.Connection):
        """Test consistency - foreign key constraints are enforced"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Try to create workspace with non-existent owner
        workspace_data = self.factory.create_workspace()
        fake_user_id = "non-existent-user-id"
        
        with pytest.raises(Exception):  # Foreign key constraint violation
            await db_connection.execute(
                """
                INSERT INTO workspaces (name, description, owner_id)
                VALUES ($1, $2, $3)
                """,
                workspace_data.name, workspace_data.description, fake_user_id
            )
        
        # Verify no workspace was created
        workspace_exists = await db_connection.fetchval(
            "SELECT EXISTS(SELECT 1 FROM workspaces WHERE name = $1)",
            workspace_data.name
        )
        assert workspace_exists == False
    
    @skip_if_not_integration()
    async def test_acid_isolation_read_committed(self, test_environment):
        """Test isolation - read committed level prevents dirty reads"""
        if not test_environment.is_integration:
            pytest.skip("Integration test environment not available")
        
        # Create two separate connections to simulate concurrent transactions
        conn1 = await asyncpg.connect(test_environment.database_url)
        conn2 = await asyncpg.connect(test_environment.database_url)
        
        try:
            user_data = self.factory.create_user()
            
            # Transaction 1: Insert user but don't commit yet
            tx1 = conn1.transaction()
            await tx1.start()
            
            user_id = await conn1.fetchval(
                """
                INSERT INTO users (email, username, first_name, last_name, hashed_password)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                user_data.email, user_data.username, user_data.first_name,
                user_data.last_name, user_data.hashed_password
            )
            
            # Transaction 2: Try to read the uncommitted user (should not see it)
            user_visible_in_tx2 = await conn2.fetchval(
                "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
                user_id
            )
            assert user_visible_in_tx2 == False  # Dirty read prevented
            
            # Commit transaction 1
            await tx1.commit()
            
            # Now transaction 2 should see the committed user
            user_visible_after_commit = await conn2.fetchval(
                "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
                user_id
            )
            assert user_visible_after_commit == True
            
        finally:
            await conn1.close()
            await conn2.close()
    
    @skip_if_not_integration()
    async def test_acid_isolation_concurrent_updates(self, test_environment):
        """Test isolation with concurrent updates"""
        if not test_environment.is_integration:
            pytest.skip("Integration test environment not available")
        
        conn1 = await asyncpg.connect(test_environment.database_url)
        conn2 = await asyncpg.connect(test_environment.database_url)
        
        try:
            # Create a user first
            user_data = self.factory.create_user()
            user_id = await conn1.fetchval(
                """
                INSERT INTO users (email, username, first_name, last_name, hashed_password)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                user_data.email, user_data.username, user_data.first_name,
                user_data.last_name, user_data.hashed_password
            )
            
            # Start concurrent transactions
            tx1 = conn1.transaction()
            tx2 = conn2.transaction()
            await tx1.start()
            await tx2.start()
            
            # Transaction 1: Update first name
            await conn1.execute(
                "UPDATE users SET first_name = $1 WHERE id = $2",
                "UpdatedByTx1", user_id
            )
            
            # Transaction 2: Update last name (should not conflict)
            await conn2.execute(
                "UPDATE users SET last_name = $1 WHERE id = $2", 
                "UpdatedByTx2", user_id
            )
            
            # Commit both transactions
            await tx1.commit()
            await tx2.commit()
            
            # Verify both updates were applied
            final_user = await conn1.fetchrow(
                "SELECT first_name, last_name FROM users WHERE id = $1",
                user_id
            )
            
            assert final_user["first_name"] == "UpdatedByTx1"
            assert final_user["last_name"] == "UpdatedByTx2"
            
        finally:
            await conn1.close()
            await conn2.close()
    
    @skip_if_not_integration()
    async def test_acid_durability_after_commit(self, db_connection: asyncpg.Connection):
        """Test durability - committed changes survive system restart"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        
        # Insert user and commit
        user_id = await db_connection.fetchval(
            """
            INSERT INTO users (email, username, first_name, last_name, hashed_password)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING id
            """,
            user_data.email, user_data.username, user_data.first_name,
            user_data.last_name, user_data.hashed_password
        )
        
        # Close and reconnect to simulate restart
        await db_connection.close()
        
        # Reconnect with new connection
        new_connection = await asyncpg.connect(self.test_env.database_url)
        
        try:
            # Verify user still exists after "restart"
            user_after_restart = await new_connection.fetchrow(
                "SELECT * FROM users WHERE id = $1", user_id
            )
            
            assert user_after_restart is not None
            assert user_after_restart["email"] == user_data.email
            assert user_after_restart["username"] == user_data.username
            
        finally:
            await new_connection.close()
    
    @skip_if_not_integration()
    async def test_savepoint_partial_rollback(self, db_connection: asyncpg.Connection):
        """Test savepoints for partial rollback within transaction"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data1 = self.factory.create_user()
        user_data2 = self.factory.create_user()
        user_data3 = self.factory.create_user()
        
        async with db_connection.transaction():
            # Insert first user
            user_id1 = await db_connection.fetchval(
                """
                INSERT INTO users (email, username, first_name, last_name, hashed_password)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                user_data1.email, user_data1.username, user_data1.first_name,
                user_data1.last_name, user_data1.hashed_password
            )
            
            # Create savepoint
            savepoint = db_connection.transaction()
            await savepoint.start()
            
            try:
                # Insert second user
                user_id2 = await db_connection.fetchval(
                    """
                    INSERT INTO users (email, username, first_name, last_name, hashed_password)
                    VALUES ($1, $2, $3, $4, $5)
                    RETURNING id
                    """,
                    user_data2.email, user_data2.username, user_data2.first_name,
                    user_data2.last_name, user_data2.hashed_password
                )
                
                # This will fail due to duplicate email
                await db_connection.execute(
                    """
                    INSERT INTO users (email, username, first_name, last_name, hashed_password)
                    VALUES ($1, $2, $3, $4, $5)
                    """,
                    user_data2.email,  # Duplicate email
                    "different_username",
                    user_data2.first_name,
                    user_data2.last_name,
                    user_data2.hashed_password
                )
                
                await savepoint.commit()
                
            except Exception:
                # Rollback to savepoint
                await savepoint.rollback()
            
            # Insert third user after savepoint rollback
            user_id3 = await db_connection.fetchval(
                """
                INSERT INTO users (email, username, first_name, last_name, hashed_password)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                user_data3.email, user_data3.username, user_data3.first_name,
                user_data3.last_name, user_data3.hashed_password
            )
        
        # Verify results after transaction commit
        # User 1 should exist (before savepoint)
        user1_exists = await db_connection.fetchval(
            "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)", user_id1
        )
        assert user1_exists == True
        
        # User 3 should exist (after savepoint rollback)
        user3_exists = await db_connection.fetchval(
            "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)", user_id3
        )
        assert user3_exists == True
    
    @skip_if_not_integration()
    async def test_deadlock_detection_and_resolution(self, test_environment):
        """Test deadlock detection and automatic resolution"""
        if not test_environment.is_integration:
            pytest.skip("Integration test environment not available")
        
        conn1 = await asyncpg.connect(test_environment.database_url)
        conn2 = await asyncpg.connect(test_environment.database_url)
        
        try:
            # Create two users for deadlock scenario
            user_data1 = self.factory.create_user()
            user_data2 = self.factory.create_user()
            
            user_id1 = await conn1.fetchval(
                """
                INSERT INTO users (email, username, first_name, last_name, hashed_password)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                user_data1.email, user_data1.username, user_data1.first_name,
                user_data1.last_name, user_data1.hashed_password
            )
            
            user_id2 = await conn1.fetchval(
                """
                INSERT INTO users (email, username, first_name, last_name, hashed_password)
                VALUES ($1, $2, $3, $4, $5)
                RETURNING id
                """,
                user_data2.email, user_data2.username, user_data2.first_name,
                user_data2.last_name, user_data2.hashed_password
            )
            
            # Create potential deadlock scenario
            async def transaction1():
                async with conn1.transaction():
                    # Lock user1 first
                    await conn1.execute(
                        "SELECT * FROM users WHERE id = $1 FOR UPDATE",
                        user_id1
                    )
                    
                    # Small delay to allow transaction2 to start
                    await asyncio.sleep(0.1)
                    
                    # Then try to lock user2
                    await conn1.execute(
                        "SELECT * FROM users WHERE id = $1 FOR UPDATE",
                        user_id2
                    )
                    
                    await conn1.execute(
                        "UPDATE users SET first_name = 'Updated1' WHERE id = $1",
                        user_id1
                    )
            
            async def transaction2():
                async with conn2.transaction():
                    # Lock user2 first
                    await conn2.execute(
                        "SELECT * FROM users WHERE id = $1 FOR UPDATE",
                        user_id2
                    )
                    
                    # Small delay
                    await asyncio.sleep(0.1)
                    
                    # Then try to lock user1 (potential deadlock)
                    await conn2.execute(
                        "SELECT * FROM users WHERE id = $1 FOR UPDATE",
                        user_id1
                    )
                    
                    await conn2.execute(
                        "UPDATE users SET first_name = 'Updated2' WHERE id = $1",
                        user_id2
                    )
            
            # Run transactions concurrently
            results = await asyncio.gather(
                transaction1(),
                transaction2(),
                return_exceptions=True
            )
            
            # One transaction should succeed, one might fail due to deadlock
            exceptions = [r for r in results if isinstance(r, Exception)]
            successes = [r for r in results if not isinstance(r, Exception)]
            
            # At least one should succeed
            assert len(successes) >= 1
            
            # If deadlock occurred, should be detected and one transaction aborted
            deadlock_detected = any(
                "deadlock" in str(e).lower() for e in exceptions
            )
            
            if deadlock_detected:
                # Verify database is in consistent state after deadlock resolution
                final_users = await conn1.fetch(
                    "SELECT id, first_name FROM users WHERE id IN ($1, $2)",
                    user_id1, user_id2
                )
                
                # Should have both users, one potentially updated
                assert len(final_users) == 2
                
        finally:
            await conn1.close()
            await conn2.close()
    
    @skip_if_not_integration()
    async def test_long_running_transaction_timeout(self, db_connection: asyncpg.Connection):
        """Test long-running transaction timeout"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        user_data = self.factory.create_user()
        
        # Start transaction with timeout
        try:
            async with asyncio.timeout(5):  # 5 second timeout
                async with db_connection.transaction():
                    # Insert user
                    await db_connection.execute(
                        """
                        INSERT INTO users (email, username, first_name, last_name, hashed_password)
                        VALUES ($1, $2, $3, $4, $5)
                        """,
                        user_data.email, user_data.username, user_data.first_name,
                        user_data.last_name, user_data.hashed_password
                    )
                    
                    # Simulate long-running operation
                    await asyncio.sleep(10)  # This should timeout
                    
        except asyncio.TimeoutError:
            # Expected timeout
            pass
        
        # Verify transaction was rolled back due to timeout
        user_exists = await db_connection.fetchval(
            "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
            user_data.email
        )
        assert user_exists == False
    
    @skip_if_not_integration()
    async def test_optimistic_locking_with_version_control(self, db_connection: asyncpg.Connection):
        """Test optimistic locking using version numbers"""
        if db_connection is None:
            pytest.skip("Database connection not available")
        
        # Create user with version field
        user_data = self.factory.create_user()
        
        user_id = await db_connection.fetchval(
            """
            INSERT INTO users (email, username, first_name, last_name, hashed_password, version)
            VALUES ($1, $2, $3, $4, $5, 1)
            RETURNING id
            """,
            user_data.email, user_data.username, user_data.first_name,
            user_data.last_name, user_data.hashed_password
        )
        
        # Read user with current version
        current_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", user_id
        )
        current_version = current_user["version"]
        
        # Simulate concurrent update that increments version
        await db_connection.execute(
            """
            UPDATE users 
            SET first_name = 'ConcurrentUpdate', version = version + 1
            WHERE id = $1 AND version = $2
            """,
            user_id, current_version
        )
        
        # Try to update with stale version (should fail)
        rows_affected = await db_connection.fetchval(
            """
            UPDATE users 
            SET last_name = 'StaleUpdate', version = version + 1
            WHERE id = $1 AND version = $2
            RETURNING version
            """,
            user_id, current_version  # Stale version
        )
        
        # Update should fail (no rows affected) due to version mismatch
        assert rows_affected is None
        
        # Verify the concurrent update succeeded
        final_user = await db_connection.fetchrow(
            "SELECT * FROM users WHERE id = $1", user_id
        )
        
        assert final_user["first_name"] == "ConcurrentUpdate"
        assert final_user["last_name"] == user_data.last_name  # Not updated
        assert final_user["version"] == current_version + 1