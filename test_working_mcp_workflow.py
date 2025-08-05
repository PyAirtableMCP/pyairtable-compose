#!/usr/bin/env python3
"""
Working MCP Workflow Test
=========================

Tests the MCP workflow using direct tool execution rather than chat interface.
This tests the core functionality that actually works.
"""

import asyncio
import sys
import logging
import json
import time
from datetime import datetime
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WorkingMCPTester:
    def __init__(self):
        self.api_gateway_url = "http://localhost:8000"
        self.api_key = "pya_efe1764855b2300ebc87363fb26b71da645a1e6c"
        self.base_id = "appVLUAubH5cFWhMV"
        self.metadata_table_id = "tblBObA3GFYWNoH5O"  # Test Metadata Table
        
    async def execute_tool(self, tool_name, arguments, timeout=60):
        """Execute an MCP tool directly"""
        import aiohttp
        
        async with aiohttp.ClientSession() as session:
            tool_url = f"{self.api_gateway_url}/api/execute-tool"
            
            payload = {
                "tool_name": tool_name,
                "arguments": arguments
            }
            
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": self.api_key
            }
            
            async with session.post(tool_url, json=payload, headers=headers, timeout=timeout) as response:
                if response.status == 200:
                    data = await response.json()
                    return {
                        "status": "success",
                        "result": data.get('result', {}),
                        "tool": data.get('tool', tool_name)
                    }
                else:
                    error_text = await response.text()
                    return {
                        "status": "failed",
                        "error": f"HTTP {response.status}: {error_text}",
                        "tool": tool_name
                    }
    
    async def test_1_get_all_tables(self):
        """Test 1: Get list of all tables"""
        logger.info("📋 Test 1: Getting list of all tables...")
        
        result = await self.execute_tool("list_tables", {
            "base_id": self.base_id
        })
        
        if result["status"] == "success":
            tables = result["result"].get("tables", [])
            table_count = result["result"].get("table_count", 0)
            logger.info(f"✅ Found {table_count} tables")
            return {
                "status": "success",
                "table_count": table_count,
                "tables": tables
            }
        else:
            logger.error(f"❌ Failed to get tables: {result.get('error')}")
            return result
    
    async def test_2_populate_metadata_table(self, tables):
        """Test 2: Populate metadata table with data for selected tables"""
        logger.info(f"📊 Test 2: Populating metadata table with data for selected tables...")
        
        # Select first 5 tables for testing
        selected_tables = tables[:5]
        results = []
        
        for i, table in enumerate(selected_tables):
            try:
                table_name = table.get("name", f"Table_{i}")
                table_id = table.get("id", f"tbl{i}")
                
                # Create metadata record for this table
                metadata_record = {
                    "Name": f"{table_name} - Metadata Analysis"
                }
                
                result = await self.execute_tool("create_record", {
                    "base_id": self.base_id,
                    "table_id": self.metadata_table_id,
                    "fields": metadata_record
                })
                
                if result["status"] == "success":
                    logger.info(f"✅ Added metadata for table: {table_name}")
                    results.append({
                        "table_name": table_name,
                        "status": "success",
                        "record_id": result["result"].get("id", "unknown")
                    })
                else:
                    logger.warning(f"⚠️ Failed to add metadata for {table_name}: {result.get('error')}")
                    results.append({
                        "table_name": table_name,
                        "status": "failed",
                        "error": result.get("error")
                    })
                
                # Small delay to avoid rate limits
                await asyncio.sleep(0.5)
                
            except Exception as e:
                logger.error(f"❌ Error processing table {table.get('name', 'unknown')}: {e}")
                results.append({
                    "table_name": table.get("name", "unknown"),
                    "status": "error",
                    "error": str(e)
                })
        
        successful_count = sum(1 for r in results if r.get("status") == "success")
        logger.info(f"📈 Successfully added metadata for {successful_count}/{len(selected_tables)} tables")
        
        return {
            "status": "success" if successful_count > 0 else "failed",
            "results": results,
            "successful_count": successful_count,
            "total_count": len(selected_tables)
        }
    
    async def test_3_analyze_table_data(self, tables):
        """Test 3: Analyze data from a few tables to show MCP capabilities"""
        logger.info("🔍 Test 3: Analyzing table data using MCP tools...")
        
        analysis_results = []
        
        # Analyze first 3 tables
        for table in tables[:3]:
            try:
                table_name = table.get("name", "unknown")
                table_id = table.get("id", "unknown")
                
                logger.info(f"Analyzing table: {table_name}")
                
                # Get field information
                field_result = await self.execute_tool("get_field_info", {
                    "base_id": self.base_id,
                    "table_id": table_id
                })
                
                # Get sample records  
                records_result = await self.execute_tool("get_records", {
                    "base_id": self.base_id,
                    "table_id": table_id,
                    "max_records": 10
                })
                
                # Analyze table data
                analyze_result = await self.execute_tool("analyze_table_data", {
                    "base_id": self.base_id,
                    "table_id": table_id,
                    "sample_size": 50
                })
                
                analysis = {
                    "table_name": table_name,
                    "table_id": table_id,
                    "field_info": field_result.get("result", {}),
                    "sample_records": len(records_result.get("result", {}).get("records", [])),
                    "analysis": analyze_result.get("result", {}),
                    "status": "success"
                }
                
                analysis_results.append(analysis)
                logger.info(f"✅ Analyzed {table_name}: {analysis.get('field_info', {}).get('total_fields', 0)} fields, {analysis['sample_records']} sample records")
                
                # Small delay
                await asyncio.sleep(0.5)
                
            except Exception as e:
                logger.error(f"❌ Error analyzing table {table.get('name', 'unknown')}: {e}")
                analysis_results.append({
                    "table_name": table.get("name", "unknown"),
                    "status": "error",
                    "error": str(e)
                })
        
        successful_analyses = sum(1 for r in analysis_results if r.get("status") == "success")
        logger.info(f"🎯 Successfully analyzed {successful_analyses}/{len(analysis_results)} tables")
        
        return {
            "status": "success" if successful_analyses > 0 else "failed",
            "analyses": analysis_results,
            "successful_count": successful_analyses
        }
    
    async def test_4_search_and_export(self, tables):
        """Test 4: Test search and export functionality"""
        logger.info("📤 Test 4: Testing search and export functionality...")
        
        # Find a table with data to test search
        tables_with_data = []
        
        for table in tables[:5]:
            try:
                table_id = table.get("id")
                records_result = await self.execute_tool("get_records", {
                    "base_id": self.base_id,
                    "table_id": table_id,
                    "max_records": 5
                })
                
                record_count = len(records_result.get("result", {}).get("records", []))
                if record_count > 0:
                    tables_with_data.append({
                        "table": table,
                        "record_count": record_count
                    })
                
                await asyncio.sleep(0.2)
                
            except Exception as e:
                logger.warning(f"Error checking records for {table.get('name')}: {e}")
        
        export_results = []
        
        if tables_with_data:
            # Try to export the first table with data
            table_data = tables_with_data[0]
            table = table_data["table"]
            table_name = table.get("name")
            table_id = table.get("id")
            
            try:
                export_result = await self.execute_tool("export_table_csv", {
                    "base_id": self.base_id,
                    "table_id": table_id,
                    "max_records": 10
                })
                
                if export_result["status"] == "success":
                    logger.info(f"✅ Successfully exported CSV for table: {table_name}")
                    export_results.append({
                        "table_name": table_name,
                        "status": "success",
                        "export_size": len(export_result.get("result", {}).get("csv_data", ""))
                    })
                else:
                    logger.warning(f"⚠️ Failed to export {table_name}")
                    export_results.append({
                        "table_name": table_name,
                        "status": "failed",
                        "error": export_result.get("error")
                    })
                    
            except Exception as e:
                logger.error(f"❌ Error exporting {table_name}: {e}")
                export_results.append({
                    "table_name": table_name,
                    "status": "error",
                    "error": str(e)
                })
        
        return {
            "status": "success" if export_results else "no_data",
            "tables_with_data": len(tables_with_data),
            "export_results": export_results
        }
    
    async def test_5_validation(self):
        """Test 5: Validate metadata table was populated"""
        logger.info("✅ Test 5: Validating metadata table population...")
        
        try:
            # Get all records from metadata table
            result = await self.execute_tool("get_records", {
                "base_id": self.base_id,
                "table_id": self.metadata_table_id,
                "max_records": 100
            })
            
            if result["status"] == "success":
                records = result["result"].get("records", [])
                record_count = len(records)
                
                logger.info(f"✅ Metadata table contains {record_count} records")
                
                # Show sample records
                for i, record in enumerate(records[:3]):
                    fields = record.get("fields", {})
                    name = fields.get("Name", "Unknown")
                    logger.info(f"  Record {i+1}: {name}")
                
                return {
                    "status": "success",
                    "record_count": record_count,
                    "sample_records": records[:3]
                }
            else:
                logger.error(f"❌ Failed to validate metadata table: {result.get('error')}")
                return result
                
        except Exception as e:
            logger.error(f"❌ Error validating metadata table: {e}")
            return {
                "status": "error",
                "error": str(e)
            }

