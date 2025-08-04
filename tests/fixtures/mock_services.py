"""
Mock services for testing PyAirtable components in isolation.
"""

import asyncio
import json
import random
from typing import Dict, Any, List, Optional
from unittest.mock import AsyncMock, MagicMock
from datetime import datetime, timedelta

class MockAirtableService:
    """Mock Airtable service for testing"""
    
    def __init__(self):
        self.records_db = {}
        self.tables_db = {}
        self.call_count = 0
        self.last_request = None
    
    async def get_records(self, table_id: str, **kwargs) -> Dict[str, Any]:
        """Mock get records endpoint"""
        self.call_count += 1
        self.last_request = {
            "method": "GET",
            "table_id": table_id,
            "params": kwargs,
            "timestamp": datetime.utcnow()
        }
        
        # Simulate network delay
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        # Return mock records
        records = self.records_db.get(table_id, [
            {
                "id": f"rec{random.randint(100000, 999999)}",
                "fields": {
                    "Name": f"Mock Record {i}",
                    "Status": random.choice(["Active", "Inactive"]),
                    "Created": datetime.utcnow().isoformat() + "Z"
                },
                "createdTime": datetime.utcnow().isoformat() + "Z"
            }
            for i in range(kwargs.get("maxRecords", 5))
        ])
        
        return {
            "records": records,
            "offset": kwargs.get("offset")
        }
    
    async def create_record(self, table_id: str, fields: Dict[str, Any]) -> Dict[str, Any]:
        """Mock create record endpoint"""
        self.call_count += 1
        self.last_request = {
            "method": "POST",
            "table_id": table_id,
            "fields": fields,
            "timestamp": datetime.utcnow()
        }
        
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        record = {
            "id": f"rec{random.randint(100000, 999999)}",
            "fields": fields,
            "createdTime": datetime.utcnow().isoformat() + "Z"
        }
        
        if table_id not in self.records_db:
            self.records_db[table_id] = []
        self.records_db[table_id].append(record)
        
        return record
    
    async def update_record(self, table_id: str, record_id: str, fields: Dict[str, Any]) -> Dict[str, Any]:
        """Mock update record endpoint"""
        self.call_count += 1
        self.last_request = {
            "method": "PATCH",
            "table_id": table_id,
            "record_id": record_id,
            "fields": fields,
            "timestamp": datetime.utcnow()
        }
        
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        # Find and update record
        if table_id in self.records_db:
            for record in self.records_db[table_id]:
                if record["id"] == record_id:
                    record["fields"].update(fields)
                    return record
        
        # Return new record if not found
        return {
            "id": record_id,
            "fields": fields,
            "createdTime": datetime.utcnow().isoformat() + "Z"
        }
    
    def reset(self):
        """Reset mock state"""
        self.records_db = {}
        self.tables_db = {}
        self.call_count = 0
        self.last_request = None

