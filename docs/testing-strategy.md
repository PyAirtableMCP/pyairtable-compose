# Testing Strategy for PyAirtable Microservices

## Overview

This document outlines the comprehensive testing strategy for the PyAirtable microservices architecture, implementing a test pyramid approach with emphasis on automation, security, and reliability.

## Test Pyramid Architecture

```
                    /\
                   /  \
                  /    \
                 / E2E  \
                /       \
               /         \
              /           \
             /_____________\
            /               \
           /   Integration   \
          /                 \
         /                   \
        /____________________\
       /                      \
      /        Unit Tests      \
     /                        \
    /________________________\
```

## 1. Unit Tests (Foundation Layer)

### Coverage Requirements
- **Target Coverage**: 80% minimum per service
- **Critical Path Coverage**: 95% minimum
- **Test Types**: Function tests, class tests, module tests

### Implementation by Service

#### Frontend (Next.js)
```json
{
  "scripts": {
    "test": "jest --coverage",
    "test:watch": "jest --watch",
    "test:ci": "jest --coverage --ci --watchAll=false"
  },
  "jest": {
    "testEnvironment": "jsdom",
    "setupFilesAfterEnv": ["<rootDir>/jest.setup.js"],
    "collectCoverageFrom": [
      "components/**/*.{js,jsx,ts,tsx}",
      "pages/**/*.{js,jsx,ts,tsx}",
      "lib/**/*.{js,jsx,ts,tsx}",
      "!**/*.d.ts",
      "!**/node_modules/**"
    ],
    "coverageThreshold": {
      "global": {
        "branches": 70,
        "functions": 80,
        "lines": 80,
        "statements": 80
      }
    }
  }
}
```

#### Backend Services (FastAPI)
```python
# pytest.ini configuration
[tool:pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = 
    --cov=src
    --cov-report=html
    --cov-report=term-missing
    --cov-report=xml
    --cov-fail-under=80
    --strict-markers
    --disable-warnings
markers = 
    unit: Unit tests
    integration: Integration tests
    slow: Slow tests
    database: Tests requiring database
```

### Unit Test Examples

#### API Gateway Unit Tests
```python
# tests/unit/test_routes.py
import pytest
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch
from src.main import app
from src.routes.health import router

client = TestClient(app)

class TestHealthEndpoint:
    def test_health_check_success(self):
        """Test successful health check response"""
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data
        assert "service" in data

    @patch('src.routes.health.check_dependencies')
    def test_health_check_with_dependency_failure(self, mock_check):
        """Test health check with dependency failure"""
        mock_check.return_value = {"database": False, "redis": True}
        response = client.get("/health")
        assert response.status_code == 503
        data = response.json()
        assert data["status"] == "unhealthy"

class TestAPIRouting:
    @patch('src.services.airtable_client.AirtableClient')
    def test_proxy_to_airtable_service(self, mock_client):
        """Test API Gateway proxies correctly to Airtable service"""
        mock_client.return_value.get_records.return_value = {"records": []}
        
        response = client.get("/airtable/records/tblXXX")
        assert response.status_code == 200
        mock_client.return_value.get_records.assert_called_once()
```

#### LLM Orchestrator Unit Tests
```python
# tests/unit/test_llm_service.py
import pytest
from unittest.mock import Mock, AsyncMock, patch
from src.services.llm_service import LLMOrchestrator
from src.models.conversation import ConversationRequest

class TestLLMOrchestrator:
    @pytest.fixture
    def llm_orchestrator(self):
        return LLMOrchestrator()

    @pytest.mark.asyncio
    async def test_process_conversation_success(self, llm_orchestrator):
        """Test successful conversation processing"""
        request = ConversationRequest(
            message="Hello",
            session_id="test-session",
            context={}
        )
        
        with patch.object(llm_orchestrator, '_call_gemini') as mock_gemini:
            mock_gemini.return_value = "Hello! How can I help you?"
            
            result = await llm_orchestrator.process_conversation(request)
            
            assert result.response == "Hello! How can I help you?"
            assert result.session_id == "test-session"
            mock_gemini.assert_called_once()

    @pytest.mark.asyncio
    async def test_process_conversation_with_mcp_tools(self, llm_orchestrator):
        """Test conversation processing with MCP tool usage"""
        request = ConversationRequest(
            message="Get data from Airtable",
            session_id="test-session",
            context={}
        )
        
        with patch.object(llm_orchestrator, '_call_mcp_server') as mock_mcp:
            mock_mcp.return_value = {"records": [{"id": "rec123"}]}
            
            result = await llm_orchestrator.process_conversation(request)
            
            assert "rec123" in result.response
            mock_mcp.assert_called_once()
```

