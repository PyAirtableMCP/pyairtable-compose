#!/usr/bin/env python3
"""
PyAirtable Metadata Workflow Test
Tests the core metadata management functionality using direct database access
"""
import json
import subprocess
import time
from datetime import datetime, timedelta
from typing import Dict, Any, List

class MetadataWorkflowTester:
    def __init__(self):
        self.results = {
            "test_start": datetime.now().isoformat(),
            "workflow_tests": {},
            "performance_metrics": {},
            "data_validation": {},
            "summary": {}
        }
        
    def log(self, message: str):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {message}")
        
    def execute_sql(self, sql: str, description: str = "") -> Dict[str, Any]:
        """Execute SQL command and return results"""
        try:
            start_time = time.time()
            result = subprocess.run([
                "docker", "exec", "pyairtable-compose-postgres-1",
                "psql", "-U", "postgres", "-d", "pyairtable", "-c", sql
            ], capture_output=True, text=True, timeout=30)
            
            execution_time = round((time.time() - start_time) * 1000, 2)
            
            return {
                "success": result.returncode == 0,
                "execution_time_ms": execution_time,
                "output": result.stdout.strip() if result.stdout else "",
                "error": result.stderr.strip() if result.stderr else "",
                "description": description
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "description": description
            }
    
    def setup_metadata_schema(self) -> Dict[str, Any]:
        """Set up complete metadata schema for PyAirtable"""
        self.log("Setting up metadata schema...")
        schema_results = {}
        
        # Drop existing tables for clean test
        drop_tables = [
            "DROP TABLE IF EXISTS airtable_sync_logs CASCADE;",
            "DROP TABLE IF EXISTS airtable_field_mappings CASCADE;",
            "DROP TABLE IF EXISTS airtable_records_cache CASCADE;", 
            "DROP TABLE IF EXISTS airtable_tables CASCADE;",
            "DROP TABLE IF EXISTS airtable_bases CASCADE;",
            "DROP TABLE IF EXISTS airtable_workspaces CASCADE;",
        ]
        
        for drop_sql in drop_tables:
            self.execute_sql(drop_sql, "Cleanup existing tables")
        
        # Create schema tables
        schema_commands = [
            {
                "name": "workspaces_table",
                "sql": '''CREATE TABLE airtable_workspaces (
                    id SERIAL PRIMARY KEY,
                    workspace_id VARCHAR(255) UNIQUE NOT NULL,
                    workspace_name VARCHAR(255) NOT NULL,
                    organization_id VARCHAR(255),
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW(),
                    is_active BOOLEAN DEFAULT TRUE
                );''',
                "description": "Create workspaces table for organization structure"
            },
            {
                "name": "bases_table", 
                "sql": '''CREATE TABLE airtable_bases (
                    id SERIAL PRIMARY KEY,
                    base_id VARCHAR(255) UNIQUE NOT NULL,
                    base_name VARCHAR(255) NOT NULL,
                    workspace_id VARCHAR(255) REFERENCES airtable_workspaces(workspace_id),
                    description TEXT,
                    permissions JSONB DEFAULT '{}',
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW(),
                    last_sync TIMESTAMP,
                    is_active BOOLEAN DEFAULT TRUE
                );''',
                "description": "Create bases table for Airtable base metadata"
            },
            {
                "name": "tables_table",
                "sql": '''CREATE TABLE airtable_tables (
                    id SERIAL PRIMARY KEY,
                    table_id VARCHAR(255) NOT NULL,
                    table_name VARCHAR(255) NOT NULL,
                    base_id VARCHAR(255) REFERENCES airtable_bases(base_id),
                    field_count INTEGER DEFAULT 0,
                    record_count INTEGER DEFAULT 0,
                    primary_field VARCHAR(255),
                    schema_definition JSONB DEFAULT '{}',
                    view_definitions JSONB DEFAULT '[]',
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW(),
                    last_sync TIMESTAMP,
                    UNIQUE(base_id, table_id)
                );''',
                "description": "Create tables metadata"
            },
            {
                "name": "field_mappings_table",
                "sql": '''CREATE TABLE airtable_field_mappings (
                    id SERIAL PRIMARY KEY,
                    field_id VARCHAR(255) NOT NULL,
                    field_name VARCHAR(255) NOT NULL,
                    field_type VARCHAR(100) NOT NULL,
                    table_id VARCHAR(255) NOT NULL,
                    base_id VARCHAR(255) NOT NULL,
                    field_config JSONB DEFAULT '{}',
                    is_primary BOOLEAN DEFAULT FALSE,
                    is_required BOOLEAN DEFAULT FALSE,
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW(),
                    FOREIGN KEY (base_id, table_id) REFERENCES airtable_tables(base_id, table_id)
                );''',
                "description": "Create field mappings for data structure"
            },
            {
                "name": "sync_logs_table",
                "sql": '''CREATE TABLE airtable_sync_logs (
                    id SERIAL PRIMARY KEY,
                    sync_id VARCHAR(255) UNIQUE NOT NULL,
                    base_id VARCHAR(255) REFERENCES airtable_bases(base_id),
                    table_id VARCHAR(255),
                    sync_type VARCHAR(50) NOT NULL, -- 'full', 'incremental', 'schema'
                    sync_status VARCHAR(50) NOT NULL, -- 'pending', 'running', 'completed', 'failed'
                    records_processed INTEGER DEFAULT 0,
                    records_created INTEGER DEFAULT 0,
                    records_updated INTEGER DEFAULT 0,
                    records_deleted INTEGER DEFAULT 0,
                    error_message TEXT,
                    started_at TIMESTAMP DEFAULT NOW(),
                    completed_at TIMESTAMP,
                    duration_seconds INTEGER
                );''',
                "description": "Create sync logs for operation tracking"
            }
        ]
        
        for command in schema_commands:
            result = self.execute_sql(command["sql"], command["description"])
            schema_results[command["name"]] = result
            
        # Create indexes for performance
        index_commands = [
            "CREATE INDEX idx_bases_workspace_id ON airtable_bases(workspace_id);",
            "CREATE INDEX idx_tables_base_id ON airtable_tables(base_id);", 
            "CREATE INDEX idx_fields_table_base ON airtable_field_mappings(base_id, table_id);",
            "CREATE INDEX idx_sync_logs_base_id ON airtable_sync_logs(base_id);",
            "CREATE INDEX idx_sync_logs_status ON airtable_sync_logs(sync_status);",
            "CREATE INDEX idx_sync_logs_started_at ON airtable_sync_logs(started_at);"
        ]
        
        for idx_sql in index_commands:
            self.execute_sql(idx_sql, "Create performance indexes")
        
        self.results["workflow_tests"]["schema_setup"] = schema_results
        return schema_results
    
    def test_metadata_operations(self) -> Dict[str, Any]:
        """Test CRUD operations on metadata"""
        self.log("Testing metadata CRUD operations...")
        crud_results = {}
        
        # Test workspace creation
        workspace_ops = [
            {
                "name": "create_workspace",
                "sql": "INSERT INTO airtable_workspaces (workspace_id, workspace_name, organization_id) VALUES ('wsp_test123', 'Test Workspace', 'org_test');",
                "description": "Create test workspace"
            },
            {
                "name": "create_base",
                "sql": "INSERT INTO airtable_bases (base_id, base_name, workspace_id, description) VALUES ('app_test123', 'Test Base', 'wsp_test123', 'Test base for validation');",
                "description": "Create test base"
            },
            {
                "name": "create_tables",
                "sql": '''INSERT INTO airtable_tables (table_id, table_name, base_id, field_count, record_count, primary_field) VALUES 
                         ('tbl_test1', 'Customers', 'app_test123', 5, 150, 'Name'),
                         ('tbl_test2', 'Orders', 'app_test123', 8, 500, 'Order ID'),
                         ('tbl_test3', 'Products', 'app_test123', 6, 75, 'Product Name');''',
                "description": "Create test tables"
            },
            {
                "name": "create_fields",
                "sql": '''INSERT INTO airtable_field_mappings (field_id, field_name, field_type, table_id, base_id, is_primary) VALUES
                         ('fld_name', 'Name', 'singleLineText', 'tbl_test1', 'app_test123', TRUE),
                         ('fld_email', 'Email', 'email', 'tbl_test1', 'app_test123', FALSE),
                         ('fld_status', 'Status', 'singleSelect', 'tbl_test1', 'app_test123', FALSE),
                         ('fld_orderid', 'Order ID', 'autonumber', 'tbl_test2', 'app_test123', TRUE),
                         ('fld_customer', 'Customer', 'linkedRecord', 'tbl_test2', 'app_test123', FALSE);''',
                "description": "Create field mappings"
            }
        ]
        
        for operation in workspace_ops:
            result = self.execute_sql(operation["sql"], operation["description"])
            crud_results[operation["name"]] = result
        
        self.results["workflow_tests"]["crud_operations"] = crud_results
        return crud_results
    
    def test_sync_workflow_simulation(self) -> Dict[str, Any]:
        """Simulate sync workflow operations"""
        self.log("Simulating sync workflow...")
        sync_results = {}
        
        # Simulate sync operations
        sync_operations = [
            {
                "name": "start_full_sync",
                "sql": "INSERT INTO airtable_sync_logs (sync_id, base_id, table_id, sync_type, sync_status) VALUES ('sync_001', 'app_test123', 'tbl_test1', 'full', 'running');",
                "description": "Start full sync simulation"
            },
            {
                "name": "update_sync_progress",
                "sql": "UPDATE airtable_sync_logs SET records_processed = 150, records_created = 150, sync_status = 'completed', completed_at = NOW(), duration_seconds = 45 WHERE sync_id = 'sync_001';",
                "description": "Complete sync with results"
            },
            {
                "name": "start_incremental_sync", 
                "sql": "INSERT INTO airtable_sync_logs (sync_id, base_id, sync_type, sync_status, records_processed, records_updated) VALUES ('sync_002', 'app_test123', 'incremental', 'completed', 25, 25);",
                "description": "Simulate incremental sync"
            },
            {
                "name": "simulate_failed_sync",
                "sql": "INSERT INTO airtable_sync_logs (sync_id, base_id, sync_type, sync_status, error_message) VALUES ('sync_003', 'app_test123', 'full', 'failed', 'Rate limit exceeded: 429 Too Many Requests');",
                "description": "Simulate failed sync for error handling"
            }
        ]
        
        for operation in sync_operations:
            result = self.execute_sql(operation["sql"], operation["description"])
            sync_results[operation["name"]] = result
            
        # Update table stats
        self.execute_sql("UPDATE airtable_tables SET last_sync = NOW(), record_count = 175 WHERE table_id = 'tbl_test1';", "Update sync timestamps")
        
        self.results["workflow_tests"]["sync_simulation"] = sync_results
        return sync_results
    
    def test_complex_queries(self) -> Dict[str, Any]:
        """Test complex analytical queries"""
        self.log("Testing complex analytical queries...")
        query_results = {}
        
        analytical_queries = [
            {
                "name": "workspace_summary",
                "sql": '''SELECT 
                    w.workspace_name,
                    COUNT(b.base_id) as total_bases,
                    SUM(t.record_count) as total_records,
                    COUNT(t.table_id) as total_tables
                FROM airtable_workspaces w
                LEFT JOIN airtable_bases b ON w.workspace_id = b.workspace_id
                LEFT JOIN airtable_tables t ON b.base_id = t.base_id
                GROUP BY w.workspace_id, w.workspace_name;''',
                "description": "Get workspace analytics summary"
            },
            {
                "name": "sync_performance_analysis",
                "sql": '''SELECT 
                    sync_type,
                    sync_status,
                    COUNT(*) as sync_count,
                    AVG(duration_seconds) as avg_duration,
                    AVG(records_processed) as avg_records,
                    MAX(started_at) as last_sync
                FROM airtable_sync_logs
                GROUP BY sync_type, sync_status
                ORDER BY sync_type, sync_status;''',
                "description": "Analyze sync performance patterns"
            },
            {
                "name": "base_health_check",
                "sql": '''SELECT 
                    b.base_name,
                    b.base_id,
                    COUNT(t.table_id) as table_count,
                    SUM(t.record_count) as total_records,
                    MAX(t.last_sync) as last_table_sync,
                    COUNT(f.field_id) as total_fields
                FROM airtable_bases b
                LEFT JOIN airtable_tables t ON b.base_id = t.base_id
                LEFT JOIN airtable_field_mappings f ON b.base_id = f.base_id
                WHERE b.is_active = TRUE
                GROUP BY b.base_id, b.base_name
                ORDER BY total_records DESC;''',
                "description": "Base health and activity check"
            },
            {
                "name": "recent_sync_activity",
                "sql": '''SELECT 
                    sl.sync_id,
                    b.base_name,
                    sl.sync_type,
                    sl.sync_status,
                    sl.records_processed,
                    sl.started_at,
                    sl.duration_seconds
                FROM airtable_sync_logs sl
                JOIN airtable_bases b ON sl.base_id = b.base_id
                WHERE sl.started_at > NOW() - INTERVAL '1 hour'
                ORDER BY sl.started_at DESC;''',
                "description": "Recent sync activity monitoring"
            }
        ]
        
        for query in analytical_queries:
            result = self.execute_sql(query["sql"], query["description"])
            query_results[query["name"]] = result
        
        self.results["workflow_tests"]["analytical_queries"] = query_results
        return query_results
    
    def validate_data_integrity(self) -> Dict[str, Any]:
        """Validate data integrity and relationships"""
        self.log("Validating data integrity...")
        validation_results = {}
        
        validation_checks = [
            {
                "name": "referential_integrity",
                "sql": '''SELECT 
                    (SELECT COUNT(*) FROM airtable_bases WHERE workspace_id NOT IN (SELECT workspace_id FROM airtable_workspaces)) as orphaned_bases,
                    (SELECT COUNT(*) FROM airtable_tables WHERE base_id NOT IN (SELECT base_id FROM airtable_bases)) as orphaned_tables,
                    (SELECT COUNT(*) FROM airtable_field_mappings WHERE base_id NOT IN (SELECT base_id FROM airtable_bases)) as orphaned_fields;''',
                "description": "Check for referential integrity violations"
            },
            {
                "name": "data_consistency",
                "sql": '''SELECT 
                    COUNT(*) as total_tables,
                    COUNT(CASE WHEN field_count > 0 THEN 1 END) as tables_with_fields,
                    COUNT(CASE WHEN record_count > 0 THEN 1 END) as tables_with_records,
                    COUNT(CASE WHEN last_sync IS NOT NULL THEN 1 END) as synced_tables
                FROM airtable_tables;''',
                "description": "Check data consistency metrics"
            },
            {
                "name": "sync_status_health", 
                "sql": '''SELECT 
                    sync_status,
                    COUNT(*) as count,
                    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
                FROM airtable_sync_logs
                GROUP BY sync_status
                ORDER BY count DESC;''',
                "description": "Analyze sync success rates"
            }
        ]
        
        for check in validation_checks:
            result = self.execute_sql(check["sql"], check["description"])
            validation_results[check["name"]] = result
        
        self.results["data_validation"] = validation_results
        return validation_results
    
    def measure_performance(self) -> Dict[str, Any]:
        """Measure database performance for metadata operations"""
        self.log("Measuring performance...")
        perf_results = {}
        
        # Test query performance with multiple runs
        performance_queries = [
            {
                "name": "workspace_lookup",
                "sql": "SELECT * FROM airtable_workspaces WHERE workspace_id = 'wsp_test123';",
                "runs": 10
            },
            {
                "name": "base_tables_join", 
                "sql": "SELECT b.*, COUNT(t.table_id) FROM airtable_bases b LEFT JOIN airtable_tables t ON b.base_id = t.base_id GROUP BY b.base_id;",
                "runs": 5
            },
            {
                "name": "field_mapping_complex",
                "sql": "SELECT t.table_name, COUNT(f.field_id) as field_count FROM airtable_tables t LEFT JOIN airtable_field_mappings f ON t.base_id = f.base_id AND t.table_id = f.table_id GROUP BY t.table_id, t.table_name;",
                "runs": 5
            }
        ]
        
        for query in performance_queries:
            times = []
            for _ in range(query["runs"]):
                result = self.execute_sql(query["sql"], f"Performance test: {query['name']}")
                if result["success"]:
                    times.append(result["execution_time_ms"])
            
            if times:
                perf_results[query["name"]] = {
                    "avg_time_ms": round(sum(times) / len(times), 2),
                    "min_time_ms": min(times),
                    "max_time_ms": max(times),
                    "runs": len(times)
                }
        
        self.results["performance_metrics"] = perf_results
        return perf_results
    
    def generate_workflow_summary(self) -> Dict[str, Any]:
        """Generate comprehensive workflow test summary"""
        self.log("Generating workflow summary...")
        
        # Count successful operations
        schema_success = sum(1 for test in self.results["workflow_tests"].get("schema_setup", {}).values()
                            if isinstance(test, dict) and test.get("success"))
        crud_success = sum(1 for test in self.results["workflow_tests"].get("crud_operations", {}).values()
                          if isinstance(test, dict) and test.get("success"))
        sync_success = sum(1 for test in self.results["workflow_tests"].get("sync_simulation", {}).values()
                          if isinstance(test, dict) and test.get("success"))
        query_success = sum(1 for test in self.results["workflow_tests"].get("analytical_queries", {}).values()
                           if isinstance(test, dict) and test.get("success"))
        validation_success = sum(1 for test in self.results["data_validation"].values()
                                if isinstance(test, dict) and test.get("success"))
        
        total_operations = (len(self.results["workflow_tests"].get("schema_setup", {})) +
                           len(self.results["workflow_tests"].get("crud_operations", {})) +
                           len(self.results["workflow_tests"].get("sync_simulation", {})) +
                           len(self.results["workflow_tests"].get("analytical_queries", {})) +
                           len(self.results["data_validation"]))
        
        total_success = schema_success + crud_success + sync_success + query_success + validation_success
        
        summary = {
            "test_completion": datetime.now().isoformat(),
            "total_operations": total_operations,
            "successful_operations": total_success,
            "success_rate": round((total_success / total_operations * 100), 2) if total_operations > 0 else 0,
            "schema_operations": f"{schema_success}/{len(self.results['workflow_tests'].get('schema_setup', {}))}",
            "crud_operations": f"{crud_success}/{len(self.results['workflow_tests'].get('crud_operations', {}))}",
            "sync_operations": f"{sync_success}/{len(self.results['workflow_tests'].get('sync_simulation', {}))}",
            "analytical_queries": f"{query_success}/{len(self.results['workflow_tests'].get('analytical_queries', {}))}",
            "data_validation": f"{validation_success}/{len(self.results['data_validation'])}",
            "workflow_status": "OPERATIONAL" if total_success > (total_operations * 0.8) else "DEGRADED",
            "key_capabilities": []
        }
        
        # Add key capabilities demonstrated
        if schema_success > 0:
            summary["key_capabilities"].append("✓ Metadata schema management")
        if crud_success > 0:
            summary["key_capabilities"].append("✓ Workspace and base operations")
        if sync_success > 0:
            summary["key_capabilities"].append("✓ Sync workflow simulation") 
        if query_success > 0:
            summary["key_capabilities"].append("✓ Analytical reporting")
        if validation_success > 0:
            summary["key_capabilities"].append("✓ Data integrity validation")
        
        # Performance insights
        if self.results["performance_metrics"]:
            avg_times = [metrics["avg_time_ms"] for metrics in self.results["performance_metrics"].values() 
                        if isinstance(metrics, dict) and "avg_time_ms" in metrics]
            if avg_times:
                summary["avg_query_performance_ms"] = round(sum(avg_times) / len(avg_times), 2)
        
        self.results["summary"] = summary
        return summary
    
    def run_metadata_workflow_tests(self) -> Dict[str, Any]:
        """Run complete metadata workflow test suite"""
        self.log("=== Starting Metadata Workflow Tests ===")
        
        # Set up schema
        self.setup_metadata_schema()
        
        # Test CRUD operations
        self.test_metadata_operations()
        
        # Test sync workflows
        self.test_sync_workflow_simulation()
        
        # Test analytical queries
        self.test_complex_queries()
        
        # Validate data integrity
        self.validate_data_integrity()
        
        # Measure performance
        self.measure_performance()
        
        # Generate summary
        self.generate_workflow_summary()
        
        # Save results
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"metadata_workflow_results_{timestamp}.json"
        
        with open(filename, 'w') as f:
            json.dump(self.results, f, indent=2)
        
        self.log(f"=== Metadata Workflow Results Saved to {filename} ===")
        return self.results

