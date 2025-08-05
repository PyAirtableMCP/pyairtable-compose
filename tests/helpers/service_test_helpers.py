"""
Service Test Helpers for PyAirtable Test Suite
==============================================

This module provides helper functions for mocking and testing service interactions
across the PyAirtable 6-service architecture.

Services covered:
- Frontend Services: tenant-dashboard, admin-dashboard, auth-frontend
- Go Services: api-gateway, auth-service, platform-services  
- Python Services: llm-orchestrator, mcp-server, airtable-gateway

Helper categories:
- Service Health Mocking
- API Response Mocking
- Inter-service Communication Mocking
- Error Scenario Simulation
- Performance Testing Utilities
"""

import asyncio
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional, Callable
from unittest.mock import AsyncMock, MagicMock
import httpx
from pathlib import Path

logger = logging.getLogger(__name__)

class ServiceTestHelpers:
    """Helper class for service testing and mocking"""
    
    def __init__(self):
        self.mock_responses = {}
        self.mock_routes = {}
        self.performance_metrics = {}
        
    # =========================================================================
    # Service Health and Status Mocking
    # =========================================================================
    
    async def mock_service_health(self, service_name: str, healthy: bool = True, 
                                 additional_data: Dict[str, Any] = None):
        """Mock service health check responses"""
        health_data = {
            'service': service_name,
            'status': 'healthy' if healthy else 'unhealthy',
            'timestamp': datetime.now().isoformat(),
            'version': '1.0.0',
            'uptime': 3600 if healthy else 0
        }
        
        if additional_data:
            health_data.update(additional_data)
        
        if not healthy:
            health_data['errors'] = ['Service unavailable', 'Database connection failed']
        
        self.mock_responses[f"{service_name}_health"] = health_data
        return health_data
    
    async def mock_all_services_healthy(self):
        """Mock all services as healthy"""
        services = [
            'api-gateway', 'auth-service', 'platform-services',
            'llm-orchestrator', 'mcp-server', 'airtable-gateway'
        ]
        
        for service in services:
            await self.mock_service_health(service, healthy=True)
    
    async def mock_service_failure(self, service_name: str, error_type: str = 'connection_error'):
        """Mock specific service failure scenarios"""
        failure_responses = {
            'connection_error': {
                'error': f'{service_name} is unreachable',
                'code': 'CONNECTION_ERROR',
                'timestamp': datetime.now().isoformat()
            },
            'timeout': {
                'error': f'{service_name} request timed out',
                'code': 'TIMEOUT_ERROR',
                'timestamp': datetime.now().isoformat()
            },
            'internal_error': {
                'error': f'{service_name} internal server error',
                'code': 'INTERNAL_ERROR',
                'timestamp': datetime.now().isoformat()
            }
        }
        
        self.mock_responses[f"{service_name}_error"] = failure_responses.get(error_type, failure_responses['internal_error'])
    
    # =========================================================================
    # Airtable Service Mocking
    # =========================================================================
    
    async def mock_airtable_connection_success(self, base_id: str = 'appTEST123456789'):
        """Mock successful Airtable connection"""
        connection_response = {
            'connected': True,
            'baseId': base_id,
            'timestamp': datetime.now().isoformat(),
            'permissions': ['read', 'write'],
            'tableCount': 4
        }
        
        self.mock_responses['airtable_connection'] = connection_response
        return connection_response
    
    async def mock_airtable_auth_failure(self):
        """Mock Airtable authentication failure"""
        auth_failure = {
            'error': 'Invalid API key or base ID',
            'code': 'AIRTABLE_AUTH_ERROR',
            'timestamp': datetime.now().isoformat()
        }
        
        self.mock_responses['airtable_auth_error'] = auth_failure
        return auth_failure
    
    async def mock_airtable_rate_limit(self):
        """Mock Airtable API rate limit response"""
        rate_limit_response = {
            'error': 'Rate limit exceeded. Please try again later.',
            'code': 'RATE_LIMIT_EXCEEDED',
            'retryAfter': 30,
            'timestamp': datetime.now().isoformat()
        }
        
        self.mock_responses['airtable_rate_limit'] = rate_limit_response
        return rate_limit_response
    
    async def mock_airtable_tables_response(self, test_base: Dict[str, Any]):
        """Mock Airtable tables list response"""
        tables_response = {
            'tables': [
                {
                    'id': table['id'],
                    'name': table['name'],
                    'description': f'Test table: {table["name"]}',
                    'fields': table['fields']
                }
                for table in test_base['tables']
            ],
            'baseId': test_base['id'],
            'timestamp': datetime.now().isoformat()
        }
        
        self.mock_responses['airtable_tables'] = tables_response
        return tables_response
    
    async def mock_airtable_records_response(self, test_table: Dict[str, Any]):
        """Mock Airtable records response for a specific table"""
        records_response = {
            'records': test_table['records'],
            'tableId': test_table['id'],
            'tableName': test_table['name'],
            'offset': None,
            'timestamp': datetime.now().isoformat()
        }
        
        self.mock_responses[f'airtable_records_{test_table["name"]}'] = records_response
        return records_response
    
    async def mock_airtable_data_access(self, test_base: Dict[str, Any]):
        """Mock complete Airtable data access for a base"""
        # Mock base metadata
        await self.mock_airtable_connection_success(test_base['id'])
        await self.mock_airtable_tables_response(test_base)
        
        # Mock records for each table
        for table in test_base['tables']:
            await self.mock_airtable_records_response(table)
    
    # =========================================================================
    # AI Service Mocking (LLM Orchestrator)
    # =========================================================================
    
    async def mock_ai_chat_response(self, custom_response: str = None):
        """Mock AI chat response"""
        default_response = {
            'response': custom_response or 'I can help you analyze your Airtable data. What would you like to know?',
            'sessionId': 'mock-session-123',
            'timestamp': datetime.now().isoformat(),
            'model': 'gemini-pro',
            'usage': {
                'promptTokens': 25,
                'completionTokens': 18,
                'totalTokens': 43
            }
        }
        
        self.mock_responses['ai_chat'] = default_response
        return default_response
    
    async def mock_ai_contextual_responses(self):
        """Mock AI responses that maintain conversation context"""
        contextual_responses = {
            'first_response': {
                'response': 'Hello John! I see you have a project management base. I can help you analyze your projects and tasks.',
                'sessionId': 'context-test-session',
                'context': {
                    'userName': 'John',
                    'baseType': 'project_management',
                    'previousMessages': 1
                }
            },
            'second_response': {
                'response': 'Based on your project management base, John, I can see you have 2 active projects with a total budget of $65,000.',
                'sessionId': 'context-test-session', 
                'context': {
                    'userName': 'John',
                    'baseType': 'project_management',
                    'previousMessages': 2,
                    'dataAccessed': True
                }
            }
        }
        
        self.mock_responses['ai_contextual'] = contextual_responses
        return contextual_responses
    
    async def mock_ai_data_analysis_response(self):
        """Mock AI response that includes data analysis"""
        analysis_response = {
            'response': '''Based on your projects data, here's the analysis:

**Total Projects**: 2
**Total Budget**: $65,000
**Average Budget**: $32,500

**Project Breakdown**:
1. Website Redesign - $15,000 (In Progress)
2. Mobile App Development - $50,000 (Planning)

**Recommendations**:
- The Mobile App project represents 77% of your total budget
- Consider breaking down the Mobile App into smaller phases
- Website Redesign is progressing well and under budget''',
            'sessionId': 'analysis-test-session',
            'dataAnalysis': {
                'projectsAnalyzed': 2,
                'totalBudget': 65000,
                'averageBudget': 32500,
                'recommendations': 3
            },
            'timestamp': datetime.now().isoformat()
        }
        
        self.mock_responses['ai_analysis'] = analysis_response
        return analysis_response
    
    async def mock_ai_service_failure(self):
        """Mock AI service failure scenarios"""
        failure_response = {
            'error': 'AI service temporarily unavailable. Please try again in a few moments.',
            'code': 'AI_SERVICE_UNAVAILABLE',
            'timestamp': datetime.now().isoformat(),
            'retryAfter': 60
        }
        
        self.mock_responses['ai_failure'] = failure_response
        return failure_response
    
    # =========================================================================
    # Service Communication Chain Mocking
    # =========================================================================
    
    async def mock_service_chain_communication(self):
        """Mock the complete service communication chain"""
        # API Gateway receives request
        api_gateway_response = {
            'received': True,
            'route': '/api/chat',
            'authenticated': True,
            'forwardedTo': 'llm-orchestrator'
        }
        
        # LLM Orchestrator processes request
        llm_orchestrator_response = {
            'processed': True,
            'intent': 'list_airtable_tables',
            'requestsData': True,
            'forwardedTo': 'mcp-server'
        }
        
        # MCP Server handles MCP protocol
        mcp_server_response = {
            'protocol': 'mcp',
            'operation': 'list_tables',
            'forwardedTo': 'airtable-gateway'
        }
        
        # Airtable Gateway fetches data
        airtable_gateway_response = {
            'connected': True,
            'operation': 'list_tables',
            'tablesFound': 4,
            'tables': ['Projects', 'Tasks', 'Users', 'Facebook Posts']
        }
        
        # Complete chain response
        chain_response = {
            'response': 'I can see your Airtable base has 4 tables: Projects, Tasks, Users, and Facebook Posts. What would you like to know about these tables?',
            'sessionId': 'service-chain-test',
            'serviceChain': {
                'api_gateway': api_gateway_response,
                'llm_orchestrator': llm_orchestrator_response,
                'mcp_server': mcp_server_response,
                'airtable_gateway': airtable_gateway_response
            },
            'timestamp': datetime.now().isoformat()
        }
        
        self.mock_responses['service_chain'] = chain_response
        return chain_response
    
    # =========================================================================
    # Performance Testing Helpers
    # =========================================================================
    
    async def mock_performance_metrics(self, service_name: str, metrics: Dict[str, float] = None):
        """Mock performance metrics for a service"""
        default_metrics = {
            'responseTime': 150.5,  # milliseconds
            'throughput': 250.0,    # requests per second
            'memoryUsage': 512.0,   # MB
            'cpuUsage': 35.5,       # percentage
            'errorRate': 0.02,      # percentage
            'activeConnections': 45
        }
        
        if metrics:
            default_metrics.update(metrics)
        
        performance_data = {
            'service': service_name,
            'metrics': default_metrics,
            'timestamp': datetime.now().isoformat(),
            'measurementPeriod': '1m'
        }
        
        self.performance_metrics[service_name] = performance_data
        return performance_data
    
    async def simulate_load_testing(self, concurrent_users: int = 10, duration: int = 60):
        """Simulate load testing scenario"""
        load_test_results = {
            'testId': f'load_test_{datetime.now().strftime("%Y%m%d_%H%M%S")}',
            'configuration': {
                'concurrentUsers': concurrent_users,
                'duration': duration,
                'rampUpTime': 10
            },
            'results': {
                'totalRequests': concurrent_users * duration,
                'successfulRequests': int(concurrent_users * duration * 0.98),
                'failedRequests': int(concurrent_users * duration * 0.02),
                'averageResponseTime': 185.7,
                'maxResponseTime': 2450.3,
                'minResponseTime': 45.2,
                'throughput': concurrent_users * 0.9,
                'errorRate': 2.0
            },
            'timestamp': datetime.now().isoformat()
        }
        
        self.performance_metrics['load_test'] = load_test_results
        return load_test_results
    
    # =========================================================================
    # Database Testing Helpers
    # =========================================================================
    
    async def mock_database_connection(self, db_type: str = 'postgresql', healthy: bool = True):
        """Mock database connection health"""
        connection_data = {
            'type': db_type,
            'connected': healthy,
            'connectionPool': {
                'active': 5 if healthy else 0,
                'idle': 15 if healthy else 0,
                'max': 20
            },
            'responseTime': 12.5 if healthy else None,
            'lastQuery': datetime.now().isoformat() if healthy else None
        }
        
        if not healthy:
            connection_data['error'] = 'Connection timeout after 30 seconds'
        
        self.mock_responses[f'{db_type}_connection'] = connection_data
        return connection_data
    
    async def mock_redis_connection(self, healthy: bool = True):
        """Mock Redis connection health"""
        redis_data = {
            'connected': healthy,
            'ping': 'PONG' if healthy else None,
            'memory': {
                'used': '2.5MB',
                'peak': '5.1MB'
            } if healthy else None,
            'keyCount': 150 if healthy else 0,
            'responseTime': 2.1 if healthy else None
        }
        
        if not healthy:
            redis_data['error'] = 'Redis server not responding'
        
        self.mock_responses['redis_connection'] = redis_data
        return redis_data
    
    # =========================================================================
    # Security Testing Helpers
    # =========================================================================
    
    async def mock_security_scan_results(self, vulnerabilities_found: int = 0):
        """Mock security scan results"""
        scan_results = {
            'scanId': f'security_scan_{datetime.now().strftime("%Y%m%d_%H%M%S")}',
            'timestamp': datetime.now().isoformat(),
            'vulnerabilities': {
                'critical': 0,
                'high': 0,
                'medium': vulnerabilities_found,
                'low': 0,
                'info': 2
            },
            'scanDuration': 45.3,
            'itemsScanned': 1250,
            'status': 'completed'
        }
        
        if vulnerabilities_found > 0:
            scan_results['details'] = [
                {
                    'type': 'XSS',
                    'severity': 'medium',
                    'location': '/api/chat',
                    'description': 'Potential XSS vulnerability in user input'
                }
            ]
        
        self.mock_responses['security_scan'] = scan_results
        return scan_results
    
    # =========================================================================
    # Utility Functions
    # =========================================================================
    
    def get_mock_response(self, key: str) -> Dict[str, Any]:
        """Get a specific mock response"""
        return self.mock_responses.get(key, {})
    
    def clear_mock_responses(self):
        """Clear all mock responses"""
        self.mock_responses.clear()
        self.performance_metrics.clear()
    
    async def wait_for_service_ready(self, service_url: str, timeout: int = 30) -> bool:
        """Wait for a service to become ready"""
        start_time = datetime.now()
        
        while (datetime.now() - start_time).total_seconds() < timeout:
            try:
                async with httpx.AsyncClient() as client:
                    response = await client.get(f"{service_url}/health", timeout=5.0)
                    if response.status_code == 200:
                        return True
            except:
                pass
            
            await asyncio.sleep(2)
        
        return False
    
    async def validate_service_response_format(self, response: Dict[str, Any], 
                                             expected_fields: List[str]) -> bool:
        """Validate that service response contains expected fields"""
        for field in expected_fields:
            if field not in response:
                logger.error(f"Missing expected field: {field}")
                return False
        return True
    
    def generate_test_summary(self) -> Dict[str, Any]:
        """Generate summary of all mocked services and responses"""
        return {
            'timestamp': datetime.now().isoformat(),
            'mockedServices': list(set(
                key.split('_')[0] for key in self.mock_responses.keys()
            )),
            'mockResponseCount': len(self.mock_responses),
            'performanceMetrics': len(self.performance_metrics),
            'mockResponses': list(self.mock_responses.keys())
        }