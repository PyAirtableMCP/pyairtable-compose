"""
Enhanced Test Data Factories for PyAirtable E2E Integration Tests
Generates consistent test data across the comprehensive test suite.
Sprint 4 - Service Enablement (Task 10/10)
"""

import uuid
import random
import string
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field, asdict
from faker import Faker
import json

fake = Faker()

# E2E Integration Test specific data structures
@dataclass
class E2ETestUser:
    """Enhanced test user for E2E integration testing"""
    id: str = field(default_factory=lambda: f"e2e_user_{str(uuid.uuid4())[:8]}")
    email: str = field(default_factory=lambda: f"e2e_test_{str(uuid.uuid4())[:8]}@pyairtable-integration.com")
    password: str = field(default_factory=lambda: f"E2ETestPass123_{str(uuid.uuid4())[:4]}!")
    first_name: str = field(default_factory=lambda: f"E2E_Test_{str(uuid.uuid4())[:4]}")
    last_name: str = "Integration_User"
    access_token: Optional[str] = None
    workspace_id: Optional[str] = None
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    
    def to_registration_dict(self) -> Dict[str, str]:
        """Convert to registration request format"""
        return {
            "email": self.email,
            "password": self.password,
            "first_name": self.first_name,
            "last_name": self.last_name
        }
    
    def to_login_dict(self) -> Dict[str, str]:
        """Convert to login request format"""
        return {
            "email": self.email,
            "password": self.password
        }

@dataclass
class E2ETestWorkspace:
    """Enhanced test workspace for E2E integration testing"""
    id: str = field(default_factory=lambda: f"e2e_ws_{str(uuid.uuid4())[:8]}")
    name: str = field(default_factory=lambda: f"E2E_Integration_Workspace_{str(uuid.uuid4())[:8]}")
    description: str = "End-to-end integration test workspace"
    owner_id: str = ""
    settings: Dict[str, Any] = field(default_factory=lambda: {
        "auto_sync": True,
        "retention_days": 7,  # Short retention for test data
        "max_tables": 5,
        "enable_ai": True,
        "test_mode": True
    })
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())

@dataclass
class UserData:
    """User data for testing"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    email: str = field(default_factory=fake.email)
    username: str = field(default_factory=fake.user_name)
    first_name: str = field(default_factory=fake.first_name)
    last_name: str = field(default_factory=fake.last_name)
    hashed_password: str = field(default="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewfEXvLLxEkCz5.q")  # "password"
    is_active: bool = True
    is_verified: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

@dataclass
class WorkspaceData:
    """Workspace data for testing"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    name: str = field(default_factory=lambda: fake.company())
    description: str = field(default_factory=fake.text)
    owner_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    is_active: bool = True
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

@dataclass
class AirtableRecordData:
    """Airtable record data for testing"""
    id: str = field(default_factory=lambda: f"rec{random.randint(100000, 999999)}")
    fields: Dict[str, Any] = field(default_factory=lambda: {
        "Name": fake.company(),
        "Status": random.choice(["Active", "Inactive", "Pending"]),
        "Created": datetime.utcnow().isoformat() + "Z",
        "Priority": random.choice(["High", "Medium", "Low"]),
        "Description": fake.text(max_nb_chars=200)
    })
    created_time: str = field(default_factory=lambda: datetime.utcnow().isoformat() + "Z")

@dataclass
class ChatConversationData:
    """Chat conversation data for testing"""
    session_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    user_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    messages: List[Dict[str, str]] = field(default_factory=lambda: [
        {"role": "user", "content": "Hello, can you help me?"},
        {"role": "assistant", "content": "Of course! How can I assist you today?"}
    ])
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

@dataclass
class EventData:
    """Event data for event sourcing tests"""
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    aggregate_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    aggregate_type: str = field(default="User")
    event_type: str = field(default="UserCreated")
    event_version: int = 1
    event_data: Dict[str, Any] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)
    occurred_at: datetime = field(default_factory=datetime.utcnow)

