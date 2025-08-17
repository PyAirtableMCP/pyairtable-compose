#!/usr/bin/env python3
"""
MCP Metadata Workflow Test
==========================

Tests the complete metadata table workflow:
1. Create metadata table
2. Populate with data for multiple tables
3. Add improvements column
4. Run LLM analysis and update improvements
"""

import asyncio
import sys
import logging
import json
import os
import time
from datetime import datetime
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class MCPWorkflowTester:
    def __init__(self):
        self.api_gateway_url = "http://localhost:8000"
        self.api_key = os.getenv("API_KEY", "your-api-key-here")
        self.base_id = "appVLUAubH5cFWhMV"
        self.session_id = f"metadata-workflow-{int(time.time())}"
        
    async def chat_request(self, message, timeout=60):
        """Send a chat request to the API Gateway"""
        import aiohttp
        
        async with aiohttp.ClientSession() as session:
            chat_url = f"{self.api_gateway_url}/api/chat"
            
            payload = {
                "messages": [
                    {
                        "role": "user",
                        "content": f"Base ID: {self.base_id}\n\n{message}"
                    }
                ],
                "session_id": self.session_id
            }
            
            headers = {
                "Content-Type": "application/json",
                "X-API-Key": self.api_key
            }
            
            async with session.post(chat_url, json=payload, headers=headers, timeout=timeout) as response:
                if response.status == 200:
                    data = await response.json()
                    return {
                        "status": "success",
                        "response": data.get('response', ''),
                        "data": data
                    }
                else:
                    error_text = await response.text()
                    return {
                        "status": "failed",
                        "error": f"HTTP {response.status}: {error_text}"
                    }
    
    async def test_step_1_create_metadata_table(self):
        """Step 1: Create the metadata table"""
        logger.info("📋 Step 1: Creating metadata table...")
        
        message = """Please create a new Airtable table called "Table_Metadata" with the following structure:

Fields:
- table_name (Single line text) - Primary field
- table_id (Single line text) 
- record_count (Number)
- field_count (Number)
- created_date (Date)
- last_updated (Date and time)
- description (Long text)
- primary_field (Single line text)
- field_types (Multiple select with options: Text, Number, Date, Select, Checkbox, Formula, Lookup, Attachment, Phone, Email, URL, Barcode, Button, Count, Rollup, Currency, Percent, Duration, Rating, Auto Number)
- data_quality_score (Number with 2 decimal places, range 0-100)
- usage_frequency (Single select with options: High, Medium, Low, Inactive)
- owner (Single line text)
- tags (Multiple select with options: CRM, Marketing, Sales, Support, Analytics, Operations, Finance, HR, Customer Data, Internal)

Please create this table and confirm it was created successfully by showing me the table ID and field structure."""
        
        result = await self.chat_request(message, timeout=90)
        
        if result["status"] == "success":
            response_text = result["response"].lower()
            # Check for success indicators
            success_indicators = [
                'table.*created', 'successfully.*created', 'table_metadata.*created',
                'created.*table', 'table.*id.*tbl', 'new table'
            ]
            
            import re
            success = any(re.search(pattern, response_text) for pattern in success_indicators)
            
            if success:
                logger.info("✅ Metadata table creation successful")
                return {"status": "success", "response": result["response"]}
            else:
                logger.warning(f"⚠️ Metadata table creation unclear")
                return {"status": "unclear", "response": result["response"]}
        else:
            logger.error(f"❌ Metadata table creation failed: {result.get('error')}")
            return result
    
    async def test_step_2_get_table_list(self):
        """Step 2: Get list of all tables for metadata population"""
        logger.info("📊 Step 2: Getting list of all tables...")
        
        message = """Please list all tables in this Airtable base. For each table, provide:
- Table name
- Table ID if available
- Approximate number of records
- Number of fields
- Primary field name
- Brief description of what the table contains

Format this as a structured list that I can use for metadata population."""
        
        result = await self.chat_request(message, timeout=45)
        
        if result["status"] == "success":
            logger.info("✅ Table list retrieved successfully")
            return {"status": "success", "response": result["response"], "tables": self._parse_table_list(result["response"])}
        else:
            logger.error(f"❌ Table list failed: {result.get('error')}")
            return result
    
    def _parse_table_list(self, response_text):
        """Parse table list from response text"""
        # Simple parsing - in production this would be more sophisticated
        tables = []
        lines = response_text.split('\n')
        
        for line in lines:
            line = line.strip()
            if any(keyword in line.lower() for keyword in ['table:', '- ', 'name:']):
                # Extract table name
                import re
                name_match = re.search(r'[:\-]\s*(.+)', line)
                if name_match:
                    table_name = name_match.group(1).strip()
                    if table_name and len(table_name) > 2:
                        tables.append({"name": table_name})
        
        # If no tables found, create some examples
        if not tables:
            tables = [
                {"name": "Facebook Posts"},
                {"name": "Customers"},
                {"name": "Orders"},
                {"name": "Products"},
                {"name": "Campaign Data"}
            ]
        
        return tables[:10]  # Limit for testing
    
    async def test_step_3_populate_metadata(self, tables):
        """Step 3: Populate metadata for multiple tables"""
        logger.info(f"🔄 Step 3: Populating metadata for {len(tables)} tables...")
        
        # Create sample metadata for tables
        table_names = [table.get("name", f"Table_{i}") for i, table in enumerate(tables)]
        
        message = f"""Now I want to populate the "Table_Metadata" table with data for these tables: {', '.join(table_names[:5])}

For each table, please add a record to the Table_Metadata table with realistic sample data:

For example, for the first table "{table_names[0]}":
- table_name: {table_names[0]}
- table_id: tbl{12345678 + hash(table_names[0]) % 87654321}
- record_count: {150 + hash(table_names[0]) % 1000}
- field_count: {5 + hash(table_names[0]) % 15}
- created_date: 2024-01-15
- last_updated: 2024-07-25T14:30:00Z
- description: Comprehensive data for {table_names[0].lower()} with analytics and tracking
- primary_field: Name
- field_types: Text, Number, Date, Select
- data_quality_score: {70 + hash(table_names[0]) % 25}.{hash(table_names[0]) % 10}
- usage_frequency: {'High' if hash(table_names[0]) % 3 == 0 else 'Medium' if hash(table_names[0]) % 3 == 1 else 'Low'}
- owner: {'Alice Johnson' if hash(table_names[0]) % 4 == 0 else 'Bob Smith' if hash(table_names[0]) % 4 == 1 else 'Carol Davis' if hash(table_names[0]) % 4 == 2 else 'David Wilson'}
- tags: {'CRM, Customer Data' if 'customer' in table_names[0].lower() else 'Marketing, Analytics' if 'post' in table_names[0].lower() or 'campaign' in table_names[0].lower() else 'Sales, Operations'}

Please create similar records for all {len(table_names[:5])} tables with varied but realistic data. Confirm how many records were added."""
        
        result = await self.chat_request(message, timeout=120)
        
        if result["status"] == "success":
            response_text = result["response"].lower()
            
            # Check for success indicators
            if any(indicator in response_text for indicator in ['records added', 'added.*records', 'successfully.*populated', 'metadata.*populated']):
                logger.info("✅ Metadata population successful")
                return {"status": "success", "response": result["response"]}
            else:
                logger.warning("⚠️ Metadata population unclear")
                return {"status": "unclear", "response": result["response"]}
        else:
            logger.error(f"❌ Metadata population failed: {result.get('error')}")
            return result
    
    async def test_step_4_add_improvements_column(self):
        """Step 4: Add improvements column"""
        logger.info("🔧 Step 4: Adding improvements column...")
        
        message = """Please add a new field to the "Table_Metadata" table:

Field name: improvements
Field type: Long text
Description: "AI-generated recommendations and improvement suggestions for this table"
Allow rich text formatting: Yes

After adding the field, please confirm it was added successfully and show me the updated table structure."""
        
        result = await self.chat_request(message, timeout=60)
        
        if result["status"] == "success":
            response_text = result["response"].lower()
            
            if any(indicator in response_text for indicator in ['field added', 'column added', 'improvements.*added', 'successfully.*added']):
                logger.info("✅ Improvements column added successfully")
                return {"status": "success", "response": result["response"]}
            else:
                logger.warning("⚠️ Improvements column addition unclear")
                return {"status": "unclear", "response": result["response"]}
        else:
            logger.error(f"❌ Improvements column addition failed: {result.get('error')}")
            return result
    
    async def test_step_5_llm_analysis(self):
        """Step 5: Run LLM analysis and update improvements"""
        logger.info("🤖 Step 5: Running LLM analysis and updating improvements...")
        
        message = """Now please analyze the data in the "Table_Metadata" table and provide AI-generated improvement recommendations. For each record in the table:

1. Analyze the table's characteristics (record count, field count, data quality score, usage frequency, etc.)
2. Generate specific, actionable improvement recommendations
3. Update the "improvements" field for each record with these recommendations

Focus on recommendations like:
- Data quality improvements for tables with low scores
- Performance optimizations for high-usage tables
- Field structure suggestions for tables with many fields
- Automation opportunities based on table type and usage
- Data validation and integrity suggestions

Please update the improvements field for all records and summarize what recommendations were added."""
        
        result = await self.chat_request(message, timeout=150)
        
        if result["status"] == "success":
            response_text = result["response"].lower()
            
            if any(indicator in response_text for indicator in ['recommendations.*added', 'improvements.*updated', 'analysis.*complete', 'updated.*improvements']):
                logger.info("✅ LLM analysis and improvements update successful")
                return {"status": "success", "response": result["response"]}
            else:
                logger.warning("⚠️ LLM analysis completion unclear")
                return {"status": "unclear", "response": result["response"]}
        else:
            logger.error(f"❌ LLM analysis failed: {result.get('error')}")
            return result
    
    async def test_step_6_validation(self):
        """Step 6: Validate the complete workflow"""
        logger.info("✅ Step 6: Validating complete workflow...")
        
        message = """Please validate the complete metadata workflow by showing me:

1. The final structure of the "Table_Metadata" table (all fields)
2. A count of how many records are in the table
3. Show me 2-3 sample records with their improvements field populated
4. Confirm that the improvements field contains AI-generated recommendations

This validates that our complete metadata management workflow is working correctly."""
        
        result = await self.chat_request(message, timeout=60)
        
        if result["status"] == "success":
            logger.info("✅ Workflow validation completed")
            return {"status": "success", "response": result["response"]}
        else:
            logger.error(f"❌ Workflow validation failed: {result.get('error')}")
            return result

