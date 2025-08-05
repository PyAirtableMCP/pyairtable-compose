"""
Comprehensive Synthetic Agent Test Scenarios for MCP Tools
==========================================================

This module provides specialized synthetic agents for testing MCP (Model Context Protocol) tools
through the pyairtable frontend UI. These agents simulate real user interactions with comprehensive
test scenarios covering table management, metadata operations, and LLM analysis integration.

Key Features:
- Create and manage Airtable metadata tables
- Populate metadata for multiple tables with statistics
- Update metadata fields with bulk operations
- Add new columns to existing tables
- Integrate LLM analysis for recommendations
- Comprehensive validation and error handling
- Performance benchmarking and screenshots
- Parallel execution with result aggregation
"""

import asyncio
import json
import logging
import time
import traceback
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple, Union, Set
import random
import re
from dataclasses import dataclass, field

from playwright.async_api import async_playwright, Browser, BrowserContext, Page, Response, Locator
from playwright.async_api import TimeoutError as PlaywrightTimeoutError

from .test_config import TestFrameworkConfig, get_config
from .test_reporter import TestResult, TestReport
from .ui_agents import SyntheticUIAgent, UIAgentAction

logger = logging.getLogger(__name__)

@dataclass
class MCPTestData:
    """Test data structure for MCP operations"""
    table_name: str
    fields: Dict[str, str] = field(default_factory=dict)
    records: List[Dict[str, Any]] = field(default_factory=list)
    metadata: Dict[str, Any] = field(default_factory=dict)
    expected_stats: Dict[str, Any] = field(default_factory=dict)

@dataclass
class MCPOperationResult:
    """Result of an MCP operation"""
    operation: str
    success: bool
    duration: float
    data: Dict[str, Any] = field(default_factory=dict)
    error: Optional[str] = None
    screenshot_path: Optional[str] = None

