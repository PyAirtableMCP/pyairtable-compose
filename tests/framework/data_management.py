"""
Test Data Management and Database Utilities
===========================================

This module provides comprehensive test data management, database state validation,
cleanup utilities, and test data factories for the PyAirtable integration testing framework.
"""

import asyncio
import json
import logging
import random
import string
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Union
import uuid
from dataclasses import dataclass, field
from contextlib import asynccontextmanager

import asyncpg
import redis.asyncio as redis
from faker import Faker

from .test_config import TestFrameworkConfig, get_config

logger = logging.getLogger(__name__)

@dataclass
class TestDataCleanupTask:
    """Represents a cleanup task for test data"""
    task_id: str
    resource_type: str  # database, redis, airtable, file
    resource_identifier: str
    cleanup_function: str
    metadata: Dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.now)

class DatabaseStateValidator:
    """Validates and manages database state during testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.connection_pool: Optional[asyncpg.Pool] = None
        self.snapshots: Dict[str, Dict[str, Any]] = {}
        
    async def __aenter__(self):
        """Initialize database connection"""
        try:
            self.connection_pool = await asyncpg.create_pool(
                host=self.config.database.host,
                port=self.config.database.port,
                database=self.config.database.database,
                user=self.config.database.username,
                password=self.config.database.password,
                timeout=self.config.database.connection_timeout,
                min_size=1,
                max_size=5
            )
            logger.info("Database connection pool initialized")
        except Exception as e:
            logger.error(f"Failed to initialize database connection: {e}")
            raise
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Close database connection"""
        if self.connection_pool:
            await self.connection_pool.close()
            logger.info("Database connection pool closed")
    
    async def create_snapshot(self, snapshot_name: str, tables: List[str] = None) -> Dict[str, Any]:
        """Create a snapshot of database state"""
        snapshot_data = {
            "name": snapshot_name,
            "timestamp": datetime.now().isoformat(),
            "tables": {}
        }
        
        try:
            async with self.connection_pool.acquire() as conn:
                # Get list of tables if not provided
                if tables is None:
                    tables_query = """
                        SELECT table_name 
                        FROM information_schema.tables 
                        WHERE table_schema = 'public' 
                        AND table_type = 'BASE TABLE'
                    """
                    table_records = await conn.fetch(tables_query)
                    tables = [record['table_name'] for record in table_records]
                
                # Snapshot each table
                for table in tables:
                    try:
                        # Get row count
                        count_query = f"SELECT COUNT(*) as count FROM {table}"
                        count_result = await conn.fetchrow(count_query)
                        row_count = count_result['count']
                        
                        # Get sample data (first 100 rows for validation)
                        sample_query = f"SELECT * FROM {table} LIMIT 100"
                        sample_rows = await conn.fetch(sample_query)
                        
                        # Get table schema
                        schema_query = """
                            SELECT column_name, data_type, is_nullable
                            FROM information_schema.columns
                            WHERE table_name = $1
                            ORDER BY ordinal_position
                        """
                        schema_rows = await conn.fetch(schema_query, table)
                        
                        snapshot_data["tables"][table] = {
                            "row_count": row_count,
                            "sample_data": [dict(row) for row in sample_rows],
                            "schema": [dict(row) for row in schema_rows]
                        }
                        
                    except Exception as e:
                        logger.warning(f"Failed to snapshot table {table}: {e}")
                        snapshot_data["tables"][table] = {
                            "error": str(e)
                        }
        
        except Exception as e:
            logger.error(f"Failed to create database snapshot: {e}")
            raise
        
        self.snapshots[snapshot_name] = snapshot_data
        logger.info(f"Database snapshot '{snapshot_name}' created with {len(snapshot_data['tables'])} tables")
        
        return snapshot_data
    
    async def compare_snapshots(self, before_snapshot: str, after_snapshot: str) -> Dict[str, Any]:
        """Compare two database snapshots"""
        if before_snapshot not in self.snapshots or after_snapshot not in self.snapshots:
            raise ValueError("One or both snapshots not found")
        
        before = self.snapshots[before_snapshot]
        after = self.snapshots[after_snapshot]
        
        comparison = {
            "before_snapshot": before_snapshot,
            "after_snapshot": after_snapshot,
            "timestamp": datetime.now().isoformat(),
            "changes": {},
            "summary": {
                "tables_added": [],
                "tables_removed": [],
                "tables_modified": [],
                "total_row_changes": 0
            }
        }
        
        # Compare tables
        before_tables = set(before["tables"].keys())
        after_tables = set(after["tables"].keys())
        
        # New tables
        comparison["summary"]["tables_added"] = list(after_tables - before_tables)
        
        # Removed tables
        comparison["summary"]["tables_removed"] = list(before_tables - after_tables)
        
        # Modified tables
        common_tables = before_tables & after_tables
        
        for table in common_tables:
            before_table = before["tables"][table]
            after_table = after["tables"][table]
            
            if "error" in before_table or "error" in after_table:
                continue
            
            before_count = before_table["row_count"]
            after_count = after_table["row_count"]
            
            if before_count != after_count:
                row_change = after_count - before_count
                comparison["changes"][table] = {
                    "row_count_before": before_count,
                    "row_count_after": after_count,
                    "row_change": row_change
                }
                comparison["summary"]["tables_modified"].append(table)
                comparison["summary"]["total_row_changes"] += abs(row_change)
        
        logger.info(f"Snapshot comparison completed: {len(comparison['summary']['tables_modified'])} tables modified")
        
        return comparison
    
    async def validate_database_integrity(self) -> Dict[str, Any]:
        """Validate database integrity and constraints"""
        validation_results = {
            "timestamp": datetime.now().isoformat(),
            "checks": {},
            "issues_found": [],
            "overall_status": "passed"
        }
        
        try:
            async with self.connection_pool.acquire() as conn:
                # Check foreign key constraints
                fk_violations_query = """
                    SELECT 
                        tc.table_name,
                        tc.constraint_name,
                        kcu.column_name,
                        ccu.table_name AS foreign_table_name,
                        ccu.column_name AS foreign_column_name
                    FROM information_schema.table_constraints AS tc
                    JOIN information_schema.key_column_usage AS kcu
                        ON tc.constraint_name = kcu.constraint_name
                    JOIN information_schema.constraint_column_usage AS ccu
                        ON ccu.constraint_name = tc.constraint_name
                    WHERE constraint_type = 'FOREIGN KEY'
                """
                
                fk_constraints = await conn.fetch(fk_violations_query)
                validation_results["checks"]["foreign_key_constraints"] = len(fk_constraints)
                
                # Check for orphaned records (basic check)
                orphaned_records = 0
                for constraint in fk_constraints:
                    try:
                        orphan_query = f"""
                            SELECT COUNT(*) as count
                            FROM {constraint['table_name']} t1
                            LEFT JOIN {constraint['foreign_table_name']} t2
                                ON t1.{constraint['column_name']} = t2.{constraint['foreign_column_name']}
                            WHERE t1.{constraint['column_name']} IS NOT NULL
                                AND t2.{constraint['foreign_column_name']} IS NULL
                        """
                        result = await conn.fetchrow(orphan_query)
                        orphan_count = result['count']
                        
                        if orphan_count > 0:
                            orphaned_records += orphan_count
                            validation_results["issues_found"].append({
                                "type": "orphaned_records",
                                "table": constraint['table_name'],
                                "constraint": constraint['constraint_name'],
                                "count": orphan_count
                            })
                    except Exception as e:
                        logger.warning(f"Failed to check constraint {constraint['constraint_name']}: {e}")
                
                validation_results["checks"]["orphaned_records"] = orphaned_records
                
                # Check for duplicate primary keys (shouldn't happen but good to verify)
                tables_query = """
                    SELECT table_name 
                    FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_type = 'BASE TABLE'
                """
                tables = await conn.fetch(tables_query)
                
                duplicate_pks = 0
                for table_record in tables:
                    table_name = table_record['table_name']
                    try:
                        # Get primary key columns
                        pk_query = """
                            SELECT kcu.column_name
                            FROM information_schema.table_constraints tc
                            JOIN information_schema.key_column_usage kcu
                                ON tc.constraint_name = kcu.constraint_name
                            WHERE tc.table_name = $1
                                AND tc.constraint_type = 'PRIMARY KEY'
                        """
                        pk_columns = await conn.fetch(pk_query, table_name)
                        
                        if pk_columns:
                            pk_column_names = [col['column_name'] for col in pk_columns]
                            pk_columns_str = ', '.join(pk_column_names)
                            
                            duplicate_query = f"""
                                SELECT {pk_columns_str}, COUNT(*) as count
                                FROM {table_name}
                                GROUP BY {pk_columns_str}
                                HAVING COUNT(*) > 1
                            """
                            duplicates = await conn.fetch(duplicate_query)
                            
                            if duplicates:
                                duplicate_pks += len(duplicates)
                                validation_results["issues_found"].append({
                                    "type": "duplicate_primary_keys",
                                    "table": table_name,
                                    "count": len(duplicates)
                                })
                    except Exception as e:
                        logger.warning(f"Failed to check primary keys for table {table_name}: {e}")
                
                validation_results["checks"]["duplicate_primary_keys"] = duplicate_pks
                
                # Overall status
                if validation_results["issues_found"]:
                    validation_results["overall_status"] = "issues_found"
        
        except Exception as e:
            logger.error(f"Database integrity validation failed: {e}")
            validation_results["overall_status"] = "error"
            validation_results["error"] = str(e)
        
        return validation_results
    
    async def cleanup_test_data(self, pattern: str = "test_%") -> Dict[str, Any]:
        """Clean up test data based on naming patterns"""
        cleanup_results = {
            "timestamp": datetime.now().isoformat(),
            "tables_cleaned": [],
            "rows_deleted": 0,
            "errors": []
        }
        
        try:
            async with self.connection_pool.acquire() as conn:
                # Get all tables
                tables_query = """
                    SELECT table_name 
                    FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_type = 'BASE TABLE'
                """
                tables = await conn.fetch(tables_query)
                
                for table_record in tables:
                    table_name = table_record['table_name']
                    
                    try:
                        # Check if table has columns that might contain test identifiers
                        columns_query = """
                            SELECT column_name, data_type
                            FROM information_schema.columns
                            WHERE table_name = $1
                            AND (column_name ILIKE '%session%' 
                                OR column_name ILIKE '%id%'
                                OR column_name ILIKE '%name%'
                                OR data_type = 'text'
                                OR data_type LIKE '%char%')
                        """
                        columns = await conn.fetch(columns_query, table_name)
                        
                        # Try to clean test data from text/varchar columns
                        for column in columns:
                            column_name = column['column_name']
                            
                            delete_query = f"""
                                DELETE FROM {table_name}
                                WHERE {column_name}::text LIKE $1
                            """
                            
                            result = await conn.execute(delete_query, pattern)
                            deleted_count = int(result.split()[-1]) if result.split()[-1].isdigit() else 0
                            
                            if deleted_count > 0:
                                cleanup_results["rows_deleted"] += deleted_count
                                if table_name not in cleanup_results["tables_cleaned"]:
                                    cleanup_results["tables_cleaned"].append(table_name)
                                
                                logger.info(f"Cleaned {deleted_count} test rows from {table_name}.{column_name}")
                    
                    except Exception as e:
                        error_msg = f"Failed to clean table {table_name}: {e}"
                        logger.warning(error_msg)
                        cleanup_results["errors"].append(error_msg)
        
        except Exception as e:
            logger.error(f"Test data cleanup failed: {e}")
            cleanup_results["errors"].append(str(e))
        
        logger.info(f"Test data cleanup completed: {cleanup_results['rows_deleted']} rows deleted from {len(cleanup_results['tables_cleaned'])} tables")
        
        return cleanup_results