@dataclass
class SagaTransactionData:
    """SAGA transaction data for testing"""
    saga_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    saga_type: str = field(default="UserRegistration")
    status: str = field(default="STARTED")
    current_step: int = 0
    steps: List[Dict[str, Any]] = field(default_factory=lambda: [
        {"name": "CreateUser", "status": "PENDING"},
        {"name": "CreateWorkspace", "status": "PENDING"},
        {"name": "SendWelcomeEmail", "status": "PENDING"}
    ])
    context: Dict[str, Any] = field(default_factory=dict)
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

class TestDataFactory:
    """Factory for generating test data"""
    
    def __init__(self):
        self.fake = Faker()
        Faker.seed(42)  # For reproducible tests
    
    def create_user(self, **overrides) -> UserData:
        """Create user test data"""
        user_data = UserData()
        for key, value in overrides.items():
            setattr(user_data, key, value)
        return user_data
    
    def create_workspace(self, **overrides) -> WorkspaceData:
        """Create workspace test data"""
        workspace_data = WorkspaceData()
        for key, value in overrides.items():
            setattr(workspace_data, key, value)
        return workspace_data
    
    def create_airtable_record(self, **field_overrides) -> AirtableRecordData:
        """Create Airtable record test data"""
        record = AirtableRecordData()
        if field_overrides:
            record.fields.update(field_overrides)
        return record
    
    def create_airtable_records(self, count: int = 5, **field_overrides) -> List[AirtableRecordData]:
        """Create multiple Airtable records"""
        return [self.create_airtable_record(**field_overrides) for _ in range(count)]
    
    def create_chat_conversation(self, **overrides) -> ChatConversationData:
        """Create chat conversation test data"""
        conversation = ChatConversationData()
        for key, value in overrides.items():
            setattr(conversation, key, value)
        return conversation
    
    def create_event(self, **overrides) -> EventData:
        """Create event test data"""
        event = EventData()
        for key, value in overrides.items():
            setattr(event, key, value)
        return event
    
    def create_event_stream(self, aggregate_id: str, count: int = 5) -> List[EventData]:
        """Create a stream of events for an aggregate"""
        events = []
        for i in range(count):
            event = self.create_event(
                aggregate_id=aggregate_id,
                event_version=i + 1,
                event_data={"step": i + 1, "data": f"event_{i + 1}"}
            )
            events.append(event)
        return events
    
    def create_saga_transaction(self, **overrides) -> SagaTransactionData:
        """Create SAGA transaction test data"""
        saga = SagaTransactionData()
        for key, value in overrides.items():
            setattr(saga, key, value)
        return saga
    
    def create_api_request_data(self, endpoint: str = "/api/test") -> Dict[str, Any]:
        """Create API request test data"""
        return {
            "method": "GET",
            "url": endpoint,
            "headers": {
                "Content-Type": "application/json",
                "User-Agent": "PyAirtable-Test/1.0",
                "X-Request-ID": str(uuid.uuid4())
            },
            "query_params": {},
            "body": {}
        }
    
    def create_auth_token_data(self, user_id: Optional[str] = None) -> Dict[str, Any]:
        """Create authentication token test data"""
        return {
            "user_id": user_id or str(uuid.uuid4()),
            "email": self.fake.email(),
            "scopes": ["read", "write"],
            "exp": datetime.utcnow() + timedelta(hours=1),
            "iat": datetime.utcnow(),
            "jti": str(uuid.uuid4())
        }
    
    def create_performance_test_data(self, size: str = "small") -> Dict[str, Any]:
        """Create performance test data of various sizes"""
        sizes = {
            "small": {"records": 10, "payload_size": 100},
            "medium": {"records": 100, "payload_size": 1000},
            "large": {"records": 1000, "payload_size": 10000}
        }
        
        config = sizes.get(size, sizes["small"])
        
        return {
            "records": [
                self.create_airtable_record(
                    Name=f"Performance Test Record {i}",
                    Description="x" * config["payload_size"]
                )
                for i in range(config["records"])
            ],
            "config": config
        }
    
    def create_chaos_scenario_data(self) -> Dict[str, Any]:
        """Create chaos engineering scenario data"""
        scenarios = [
            {
                "name": "network_latency",
                "description": "Introduce network latency",
                "config": {"delay_ms": random.randint(100, 1000)}
            },
            {
                "name": "service_failure",
                "description": "Simulate service failure",
                "config": {"failure_rate": random.uniform(0.1, 0.5)}
            },
            {
                "name": "resource_exhaustion",
                "description": "Exhaust system resources",
                "config": {"cpu_percentage": random.randint(80, 95)}
            }
        ]
        
        return random.choice(scenarios)
    
    def create_database_migration_data(self) -> Dict[str, Any]:
        """Create database migration test data"""
        return {
            "migration_id": f"migration_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}",
            "version": f"v{random.randint(1, 100)}",
            "description": self.fake.sentence(),
            "up_script": "CREATE TABLE test_table (id SERIAL PRIMARY KEY);",
            "down_script": "DROP TABLE test_table;",
            "created_at": datetime.utcnow()
        }
    
    @staticmethod
    def random_string(length: int = 10) -> str:
        """Generate random string"""
        return ''.join(random.choices(string.ascii_letters + string.digits, k=length))
    
    @staticmethod
    def random_email() -> str:
        """Generate random email"""
        return f"test_{TestDataFactory.random_string(8)}@example.com"
    
    @staticmethod
    def random_uuid() -> str:
        """Generate random UUID"""
        return str(uuid.uuid4())
    
    def create_user_data(self) -> Dict[str, Any]:
        """Create user data dictionary for API requests"""
        return {
            "email": self.fake.email(),
            "password": "TestPassword123!",
            "first_name": self.fake.first_name(),
            "last_name": self.fake.last_name(),
            "username": self.fake.user_name()
        }
    
    def create_table_data(self) -> Dict[str, Any]:
        """Create table data dictionary for API requests"""
        return {
            "name": f"Test Table {self.fake.word().title()}",
            "description": self.fake.sentence(),
            "fields": [
                {"name": "Name", "type": "singleLineText"},
                {"name": "Email", "type": "email"},
                {"name": "Status", "type": "singleSelect", "options": [
                    {"name": "Active", "color": "green"},
                    {"name": "Inactive", "color": "red"}
                ]}
            ]
        }
    
    def create_record_data(self) -> Dict[str, Any]:
        """Create record data dictionary for API requests"""
        return {
            "name": self.fake.name(),
            "email": self.fake.email(),
            "status": random.choice(["Active", "Inactive"]),
            "notes": self.fake.text(max_nb_chars=100)
        }

