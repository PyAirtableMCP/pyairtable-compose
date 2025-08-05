"""
API Mocking Framework for MCP Tools and External Services
=========================================================

This module provides comprehensive mocking capabilities for MCP tools testing,
including Airtable API responses, LLM service responses, and UI interaction mocking.
It supports both response recording/replay and synthetic response generation.

Key Features:
- Mock Airtable API responses for table operations
- Mock LLM service responses for analysis scenarios
- UI response simulation for faster testing
- Recording and replay of real API interactions
- Synthetic data generation for test scenarios
- Network request interception and manipulation
"""

import asyncio
import json
import logging
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any, Callable, Union
import random
import re
from dataclasses import dataclass, field
from urllib.parse import urlparse, parse_qs

from playwright.async_api import Page, Route, Request, Response
import httpx

logger = logging.getLogger(__name__)

@dataclass 
class MockResponse:
    """Mock response configuration"""
    status: int = 200
    headers: Dict[str, str] = field(default_factory=dict)
    body: Union[Dict, str, bytes] = field(default_factory=dict)
    delay: float = 0.0
    content_type: str = "application/json"
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "status": self.status,
            "headers": self.headers,
            "body": self.body,
            "delay": self.delay,
            "content_type": self.content_type
        }

@dataclass
class MockRule:
    """Mock rule configuration"""
    pattern: str  # URL pattern or regex
    method: str = "GET"
    response: MockResponse = field(default_factory=MockResponse)
    condition: Optional[Callable[[Request], bool]] = None
    count_limit: Optional[int] = None
    use_count: int = 0
    