## 2. Integration Tests (Middle Layer)

### Service Integration Tests

#### Database Integration Tests
```python
# tests/integration/test_database.py
import pytest
import asyncpg
from src.database import get_database_connection
from src.models.user import User

class TestDatabaseIntegration:
    @pytest.mark.asyncio
    async def test_user_crud_operations(self, db_connection):
        """Test complete user CRUD operations"""
        # Create
        user_data = {
            "email": "test@example.com",
            "username": "testuser",
            "hashed_password": "hashed_password"
        }
        user = await User.create(db_connection, **user_data)
        assert user.id is not None
        
        # Read
        retrieved_user = await User.get_by_id(db_connection, user.id)
        assert retrieved_user.email == user_data["email"]
        
        # Update
        updated_user = await User.update(
            db_connection, user.id, {"username": "updated_user"}
        )
        assert updated_user.username == "updated_user"
        
        # Delete
        await User.delete(db_connection, user.id)
        deleted_user = await User.get_by_id(db_connection, user.id)
        assert deleted_user is None

    @pytest.mark.asyncio
    async def test_connection_pooling(self):
        """Test database connection pooling works correctly"""
        connections = []
        for _ in range(10):
            conn = await get_database_connection()
            connections.append(conn)
        
        # All connections should be valid
        for conn in connections:
            result = await conn.fetchval("SELECT 1")
            assert result == 1
```

#### Redis Integration Tests
```python
# tests/integration/test_redis.py
import pytest
import redis.asyncio as redis
from src.services.cache_service import CacheService

class TestRedisIntegration:
    @pytest.mark.asyncio
    async def test_cache_operations(self, redis_client):
        """Test Redis caching operations"""
        cache_service = CacheService(redis_client)
        
        # Set and get
        await cache_service.set("test_key", {"data": "test_value"}, ttl=300)
        result = await cache_service.get("test_key")
        assert result["data"] == "test_value"
        
        # Expiration
        await cache_service.set("expire_key", "value", ttl=1)
        await asyncio.sleep(2)
        result = await cache_service.get("expire_key")
        assert result is None

    @pytest.mark.asyncio
    async def test_session_storage(self, redis_client):
        """Test session storage in Redis"""
        session_data = {
            "user_id": "user123",
            "session_id": "session456",
            "created_at": "2024-01-01T00:00:00Z"
        }
        
        await redis_client.hset("session:session456", mapping=session_data)
        stored_data = await redis_client.hgetall("session:session456")
        
        assert stored_data[b"user_id"].decode() == "user123"
```