class MockLLMService:
    """Mock LLM service for testing"""
    
    def __init__(self):
        self.conversation_history = {}
        self.call_count = 0
        self.last_request = None
        self.response_templates = [
            "I understand you'd like help with {topic}. Let me assist you.",
            "Based on your request about {topic}, here's what I can do:",
            "I'll help you with {topic}. Here are the details:",
        ]
    
    async def process_conversation(self, message: str, session_id: str, context: Optional[Dict] = None) -> Dict[str, Any]:
        """Mock conversation processing"""
        self.call_count += 1
        self.last_request = {
            "message": message,
            "session_id": session_id,
            "context": context or {},
            "timestamp": datetime.utcnow()
        }
        
        # Simulate processing time
        await asyncio.sleep(random.uniform(0.5, 1.5))
        
        # Generate mock response
        topic = self._extract_topic(message)
        template = random.choice(self.response_templates)
        response = template.format(topic=topic)
        
        # Store conversation
        if session_id not in self.conversation_history:
            self.conversation_history[session_id] = []
        
        self.conversation_history[session_id].extend([
            {"role": "user", "content": message, "timestamp": datetime.utcnow()},
            {"role": "assistant", "content": response, "timestamp": datetime.utcnow()}
        ])
        
        return {
            "response": response,
            "session_id": session_id,
            "context": context or {},
            "metadata": {
                "model": "mock-gpt-4",
                "tokens_used": len(message) + len(response),
                "response_time": random.uniform(0.5, 1.5)
            }
        }
    
    async def generate_with_tools(self, message: str, available_tools: List[str], session_id: str) -> Dict[str, Any]:
        """Mock tool-assisted generation"""
        self.call_count += 1
        
        await asyncio.sleep(random.uniform(0.3, 0.8))
        
        # Simulate tool usage decision
        if "airtable" in message.lower() and "airtable_get_records" in available_tools:
            tool_calls = [{
                "tool": "airtable_get_records",
                "params": {"table_id": "tblMockTable"},
                "result": {"records": [{"id": "rec123", "fields": {"Name": "Mock Data"}}]}
            }]
            response = f"I found some data in Airtable: {tool_calls[0]['result']}"
        else:
            tool_calls = []
            response = f"I can help you with: {message}. Available tools: {', '.join(available_tools)}"
        
        return {
            "response": response,
            "tool_calls": tool_calls,
            "session_id": session_id,
            "metadata": {
                "model": "mock-gpt-4-tools",
                "tools_used": len(tool_calls)
            }
        }
    
    def _extract_topic(self, message: str) -> str:
        """Extract topic from message for response generation"""
        keywords = ["airtable", "data", "records", "help", "automation", "workflow"]
        for keyword in keywords:
            if keyword in message.lower():
                return keyword
        return "your request"
    
    def reset(self):
        """Reset mock state"""
        self.conversation_history = {}
        self.call_count = 0
        self.last_request = None

