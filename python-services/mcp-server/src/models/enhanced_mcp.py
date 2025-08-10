"""Enhanced MCP (Model Context Protocol) models for Sprint 2 implementation"""
from typing import Any, Dict, List, Optional, Union, Literal
from datetime import datetime
from pydantic import BaseModel, Field, validator, root_validator
from enum import Enum
import uuid


class ToolType(str, Enum):
    """MCP tool types - Updated to match Sprint 2 architecture requirements"""
    # Core Airtable operations (10 required tools)
    LIST_BASES = "list_bases"
    LIST_TABLES = "list_tables" 
    GET_SCHEMA = "get_schema"
    LIST_RECORDS = "list_records"
    CREATE_RECORD = "create_record"
    UPDATE_RECORD = "update_record"
    DELETE_RECORD = "delete_record"
    BATCH_CREATE = "batch_create"
    BATCH_UPDATE = "batch_update"
    SEARCH_RECORDS = "search_records"
    
    # Legacy aliases for backward compatibility
    AIRTABLE_LIST_BASES = "airtable_list_bases"
    AIRTABLE_GET_SCHEMA = "airtable_get_schema"
    AIRTABLE_LIST_RECORDS = "airtable_list_records"
    AIRTABLE_GET_RECORD = "airtable_get_record"
    AIRTABLE_CREATE_RECORDS = "airtable_create_records"
    AIRTABLE_UPDATE_RECORDS = "airtable_update_records"
    AIRTABLE_DELETE_RECORDS = "airtable_delete_records"
    
    # Utility tools
    CALCULATE = "calculate"
    SEARCH = "search"
    QUERY_DATABASE = "query_database"