class AirtableMockResponses:
    """Pre-defined mock responses for Airtable API"""
    
    @staticmethod
    def get_base_schema(base_id: str = "appVLUAubH5cFWhMV") -> MockResponse:
        """Mock response for base schema"""
        return MockResponse(
            status=200,
            body={
                "tables": [
                    {
                        "id": "tblMetadata123456789",
                        "name": "Table_Metadata",
                        "primaryFieldId": "fldTableName",
                        "fields": [
                            {"id": "fldTableName", "name": "table_name", "type": "singleLineText"},
                            {"id": "fldTableId", "name": "table_id", "type": "singleLineText"},
                            {"id": "fldRecordCount", "name": "record_count", "type": "number"},
                            {"id": "fldFieldCount", "name": "field_count", "type": "number"},
                            {"id": "fldCreatedDate", "name": "created_date", "type": "date"},
                            {"id": "fldLastUpdated", "name": "last_updated", "type": "dateTime"},
                            {"id": "fldDescription", "name": "description", "type": "multilineText"},
                            {"id": "fldPrimaryField", "name": "primary_field", "type": "singleLineText"},
                            {"id": "fldFieldTypes", "name": "field_types", "type": "multipleSelects"},
                            {"id": "fldQualityScore", "name": "data_quality_score", "type": "number"},
                            {"id": "fldUsageFreq", "name": "usage_frequency", "type": "singleSelect"},
                            {"id": "fldOwner", "name": "owner", "type": "singleLineText"},
                            {"id": "fldTags", "name": "tags", "type": "multipleSelects"},
                            {"id": "fldImprovements", "name": "improvements", "type": "multilineText"}
                        ]
                    },
                    *[{
                        "id": f"tblTest{i:09d}",
                        "name": f"Test_Table_{i}",
                        "primaryFieldId": f"fldName{i}",
                        "fields": [
                            {"id": f"fldName{i}", "name": "Name", "type": "singleLineText"},
                            {"id": f"fldStatus{i}", "name": "Status", "type": "singleSelect"},
                            {"id": f"fldDate{i}", "name": "Date", "type": "date"},
                            {"id": f"fldNotes{i}", "name": "Notes", "type": "multilineText"}
                        ]
                    } for i in range(1, 36)]
                ]
            }
        )
    
    @staticmethod
    def create_table_success(table_name: str) -> MockResponse:
        """Mock successful table creation response"""
        return MockResponse(
            status=200,
            body={
                "id": f"tbl{random.randint(100000000, 999999999)}",
                "name": table_name,
                "primaryFieldId": "fldPrimary",
                "fields": [
                    {"id": "fldPrimary", "name": "table_name", "type": "singleLineText"},
                    {"id": "fldTableId", "name": "table_id", "type": "singleLineText"},
                    {"id": "fldRecordCount", "name": "record_count", "type": "number"},
                    {"id": "fldFieldCount", "name": "field_count", "type": "number"},
                    {"id": "fldCreatedDate", "name": "created_date", "type": "date"},
                    {"id": "fldLastUpdated", "name": "last_updated", "type": "dateTime"},
                    {"id": "fldDescription", "name": "description", "type": "multilineText"},
                    {"id": "fldPrimaryField", "name": "primary_field", "type": "singleLineText"},
                    {"id": "fldFieldTypes", "name": "field_types", "type": "multipleSelects"},
                    {"id": "fldQualityScore", "name": "data_quality_score", "type": "number"},
                    {"id": "fldUsageFreq", "name": "usage_frequency", "type": "singleSelect"},
                    {"id": "fldOwner", "name": "owner", "type": "singleLineText"},
                    {"id": "fldTags", "name": "tags", "type": "multipleSelects"}
                ],
                "views": [
                    {"id": "viwGrid", "name": "Grid view", "type": "grid"}
                ]
            }
        )
    
    @staticmethod
    def add_field_success(field_name: str, field_type: str = "multilineText") -> MockResponse:
        """Mock successful field addition response"""
        return MockResponse(
            status=200,
            body={
                "id": f"fld{random.randint(100000000, 999999999)}",
                "name": field_name,
                "type": field_type,
                "options": {} if field_type == "multilineText" else None
            }
        )
    
    @staticmethod
    def create_records_success(record_count: int = 1) -> MockResponse:
        """Mock successful record creation response"""
        records = []
        for i in range(record_count):
            records.append({
                "id": f"rec{random.randint(100000000, 999999999)}",
                "createdTime": datetime.now().isoformat(),
                "fields": {
                    "table_name": f"Sample_Table_{i+1}",
                    "table_id": f"tbl{random.randint(100000000, 999999999)}",
                    "record_count": random.randint(10, 5000),
                    "field_count": random.randint(5, 25),
                    "created_date": (datetime.now() - timedelta(days=random.randint(1, 365))).strftime("%Y-%m-%d"),
                    "last_updated": datetime.now().isoformat(),
                    "description": f"Sample table {i+1} for testing purposes",
                    "primary_field": "Name",
                    "data_quality_score": round(random.uniform(65.0, 98.5), 2),
                    "usage_frequency": random.choice(["High", "Medium", "Low", "Inactive"]),
                    "owner": random.choice(["Alice Johnson", "Bob Smith", "Carol Davis"]),
                    "tags": random.sample(["CRM", "Marketing", "Sales", "Analytics"], 2)
                }
            })
        
        return MockResponse(
            status=200,
            body={"records": records}
        )
    
    @staticmethod
    def update_records_success(record_ids: List[str]) -> MockResponse:
        """Mock successful record update response"""
        records = []
        for record_id in record_ids:
            records.append({
                "id": record_id,
                "fields": {
                    "last_updated": datetime.now().isoformat(),
                    "data_quality_score": round(random.uniform(75.0, 95.0), 2)
                }
            })
        
        return MockResponse(
            status=200,
            body={"records": records}
        )
    
    @staticmethod
    def list_records(table_name: str = "Table_Metadata", record_count: int = 35) -> MockResponse:
        """Mock response for listing records"""
        records = []
        for i in range(record_count):
            records.append({
                "id": f"rec{random.randint(100000000, 999999999)}",
                "createdTime": (datetime.now() - timedelta(days=random.randint(1, 100))).isoformat(),
                "fields": {
                    "table_name": f"Table_{i+1}",
                    "table_id": f"tbl{random.randint(100000000, 999999999)}",
                    "record_count": random.randint(10, 5000),
                    "field_count": random.randint(5, 25),
                    "created_date": (datetime.now() - timedelta(days=random.randint(1, 365))).strftime("%Y-%m-%d"),
                    "last_updated": datetime.now().isoformat(),
                    "description": f"Table {i+1} containing business data",
                    "primary_field": random.choice(["Name", "ID", "Title"]),
                    "field_types": random.sample(["Text", "Number", "Date", "Select", "Checkbox"], 3),
                    "data_quality_score": round(random.uniform(65.0, 98.5), 2),
                    "usage_frequency": random.choice(["High", "Medium", "Low", "Inactive"]),
                    "owner": random.choice(["Alice Johnson", "Bob Smith", "Carol Davis", "David Wilson"]),
                    "tags": random.sample(["CRM", "Marketing", "Sales", "Support", "Analytics"], 2),
                    "improvements": f"Sample improvements for Table_{i+1}" if i % 3 == 0 else ""
                }
            })
        
        return MockResponse(
            status=200,
            body={
                "records": records,
                "offset": None
            }
        )

