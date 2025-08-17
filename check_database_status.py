#!/usr/bin/env python3
"""
PyAirtable Database Status Checker
==================================

Quick script to check the current state of the database and calculate
a "Reality Score" based on data completeness.

Usage: python check_database_status.py
"""

import os
import psycopg2
from datetime import datetime

def check_database_status():
    """Check database status and calculate reality score"""
    
    config = {
        'host': 'postgres',
        'port': 5432,
        'database': 'pyairtable',
        'user': 'pyairtable',
        'password': os.getenv('POSTGRES_PASSWORD', 'CHANGE_ME')
    }
    
    try:
        conn = psycopg2.connect(**config)
        cursor = conn.cursor()
        
        print("🔍 PyAirtable Database Status Check")
        print("=" * 50)
        print(f"⏰ Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Core data counts
        queries = [
            ("Users", "SELECT COUNT(*) FROM users", "SELECT COUNT(*) FROM users WHERE is_active = true"),
            ("Tenants", "SELECT COUNT(*) FROM tenants", "SELECT COUNT(*) FROM tenants WHERE is_active = true"),
            ("Workspaces", "SELECT COUNT(*) FROM user_workspaces", "SELECT COUNT(*) FROM user_workspaces WHERE is_active = true"),
            ("Workflows", "SELECT COUNT(*) FROM workflows", "SELECT COUNT(*) FROM workflows WHERE is_active = true"),
            ("Workflow Runs", "SELECT COUNT(*) FROM workflow_runs", "SELECT COUNT(*) FROM workflow_runs WHERE status = 'completed'"),
            ("API Keys", "SELECT COUNT(*) FROM api_keys", "SELECT COUNT(*) FROM api_keys WHERE is_active = true"),
            ("Workspace Members", "SELECT COUNT(*) FROM workspace_members", None),
            ("Analytics Events", "SELECT COUNT(*) FROM platform_analytics_events", None),
            ("Analytics Metrics", "SELECT COUNT(*) FROM platform_analytics_metrics", None)
        ]
        
        data_counts = {}
        print("📊 Database Population Status:")
        print("-" * 30)
        
        for name, total_query, active_query in queries:
            cursor.execute(total_query)
            total = cursor.fetchone()[0]
            data_counts[name] = total
            
            if active_query:
                cursor.execute(active_query)
                active = cursor.fetchone()[0]
                print(f"  {name:18}: {total:4d} total, {active:4d} active")
            else:
                print(f"  {name:18}: {total:4d} total")
        
        # Calculate Reality Score
        print("\n🎯 Reality Score Calculation:")
        print("-" * 30)
        
        score = 0
        max_score = 10
        
        # Scoring criteria
        criteria = [
            ("Users (min 10)", data_counts["Users"] >= 10, 1),
            ("Tenants (min 5)", data_counts["Tenants"] >= 5, 1),
            ("Workspaces (min 15)", data_counts["Workspaces"] >= 15, 1),
            ("Workflows (min 20)", data_counts["Workflows"] >= 20, 1),
            ("Workflow Runs (min 50)", data_counts["Workflow Runs"] >= 50, 2),
            ("API Keys (min 5)", data_counts["API Keys"] >= 5, 1),
            ("Workspace Members (min 30)", data_counts["Workspace Members"] >= 30, 1),
            ("Analytics Events (min 100)", data_counts["Analytics Events"] >= 100, 1),
            ("Analytics Metrics (min 50)", data_counts["Analytics Metrics"] >= 50, 1)
        ]
        
        for criterion, passed, points in criteria:
            status = "✅" if passed else "❌"
            print(f"  {status} {criterion:30} (+{points if passed else 0} pts)")
            if passed:
                score += points
        
        print(f"\n📈 REALITY SCORE: {score}/{max_score} ({(score/max_score)*100:.1f}%)")
        
        # Interpretation
        if score >= 9:
            interpretation = "🎉 EXCELLENT - Database is fully populated with realistic test data!"
        elif score >= 7:
            interpretation = "🎯 GOOD - Database has substantial test data, suitable for most testing scenarios"
        elif score >= 5:
            interpretation = "⚠️  FAIR - Database has some test data, but may need more for comprehensive testing"
        elif score >= 3:
            interpretation = "❌ POOR - Database has minimal test data, not suitable for realistic testing"
        else:
            interpretation = "💀 CRITICAL - Database is essentially empty, seeding required immediately"
        
        print(f"\n{interpretation}")
        
        # Additional insights
        print("\n🔍 Additional Insights:")
        print("-" * 20)
        
        cursor.execute("SELECT role, COUNT(*) FROM users GROUP BY role ORDER BY COUNT(*) DESC")
        user_roles = cursor.fetchall()
        print("  User Roles:", ", ".join([f"{role}: {count}" for role, count in user_roles]))
        
        cursor.execute("SELECT plan, COUNT(*) FROM tenants GROUP BY plan ORDER BY COUNT(*) DESC")
        tenant_plans = cursor.fetchall()
        print("  Tenant Plans:", ", ".join([f"{plan}: {count}" for plan, count in tenant_plans]))
        
        cursor.execute("SELECT status, COUNT(*) FROM workflow_runs GROUP BY status ORDER BY COUNT(*) DESC LIMIT 3")
        workflow_statuses = cursor.fetchall()
        print("  Top Workflow Statuses:", ", ".join([f"{status}: {count}" for status, count in workflow_statuses]))
        
        cursor.close()
        conn.close()
        
        return score
        
    except Exception as e:
        print(f"❌ Database connection failed: {e}")
        return 0

if __name__ == "__main__":
    check_database_status()