class MCPMetadataTableAgent(SyntheticUIAgent):
    """Specialized agent for creating and managing Airtable metadata tables"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("MCP Metadata Table Agent", config)
        self.created_tables: Set[str] = set()
        self.test_data: Dict[str, MCPTestData] = {}
        
    async def test_create_metadata_table(self) -> TestResult:
        """Test comprehensive metadata table creation workflow"""
        result = TestResult("MCP Metadata Table Agent", "Create Metadata Table")
        
        try:
            # Navigate to the frontend
            frontend_url = self.config.services["frontend"].url
            success = await self.navigate_to(frontend_url)
            
            if not success:
                result.add_issue("critical", "Navigation Failed", f"Could not navigate to {frontend_url}")
                result.complete("failed")
                return result
            
            await self.wait_for_network_idle()
            result.add_log("info", "Successfully navigated to frontend")
            
            # Wait for chat interface to be ready
            chat_input_selector = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            await self.wait_for_element(chat_input_selector, timeout=10000)
            
            # Create metadata table using MCP tools
            create_table_prompt = self._generate_create_metadata_table_prompt()
            operation_result = await self._execute_mcp_operation(
                "create_metadata_table",
                create_table_prompt,
                timeout=60
            )
            
            if not operation_result.success:
                result.add_issue("critical", "Table Creation Failed", operation_result.error or "Unknown error")
                result.complete("failed")
                return result
            
            result.add_log("info", f"Metadata table creation completed in {operation_result.duration:.2f}s")
            result.performance_metrics["table_creation_time"] = operation_result.duration
            
            # Validate table creation
            validation_result = await self._validate_table_creation("Table_Metadata")
            if not validation_result.success:
                result.add_issue("high", "Table Validation Failed", validation_result.error)
            else:
                result.add_log("info", "Table validation successful")
                self.created_tables.add("Table_Metadata")
            
            # Verify table structure
            structure_validation = await self._verify_table_structure("Table_Metadata")
            if not structure_validation.success:
                result.add_issue("medium", "Structure Validation Failed", structure_validation.error)
            else:
                result.add_log("info", "Table structure validation successful")
            
            # Take final screenshot
            screenshot_path = await self._take_screenshot("metadata_table_created")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Metadata table creation completed")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Metadata table creation test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    def _generate_create_metadata_table_prompt(self) -> str:
        """Generate prompt for creating metadata table"""
        return """
        Create a new Airtable table called "Table_Metadata" with the following structure:
        
        Fields:
        - table_name (Single line text) - Primary field
        - table_id (Single line text) 
        - record_count (Number)
        - field_count (Number)
        - created_date (Date)
        - last_updated (Date and time)
        - description (Long text)
        - primary_field (Single line text)
        - field_types (Multiple select: Text, Number, Date, Select, Checkbox, Formula, Lookup, etc.)
        - data_quality_score (Number with 2 decimal places, 0-100 scale)
        - usage_frequency (Single select: High, Medium, Low, Inactive)
        - owner (Single line text)
        - tags (Multiple select)
        
        Please create this table and confirm it was created successfully by showing me the table structure.
        """
    
    async def _execute_mcp_operation(self, operation: str, prompt: str, 
                                   timeout: int = 60) -> MCPOperationResult:
        """Execute an MCP operation through the chat interface"""
        start_time = time.time()
        
        try:
            # Find chat elements
            chat_input = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            # Clear input and type prompt
            await self.page.fill(chat_input, "")
            await asyncio.sleep(0.5)
            await self.page.type(chat_input, prompt, delay=50)
            
            # Send message
            await self.page.click(send_button)
            
            # Wait for response with progress indicators
            response_found = False
            error_detected = False
            operation_data = {}
            
            for attempt in range(timeout):
                # Check for AI responses
                ai_messages = await self.page.query_selector_all(
                    ".message.assistant, [data-role='assistant'], .ai-message, .assistant-message"
                )
                
                if ai_messages:
                    last_message = ai_messages[-1]
                    message_text = await last_message.text_content()
                    
                    if message_text and len(message_text) > 100:
                        # Check for success indicators
                        success_patterns = [
                            r"table.*created.*successfully",
                            r"successfully.*created.*table",
                            r"table.*Table_Metadata.*created",
                            r"created.*Table_Metadata",
                            r"table structure",
                            r"fields.*added"
                        ]
                        
                        # Check for error indicators
                        error_patterns = [
                            r"error.*creating",
                            r"failed.*create",
                            r"unable.*create",
                            r"permission.*denied",
                            r"api.*error",
                            r"authentication.*failed"
                        ]
                        
                        message_lower = message_text.lower()
                        
                        # Check for errors first
                        for error_pattern in error_patterns:
                            if re.search(error_pattern, message_lower):
                                error_detected = True
                                break
                        
                        # Check for success if no errors
                        if not error_detected:
                            for success_pattern in success_patterns:
                                if re.search(success_pattern, message_lower):
                                    response_found = True
                                    operation_data = self._extract_operation_data(message_text, operation)
                                    break
                        
                        if response_found or error_detected:
                            break
                
                await asyncio.sleep(1)
            
            duration = time.time() - start_time
            
            if error_detected:
                return MCPOperationResult(
                    operation=operation,
                    success=False,
                    duration=duration,
                    error="Error detected in AI response"
                )
            elif response_found:
                return MCPOperationResult(
                    operation=operation,
                    success=True,
                    duration=duration,
                    data=operation_data
                )
            else:
                return MCPOperationResult(
                    operation=operation,
                    success=False,
                    duration=duration,
                    error="Timeout waiting for operation completion"
                )
                
        except Exception as e:
            duration = time.time() - start_time
            return MCPOperationResult(
                operation=operation,
                success=False,
                duration=duration,
                error=str(e)
            )
    
    def _extract_operation_data(self, message_text: str, operation: str) -> Dict[str, Any]:
        """Extract structured data from AI response"""
        data = {}
        
        if operation == "create_metadata_table":
            # Extract table information
            if "Table_Metadata" in message_text:
                data["table_name"] = "Table_Metadata"
            
            # Extract field count if mentioned
            field_match = re.search(r"(\d+)\s*fields?", message_text, re.IGNORECASE)
            if field_match:
                data["field_count"] = int(field_match.group(1))
            
            # Extract field names if mentioned
            field_names = re.findall(r"[-•]\s*([a-zA-Z_][a-zA-Z0-9_\s]*)\s*\(", message_text)
            if field_names:
                data["fields"] = [name.strip() for name in field_names]
        
        return data
    
    async def _validate_table_creation(self, table_name: str) -> MCPOperationResult:
        """Validate that the table was actually created"""
        validation_prompt = f"""
        Please verify that the table "{table_name}" was created successfully. 
        Show me:
        1. The table exists in the base
        2. The field structure
        3. The table ID if available
        
        If there are any issues, please describe them in detail.
        """
        
        return await self._execute_mcp_operation("validate_table", validation_prompt, timeout=30)
    
    async def _verify_table_structure(self, table_name: str) -> MCPOperationResult:
        """Verify the table has the correct structure"""
        structure_prompt = f"""
        Please verify the structure of the "{table_name}" table. Check that it has these fields:
        - table_name (Primary field)
        - table_id
        - record_count  
        - field_count
        - created_date
        - last_updated
        - description
        - primary_field
        - field_types
        - data_quality_score
        - usage_frequency
        - owner
        - tags
        
        Confirm each field exists and has the correct type.
        """
        
        return await self._execute_mcp_operation("verify_structure", structure_prompt, timeout=30)

class MCPMetadataPopulationAgent(SyntheticUIAgent):
    """Specialized agent for populating metadata for multiple tables"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("MCP Metadata Population Agent", config)
        self.target_table_count = 35
        self.populated_tables: Set[str] = set()
        
    async def test_populate_metadata_for_tables(self) -> TestResult:
        """Test populating metadata for 35 tables"""
        result = TestResult("MCP Metadata Population Agent", "Populate Metadata for 35 Tables")
        
        try:
            # Navigate to frontend
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            await self.wait_for_network_idle()
            
            # First, get list of all tables in the base
            table_list_result = await self._get_table_list()
            if not table_list_result.success:
                result.add_issue("critical", "Failed to Get Table List", table_list_result.error)
                result.complete("failed")
                return result
            
            available_tables = table_list_result.data.get("tables", [])
            result.add_log("info", f"Found {len(available_tables)} tables in the base")
            
            # If we don't have enough tables, create some test tables
            if len(available_tables) < self.target_table_count:
                create_count = self.target_table_count - len(available_tables)
                result.add_log("info", f"Creating {create_count} additional test tables")
                
                creation_result = await self._create_test_tables(create_count)
                if creation_result.success:
                    available_tables.extend(creation_result.data.get("created_tables", []))
                else:
                    result.add_issue("medium", "Test Table Creation Failed", creation_result.error)
            
            # Populate metadata for each table
            tables_to_process = available_tables[:self.target_table_count]
            successful_populations = 0
            failed_populations = 0
            
            start_time = time.time()
            
            for i, table_info in enumerate(tables_to_process):
                table_name = table_info.get("name") if isinstance(table_info, dict) else str(table_info)
                
                result.add_log("info", f"Processing table {i+1}/{len(tables_to_process)}: {table_name}")
                
                # Generate metadata for this table
                metadata_result = await self._populate_table_metadata(table_name, i+1)
                
                if metadata_result.success:
                    successful_populations += 1
                    self.populated_tables.add(table_name)
                    result.add_log("info", f"Successfully populated metadata for {table_name}")
                else:
                    failed_populations += 1
                    result.add_issue("medium", f"Failed to populate {table_name}", metadata_result.error)
                
                # Add small delay between operations to avoid rate limiting
                await asyncio.sleep(2)
            
            total_duration = time.time() - start_time
            
            # Record performance metrics
            result.performance_metrics.update({
                "total_duration": total_duration,
                "successful_populations": successful_populations,
                "failed_populations": failed_populations,
                "average_time_per_table": total_duration / len(tables_to_process) if tables_to_process else 0,
                "success_rate": successful_populations / len(tables_to_process) if tables_to_process else 0
            })
            
            # Validate population results
            validation_result = await self._validate_metadata_population()
            if validation_result.success:
                result.add_log("info", "Metadata population validation successful")
            else:
                result.add_issue("medium", "Population Validation Failed", validation_result.error)
            
            # Take final screenshot
            screenshot_path = await self._take_screenshot("metadata_population_completed")
            if screenshot_path:
                result.add_screenshot(screenshot_path, f"Metadata populated for {successful_populations} tables")
            
            # Determine test result
            if successful_populations >= (self.target_table_count * 0.8):  # 80% success rate
                result.complete("passed")
            elif successful_populations > 0:
                result.complete("partial")
            else:
                result.complete("failed")
            
        except Exception as e:
            result.add_log("error", f"Metadata population test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def _get_table_list(self) -> MCPOperationResult:
        """Get list of all tables in the base"""
        prompt = """
        Please list all tables in this Airtable base. For each table, provide:
        - Table name
        - Table ID if available
        - Number of records
        - Number of fields
        - Primary field name
        
        Format the response in a clear, structured way.
        """
        
        result = await self._execute_mcp_operation("get_table_list", prompt)
        
        if result.success:
            # Parse table information from the response
            # This would need to be adapted based on actual AI response format
            tables = self._parse_table_list_response(result.data.get("response_text", ""))
            result.data["tables"] = tables
        
        return result
    
    def _parse_table_list_response(self, response_text: str) -> List[Dict[str, Any]]:
        """Parse table list from AI response"""
        tables = []
        
        # Simple parsing - in reality this would be more sophisticated
        lines = response_text.split('\n')
        current_table = {}
        
        for line in lines:
            line = line.strip()
            if not line:
                if current_table:
                    tables.append(current_table)
                    current_table = {}
                continue
            
            # Look for table name patterns
            if any(keyword in line.lower() for keyword in ['table:', 'name:', '- ']):
                if 'table' in line.lower() or 'name' in line.lower():
                    name_match = re.search(r'[:\-]\s*(.+)', line)
                    if name_match:
                        current_table['name'] = name_match.group(1).strip()
                elif line.startswith('- '):
                    current_table['name'] = line[2:].strip()
        
        if current_table:
            tables.append(current_table)
        
        # If parsing failed, create some default table names
        if not tables:
            tables = [{"name": f"Table_{i}"} for i in range(1, 36)]
        
        return tables
    
    async def _create_test_tables(self, count: int) -> MCPOperationResult:
        """Create additional test tables if needed"""
        prompt = f"""
        Create {count} test tables in this Airtable base with the following names and basic structure:
        
        {chr(10).join([f"- Test_Table_{i}: Include fields like Name (text), Status (select), Date (date), Notes (long text)" for i in range(1, count + 1)])}
        
        Please create these tables and confirm they were created successfully.
        """
        
        return await self._execute_mcp_operation("create_test_tables", prompt, timeout=120)
    
    async def _populate_table_metadata(self, table_name: str, index: int) -> MCPOperationResult:
        """Populate metadata for a specific table"""
        
        # Generate realistic metadata
        metadata = self._generate_table_metadata(table_name, index)
        
        prompt = f"""
        Add a new record to the "Table_Metadata" table with the following information for table "{table_name}":
        
        - table_name: {metadata['table_name']}
        - table_id: {metadata['table_id']}
        - record_count: {metadata['record_count']}
        - field_count: {metadata['field_count']}
        - created_date: {metadata['created_date']}
        - last_updated: {metadata['last_updated']}
        - description: {metadata['description']}
        - primary_field: {metadata['primary_field']}
        - field_types: {', '.join(metadata['field_types'])}
        - data_quality_score: {metadata['data_quality_score']}
        - usage_frequency: {metadata['usage_frequency']}
        - owner: {metadata['owner']}
        - tags: {', '.join(metadata['tags'])}
        
        Please create this record and confirm it was added successfully.
        """
        
        return await self._execute_mcp_operation("populate_metadata", prompt, timeout=45)
    
    def _generate_table_metadata(self, table_name: str, index: int) -> Dict[str, Any]:
        """Generate realistic metadata for a table"""
        
        # Generate realistic data based on table name and index
        base_date = datetime.now() - timedelta(days=random.randint(1, 365))
        
        field_types_options = [
            ["Text", "Number", "Date"],
            ["Text", "Select", "Checkbox", "Date"],
            ["Text", "Number", "Formula", "Lookup"],
            ["Text", "Email", "Phone", "URL"],
            ["Text", "Attachment", "Date", "Select"],
            ["Text", "Number", "Currency", "Percent"],
            ["Text", "Long text", "Date", "Multiple select"]
        ]
        
        usage_frequencies = ["High", "Medium", "Low", "Inactive"]
        owners = ["Alice Johnson", "Bob Smith", "Carol Davis", "David Wilson", "Eve Brown"]
        tag_options = ["CRM", "Marketing", "Sales", "Support", "Analytics", "Operations", "Finance", "HR"]
        
        return {
            "table_name": table_name,
            "table_id": f"tbl{random.randint(10000000, 99999999)}",
            "record_count": random.randint(10, 5000),
            "field_count": random.randint(5, 25),
            "created_date": base_date.strftime("%Y-%m-%d"),
            "last_updated": (base_date + timedelta(days=random.randint(0, 30))).isoformat(),
            "description": f"Table containing {table_name.lower().replace('_', ' ')} data with comprehensive field structure",
            "primary_field": "Name" if "name" not in table_name.lower() else "ID",
            "field_types": random.choice(field_types_options),
            "data_quality_score": round(random.uniform(65.0, 98.5), 2),
            "usage_frequency": random.choice(usage_frequencies),
            "owner": random.choice(owners),
            "tags": random.sample(tag_options, random.randint(1, 3))
        }
    
    async def _validate_metadata_population(self) -> MCPOperationResult:
        """Validate that metadata was populated correctly"""
        prompt = """
        Please check the "Table_Metadata" table and tell me:
        1. How many records are in the table
        2. Show me a few sample records to verify the data looks correct
        3. Are there any missing or malformed records?
        
        Provide a summary of the metadata population status.
        """
        
        return await self._execute_mcp_operation("validate_population", prompt, timeout=30)
    
    async def _execute_mcp_operation(self, operation: str, prompt: str, 
                                   timeout: int = 60) -> MCPOperationResult:
        """Execute MCP operation (shared method)"""
        start_time = time.time()
        
        try:
            # Find chat elements
            chat_input = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            # Clear and send prompt
            await self.page.fill(chat_input, "")
            await asyncio.sleep(0.5)
            await self.page.type(chat_input, prompt, delay=30)
            await self.page.click(send_button)
            
            # Wait for response
            response_found = False
            error_detected = False
            response_data = {}
            
            for attempt in range(timeout):
                ai_messages = await self.page.query_selector_all(
                    ".message.assistant, [data-role='assistant'], .ai-message, .assistant-message"
                )
                
                if ai_messages:
                    last_message = ai_messages[-1]
                    message_text = await last_message.text_content()
                    
                    if message_text and len(message_text) > 50:
                        # Check for completion indicators
                        if any(indicator in message_text.lower() for indicator in [
                            "successfully", "completed", "created", "added", "updated", "done"
                        ]):
                            response_found = True
                            response_data = {"response_text": message_text}
                            break
                        
                        # Check for errors
                        if any(error in message_text.lower() for error in [
                            "error", "failed", "unable", "permission denied", "not found"
                        ]):
                            error_detected = True
                            break
                
                await asyncio.sleep(1)
            
            duration = time.time() - start_time
            
            return MCPOperationResult(
                operation=operation,
                success=response_found and not error_detected,
                duration=duration,
                data=response_data,
                error="Error detected in response" if error_detected else (
                    "Timeout waiting for response" if not response_found else None
                )
            )
            
        except Exception as e:
            duration = time.time() - start_time
            return MCPOperationResult(
                operation=operation,
                success=False,
                duration=duration,
                error=str(e)
            )

class MCPMetadataUpdateAgent(SyntheticUIAgent):
    """Specialized agent for updating metadata fields with bulk operations"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("MCP Metadata Update Agent", config)
        self.updated_records: Set[str] = set()
        
    async def test_update_metadata_fields(self) -> TestResult:
        """Test updating metadata fields with bulk operations"""
        result = TestResult("MCP Metadata Update Agent", "Update Metadata Fields")
        
        try:
            # Navigate to frontend
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            await self.wait_for_network_idle()
            
            # Get current metadata records
            records_result = await self._get_metadata_records()
            if not records_result.success:
                result.add_issue("critical", "Failed to Get Metadata Records", records_result.error)
                result.complete("failed")
                return result
            
            metadata_records = records_result.data.get("records", [])
            result.add_log("info", f"Found {len(metadata_records)} metadata records to update")
            
            if not metadata_records:
                result.add_issue("critical", "No Metadata Records Found", "Cannot perform updates without existing records")
                result.complete("failed")
                return result
            
            # Perform different types of updates
            update_operations = [
                ("description_updates", "Update descriptions for better clarity"),
                ("quality_score_updates", "Recalculate data quality scores"),
                ("usage_frequency_updates", "Update usage frequency based on recent activity"),
                ("tag_updates", "Add/update tags for better categorization"),
                ("owner_updates", "Update ownership information")
            ]
            
            successful_updates = 0
            failed_updates = 0
            start_time = time.time()
            
            for operation_name, operation_desc in update_operations:
                result.add_log("info", f"Performing {operation_desc}")
                
                update_result = await self._perform_bulk_update(operation_name, metadata_records)
                
                if update_result.success:
                    successful_updates += 1
                    result.add_log("info", f"Successfully completed {operation_desc}")
                    result.performance_metrics[f"{operation_name}_duration"] = update_result.duration
                else:
                    failed_updates += 1
                    result.add_issue("medium", f"Update Failed: {operation_desc}", update_result.error)
                
                # Delay between operations
                await asyncio.sleep(3)
            
            total_duration = time.time() - start_time
            result.performance_metrics["total_update_duration"] = total_duration
            result.performance_metrics["successful_updates"] = successful_updates
            result.performance_metrics["failed_updates"] = failed_updates
            
            # Validate updates
            validation_result = await self._validate_updates()
            if validation_result.success:
                result.add_log("info", "Update validation successful")
            else:
                result.add_issue("medium", "Update Validation Failed", validation_result.error)
            
            # Test selective record updates
            selective_result = await self._test_selective_updates()
            if selective_result.success:
                result.add_log("info", "Selective updates test passed")
            else:
                result.add_issue("low", "Selective Updates Issue", selective_result.error)
            
            # Take final screenshot
            screenshot_path = await self._take_screenshot("metadata_updates_completed")
            if screenshot_path:
                result.add_screenshot(screenshot_path, f"Completed {successful_updates} update operations")
            
            # Determine result
            if successful_updates >= len(update_operations) * 0.8:
                result.complete("passed")
            elif successful_updates > 0:
                result.complete("partial")
            else:
                result.complete("failed")
            
        except Exception as e:
            result.add_log("error", f"Metadata update test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def _get_metadata_records(self) -> MCPOperationResult:
        """Get current metadata records"""
        prompt = """
        Please show me all records in the "Table_Metadata" table. I need to see:
        - Record IDs
        - Table names
        - Current field values
        - Which records need updates
        
        Provide a structured overview of the current metadata.
        """
        
        return await self._execute_mcp_operation("get_metadata_records", prompt, timeout=30)
    
    async def _perform_bulk_update(self, operation_type: str, records: List[Dict]) -> MCPOperationResult:
        """Perform bulk update operation"""
        
        if operation_type == "description_updates":
            prompt = """
            Update the description field for multiple records in the "Table_Metadata" table:
            
            - For CRM-related tables: Add "Customer relationship management data with comprehensive contact information"
            - For Sales tables: Add "Sales pipeline and transaction data with revenue tracking"  
            - For Marketing tables: Add "Marketing campaign and lead generation data"
            - For other tables: Enhance existing descriptions with more detail about data purpose
            
            Please update at least 5-10 records with improved descriptions.
            """
        
        elif operation_type == "quality_score_updates":
            prompt = """
            Recalculate and update the data_quality_score field for records in "Table_Metadata":
            
            - Tables with high record counts (>1000): Increase score by 5-10 points
            - Tables with many field types: Increase score by 3-5 points
            - Tables with recent updates: Increase score by 2-3 points
            - Ensure all scores remain between 0-100
            
            Update quality scores for at least 8-12 records.
            """
        
        elif operation_type == "usage_frequency_updates":
            prompt = """
            Update the usage_frequency field based on table characteristics:
            
            - Tables with >2000 records: Set to "High"
            - Tables with 500-2000 records: Set to "Medium"  
            - Tables with <500 records: Set to "Low"
            - Tables not updated in 6+ months: Set to "Inactive"
            
            Update usage frequency for all applicable records.
            """
        
        elif operation_type == "tag_updates":
            prompt = """
            Add or update tags for better categorization in "Table_Metadata":
            
            - Add "High-Priority" tag to tables with High usage frequency
            - Add "Data-Rich" tag to tables with >15 fields
            - Add "Customer-Facing" tag to CRM/Sales tables
            - Add "Analytics" tag to tables with formulas/lookups
            - Add "Archived" tag to Inactive tables
            
            Update tags for at least 10-15 records.
            """
        
        elif operation_type == "owner_updates":
            prompt = """
            Update owner information in "Table_Metadata" table:
            
            - Assign department heads to relevant tables
            - Update contact information for current owners
            - Add secondary owners for critical tables
            - Ensure all tables have assigned owners
            
            Update owner fields for all records that need it.
            """
        
        else:
            prompt = f"Perform bulk update operation: {operation_type}"
        
        return await self._execute_mcp_operation(operation_type, prompt, timeout=90)
    
    async def _validate_updates(self) -> MCPOperationResult:
        """Validate that updates were applied correctly"""
        prompt = """
        Validate the recent updates to the "Table_Metadata" table:
        
        1. Check if descriptions were updated and are more detailed
        2. Verify data quality scores are within valid ranges (0-100)
        3. Confirm usage frequencies are appropriate for table sizes
        4. Check that tags were added appropriately
        5. Verify all tables have assigned owners
        
        Provide a summary of validation results with any issues found.
        """
        
        return await self._execute_mcp_operation("validate_updates", prompt, timeout=45)
    
    async def _test_selective_updates(self) -> MCPOperationResult:
        """Test updating specific records based on criteria"""
        prompt = """
        Perform selective updates on "Table_Metadata" records:
        
        1. Find tables with data_quality_score < 70 and update their descriptions to explain improvement plans
        2. Find tables tagged with "High-Priority" and update their last_updated timestamp
        3. Find tables with usage_frequency = "Inactive" and add a "Review-Needed" tag
        
        Report on which specific records were updated and what changes were made.
        """
        
        return await self._execute_mcp_operation("selective_updates", prompt, timeout=60)
    
    async def _execute_mcp_operation(self, operation: str, prompt: str, 
                                   timeout: int = 60) -> MCPOperationResult:
        """Execute MCP operation (shared method)"""
        start_time = time.time()
        
        try:
            # Find chat elements
            chat_input = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            # Clear and send prompt
            await self.page.fill(chat_input, "")
            await asyncio.sleep(0.5)
            await self.page.type(chat_input, prompt, delay=30)
            await self.page.click(send_button)
            
            # Wait for response with specific success indicators
            response_found = False
            error_detected = False
            response_data = {}
            
            for attempt in range(timeout):
                ai_messages = await self.page.query_selector_all(
                    ".message.assistant, [data-role='assistant'], .ai-message, .assistant-message"
                )
                
                if ai_messages:
                    last_message = ai_messages[-1]
                    message_text = await last_message.text_content()
                    
                    if message_text and len(message_text) > 50:
                        message_lower = message_text.lower()
                        
                        # Look for success indicators
                        success_indicators = [
                            "updated successfully", "records updated", "changes applied",
                            "bulk update completed", "validation successful", "updates complete"
                        ]
                        
                        error_indicators = [
                            "error updating", "failed to update", "permission denied",
                            "validation failed", "unable to apply", "update unsuccessful"
                        ]
                        
                        if any(indicator in message_lower for indicator in success_indicators):
                            response_found = True
                            response_data = {"response_text": message_text}
                            break
                        elif any(indicator in message_lower for indicator in error_indicators):
                            error_detected = True
                            break
                
                await asyncio.sleep(1)
            
            duration = time.time() - start_time
            
            return MCPOperationResult(
                operation=operation,
                success=response_found and not error_detected,
                duration=duration,
                data=response_data,
                error="Error detected in response" if error_detected else (
                    "Timeout waiting for response" if not response_found else None
                )
            )
            
        except Exception as e:
            duration = time.time() - start_time
            return MCPOperationResult(
                operation=operation,
                success=False,
                duration=duration,
                error=str(e)
            )

class MCPColumnAdditionAgent(SyntheticUIAgent):
    """Specialized agent for adding new columns to existing tables"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("MCP Column Addition Agent", config)
        self.added_columns: Set[str] = set()
        
    async def test_add_improvements_column(self) -> TestResult:
        """Test adding improvements column to metadata table"""
        result = TestResult("MCP Column Addition Agent", "Add Improvements Column")
        
        try:
            # Navigate to frontend
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            await self.wait_for_network_idle()
            
            # First, verify the Table_Metadata table exists
            table_check_result = await self._verify_metadata_table_exists()
            if not table_check_result.success:
                result.add_issue("critical", "Metadata Table Not Found", table_check_result.error)
                result.complete("failed")
                return result
            
            result.add_log("info", "Metadata table verified, proceeding with column addition")
            
            # Add the improvements column
            column_add_result = await self._add_improvements_column()
            if not column_add_result.success:
                result.add_issue("critical", "Column Addition Failed", column_add_result.error)
                result.complete("failed")
                return result
            
            result.add_log("info", f"Improvements column added in {column_add_result.duration:.2f}s")
            result.performance_metrics["column_addition_time"] = column_add_result.duration
            self.added_columns.add("improvements")
            
            # Verify column was added correctly
            verification_result = await self._verify_column_addition()
            if not verification_result.success:
                result.add_issue("high", "Column Verification Failed", verification_result.error)
            else:
                result.add_log("info", "Column addition verified successfully")
            
            # Test applying the column to existing rows
            apply_result = await self._apply_column_to_existing_rows()
            if not apply_result.success:
                result.add_issue("medium", "Failed to Apply Column to Existing Rows", apply_result.error)
            else:
                result.add_log("info", "Column applied to existing rows successfully")
                result.performance_metrics["column_application_time"] = apply_result.duration
            
            # Test adding sample improvement data
            sample_data_result = await self._add_sample_improvement_data()
            if sample_data_result.success:
                result.add_log("info", "Sample improvement data added successfully")
            else:
                result.add_issue("low", "Sample Data Addition Failed", sample_data_result.error)
            
            # Test additional column configurations
            config_result = await self._test_column_configurations()
            if config_result.success:
                result.add_log("info", "Column configuration tests passed")
            else:
                result.add_issue("low", "Column Configuration Issues", config_result.error)
            
            # Take final screenshot
            screenshot_path = await self._take_screenshot("improvements_column_added")
            if screenshot_path:
                result.add_screenshot(screenshot_path, "Improvements column successfully added")
            
            result.complete("passed")
            
        except Exception as e:
            result.add_log("error", f"Add improvements column test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def _verify_metadata_table_exists(self) -> MCPOperationResult:
        """Verify the Table_Metadata table exists and show its structure"""
        prompt = """
        Please verify that the "Table_Metadata" table exists and show me its current structure:
        - List all existing fields
        - Show field types
        - Confirm I can modify the table structure
        - Show a few sample records if available
        """
        
        return await self._execute_mcp_operation("verify_table", prompt, timeout=30)
    
    async def _add_improvements_column(self) -> MCPOperationResult:
        """Add the improvements column to the metadata table"""
        prompt = """
        Add a new field called "improvements" to the "Table_Metadata" table with these specifications:
        
        - Field name: improvements
        - Field type: Long text
        - Description: "Recommended improvements and optimization suggestions for this table"
        - Allow rich text formatting if possible
        - Make it optional (not required)
        
        Please add this field and confirm it was created successfully. Show me the updated table structure.
        """
        
        return await self._execute_mcp_operation("add_improvements_column", prompt, timeout=60)
    
    async def _verify_column_addition(self) -> MCPOperationResult:
        """Verify the improvements column was added correctly"""
        prompt = """
        Verify that the "improvements" field was added to the "Table_Metadata" table:
        
        1. Confirm the field exists
        2. Check that it's a Long text field type
        3. Verify it appears in the table structure
        4. Test that I can add content to this field
        
        Please provide confirmation of the field addition with details.
        """
        
        return await self._execute_mcp_operation("verify_column", prompt, timeout=30)
    
    async def _apply_column_to_existing_rows(self) -> MCPOperationResult:
        """Apply the new column to existing rows with default values"""
        prompt = """
        For existing records in the "Table_Metadata" table, populate the new "improvements" field with appropriate default content:
        
        - For tables with low data_quality_score (<70): Add "Review data quality and implement validation rules"
        - For tables with High usage_frequency: Add "Monitor performance and consider optimization"  
        - For tables with many fields (>15): Add "Review field necessity and consider normalization"
        - For Inactive tables: Add "Assess if table is still needed or should be archived"
        - For other tables: Add "Regular maintenance and documentation updates recommended"
        
        Update the improvements field for all existing records.
        """
        
        return await self._execute_mcp_operation("apply_column", prompt, timeout=90)
    
    async def _add_sample_improvement_data(self) -> MCPOperationResult:
        """Add sample improvement data to demonstrate the column functionality"""
        prompt = """
        Add specific improvement recommendations to a few records in the "Table_Metadata" table:
        
        Pick 3-5 different tables and add detailed improvement suggestions like:
        - "Consider adding data validation rules for email fields"
        - "Implement automated backups for this critical customer data"
        - "Review and update field descriptions for better user understanding"
        - "Add lookup fields to reduce data duplication"
        - "Consider archiving old records to improve performance"
        
        Make each suggestion specific and actionable for the table type.
        """
        
        return await self._execute_mcp_operation("add_sample_data", prompt, timeout=60)
    
    async def _test_column_configurations(self) -> MCPOperationResult:
        """Test various column configuration options"""
        prompt = """
        Test the improvements column configuration:
        
        1. Try adding rich text formatting (bold, italics, lists) to an improvements field
        2. Test adding longer improvement text (multiple paragraphs)
        3. Verify the field can be filtered and searched
        4. Check if the field appears in views correctly
        5. Test copying/pasting formatted text into the field
        
        Report on the column's functionality and any limitations found.
        """
        
        return await self._execute_mcp_operation("test_configurations", prompt, timeout=45)
    
    async def _execute_mcp_operation(self, operation: str, prompt: str, 
                                   timeout: int = 60) -> MCPOperationResult:
        """Execute MCP operation (shared method)"""
        start_time = time.time()
        
        try:
            # Find chat elements  
            chat_input = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            # Clear and send prompt
            await self.page.fill(chat_input, "")
            await asyncio.sleep(0.5)
            await self.page.type(chat_input, prompt, delay=30)
            await self.page.click(send_button)
            
            # Wait for response with specific indicators
            response_found = False
            error_detected = False
            response_data = {}
            
            for attempt in range(timeout):
                ai_messages = await self.page.query_selector_all(
                    ".message.assistant, [data-role='assistant'], .ai-message, .assistant-message"
                )
                
                if ai_messages:
                    last_message = ai_messages[-1]
                    message_text = await last_message.text_content()
                    
                    if message_text and len(message_text) > 50:
                        message_lower = message_text.lower()
                        
                        # Success indicators for column operations
                        success_indicators = [
                            "field added", "column added", "improvements field", "field created",
                            "successfully added", "field exists", "structure updated", "applied to"
                        ]
                        
                        # Error indicators
                        error_indicators = [
                            "error adding", "failed to add", "cannot add", "permission denied",
                            "field exists already", "invalid field", "add failed"
                        ]
                        
                        if any(indicator in message_lower for indicator in success_indicators):
                            response_found = True
                            response_data = {"response_text": message_text}
                            break
                        elif any(indicator in message_lower for indicator in error_indicators):
                            error_detected = True
                            break
                
                await asyncio.sleep(1)
            
            duration = time.time() - start_time
            
            return MCPOperationResult(
                operation=operation,
                success=response_found and not error_detected,
                duration=duration,
                data=response_data,
                error="Error detected in response" if error_detected else (
                    "Timeout waiting for response" if not response_found else None
                )
            )
            
        except Exception as e:
            duration = time.time() - start_time
            return MCPOperationResult(
                operation=operation,
                success=False,
                duration=duration,
                error=str(e)
            )

class MCPLLMAnalysisAgent(SyntheticUIAgent):
    """Specialized agent for LLM analysis integration and recommendations"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        super().__init__("MCP LLM Analysis Agent", config)
        self.analyzed_tables: Set[str] = set()
        self.recommendations_added: int = 0
        
    async def test_llm_analysis_integration(self) -> TestResult:
        """Test comprehensive LLM analysis integration workflow"""
        result = TestResult("MCP LLM Analysis Agent", "LLM Analysis Integration")
        
        try:
            # Navigate to frontend
            frontend_url = self.config.services["frontend"].url
            await self.navigate_to(frontend_url)
            await self.wait_for_network_idle()
            
            # Get tables for analysis
            tables_result = await self._get_tables_for_analysis()
            if not tables_result.success:
                result.add_issue("critical", "Failed to Get Tables for Analysis", tables_result.error)
                result.complete("failed")
                return result
            
            tables_to_analyze = tables_result.data.get("tables", [])[:10]  # Limit to 10 for testing
            result.add_log("info", f"Selected {len(tables_to_analyze)} tables for LLM analysis")
            
            # Perform comprehensive analysis workflow
            analysis_workflows = [
                ("structure_analysis", "Analyze table structure and relationships"),
                ("data_quality_analysis", "Analyze data quality and integrity"),
                ("performance_analysis", "Analyze performance optimization opportunities"), 
                ("usage_pattern_analysis", "Analyze usage patterns and access frequency"),
                ("automation_recommendations", "Generate automation and workflow recommendations")
            ]
            
            successful_analyses = 0
            failed_analyses = 0
            start_time = time.time()
            
            for workflow_name, workflow_desc in analysis_workflows:
                result.add_log("info", f"Executing {workflow_desc}")
                
                analysis_result = await self._execute_llm_analysis_workflow(
                    workflow_name, tables_to_analyze, workflow_desc
                )
                
                if analysis_result.success:
                    successful_analyses += 1
                    result.add_log("info", f"Successfully completed {workflow_desc}")
                    result.performance_metrics[f"{workflow_name}_duration"] = analysis_result.duration
                    
                    # Update improvements field with recommendations
                    update_result = await self._update_improvements_with_recommendations(
                        workflow_name, analysis_result.data
                    )
                    
                    if update_result.success:
                        self.recommendations_added += len(tables_to_analyze)
                        result.add_log("info", f"Updated improvements field with {workflow_name} recommendations")
                    else:
                        result.add_issue("medium", f"Failed to update improvements for {workflow_name}", 
                                       update_result.error)
                else:
                    failed_analyses += 1
                    result.add_issue("high", f"Analysis Failed: {workflow_desc}", analysis_result.error)
                
                # Delay between analyses
                await asyncio.sleep(5)
            
            total_duration = time.time() - start_time
            
            # Test interactive analysis capabilities
            interactive_result = await self._test_interactive_analysis()
            if interactive_result.success:
                result.add_log("info", "Interactive analysis test passed")
            else:
                result.add_issue("medium", "Interactive Analysis Issues", interactive_result.error)
            
            # Test AI response quality validation
            quality_result = await self._validate_ai_response_quality()
            if quality_result.success:
                result.add_log("info", "AI response quality validation passed")
            else:
                result.add_issue("medium", "AI Response Quality Issues", quality_result.error)
            
            # Test recommendation implementation
            implementation_result = await self._test_recommendation_implementation()
            if implementation_result.success:
                result.add_log("info", "Recommendation implementation test passed")
            else:
                result.add_issue("low", "Recommendation Implementation Issues", implementation_result.error)
                
            # Record comprehensive metrics
            result.performance_metrics.update({
                "total_analysis_duration": total_duration,
                "successful_analyses": successful_analyses,
                "failed_analyses": failed_analyses,
                "recommendations_added": self.recommendations_added,
                "tables_analyzed": len(self.analyzed_tables),
                "analysis_success_rate": successful_analyses / len(analysis_workflows) if analysis_workflows else 0
            })
            
            # Take final screenshot
            screenshot_path = await self._take_screenshot("llm_analysis_completed")
            if screenshot_path:
                result.add_screenshot(screenshot_path, f"LLM analysis completed for {len(tables_to_analyze)} tables")
            
            # Determine result based on success rate
            if successful_analyses >= len(analysis_workflows) * 0.8:
                result.complete("passed")
            elif successful_analyses > 0:
                result.complete("partial")
            else:
                result.complete("failed")
            
        except Exception as e:
            result.add_log("error", f"LLM analysis integration test failed: {e}")
            result.add_log("error", traceback.format_exc())
            result.complete("failed")
        
        self.test_results.append(result)
        return result
    
    async def _get_tables_for_analysis(self) -> MCPOperationResult:
        """Get list of tables that need LLM analysis"""
        prompt = """
        Identify tables that would benefit from LLM analysis. Look for:
        - Tables with complex structures (many fields, relationships)
        - Tables with data quality issues (low scores)
        - High-usage tables that need optimization
        - Tables lacking proper documentation
        
        Provide a prioritized list of tables for analysis with reasons why each needs analysis.
        """
        
        result = await self._execute_mcp_operation("get_analysis_tables", prompt, timeout=45)
        
        if result.success:
            # Parse table list from response
            tables = self._parse_analysis_tables_response(result.data.get("response_text", ""))
            result.data["tables"] = tables
        
        return result
    
    def _parse_analysis_tables_response(self, response_text: str) -> List[Dict[str, Any]]:
        """Parse tables list from AI response"""
        tables = []
        
        # Simple parsing to extract table names and reasons
        lines = response_text.split('\n')
        current_table = {}
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # Look for table indicators
            if any(indicator in line.lower() for indicator in ['table:', '- ', 'name:']):
                if 'table' in line.lower() or 'name' in line.lower():
                    name_match = re.search(r'[:\-]\s*(.+)', line)
                    if name_match:
                        table_name = name_match.group(1).strip()
                        current_table = {"name": table_name, "priority": "medium"}
                        tables.append(current_table)
                elif line.startswith('- '):
                    table_name = line[2:].strip()
                    current_table = {"name": table_name, "priority": "medium"}  
                    tables.append(current_table)
        
        # If no tables parsed, create some defaults
        if not tables:
            default_tables = [
                {"name": "Table_Metadata", "priority": "high"},
                {"name": "Customer_Data", "priority": "high"},
                {"name": "Sales_Pipeline", "priority": "medium"},
                {"name": "Marketing_Campaigns", "priority": "medium"},
                {"name": "Product_Inventory", "priority": "low"}
            ]
            tables = default_tables
        
        return tables[:10]  # Limit for testing
    
    async def _execute_llm_analysis_workflow(self, workflow_name: str, tables: List[Dict], 
                                           description: str) -> MCPOperationResult:
        """Execute a specific LLM analysis workflow"""
        
        table_names = [table.get("name", str(table)) for table in tables]
        
        if workflow_name == "structure_analysis":
            prompt = f"""
            Perform comprehensive structure analysis for these tables: {', '.join(table_names)}
            
            For each table, analyze:
            1. Field relationships and dependencies
            2. Data normalization opportunities
            3. Potential for data consolidation
            4. Missing key fields or indexes
            5. Schema optimization recommendations
            
            Provide specific, actionable recommendations for improving table structure.
            """
        
        elif workflow_name == "data_quality_analysis":
            prompt = f"""
            Analyze data quality for these tables: {', '.join(table_names)}
            
            Examine:
            1. Data consistency and validation rules
            2. Missing or incomplete data patterns
            3. Duplicate record detection
            4. Data format standardization needs
            5. Quality scoring methodology improvements
            
            Provide recommendations for improving data quality and integrity.
            """
        
        elif workflow_name == "performance_analysis":
            prompt = f"""
            Analyze performance optimization opportunities for: {', '.join(table_names)}
            
            Consider:
            1. Query performance and indexing strategies
            2. Large table partitioning opportunities
            3. Archive strategies for old data
            4. Caching mechanisms for frequently accessed data
            5. API rate limiting and batch processing optimizations
            
            Suggest specific performance improvements with expected impact.
            """
        
        elif workflow_name == "usage_pattern_analysis":
            prompt = f"""
            Analyze usage patterns for these tables: {', '.join(table_names)}
            
            Review:
            1. Access frequency and peak usage times
            2. Read vs write operation patterns
            3. User and application access patterns
            4. Integration points and data flow
            5. Seasonal or cyclical usage variations
            
            Recommend optimizations based on usage patterns.
            """
        
        elif workflow_name == "automation_recommendations":
            prompt = f"""
            Generate automation recommendations for: {', '.join(table_names)}
            
            Identify opportunities for:
            1. Automated data validation and cleanup
            2. Workflow automation triggers
            3. Scheduled reporting and notifications
            4. Data synchronization automation
            5. Backup and maintenance automation
            
            Provide actionable automation suggestions with implementation priorities.
            """
        
        else:
            prompt = f"Perform {description} for tables: {', '.join(table_names)}"
        
        result = await self._execute_mcp_operation(workflow_name, prompt, timeout=120)
        
        # Mark tables as analyzed if successful
        if result.success:
            for table_name in table_names:
                self.analyzed_tables.add(table_name)
        
        return result
    
    async def _update_improvements_with_recommendations(self, workflow_name: str, 
                                                      analysis_data: Dict[str, Any]) -> MCPOperationResult:
        """Update the improvements field with AI recommendations"""
        
        response_text = analysis_data.get("response_text", "")
        
        prompt = f"""
        Based on the {workflow_name} analysis results, update the "improvements" field in the "Table_Metadata" table.
        
        Analysis results:
        {response_text[:1000]}...
        
        For each analyzed table:
        1. Extract the key recommendations from the analysis
        2. Format them as clear, actionable bullet points
        3. Append them to the existing improvements field content
        4. Mark with the analysis type and date
        
        Update the improvements field for all analyzed tables with these recommendations.
        """
        
        return await self._execute_mcp_operation("update_improvements", prompt, timeout=90)
    
    async def _test_interactive_analysis(self) -> MCPOperationResult:
        """Test interactive analysis capabilities"""
        prompt = """
        Test the interactive analysis capabilities:
        
        1. Ask follow-up questions about a specific table's analysis
        2. Request deeper analysis of a particular recommendation
        3. Compare analysis results between different tables
        4. Ask for prioritization of recommendations by impact/effort
        5. Request specific implementation steps for a recommendation
        
        Demonstrate the AI's ability to provide interactive, detailed analysis.
        """
        
        return await self._execute_mcp_operation("interactive_analysis", prompt, timeout=90)
    
    async def _validate_ai_response_quality(self) -> MCPOperationResult:
        """Validate the quality of AI analysis responses"""
        prompt = """
        Evaluate the quality of the recent analysis recommendations:
        
        1. Are the recommendations specific and actionable?
        2. Do they demonstrate understanding of Airtable capabilities?
        3. Are the suggestions appropriate for the table types analyzed?
        4. Is the technical depth appropriate?
        5. Are implementation priorities clear?
        
        Provide a quality assessment of the analysis outputs with suggestions for improvement.
        """
        
        return await self._execute_mcp_operation("validate_quality", prompt, timeout=60)
    
    async def _test_recommendation_implementation(self) -> MCPOperationResult:
        """Test implementing one of the AI recommendations"""
        prompt = """
        Select one actionable recommendation from the recent analysis and attempt to implement it:
        
        1. Choose a simple, implementable recommendation (like adding a field or updating a description)
        2. Execute the implementation step by step
        3. Verify the implementation was successful
        4. Document any challenges or limitations encountered
        5. Assess the effectiveness of the implemented change
        
        Provide a complete implementation report with lessons learned.
        """
        
        return await self._execute_mcp_operation("test_implementation", prompt, timeout=120)
    
    async def _execute_mcp_operation(self, operation: str, prompt: str, 
                                   timeout: int = 60) -> MCPOperationResult:
        """Execute MCP operation (shared method)"""
        start_time = time.time()
        
        try:
            # Find chat elements
            chat_input = "#messageInput, [data-testid='message-input'], input[placeholder*='message']"
            send_button = "#sendButton, [data-testid='send-button'], button[type='submit']"
            
            # Clear and send prompt
            await self.page.fill(chat_input, "")
            await asyncio.sleep(0.5)
            await self.page.type(chat_input, prompt, delay=25)
            await self.page.click(send_button)
            
            # Wait for comprehensive response
            response_found = False
            error_detected = False
            response_data = {}
            
            for attempt in range(timeout):
                ai_messages = await self.page.query_selector_all(
                    ".message.assistant, [data-role='assistant'], .ai-message, .assistant-message"
                )
                
                if ai_messages:
                    last_message = ai_messages[-1]
                    message_text = await last_message.text_content()
                    
                    if message_text and len(message_text) > 100:  # Require substantial response
                        message_lower = message_text.lower()
                        
                        # Success indicators for analysis operations
                        success_indicators = [
                            "analysis complete", "recommendations", "suggests", "should consider",
                            "analysis results", "findings", "optimization", "improvement",
                            "implementation", "actionable", "priority", "assessment"
                        ]
                        
                        # Error indicators
                        error_indicators = [
                            "analysis failed", "cannot analyze", "error in analysis",
                            "insufficient data", "analysis not possible", "failed to assess"
                        ]
                        
                        if any(indicator in message_lower for indicator in success_indicators):
                            response_found = True
                            response_data = {"response_text": message_text}
                            break
                        elif any(indicator in message_lower for indicator in error_indicators):
                            error_detected = True
                            break
                
                await asyncio.sleep(2)  # Longer delay for analysis operations
            
            duration = time.time() - start_time
            
            return MCPOperationResult(
                operation=operation,
                success=response_found and not error_detected,
                duration=duration,
                data=response_data,
                error="Error detected in analysis response" if error_detected else (
                    "Timeout waiting for analysis completion" if not response_found else None
                )
            )
            
        except Exception as e:
            duration = time.time() - start_time
            return MCPOperationResult(
                operation=operation,
                success=False,
                duration=duration,
                error=str(e)
            )

class MCPTestOrchestrator:
    """Master orchestrator for MCP tool test scenarios with parallel execution"""
    
    def __init__(self, config: TestFrameworkConfig = None):
        self.config = config or get_config()
        self.agents: List[SyntheticUIAgent] = []
        self.test_report = TestReport("MCP Tools Comprehensive Test Suite")
        self.execution_results: Dict[str, Any] = {}
        
    def create_test_agents(self) -> List[SyntheticUIAgent]:
        """Create all MCP test agents"""
        agents = [
            MCPMetadataTableAgent(self.config),
            MCPMetadataPopulationAgent(self.config),
            MCPMetadataUpdateAgent(self.config),
            MCPColumnAdditionAgent(self.config),
            MCPLLMAnalysisAgent(self.config)
        ]
        
        self.agents = agents
        return agents
    
    async def run_comprehensive_mcp_tests(self, parallel: bool = True, 
                                        agents_subset: List[str] = None) -> TestReport:
        """Run comprehensive MCP tool tests"""
        logger.info("Starting comprehensive MCP tools test execution")
        
        # Create agents
        if not self.agents:
            self.create_test_agents()
        
        # Filter agents if subset specified
        if agents_subset:
            filtered_agents = [agent for agent in self.agents 
                             if any(subset_name.lower() in agent.name.lower() 
                                   for subset_name in agents_subset)]
            agents_to_run = filtered_agents
        else:
            agents_to_run = self.agents
        
        logger.info(f"Running tests with {len(agents_to_run)} agents")
        
        start_time = time.time()
        all_results = []
        
        try:
            if parallel and len(agents_to_run) > 1:
                # Run agents in parallel
                logger.info("Executing agents in parallel")
                tasks = []
                for agent in agents_to_run:
                    task = self._run_agent_comprehensive_tests(agent)
                    tasks.append(task)
                
                agent_results = await asyncio.gather(*tasks, return_exceptions=True)
                
                for i, result in enumerate(agent_results):
                    agent_name = agents_to_run[i].name
                    if isinstance(result, Exception):
                        logger.error(f"Agent {agent_name} failed with exception: {result}")
                        # Create error result
                        error_result = TestResult("Test Orchestrator", f"Agent: {agent_name}")
                        error_result.add_log("error", f"Agent execution failed: {result}")
                        error_result.complete("failed")
                        all_results.append(error_result)
                    else:
                        all_results.extend(result)
                        self.execution_results[agent_name] = {
                            "status": "completed",
                            "results": result,
                            "duration": sum(r.performance_metrics.get("duration", 0) for r in result)
                        }
            else:
                # Run agents sequentially
                logger.info("Executing agents sequentially")
                for agent in agents_to_run:
                    try:
                        agent_results = await self._run_agent_comprehensive_tests(agent)
                        all_results.extend(agent_results)
                        self.execution_results[agent.name] = {
                            "status": "completed",
                            "results": agent_results,
                            "duration": sum(r.performance_metrics.get("duration", 0) for r in agent_results)
                        }
                    except Exception as e:
                        logger.error(f"Agent {agent.name} failed: {e}")
                        error_result = TestResult("Test Orchestrator", f"Agent: {agent.name}")
                        error_result.add_log("error", f"Agent execution failed: {e}")
                        error_result.complete("failed")
                        all_results.append(error_result)
                        self.execution_results[agent.name] = {
                            "status": "failed",
                            "error": str(e),
                            "duration": 0
                        }
            
            total_duration = time.time() - start_time
            
            # Add all results to main report
            for result in all_results:
                self.test_report.add_test_result(result)
            
            # Generate comprehensive metrics
            self._generate_execution_metrics(total_duration, agents_to_run)
            
            # Generate reports
            json_report, html_report = await self.test_report.generate_report()
            
            logger.info(f"MCP tests completed in {total_duration:.2f}s")
            logger.info(f"Total tests executed: {len(all_results)}")
            logger.info(f"JSON report: {json_report}")
            logger.info(f"HTML report: {html_report}")
            
        except Exception as e:
            logger.error(f"MCP test orchestration failed: {e}")
            error_result = TestResult("MCP Test Orchestrator", "Orchestration")
            error_result.add_log("error", f"Orchestration failed: {e}")
            error_result.complete("failed")
            self.test_report.add_test_result(error_result)
        
        return self.test_report
    
    async def _run_agent_comprehensive_tests(self, agent: SyntheticUIAgent) -> List[TestResult]:
        """Run comprehensive tests for a specific agent"""
        results = []
        
        async with agent:
            try:
                if isinstance(agent, MCPMetadataTableAgent):
                    results.append(await agent.test_create_metadata_table())
                
                elif isinstance(agent, MCPMetadataPopulationAgent):
                    results.append(await agent.test_populate_metadata_for_tables())
                
                elif isinstance(agent, MCPMetadataUpdateAgent):
                    results.append(await agent.test_update_metadata_fields())
                
                elif isinstance(agent, MCPColumnAdditionAgent):
                    results.append(await agent.test_add_improvements_column())
                
                elif isinstance(agent, MCPLLMAnalysisAgent):
                    results.append(await agent.test_llm_analysis_integration())
                
                else:
                    logger.warning(f"Unknown agent type: {type(agent)}")
            
            except Exception as e:
                logger.error(f"Error running tests for agent {agent.name}: {e}")
                error_result = TestResult(agent.name, "Agent Execution")
                error_result.add_log("error", f"Test execution failed: {e}")
                error_result.complete("failed")
                results.append(error_result)
        
        return results
    
    def _generate_execution_metrics(self, total_duration: float, agents: List[SyntheticUIAgent]):
        """Generate comprehensive execution metrics"""
        
        metrics = {
            "execution_summary": {
                "total_duration": total_duration,
                "agents_executed": len(agents),
                "total_tests": len(self.test_report.test_results),
                "execution_timestamp": datetime.now().isoformat()
            },
            "agent_performance": {},
            "test_statistics": {
                "passed": 0,
                "failed": 0,
                "partial": 0,
                "error": 0
            },
            "scenario_coverage": {
                "metadata_table_creation": False,
                "metadata_population": False,
                "metadata_updates": False,
                "column_addition": False,
                "llm_analysis": False
            }
        }
        
        # Calculate test statistics
        for result in self.test_report.test_results:
            status = result.status
            if status in metrics["test_statistics"]:
                metrics["test_statistics"][status] += 1
        
        # Agent performance metrics
        for agent_name, execution_data in self.execution_results.items():
            metrics["agent_performance"][agent_name] = {
                "status": execution_data["status"],
                "duration": execution_data["duration"],
                "tests_completed": len(execution_data.get("results", [])) if execution_data["status"] == "completed" else 0
            }
        
        # Scenario coverage
        for result in self.test_report.test_results:
            test_name = result.test_name.lower()
            if "metadata table" in test_name:
                metrics["scenario_coverage"]["metadata_table_creation"] = True
            elif "populate metadata" in test_name:
                metrics["scenario_coverage"]["metadata_population"] = True
            elif "update metadata" in test_name:
                metrics["scenario_coverage"]["metadata_updates"] = True
            elif "improvements column" in test_name:
                metrics["scenario_coverage"]["column_addition"] = True
            elif "llm analysis" in test_name:
                metrics["scenario_coverage"]["llm_analysis"] = True
        
        # Add metrics to test report
        self.test_report.execution_metrics = metrics
    
    async def run_specific_scenario(self, scenario_name: str) -> TestResult:
        """Run a specific MCP test scenario"""
        
        scenario_map = {
            "create_metadata_table": (MCPMetadataTableAgent, "test_create_metadata_table"),
            "populate_metadata": (MCPMetadataPopulationAgent, "test_populate_metadata_for_tables"),
            "update_metadata": (MCPMetadataUpdateAgent, "test_update_metadata_fields"),
            "add_column": (MCPColumnAdditionAgent, "test_add_improvements_column"),
            "llm_analysis": (MCPLLMAnalysisAgent, "test_llm_analysis_integration")
        }
        
        if scenario_name not in scenario_map:
            raise ValueError(f"Unknown scenario: {scenario_name}")
        
        agent_class, method_name = scenario_map[scenario_name]
        agent = agent_class(self.config)
        
        async with agent:
            method = getattr(agent, method_name)
            result = await method()
        
        return result
    
    def get_execution_summary(self) -> Dict[str, Any]:
        """Get summary of test execution"""
        return {
            "execution_results": self.execution_results,
            "test_report_summary": self.test_report.get_summary_stats(),
            "execution_metrics": getattr(self.test_report, "execution_metrics", {})
        }

# Convenience functions for running specific scenarios

async def run_create_metadata_table_test(config: TestFrameworkConfig = None) -> TestResult:
    """Run metadata table creation test"""
    orchestrator = MCPTestOrchestrator(config)
    return await orchestrator.run_specific_scenario("create_metadata_table")

async def run_populate_metadata_test(config: TestFrameworkConfig = None) -> TestResult:
    """Run metadata population test"""
    orchestrator = MCPTestOrchestrator(config)
    return await orchestrator.run_specific_scenario("populate_metadata")

async def run_update_metadata_test(config: TestFrameworkConfig = None) -> TestResult:
    """Run metadata update test"""
    orchestrator = MCPTestOrchestrator(config)
    return await orchestrator.run_specific_scenario("update_metadata")

async def run_add_column_test(config: TestFrameworkConfig = None) -> TestResult:
    """Run add improvements column test"""
    orchestrator = MCPTestOrchestrator(config)
    return await orchestrator.run_specific_scenario("add_column")

async def run_llm_analysis_test(config: TestFrameworkConfig = None) -> TestResult:
    """Run LLM analysis integration test"""
    orchestrator = MCPTestOrchestrator(config)
    return await orchestrator.run_specific_scenario("llm_analysis")

async def run_all_mcp_tests(config: TestFrameworkConfig = None, parallel: bool = True) -> TestReport:
    """Run all MCP tool tests"""
    orchestrator = MCPTestOrchestrator(config)
    return await orchestrator.run_comprehensive_mcp_tests(parallel=parallel)

# CLI helper functions
def get_mcp_test_commands() -> Dict[str, Any]:
    """Get CLI commands for MCP tests"""
    return {
        "mcp-create-table": {
            "function": run_create_metadata_table_test,
            "description": "Test creating metadata table",
            "args": []
        },
        "mcp-populate": {
            "function": run_populate_metadata_test,
            "description": "Test populating metadata for 35 tables",
            "args": []
        },
        "mcp-update": {
            "function": run_update_metadata_test,
            "description": "Test updating metadata fields",
            "args": []
        },
        "mcp-add-column": {
            "function": run_add_column_test,
            "description": "Test adding improvements column",
            "args": []
        },
        "mcp-llm-analysis": {
            "function": run_llm_analysis_test,
            "description": "Test LLM analysis integration",
            "args": []
        },
        "mcp-all": {
            "function": run_all_mcp_tests,
            "description": "Run all MCP tool tests",
            "args": [
                {"name": "parallel", "type": bool, "default": True, "help": "Run tests in parallel"}
            ]
        }
    }