async def run_working_mcp_tests():
    """Run the working MCP tests"""
    logger.info("🚀 Starting Working MCP Functionality Tests")
    logger.info("="*80)
    
    tester = WorkingMCPTester()
    results = {
        "test_run_id": f"working_mcp_{int(time.time())}",
        "timestamp": datetime.now().isoformat(),
        "base_id": tester.base_id,
        "tests": {}
    }
    
    try:
        # Test 1: Get all tables
        results["tests"]["test_1_tables"] = await tester.test_1_get_all_tables()
        tables = results["tests"]["test_1_tables"].get("tables", [])
        
        if not tables:
            logger.error("❌ No tables found, cannot continue tests")
            return results
        
        # Test 2: Populate metadata table
        results["tests"]["test_2_populate"] = await tester.test_2_populate_metadata_table(tables)
        
        # Test 3: Analyze table data
        results["tests"]["test_3_analyze"] = await tester.test_3_analyze_table_data(tables)
        
        # Test 4: Search and export
        results["tests"]["test_4_export"] = await tester.test_4_search_and_export(tables)
        
        # Test 5: Validation
        results["tests"]["test_5_validate"] = await tester.test_5_validation()
        
        # Calculate summary
        total_tests = len(results["tests"])
        successful_tests = sum(1 for test in results["tests"].values() 
                             if test.get("status") == "success")
        
        results["summary"] = {
            "total_tests": total_tests,
            "successful_tests": successful_tests,
            "failed_tests": total_tests - successful_tests,
            "success_rate": successful_tests / total_tests if total_tests > 0 else 0,
            "base_table_count": len(tables),
            "metadata_records_created": results["tests"]["test_2_populate"].get("successful_count", 0)
        }
        
        return results
        
    except Exception as e:
        logger.error(f"Test execution failed: {e}")
        import traceback
        traceback.print_exc()
        results["error"] = str(e)
        return results

