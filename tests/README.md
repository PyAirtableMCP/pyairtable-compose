# PyAirtable Integration Tests - Sprint 1

This directory contains comprehensive integration tests for the PyAirtable microservices architecture, focusing on Sprint 1 functionality validation.

## Test Structure

### Core Test Files

- **`test_auth_flow.py`** - Complete authentication flow testing
  - User registration and login
  - JWT token validation and refresh
  - Session management
  - Cross-service authentication

- **`test_api_gateway_routing.py`** - API Gateway functionality
  - Request routing to backend services
  - CORS configuration
  - Error handling and rate limiting
  - Header forwarding

- **`test_frontend_backend_communication.py`** - Frontend integration
  - API response formatting
  - Session management
  - Error handling for frontend consumption
  - File upload support

- **`test_ai_chat_integration.py`** - AI chat functionality
  - Chat endpoint availability
  - Message processing
  - Session context management
  - Airtable data integration

- **`test_health_endpoints.py`** - Service health monitoring
  - Health endpoint verification
  - Dependency checks
  - Performance monitoring
  - Service discovery

- **`test_sprint1_core_functionality.py`** - Smoke tests
  - Critical functionality validation
  - Service accessibility
  - Basic error handling

## Service Architecture

The tests validate integration between these services:

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Frontend      │───▶│ API Gateway  │───▶│ Platform Services│
│   (Next.js)     │    │   (Port 8000)│    │   (Port 8007)   │
│   Port 3000     │    └──────────────┘    └─────────────────┘
└─────────────────┘           │                      │
                              │                      │ Auth/Users
                              ▼                      │
                    ┌──────────────────┐             │
                    │ Airtable Gateway │◀────────────┘
                    │   (Port 8002)    │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │ AI Processing    │
                    │   (Port 8001)    │
                    └──────────────────┘
```

## Running Tests

### Prerequisites

1. Install Python dependencies:
```bash
pip install -r tests/requirements.txt
```

2. Ensure services are running:
```bash
docker-compose up -d
# or
./start-all-services.sh
```

### Run All Tests
```bash
python run_integration_tests.py
```

### Run Specific Test Categories
```bash
# Authentication tests only
python run_integration_tests.py --markers "auth"

# Health check tests only  
python run_integration_tests.py --markers "health"

# Smoke tests only
python run_integration_tests.py --markers "smoke"

# Skip slow tests
python run_integration_tests.py --markers "not slow"
```

### Run Specific Test Files
```bash
# Core functionality smoke test
pytest tests/integration/test_sprint1_core_functionality.py -v

# Authentication flow tests
pytest tests/integration/test_auth_flow.py -v

# API Gateway tests
pytest tests/integration/test_api_gateway_routing.py -v
```

### Debug Mode
```bash
# Run with detailed output and no capture
pytest tests/integration/ -v -s --tb=long
```

## Test Configuration

### Environment Variables
- `API_GATEWAY_URL` - API Gateway URL (default: http://localhost:8000)
- `PLATFORM_SERVICES_URL` - Platform Services URL (default: http://localhost:8007)
- `AIRTABLE_GATEWAY_URL` - Airtable Gateway URL (default: http://localhost:8002)
- `AI_PROCESSING_URL` - AI Processing Service URL (default: http://localhost:8001)
- `FRONTEND_URL` - Frontend URL (default: http://localhost:5173)

### Test Markers

Tests are organized with pytest markers:

- `@pytest.mark.integration` - All integration tests
- `@pytest.mark.auth` - Authentication-related tests
- `@pytest.mark.api_gateway` - API Gateway functionality tests
- `@pytest.mark.frontend` - Frontend communication tests
- `@pytest.mark.ai_chat` - AI chat functionality tests
- `@pytest.mark.health` - Health check tests
- `@pytest.mark.smoke` - Smoke tests for core functionality
- `@pytest.mark.slow` - Tests that take >5 seconds

## Test Reports

Tests generate comprehensive reports:

- **HTML Report** - `test_results/integration_test_report_TIMESTAMP.html`
- **JSON Results** - `test_results/test_results_TIMESTAMP.json`
- **Coverage Report** - `test_results/coverage_TIMESTAMP/` (if coverage installed)
- **Summary** - `test_results/test_summary_TIMESTAMP.txt`

## Expected Test Scenarios

### Authentication Flow
1. ✅ User registration with validation
2. ✅ User login with JWT token generation
3. ✅ JWT token validation across services
4. ✅ Token refresh mechanism
5. ✅ Logout and token invalidation
6. ✅ Invalid credential handling
7. ✅ Duplicate registration prevention

### API Gateway Routing
1. ✅ Health endpoint accessibility
2. ✅ Authentication service routing
3. ✅ CORS header management
4. ✅ Request forwarding to backend services
5. ✅ Error handling for invalid routes
6. ✅ Header forwarding between services
7. ✅ Rate limiting (if configured)

### Frontend-Backend Communication
1. ✅ API response format consistency
2. ✅ Session management
3. ✅ Error message formatting
4. ✅ CORS configuration for frontend requests
5. ✅ Pagination format (if applicable)
6. ✅ File upload support (if implemented)

### AI Chat Integration
1. ✅ Chat endpoint authentication
2. ✅ Message processing and response generation
3. ✅ Conversation session management
4. ✅ Airtable data integration
5. ✅ Error handling for AI service failures
6. ✅ Performance characteristics
7. ✅ Concurrent request handling

### Health Monitoring
1. ✅ All service health endpoints respond
2. ✅ Health check performance (<2s response time)
3. ✅ Dependency status reporting
4. ✅ Consistent health response format
5. ✅ Service identification in health responses

## Troubleshooting

### Common Issues

**Services Not Running**
```
❌ API Gateway: Not accessible
```
- Solution: Start services with `docker-compose up -d`

**Authentication Tests Failing**
```
pytest.skip: Registration failed: 400
```
- Check Platform Services is running on port 8007
- Verify database and Redis connectivity

**Timeout Errors**
```
httpx.TimeoutException
```
- Increase timeout in test configuration
- Check service performance and resource usage

**Import Errors**
```
ImportError: No module named 'httpx'
```
- Install requirements: `pip install -r tests/requirements.txt`

### Service Status Check
```bash
# Quick service health check
curl http://localhost:8000/api/health     # API Gateway
curl http://localhost:8007/health         # Platform Services  
curl http://localhost:8002/health         # Airtable Gateway
curl http://localhost:8001/health         # AI Processing
```

## Contributing

When adding new tests:

1. Follow existing naming conventions
2. Add appropriate pytest markers
3. Include docstrings explaining test purpose
4. Handle service unavailability gracefully with `pytest.skip()`
5. Use fixtures for common setup
6. Keep tests focused and fast (<100 lines per test file)

## Sprint 1 Success Criteria

For Sprint 1 to be considered complete, these integration tests should pass:

- ✅ Authentication flow works end-to-end
- ✅ API Gateway routes requests correctly
- ✅ JWT tokens are validated across services
- ✅ Frontend can communicate with backend
- ✅ Health endpoints report service status
- ✅ Basic error handling functions properly

Run the smoke test for quick validation:
```bash
pytest tests/integration/test_sprint1_core_functionality.py::TestSprint1CoreFunctionality::test_sprint1_smoke_test -v
```