class LLMMockResponses:
    """Pre-defined mock responses for LLM services"""
    
    @staticmethod
    def table_creation_response(table_name: str = "Table_Metadata") -> MockResponse:
        """Mock LLM response for table creation"""
        return MockResponse(
            status=200,
            body={
                "response": f"""I've successfully created the "{table_name}" table with the following structure:

✅ **Table Created: {table_name}**

**Fields Added:**
- `table_name` (Single line text) - Primary field
- `table_id` (Single line text)
- `record_count` (Number)
- `field_count` (Number) 
- `created_date` (Date)
- `last_updated` (Date and time)
- `description` (Long text)
- `primary_field` (Single line text)
- `field_types` (Multiple select)
- `data_quality_score` (Number, 0-100 scale)
- `usage_frequency` (Single select: High, Medium, Low, Inactive)
- `owner` (Single line text)
- `tags` (Multiple select)

The table is now ready for use. You can start adding metadata records for your existing tables.""",
                "metadata": {
                    "table_created": True,
                    "table_name": table_name,
                    "field_count": 13,
                    "creation_time": datetime.now().isoformat()
                }
            },
            delay=2.0
        )
    
    @staticmethod
    def table_analysis_response(table_names: List[str]) -> MockResponse:
        """Mock LLM response for table analysis"""
        analysis_text = f"""📊 **Comprehensive Table Analysis Complete**

I've analyzed {len(table_names)} tables and here are my findings:

**Structure Analysis:**
- **{table_names[0] if table_names else 'Sample_Table'}**: Well-normalized structure with appropriate field types. Consider adding validation rules for email fields.
- **Data Relationships**: Strong referential integrity across core tables. Recommend implementing lookup fields to reduce duplication.

**Data Quality Assessment:**
- **Overall Score**: 87.3/100
- **Key Issues**: 
  - Missing validation on 15% of text fields
  - Date format inconsistencies in historical data
  - Duplicate detection needed for customer records

**Performance Optimization:**
- **High-Usage Tables**: Consider implementing caching for frequently accessed records
- **Large Tables**: Recommend archiving strategy for records older than 2 years
- **Index Optimization**: Add indexes on frequently queried fields

**Automation Recommendations:**
1. **Data Validation**: Implement automated quality checks on new records
2. **Backup Automation**: Schedule daily incremental backups
3. **Notification Workflows**: Set up alerts for data quality threshold breaches
4. **Reporting**: Automate weekly data health reports

**Priority Actions:**
🔴 **High**: Implement data validation rules
🟡 **Medium**: Set up automated archiving
🟢 **Low**: Enhance field descriptions

Would you like me to elaborate on any of these recommendations or help implement specific improvements?"""
        
        return MockResponse(
            status=200,
            body={
                "response": analysis_text,
                "metadata": {
                    "analysis_type": "comprehensive",
                    "tables_analyzed": len(table_names),
                    "recommendations_count": 12,
                    "analysis_time": datetime.now().isoformat()
                }
            },
            delay=5.0
        )
    
    @staticmethod
    def field_addition_response(field_name: str = "improvements") -> MockResponse:
        """Mock LLM response for field addition"""
        return MockResponse(
            status=200,
            body={
                "response": f"""✅ **Field Added Successfully**

I've added the "{field_name}" field to the Table_Metadata table with these specifications:

**Field Details:**
- **Name**: {field_name}
- **Type**: Long text
- **Description**: Recommended improvements and optimization suggestions
- **Features**: Rich text formatting enabled, Optional field

**Next Steps:**
The field has been added to the table structure and is now available for all records. I can help you:
1. Populate existing records with improvement suggestions
2. Set up automated workflows to update this field
3. Create views filtered by improvement priority

The improvements field is ready for use! Would you like me to add sample improvement data to existing records?""",
                "metadata": {
                    "field_added": True,
                    "field_name": field_name,
                    "field_type": "multilineText"
                }
            },
            delay=1.5
        )
    
    @staticmethod
    def bulk_update_response(operation_type: str, affected_count: int = 10) -> MockResponse:
        """Mock LLM response for bulk updates"""
        return MockResponse(
            status=200,
            body={
                "response": f"""🔄 **Bulk Update Completed - {operation_type.title()}**

Successfully updated {affected_count} records in the Table_Metadata table.

**Changes Applied:**
- Updated {affected_count} records with enhanced {operation_type.replace('_', ' ')}
- All updates validated and applied successfully
- Data integrity maintained throughout the process

**Summary of Changes:**
- **Descriptions**: Enhanced with more detailed explanations
- **Quality Scores**: Recalculated based on latest data analysis
- **Usage Frequencies**: Updated based on recent activity patterns
- **Tags**: Added relevant categorization tags
- **Owner Information**: Updated with current assignments

**Validation Results:**
✅ All records updated successfully
✅ No data integrity issues detected
✅ Field constraints maintained
✅ Relationships preserved

The bulk update operation completed successfully. All records now have improved metadata quality.""",
                "metadata": {
                    "operation": operation_type,
                    "records_updated": affected_count,
                    "update_time": datetime.now().isoformat(),
                    "success": True
                }
            },
            delay=3.0
        )
    
    @staticmethod
    def metadata_population_response(table_count: int = 35) -> MockResponse:
        """Mock LLM response for metadata population"""
        return MockResponse(
            status=200,
            body={
                "response": f"""📝 **Metadata Population Complete**

Successfully populated metadata for {table_count} tables in your Airtable base.

**Population Summary:**
- **Tables Processed**: {table_count}
- **Records Created**: {table_count}
- **Fields Populated**: 13 per record
- **Data Quality**: All records meet validation standards

**Metadata Includes:**
- Table identification and structure information
- Record and field counts
- Creation and update timestamps
- Comprehensive descriptions
- Data quality assessments (65-98 score range)
- Usage frequency classifications
- Owner assignments
- Relevant tags and categorization

**Quality Metrics:**
- **Average Quality Score**: 84.7/100
- **High Usage Tables**: {table_count // 3}
- **Recently Updated**: {table_count // 2}
- **Fully Documented**: {table_count}

**Next Steps Available:**
1. Run analysis on populated metadata
2. Generate reports from metadata
3. Set up monitoring workflows
4. Add improvement recommendations

Your Table_Metadata is now fully populated and ready for analysis and reporting!""",
                "metadata": {
                    "tables_processed": table_count,
                    "records_created": table_count,
                    "population_time": datetime.now().isoformat(),
                    "success": True
                }
            },
            delay=8.0
        )

