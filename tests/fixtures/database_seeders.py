"""
Database seeders for test data.
Provides comprehensive test data seeding for all database entities.
"""

import asyncio
import asyncpg
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta
import json
import uuid
from tests.fixtures.factories import TestDataFactory
import logging

logger = logging.getLogger(__name__)

class DatabaseSeeder:
    """Main database seeder class"""
    
    def __init__(self, connection: asyncpg.Connection):
        self.connection = connection
        self.factory = TestDataFactory()
        self.seeded_data = {}
    
    async def seed_all(self, scale: str = "small") -> Dict[str, Any]:
        """Seed all tables with test data"""
        scales = {
            "small": {"users": 5, "workspaces": 3, "airtable_bases": 2},
            "medium": {"users": 50, "workspaces": 20, "airtable_bases": 15},
            "large": {"users": 500, "workspaces": 100, "airtable_bases": 75}
        }
        
        config = scales.get(scale, scales["small"])
        
        logger.info(f"Starting database seeding with scale: {scale}")
        
        try:
            async with self.connection.transaction():
                # Seed in dependency order
                await self.seed_users(config["users"])
                await self.seed_workspaces(config["workspaces"])
                await self.seed_airtable_bases(config["airtable_bases"])
                await self.seed_airtable_tables()
                await self.seed_airtable_records()
                await self.seed_user_sessions()
                await self.seed_audit_logs()
                
            logger.info("Database seeding completed successfully")
            return self.seeded_data
            
        except Exception as e:
            logger.error(f"Database seeding failed: {e}")
            raise
    
    async def seed_users(self, count: int = 5) -> List[Dict[str, Any]]:
        """Seed users table with test data"""
        logger.info(f"Seeding {count} users")
        
        users = []
        for i in range(count):
            user = self.factory.create_user(
                email=f"user{i+1}@example.com",
                first_name=f"User{i+1}",
                last_name="Test"
            )
            users.append(user)
        
        # Insert users
        await self.connection.executemany(
            """
            INSERT INTO users (id, email, first_name, last_name, username, hashed_password, is_active, is_verified, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            ON CONFLICT (email) DO NOTHING
            """,
            [
                (
                    user.id, user.email, user.first_name, user.last_name,
                    user.username, user.hashed_password, user.is_active,
                    user.is_verified, user.created_at, user.updated_at
                )
                for user in users
            ]
        )
        
        # Store for reference
        self.seeded_data["users"] = [
            {
                "id": user.id,
                "email": user.email,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "is_active": user.is_active
            }
            for user in users
        ]
        
        logger.info(f"Successfully seeded {len(users)} users")
        return self.seeded_data["users"]
    
    async def seed_workspaces(self, count: int = 3) -> List[Dict[str, Any]]:
        """Seed workspaces table with test data"""
        logger.info(f"Seeding {count} workspaces")
        
        if "users" not in self.seeded_data:
            await self.seed_users()
        
        users = self.seeded_data["users"]
        workspaces = []
        
        for i in range(count):
            owner = users[i % len(users)]  # Cycle through users
            workspace = self.factory.create_workspace(
                name=f"Test Workspace {i+1}",
                description=f"Test workspace {i+1} for development and testing",
                owner_id=owner["id"]
            )
            workspaces.append(workspace)
        
        # Insert workspaces
        await self.connection.executemany(
            """
            INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (id) DO NOTHING
            """,
            [
                (
                    ws.id, ws.name, ws.description, ws.owner_id,
                    ws.is_active, ws.created_at, ws.updated_at
                )
                for ws in workspaces
            ]
        )
        
        # Store for reference
        self.seeded_data["workspaces"] = [
            {
                "id": ws.id,
                "name": ws.name,
                "description": ws.description,
                "owner_id": ws.owner_id,
                "is_active": ws.is_active
            }
            for ws in workspaces
        ]
        
        logger.info(f"Successfully seeded {len(workspaces)} workspaces")
        return self.seeded_data["workspaces"]
    
    async def seed_airtable_bases(self, count: int = 2) -> List[Dict[str, Any]]:
        """Seed airtable_bases table with test data"""
        logger.info(f"Seeding {count} airtable bases")
        
        if "workspaces" not in self.seeded_data:
            await self.seed_workspaces()
        
        workspaces = self.seeded_data["workspaces"]
        bases = []
        
        for i in range(count):
            workspace = workspaces[i % len(workspaces)]  # Cycle through workspaces
            base_id = str(uuid.uuid4())
            
            # Create realistic Airtable base data
            base_data = {
                "id": base_id,
                "name": f"Test Base {i+1}",
                "workspace_id": workspace["id"],
                "airtable_base_id": f"app{''.join([chr(65 + (i % 26)) for _ in range(14)])}",
                "api_token": f"pat14.{''.join([chr(97 + (j % 26)) for j in range(40)])}",
                "is_active": True,
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow()
            }
            bases.append(base_data)
        
        # Insert airtable bases
        await self.connection.executemany(
            """
            INSERT INTO airtable_bases (id, name, workspace_id, airtable_base_id, api_token, is_active, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (id) DO NOTHING
            """,
            [
                (
                    base["id"], base["name"], base["workspace_id"],
                    base["airtable_base_id"], base["api_token"],
                    base["is_active"], base["created_at"], base["updated_at"]
                )
                for base in bases
            ]
        )
        
        # Store for reference
        self.seeded_data["airtable_bases"] = bases
        
        logger.info(f"Successfully seeded {len(bases)} airtable bases")
        return self.seeded_data["airtable_bases"]
    
    async def seed_airtable_tables(self) -> List[Dict[str, Any]]:
        """Seed airtable_tables with test data"""
        logger.info("Seeding airtable tables")
        
        if "airtable_bases" not in self.seeded_data:
            await self.seed_airtable_bases()
        
        bases = self.seeded_data["airtable_bases"]
        tables = []
        
        table_templates = [
            {"name": "Contacts", "primary_field": "Name"},
            {"name": "Projects", "primary_field": "Project Name"},
            {"name": "Tasks", "primary_field": "Task Title"},
            {"name": "Events", "primary_field": "Event Name"},
        ]
        
        for base in bases:
            for i, template in enumerate(table_templates[:2]):  # 2 tables per base
                table_id = str(uuid.uuid4())
                table_data = {
                    "id": table_id,
                    "name": template["name"],
                    "base_id": base["id"],
                    "airtable_table_id": f"tbl{''.join([chr(65 + ((i * 7) % 26)) for _ in range(14)])}",
                    "primary_field": template["primary_field"],
                    "created_at": datetime.utcnow(),
                    "updated_at": datetime.utcnow()
                }
                tables.append(table_data)
        
        # Insert airtable tables
        await self.connection.executemany(
            """
            INSERT INTO airtable_tables (id, name, base_id, airtable_table_id, primary_field, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (id) DO NOTHING
            """,
            [
                (
                    table["id"], table["name"], table["base_id"],
                    table["airtable_table_id"], table["primary_field"],
                    table["created_at"], table["updated_at"]
                )
                for table in tables
            ]
        )
        
        # Store for reference
        self.seeded_data["airtable_tables"] = tables
        
        logger.info(f"Successfully seeded {len(tables)} airtable tables")
        return self.seeded_data["airtable_tables"]
    
    async def seed_airtable_records(self) -> List[Dict[str, Any]]:
        """Seed airtable_records with test data"""
        logger.info("Seeding airtable records")
        
        if "airtable_tables" not in self.seeded_data:
            await self.seed_airtable_tables()
        
        tables = self.seeded_data["airtable_tables"]
        records = []
        
        for table in tables:
            for i in range(5):  # 5 records per table
                record_id = str(uuid.uuid4())
                
                # Generate realistic field data based on table type
                if "Contacts" in table["name"]:
                    fields = {
                        "Name": f"Contact {i+1}",
                        "Email": f"contact{i+1}@example.com",
                        "Phone": f"+1-555-000{i:02d}",
                        "Status": "Active"
                    }
                elif "Projects" in table["name"]:
                    fields = {
                        "Project Name": f"Project {i+1}",
                        "Status": "In Progress",
                        "Start Date": datetime.utcnow().strftime("%Y-%m-%d"),
                        "Priority": ["High", "Medium", "Low"][i % 3]
                    }
                elif "Tasks" in table["name"]:
                    fields = {
                        "Task Title": f"Task {i+1}",
                        "Completed": i % 2 == 0,
                        "Due Date": (datetime.utcnow() + timedelta(days=i*7)).strftime("%Y-%m-%d"),
                        "Assignee": f"User {(i % 3) + 1}"
                    }
                else:
                    fields = {
                        "Name": f"Record {i+1}",
                        "Description": f"Test record {i+1} for table {table['name']}",
                        "Status": "Active"
                    }
                
                record_data = {
                    "id": record_id,
                    "table_id": table["id"],
                    "airtable_record_id": f"rec{''.join([chr(65 + ((i * 13) % 26)) for _ in range(14)])}",
                    "fields": json.dumps(fields),
                    "created_at": datetime.utcnow(),
                    "updated_at": datetime.utcnow()
                }
                records.append(record_data)
        
        # Insert airtable records
        await self.connection.executemany(
            """
            INSERT INTO airtable_records (id, table_id, airtable_record_id, fields, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (id) DO NOTHING
            """,
            [
                (
                    record["id"], record["table_id"], record["airtable_record_id"],
                    record["fields"], record["created_at"], record["updated_at"]
                )
                for record in records
            ]
        )
        
        # Store for reference (with parsed fields)
        self.seeded_data["airtable_records"] = [
            {
                **record,
                "fields": json.loads(record["fields"])
            }
            for record in records
        ]
        
        logger.info(f"Successfully seeded {len(records)} airtable records")
        return self.seeded_data["airtable_records"]
    
    async def seed_user_sessions(self) -> List[Dict[str, Any]]:
        """Seed user_sessions with test data"""
        logger.info("Seeding user sessions")
        
        if "users" not in self.seeded_data:
            await self.seed_users()
        
        users = self.seeded_data["users"][:3]  # Sessions for first 3 users
        sessions = []
        
        for user in users:
            # Create 2 sessions per user (current + expired)
            for i in range(2):
                session_id = str(uuid.uuid4())
                is_active = i == 0  # First session is active
                
                session_data = {
                    "id": session_id,
                    "user_id": user["id"],
                    "refresh_token": f"rt_{''.join([chr(97 + ((hash(session_id) + j) % 26)) for j in range(32)])}",
                    "expires_at": datetime.utcnow() + timedelta(days=7 if is_active else -1),
                    "is_active": is_active,
                    "ip_address": f"192.168.1.{(hash(session_id) % 254) + 1}",
                    "user_agent": "PyAirtable-Test/1.0",
                    "created_at": datetime.utcnow() - timedelta(hours=i*24),
                    "updated_at": datetime.utcnow()
                }
                sessions.append(session_data)
        
        # Insert user sessions
        await self.connection.executemany(
            """
            INSERT INTO user_sessions (id, user_id, refresh_token, expires_at, is_active, ip_address, user_agent, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (id) DO NOTHING
            """,
            [
                (
                    session["id"], session["user_id"], session["refresh_token"],
                    session["expires_at"], session["is_active"], session["ip_address"],
                    session["user_agent"], session["created_at"], session["updated_at"]
                )
                for session in sessions
            ]
        )
        
        # Store for reference
        self.seeded_data["user_sessions"] = sessions
        
        logger.info(f"Successfully seeded {len(sessions)} user sessions")
        return self.seeded_data["user_sessions"]
    
    async def seed_audit_logs(self) -> List[Dict[str, Any]]:
        """Seed audit_log with test data"""
        logger.info("Seeding audit logs")
        
        if "users" not in self.seeded_data:
            await self.seed_users()
        
        users = self.seeded_data["users"]
        audit_logs = []
        
        # Create audit logs for various operations
        operations = [
            ("users", "CREATE", None, {"email": "user@example.com", "is_active": True}),
            ("users", "UPDATE", {"email": "old@example.com"}, {"email": "new@example.com"}),
            ("workspaces", "CREATE", None, {"name": "New Workspace", "is_active": True}),
            ("airtable_bases", "DELETE", {"is_active": True}, {"is_active": False}),
        ]
        
        for user in users[:2]:  # Audit logs for first 2 users
            for table_name, action, old_values, new_values in operations:
                audit_id = str(uuid.uuid4())
                
                audit_data = {
                    "id": audit_id,
                    "table_name": table_name,
                    "record_id": str(uuid.uuid4()),  # Mock record ID
                    "action": action,
                    "old_values": json.dumps(old_values) if old_values else None,
                    "new_values": json.dumps(new_values) if new_values else None,
                    "user_id": user["id"],
                    "ip_address": f"192.168.1.{(hash(audit_id) % 254) + 1}",
                    "user_agent": "PyAirtable-Web/1.0",
                    "created_at": datetime.utcnow() - timedelta(days=hash(audit_id) % 30)
                }
                audit_logs.append(audit_data)
        
        # Insert audit logs
        await self.connection.executemany(
            """
            INSERT INTO audit_log (id, table_name, record_id, action, old_values, new_values, user_id, ip_address, user_agent, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            ON CONFLICT (id) DO NOTHING
            """,
            [
                (
                    log["id"], log["table_name"], log["record_id"], log["action"],
                    log["old_values"], log["new_values"], log["user_id"],
                    log["ip_address"], log["user_agent"], log["created_at"]
                )
                for log in audit_logs
            ]
        )
        
        # Store for reference
        self.seeded_data["audit_logs"] = audit_logs
        
        logger.info(f"Successfully seeded {len(audit_logs)} audit logs")
        return self.seeded_data["audit_logs"]
    
    async def clean_all(self) -> None:
        """Clean all seeded test data"""
        logger.info("Cleaning all seeded test data")
        
        try:
            async with self.connection.transaction():
                # Delete in reverse dependency order
                await self.connection.execute("DELETE FROM audit_log WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@example.com')")
                await self.connection.execute("DELETE FROM user_sessions WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@example.com')")
                await self.connection.execute("DELETE FROM airtable_records WHERE table_id IN (SELECT id FROM airtable_tables WHERE base_id IN (SELECT id FROM airtable_bases WHERE name LIKE 'Test Base%'))")
                await self.connection.execute("DELETE FROM airtable_tables WHERE base_id IN (SELECT id FROM airtable_bases WHERE name LIKE 'Test Base%')")
                await self.connection.execute("DELETE FROM airtable_bases WHERE name LIKE 'Test Base%'")
                await self.connection.execute("DELETE FROM workspaces WHERE name LIKE 'Test Workspace%'")
                await self.connection.execute("DELETE FROM users WHERE email LIKE '%@example.com'")
                
            logger.info("Successfully cleaned all seeded test data")
            self.seeded_data = {}
            
        except Exception as e:
            logger.error(f"Failed to clean seeded data: {e}")
            raise