### Service-to-Service Integration Tests
```python
# tests/integration/test_service_communication.py
import pytest
import httpx
from unittest.mock import patch

class TestServiceCommunication:
    @pytest.mark.asyncio
    async def test_api_gateway_to_airtable_gateway(self):
        """Test API Gateway communicates correctly with Airtable Gateway"""
        async with httpx.AsyncClient() as client:
            # Mock Airtable Gateway response
            with patch('httpx.AsyncClient.get') as mock_get:
                mock_get.return_value.status_code = 200
                mock_get.return_value.json.return_value = {
                    "records": [{"id": "rec123", "fields": {"name": "test"}}]
                }
                
                # Call API Gateway endpoint that proxies to Airtable Gateway
                response = await client.get(
                    "http://api-gateway:8000/airtable/records",
                    headers={"Authorization": "Bearer test-token"}
                )
                
                assert response.status_code == 200
                data = response.json()
                assert len(data["records"]) == 1

    @pytest.mark.asyncio
    async def test_llm_orchestrator_to_mcp_server(self):
        """Test LLM Orchestrator communicates with MCP Server"""
        async with httpx.AsyncClient() as client:
            # Test MCP Server call from LLM Orchestrator
            with patch('httpx.AsyncClient.post') as mock_post:
                mock_post.return_value.status_code = 200
                mock_post.return_value.json.return_value = {
                    "result": {"data": "mcp_response"}
                }
                
                response = await client.post(
                    "http://llm-orchestrator:8003/chat",
                    json={
                        "message": "Use MCP to get data",
                        "session_id": "test-session"
                    }
                )
                
                assert response.status_code == 200
                mock_post.assert_called_once()
```

## 3. End-to-End Tests (Top Layer)

### User Journey Tests
```python
# tests/e2e/test_user_journeys.py
import pytest
from playwright.async_api import async_playwright

class TestUserJourneys:
    @pytest.mark.asyncio
    async def test_complete_user_workflow(self):
        """Test complete user workflow from login to data interaction"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            page = await browser.new_page()
            
            # Navigate to application
            await page.goto("http://frontend:3000")
            
            # Login
            await page.fill('[data-testid="email-input"]', "test@example.com")
            await page.fill('[data-testid="password-input"]', "password123")
            await page.click('[data-testid="login-button"]')
            
            # Wait for dashboard
            await page.wait_for_selector('[data-testid="dashboard"]')
            
            # Interact with Airtable data
            await page.click('[data-testid="airtable-tab"]')
            await page.wait_for_selector('[data-testid="records-table"]')
            
            # Verify data loaded
            records = await page.query_selector_all('[data-testid="record-row"]')
            assert len(records) > 0
            
            # Test LLM interaction
            await page.click('[data-testid="chat-tab"]')
            await page.fill('[data-testid="chat-input"]', "Get me data from Airtable")
            await page.click('[data-testid="send-button"]')
            
            # Wait for response
            await page.wait_for_selector('[data-testid="chat-response"]')
            response = await page.text_content('[data-testid="chat-response"]')
            assert "data" in response.lower()
            
            await browser.close()

    @pytest.mark.asyncio
    async def test_file_upload_workflow(self):
        """Test file upload and processing workflow"""
        async with async_playwright() as p:
            browser = await p.chromium.launch()
            page = await browser.new_page()
            
            await page.goto("http://frontend:3000/automation")
            
            # Upload file
            await page.set_input_files(
                '[data-testid="file-input"]', 
                "tests/fixtures/test-document.pdf"
            )
            
            # Start processing
            await page.click('[data-testid="process-button"]')
            
            # Wait for processing completion
            await page.wait_for_selector(
                '[data-testid="processing-complete"]',
                timeout=30000
            )
            
            # Verify results
            results = await page.text_content('[data-testid="processing-results"]')
            assert "processed successfully" in results.lower()
            
            await browser.close()
```

## 4. Contract Tests

