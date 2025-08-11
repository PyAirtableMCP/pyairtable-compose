"""MCP (Model Context Protocol) models and tools"""
from typing import Any, Dict, List, Optional, Union
from datetime import datetime
from pydantic import BaseModel, Field
from enum import Enum


class ToolType(str, Enum):
    """MCP tool types"""
    AIRTABLE_LIST_BASES = "airtable_list_bases"
    AIRTABLE_GET_SCHEMA = "airtable_get_schema"
    AIRTABLE_LIST_RECORDS = "airtable_list_records"
    AIRTABLE_GET_RECORD = "airtable_get_record"
    AIRTABLE_CREATE_RECORDS = "airtable_create_records"
    AIRTABLE_UPDATE_RECORDS = "airtable_update_records"
    AIRTABLE_DELETE_RECORDS = "airtable_delete_records"
    CALCULATE = "calculate"
    SEARCH = "search"
    QUERY_DATABASE = "query_database"
    # AI-specific tools
    GENERATE_EMBEDDINGS = "generate_embeddings"
    SEMANTIC_SEARCH = "semantic_search"
    CLASSIFY_TEXT = "classify_text"
    SUMMARIZE_TEXT = "summarize_text"
    EXTRACT_ENTITIES = "extract_entities"


class ToolParameter(BaseModel):
    """Tool parameter definition"""
    name: str
    type: str
    description: str
    required: bool = True
    default: Any = None
    enum: Optional[List[str]] = None
    minimum: Optional[float] = None
    maximum: Optional[float] = None


class Tool(BaseModel):
    """MCP tool definition"""
    name: str
    type: ToolType
    description: str
    parameters: List[ToolParameter]
    version: str = "1.0"
    category: str = "general"
    examples: Optional[List[Dict[str, Any]]] = None


class ToolCall(BaseModel):
    """Tool call request"""
    id: str = Field(default_factory=lambda: f"call_{int(datetime.utcnow().timestamp())}")
    tool: str
    arguments: Dict[str, Any]
    user_id: Optional[str] = None
    session_id: Optional[str] = None


class ToolResult(BaseModel):
    """Tool execution result"""
    call_id: str
    tool: str
    result: Any
    error: Optional[str] = None
    duration_ms: Optional[float] = None
    cached: bool = False
    metadata: Optional[Dict[str, Any]] = None


class MCPRequest(BaseModel):
    """MCP request"""
    version: str = "1.0"
    method: str
    params: Optional[Dict[str, Any]] = None
    id: Optional[Union[str, int]] = None


class MCPResponse(BaseModel):
    """MCP response"""
    version: str = "1.0"
    result: Optional[Any] = None
    error: Optional[Dict[str, Any]] = None
    id: Optional[Union[str, int]] = None


class MCPError(BaseModel):
    """MCP error"""
    code: int
    message: str
    data: Optional[Any] = None


class ToolExecutionContext(BaseModel):
    """Context for tool execution"""
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    trace_id: Optional[str] = None
    request_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