class SpecializedSeeders:
    """Specialized seeders for specific test scenarios"""
    
    def __init__(self, connection: asyncpg.Connection):
        self.connection = connection
        self.factory = TestDataFactory()
    
    async def seed_performance_test_data(self, record_count: int = 10000) -> Dict[str, Any]:
        """Seed large amounts of data for performance testing"""
        logger.info(f"Seeding {record_count} records for performance testing")
        
        base_seeder = DatabaseSeeder(self.connection)
        await base_seeder.seed_users(10)
        await base_seeder.seed_workspaces(5)
        await base_seeder.seed_airtable_bases(3)
        await base_seeder.seed_airtable_tables()
        
        tables = base_seeder.seeded_data["airtable_tables"]
        
        # Generate large number of records
        batch_size = 1000
        total_inserted = 0
        
        for batch_start in range(0, record_count, batch_size):
            batch_end = min(batch_start + batch_size, record_count)
            batch_records = []
            
            for i in range(batch_start, batch_end):
                table = tables[i % len(tables)]
                record_id = str(uuid.uuid4())
                
                fields = {
                    "Name": f"Performance Test Record {i+1}",
                    "Index": i + 1,
                    "Batch": batch_start // batch_size + 1,
                    "Data": "x" * 100,  # 100 chars of data
                    "Created": datetime.utcnow().isoformat()
                }
                
                batch_records.append((
                    record_id,
                    table["id"],
                    f"rec{i:014d}",
                    json.dumps(fields),
                    datetime.utcnow(),
                    datetime.utcnow()
                ))
            
            await self.connection.executemany(
                """
                INSERT INTO airtable_records (id, table_id, airtable_record_id, fields, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6)
                """,
                batch_records
            )
            
            total_inserted += len(batch_records)
            if total_inserted % 5000 == 0:
                logger.info(f"Inserted {total_inserted} performance test records")
        
        logger.info(f"Successfully seeded {total_inserted} performance test records")
        return {"record_count": total_inserted, "tables": len(tables)}
    
    async def seed_security_test_data(self) -> Dict[str, Any]:
        """Seed data for security testing scenarios"""
        logger.info("Seeding security test data")
        
        # Create users with various security scenarios
        security_users = [
            {"email": "admin@example.com", "role": "admin", "is_active": True, "is_verified": True},
            {"email": "user@example.com", "role": "user", "is_active": True, "is_verified": True},
            {"email": "inactive@example.com", "role": "user", "is_active": False, "is_verified": True},
            {"email": "unverified@example.com", "role": "user", "is_active": True, "is_verified": False},
        ]
        
        for user_config in security_users:
            user = self.factory.create_user(**user_config)
            
            await self.connection.execute(
                """
                INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, is_verified, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                ON CONFLICT (email) DO NOTHING
                """,
                user.id, user.email, user.first_name, user.last_name,
                user.hashed_password, user.is_active, user.is_verified,
                user.created_at, user.updated_at
            )
        
        # Create expired and active sessions for security testing
        admin_user = await self.connection.fetchrow(
            "SELECT * FROM users WHERE email = 'admin@example.com'"
        )
        
        if admin_user:
            # Active session
            await self.connection.execute(
                """
                INSERT INTO user_sessions (id, user_id, refresh_token, expires_at, is_active, ip_address, user_agent, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                """,
                str(uuid.uuid4()), admin_user["id"], "active_token_123",
                datetime.utcnow() + timedelta(days=7), True, "192.168.1.100",
                "Security-Test/1.0", datetime.utcnow(), datetime.utcnow()
            )
            
            # Expired session
            await self.connection.execute(
                """
                INSERT INTO user_sessions (id, user_id, refresh_token, expires_at, is_active, ip_address, user_agent, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                """,
                str(uuid.uuid4()), admin_user["id"], "expired_token_123",
                datetime.utcnow() - timedelta(days=1), False, "192.168.1.100",
                "Security-Test/1.0", datetime.utcnow() - timedelta(days=2), datetime.utcnow()
            )
        
        logger.info("Successfully seeded security test data")
        return {"users": len(security_users), "sessions": 2}
    
    async def seed_integration_test_data(self) -> Dict[str, Any]:
        """Seed data for integration testing"""
        logger.info("Seeding integration test data")
        
        # Create a complete user journey dataset
        user = self.factory.create_user(
            email="integration@example.com",
            first_name="Integration",
            last_name="Test"
        )
        
        workspace = self.factory.create_workspace(
            name="Integration Test Workspace",
            description="Workspace for integration testing",
            owner_id=user.id
        )
        
        # Insert user and workspace
        await self.connection.execute(
            """
            INSERT INTO users (id, email, first_name, last_name, hashed_password, is_active, is_verified, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (email) DO NOTHING
            """,
            user.id, user.email, user.first_name, user.last_name,
            user.hashed_password, user.is_active, user.is_verified,
            user.created_at, user.updated_at
        )
        
        await self.connection.execute(
            """
            INSERT INTO workspaces (id, name, description, owner_id, is_active, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (id) DO NOTHING
            """,
            workspace.id, workspace.name, workspace.description,
            workspace.owner_id, workspace.is_active, workspace.created_at,
            workspace.updated_at
        )
        
        # Create Airtable base with realistic data
        base_id = str(uuid.uuid4())
        await self.connection.execute(
            """
            INSERT INTO airtable_bases (id, name, workspace_id, airtable_base_id, api_token, is_active, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
            base_id, "Integration Test Base", workspace.id,
            "appINTEGRATIONTEST", "pat14.integration_test_token",
            True, datetime.utcnow(), datetime.utcnow()
        )
        
        logger.info("Successfully seeded integration test data")
        return {
            "user": {"id": user.id, "email": user.email},
            "workspace": {"id": workspace.id, "name": workspace.name},
            "base": {"id": base_id, "name": "Integration Test Base"}
        }

# Convenience functions
async def seed_test_database(connection: asyncpg.Connection, scale: str = "small") -> Dict[str, Any]:
    """Convenience function to seed test database"""
    seeder = DatabaseSeeder(connection)
    return await seeder.seed_all(scale)

async def clean_test_database(connection: asyncpg.Connection) -> None:
    """Convenience function to clean test database"""
    seeder = DatabaseSeeder(connection)
    await seeder.clean_all()

async def seed_performance_data(connection: asyncpg.Connection, record_count: int = 10000) -> Dict[str, Any]:
    """Convenience function to seed performance test data"""
    seeder = SpecializedSeeders(connection)
    return await seeder.seed_performance_test_data(record_count)

async def seed_security_data(connection: asyncpg.Connection) -> Dict[str, Any]:
    """Convenience function to seed security test data"""
    seeder = SpecializedSeeders(connection)
    return await seeder.seed_security_test_data()

async def seed_integration_data(connection: asyncpg.Connection) -> Dict[str, Any]:
    """Convenience function to seed integration test data"""
    seeder = SpecializedSeeders(connection)
    return await seeder.seed_integration_test_data()