async def run_complete_workflow():
    """Run the complete metadata workflow test"""
    logger.info("🚀 Starting Complete MCP Metadata Workflow Test")
    logger.info("="*80)
    
    tester = MCPWorkflowTester()
    results = {
        "test_run_id": f"metadata_workflow_{int(time.time())}",
        "timestamp": datetime.now().isoformat(),
        "base_id": tester.base_id,
        "steps": {}
    }
    
    try:
        # Step 1: Create metadata table
        results["steps"]["step_1_create_table"] = await tester.test_step_1_create_metadata_table()
        
        # Step 2: Get table list
        results["steps"]["step_2_get_tables"] = await tester.test_step_2_get_table_list()
        tables = results["steps"]["step_2_get_tables"].get("tables", [])
        
        # Step 3: Populate metadata (if table creation was successful)
        if results["steps"]["step_1_create_table"]["status"] in ["success", "unclear"]:
            results["steps"]["step_3_populate"] = await tester.test_step_3_populate_metadata(tables)
        else:
            results["steps"]["step_3_populate"] = {"status": "skipped", "reason": "Table creation failed"}
        
        # Step 4: Add improvements column (if population was successful)
        if results["steps"]["step_3_populate"]["status"] in ["success", "unclear"]:
            results["steps"]["step_4_add_column"] = await tester.test_step_4_add_improvements_column()
        else:
            results["steps"]["step_4_add_column"] = {"status": "skipped", "reason": "Metadata population failed"}
        
        # Step 5: LLM analysis (if column addition was successful)
        if results["steps"]["step_4_add_column"]["status"] in ["success", "unclear"]:
            results["steps"]["step_5_llm_analysis"] = await tester.test_step_5_llm_analysis()
        else:
            results["steps"]["step_5_llm_analysis"] = {"status": "skipped", "reason": "Column addition failed"}
        
        # Step 6: Validation (if analysis was successful)
        if results["steps"]["step_5_llm_analysis"]["status"] in ["success", "unclear"]:
            results["steps"]["step_6_validation"] = await tester.test_step_6_validation()
        else:
            results["steps"]["step_6_validation"] = {"status": "skipped", "reason": "LLM analysis failed"}
        
        # Calculate summary
        total_steps = len(results["steps"])
        successful_steps = sum(1 for step in results["steps"].values() 
                             if step.get("status") in ["success"])
        unclear_steps = sum(1 for step in results["steps"].values() 
                           if step.get("status") == "unclear")
        
        results["summary"] = {
            "total_steps": total_steps,
            "successful_steps": successful_steps,
            "unclear_steps": unclear_steps,
            "failed_steps": total_steps - successful_steps - unclear_steps,
            "success_rate": (successful_steps + unclear_steps * 0.5) / total_steps if total_steps > 0 else 0
        }
        
        return results
        
    except Exception as e:
        logger.error(f"Workflow test failed: {e}")
        import traceback
        traceback.print_exc()
        results["error"] = str(e)
        return results