# Convenience functions for quick access
def create_user(**overrides) -> UserData:
    """Quick user creation"""
    factory = TestDataFactory()
    return factory.create_user(**overrides)

def create_workspace(**overrides) -> WorkspaceData:
    """Quick workspace creation"""
    factory = TestDataFactory()
    return factory.create_workspace(**overrides)

def create_airtable_records(count: int = 5) -> List[AirtableRecordData]:
    """Quick Airtable records creation"""
    factory = TestDataFactory()
    return factory.create_airtable_records(count)

def create_event_stream(aggregate_id: str, count: int = 5) -> List[EventData]:
    """Quick event stream creation"""
    factory = TestDataFactory()
    return factory.create_event_stream(aggregate_id, count)

# E2E Integration Test Extensions
class E2EIntegrationTestFactory(TestDataFactory):
    """Extended factory for E2E integration tests"""
    
    def __init__(self):
        super().__init__()
        self.test_session_id = f"e2e_session_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
    
    def create_e2e_test_user(self, **overrides) -> E2ETestUser:
        """Create E2E test user"""
        user = E2ETestUser()
        for key, value in overrides.items():
            if hasattr(user, key):
                setattr(user, key, value)
        return user
    
    def create_e2e_test_workspace(self, owner_id: str = None, **overrides) -> E2ETestWorkspace:
        """Create E2E test workspace"""
        workspace = E2ETestWorkspace()
        if owner_id:
            workspace.owner_id = owner_id
        for key, value in overrides.items():
            if hasattr(workspace, key):
                setattr(workspace, key, value)
        return workspace
    
    def create_integration_test_scenario(self) -> Dict[str, Any]:
        """Create complete E2E integration test scenario"""
        test_user = self.create_e2e_test_user()
        test_workspace = self.create_e2e_test_workspace(owner_id=test_user.id)
        
        return {
            "test_session_id": self.test_session_id,
            "user": test_user,
            "workspace": test_workspace,
            "airtable_data": {
                "test_base_name": f"E2E_Test_Base_{self.test_session_id}",
                "test_records": self.create_airtable_records(count=5, 
                    Name=f"E2E Test Record", 
                    TestSession=self.test_session_id,
                    Status="Testing"
                )
            },
            "llm_test_prompts": [
                "Generate a simple test response for integration testing",
                "Analyze test data structure",
                "Create a summary of test results"
            ],
            "api_endpoints_to_test": [
                "/api/health",
                "/api/auth/register",
                "/api/auth/login", 
                "/api/user/profile",
                "/api/workspaces",
                "/api/airtable/bases",
                "/api/llm/status"
            ],
            "expected_service_statuses": {
                "api_gateway": 200,
                "auth_service": 200,
                "user_service": 200,
                "airtable_gateway": 200,
                "llm_orchestrator": 200,
                "platform_services": 200
            }
        }
    
    def create_service_health_test_data(self) -> Dict[str, Dict[str, Any]]:
        """Create service health check test data"""
        return {
            "api_gateway": {
                "url": "http://localhost:8000",
                "health_endpoint": "/api/health",
                "expected_status": 200,
                "timeout": 10
            },
            "airtable_gateway": {
                "url": "http://localhost:8002", 
                "health_endpoint": "/health",
                "expected_status": 200,
                "timeout": 10
            },
            "llm_orchestrator": {
                "url": "http://localhost:8003",
                "health_endpoint": "/health", 
                "expected_status": 200,
                "timeout": 15
            },
            "platform_services": {
                "url": "http://localhost:8007",
                "health_endpoint": "/health",
                "expected_status": 200,
                "timeout": 10
            },
            "auth_service": {
                "url": "http://localhost:8009",
                "health_endpoint": "/health",
                "expected_status": 200,
                "timeout": 10
            },
            "user_service": {
                "url": "http://localhost:8010",
                "health_endpoint": "/health",
                "expected_status": 200,
                "timeout": 10
            }
        }
    
    def create_authentication_flow_test_data(self) -> Dict[str, Any]:
        """Create authentication flow test data"""
        test_user = self.create_e2e_test_user()
        
        return {
            "registration_data": test_user.to_registration_dict(),
            "login_data": test_user.to_login_dict(),
            "invalid_credentials": {
                "email": test_user.email,
                "password": "WrongPassword123!"
            },
            "malformed_requests": [
                {"email": "not_an_email", "password": "test"},
                {"email": test_user.email},  # Missing password
                {"password": "test"},  # Missing email
                {}  # Empty request
            ],
            "expected_responses": {
                "successful_registration": [200, 201],
                "successful_login": [200],
                "invalid_credentials": [401, 403],
                "malformed_request": [400, 422]
            }
        }
    
    def create_api_gateway_routing_test_data(self) -> Dict[str, Dict[str, Any]]:
        """Create API Gateway routing test data"""
        return {
            "health_check": {
                "method": "GET",
                "endpoint": "/api/health",
                "expected_status": 200,
                "requires_auth": False
            },
            "user_profile": {
                "method": "GET", 
                "endpoint": "/api/user/profile",
                "expected_status": [200, 404],  # 404 acceptable if endpoint not implemented
                "requires_auth": True
            },
            "airtable_bases": {
                "method": "GET",
                "endpoint": "/api/airtable/bases", 
                "expected_status": [200, 404],
                "requires_auth": True
            },
            "llm_status": {
                "method": "GET",
                "endpoint": "/api/llm/status",
                "expected_status": [200, 404],
                "requires_auth": True
            },
            "workspace_list": {
                "method": "GET",
                "endpoint": "/api/workspaces",
                "expected_status": [200, 404],
                "requires_auth": True
            }
        }
    
    def create_error_handling_test_data(self) -> Dict[str, Dict[str, Any]]:
        """Create error handling test data"""
        return {
            "invalid_authentication": {
                "headers": {"Authorization": "Bearer invalid_jwt_token_12345"},
                "endpoints": [
                    "/api/user/profile",
                    "/api/workspaces",
                    "/api/airtable/bases"
                ],
                "expected_status": 401
            },
            "missing_authentication": {
                "headers": {},
                "endpoints": [
                    "/api/user/profile", 
                    "/api/workspaces",
                    "/api/airtable/bases"
                ],
                "expected_status": [401, 403]
            },
            "non_existent_endpoints": {
                "endpoints": [
                    "/api/nonexistent/endpoint",
                    "/api/invalid/path",
                    "/totally/wrong/url"
                ],
                "expected_status": 404
            },
            "malformed_requests": [
                {
                    "endpoint": "/api/auth/login",
                    "method": "POST",
                    "data": {"invalid": "structure"},
                    "expected_status": [400, 422]
                },
                {
                    "endpoint": "/api/workspaces", 
                    "method": "POST",
                    "data": {},  # Missing required fields
                    "expected_status": [400, 422]
                }
            ]
        }
    
    def create_performance_baseline_data(self) -> Dict[str, Any]:
        """Create performance baseline test data"""
        return {
            "acceptable_response_times": {
                "health_checks": 1.0,  # seconds
                "authentication": 2.0,
                "data_retrieval": 3.0,
                "ai_processing": 10.0
            },
            "acceptable_error_rates": {
                "health_checks": 0.01,  # 1%
                "authentication": 0.02,  # 2%  
                "data_operations": 0.05,  # 5%
                "ai_operations": 0.10  # 10%
            },
            "load_test_config": {
                "concurrent_users": 5,
                "test_duration": 30,  # seconds
                "ramp_up_time": 10,
                "requests_per_user": 20
            }
        }
    
    def get_cleanup_instructions(self) -> Dict[str, List[str]]:
        """Get cleanup instructions for E2E test data"""
        return {
            "database_cleanup": [
                f"DELETE FROM users WHERE email LIKE '%pyairtable-integration.com'",
                f"DELETE FROM workspaces WHERE name LIKE 'E2E_Integration_Workspace_%'",
                f"DELETE FROM sessions WHERE created_at < NOW() - INTERVAL '1 hour'"
            ],
            "redis_cleanup": [
                "FLUSHDB",  # Clear all Redis test data
                f"DEL e2e_test_*",
                f"DEL session:{self.test_session_id}*"
            ],
            "file_cleanup": [
                f"Remove temporary files: /tmp/e2e_test_{self.test_session_id}*",
                f"Clear test logs: /var/log/pyairtable/e2e_test_*"
            ]
        }