class ExecutionStatus(str, Enum):
    """Tool execution status"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    TIMEOUT = "timeout"
    CANCELLED = "cancelled"


class ErrorCode(str, Enum):
    """Standard error codes for MCP operations"""
    UNKNOWN_TOOL = "UNKNOWN_TOOL"
    INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    MISSING_REQUIRED_PARAM = "MISSING_REQUIRED_PARAM"
    RATE_LIMIT_EXCEEDED = "RATE_LIMIT_EXCEEDED"
    AUTHENTICATION_FAILED = "AUTHENTICATION_FAILED"
    AUTHORIZATION_FAILED = "AUTHORIZATION_FAILED"
    AIRTABLE_API_ERROR = "AIRTABLE_API_ERROR"
    NETWORK_ERROR = "NETWORK_ERROR"
    TIMEOUT_ERROR = "TIMEOUT_ERROR"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    VALIDATION_ERROR = "VALIDATION_ERROR"
    CACHE_ERROR = "CACHE_ERROR"


class ParameterType(str, Enum):
    """Parameter data types"""
    STRING = "string"
    INTEGER = "integer"
    NUMBER = "number"
    BOOLEAN = "boolean"
    ARRAY = "array"
    OBJECT = "object"


class ToolParameter(BaseModel):
    """Enhanced tool parameter definition with validation"""
    name: str = Field(..., min_length=1, description="Parameter name")
    type: ParameterType = Field(..., description="Parameter data type")
    description: str = Field(..., min_length=1, description="Parameter description")
    required: bool = Field(default=True, description="Whether parameter is required")
    default: Optional[Any] = Field(default=None, description="Default value")
    enum: Optional[List[str]] = Field(default=None, description="Allowed values for enum types")
    pattern: Optional[str] = Field(default=None, description="Regex pattern for string validation")
    min_value: Optional[Union[int, float]] = Field(default=None, description="Minimum value for numbers")
    max_value: Optional[Union[int, float]] = Field(default=None, description="Maximum value for numbers")
    min_length: Optional[int] = Field(default=None, description="Minimum length for strings/arrays")
    max_length: Optional[int] = Field(default=None, description="Maximum length for strings/arrays")


class Tool(BaseModel):
    """Enhanced MCP tool definition"""
    name: str = Field(..., min_length=1, description="Tool name")
    type: ToolType = Field(..., description="Tool type")
    description: str = Field(..., min_length=1, description="Tool description")
    parameters: List[ToolParameter] = Field(default_factory=list, description="Tool parameters")
    category: str = Field(default="airtable", description="Tool category")
    tags: List[str] = Field(default_factory=list, description="Tool tags")
    examples: List[Dict[str, Any]] = Field(default_factory=list, description="Usage examples")
    deprecated: bool = Field(default=False, description="Whether tool is deprecated")
    rate_limit: Optional[int] = Field(default=None, description="Rate limit per hour")
    timeout_seconds: Optional[int] = Field(default=30, description="Execution timeout")
    
    @validator('name')
    def validate_name(cls, v):
        if not v.replace('_', '').replace('-', '').isalnum():
            raise ValueError('Tool name must contain only alphanumeric characters, underscores, and hyphens')
        return v


class AuthContext(BaseModel):
    """Authentication context for tool execution"""
    user_id: str = Field(..., description="User ID")
    session_id: str = Field(..., description="Session ID")
    tenant_id: Optional[str] = Field(default=None, description="Tenant ID")
    permissions: List[str] = Field(default_factory=list, description="User permissions")
    token_expiry: Optional[datetime] = Field(default=None, description="Token expiry time")
    rate_limit_remaining: Optional[int] = Field(default=None, description="Remaining rate limit")


class ToolCall(BaseModel):
    """Enhanced tool call request with validation and context"""
    id: str = Field(default_factory=lambda: f"call_{uuid.uuid4().hex[:12]}", description="Unique call ID")
    tool: str = Field(..., min_length=1, description="Tool name to execute")
    arguments: Dict[str, Any] = Field(default_factory=dict, description="Tool arguments")
    auth_context: Optional[AuthContext] = Field(default=None, description="Authentication context")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Additional metadata")
    priority: int = Field(default=0, description="Execution priority (higher = more priority)")
    timeout_seconds: Optional[int] = Field(default=None, description="Custom timeout for this call")
    retry_count: int = Field(default=0, description="Number of retry attempts")
    created_at: datetime = Field(default_factory=datetime.utcnow, description="Creation timestamp")
    
    @validator('priority')
    def validate_priority(cls, v):
        if not -10 <= v <= 10:
            raise ValueError('Priority must be between -10 and 10')
        return v


class ToolError(BaseModel):
    """Enhanced error information"""
    code: ErrorCode = Field(..., description="Error code")
    message: str = Field(..., min_length=1, description="Error message")
    details: Optional[Dict[str, Any]] = Field(default=None, description="Additional error details")
    retryable: bool = Field(default=False, description="Whether the error is retryable")
    retry_after_seconds: Optional[int] = Field(default=None, description="Suggested retry delay")
    trace_id: Optional[str] = Field(default=None, description="Trace ID for debugging")


class ToolResult(BaseModel):
    """Enhanced tool execution result"""
    call_id: str = Field(..., description="Matching call ID")
    tool: str = Field(..., description="Tool name")
    status: ExecutionStatus = Field(..., description="Execution status")
    result: Optional[Any] = Field(default=None, description="Success result")
    error: Optional[ToolError] = Field(default=None, description="Error information")
    duration_ms: Optional[float] = Field(default=None, description="Execution duration in milliseconds")
    cache_hit: bool = Field(default=False, description="Whether result was from cache")
    usage: Optional[Dict[str, Any]] = Field(default=None, description="Resource usage information")
    completed_at: Optional[datetime] = Field(default=None, description="Completion timestamp")
    
    @root_validator
    def validate_result_or_error(cls, values):
        status = values.get('status')
        result = values.get('result')
        error = values.get('error')
        
        if status == ExecutionStatus.COMPLETED and result is None and error is None:
            raise ValueError('Completed execution must have either result or error')
        if status == ExecutionStatus.FAILED and error is None:
            raise ValueError('Failed execution must have error information')
            
        return values


class MCPRequest(BaseModel):
    """Enhanced MCP request"""
    version: str = Field(default="1.0", description="MCP protocol version")
    method: str = Field(..., min_length=1, description="Method name")
    params: Optional[Dict[str, Any]] = Field(default=None, description="Method parameters")
    id: Optional[Union[str, int]] = Field(default=None, description="Request ID")
    timeout_seconds: Optional[int] = Field(default=30, description="Request timeout")
    trace_id: Optional[str] = Field(default_factory=lambda: uuid.uuid4().hex, description="Trace ID")


class MCPResponse(BaseModel):
    """Enhanced MCP response"""
    version: str = Field(default="1.0", description="MCP protocol version")
    result: Optional[Any] = Field(default=None, description="Success result")
    error: Optional[Dict[str, Any]] = Field(default=None, description="Error information")
    id: Optional[Union[str, int]] = Field(default=None, description="Request ID")
    trace_id: Optional[str] = Field(default=None, description="Trace ID")
    duration_ms: Optional[float] = Field(default=None, description="Processing duration")


class MCPError(BaseModel):
    """Enhanced MCP error"""
    code: int = Field(..., description="Error code")
    message: str = Field(..., min_length=1, description="Error message")
    data: Optional[Any] = Field(default=None, description="Additional error data")


class BatchToolCall(BaseModel):
    """Batch tool execution request"""
    id: str = Field(default_factory=lambda: f"batch_{uuid.uuid4().hex[:12]}", description="Batch ID")
    tool_calls: List[ToolCall] = Field(..., min_items=1, max_items=10, description="Tool calls to execute")
    parallel: bool = Field(default=True, description="Execute calls in parallel")
    stop_on_error: bool = Field(default=False, description="Stop batch on first error")
    timeout_seconds: Optional[int] = Field(default=60, description="Total batch timeout")


class BatchToolResult(BaseModel):
    """Batch tool execution result"""
    batch_id: str = Field(..., description="Batch ID")
    results: List[ToolResult] = Field(..., description="Individual tool results")
    total_duration_ms: Optional[float] = Field(default=None, description="Total batch duration")
    success_count: int = Field(..., description="Number of successful executions")
    error_count: int = Field(..., description="Number of failed executions")
    completed_at: datetime = Field(default_factory=datetime.utcnow, description="Batch completion time")


class CacheEntry(BaseModel):
    """Cache entry for tool results"""
    key: str = Field(..., description="Cache key")
    tool: str = Field(..., description="Tool name")
    arguments_hash: str = Field(..., description="Hash of arguments")
    result: Any = Field(..., description="Cached result")
    created_at: datetime = Field(default_factory=datetime.utcnow, description="Cache creation time")
    expires_at: Optional[datetime] = Field(default=None, description="Cache expiration time")
    hit_count: int = Field(default=0, description="Number of cache hits")
    user_id: Optional[str] = Field(default=None, description="User ID for user-specific caching")


class ToolExecutionMetrics(BaseModel):
    """Metrics for tool execution monitoring"""
    tool_name: str = Field(..., description="Tool name")
    total_calls: int = Field(default=0, description="Total number of calls")
    successful_calls: int = Field(default=0, description="Number of successful calls")
    failed_calls: int = Field(default=0, description="Number of failed calls")
    avg_duration_ms: float = Field(default=0.0, description="Average execution duration")
    cache_hit_rate: float = Field(default=0.0, description="Cache hit rate percentage")
    error_rates: Dict[str, int] = Field(default_factory=dict, description="Error counts by type")
    last_executed: Optional[datetime] = Field(default=None, description="Last execution time")


# Tool definitions for the 10 required MCP tools
ENHANCED_AVAILABLE_TOOLS = [
    Tool(
        name="list_bases",
        type=ToolType.LIST_BASES,
        description="List all accessible Airtable bases for the authenticated user",
        parameters=[],
        category="airtable",
        tags=["base", "metadata", "discovery"],
        examples=[
            {"description": "List all bases", "arguments": {}}
        ]
    ),
    Tool(
        name="list_tables",
        type=ToolType.LIST_TABLES,
        description="List all tables in a specific Airtable base",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID (starts with 'app')",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            )
        ],
        category="airtable",
        tags=["table", "metadata", "discovery"],
        examples=[
            {"description": "List tables in a base", "arguments": {"base_id": "appXXXXXXXXXXXXXX"}}
        ]
    ),
    Tool(
        name="get_schema",
        type=ToolType.GET_SCHEMA,
        description="Get schema information for an Airtable base or table",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Specific table ID (optional, if not provided returns full base schema)",
                required=False,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            )
        ],
        category="airtable",
        tags=["schema", "metadata", "fields"],
        examples=[
            {"description": "Get base schema", "arguments": {"base_id": "appXXXXXXXXXXXXXX"}},
            {"description": "Get table schema", "arguments": {"base_id": "appXXXXXXXXXXXXXX", "table_id": "tblXXXXXXXXXXXXXX"}}
        ]
    ),
    Tool(
        name="list_records",
        type=ToolType.LIST_RECORDS,
        description="List records from an Airtable table with optional filtering and pagination",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Airtable table ID",
                required=True,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="view",
                type=ParameterType.STRING,
                description="View name or ID to filter records",
                required=False
            ),
            ToolParameter(
                name="max_records",
                type=ParameterType.INTEGER,
                description="Maximum number of records to return",
                required=False,
                min_value=1,
                max_value=100
            ),
            ToolParameter(
                name="page_size",
                type=ParameterType.INTEGER,
                description="Page size for pagination",
                required=False,
                min_value=1,
                max_value=100
            ),
            ToolParameter(
                name="offset",
                type=ParameterType.STRING,
                description="Pagination offset token",
                required=False
            ),
            ToolParameter(
                name="fields",
                type=ParameterType.ARRAY,
                description="Specific fields to retrieve",
                required=False
            ),
            ToolParameter(
                name="filter_by_formula",
                type=ParameterType.STRING,
                description="Airtable formula for filtering records",
                required=False
            ),
            ToolParameter(
                name="sort",
                type=ParameterType.ARRAY,
                description="Sort configuration array",
                required=False
            )
        ],
        category="airtable",
        tags=["records", "read", "filter", "pagination"],
        examples=[
            {"description": "List all records", "arguments": {"base_id": "appXXX", "table_id": "tblXXX"}},
            {"description": "List with filter", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "filter_by_formula": "{Status} = 'Active'"}}
        ]
    ),
    Tool(
        name="create_record",
        type=ToolType.CREATE_RECORD,
        description="Create a new record in an Airtable table",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Airtable table ID",
                required=True,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="fields",
                type=ParameterType.OBJECT,
                description="Record fields data",
                required=True
            ),
            ToolParameter(
                name="typecast",
                type=ParameterType.BOOLEAN,
                description="Enable automatic type casting",
                required=False,
                default=False
            )
        ],
        category="airtable",
        tags=["records", "create", "write"],
        examples=[
            {"description": "Create a record", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "fields": {"Name": "John Doe", "Status": "Active"}}}
        ]
    ),
    Tool(
        name="update_record",
        type=ToolType.UPDATE_RECORD,
        description="Update an existing record in an Airtable table",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Airtable table ID",
                required=True,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="record_id",
                type=ParameterType.STRING,
                description="Record ID to update",
                required=True,
                pattern="^rec[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="fields",
                type=ParameterType.OBJECT,
                description="Fields to update",
                required=True
            ),
            ToolParameter(
                name="typecast",
                type=ParameterType.BOOLEAN,
                description="Enable automatic type casting",
                required=False,
                default=False
            ),
            ToolParameter(
                name="replace",
                type=ParameterType.BOOLEAN,
                description="Replace entire record (PUT) vs partial update (PATCH)",
                required=False,
                default=False
            )
        ],
        category="airtable",
        tags=["records", "update", "write"],
        examples=[
            {"description": "Update a record", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "record_id": "recXXX", "fields": {"Status": "Completed"}}}
        ]
    ),
    Tool(
        name="delete_record",
        type=ToolType.DELETE_RECORD,
        description="Delete a record from an Airtable table",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Airtable table ID",
                required=True,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="record_id",
                type=ParameterType.STRING,
                description="Record ID to delete",
                required=True,
                pattern="^rec[a-zA-Z0-9]{14}$"
            )
        ],
        category="airtable",
        tags=["records", "delete", "write"],
        examples=[
            {"description": "Delete a record", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "record_id": "recXXX"}}
        ]
    ),
    Tool(
        name="batch_create",
        type=ToolType.BATCH_CREATE,
        description="Create multiple records in an Airtable table in a single operation",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Airtable table ID",
                required=True,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="records",
                type=ParameterType.ARRAY,
                description="Array of record field objects to create",
                required=True,
                min_length=1,
                max_length=10
            ),
            ToolParameter(
                name="typecast",
                type=ParameterType.BOOLEAN,
                description="Enable automatic type casting",
                required=False,
                default=False
            )
        ],
        category="airtable",
        tags=["records", "create", "batch", "write"],
        examples=[
            {"description": "Batch create records", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "records": [{"Name": "John"}, {"Name": "Jane"}]}}
        ]
    ),
    Tool(
        name="batch_update",
        type=ToolType.BATCH_UPDATE,
        description="Update multiple records in an Airtable table in a single operation",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Airtable table ID",
                required=True,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="records",
                type=ParameterType.ARRAY,
                description="Array of records to update (must include id and fields)",
                required=True,
                min_length=1,
                max_length=10
            ),
            ToolParameter(
                name="typecast",
                type=ParameterType.BOOLEAN,
                description="Enable automatic type casting",
                required=False,
                default=False
            ),
            ToolParameter(
                name="replace",
                type=ParameterType.BOOLEAN,
                description="Replace entire records (PUT) vs partial update (PATCH)",
                required=False,
                default=False
            )
        ],
        category="airtable",
        tags=["records", "update", "batch", "write"],
        examples=[
            {"description": "Batch update records", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "records": [{"id": "recXXX", "fields": {"Status": "Done"}}]}}
        ]
    ),
    Tool(
        name="search_records",
        type=ToolType.SEARCH_RECORDS,
        description="Search for records across tables with advanced query capabilities",
        parameters=[
            ToolParameter(
                name="base_id",
                type=ParameterType.STRING,
                description="Airtable base ID",
                required=True,
                pattern="^app[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="query",
                type=ParameterType.STRING,
                description="Search query string",
                required=True,
                min_length=1
            ),
            ToolParameter(
                name="table_id",
                type=ParameterType.STRING,
                description="Specific table ID to search (optional)",
                required=False,
                pattern="^tbl[a-zA-Z0-9]{14}$"
            ),
            ToolParameter(
                name="fields",
                type=ParameterType.ARRAY,
                description="Specific fields to search in",
                required=False
            ),
            ToolParameter(
                name="max_results",
                type=ParameterType.INTEGER,
                description="Maximum number of results to return",
                required=False,
                min_value=1,
                max_value=100,
                default=50
            )
        ],
        category="airtable",
        tags=["search", "query", "find", "records"],
        examples=[
            {"description": "Search across base", "arguments": {"base_id": "appXXX", "query": "project management"}},
            {"description": "Search in specific table", "arguments": {"base_id": "appXXX", "table_id": "tblXXX", "query": "active tasks"}}
        ]
    )
]


# Legacy tool mappings for backward compatibility
LEGACY_TOOL_MAPPING = {
    "airtable_list_bases": "list_bases",
    "airtable_get_schema": "get_schema",
    "airtable_list_records": "list_records",
    "airtable_get_record": "list_records",  # Mapped to list_records with specific record_id
    "airtable_create_records": "batch_create",  # Mapped to batch_create
    "airtable_update_records": "batch_update",  # Mapped to batch_update
    "airtable_delete_records": "delete_record",  # Mapped to delete_record
}