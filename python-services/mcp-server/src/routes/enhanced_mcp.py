"""Enhanced MCP protocol routes with 10 required tools and HTTP mode support"""
from typing import List, Dict, Any, Optional
import asyncio
import logging
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ValidationError

from ..models.enhanced_mcp import (
    MCPRequest, MCPResponse, MCPError, ToolCall, ToolResult, BatchToolCall, BatchToolResult,
    AuthContext, ENHANCED_AVAILABLE_TOOLS, ExecutionStatus
)
from ..services.enhanced_tool_executor import EnhancedToolExecutor
from ..dependencies import get_tool_executor, get_current_user_optional, get_current_user, validate_rate_limit

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/mcp", tags=["mcp-enhanced"])

# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
        self.user_connections: Dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, user_id: Optional[str] = None):
        await websocket.accept()
        self.active_connections.append(websocket)
        if user_id:
            self.user_connections[user_id] = websocket

    def disconnect(self, websocket: WebSocket, user_id: Optional[str] = None):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        if user_id and user_id in self.user_connections:
            del self.user_connections[user_id]

    async def send_personal_message(self, message: str, websocket: WebSocket):
        await websocket.send_text(message)

    async def send_to_user(self, message: str, user_id: str):
        if user_id in self.user_connections:
            websocket = self.user_connections[user_id]
            await websocket.send_text(message)

manager = ConnectionManager()


# Request/Response models for HTTP endpoints
class ToolExecuteRequest(BaseModel):
    tool: str
    arguments: Dict[str, Any] = {}
    metadata: Dict[str, Any] = {}
    timeout_seconds: Optional[int] = None


class BatchExecuteRequest(BaseModel):
    tool_calls: List[ToolExecuteRequest]
    parallel: bool = True
    stop_on_error: bool = False
    timeout_seconds: Optional[int] = 60


# MCP Protocol Implementation

@router.post("/rpc", response_model=MCPResponse)
async def mcp_rpc(
    request: MCPRequest,
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    auth_context: Optional[AuthContext] = Depends(get_current_user_optional),
    _rate_limit: None = Depends(validate_rate_limit)
) -> MCPResponse:
    """Handle MCP RPC requests according to protocol specification"""
    start_time = datetime.utcnow()
    
    try:
        # Route based on method
        if request.method == "initialize":
            result = await handle_initialize(request.params)
        elif request.method == "list_tools":
            result = await handle_list_tools()
        elif request.method == "call_tool":
            result = await handle_call_tool(request.params, executor, auth_context)
        elif request.method == "completion/complete":
            result = await handle_complete(request.params, executor, auth_context)
        elif request.method == "batch_call_tools":
            result = await handle_batch_call_tools(request.params, executor, auth_context)
        else:
            return MCPResponse(
                id=request.id,
                trace_id=request.trace_id,
                error={
                    "code": -32601,
                    "message": f"Method not found: {request.method}"
                },
                duration_ms=(datetime.utcnow() - start_time).total_seconds() * 1000
            )
        
        return MCPResponse(
            id=request.id,
            trace_id=request.trace_id,
            result=result,
            duration_ms=(datetime.utcnow() - start_time).total_seconds() * 1000
        )
        
    except ValidationError as e:
        return MCPResponse(
            id=request.id,
            trace_id=request.trace_id,
            error={
                "code": -32602,
                "message": "Invalid params",
                "data": str(e)
            },
            duration_ms=(datetime.utcnow() - start_time).total_seconds() * 1000
        )
    except Exception as e:
        logger.error(f"MCP RPC error: {e}", exc_info=True)
        return MCPResponse(
            id=request.id,
            trace_id=request.trace_id,
            error={
                "code": -32603,
                "message": "Internal error",
                "data": str(e)
            },
            duration_ms=(datetime.utcnow() - start_time).total_seconds() * 1000
        )