class MockMCPServer:
    """Mock MCP (Model Context Protocol) server for testing"""
    
    def __init__(self):
        self.tools = {
            "airtable_get_records": self._mock_airtable_get_records,
            "airtable_create_record": self._mock_airtable_create_record,
            "file_upload": self._mock_file_upload,
            "data_analysis": self._mock_data_analysis
        }
        self.call_count = 0
        self.execution_history = []
    
    async def list_tools(self) -> Dict[str, Any]:
        """Mock list available tools"""
        return {
            "tools": [
                {
                    "name": name,
                    "description": f"Mock implementation of {name}",
                    "parameters": {"type": "object", "properties": {}}
                }
                for name in self.tools.keys()
            ]
        }
    
    async def execute_tool(self, tool_name: str, parameters: Dict[str, Any]) -> Dict[str, Any]:
        """Mock tool execution"""
        self.call_count += 1
        execution = {
            "tool_name": tool_name,
            "parameters": parameters,
            "timestamp": datetime.utcnow(),
            "execution_id": f"exec_{random.randint(100000, 999999)}"
        }
        self.execution_history.append(execution)
        
        await asyncio.sleep(random.uniform(0.2, 0.6))
        
        if tool_name in self.tools:
            result = await self.tools[tool_name](parameters)
            return {
                "success": True,
                "result": result,
                "execution_id": execution["execution_id"]
            }
        else:
            return {
                "success": False,
                "error": f"Tool '{tool_name}' not found",
                "execution_id": execution["execution_id"]
            }
    
    async def _mock_airtable_get_records(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Mock Airtable get records tool"""
        table_id = params.get("table_id", "tblMockTable")
        return {
            "records": [
                {
                    "id": f"rec{i}",
                    "fields": {
                        "Name": f"Record {i}",
                        "Status": random.choice(["Active", "Inactive"]),
                        "Created": datetime.utcnow().isoformat()
                    }
                }
                for i in range(1, 4)
            ],
            "table_id": table_id
        }
    
    async def _mock_airtable_create_record(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Mock Airtable create record tool"""
        return {
            "id": f"rec{random.randint(100000, 999999)}",
            "fields": params.get("fields", {}),
            "created": True
        }
    
    async def _mock_file_upload(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Mock file upload tool"""
        return {
            "file_id": f"file_{random.randint(100000, 999999)}",
            "filename": params.get("filename", "mock_file.txt"),
            "size": random.randint(1024, 1024000),
            "uploaded": True
        }
    
    async def _mock_data_analysis(self, params: Dict[str, Any]) -> Dict[str, Any]:
        """Mock data analysis tool"""
        return {
            "analysis_id": f"analysis_{random.randint(100000, 999999)}",
            "summary": "Mock data analysis completed",
            "insights": [
                "Data trend is positive",
                "Outliers detected: 2",
                "Confidence level: 0.85"
            ],
            "processed_records": random.randint(100, 1000)
        }
    
    def reset(self):
        """Reset mock state"""
        self.call_count = 0
        self.execution_history = []

class MockAuthService:
    """Mock authentication service for testing"""
    
    def __init__(self):
        self.users_db = {}
        self.tokens_db = {}
        self.call_count = 0
        self.last_request = None
    
    async def authenticate(self, email: str, password: str) -> Dict[str, Any]:
        """Mock user authentication"""
        self.call_count += 1
        self.last_request = {
            "method": "authenticate",
            "email": email,
            "timestamp": datetime.utcnow()
        }
        
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        # Mock authentication logic
        if email == "test@example.com" and password == "test_password":
            token = f"mock_token_{random.randint(100000, 999999)}"
            user_id = f"user_{random.randint(1000, 9999)}"
            
            self.tokens_db[token] = {
                "user_id": user_id,
                "email": email,
                "expires_at": datetime.utcnow() + timedelta(hours=1)
            }
            
            return {
                "success": True,
                "access_token": token,
                "token_type": "bearer",
                "expires_in": 3600,
                "user": {
                    "id": user_id,
                    "email": email,
                    "name": "Test User"
                }
            }
        else:
            return {
                "success": False,
                "error": "Invalid credentials"
            }
    
    async def validate_token(self, token: str) -> Dict[str, Any]:
        """Mock token validation"""
        self.call_count += 1
        self.last_request = {
            "method": "validate_token",
            "token": token[:20] + "...",  # Truncate for security
            "timestamp": datetime.utcnow()
        }
        
        await asyncio.sleep(random.uniform(0.05, 0.15))
        
        if token in self.tokens_db:
            token_data = self.tokens_db[token]
            if datetime.utcnow() < token_data["expires_at"]:
                return {
                    "valid": True,
                    "user_id": token_data["user_id"],
                    "email": token_data["email"]
                }
        
        return {"valid": False}
    
    def reset(self):
        """Reset mock state"""
        self.users_db = {}
        self.tokens_db = {}
        self.call_count = 0
        self.last_request = None

class MockEventBus:
    """Mock event bus for testing event-driven architecture"""
    
    def __init__(self):
        self.events = []
        self.subscribers = {}
        self.call_count = 0
    
    async def publish(self, event_type: str, data: Dict[str, Any], metadata: Optional[Dict] = None) -> str:
        """Mock event publishing"""
        self.call_count += 1
        
        event = {
            "id": f"event_{random.randint(100000, 999999)}",
            "type": event_type,
            "data": data,
            "metadata": metadata or {},
            "timestamp": datetime.utcnow(),
            "published": True
        }
        
        self.events.append(event)
        
        # Simulate event delivery to subscribers
        if event_type in self.subscribers:
            for subscriber in self.subscribers[event_type]:
                await subscriber(event)
        
        await asyncio.sleep(random.uniform(0.01, 0.05))
        
        return event["id"]
    
    async def subscribe(self, event_type: str, handler):
        """Mock event subscription"""
        if event_type not in self.subscribers:
            self.subscribers[event_type] = []
        self.subscribers[event_type].append(handler)
    
    def get_events(self, event_type: Optional[str] = None) -> List[Dict[str, Any]]:
        """Get published events"""
        if event_type:
            return [e for e in self.events if e["type"] == event_type]
        return self.events
    
    def reset(self):
        """Reset mock state"""
        self.events = []
        self.subscribers = {}
        self.call_count = 0

# Factory function to create all mock services
def create_mock_services() -> Dict[str, Any]:
    """Create all mock services for testing"""
    return {
        "airtable": MockAirtableService(),
        "llm": MockLLMService(),
        "mcp": MockMCPServer(),
        "auth": MockAuthService(),
        "event_bus": MockEventBus()
    }

# Utility function to reset all mocks
def reset_all_mocks(mocks: Dict[str, Any]):
    """Reset all mock services"""
    for mock_service in mocks.values():
        if hasattr(mock_service, 'reset'):
            mock_service.reset()