# Enhanced tool definitions with AI capabilities
AVAILABLE_TOOLS = [
    # Airtable tools
    Tool(
        name="airtable_list_bases",
        type=ToolType.AIRTABLE_LIST_BASES,
        description="List all accessible Airtable bases",
        parameters=[],
        category="airtable",
        examples=[
            {
                "description": "List all bases",
                "arguments": {},
                "expected_result": "List of base objects with id, name, and permissions"
            }
        ]
    ),
    Tool(
        name="airtable_get_schema",
        type=ToolType.AIRTABLE_GET_SCHEMA,
        description="Get schema for an Airtable base including tables and fields",
        parameters=[
            ToolParameter(name="base_id", type="string", description="Airtable base ID")
        ],
        category="airtable",
        examples=[
            {
                "description": "Get schema for a base",
                "arguments": {"base_id": "appXXXXXXXXXXXXXX"},
                "expected_result": "Base schema with tables and field definitions"
            }
        ]
    ),
    Tool(
        name="airtable_list_records",
        type=ToolType.AIRTABLE_LIST_RECORDS,
        description="List records from an Airtable table with optional filtering and sorting",
        parameters=[
            ToolParameter(name="base_id", type="string", description="Airtable base ID"),
            ToolParameter(name="table_id", type="string", description="Airtable table ID"),
            ToolParameter(name="view", type="string", description="View name", required=False),
            ToolParameter(name="max_records", type="integer", description="Maximum records to return", required=False, minimum=1, maximum=100),
            ToolParameter(name="filter_by_formula", type="string", description="Airtable formula for filtering", required=False),
            ToolParameter(name="sort", type="array", description="Sort configuration", required=False)
        ],
        category="airtable",
        examples=[
            {
                "description": "List first 10 records",
                "arguments": {"base_id": "appXXXXXXXXXXXXXX", "table_id": "tblXXXXXXXXXXXXXX", "max_records": 10},
                "expected_result": "Array of record objects"
            }
        ]
    ),
    Tool(
        name="airtable_get_record",
        type=ToolType.AIRTABLE_GET_RECORD,
        description="Get a single Airtable record by ID",
        parameters=[
            ToolParameter(name="base_id", type="string", description="Airtable base ID"),
            ToolParameter(name="table_id", type="string", description="Airtable table ID"),
            ToolParameter(name="record_id", type="string", description="Record ID")
        ],
        category="airtable"
    ),
    Tool(
        name="airtable_create_records",
        type=ToolType.AIRTABLE_CREATE_RECORDS,
        description="Create new Airtable records",
        parameters=[
            ToolParameter(name="base_id", type="string", description="Airtable base ID"),
            ToolParameter(name="table_id", type="string", description="Airtable table ID"),
            ToolParameter(name="records", type="array", description="Array of record objects to create"),
            ToolParameter(name="typecast", type="boolean", description="Enable automatic typecasting", required=False, default=False)
        ],
        category="airtable"
    ),
    Tool(
        name="airtable_update_records",
        type=ToolType.AIRTABLE_UPDATE_RECORDS,
        description="Update existing Airtable records",
        parameters=[
            ToolParameter(name="base_id", type="string", description="Airtable base ID"),
            ToolParameter(name="table_id", type="string", description="Airtable table ID"),
            ToolParameter(name="records", type="array", description="Array of record objects to update"),
            ToolParameter(name="typecast", type="boolean", description="Enable automatic typecasting", required=False, default=False),
            ToolParameter(name="replace", type="boolean", description="Replace entire record content", required=False, default=False)
        ],
        category="airtable"
    ),
    Tool(
        name="airtable_delete_records",
        type=ToolType.AIRTABLE_DELETE_RECORDS,
        description="Delete Airtable records by ID",
        parameters=[
            ToolParameter(name="base_id", type="string", description="Airtable base ID"),
            ToolParameter(name="table_id", type="string", description="Airtable table ID"),
            ToolParameter(name="record_ids", type="array", description="Array of record IDs to delete")
        ],
        category="airtable"
    ),
    
    # Utility tools
    Tool(
        name="calculate",
        type=ToolType.CALCULATE,
        description="Perform mathematical calculations and expressions",
        parameters=[
            ToolParameter(name="expression", type="string", description="Mathematical expression to evaluate")
        ],
        category="utility",
        examples=[
            {
                "description": "Simple calculation",
                "arguments": {"expression": "2 + 2 * 3"},
                "expected_result": {"expression": "2 + 2 * 3", "result": 8}
            }
        ]
    ),
    Tool(
        name="search",
        type=ToolType.SEARCH,
        description="Search across Airtable data using full-text search",
        parameters=[
            ToolParameter(name="query", type="string", description="Search query"),
            ToolParameter(name="base_id", type="string", description="Limit search to specific base", required=False),
            ToolParameter(name="table_id", type="string", description="Limit search to specific table", required=False),
            ToolParameter(name="limit", type="integer", description="Maximum results to return", required=False, default=10, minimum=1, maximum=100)
        ],
        category="search"
    ),
    Tool(
        name="query_database",
        type=ToolType.QUERY_DATABASE,
        description="Execute SQL query on metadata database",
        parameters=[
            ToolParameter(name="query", type="string", description="SQL query to execute"),
            ToolParameter(name="params", type="object", description="Query parameters", required=False)
        ],
        category="database"
    ),
    
    # AI tools
    Tool(
        name="generate_embeddings",
        type=ToolType.GENERATE_EMBEDDINGS,
        description="Generate vector embeddings for text using AI models",
        parameters=[
            ToolParameter(name="text", type="string", description="Text to generate embeddings for"),
            ToolParameter(name="model", type="string", description="Embedding model to use", required=False, 
                         enum=["text-embedding-3-small", "text-embedding-3-large", "all-MiniLM-L6-v2"]),
            ToolParameter(name="normalize", type="boolean", description="Normalize embeddings", required=False, default=True)
        ],
        category="ai",
        examples=[
            {
                "description": "Generate embeddings for text",
                "arguments": {"text": "Hello world", "model": "text-embedding-3-small"},
                "expected_result": "Array of float values representing the embedding vector"
            }
        ]
    ),
    Tool(
        name="semantic_search",
        type=ToolType.SEMANTIC_SEARCH,
        description="Perform semantic search using vector embeddings",
        parameters=[
            ToolParameter(name="query", type="string", description="Search query"),
            ToolParameter(name="collection", type="string", description="Vector collection to search", required=False),
            ToolParameter(name="limit", type="integer", description="Maximum results to return", required=False, default=10, minimum=1, maximum=100),
            ToolParameter(name="threshold", type="number", description="Similarity threshold", required=False, minimum=0.0, maximum=1.0)
        ],
        category="ai"
    ),
    Tool(
        name="classify_text",
        type=ToolType.CLASSIFY_TEXT,
        description="Classify text using AI models",
        parameters=[
            ToolParameter(name="text", type="string", description="Text to classify"),
            ToolParameter(name="model", type="string", description="Classification model to use", required=False),
            ToolParameter(name="labels", type="array", description="Possible classification labels", required=False),
            ToolParameter(name="return_probabilities", type="boolean", description="Return classification probabilities", required=False, default=True)
        ],
        category="ai"
    ),
    Tool(
        name="summarize_text",
        type=ToolType.SUMMARIZE_TEXT,
        description="Generate text summaries using AI models",
        parameters=[
            ToolParameter(name="text", type="string", description="Text to summarize"),
            ToolParameter(name="max_length", type="integer", description="Maximum summary length in words", required=False, default=100, minimum=10, maximum=1000),
            ToolParameter(name="style", type="string", description="Summary style", required=False, enum=["concise", "detailed", "bullet-points"], default="concise")
        ],
        category="ai"
    ),
    Tool(
        name="extract_entities",
        type=ToolType.EXTRACT_ENTITIES,
        description="Extract named entities from text using AI models",
        parameters=[
            ToolParameter(name="text", type="string", description="Text to extract entities from"),
            ToolParameter(name="entity_types", type="array", description="Types of entities to extract", required=False,
                         enum=["PERSON", "ORG", "GPE", "DATE", "MONEY", "EMAIL", "PHONE"]),
            ToolParameter(name="model", type="string", description="NER model to use", required=False)
        ],
        category="ai"
    )
]


