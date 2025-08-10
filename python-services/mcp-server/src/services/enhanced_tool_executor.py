"""Enhanced Tool Executor with retry logic, caching, and authentication for Sprint 2"""
import time
import json
import hashlib
import asyncio
import logging
from typing import Any, Dict, Optional, List
from datetime import datetime, timedelta
from contextlib import asynccontextmanager

import httpx
import jwt
from redis import asyncio as aioredis
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from ..config import get_settings
from ..models.enhanced_mcp import (
    ToolCall, ToolResult, ToolError, AuthContext, ExecutionStatus, ErrorCode,
    BatchToolCall, BatchToolResult, CacheEntry, ToolExecutionMetrics,
    ENHANCED_AVAILABLE_TOOLS, LEGACY_TOOL_MAPPING, ToolType
)

logger = logging.getLogger(__name__)


class EnhancedToolExecutor:
    """Enhanced service for executing MCP tools with advanced features"""
    
    def __init__(self):
        self.settings = get_settings()
        self.client = httpx.AsyncClient(
            timeout=httpx.Timeout(self.settings.request_timeout),
            limits=httpx.Limits(max_keepalive_connections=20, max_connections=100)
        )
        self.redis_client: Optional[aioredis.Redis] = None
        self.metrics: Dict[str, ToolExecutionMetrics] = {}
        self._authenticated_sessions: Dict[str, AuthContext] = {}
        
        # Tool name mapping for backward compatibility
        self.tool_mapping = {tool.name: tool for tool in ENHANCED_AVAILABLE_TOOLS}
        self.tool_mapping.update({legacy: self.tool_mapping[new] for legacy, new in LEGACY_TOOL_MAPPING.items() if new in self.tool_mapping})
        
    async def initialize(self):
        """Initialize Redis connection and other async resources"""
        try:
            if self.settings.enable_caching:
                self.redis_client = aioredis.from_url(
                    self.settings.redis_url,
                    decode_responses=True,
                    retry_on_timeout=True,
                    socket_keepalive=True
                )
                await self.redis_client.ping()
                logger.info("Redis connection established for caching")
        except Exception as e:
            logger.warning(f"Redis initialization failed: {e}. Caching disabled.")
            self.redis_client = None
    
    async def close(self):
        """Close all connections"""
        await self.client.aclose()
        if self.redis_client:
            await self.redis_client.close()
    
    @asynccontextmanager
    async def get_client(self):
        """Context manager for HTTP client with proper cleanup"""
        try:
            yield self.client
        except Exception as e:
            logger.error(f"HTTP client error: {e}")
            raise
    
    async def authenticate_request(self, auth_context: Optional[AuthContext]) -> AuthContext:
        """Validate and enhance authentication context"""
        if not auth_context:
            raise ValueError("Authentication required for tool execution")
            
        # Check if token is expired
        if auth_context.token_expiry and auth_context.token_expiry < datetime.utcnow():
            raise ValueError("Authentication token has expired")
            
        # Validate with platform services if JWT secret is available
        if self.settings.jwt_secret and auth_context.session_id:
            try:
                # Here you would validate the JWT token
                # For now, we'll assume it's valid if present
                pass
            except jwt.InvalidTokenError:
                raise ValueError("Invalid authentication token")
        
        return auth_context
    
    def _generate_cache_key(self, tool_name: str, arguments: Dict[str, Any], user_id: Optional[str] = None) -> str:
        """Generate cache key for tool call results"""
        # Create a deterministic hash of the arguments
        args_str = json.dumps(arguments, sort_keys=True)
        args_hash = hashlib.md5(args_str.encode()).hexdigest()
        
        # Include user_id for user-specific caching
        user_prefix = f"user:{user_id}:" if user_id else ""
        return f"mcp:tool:{user_prefix}{tool_name}:{args_hash}"
    
    async def _get_cached_result(self, cache_key: str) -> Optional[Any]:
        """Get cached result if available and not expired"""
        if not self.redis_client or not self.settings.enable_caching:
            return None
            
        try:
            cached_data = await self.redis_client.get(cache_key)
            if cached_data:
                cache_entry = CacheEntry.parse_raw(cached_data)
                
                # Check if expired
                if cache_entry.expires_at and cache_entry.expires_at < datetime.utcnow():
                    await self.redis_client.delete(cache_key)
                    return None
                
                # Increment hit count
                cache_entry.hit_count += 1
                await self.redis_client.set(
                    cache_key, 
                    cache_entry.json(),
                    ex=self.settings.cache_ttl
                )
                
                logger.debug(f"Cache hit for key: {cache_key}")
                return cache_entry.result
                
        except Exception as e:
            logger.warning(f"Cache retrieval error: {e}")
            
        return None
    
    async def _cache_result(self, cache_key: str, tool_name: str, arguments: Dict[str, Any], result: Any, user_id: Optional[str] = None):
        """Cache tool execution result"""
        if not self.redis_client or not self.settings.enable_caching:
            return
            
        try:
            # Create cache entry
            cache_entry = CacheEntry(
                key=cache_key,
                tool=tool_name,
                arguments_hash=hashlib.md5(json.dumps(arguments, sort_keys=True).encode()).hexdigest(),
                result=result,
                expires_at=datetime.utcnow() + timedelta(seconds=self.settings.cache_ttl),
                user_id=user_id
            )
            
            await self.redis_client.set(
                cache_key,
                cache_entry.json(),
                ex=self.settings.cache_ttl
            )
            
            logger.debug(f"Cached result for key: {cache_key}")
            
        except Exception as e:
            logger.warning(f"Cache storage error: {e}")
    
    async def _update_metrics(self, tool_name: str, duration_ms: float, success: bool, error_code: Optional[str] = None, cache_hit: bool = False):
        """Update execution metrics"""
        if tool_name not in self.metrics:
            self.metrics[tool_name] = ToolExecutionMetrics(tool_name=tool_name)
            
        metrics = self.metrics[tool_name]
        metrics.total_calls += 1
        metrics.last_executed = datetime.utcnow()
        
        if success:
            metrics.successful_calls += 1
        else:
            metrics.failed_calls += 1
            if error_code:
                metrics.error_rates[error_code] = metrics.error_rates.get(error_code, 0) + 1
        
        # Update rolling average duration
        if duration_ms > 0:
            total_duration = metrics.avg_duration_ms * (metrics.total_calls - 1) + duration_ms
            metrics.avg_duration_ms = total_duration / metrics.total_calls
        
        # Update cache hit rate
        if cache_hit:
            cache_hits = metrics.cache_hit_rate * metrics.total_calls / 100 + 1
            metrics.cache_hit_rate = (cache_hits / metrics.total_calls) * 100
    
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=10),
        retry=retry_if_exception_type((httpx.NetworkError, httpx.TimeoutException))
    )
    async def _make_http_request(self, method: str, url: str, **kwargs) -> httpx.Response:
        """Make HTTP request with retry logic"""
        async with self.get_client() as client:
            response = await client.request(method, url, **kwargs)
            response.raise_for_status()
            return response
    
    async def execute(self, tool_call: ToolCall) -> ToolResult:
        """Execute a single tool call with enhanced features"""
        start_time = time.time()
        cache_hit = False
        
        try:
            # Validate authentication
            if tool_call.auth_context:
                await self.authenticate_request(tool_call.auth_context)
            
            # Validate tool exists
            if tool_call.tool not in self.tool_mapping:
                error = ToolError(
                    code=ErrorCode.UNKNOWN_TOOL,
                    message=f"Unknown tool: {tool_call.tool}",
                    retryable=False
                )
                return ToolResult(
                    call_id=tool_call.id,
                    tool=tool_call.tool,
                    status=ExecutionStatus.FAILED,
                    error=error,
                    duration_ms=(time.time() - start_time) * 1000
                )
            
            # Check cache first
            cache_key = self._generate_cache_key(
                tool_call.tool, 
                tool_call.arguments, 
                tool_call.auth_context.user_id if tool_call.auth_context else None
            )
            
            cached_result = await self._get_cached_result(cache_key)
            if cached_result is not None:
                cache_hit = True
                duration_ms = (time.time() - start_time) * 1000
                await self._update_metrics(tool_call.tool, duration_ms, True, cache_hit=True)
                
                return ToolResult(
                    call_id=tool_call.id,
                    tool=tool_call.tool,
                    status=ExecutionStatus.COMPLETED,
                    result=cached_result,
                    duration_ms=duration_ms,
                    cache_hit=True,
                    completed_at=datetime.utcnow()
                )
            
            # Execute the tool
            result = await self._execute_tool_implementation(tool_call)
            
            # Cache the result
            user_id = tool_call.auth_context.user_id if tool_call.auth_context else None
            await self._cache_result(cache_key, tool_call.tool, tool_call.arguments, result, user_id)
            
            duration_ms = (time.time() - start_time) * 1000
            await self._update_metrics(tool_call.tool, duration_ms, True, cache_hit=cache_hit)
            
            return ToolResult(
                call_id=tool_call.id,
                tool=tool_call.tool,
                status=ExecutionStatus.COMPLETED,
                result=result,
                duration_ms=duration_ms,
                cache_hit=cache_hit,
                completed_at=datetime.utcnow()
            )
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            
            # Determine error code and retryability
            if isinstance(e, httpx.TimeoutException):
                error_code = ErrorCode.TIMEOUT_ERROR
                retryable = True
            elif isinstance(e, httpx.NetworkError):
                error_code = ErrorCode.NETWORK_ERROR
                retryable = True
            elif isinstance(e, ValueError) and "Authentication" in str(e):
                error_code = ErrorCode.AUTHENTICATION_FAILED
                retryable = False
            elif "rate limit" in str(e).lower():
                error_code = ErrorCode.RATE_LIMIT_EXCEEDED
                retryable = True
            else:
                error_code = ErrorCode.INTERNAL_ERROR
                retryable = False
            
            await self._update_metrics(tool_call.tool, duration_ms, False, error_code.value)
            
            error = ToolError(
                code=error_code,
                message=str(e),
                retryable=retryable,
                trace_id=tool_call.metadata.get("trace_id")
            )
            
            return ToolResult(
                call_id=tool_call.id,
                tool=tool_call.tool,
                status=ExecutionStatus.FAILED,
                error=error,
                duration_ms=duration_ms
            )
    
    async def _execute_tool_implementation(self, tool_call: ToolCall) -> Any:
        """Execute the actual tool implementation"""
        tool_name = tool_call.tool
        args = tool_call.arguments
        
        # Map legacy tool names to new ones
        if tool_name in LEGACY_TOOL_MAPPING:
            tool_name = LEGACY_TOOL_MAPPING[tool_name]
        
        # Route to appropriate handler based on tool type
        tool_info = self.tool_mapping.get(tool_name)
        if not tool_info:
            raise ValueError(f"Tool not implemented: {tool_name}")
        
        if tool_info.type in [ToolType.LIST_BASES, ToolType.AIRTABLE_LIST_BASES]:
            return await self._execute_list_bases(args)
        elif tool_info.type in [ToolType.LIST_TABLES]:
            return await self._execute_list_tables(args)
        elif tool_info.type in [ToolType.GET_SCHEMA, ToolType.AIRTABLE_GET_SCHEMA]:
            return await self._execute_get_schema(args)
        elif tool_info.type in [ToolType.LIST_RECORDS, ToolType.AIRTABLE_LIST_RECORDS]:
            return await self._execute_list_records(args)
        elif tool_info.type in [ToolType.CREATE_RECORD]:
            return await self._execute_create_record(args)
        elif tool_info.type in [ToolType.UPDATE_RECORD]:
            return await self._execute_update_record(args)
        elif tool_info.type in [ToolType.DELETE_RECORD]:
            return await self._execute_delete_record(args)
        elif tool_info.type in [ToolType.BATCH_CREATE, ToolType.AIRTABLE_CREATE_RECORDS]:
            return await self._execute_batch_create(args)
        elif tool_info.type in [ToolType.BATCH_UPDATE, ToolType.AIRTABLE_UPDATE_RECORDS]:
            return await self._execute_batch_update(args)
        elif tool_info.type in [ToolType.SEARCH_RECORDS]:
            return await self._execute_search_records(args)
        elif tool_info.type == ToolType.CALCULATE:
            return await self._execute_calculate(args)
        else:
            raise ValueError(f"Tool type not implemented: {tool_info.type}")
    
    # Implementation of the 10 required MCP tools
    
    async def _execute_list_bases(self, args: Dict[str, Any]) -> Any:
        """List all accessible Airtable bases"""
        url = f"{self.settings.airtable_gateway_url}/api/v1/bases"
        response = await self._make_http_request("GET", url)
        return response.json()
    
    async def _execute_list_tables(self, args: Dict[str, Any]) -> Any:
        """List tables in a base"""
        base_id = args["base_id"]
        url = f"{self.settings.airtable_gateway_url}/api/v1/bases/{base_id}/tables"
        response = await self._make_http_request("GET", url)
        return response.json()
    
    async def _execute_get_schema(self, args: Dict[str, Any]) -> Any:
        """Get schema for a base or table"""
        base_id = args["base_id"]
        table_id = args.get("table_id")
        
        if table_id:
            url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/schema"
            params = {"base_id": base_id}
        else:
            url = f"{self.settings.airtable_gateway_url}/api/v1/bases/{base_id}/schema"
            params = {}
        
        response = await self._make_http_request("GET", url, params=params)
        return response.json()
    
    async def _execute_list_records(self, args: Dict[str, Any]) -> Any:
        """List records from a table"""
        base_id = args["base_id"]
        table_id = args["table_id"]
        
        url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records"
        
        # Build query parameters
        params = {"base_id": base_id}
        
        optional_params = [
            "view", "max_records", "page_size", "offset", 
            "fields", "filter_by_formula", "sort_field", "sort_direction"
        ]
        
        for param in optional_params:
            if param in args:
                params[param] = args[param]
        
        # Handle sort parameter (convert from array to individual fields)
        if "sort" in args and isinstance(args["sort"], list) and args["sort"]:
            sort_item = args["sort"][0]  # Take first sort field
            if isinstance(sort_item, dict):
                params["sort_field"] = sort_item.get("field")
                params["sort_direction"] = sort_item.get("direction", "asc")
        
        response = await self._make_http_request("GET", url, params=params)
        return response.json()
    
    async def _execute_create_record(self, args: Dict[str, Any]) -> Any:
        """Create a single record"""
        base_id = args["base_id"]
        table_id = args["table_id"]
        fields = args["fields"]
        typecast = args.get("typecast", False)
        
        url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records"
        params = {"base_id": base_id, "typecast": typecast}
        
        # Convert single record to array format expected by the API
        payload = [fields]  # API expects array of field objects
        
        response = await self._make_http_request("POST", url, params=params, json=payload)
        result = response.json()
        
        # Return just the first record if it's an array
        if isinstance(result, dict) and "records" in result and result["records"]:
            return result["records"][0]
        return result
    
    async def _execute_update_record(self, args: Dict[str, Any]) -> Any:
        """Update a single record"""
        base_id = args["base_id"]
        table_id = args["table_id"]
        record_id = args["record_id"]
        fields = args["fields"]
        typecast = args.get("typecast", False)
        replace = args.get("replace", False)
        
        if replace:
            # Use PUT endpoint for full record replacement
            url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records/{record_id}"
            method = "PUT"
        else:
            # Use PATCH endpoint for partial update
            url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records/{record_id}"
            method = "PATCH"
        
        params = {"base_id": base_id, "typecast": typecast}
        
        response = await self._make_http_request(method, url, params=params, json=fields)
        return response.json()
    
    async def _execute_delete_record(self, args: Dict[str, Any]) -> Any:
        """Delete a single record"""
        base_id = args["base_id"]
        table_id = args["table_id"]
        record_id = args["record_id"]
        
        url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records/{record_id}"
        params = {"base_id": base_id}
        
        response = await self._make_http_request("DELETE", url, params=params)
        return response.json()
    
    async def _execute_batch_create(self, args: Dict[str, Any]) -> Any:
        """Create multiple records in batch"""
        base_id = args["base_id"]
        table_id = args["table_id"]
        records = args["records"]
        typecast = args.get("typecast", False)
        
        url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records"
        params = {"base_id": base_id, "typecast": typecast}
        
        response = await self._make_http_request("POST", url, params=params, json=records)
        return response.json()
    
    async def _execute_batch_update(self, args: Dict[str, Any]) -> Any:
        """Update multiple records in batch"""
        base_id = args["base_id"]
        table_id = args["table_id"]
        records = args["records"]
        typecast = args.get("typecast", False)
        replace = args.get("replace", False)
        
        url = f"{self.settings.airtable_gateway_url}/api/v1/tables/{table_id}/records/batch"
        params = {
            "base_id": base_id,
            "operation": "update",
            "typecast": typecast
        }
        
        response = await self._make_http_request("POST", url, params=params, json=records)
        return response.json()
    
    async def _execute_search_records(self, args: Dict[str, Any]) -> Any:
        """Search records across tables"""
        base_id = args["base_id"]
        query = args["query"]
        table_id = args.get("table_id")
        fields = args.get("fields")
        max_results = args.get("max_results", 50)
        
        # For now, implement as filtered list_records
        # In a full implementation, this would use a dedicated search endpoint
        if table_id:
            # Search within specific table using filter_by_formula
            search_args = {
                "base_id": base_id,
                "table_id": table_id,
                "max_records": max_results,
                "filter_by_formula": f"SEARCH(LOWER('{query}'), LOWER(CONCATENATE(values)))"
            }
            if fields:
                search_args["fields"] = fields
            
            return await self._execute_list_records(search_args)
        else:
            # Search across all tables in base
            # This would require getting table list first, then searching each
            return {
                "query": query,
                "base_id": base_id,
                "results": [],
                "message": "Cross-table search not yet fully implemented. Please specify a table_id."
            }
    
    async def _execute_calculate(self, args: Dict[str, Any]) -> Any:
        """Execute mathematical calculations"""
        expression = args["expression"]
        
        # Basic safety check
        allowed_chars = "0123456789+-*/()., "
        if not all(c in allowed_chars for c in expression):
            raise ValueError("Invalid characters in expression")
        
        try:
            result = eval(expression)  # In production, use a safer math parser
            return {
                "expression": expression,
                "result": result,
                "type": type(result).__name__
            }
        except Exception as e:
            raise ValueError(f"Calculation error: {str(e)}")
    
    async def execute_batch(self, batch_call: BatchToolCall) -> BatchToolResult:
        """Execute multiple tool calls in batch"""
        start_time = time.time()
        results = []
        
        if batch_call.parallel:
            # Execute in parallel
            tasks = [self.execute(tool_call) for tool_call in batch_call.tool_calls]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Convert exceptions to error results
            for i, result in enumerate(results):
                if isinstance(result, Exception):
                    error = ToolError(
                        code=ErrorCode.INTERNAL_ERROR,
                        message=str(result),
                        retryable=False
                    )
                    results[i] = ToolResult(
                        call_id=batch_call.tool_calls[i].id,
                        tool=batch_call.tool_calls[i].tool,
                        status=ExecutionStatus.FAILED,
                        error=error
                    )
        else:
            # Execute sequentially
            for tool_call in batch_call.tool_calls:
                result = await self.execute(tool_call)
                results.append(result)
                
                # Stop on error if configured
                if batch_call.stop_on_error and result.status == ExecutionStatus.FAILED:
                    break
        
        total_duration_ms = (time.time() - start_time) * 1000
        success_count = sum(1 for r in results if r.status == ExecutionStatus.COMPLETED)
        error_count = len(results) - success_count
        
        return BatchToolResult(
            batch_id=batch_call.id,
            results=results,
            total_duration_ms=total_duration_ms,
            success_count=success_count,
            error_count=error_count
        )
    
    async def get_metrics(self) -> Dict[str, ToolExecutionMetrics]:
        """Get execution metrics for all tools"""
        return self.metrics.copy()
    
    async def invalidate_cache(self, pattern: Optional[str] = None) -> int:
        """Invalidate cache entries"""
        if not self.redis_client:
            return 0
        
        try:
            if pattern:
                keys = await self.redis_client.keys(f"mcp:tool:*{pattern}*")
            else:
                keys = await self.redis_client.keys("mcp:tool:*")
            
            if keys:
                deleted_count = await self.redis_client.delete(*keys)
                logger.info(f"Invalidated {deleted_count} cache entries")
                return deleted_count
            
            return 0
        except Exception as e:
            logger.error(f"Cache invalidation error: {e}")
            return 0