### API Contract Tests
```python
# tests/contract/test_api_contracts.py
import pytest
import pact
from pact import Consumer, Provider

class TestAPIContracts:
    def test_airtable_gateway_contract(self):
        """Test contract between API Gateway and Airtable Gateway"""
        pact = Consumer('APIGateway').has_pact_with(Provider('AirtableGateway'))
        
        # Define expected interaction
        pact.given('records exist in Airtable').upon_receiving(
            'a request for records'
        ).with_request(
            method='GET',
            path='/records',
            headers={'Authorization': 'Bearer token'}
        ).will_respond_with(
            status=200,
            headers={'Content-Type': 'application/json'},
            body={
                'records': pact.each_like({
                    'id': pact.like('rec123'),
                    'fields': pact.like({'name': 'test'})
                })
            }
        )
        
        # Run the test
        with pact:
            # Make actual request and verify
            pass

    def test_mcp_server_contract(self):
        """Test contract between LLM Orchestrator and MCP Server"""
        pact = Consumer('LLMOrchestrator').has_pact_with(Provider('MCPServer'))
        
        pact.given('MCP server is running').upon_receiving(
            'a tool execution request'
        ).with_request(
            method='POST',
            path='/execute',
            headers={'Content-Type': 'application/json'},
            body={
                'tool': pact.like('airtable_get_records'),
                'params': pact.like({'table_id': 'tbl123'})
            }
        ).will_respond_with(
            status=200,
            body={
                'result': pact.like({'records': []}),
                'success': True
            }
        )
```

## 5. Performance Tests

### Load Testing
```python
# tests/performance/test_load.py
import asyncio
import aiohttp
import time
from concurrent.futures import ThreadPoolExecutor

class TestLoadPerformance:
    async def test_api_gateway_load(self):
        """Test API Gateway under load"""
        async def make_request(session):
            async with session.get('http://api-gateway:8000/health') as response:
                return response.status
        
        async with aiohttp.ClientSession() as session:
            # Simulate 100 concurrent requests
            tasks = [make_request(session) for _ in range(100)]
            start_time = time.time()
            results = await asyncio.gather(*tasks)
            end_time = time.time()
            
            # Verify all requests succeeded
            assert all(status == 200 for status in results)
            
            # Verify response time is acceptable (< 5 seconds for 100 requests)
            assert (end_time - start_time) < 5.0

    async def test_llm_orchestrator_concurrent_sessions(self):
        """Test LLM Orchestrator with multiple concurrent sessions"""
        async def chat_session(session, session_id):
            messages = [
                "Hello", 
                "What's the weather?", 
                "Get data from Airtable",
                "Goodbye"
            ]
            
            for message in messages:
                async with session.post(
                    'http://llm-orchestrator:8003/chat',
                    json={
                        'message': message,
                        'session_id': session_id
                    }
                ) as response:
                    assert response.status == 200
        
        async with aiohttp.ClientSession() as session:
            # Run 10 concurrent chat sessions
            tasks = [
                chat_session(session, f"session-{i}") 
                for i in range(10)
            ]
            await asyncio.gather(*tasks)
```

### Stress Testing
```python
# tests/performance/test_stress.py
import locust
from locust import HttpUser, task, between

class APIGatewayUser(HttpUser):
    wait_time = between(1, 3)
    
    def on_start(self):
        """Login before starting tasks"""
        self.client.post("/auth/login", json={
            "email": "test@example.com",
            "password": "password123"
        })
    
    @task(3)
    def get_health(self):
        """Health check endpoint - most frequent"""
        self.client.get("/health")
    
    @task(2)
    def get_airtable_records(self):
        """Get Airtable records"""
        self.client.get("/airtable/records")
    
    @task(1)
    def chat_with_llm(self):
        """Chat with LLM - least frequent but most resource intensive"""
        self.client.post("/llm/chat", json={
            "message": "Hello, how are you?",
            "session_id": "load-test-session"
        })

class LLMOrchestratorUser(HttpUser):
    wait_time = between(2, 5)
    
    @task
    def process_conversation(self):
        self.client.post("/chat", json={
            "message": "Get me some data from Airtable",
            "session_id": f"stress-test-{self.environment.runner.user_count}"
        })
```

## 6. Security Tests