class MCPMockingFramework:
    """Main framework for mocking MCP tool interactions"""
    
    def __init__(self, page: Page):
        self.page = page
        self.mock_rules: List[MockRule] = []
        self.intercepted_requests: List[Dict[str, Any]] = []
        self.response_recordings: Dict[str, Any] = {}
        self.enabled = False
        
    async def enable_mocking(self):
        """Enable request interception and mocking"""
        if self.enabled:
            return
            
        await self.page.route("**/*", self._handle_route)
        self.enabled = True
        logger.info("MCP mocking framework enabled")
    
    async def disable_mocking(self):
        """Disable request interception and mocking"""
        if not self.enabled:
            return
            
        await self.page.unroute("**/*")
        self.enabled = False
        logger.info("MCP mocking framework disabled")
    
    def add_mock_rule(self, rule: MockRule):
        """Add a mock rule"""
        self.mock_rules.append(rule)
        logger.info(f"Added mock rule for {rule.pattern} ({rule.method})")
    
    def setup_airtable_mocks(self, base_id: str = "appVLUAubH5cFWhMV"):
        """Set up standard Airtable API mocks"""
        
        # Base schema endpoint
        self.add_mock_rule(MockRule(
            pattern=f"https://api.airtable.com/v0/meta/bases/{base_id}/tables",
            method="GET",
            response=AirtableMockResponses.get_base_schema(base_id)
        ))
        
        # Table creation endpoint
        self.add_mock_rule(MockRule(
            pattern=f"https://api.airtable.com/v0/meta/bases/{base_id}/tables",
            method="POST",
            response=AirtableMockResponses.create_table_success("Table_Metadata")
        ))
        
        # Field addition endpoint
        self.add_mock_rule(MockRule(
            pattern=f"https://api.airtable.com/v0/meta/bases/{base_id}/tables/*/fields",
            method="POST",
            response=AirtableMockResponses.add_field_success("improvements")
        ))
        
        # Record operations
        self.add_mock_rule(MockRule(
            pattern=f"https://api.airtable.com/v0/{base_id}/Table_Metadata",
            method="GET",
            response=AirtableMockResponses.list_records()
        ))
        
        self.add_mock_rule(MockRule(
            pattern=f"https://api.airtable.com/v0/{base_id}/Table_Metadata",
            method="POST",
            response=AirtableMockResponses.create_records_success(1)
        ))
        
        self.add_mock_rule(MockRule(
            pattern=f"https://api.airtable.com/v0/{base_id}/Table_Metadata",
            method="PATCH",
            response=AirtableMockResponses.update_records_success(["rec1", "rec2", "rec3"])
        ))
        
        logger.info(f"Set up Airtable mocks for base {base_id}")
    
    def setup_llm_mocks(self):
        """Set up LLM service mocks"""
        
        # Gemini API endpoint
        self.add_mock_rule(MockRule(
            pattern="https://generativelanguage.googleapis.com/v1beta/models/*",
            method="POST",
            response=self._dynamic_llm_response
        ))
        
        # OpenAI API endpoint (if used)
        self.add_mock_rule(MockRule(
            pattern="https://api.openai.com/v1/chat/completions",
            method="POST", 
            response=self._dynamic_llm_response
        ))
        
        # Local LLM orchestrator endpoint
        self.add_mock_rule(MockRule(
            pattern="**/llm-orchestrator/**",
            method="POST",
            response=self._dynamic_llm_response
        ))
        
        logger.info("Set up LLM service mocks")
    
    def setup_frontend_mocks(self):
        """Set up frontend UI interaction mocks"""
        
        # Mock chat responses for faster testing
        self.add_mock_rule(MockRule(
            pattern="**/api/chat",
            method="POST",
            response=self._dynamic_chat_response
        ))
        
        # Mock health check endpoints
        self.add_mock_rule(MockRule(
            pattern="**/health",
            method="GET",
            response=MockResponse(status=200, body={"status": "healthy"})
        ))
        
        logger.info("Set up frontend interaction mocks")
    
    async def _handle_route(self, route: Route):
        """Handle intercepted routes"""
        request = route.request
        url = request.url
        method = request.method
        
        # Record the request
        self.intercepted_requests.append({
            "url": url,
            "method": method,
            "headers": dict(request.headers),
            "body": request.post_data,
            "timestamp": datetime.now().isoformat()
        })
        
        # Check for matching mock rules
        matching_rule = self._find_matching_rule(request)
        
        if matching_rule:
            # Apply mock response
            await self._apply_mock_response(route, matching_rule)
        else:
            # Continue with real request
            await route.continue_()
    
    def _find_matching_rule(self, request: Request) -> Optional[MockRule]:
        """Find matching mock rule for request"""
        url = request.url
        method = request.method
        
        for rule in self.mock_rules:
            # Check method match
            if rule.method != "*" and rule.method != method:
                continue
            
            # Check URL pattern match  
            if self._url_matches_pattern(url, rule.pattern):
                # Check custom condition
                if rule.condition and not rule.condition(request):
                    continue
                    
                # Check count limit
                if rule.count_limit and rule.use_count >= rule.count_limit:
                    continue
                
                rule.use_count += 1
                return rule
        
        return None
    
    def _url_matches_pattern(self, url: str, pattern: str) -> bool:
        """Check if URL matches pattern"""
        # Simple wildcard matching
        if "*" in pattern:
            pattern_regex = pattern.replace("*", ".*").replace("?", ".")
            return bool(re.match(pattern_regex, url))
        else:
            return url == pattern
    
    async def _apply_mock_response(self, route: Route, rule: MockRule):
        """Apply mock response to route"""
        response = rule.response
        
        # Handle dynamic responses
        if callable(response):
            response = response(route.request)
        
        # Add delay if specified
        if response.delay > 0:
            await asyncio.sleep(response.delay)
        
        # Prepare response body
        body = response.body
        if isinstance(body, dict):
            body = json.dumps(body)
        elif isinstance(body, str):
            body = body.encode()
        
        # Set up headers
        headers = dict(response.headers)
        if "content-type" not in headers:
            headers["content-type"] = response.content_type
        
        # Fulfill the route with mock response
        await route.fulfill(
            status=response.status,
            headers=headers,
            body=body
        )
        
        logger.debug(f"Applied mock response for {route.request.url}")
    
    def _dynamic_llm_response(self, request: Request) -> MockResponse:
        """Generate dynamic LLM response based on request content"""
        try:
            # Parse request to determine response type
            post_data = request.post_data
            if post_data:
                # Try to parse JSON
                try:
                    data = json.loads(post_data)
                    content = data.get("prompt", "") or data.get("messages", [{}])[-1].get("content", "")
                except:
                    content = post_data
            else:
                content = ""
            
            content_lower = content.lower()
            
            # Determine response type based on content
            if "create" in content_lower and "table" in content_lower and "metadata" in content_lower:
                return LLMMockResponses.table_creation_response()
            elif "populate" in content_lower and "metadata" in content_lower:
                return LLMMockResponses.metadata_population_response()
            elif "add" in content_lower and ("field" in content_lower or "column" in content_lower):
                return LLMMockResponses.field_addition_response()
            elif "update" in content_lower and "bulk" in content_lower:
                return LLMMockResponses.bulk_update_response("bulk_update")
            elif "analyz" in content_lower or "recommend" in content_lower:
                return LLMMockResponses.table_analysis_response(["Table_1", "Table_2", "Table_3"])
            else:
                # Generic response
                return MockResponse(
                    status=200,
                    body={
                        "response": "I understand your request and I'm processing it. Let me work on that for you.",
                        "metadata": {"request_type": "generic"}
                    },
                    delay=1.0
                )
                
        except Exception as e:
            logger.error(f"Error generating dynamic LLM response: {e}")
            return MockResponse(
                status=200,
                body={
                    "response": "I'm working on your request. Please wait a moment while I process this.",
                    "metadata": {"error": str(e)}
                },
                delay=0.5
            )
    
    def _dynamic_chat_response(self, request: Request) -> MockResponse:
        """Generate dynamic chat response for frontend"""
        return MockResponse(
            status=200,
            body={
                "message": "Mock response generated for testing",
                "timestamp": datetime.now().isoformat(),
                "success": True
            },
            delay=0.5
        )
    
    def get_intercepted_requests(self) -> List[Dict[str, Any]]:
        """Get list of intercepted requests"""
        return self.intercepted_requests.copy()
    
    def clear_intercepted_requests(self):
        """Clear intercepted requests log"""
        self.intercepted_requests.clear()
    
    def get_mock_rules_usage(self) -> Dict[str, Any]:
        """Get usage statistics for mock rules"""
        return {
            "total_rules": len(self.mock_rules),
            "rules": [
                {
                    "pattern": rule.pattern,
                    "method": rule.method,
                    "use_count": rule.use_count,
                    "count_limit": rule.count_limit
                }
                for rule in self.mock_rules
            ]
        }
    
    async def record_interactions(self, output_file: str):
        """Record real interactions for later replay"""
        # This would implement recording of real responses
        # for later use in mocks
        pass
    
    async def load_recorded_interactions(self, input_file: str):
        """Load recorded interactions for replay"""
        # This would load previously recorded responses
        pass

