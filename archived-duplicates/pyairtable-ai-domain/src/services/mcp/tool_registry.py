"""Tool Registry for managing MCP tools"""
import time
from typing import Dict, List, Optional, Any, Callable
from datetime import datetime

from ...models.mcp.tools import (
    Tool, ToolCall, ToolResult, ToolExecutionContext,
    AVAILABLE_TOOLS, get_tool_by_name, validate_tool_arguments
)
from ...core.config import get_settings
from ...core.logging import get_logger, MCPLogger
from .tool_executor import ToolExecutor


class ToolRegistry:
    """Registry for managing and executing MCP tools"""
    
    def __init__(self):
        self.settings = get_settings()
        self.logger = get_logger(__name__)
        self.mcp_logger = MCPLogger()
        
        # Tool registry
        self._tools: Dict[str, Tool] = {}
        self._executors: Dict[str, Callable] = {}
        self._tool_stats: Dict[str, Dict[str, Any]] = {}
        
        # Initialize executor
        self.executor = ToolExecutor()
        
        # Register built-in tools
        self._register_builtin_tools()
    
    def _register_builtin_tools(self) -> None:
        """Register all built-in tools"""
        for tool in AVAILABLE_TOOLS:
            if tool.name in self.settings.mcp_tools_enabled:
                self.register_tool(tool)
                self.logger.info(f"Registered tool: {tool.name}")
    
    def register_tool(self, tool: Tool, executor: Optional[Callable] = None) -> None:
        """Register a tool with optional custom executor"""
        self._tools[tool.name] = tool
        
        if executor:
            self._executors[tool.name] = executor
        
        # Initialize stats
        self._tool_stats[tool.name] = {
            "executions": 0,
            "total_duration_ms": 0.0,
            "success_count": 0,
            "error_count": 0,
            "last_executed": None,
            "average_duration_ms": 0.0
        }
        
        self.logger.info(f"Tool registered: {tool.name}")
    
    def unregister_tool(self, tool_name: str) -> bool:
        """Unregister a tool"""
        if tool_name in self._tools:
            del self._tools[tool_name]
            if tool_name in self._executors:
                del self._executors[tool_name]
            if tool_name in self._tool_stats:
                del self._tool_stats[tool_name]
            
            self.logger.info(f"Tool unregistered: {tool_name}")
            return True
        
        return False
    
    def get_tool(self, tool_name: str) -> Optional[Tool]:
        """Get tool definition by name"""
        return self._tools.get(tool_name)
    
    def list_tools(self, category: Optional[str] = None) -> List[Tool]:
        """List all registered tools, optionally filtered by category"""
        tools = list(self._tools.values())
        
        if category:
            tools = [tool for tool in tools if tool.category == category]
        
        return tools
    
    def get_tool_info(self, tool_name: str) -> Optional[Dict[str, Any]]:
        """Get comprehensive tool information"""
        tool = self.get_tool(tool_name)
        if not tool:
            return None
        
        stats = self._tool_stats.get(tool_name, {})
        
        return {
            "tool": tool.model_dump(),
            "statistics": stats,
            "has_custom_executor": tool_name in self._executors,
            "enabled": tool_name in self.settings.mcp_tools_enabled
        }
    
    async def execute_tool(
        self, 
        tool_call: ToolCall,
        context: Optional[ToolExecutionContext] = None
    ) -> ToolResult:
        """Execute a tool call"""
        start_time = time.time()
        
        # Validate tool exists
        tool = self.get_tool(tool_call.tool)
        if not tool:
            error_msg = f"Unknown tool: {tool_call.tool}"
            self.logger.error(error_msg)
            return ToolResult(
                call_id=tool_call.id,
                tool=tool_call.tool,
                result=None,
                error=error_msg,
                duration_ms=(time.time() - start_time) * 1000
            )
        
        # Validate arguments
        if not validate_tool_arguments(tool_call.tool, tool_call.arguments):
            error_msg = f"Invalid arguments for tool: {tool_call.tool}"
            self.logger.error(error_msg, arguments=tool_call.arguments)
            return ToolResult(
                call_id=tool_call.id,
                tool=tool_call.tool,
                result=None,
                error=error_msg,
                duration_ms=(time.time() - start_time) * 1000
            )
        
        try:
            # Use custom executor if available
            if tool_call.tool in self._executors:
                result = await self._executors[tool_call.tool](tool_call, context)
            else:
                # Use default executor
                result = await self.executor.execute(tool_call, context)
            
            duration_ms = (time.time() - start_time) * 1000
            
            # Update statistics
            self._update_tool_stats(tool_call.tool, duration_ms, success=True)
            
            # Log execution
            self.mcp_logger.log_tool_execution(
                tool_name=tool_call.tool,
                execution_time_ms=duration_ms,
                success=True,
                user_id=tool_call.user_id
            )
            
            return ToolResult(
                call_id=tool_call.id,
                tool=tool_call.tool,
                result=result,
                duration_ms=duration_ms
            )
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            error_msg = str(e)
            
            # Update statistics
            self._update_tool_stats(tool_call.tool, duration_ms, success=False)
            
            # Log execution
            self.mcp_logger.log_tool_execution(
                tool_name=tool_call.tool,
                execution_time_ms=duration_ms,
                success=False,
                error=error_msg,
                user_id=tool_call.user_id
            )
            
            self.logger.error(
                f"Tool execution failed",
                tool=tool_call.tool,
                error=error_msg,
                call_id=tool_call.id
            )
            
            return ToolResult(
                call_id=tool_call.id,
                tool=tool_call.tool,
                result=None,
                error=error_msg,
                duration_ms=duration_ms
            )
    
    async def execute_tools_batch(
        self,
        tool_calls: List[ToolCall],
        context: Optional[ToolExecutionContext] = None,
        parallel: bool = False
    ) -> List[ToolResult]:
        """Execute multiple tool calls"""
        if parallel:
            import asyncio
            tasks = [
                self.execute_tool(tool_call, context)
                for tool_call in tool_calls
            ]
            return await asyncio.gather(*tasks)
        else:
            results = []
            for tool_call in tool_calls:
                result = await self.execute_tool(tool_call, context)
                results.append(result)
            return results
    
    def get_tool_statistics(self, tool_name: Optional[str] = None) -> Dict[str, Any]:
        """Get tool execution statistics"""
        if tool_name:
            return self._tool_stats.get(tool_name, {})
        
        # Return aggregated stats for all tools
        total_executions = sum(stats["executions"] for stats in self._tool_stats.values())
        total_duration = sum(stats["total_duration_ms"] for stats in self._tool_stats.values())
        total_success = sum(stats["success_count"] for stats in self._tool_stats.values())
        total_errors = sum(stats["error_count"] for stats in self._tool_stats.values())
        
        return {
            "total_executions": total_executions,
            "total_duration_ms": total_duration,
            "average_duration_ms": total_duration / total_executions if total_executions > 0 else 0.0,
            "success_rate": total_success / total_executions if total_executions > 0 else 0.0,
            "error_rate": total_errors / total_executions if total_executions > 0 else 0.0,
            "tools": dict(self._tool_stats),
            "most_used_tools": self._get_most_used_tools(),
            "fastest_tools": self._get_fastest_tools(),
            "slowest_tools": self._get_slowest_tools()
        }
    
    def get_tool_categories(self) -> List[str]:
        """Get list of all tool categories"""
        categories = set()
        for tool in self._tools.values():
            categories.add(tool.category)
        return sorted(list(categories))
    
    def search_tools(self, query: str) -> List[Tool]:
        """Search tools by name or description"""
        query_lower = query.lower()
        matching_tools = []
        
        for tool in self._tools.values():
            if (query_lower in tool.name.lower() or 
                query_lower in tool.description.lower()):
                matching_tools.append(tool)
        
        return matching_tools
    
    def validate_tool_call(self, tool_call: ToolCall) -> Dict[str, Any]:
        """Validate a tool call and return validation result"""
        tool = self.get_tool(tool_call.tool)
        
        if not tool:
            return {
                "valid": False,
                "error": f"Unknown tool: {tool_call.tool}",
                "suggestions": self._suggest_similar_tools(tool_call.tool)
            }
        
        if not validate_tool_arguments(tool_call.tool, tool_call.arguments):
            return {
                "valid": False,
                "error": f"Invalid arguments for tool: {tool_call.tool}",
                "expected_parameters": [param.model_dump() for param in tool.parameters]
            }
        
        return {"valid": True}
    
    def _update_tool_stats(self, tool_name: str, duration_ms: float, success: bool) -> None:
        """Update tool execution statistics"""
        if tool_name not in self._tool_stats:
            return
        
        stats = self._tool_stats[tool_name]
        stats["executions"] += 1
        stats["total_duration_ms"] += duration_ms
        stats["last_executed"] = datetime.utcnow().isoformat()
        
        if success:
            stats["success_count"] += 1
        else:
            stats["error_count"] += 1
        
        # Update average duration
        stats["average_duration_ms"] = stats["total_duration_ms"] / stats["executions"]
    
    def _get_most_used_tools(self, limit: int = 5) -> List[Dict[str, Any]]:
        """Get most frequently used tools"""
        sorted_tools = sorted(
            self._tool_stats.items(),
            key=lambda x: x[1]["executions"],
            reverse=True
        )
        
        return [
            {"tool": tool_name, "executions": stats["executions"]}
            for tool_name, stats in sorted_tools[:limit]
        ]
    
    def _get_fastest_tools(self, limit: int = 5) -> List[Dict[str, Any]]:
        """Get fastest executing tools"""
        tools_with_executions = [
            (tool_name, stats) for tool_name, stats in self._tool_stats.items()
            if stats["executions"] > 0
        ]
        
        sorted_tools = sorted(
            tools_with_executions,
            key=lambda x: x[1]["average_duration_ms"]
        )
        
        return [
            {"tool": tool_name, "average_duration_ms": stats["average_duration_ms"]}
            for tool_name, stats in sorted_tools[:limit]
        ]
    
    def _get_slowest_tools(self, limit: int = 5) -> List[Dict[str, Any]]:
        """Get slowest executing tools"""
        tools_with_executions = [
            (tool_name, stats) for tool_name, stats in self._tool_stats.items()
            if stats["executions"] > 0
        ]
        
        sorted_tools = sorted(
            tools_with_executions,
            key=lambda x: x[1]["average_duration_ms"],
            reverse=True
        )
        
        return [
            {"tool": tool_name, "average_duration_ms": stats["average_duration_ms"]}
            for tool_name, stats in sorted_tools[:limit]
        ]
    
    def _suggest_similar_tools(self, tool_name: str) -> List[str]:
        """Suggest similar tool names using simple string similarity"""
        suggestions = []
        tool_name_lower = tool_name.lower()
        
        for existing_tool in self._tools.keys():
            # Simple similarity check
            if (any(word in existing_tool.lower() for word in tool_name_lower.split('_')) or
                any(word in tool_name_lower for word in existing_tool.lower().split('_'))):
                suggestions.append(existing_tool)
        
        return suggestions[:3]  # Return top 3 suggestions
    
    async def health_check(self) -> Dict[str, Any]:
        """Check tool registry health"""
        return {
            "status": "healthy",
            "registered_tools": len(self._tools),
            "enabled_tools": len([t for t in self._tools.keys() if t in self.settings.mcp_tools_enabled]),
            "categories": len(self.get_tool_categories()),
            "total_executions": sum(stats["executions"] for stats in self._tool_stats.values())
        }