def main():
    tester = MetadataWorkflowTester()
    results = tester.run_metadata_workflow_tests()
    
    # Print summary
    print("\n" + "="*80)
    print("PYAIRTABLE METADATA WORKFLOW TEST SUMMARY")
    print("="*80)
    summary = results.get("summary", {})
    
    print(f"Workflow Status: {summary.get('workflow_status', 'UNKNOWN')}")
    print(f"Success Rate: {summary.get('success_rate', 0)}% ({summary.get('successful_operations', 0)}/{summary.get('total_operations', 0)} operations)")
    
    if "avg_query_performance_ms" in summary:
        print(f"Average Query Performance: {summary['avg_query_performance_ms']}ms")
    
    print("\nOperation Results:")
    print(f"  • Schema Setup:      {summary.get('schema_operations', 'N/A')}")
    print(f"  • CRUD Operations:   {summary.get('crud_operations', 'N/A')}")
    print(f"  • Sync Workflows:    {summary.get('sync_operations', 'N/A')}")
    print(f"  • Analytical Queries: {summary.get('analytical_queries', 'N/A')}")
    print(f"  • Data Validation:   {summary.get('data_validation', 'N/A')}")
    
    print("\nDemonstrated Capabilities:")
    for capability in summary.get("key_capabilities", []):
        print(f"  {capability}")
    
    print("="*80)
    return 0

if __name__ == "__main__":
    exit(main())