class RedisStateManager:
    """Manages Redis state for testing"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.redis_client: Optional[redis.Redis] = None
        self.test_keys: List[str] = []
    
    async def __aenter__(self):
        """Initialize Redis connection"""
        try:
            # Parse Redis URL from config
            redis_url = getattr(self.config, 'redis_url', 'redis://localhost:6379')
            self.redis_client = redis.from_url(redis_url, decode_responses=True)
            
            # Test connection
            await self.redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Close Redis connection"""
        if self.redis_client:
            await self.redis_client.close()
            logger.info("Redis connection closed")
    
    async def create_test_session(self, session_id: str, data: Dict[str, Any]) -> str:
        """Create a test session in Redis"""
        session_key = f"test:session:{session_id}"
        
        try:
            # Store session data
            await self.redis_client.hset(session_key, mapping=data)
            
            # Set expiration (1 hour)
            await self.redis_client.expire(session_key, 3600)
            
            # Track for cleanup
            self.test_keys.append(session_key)
            
            logger.info(f"Test session created: {session_key}")
            return session_key
        
        except Exception as e:
            logger.error(f"Failed to create test session: {e}")
            raise
    
    async def get_session_data(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session data from Redis"""
        session_key = f"test:session:{session_id}"
        
        try:
            data = await self.redis_client.hgetall(session_key)
            return data if data else None
        except Exception as e:
            logger.error(f"Failed to get session data: {e}")
            return None
    
    async def cleanup_test_keys(self) -> int:
        """Clean up all test keys created during testing"""
        deleted_count = 0
        
        try:
            # Clean up tracked keys
            if self.test_keys:
                deleted_count = await self.redis_client.delete(*self.test_keys)
                self.test_keys.clear()
            
            # Clean up any remaining test keys by pattern
            test_pattern_keys = await self.redis_client.keys("test:*")
            if test_pattern_keys:
                pattern_deleted = await self.redis_client.delete(*test_pattern_keys)
                deleted_count += pattern_deleted
            
            logger.info(f"Cleaned up {deleted_count} Redis test keys")
        
        except Exception as e:
            logger.error(f"Failed to cleanup Redis test keys: {e}")
        
        return deleted_count

class TestDataFactory:
    """Factory for generating test data"""
    
    def __init__(self, locale: str = 'en_US'):
        self.faker = Faker(locale)
        self.session_counter = 0
    
    def generate_user_data(self) -> Dict[str, Any]:
        """Generate realistic user test data"""
        return {
            "id": str(uuid.uuid4()),
            "email": self.faker.email(),
            "first_name": self.faker.first_name(),
            "last_name": self.faker.last_name(),
            "username": self.faker.user_name(),
            "phone": self.faker.phone_number(),
            "address": {
                "street": self.faker.street_address(),
                "city": self.faker.city(),
                "state": self.faker.state(),
                "zip_code": self.faker.zipcode(),
                "country": self.faker.country_code()
            },
            "created_at": self.faker.date_time_between(start_date='-1y').isoformat(),
            "is_active": self.faker.boolean(chance_of_getting_true=80),
            "metadata": {
                "last_login": self.faker.date_time_between(start_date='-30d').isoformat(),
                "login_count": self.faker.random_int(min=1, max=100),
                "preferences": {
                    "theme": self.faker.random_element(elements=["light", "dark", "auto"]),
                    "language": self.faker.language_code(),
                    "notifications": self.faker.boolean()
                }
            }
        }
    
    def generate_session_data(self, user_id: str = None) -> Dict[str, Any]:
        """Generate session test data"""
        self.session_counter += 1
        
        return {
            "session_id": f"test_session_{self.session_counter}_{uuid.uuid4().hex[:8]}",
            "user_id": user_id or str(uuid.uuid4()),
            "created_at": datetime.now().isoformat(),
            "expires_at": (datetime.now() + timedelta(hours=24)).isoformat(),
            "ip_address": self.faker.ipv4(),
            "user_agent": self.faker.user_agent(),
            "metadata": {
                "login_method": self.faker.random_element(elements=["password", "oauth", "sso"]),
                "device_type": self.faker.random_element(elements=["desktop", "mobile", "tablet"]),
                "location": {
                    "country": self.faker.country_code(),
                    "city": self.faker.city(),
                    "timezone": self.faker.timezone()
                }
            }
        }
    
    def generate_airtable_record_data(self, table_type: str = "generic") -> Dict[str, Any]:
        """Generate Airtable record test data"""
        base_data = {
            "id": f"rec{self.faker.lexify(text='???????????????')}",
            "created_time": self.faker.date_time_between(start_date='-1y').isoformat(),
            "fields": {}
        }
        
        if table_type == "contacts":
            base_data["fields"] = {
                "Name": self.faker.name(),
                "Email": self.faker.email(),
                "Phone": self.faker.phone_number(),
                "Company": self.faker.company(),
                "Status": self.faker.random_element(elements=["Active", "Inactive", "Pending"]),
                "Notes": self.faker.text(max_nb_chars=200)
            }
        elif table_type == "projects":
            base_data["fields"] = {
                "Project Name": self.faker.catch_phrase(),
                "Description": self.faker.text(max_nb_chars=300),
                "Status": self.faker.random_element(elements=["Planning", "In Progress", "Completed", "On Hold"]),
                "Budget": self.faker.random_int(min=1000, max=100000),
                "Start Date": self.faker.date_between(start_date='-6m', end_date='today').isoformat(),
                "End Date": self.faker.date_between(start_date='today', end_date='+6m').isoformat(),
                "Priority": self.faker.random_element(elements=["Low", "Medium", "High", "Critical"])
            }
        elif table_type == "tasks":
            base_data["fields"] = {
                "Task Name": self.faker.sentence(nb_words=4),
                "Description": self.faker.text(max_nb_chars=150),
                "Assignee": self.faker.name(),
                "Status": self.faker.random_element(elements=["To Do", "In Progress", "Review", "Done"]),
                "Due Date": self.faker.date_between(start_date='today', end_date='+30d').isoformat(),
                "Estimated Hours": self.faker.random_int(min=1, max=40),
                "Tags": self.faker.random_elements(
                    elements=["urgent", "bug", "feature", "maintenance", "documentation"],
                    length=self.faker.random_int(min=1, max=3),
                    unique=True
                )
            }
        else:
            # Generic record
            base_data["fields"] = {
                "Name": self.faker.word(),
                "Value": self.faker.random_int(min=1, max=1000),
                "Category": self.faker.random_element(elements=["A", "B", "C", "D"]),
                "Description": self.faker.sentence(),
                "Active": self.faker.boolean()
            }
        
        return base_data
    
    def generate_chat_message_data(self, role: str = "user") -> Dict[str, Any]:
        """Generate chat message test data"""
        message_templates = {
            "user": [
                "Hello, can you help me with my Airtable data?",
                "Show me all the tables in my base",
                "What records are in the {} table?",
                "Can you analyze the data in {} and provide insights?",
                "Create a summary report for project {}",
                "How many {} do I have in total?",
                "Update the status of {} to completed",
                "What's the average {} across all records?"
            ],
            "assistant": [
                "I'd be happy to help you with your Airtable data. Let me analyze your base.",
                "I can see {} tables in your base. Here are the details:",
                "Based on your data, I found {} records. Here's what I discovered:",
                "I've analyzed your {} table and here are my insights:",
                "I'll create a summary report for you right away.",
                "Let me calculate those totals for you.",
                "I've successfully updated the record status.",
                "I've calculated the average and here are the results:"
            ]
        }
        
        template = self.faker.random_element(elements=message_templates[role])
        
        # Fill in placeholders with realistic data
        if "{}" in template:
            if "table" in template.lower():
                replacement = self.faker.random_element(elements=["Projects", "Contacts", "Tasks", "Inventory"])
            elif "project" in template.lower():
                replacement = self.faker.catch_phrase()
            else:
                replacement = self.faker.word()
            
            template = template.format(replacement)
        
        return {
            "role": role,
            "content": template,
            "timestamp": datetime.now().isoformat(),
            "metadata": {
                "message_id": str(uuid.uuid4()),
                "session_id": f"test_session_{uuid.uuid4().hex[:8]}",
                "user_id": str(uuid.uuid4()) if role == "user" else "assistant"
            }
        }
    
    def generate_api_test_payload(self, endpoint_type: str) -> Dict[str, Any]:
        """Generate API test payloads"""
        if endpoint_type == "chat":
            return {
                "messages": [
                    self.generate_chat_message_data("user")
                ],
                "session_id": f"test_session_{uuid.uuid4().hex[:8]}",
                "options": {
                    "temperature": 0.7,
                    "max_tokens": 1000,
                    "stream": False
                }
            }
        elif endpoint_type == "airtable_query":
            return {
                "base_id": f"app{self.faker.lexify(text='??????????????')}",
                "table_name": self.faker.random_element(elements=["Projects", "Contacts", "Tasks"]),
                "filter_by_formula": f"{{Status}} = '{self.faker.random_element(elements=['Active', 'Completed', 'Pending'])}'",
                "max_records": self.faker.random_int(min=10, max=100),
                "sort": [
                    {
                        "field": "Created Time",
                        "direction": "desc"
                    }
                ]
            }
        elif endpoint_type == "user_registration":
            user_data = self.generate_user_data()
            return {
                "email": user_data["email"],
                "password": self.faker.password(length=12),
                "first_name": user_data["first_name"],
                "last_name": user_data["last_name"],
                "terms_accepted": True
            }
        else:
            return {
                "test_data": True,
                "timestamp": datetime.now().isoformat(),
                "random_value": self.faker.random_int(min=1, max=1000)
            }

class TestDataManager:
    """Central manager for test data lifecycle"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.cleanup_tasks: List[TestDataCleanupTask] = []
        self.data_factory = TestDataFactory()
        self.db_validator: Optional[DatabaseStateValidator] = None
        self.redis_manager: Optional[RedisStateManager] = None
    
    async def __aenter__(self):
        """Initialize data management resources"""
        if self.config.database:
            self.db_validator = DatabaseStateValidator(self.config)
            await self.db_validator.__aenter__()
        
        self.redis_manager = RedisStateManager(self.config)
        await self.redis_manager.__aenter__()
        
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Cleanup data management resources"""
        # Perform cleanup if configured
        if self.config.cleanup_test_data:
            await self.cleanup_all_test_data()
        
        if self.db_validator:
            await self.db_validator.__aexit__(exc_type, exc_val, exc_tb)
        
        if self.redis_manager:
            await self.redis_manager.__aexit__(exc_type, exc_val, exc_tb)
    
    def register_cleanup_task(self, resource_type: str, resource_identifier: str, 
                            cleanup_function: str, metadata: Dict[str, Any] = None):
        """Register a cleanup task for later execution"""
        task = TestDataCleanupTask(
            task_id=str(uuid.uuid4()),
            resource_type=resource_type,
            resource_identifier=resource_identifier,
            cleanup_function=cleanup_function,
            metadata=metadata or {}
        )
        
        self.cleanup_tasks.append(task)
        logger.debug(f"Registered cleanup task: {task.task_id} for {resource_type}:{resource_identifier}")
    
    async def cleanup_all_test_data(self) -> Dict[str, Any]:
        """Execute all registered cleanup tasks"""
        cleanup_results = {
            "timestamp": datetime.now().isoformat(),
            "tasks_executed": 0,
            "tasks_failed": 0,
            "details": []
        }
        
        logger.info(f"Starting cleanup of {len(self.cleanup_tasks)} test data tasks")
        
        for task in self.cleanup_tasks:
            try:
                if task.resource_type == "database" and self.db_validator:
                    result = await self.db_validator.cleanup_test_data()
                    cleanup_results["details"].append({
                        "task_id": task.task_id,
                        "resource_type": task.resource_type,
                        "status": "success",
                        "result": result
                    })
                
                elif task.resource_type == "redis" and self.redis_manager:
                    deleted_count = await self.redis_manager.cleanup_test_keys()
                    cleanup_results["details"].append({
                        "task_id": task.task_id,
                        "resource_type": task.resource_type,
                        "status": "success",
                        "deleted_keys": deleted_count
                    })
                
                cleanup_results["tasks_executed"] += 1
                
            except Exception as e:
                logger.error(f"Cleanup task {task.task_id} failed: {e}")
                cleanup_results["tasks_failed"] += 1
                cleanup_results["details"].append({
                    "task_id": task.task_id,
                    "resource_type": task.resource_type,
                    "status": "failed",
                    "error": str(e)
                })
        
        # Clear completed tasks
        self.cleanup_tasks.clear()
        
        logger.info(f"Cleanup completed: {cleanup_results['tasks_executed']} succeeded, {cleanup_results['tasks_failed']} failed")
        
        return cleanup_results
    
    async def create_test_environment(self, test_name: str) -> Dict[str, Any]:
        """Create a complete test environment with data"""
        environment = {
            "test_name": test_name,
            "created_at": datetime.now().isoformat(),
            "session_data": {},
            "test_users": [],
            "test_records": []
        }
        
        try:
            # Create test session
            if self.redis_manager:
                session_data = self.data_factory.generate_session_data()
                session_key = await self.redis_manager.create_test_session(
                    session_data["session_id"], 
                    session_data
                )
                environment["session_data"] = session_data
                
                # Register for cleanup
                self.register_cleanup_task("redis", session_key, "delete_key")
            
            # Generate test users
            for i in range(3):  # Create 3 test users
                user_data = self.data_factory.generate_user_data()
                environment["test_users"].append(user_data)
            
            # Generate test records
            for record_type in ["contacts", "projects", "tasks"]:
                for i in range(5):  # Create 5 records of each type
                    record_data = self.data_factory.generate_airtable_record_data(record_type)
                    environment["test_records"].append(record_data)
            
            logger.info(f"Test environment created for '{test_name}': {len(environment['test_users'])} users, {len(environment['test_records'])} records")
        
        except Exception as e:
            logger.error(f"Failed to create test environment: {e}")
            raise
        
        return environment