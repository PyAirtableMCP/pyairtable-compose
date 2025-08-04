"""
Test data factories for generating consistent test data across the test suite.
"""

import uuid
import random
import string
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, field
from faker import Faker

fake = Faker()

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