async def handle_initialize(params: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Handle MCP initialize request"""
    return {
        "protocol_version": "1.0",
        "server_info": {
            "name": "pyairtable-mcp-server",
            "version": "1.0.0",
            "description": "Enhanced MCP server for PyAirtable with 10 core tools",
            "capabilities": {
                "tools": True,
                "completion": False,
                "resources": False,
                "streaming": True,
                "batch_execution": True,
                "caching": True,
                "rate_limiting": True
            }
        },
        "supported_features": [
            "authentication",
            "rate_limiting", 
            "caching",
            "batch_operations",
            "metrics",
            "websocket_fallback"
        ]
    }


async def handle_list_tools() -> List[Dict[str, Any]]:
    """Handle list_tools request - return all 10 required tools"""
    return [
        {
            "name": tool.name,
            "description": tool.description,
            "category": tool.category,
            "tags": tool.tags,
            "input_schema": {
                "type": "object",
                "properties": {
                    param.name: {
                        "type": param.type.value,
                        "description": param.description,
                        **({"default": param.default} if param.default is not None else {}),
                        **({"enum": param.enum} if param.enum else {}),
                        **({"pattern": param.pattern} if param.pattern else {}),
                        **({"minimum": param.min_value} if param.min_value is not None else {}),
                        **({"maximum": param.max_value} if param.max_value is not None else {}),
                        **({"minLength": param.min_length} if param.min_length is not None else {}),
                        **({"maxLength": param.max_length} if param.max_length is not None else {})
                    }
                    for param in tool.parameters
                },
                "required": [param.name for param in tool.parameters if param.required]
            },
            "examples": tool.examples,
            "rate_limit": tool.rate_limit,
            "timeout_seconds": tool.timeout_seconds,
            "deprecated": tool.deprecated
        }
        for tool in ENHANCED_AVAILABLE_TOOLS
    ]


async def handle_call_tool(
    params: Dict[str, Any],
    executor: EnhancedToolExecutor,
    auth_context: Optional[AuthContext]
) -> Dict[str, Any]:
    """Handle single tool call"""
    tool_name = params.get("name")
    arguments = params.get("arguments", {})
    
    # Validate tool exists
    if not any(tool.name == tool_name for tool in ENHANCED_AVAILABLE_TOOLS):
        raise ValueError(f"Unknown tool: {tool_name}")
    
    # Create tool call
    tool_call = ToolCall(
        tool=tool_name,
        arguments=arguments,
        auth_context=auth_context,
        metadata=params.get("metadata", {})
    )
    
    # Execute tool
    result = await executor.execute(tool_call)
    
    if result.error:
        return {
            "error": {
                "code": result.error.code.value,
                "message": result.error.message,
                "details": result.error.details,
                "retryable": result.error.retryable
            },
            "duration_ms": result.duration_ms,
            "cache_hit": result.cache_hit
        }
    
    return {
        "result": result.result,
        "duration_ms": result.duration_ms,
        "cache_hit": result.cache_hit,
        "usage": result.usage
    }


async def handle_batch_call_tools(
    params: Dict[str, Any],
    executor: EnhancedToolExecutor,
    auth_context: Optional[AuthContext]
) -> Dict[str, Any]:
    """Handle batch tool calls"""
    tool_calls_data = params.get("tool_calls", [])
    parallel = params.get("parallel", True)
    stop_on_error = params.get("stop_on_error", False)
    
    # Create tool call objects
    tool_calls = []
    for call_data in tool_calls_data:
        tool_call = ToolCall(
            tool=call_data["name"],
            arguments=call_data.get("arguments", {}),
            auth_context=auth_context,
            metadata=call_data.get("metadata", {})
        )
        tool_calls.append(tool_call)
    
    # Create batch call
    batch_call = BatchToolCall(
        tool_calls=tool_calls,
        parallel=parallel,
        stop_on_error=stop_on_error
    )
    
    # Execute batch
    batch_result = await executor.execute_batch(batch_call)
    
    return {
        "batch_id": batch_result.batch_id,
        "results": [
            {
                "call_id": r.call_id,
                "tool": r.tool,
                "status": r.status.value,
                "result": r.result,
                "error": r.error.dict() if r.error else None,
                "duration_ms": r.duration_ms,
                "cache_hit": r.cache_hit
            }
            for r in batch_result.results
        ],
        "total_duration_ms": batch_result.total_duration_ms,
        "success_count": batch_result.success_count,
        "error_count": batch_result.error_count
    }


async def handle_complete(
    params: Dict[str, Any],
    executor: EnhancedToolExecutor,
    auth_context: Optional[AuthContext]
) -> Dict[str, Any]:
    """Handle completion request (placeholder for LLM integration)"""
    return {
        "completion": "Completion functionality delegated to LLM Orchestrator service",
        "usage": {
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0
        }
    }


# HTTP REST API endpoints for the 10 tools

@router.get("/tools", response_model=List[Dict[str, Any]])
async def list_tools():
    """List all available tools (REST endpoint)"""
    return await handle_list_tools()


@router.get("/tools/{tool_name}")
async def get_tool_info(tool_name: str):
    """Get detailed information about a specific tool"""
    tool = next((t for t in ENHANCED_AVAILABLE_TOOLS if t.name == tool_name), None)
    if not tool:
        raise HTTPException(status_code=404, detail=f"Tool not found: {tool_name}")
    
    tools_list = await handle_list_tools()
    return next((t for t in tools_list if t["name"] == tool_name), None)


@router.post("/tools/{tool_name}/execute")
async def execute_tool(
    tool_name: str,
    request: ToolExecuteRequest,
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    auth_context: Optional[AuthContext] = Depends(get_current_user_optional),
    _rate_limit: None = Depends(validate_rate_limit)
):
    """Execute a specific tool (REST endpoint)"""
    try:
        result = await handle_call_tool({
            "name": tool_name,
            "arguments": request.arguments,
            "metadata": request.metadata
        }, executor, auth_context)
        
        return result
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Tool execution error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/batch/execute")
async def execute_batch(
    request: BatchExecuteRequest,
    background_tasks: BackgroundTasks,
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    auth_context: Optional[AuthContext] = Depends(get_current_user_optional),
    _rate_limit: None = Depends(validate_rate_limit)
):
    """Execute multiple tools in batch"""
    try:
        # Convert request to internal format
        tool_calls_data = [
            {
                "name": call.tool,
                "arguments": call.arguments,
                "metadata": call.metadata
            }
            for call in request.tool_calls
        ]
        
        result = await handle_batch_call_tools({
            "tool_calls": tool_calls_data,
            "parallel": request.parallel,
            "stop_on_error": request.stop_on_error
        }, executor, auth_context)
        
        return result
        
    except Exception as e:
        logger.error(f"Batch execution error: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


# WebSocket endpoint for real-time tool execution
@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    executor: EnhancedToolExecutor = Depends(get_tool_executor)
):
    """WebSocket endpoint for real-time MCP tool execution"""
    user_id = None
    
    try:
        await manager.connect(websocket, user_id)
        logger.info(f"WebSocket client connected")
        
        while True:
            # Receive message
            data = await websocket.receive_text()
            
            try:
                message = MCPRequest.parse_raw(data)
                
                # Handle authentication if provided
                auth_context = None  # Would extract from message or headers
                
                # Process the request
                if message.method == "call_tool":
                    result = await handle_call_tool(message.params, executor, auth_context)
                    response = MCPResponse(id=message.id, result=result)
                elif message.method == "list_tools":
                    result = await handle_list_tools()
                    response = MCPResponse(id=message.id, result=result)
                else:
                    response = MCPResponse(
                        id=message.id,
                        error={"code": -32601, "message": f"Method not found: {message.method}"}
                    )
                
                # Send response
                await manager.send_personal_message(response.json(), websocket)
                
            except ValidationError as e:
                error_response = MCPResponse(
                    error={"code": -32602, "message": "Invalid request", "data": str(e)}
                )
                await manager.send_personal_message(error_response.json(), websocket)
            except Exception as e:
                logger.error(f"WebSocket processing error: {e}", exc_info=True)
                error_response = MCPResponse(
                    error={"code": -32603, "message": "Internal error", "data": str(e)}
                )
                await manager.send_personal_message(error_response.json(), websocket)
                
    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)
        logger.info(f"WebSocket client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}", exc_info=True)
        manager.disconnect(websocket, user_id)


# Monitoring and management endpoints

@router.get("/status")
async def mcp_status(
    executor: EnhancedToolExecutor = Depends(get_tool_executor)
):
    """Get MCP server status"""
    metrics = await executor.get_metrics()
    
    return {
        "protocol_version": "1.0",
        "server": {
            "name": "pyairtable-mcp-server",
            "version": "1.0.0",
            "description": "Enhanced MCP server for PyAirtable"
        },
        "status": "operational",
        "timestamp": datetime.utcnow().isoformat(),
        "capabilities": {
            "tools": len(ENHANCED_AVAILABLE_TOOLS),
            "completion": False,
            "resources": False,
            "streaming": True,
            "batch_execution": True,
            "caching": True
        },
        "available_tools": [tool.name for tool in ENHANCED_AVAILABLE_TOOLS],
        "connections": {
            "websocket_active": len(manager.active_connections),
            "websocket_users": len(manager.user_connections)
        },
        "metrics": {
            tool_name: {
                "total_calls": m.total_calls,
                "successful_calls": m.successful_calls,
                "failed_calls": m.failed_calls,
                "avg_duration_ms": m.avg_duration_ms,
                "cache_hit_rate": m.cache_hit_rate,
                "last_executed": m.last_executed.isoformat() if m.last_executed else None
            }
            for tool_name, m in metrics.items()
        }
    }


@router.get("/metrics")
async def get_metrics(
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    auth_context: AuthContext = Depends(get_current_user)
):
    """Get detailed execution metrics"""
    metrics = await executor.get_metrics()
    return {"metrics": metrics}


@router.post("/cache/invalidate")
async def invalidate_cache(
    pattern: Optional[str] = None,
    executor: EnhancedToolExecutor = Depends(get_tool_executor),
    auth_context: AuthContext = Depends(get_current_user)
):
    """Invalidate cache entries"""
    deleted_count = await executor.invalidate_cache(pattern)
    return {
        "status": "success",
        "message": f"Invalidated {deleted_count} cache entries",
        "pattern": pattern or "all"
    }


# Info endpoint
@router.get("/info")
async def mcp_info():
    """Get comprehensive MCP server information"""
    return {
        "protocol_version": "1.0",
        "server": {
            "name": "pyairtable-mcp-server",
            "version": "1.0.0",
            "description": "Enhanced Model Context Protocol server for PyAirtable with 10 core tools"
        },
        "implementation": {
            "language": "Python",
            "framework": "FastAPI",
            "features": [
                "HTTP mode",
                "WebSocket support",
                "Authentication & authorization",
                "Rate limiting",
                "Redis caching",
                "Retry logic with exponential backoff",
                "Batch execution",
                "Comprehensive error handling",
                "Metrics collection",
                "Health monitoring"
            ]
        },
        "tools": {
            "count": len(ENHANCED_AVAILABLE_TOOLS),
            "categories": list(set(tool.category for tool in ENHANCED_AVAILABLE_TOOLS)),
            "core_tools": [
                "list_bases", "list_tables", "get_schema", "list_records",
                "create_record", "update_record", "delete_record",
                "batch_create", "batch_update", "search_records"
            ]
        },
        "endpoints": {
            "mcp_rpc": "/mcp/rpc",
            "websocket": "/mcp/ws",
            "tools_list": "/mcp/tools",
            "tool_execute": "/mcp/tools/{tool_name}/execute",
            "batch_execute": "/mcp/batch/execute",
            "status": "/mcp/status",
            "metrics": "/mcp/metrics",
            "cache_invalidate": "/mcp/cache/invalidate"
        }
    }