class MCPMockContextManager:
    """Context manager for MCP mocking"""
    
    def __init__(self, page: Page, enable_airtable: bool = True, 
                 enable_llm: bool = True, enable_frontend: bool = False):
        self.page = page
        self.framework = MCPMockingFramework(page)
        self.enable_airtable = enable_airtable
        self.enable_llm = enable_llm
        self.enable_frontend = enable_frontend
    
    async def __aenter__(self):
        """Enter context manager"""
        await self.framework.enable_mocking()
        
        if self.enable_airtable:
            self.framework.setup_airtable_mocks()
        
        if self.enable_llm:
            self.framework.setup_llm_mocks()
        
        if self.enable_frontend:
            self.framework.setup_frontend_mocks()
        
        return self.framework
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Exit context manager"""
        await self.framework.disable_mocking()

# Convenience functions

async def create_mcp_mocks(page: Page, **kwargs) -> MCPMockingFramework:
    """Create and configure MCP mocking framework"""
    ctx = MCPMockContextManager(page, **kwargs)
    return await ctx.__aenter__()

def create_custom_mock_rule(pattern: str, method: str = "GET", 
                           response_body: Any = None, status: int = 200,
                           delay: float = 0.0) -> MockRule:
    """Create a custom mock rule"""
    response = MockResponse(
        status=status,
        body=response_body or {"success": True},
        delay=delay
    )
    
    return MockRule(
        pattern=pattern,
        method=method,
        response=response
    )

# Test utilities for validating mocks

class MockValidator:
    """Utilities for validating mock responses"""
    
    @staticmethod
    def validate_airtable_response(response_body: Dict[str, Any], 
                                 expected_fields: List[str] = None) -> bool:
        """Validate Airtable API response structure"""
        if "records" in response_body:
            # Record list response
            records = response_body["records"]
            if not isinstance(records, list):
                return False
            
            if records and expected_fields:
                first_record = records[0]
                if "fields" in first_record:
                    fields = first_record["fields"]
                    return all(field in fields for field in expected_fields)
        
        elif "id" in response_body and "name" in response_body:
            # Single table/field response
            return True
        
        return False
    
    @staticmethod
    def validate_llm_response(response_body: Dict[str, Any]) -> bool:
        """Validate LLM service response structure"""
        return (
            "response" in response_body and
            isinstance(response_body["response"], str) and
            len(response_body["response"]) > 10
        )
    
    @staticmethod
    def extract_mock_metrics(framework: MCPMockingFramework) -> Dict[str, Any]:
        """Extract metrics from mock framework"""
        requests = framework.get_intercepted_requests()
        rules_usage = framework.get_mock_rules_usage()
        
        request_methods = {}
        request_domains = {}
        
        for req in requests:
            method = req["method"]
            request_methods[method] = request_methods.get(method, 0) + 1
            
            domain = urlparse(req["url"]).netloc
            request_domains[domain] = request_domains.get(domain, 0) + 1
        
        return {
            "total_requests": len(requests),
            "methods": request_methods,
            "domains": request_domains,
            "rules_usage": rules_usage,
            "mock_effectiveness": sum(rule["use_count"] for rule in rules_usage["rules"]) / len(requests) if requests else 0
        }