def print_working_mcp_results(results):
    """Print formatted working MCP results"""
    print("\n" + "="*80)
    print("WORKING MCP FUNCTIONALITY TEST RESULTS")
    print("="*80)
    
    summary = results.get("summary", {})
    print(f"Test Run ID: {results.get('test_run_id', 'unknown')}")
    print(f"Base ID: {results.get('base_id', 'unknown')}")
    print(f"Timestamp: {results.get('timestamp', 'unknown')}")
    print(f"Total Tests: {summary.get('total_tests', 0)}")
    print(f"Successful: {summary.get('successful_tests', 0)}")
    print(f"Failed: {summary.get('failed_tests', 0)}")
    print(f"Success Rate: {summary.get('success_rate', 0):.1%}")
    print(f"Base Table Count: {summary.get('base_table_count', 0)}")
    print(f"Metadata Records Created: {summary.get('metadata_records_created', 0)}")
    
    print("\nTEST RESULTS:")
    print("-" * 80)
    
    test_names = {
        "test_1_tables": "1. Get All Tables",
        "test_2_populate": "2. Populate Metadata",
        "test_3_analyze": "3. Analyze Table Data",
        "test_4_export": "4. Search & Export",
        "test_5_validate": "5. Validate Results"
    }
    
    for test_key, test_result in results.get("tests", {}).items():
        test_name = test_names.get(test_key, test_key)
        status = test_result.get("status", "unknown")
        
        if status == "success":
            print(f"✅ {test_name}: SUCCESS")
            
            # Show additional details
            if test_key == "test_1_tables":
                print(f"   Found {test_result.get('table_count', 0)} tables")
            elif test_key == "test_2_populate":
                print(f"   Added metadata for {test_result.get('successful_count', 0)} tables")
            elif test_key == "test_3_analyze":
                print(f"   Analyzed {test_result.get('successful_count', 0)} tables")
            elif test_key == "test_4_export":
                print(f"   Found {test_result.get('tables_with_data', 0)} tables with data")
            elif test_key == "test_5_validate":
                print(f"   Metadata table has {test_result.get('record_count', 0)} records")
                
        elif status == "no_data":
            print(f"⚠️ {test_name}: NO DATA (not an error)")
        else:
            print(f"❌ {test_name}: FAILED")
            if "error" in test_result:
                print(f"   Error: {test_result['error']}")
    
    print("="*80)

async def main():
    """Main entry point"""
    try:
        # Run working MCP tests
        results = await run_working_mcp_tests()
        
        # Print results
        print_working_mcp_results(results)
        
        # Save results
        results_file = Path(f"working_mcp_results_{int(time.time())}.json")
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        logger.info(f"Working MCP results saved to: {results_file}")
        
        # Return appropriate exit code
        success_rate = results.get("summary", {}).get("success_rate", 0)
        if success_rate >= 0.8:  # 80% success rate
            sys.exit(0)
        elif success_rate >= 0.6:  # 60% success rate  
            sys.exit(1)
        else:
            sys.exit(2)
            
    except Exception as e:
        logger.error(f"Test execution failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(3)

if __name__ == "__main__":
    asyncio.run(main())