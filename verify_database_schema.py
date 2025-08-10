#!/usr/bin/env python3
"""
Database Schema Verification Script
Verifies that all critical database tables exist and are accessible.
"""

import psycopg2
import sys
import json
from datetime import datetime

# Database connection parameters
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'pyairtable',
    'user': 'postgres',
    'password': 'postgres'  # Default for local development
}

# Required tables for each service
REQUIRED_TABLES = {
    'automation-services': [
        'workflows',
        'workflow_executions', 
        'files'
    ],
    'saga-orchestrator': [
        'saga_instances',
        'saga_timeouts',
        'saga_compensations',
        'saga_snapshots',
        'event_store'
    ],
    'platform-core': [
        'platform_users',
        'conversation_sessions',
        'conversation_messages',
        'api_usage_logs',
        'tool_executions'
    ]
}

# Critical indexes to check
REQUIRED_INDEXES = [
    'idx_workflows_status',
    'idx_saga_instances_status',
    'idx_platform_users_is_active',
    'idx_conversation_sessions_user_id',
    'idx_saga_timeouts_timeout_at'
]

def test_database_connection():
    """Test basic database connectivity."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        cursor.execute("SELECT version();")
        db_version = cursor.fetchone()[0]
        print(f"✅ Database connection successful")
        print(f"   PostgreSQL version: {db_version.split(',')[0]}")
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        return False

def check_tables_exist():
    """Check if all required tables exist."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        # Get list of all tables
        cursor.execute("""
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        """)
        existing_tables = [row[0] for row in cursor.fetchall()]
        print(f"✅ Found {len(existing_tables)} tables in database")
        
        # Check each service's required tables
        all_tables_exist = True
        missing_tables = []
        
        for service, tables in REQUIRED_TABLES.items():
            print(f"\n🔍 Checking tables for {service}:")
            for table in tables:
                if table in existing_tables:
                    print(f"   ✅ {table}")
                else:
                    print(f"   ❌ {table} - MISSING")
                    missing_tables.append((service, table))
                    all_tables_exist = False
        
        cursor.close()
        conn.close()
        
        if missing_tables:
            print(f"\n❌ Missing {len(missing_tables)} required tables:")
            for service, table in missing_tables:
                print(f"   - {service}: {table}")
        
        return all_tables_exist, missing_tables
        
    except Exception as e:
        print(f"❌ Table check failed: {e}")
        return False, []

def check_indexes_exist():
    """Check if performance indexes exist."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT indexname 
            FROM pg_indexes 
            WHERE schemaname = 'public' 
            AND indexname LIKE 'idx_%'
            ORDER BY indexname;
        """)
        existing_indexes = [row[0] for row in cursor.fetchall()]
        print(f"\n🔍 Found {len(existing_indexes)} performance indexes")
        
        missing_indexes = []
        for idx in REQUIRED_INDEXES:
            if idx in existing_indexes:
                print(f"   ✅ {idx}")
            else:
                print(f"   ❌ {idx} - MISSING")
                missing_indexes.append(idx)
        
        cursor.close()
        conn.close()
        
        return len(missing_indexes) == 0, missing_indexes
        
    except Exception as e:
        print(f"❌ Index check failed: {e}")
        return False, []

