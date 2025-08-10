#!/usr/bin/env python3
"""
Comprehensive test data seeder for all test databases.
Creates realistic test data for unit, integration, and e2e tests.
"""

import os
import asyncio
import random
from datetime import datetime, timedelta
from typing import List, Dict, Any
from faker import Faker
import psycopg2
from psycopg2.extras import RealDictCursor
import uuid
import bcrypt
import json

fake = Faker()


class TestDataSeeder:
    """Seeds test data across all test databases."""
    
    def __init__(self):
        self.databases = [
            'unit_test_db',
            'integration_test_db', 
            'e2e_test_db'
        ]
        self.base_db_url = os.getenv('DATABASE_URL', 'postgresql://test_user:test_password@postgres-test:5432')
        
    def get_db_connection(self, database_name: str):
        """Get database connection for specific test database."""
        db_url = self.base_db_url.replace('/test_db', f'/{database_name}')
        return psycopg2.connect(db_url)
    
    def hash_password(self, password: str) -> str:
        """Hash password using bcrypt."""
        return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    
    def generate_test_users(self, count: int = 50) -> List[Dict[str, Any]]:
        """Generate test users with realistic data."""
        users = []
        
        # Always include some predictable test users
        predictable_users = [
            {
                'email': 'admin@example.com',
                'username': 'admin',
                'password_hash': self.hash_password('admin123'),
                'first_name': 'Admin',
                'last_name': 'User',
                'is_active': True,
                'is_verified': True
            },
            {
                'email': 'test@example.com',
                'username': 'testuser',
                'password_hash': self.hash_password('test123'),
                'first_name': 'Test',
                'last_name': 'User',
                'is_active': True,
                'is_verified': True
            },
            {
                'email': 'inactive@example.com',
                'username': 'inactive',
                'password_hash': self.hash_password('inactive123'),
                'first_name': 'Inactive',
                'last_name': 'User',
                'is_active': False,
                'is_verified': False
            }
        ]
        
        users.extend(predictable_users)
        
        # Generate random users
        for _ in range(count - len(predictable_users)):
            user = {
                'email': fake.unique.email(),
                'username': fake.unique.user_name(),
                'password_hash': self.hash_password('password123'),
                'first_name': fake.first_name(),
                'last_name': fake.last_name(),
                'is_active': random.choice([True, True, True, False]),  # 75% active
                'is_verified': random.choice([True, True, False]),  # 67% verified
                'created_at': fake.date_time_between(start_date='-2y', end_date='now'),
            }
            users.append(user)
        
        return users
    
    def generate_test_workspaces(self, user_ids: List[str], count: int = 20) -> List[Dict[str, Any]]:
        """Generate test workspaces."""
        workspaces = []
        
        workspace_names = [
            'Marketing Campaigns',
            'Product Development',
            'Customer Support',
            'Sales Pipeline',
            'HR Management',
            'Finance Tracking',
            'Project Alpha',
            'Content Calendar',
            'Inventory Management',
            'Quality Assurance'
        ]
        
        for i in range(count):
            workspace = {
                'name': fake.unique.company() if i >= len(workspace_names) else workspace_names[i],
                'description': fake.text(max_nb_chars=200),
                'owner_id': random.choice(user_ids),
                'settings': json.dumps({
                    'theme': random.choice(['light', 'dark']),
                    'timezone': random.choice(['UTC', 'America/New_York', 'Europe/London', 'Asia/Tokyo']),
                    'notifications_enabled': random.choice([True, False]),
                    'auto_save': True,
                    'collaboration_mode': random.choice(['open', 'restricted', 'private'])
                }),
                'created_at': fake.date_time_between(start_date='-1y', end_date='now'),
            }
            workspaces.append(workspace)
        
        return workspaces
    
    def generate_test_sessions(self, user_ids: List[str], count: int = 100) -> List[Dict[str, Any]]:
        """Generate test sessions."""
        sessions = []
        
        for _ in range(count):
            created_at = fake.date_time_between(start_date='-30d', end_date='now')
            expires_at = created_at + timedelta(days=random.randint(1, 30))
            last_accessed = fake.date_time_between(start_date=created_at, end_date='now')
            
            session = {
                'user_id': random.choice(user_ids),
                'session_token': fake.uuid4(),
                'expires_at': expires_at,
                'created_at': created_at,
                'last_accessed_at': last_accessed
            }
            sessions.append(session)
        
        return sessions
    
    def generate_audit_logs(self, user_ids: List[str], count: int = 500) -> List[Dict[str, Any]]:
        """Generate test audit logs."""
        logs = []
        
        actions = ['login', 'logout', 'create', 'update', 'delete', 'view', 'download', 'export', 'import', 'share']
        resource_types = ['user', 'workspace', 'table', 'record', 'file', 'permission', 'integration']
        
        for _ in range(count):
            log = {
                'user_id': random.choice(user_ids + [None]),  # Some logs might not have user_id
                'action': random.choice(actions),
                'resource_type': random.choice(resource_types),
                'resource_id': str(uuid.uuid4()),
                'details': json.dumps({
                    'method': random.choice(['GET', 'POST', 'PUT', 'DELETE']),
                    'status_code': random.choice([200, 201, 400, 401, 403, 404, 500]),
                    'duration_ms': random.randint(10, 5000),
                    'affected_records': random.randint(0, 100)
                }),
                'ip_address': fake.ipv4(),
                'user_agent': fake.user_agent(),
                'created_at': fake.date_time_between(start_date='-90d', end_date='now')
            }
            logs.append(log)
        
        return logs
    
    def seed_database(self, database_name: str):
        """Seed a specific test database."""
        print(f"Seeding database: {database_name}")
        
        try:
            conn = self.get_db_connection(database_name)
            cursor = conn.cursor()
            
            # Clear existing test data
            cursor.execute("TRUNCATE test_audit_logs, test_sessions, test_workspaces, test_users RESTART IDENTITY CASCADE")
            
            # Generate test data
            users = self.generate_test_users(50)
            
            # Insert users and collect IDs
            user_ids = []
            for user in users:
                cursor.execute("""
                    INSERT INTO test_users (email, username, password_hash, first_name, last_name, 
                                          is_active, is_verified, created_at)
                    VALUES (%(email)s, %(username)s, %(password_hash)s, %(first_name)s, %(last_name)s,
                           %(is_active)s, %(is_verified)s, %(created_at)s)
                    RETURNING id
                """, user)
                user_id = cursor.fetchone()[0]
                user_ids.append(str(user_id))
            
            print(f"  Created {len(user_ids)} test users")
            
            # Generate and insert workspaces
            workspaces = self.generate_test_workspaces(user_ids, 20)
            for workspace in workspaces:
                cursor.execute("""
                    INSERT INTO test_workspaces (name, description, owner_id, settings, created_at)
                    VALUES (%(name)s, %(description)s, %(owner_id)s, %(settings)s, %(created_at)s)
                """, workspace)
            
            print(f"  Created {len(workspaces)} test workspaces")
            
            # Generate and insert sessions
            sessions = self.generate_test_sessions(user_ids, 100)
            for session in sessions:
                cursor.execute("""
                    INSERT INTO test_sessions (user_id, session_token, expires_at, created_at, last_accessed_at)
                    VALUES (%(user_id)s, %(session_token)s, %(expires_at)s, %(created_at)s, %(last_accessed_at)s)
                """, session)
            
            print(f"  Created {len(sessions)} test sessions")
            
            # Generate and insert audit logs
            audit_logs = self.generate_audit_logs(user_ids, 500)
            for log in audit_logs:
                cursor.execute("""
                    INSERT INTO test_audit_logs (user_id, action, resource_type, resource_id, details, 
                                               ip_address, user_agent, created_at)
                    VALUES (%(user_id)s, %(action)s, %(resource_type)s, %(resource_id)s, %(details)s,
                           %(ip_address)s, %(user_agent)s, %(created_at)s)
                """, log)
            
            print(f"  Created {len(audit_logs)} test audit logs")
            
            # Commit changes
            conn.commit()
            
            # Print summary
            cursor.execute("SELECT COUNT(*) FROM test_users")
            user_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM test_workspaces")
            workspace_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM test_sessions")
            session_count = cursor.fetchone()[0]
            
            cursor.execute("SELECT COUNT(*) FROM test_audit_logs")
            log_count = cursor.fetchone()[0]
            
            print(f"  Summary for {database_name}:")
            print(f"    Users: {user_count}")
            print(f"    Workspaces: {workspace_count}")
            print(f"    Sessions: {session_count}")
            print(f"    Audit Logs: {log_count}")
            
        except Exception as e:
            print(f"Error seeding {database_name}: {e}")
            raise
        finally:
            if 'conn' in locals():
                conn.close()
    
    def seed_all_databases(self):
        """Seed all test databases."""
        print("Starting test data seeding for all databases...")
        
        for database in self.databases:
            try:
                self.seed_database(database)
            except Exception as e:
                print(f"Failed to seed {database}: {e}")
                continue
        
        print("Test data seeding completed!")
    
    def create_test_data_snapshots(self):
        """Create JSON snapshots of test data for use in tests."""
        snapshots = {}
        
        for database in self.databases:
            try:
                conn = self.get_db_connection(database)
                cursor = conn.cursor(cursor_factory=RealDictCursor)
                
                # Get sample data from each table
                cursor.execute("SELECT * FROM test_users LIMIT 10")
                users = [dict(row) for row in cursor.fetchall()]
                
                cursor.execute("SELECT * FROM test_workspaces LIMIT 5")
                workspaces = [dict(row) for row in cursor.fetchall()]
                
                cursor.execute("SELECT * FROM test_sessions WHERE expires_at > NOW() LIMIT 5")
                sessions = [dict(row) for row in cursor.fetchall()]
                
                snapshots[database] = {
                    'users': users,
                    'workspaces': workspaces,
                    'sessions': sessions
                }
                
                conn.close()
                
            except Exception as e:
                print(f"Error creating snapshot for {database}: {e}")
        
        # Save snapshots to JSON file
        snapshot_file = '/app/tests/fixtures/test_data_snapshots.json'
        os.makedirs(os.path.dirname(snapshot_file), exist_ok=True)
        
        with open(snapshot_file, 'w') as f:
            json.dump(snapshots, f, indent=2, default=str)
        
        print(f"Test data snapshots saved to {snapshot_file}")


def main():
    """Main function to run the seeder."""
    seeder = TestDataSeeder()
    
    # Wait for database to be ready
    import time
    max_retries = 30
    retry_count = 0
    
    while retry_count < max_retries:
        try:
            conn = seeder.get_db_connection('test_db')
            conn.close()
            print("Database connection successful!")
            break
        except Exception as e:
            print(f"Waiting for database... ({retry_count + 1}/{max_retries})")
            time.sleep(2)
            retry_count += 1
    
    if retry_count >= max_retries:
        print("Failed to connect to database after maximum retries")
        exit(1)
    
    # Seed all databases
    seeder.seed_all_databases()
    
    # Create test data snapshots
    seeder.create_test_data_snapshots()
    
    print("All seeding operations completed successfully!")


if __name__ == '__main__':
    main()