### Authentication & Authorization Tests
```python
# tests/security/test_auth.py
import pytest
import jwt
from fastapi.testclient import TestClient

class TestAuthentication:
    def test_jwt_token_validation(self, client: TestClient):
        """Test JWT token validation"""
        # Test without token
        response = client.get("/protected-endpoint")
        assert response.status_code == 401
        
        # Test with invalid token
        headers = {"Authorization": "Bearer invalid-token"}
        response = client.get("/protected-endpoint", headers=headers)
        assert response.status_code == 401
        
        # Test with valid token
        valid_token = jwt.encode(
            {"user_id": "123", "exp": time.time() + 3600},
            "secret-key",
            algorithm="HS256"
        )
        headers = {"Authorization": f"Bearer {valid_token}"}
        response = client.get("/protected-endpoint", headers=headers)
        assert response.status_code == 200

    def test_api_key_validation(self, client: TestClient):
        """Test API key validation"""
        # Test without API key
        response = client.get("/api/data")
        assert response.status_code == 401
        
        # Test with invalid API key
        headers = {"X-API-Key": "invalid-key"}
        response = client.get("/api/data", headers=headers)
        assert response.status_code == 401
        
        # Test with valid API key
        headers = {"X-API-Key": "valid-api-key"}
        response = client.get("/api/data", headers=headers)
        assert response.status_code == 200
```

### Input Validation Tests
```python
# tests/security/test_input_validation.py
class TestInputValidation:
    def test_sql_injection_prevention(self, client: TestClient):
        """Test SQL injection prevention"""
        malicious_inputs = [
            "'; DROP TABLE users; --",
            "' OR '1'='1",
            "1' UNION SELECT * FROM users --"
        ]
        
        for malicious_input in malicious_inputs:
            response = client.get(f"/users/{malicious_input}")
            # Should return 400 or 404, not 500 (which would indicate SQL error)
            assert response.status_code in [400, 404]

    def test_xss_prevention(self, client: TestClient):
        """Test XSS prevention"""
        xss_payloads = [
            "<script>alert('xss')</script>",
            "javascript:alert('xss')",
            "<img src=x onerror=alert('xss')>"
        ]
        
        for payload in xss_payloads:
            response = client.post("/comments", json={"content": payload})
            if response.status_code == 200:
                # If accepted, verify it's properly escaped
                assert "<script>" not in response.json().get("content", "")
```

## 7. Database Migration Tests

### Migration Testing
```python
# tests/database/test_migrations.py
import pytest
import alembic.config
import alembic.command
from sqlalchemy import create_engine, text

class TestDatabaseMigrations:
    @pytest.fixture
    def clean_database(self):
        """Provide a clean database for migration testing"""
        engine = create_engine("postgresql://test:test@localhost/test_db")
        with engine.connect() as conn:
            # Drop all tables
            conn.execute(text("DROP SCHEMA public CASCADE"))
            conn.execute(text("CREATE SCHEMA public"))
            conn.commit()
        return engine

    def test_migration_up_and_down(self, clean_database):
        """Test migration up and down"""
        alembic_cfg = alembic.config.Config("alembic.ini")
        
        # Test migration up
        alembic.command.upgrade(alembic_cfg, "head")
        
        # Verify tables exist
        with clean_database.connect() as conn:
            result = conn.execute(text(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = 'public'"
            ))
            tables = [row[0] for row in result]
            assert "users" in tables
            assert "sessions" in tables
        
        # Test migration down
        alembic.command.downgrade(alembic_cfg, "base")
        
        # Verify tables are gone
        with clean_database.connect() as conn:
            result = conn.execute(text(
                "SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = 'public'"
            ))
            tables = [row[0] for row in result]
            assert len(tables) == 0
```

## 8. Test Environment Setup

### Docker Compose for Testing
```yaml
# docker-compose.test.yml
version: '3.8'

services:
  postgres-test:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: test_db
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_password
    ports:
      - "5433:5432"
    volumes:
      - postgres-test-data:/var/lib/postgresql/data

  redis-test:
    image: redis:7-alpine
    ports:
      - "6380:6379"
    command: redis-server --requirepass test_password

  # Test services
  api-gateway-test:
    build:
      context: ../pyairtable-api-gateway
      dockerfile: Dockerfile
    environment:
      - TESTING=true
      - DATABASE_URL=postgresql://test_user:test_password@postgres-test:5432/test_db
      - REDIS_URL=redis://:test_password@redis-test:6379
    depends_on:
      - postgres-test
      - redis-test
    ports:
      - "8001:8000"

volumes:
  postgres-test-data:
```

