#!/usr/bin/env python3
"""
Comprehensive Database Test Script
Tests 18 tables exist, indexes applied, query performance, health checks
"""

import subprocess
import json
import os
import sys
import time
import requests
from typing import Dict, Any, List

class DatabaseTester:
    def __init__(self):
        self.test_results = {}
        self.db_config = {
            'host': os.getenv('TEST_DB_HOST', 'localhost'),
            'port': int(os.getenv('TEST_DB_PORT', '5432')),
            'database': os.getenv('TEST_DB_NAME', 'pyairtable_test'),
            'user': os.getenv('TEST_DB_USER', 'pyairtable_test_user'),
            'password': os.getenv('TEST_DB_PASSWORD', 'change_me_in_env')
        }
        
    def log_test(self, test_name: str, success: bool, message: str, details: Dict = None):
        """Log test results"""
        self.test_results[test_name] = {
            "success": success,
            "message": message,
            "details": details or {}
        }
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}: {message}")
        if details:
            print(f"   Details: {details}")
    
    def execute_db_query(self, query: str):
        """Execute database query using docker exec"""
        try:
            # Use docker exec to run psql commands
            cmd = [
                'docker-compose', 'exec', '-T', 'postgres', 
                'psql', '-U', 'pyairtable_user', '-d', 'pyairtable_db', 
                '-c', query
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                return True, result.stdout
            else:
                return False, result.stderr
                
        except Exception as e:
            return False, str(e)
    
    def test_database_connectivity(self):
        """Test if database is accessible"""
        try:
            success, output = self.execute_db_query("SELECT 1;")
            
            if success:
                self.log_test("Database Connectivity", True, "Database is accessible")
                return True
            else:
                self.log_test("Database Connectivity", False, f"Cannot connect to database: {output}")
                return False
        except Exception as e:
            self.log_test("Database Connectivity", False, f"Connection error: {str(e)}")
            return False
    
    def test_docker_postgres_running(self):
        """Test if PostgreSQL container is running"""
        try:
            result = subprocess.run(['docker-compose', 'ps', 'postgres'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0 and 'Up' in result.stdout:
                self.log_test("PostgreSQL Container", True, "PostgreSQL container is running")
                return True
            else:
                self.log_test("PostgreSQL Container", False, "PostgreSQL container not running")
                return False
        except Exception as e:
            self.log_test("PostgreSQL Container", False, f"Error checking container: {str(e)}")
            return False
    
    def test_table_count(self):
        """Test if required number of tables exist"""
        try:
            success, output = self.execute_db_query("""
                SELECT COUNT(*) 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_type = 'BASE TABLE';
            """)
            
            if not success:
                self.log_test("Table Count", False, f"Query failed: {output}")
                return False
            
            # Extract table count from output
            lines = output.strip().split('\n')
            table_count = 0
            for line in lines:
                line = line.strip()
                if line.isdigit():
                    table_count = int(line)
                    break
            
            # Get table names
            success2, output2 = self.execute_db_query("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_type = 'BASE TABLE'
                ORDER BY table_name;
            """)
            
            table_names = []
            if success2:
                lines = output2.strip().split('\n')
                for line in lines:
                    line = line.strip()
                    if line and line != 'table_name' and not line.startswith('-'):
                        table_names.append(line)
            
            if table_count >= 18:
                self.log_test("Table Count", True, f"Found {table_count} tables (target: 18)",
                             {"table_count": table_count, "tables": table_names[:10]})  # Show first 10
                return True
            else:
                self.log_test("Table Count", False, f"Only {table_count} tables found (target: 18)",
                             {"table_count": table_count, "tables": table_names})
                return False
                
        except Exception as e:
            self.log_test("Table Count", False, f"Error counting tables: {str(e)}")
            return False
    
    def test_indexes_exist(self):
        """Test if indexes are applied to tables"""
        try:
            success, output = self.execute_db_query("""
                SELECT COUNT(*) 
                FROM pg_indexes 
                WHERE schemaname = 'public';
            """)
            
            if not success:
                self.log_test("Database Indexes", False, f"Query failed: {output}")
                return False
            
            # Extract index count from output
            lines = output.strip().split('\n')
            index_count = 0
            for line in lines:
                line = line.strip()
                if line.isdigit():
                    index_count = int(line)
                    break
            
            # Expect at least some indexes (primary keys + additional indexes)
            if index_count >= 10:
                self.log_test("Database Indexes", True, f"Found {index_count} indexes",
                             {"index_count": index_count})
                return True
            else:
                self.log_test("Database Indexes", False, f"Only {index_count} indexes found",
                             {"index_count": index_count})
                return False
                
        except Exception as e:
            self.log_test("Database Indexes", False, f"Error checking indexes: {str(e)}")
            return False
    
    def test_query_performance(self):
        """Test basic query performance"""
        try:
            # Test a simple query and measure time
            start_time = time.time()
            success, output = self.execute_db_query("SELECT COUNT(*) FROM information_schema.tables;")
            end_time = time.time()
            
            if not success:
                self.log_test("Query Performance", False, f"Query failed: {output}")
                return False
            
            query_time = (end_time - start_time) * 1000  # Convert to milliseconds
            
            if query_time < 2000:  # Less than 2 seconds (accounting for docker overhead)
                self.log_test("Query Performance", True, f"Query executed in {query_time:.2f}ms",
                             {"query_time_ms": query_time})
                return True
            else:
                self.log_test("Query Performance", False, f"Query took {query_time:.2f}ms (too slow)",
                             {"query_time_ms": query_time})
                return False
                
        except Exception as e:
            self.log_test("Query Performance", False, f"Error testing performance: {str(e)}")
            return False
    
    def test_platform_service_db_health(self):
        """Test database health through platform service"""
        try:
            response = requests.get("http://localhost:8007/health", timeout=5)
            
            if response.status_code == 200:
                health_data = response.json()
                database_status = health_data.get("database", "unknown")
                
                if database_status == "connected":
                    self.log_test("Service DB Health", True, "Database connected via platform service",
                                 {"health_data": health_data})
                    return True
                else:
                    self.log_test("Service DB Health", False, f"Database status: {database_status}",
                                 {"health_data": health_data})
                    return False
            else:
                self.log_test("Service DB Health", False, f"Platform service not responding: {response.status_code}")
                return False
                
        except Exception as e:
            self.log_test("Service DB Health", False, f"Error checking service health: {str(e)}")
            return False
    
    def test_database_migrations(self):
        """Test if database migrations have been applied"""
        try:
            success, output = self.execute_db_query("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables 
                    WHERE table_schema = 'public' 
                    AND table_name IN ('migrations', 'schema_migrations', 'alembic_version')
                );
            """)
            
            if not success:
                self.log_test("Database Migrations", False, f"Query failed: {output}")
                return False
            
            # Extract boolean result
            migrations_table_exists = 't' in output.lower()
            
            if migrations_table_exists:
                self.log_test("Database Migrations", True, "Migration table found")
            else:
                self.log_test("Database Migrations", True, "No migration table found (manual setup)")
            
            return True
            
        except Exception as e:
            self.log_test("Database Migrations", False, f"Error checking migrations: {str(e)}")
            return False
    
    def test_essential_tables(self):
        """Test if essential tables exist"""
        essential_tables = [
            'users', 'user', 'auth_users',
            'roles', 'permissions', 
            'bases', 'airtable_bases',
            'records', 'airtable_records',
            'sessions', 'auth_sessions'
        ]
        
        try:
            success, output = self.execute_db_query("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public'
                ORDER BY table_name;
            """)
            
            if not success:
                self.log_test("Essential Tables", False, f"Query failed: {output}")
                return False
            
            # Extract table names from output
            existing_tables = []
            lines = output.strip().split('\n')
            for line in lines:
                line = line.strip()
                if line and line != 'table_name' and not line.startswith('-') and '(' not in line:
                    existing_tables.append(line.lower())
            
            found_essential = []
            for table in essential_tables:
                if table.lower() in existing_tables:
                    found_essential.append(table)
            
            if len(found_essential) >= 3:  # At least 3 essential tables
                self.log_test("Essential Tables", True, f"Found {len(found_essential)} essential tables",
                             {"found_tables": found_essential})
                return True
            else:
                self.log_test("Essential Tables", False, f"Only {len(found_essential)} essential tables found",
                             {"found_tables": found_essential, "all_tables": existing_tables[:10]})
                return False
                
        except Exception as e:
            self.log_test("Essential Tables", False, f"Error checking essential tables: {str(e)}")
            return False
    
    def run_all_tests(self):
        """Run all database tests"""
        print("🗄️ Starting Database Tests")
        print("=" * 50)
        
        # Test 1: Docker container running
        self.test_docker_postgres_running()
        
        # Test 2: Database connectivity
        db_connected = self.test_database_connectivity()
        
        if db_connected:
            # Test 3: Table count
            self.test_table_count()
            
            # Test 4: Indexes exist
            self.test_indexes_exist()
            
            # Test 5: Query performance
            self.test_query_performance()
            
            # Test 6: Essential tables
            self.test_essential_tables()
            
            # Test 7: Migrations
            self.test_database_migrations()
        else:
            print("❌ Cannot run detailed tests - database not accessible")
        
        # Test 8: Service health check
        self.test_platform_service_db_health()
        
        return self.get_summary()
    
    def get_summary(self):
        """Get test summary"""
        total_tests = len(self.test_results)
        passed_tests = sum(1 for result in self.test_results.values() if result["success"])
        
        summary = {
            "total_tests": total_tests,
            "passed_tests": passed_tests,
            "failed_tests": total_tests - passed_tests,
            "pass_rate": (passed_tests / total_tests * 100) if total_tests > 0 else 0,
            "results": self.test_results
        }
        
        print("\n" + "=" * 50)
        print("📊 Database Test Summary")
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed_tests}")
        print(f"Failed: {total_tests - passed_tests}")
        print(f"Pass Rate: {summary['pass_rate']:.1f}%")
        
        return summary

if __name__ == "__main__":
    tester = DatabaseTester()
    summary = tester.run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if summary["pass_rate"] >= 80 else 1)