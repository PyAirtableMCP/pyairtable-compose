"""Enhanced Tool Executor for MCP with AI capabilities"""
import time
import httpx
import json
import re
from typing import Any, Dict, Optional, List
from datetime import datetime

from ...models.mcp.tools import ToolCall, ToolExecutionContext
from ...core.config import get_settings
from ...core.logging import get_logger


class ToolExecutor:
    """Enhanced service for executing MCP tools with AI capabilities"""
    
    def __init__(self):
        self.settings = get_settings()
        self.logger = get_logger(__name__)
        self.client = httpx.AsyncClient(timeout=30.0)
    
    async def execute(
        self, 
        tool_call: ToolCall, 
        context: Optional[ToolExecutionContext] = None
    ) -> Any:
        """Execute a tool call with enhanced capabilities"""
        start_time = time.time()
        
        try:
            # Route to appropriate handler based on tool type
            if tool_call.tool.startswith("airtable_"):
                result = await self._execute_airtable_tool(tool_call)
            elif tool_call.tool == "calculate":
                result = await self._execute_calculate(tool_call)
            elif tool_call.tool == "search":
                result = await self._execute_search(tool_call)
            elif tool_call.tool == "query_database":
                result = await self._execute_query(tool_call)
            elif tool_call.tool == "generate_embeddings":
                result = await self._execute_generate_embeddings(tool_call)
            elif tool_call.tool == "semantic_search":
                result = await self._execute_semantic_search(tool_call)
            elif tool_call.tool == "classify_text":
                result = await self._execute_classify_text(tool_call)
            elif tool_call.tool == "summarize_text":
                result = await self._execute_summarize_text(tool_call)
            elif tool_call.tool == "extract_entities":
                result = await self._execute_extract_entities(tool_call)
            else:
                raise ValueError(f"Unknown tool: {tool_call.tool}")
            
            return result
            
        except Exception as e:
            self.logger.error(f"Tool execution failed: {tool_call.tool} - {str(e)}")
            raise
    
    async def _execute_airtable_tool(self, tool_call: ToolCall) -> Any:
        """Execute Airtable-related tools"""
        tool_name = tool_call.tool
        args = tool_call.arguments
        
        # Build URL based on tool
        base_url = self.settings.airtable_gateway_url
        
        if tool_name == "airtable_list_bases":
            url = f"{base_url}/api/v1/airtable/bases"
            response = await self.client.get(url)
            
        elif tool_name == "airtable_get_schema":
            base_id = args["base_id"]
            url = f"{base_url}/api/v1/airtable/bases/{base_id}/schema"
            response = await self.client.get(url)
            
        elif tool_name == "airtable_list_records":
            base_id = args["base_id"]
            table_id = args["table_id"]
            url = f"{base_url}/api/v1/airtable/bases/{base_id}/tables/{table_id}/records"
            
            # Build query params
            params = {}
            if "view" in args:
                params["view"] = args["view"]
            if "max_records" in args:
                params["max_records"] = args["max_records"]
            if "filter_by_formula" in args:
                params["filter_by_formula"] = args["filter_by_formula"]
            if "sort" in args and isinstance(args["sort"], list):
                for i, sort_item in enumerate(args["sort"]):
                    params[f"sort[{i}][field]"] = sort_item.get("field")
                    params[f"sort[{i}][direction]"] = sort_item.get("direction", "asc")
            
            response = await self.client.get(url, params=params)
            
        elif tool_name == "airtable_get_record":
            base_id = args["base_id"]
            table_id = args["table_id"]
            record_id = args["record_id"]
            url = f"{base_url}/api/v1/airtable/bases/{base_id}/tables/{table_id}/records/{record_id}"
            response = await self.client.get(url)
            
        elif tool_name == "airtable_create_records":
            base_id = args["base_id"]
            table_id = args["table_id"]
            url = f"{base_url}/api/v1/airtable/bases/{base_id}/tables/{table_id}/records"
            
            params = {"typecast": args.get("typecast", False)}
            response = await self.client.post(url, json={"records": args["records"]}, params=params)
            
        elif tool_name == "airtable_update_records":
            base_id = args["base_id"]
            table_id = args["table_id"]
            url = f"{base_url}/api/v1/airtable/bases/{base_id}/tables/{table_id}/records"
            
            method = "PUT" if args.get("replace", False) else "PATCH"
            params = {"typecast": args.get("typecast", False)}
            response = await self.client.request(method, url, json={"records": args["records"]}, params=params)
            
        elif tool_name == "airtable_delete_records":
            base_id = args["base_id"]
            table_id = args["table_id"]
            url = f"{base_url}/api/v1/airtable/bases/{base_id}/tables/{table_id}/records"
            
            # Convert record_ids to query params
            params = {}
            for i, record_id in enumerate(args["record_ids"]):
                params[f"records[{i}]"] = record_id
            
            response = await self.client.delete(url, params=params)
            
        else:
            raise ValueError(f"Unknown Airtable tool: {tool_name}")
        
        response.raise_for_status()
        return response.json()
    
    async def _execute_calculate(self, tool_call: ToolCall) -> Any:
        """Execute mathematical calculations with enhanced safety"""
        expression = tool_call.arguments["expression"]
        
        # Enhanced safety check
        allowed_chars = "0123456789+-*/()., abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        allowed_functions = ["abs", "round", "min", "max", "sum", "pow", "sqrt"]
        
        # Basic character validation
        if not all(c in allowed_chars for c in expression):
            raise ValueError("Invalid characters in expression")
        
        # Check for dangerous functions/imports
        dangerous_patterns = [
            r"import\s+", r"exec\s*\(", r"eval\s*\(", r"__.*__", r"open\s*\(",
            r"file\s*\(", r"input\s*\(", r"raw_input\s*\("
        ]
        
        for pattern in dangerous_patterns:
            if re.search(pattern, expression, re.IGNORECASE):
                raise ValueError("Potentially dangerous expression detected")
        
        try:
            # Create safe namespace with limited functions
            safe_namespace = {
                "__builtins__": {},
                "abs": abs,
                "round": round,
                "min": min,
                "max": max,
                "sum": sum,
                "pow": pow,
            }
            
            # Add math functions if available
            try:
                import math
                safe_namespace.update({
                    "sqrt": math.sqrt,
                    "sin": math.sin,
                    "cos": math.cos,
                    "tan": math.tan,
                    "log": math.log,
                    "pi": math.pi,
                    "e": math.e,
                })
            except ImportError:
                pass
            
            # Evaluate the expression
            result = eval(expression, safe_namespace, {})
            
            return {
                "expression": expression,
                "result": result,
                "type": type(result).__name__,
                "timestamp": datetime.utcnow().isoformat()
            }
            
        except Exception as e:
            raise ValueError(f"Calculation error: {str(e)}")
    
    async def _execute_search(self, tool_call: ToolCall) -> Any:
        """Execute enhanced search across Airtable data"""
        query = tool_call.arguments["query"]
        base_id = tool_call.arguments.get("base_id")
        table_id = tool_call.arguments.get("table_id")
        limit = tool_call.arguments.get("limit", 10)
        
        # TODO: Implement actual search functionality
        # This would integrate with a search service or vector database
        
        return {
            "query": query,
            "results": [],
            "total_results": 0,
            "search_time_ms": 0,
            "filters": {
                "base_id": base_id,
                "table_id": table_id
            },
            "limit": limit,
            "message": "Search functionality implementation pending"
        }
    
    async def _execute_query(self, tool_call: ToolCall) -> Any:
        """Execute database query with enhanced safety"""
        query = tool_call.arguments["query"]
        params = tool_call.arguments.get("params", {})
        
        # Basic SQL injection protection
        dangerous_keywords = [
            "DROP", "DELETE", "INSERT", "UPDATE", "ALTER", "CREATE",
            "EXEC", "EXECUTE", "xp_", "sp_", "UNION", "TRUNCATE"
        ]
        
        query_upper = query.upper()
        for keyword in dangerous_keywords:
            if keyword in query_upper:
                raise ValueError(f"Potentially dangerous SQL keyword detected: {keyword}")
        
        # TODO: Implement actual database query execution
        # This would connect to the metadata database and execute read-only queries
        
        return {
            "query": query,
            "params": params,
            "results": [],
            "row_count": 0,
            "execution_time_ms": 0,
            "message": "Database query functionality implementation pending"
        }
    
    async def _execute_generate_embeddings(self, tool_call: ToolCall) -> Any:
        """Generate embeddings using AI models"""
        text = tool_call.arguments["text"]
        model = tool_call.arguments.get("model", "all-MiniLM-L6-v2")
        normalize = tool_call.arguments.get("normalize", True)
        
        try:
            # Get model manager from app state or initialize
            from ...services.models.model_manager import ModelManager
            model_manager = ModelManager()
            
            # Generate embeddings
            embeddings = await model_manager.generate_embeddings(
                texts=[text],
                model_name=model,
                normalize=normalize
            )
            
            return {
                "text": text,
                "model": model,
                "embedding": embeddings[0] if embeddings else [],
                "dimensions": len(embeddings[0]) if embeddings else 0,
                "normalized": normalize
            }
            
        except Exception as e:
            self.logger.error(f"Embedding generation failed: {str(e)}")
            raise ValueError(f"Failed to generate embeddings: {str(e)}")
    
    async def _execute_semantic_search(self, tool_call: ToolCall) -> Any:
        """Perform semantic search using vector embeddings"""
        query = tool_call.arguments["query"]
        collection = tool_call.arguments.get("collection", "default")
        limit = tool_call.arguments.get("limit", 10)
        threshold = tool_call.arguments.get("threshold", 0.7)
        
        # TODO: Implement actual vector search
        # This would integrate with vector databases like Qdrant, Pinecone, etc.
        
        return {
            "query": query,
            "collection": collection,
            "results": [],
            "search_time_ms": 0,
            "threshold": threshold,
            "limit": limit,
            "message": "Semantic search functionality implementation pending"
        }
    
    async def _execute_classify_text(self, tool_call: ToolCall) -> Any:
        """Classify text using AI models"""
        text = tool_call.arguments["text"]
        model = tool_call.arguments.get("model", "distilbert-base-uncased")
        labels = tool_call.arguments.get("labels")
        return_probabilities = tool_call.arguments.get("return_probabilities", True)
        
        try:
            # Get model manager
            from ...services.models.model_manager import ModelManager
            model_manager = ModelManager()
            
            # Perform classification
            result = await model_manager.classify_text(
                text=text,
                model_name=model,
                return_probabilities=return_probabilities
            )
            
            return {
                "text": text,
                "model": model,
                "classification": result,
                "labels": labels
            }
            
        except Exception as e:
            self.logger.error(f"Text classification failed: {str(e)}")
            raise ValueError(f"Failed to classify text: {str(e)}")
    
    async def _execute_summarize_text(self, tool_call: ToolCall) -> Any:
        """Summarize text using AI models"""
        text = tool_call.arguments["text"]
        max_length = tool_call.arguments.get("max_length", 100)
        style = tool_call.arguments.get("style", "concise")
        
        # TODO: Implement text summarization
        # This would use LLM providers or dedicated summarization models
        
        return {
            "text": text,
            "summary": "Text summarization functionality implementation pending",
            "max_length": max_length,
            "style": style,
            "original_length": len(text.split()),
            "summary_length": 0,
            "compression_ratio": 0.0
        }
    
    async def _execute_extract_entities(self, tool_call: ToolCall) -> Any:
        """Extract named entities from text"""
        text = tool_call.arguments["text"]
        entity_types = tool_call.arguments.get("entity_types", ["PERSON", "ORG", "GPE"])
        model = tool_call.arguments.get("model", "en_core_web_sm")
        
        try:
            # TODO: Implement NER using spaCy or similar
            # For now, return placeholder
            
            return {
                "text": text,
                "entities": [],
                "entity_types": entity_types,
                "model": model,
                "message": "Named entity extraction functionality implementation pending"
            }
            
        except Exception as e:
            self.logger.error(f"Entity extraction failed: {str(e)}")
            raise ValueError(f"Failed to extract entities: {str(e)}")
    
    async def close(self) -> None:
        """Close HTTP client"""
        await self.client.aclose()