def get_tool_by_name(name: str) -> Optional[Tool]:
    """Get tool definition by name"""
    for tool in AVAILABLE_TOOLS:
        if tool.name == name:
            return tool
    return None


def get_tools_by_category(category: str) -> List[Tool]:
    """Get all tools in a specific category"""
    return [tool for tool in AVAILABLE_TOOLS if tool.category == category]


def validate_tool_arguments(tool_name: str, arguments: Dict[str, Any]) -> bool:
    """Validate tool arguments against tool definition"""
    tool = get_tool_by_name(tool_name)
    if not tool:
        return False
    
    # Check required parameters
    for param in tool.parameters:
        if param.required and param.name not in arguments:
            return False
        
        # Validate parameter types and constraints
        if param.name in arguments:
            value = arguments[param.name]
            
            # Type validation (simplified)
            if param.type == "integer" and not isinstance(value, int):
                return False
            elif param.type == "number" and not isinstance(value, (int, float)):
                return False
            elif param.type == "string" and not isinstance(value, str):
                return False
            elif param.type == "boolean" and not isinstance(value, bool):
                return False
            elif param.type == "array" and not isinstance(value, list):
                return False
            elif param.type == "object" and not isinstance(value, dict):
                return False
            
            # Range validation
            if param.minimum is not None and isinstance(value, (int, float)) and value < param.minimum:
                return False
            if param.maximum is not None and isinstance(value, (int, float)) and value > param.maximum:
                return False
            
            # Enum validation
            if param.enum and value not in param.enum:
                return False
    
    return True