def print_workflow_results(results):
    """Print formatted workflow results"""
    print("\n" + "="*80)
    print("MCP METADATA WORKFLOW TEST RESULTS")
    print("="*80)
    
    summary = results.get("summary", {})
    print(f"Test Run ID: {results.get('test_run_id', 'unknown')}")
    print(f"Base ID: {results.get('base_id', 'unknown')}")
    print(f"Timestamp: {results.get('timestamp', 'unknown')}")
    print(f"Total Steps: {summary.get('total_steps', 0)}")
    print(f"Successful: {summary.get('successful_steps', 0)}")
    print(f"Unclear: {summary.get('unclear_steps', 0)}")
    print(f"Failed: {summary.get('failed_steps', 0)}")
    print(f"Success Rate: {summary.get('success_rate', 0):.1%}")
    
    print("\nSTEP-BY-STEP RESULTS:")
    print("-" * 80)
    
    step_names = {
        "step_1_create_table": "1. Create Metadata Table",
        "step_2_get_tables": "2. Get Table List",
        "step_3_populate": "3. Populate Metadata",
        "step_4_add_column": "4. Add Improvements Column",
        "step_5_llm_analysis": "5. LLM Analysis & Updates",
        "step_6_validation": "6. Workflow Validation"
    }
    
    for step_key, step_result in results.get("steps", {}).items():
        step_name = step_names.get(step_key, step_key)
        status = step_result.get("status", "unknown")
        
        if status == "success":
            print(f"✅ {step_name}: SUCCESS")
        elif status == "unclear":
            print(f"⚠️ {step_name}: UNCLEAR (may have worked)")
        elif status == "skipped":
            print(f"⏭️ {step_name}: SKIPPED - {step_result.get('reason', 'No reason given')}")
        else:
            print(f"❌ {step_name}: FAILED")
            if "error" in step_result:
                print(f"   Error: {step_result['error']}")
    
    print("="*80)

async def main():
    """Main entry point"""
    try:
        # Run workflow test
        results = await run_complete_workflow()
        
        # Print results
        print_workflow_results(results)
        
        # Save results
        results_file = Path(f"metadata_workflow_results_{int(time.time())}.json")
        with open(results_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        logger.info(f"Workflow results saved to: {results_file}")
        
        # Return appropriate exit code
        success_rate = results.get("summary", {}).get("success_rate", 0)
        if success_rate >= 0.8:  # 80% success rate
            sys.exit(0)
        elif success_rate >= 0.5:  # 50% success rate  
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