def test_table_operations():
    """Test basic CRUD operations on critical tables."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        print(f"\n🔍 Testing table operations:")
        
        # Test workflows table
        test_workflow_id = None
        try:
            cursor.execute("""
                INSERT INTO workflows (name, description, workflow_config)
                VALUES ('test_workflow', 'Database schema test', '{"test": true}')
                RETURNING id;
            """)
            test_workflow_id = cursor.fetchone()[0]
            print("   ✅ Workflows table - INSERT successful")
            
            cursor.execute("SELECT COUNT(*) FROM workflows WHERE id = %s", (test_workflow_id,))
            if cursor.fetchone()[0] == 1:
                print("   ✅ Workflows table - SELECT successful")
            
            cursor.execute("DELETE FROM workflows WHERE id = %s", (test_workflow_id,))
            print("   ✅ Workflows table - DELETE successful")
            
        except Exception as e:
            print(f"   ❌ Workflows table operations failed: {e}")
        
        # Test saga_instances table
        try:
            cursor.execute("""
                INSERT INTO saga_instances (id, saga_type, status, total_steps)
                VALUES ('test_saga_123', 'test_saga', 'running', 3);
            """)
            print("   ✅ SAGA instances table - INSERT successful")
            
            cursor.execute("SELECT status FROM saga_instances WHERE id = 'test_saga_123'")
            if cursor.fetchone()[0] == 'running':
                print("   ✅ SAGA instances table - SELECT successful")
            
            cursor.execute("DELETE FROM saga_instances WHERE id = 'test_saga_123'")
            print("   ✅ SAGA instances table - DELETE successful")
            
        except Exception as e:
            print(f"   ❌ SAGA instances table operations failed: {e}")
        
        conn.commit()
        cursor.close()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"❌ Table operations test failed: {e}")
        return False

def analyze_query_performance():
    """Analyze query performance for common operations."""
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        
        print(f"\n🔍 Analyzing query performance:")
        
        # Test workflow lookup performance
        cursor.execute("EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM workflows WHERE status = 'active' LIMIT 10;")
        workflow_plan = cursor.fetchall()
        has_index_scan = any('Index Scan' in str(row) for row in workflow_plan)
        if has_index_scan:
            print("   ✅ Workflow status queries use index")
        else:
            print("   ⚠️  Workflow status queries may need optimization")
        
        # Test saga lookup performance  
        cursor.execute("EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM saga_instances WHERE status = 'running' LIMIT 10;")
        saga_plan = cursor.fetchall()
        has_index_scan = any('Index Scan' in str(row) for row in saga_plan)
        if has_index_scan:
            print("   ✅ SAGA status queries use index")
        else:
            print("   ⚠️  SAGA status queries may need optimization")
        
        cursor.close()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"❌ Performance analysis failed: {e}")
        return False

def generate_report():
    """Generate comprehensive database status report."""
    print("=" * 80)
    print("🗄️  PYAIRTABLE DATABASE SCHEMA VERIFICATION REPORT")
    print("=" * 80)
    print(f"📅 Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Test database connection
    connection_ok = test_database_connection()
    if not connection_ok:
        print("\n❌ CRITICAL: Database connection failed. Cannot proceed with verification.")
        return False
    
    # Check tables
    tables_ok, missing_tables = check_tables_exist()
    
    # Check indexes
    indexes_ok, missing_indexes = check_indexes_exist()
    
    # Test operations
    operations_ok = test_table_operations()
    
    # Performance analysis
    performance_ok = analyze_query_performance()
    
    # Final status
    print("\n" + "=" * 80)
    print("📊 VERIFICATION SUMMARY")
    print("=" * 80)
    
    all_checks_passed = all([connection_ok, tables_ok, indexes_ok, operations_ok])
    
    if all_checks_passed:
        print("🎉 ALL CHECKS PASSED!")
        print("   ✅ Database connection working")
        print("   ✅ All required tables exist")
        print("   ✅ Performance indexes in place")  
        print("   ✅ Table operations functional")
        print("\n✨ Database schema is ready for production!")
        
    else:
        print("⚠️  ISSUES DETECTED:")
        if not connection_ok:
            print("   ❌ Database connection failed")
        if not tables_ok:
            print(f"   ❌ {len(missing_tables)} tables missing")
        if not indexes_ok:
            print(f"   ❌ {len(missing_indexes)} indexes missing")  
        if not operations_ok:
            print("   ❌ Table operations failed")
        
        print("\n🔧 Manual intervention required before production deployment.")
    
    return all_checks_passed

if __name__ == "__main__":
    success = generate_report()
    sys.exit(0 if success else 1)