### Test Configuration
```python
# conftest.py - Pytest configuration
import pytest
import asyncio
import asyncpg
import redis.asyncio as redis
from fastapi.testclient import TestClient

@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture
async def db_connection():
    """Provide a database connection for tests"""
    conn = await asyncpg.connect(
        "postgresql://test_user:test_password@localhost:5433/test_db"
    )
    yield conn
    await conn.close()

@pytest.fixture
async def redis_client():
    """Provide a Redis client for tests"""
    client = redis.Redis.from_url(
        "redis://:test_password@localhost:6380"
    )
    yield client
    await client.close()

@pytest.fixture
def client():
    """Provide a test client"""
    from src.main import app
    return TestClient(app)

@pytest.fixture(autouse=True)
async def clean_database(db_connection):
    """Clean database before each test"""
    await db_connection.execute("TRUNCATE TABLE users, sessions CASCADE")
```

## 9. Continuous Integration Testing

### GitHub Actions Test Configuration
```yaml
# .github/workflows/test.yml (already included in main workflow)
name: Test Suite

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
      
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov pytest-asyncio
      
      - name: Run unit tests
        run: pytest tests/unit/ -v --cov=src --cov-report=xml
      
      - name: Run integration tests
        run: pytest tests/integration/ -v
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test_db
          REDIS_URL: redis://localhost:6379
      
      - name: Upload coverage reports
        uses: codecov/codecov-action@v3
        with:
          file: ./coverage.xml
```

## 10. Test Data Management

### Test Fixtures
```python
# tests/fixtures/data.py
import pytest
from datetime import datetime

@pytest.fixture
def sample_user_data():
    """Sample user data for testing"""
    return {
        "email": "test@example.com",
        "username": "testuser",
        "first_name": "Test",
        "last_name": "User",
        "created_at": datetime.utcnow()
    }

@pytest.fixture
def sample_airtable_records():
    """Sample Airtable records for testing"""
    return {
        "records": [
            {
                "id": "rec123",
                "fields": {
                    "Name": "Test Record 1",
                    "Status": "Active",
                    "Created": "2024-01-01T00:00:00.000Z"
                }
            },
            {
                "id": "rec456", 
                "fields": {
                    "Name": "Test Record 2",
                    "Status": "Inactive",
                    "Created": "2024-01-02T00:00:00.000Z"
                }
            }
        ]
    }

@pytest.fixture
def sample_chat_conversation():
    """Sample chat conversation for testing"""
    return [
        {"role": "user", "content": "Hello"},
        {"role": "assistant", "content": "Hi! How can I help you today?"},
        {"role": "user", "content": "Get data from Airtable"},
        {"role": "assistant", "content": "I'll fetch the data for you."}
    ]
```

## Testing Implementation Timeline

### Week 1: Foundation Setup
- [ ] Set up test infrastructure (Docker Compose, databases)
- [ ] Configure pytest and Jest
- [ ] Implement basic unit tests for each service
- [ ] Set up code coverage reporting

### Week 2: Integration & Contract Tests
- [ ] Implement service-to-service integration tests
- [ ] Set up contract testing with Pact
- [ ] Database integration tests
- [ ] Redis integration tests

### Week 3: E2E & Performance Tests
- [ ] Set up Playwright for E2E testing
- [ ] Implement critical user journey tests
- [ ] Set up Locust for performance testing
- [ ] Basic load testing implementation

### Week 4: Security & Advanced Testing
- [ ] Implement security testing suite  
- [ ] Set up automated security scanning
- [ ] Database migration testing
- [ ] Complete CI/CD integration

This comprehensive testing strategy ensures high-quality, reliable deployments while maintaining fast feedback loops for the development team.