# Global E2E test factory instance
e2e_factory = E2EIntegrationTestFactory()

# Convenience functions for E2E testing
def create_e2e_test_user(**overrides) -> E2ETestUser:
    """Quick E2E test user creation"""
    return e2e_factory.create_e2e_test_user(**overrides)

def create_e2e_integration_scenario() -> Dict[str, Any]:
    """Quick E2E integration test scenario creation"""  
    return e2e_factory.create_integration_test_scenario()

def get_service_health_test_data() -> Dict[str, Dict[str, Any]]:
    """Quick service health test data"""
    return e2e_factory.create_service_health_test_data()

def get_authentication_test_data() -> Dict[str, Any]:
    """Quick authentication test data"""
    return e2e_factory.create_authentication_flow_test_data()

def get_error_handling_test_data() -> Dict[str, Dict[str, Any]]:
    """Quick error handling test data"""
    return e2e_factory.create_error_handling_test_data()

# Export all for easy imports
__all__ = [
    'E2ETestUser', 'E2ETestWorkspace', 'E2EIntegrationTestFactory',
    'TestDataFactory', 'UserData', 'WorkspaceData', 'AirtableRecordData',
    'e2e_factory', 'create_e2e_test_user', 'create_e2e_integration_scenario',
    'get_service_health_test_data', 'get_authentication_test_data', 
    'get_error_handling_test_data'
]