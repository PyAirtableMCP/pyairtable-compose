# Testing Guide - PyAirtable Compose

This comprehensive guide covers all aspects of testing in the PyAirtable Compose project, including local development, continuous integration, and production testing strategies.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Test Infrastructure](#test-infrastructure)
- [Running Tests Locally](#running-tests-locally)
- [Test Categories](#test-categories)
- [Service-Specific Testing](#service-specific-testing)
- [Coverage Analysis](#coverage-analysis)
- [Pre-commit Hooks](#pre-commit-hooks)
- [CI/CD Testing](#cicd-testing)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Overview

Our testing infrastructure supports multiple languages and frameworks:

- **Python**: pytest, coverage, bandit (security)
- **Go**: go test, gosec (security)
- **JavaScript/TypeScript**: Jest, Playwright, Cypress
- **Integration**: Docker Compose, Testcontainers
- **E2E**: Selenium Grid, Playwright

### Test Pyramid

We follow the test pyramid approach:

```
        /\
       /  \     E2E Tests (Few)
      /____\    
     /      \   Integration Tests (Some)
    /________\  
   /          \ Unit Tests (Many)
  /__________\
```

## Quick Start

### 1. Install Dependencies

```bash
# Python dependencies
pip install pytest pytest-cov pytest-xdist coverage bandit safety

# Go dependencies (if not installed)
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

# Node.js dependencies
npm install -g jest @playwright/test cypress eslint
```

### 2. Set Up Test Environment

```bash
# Clone and navigate to project
cd pyairtable-compose

# Start test infrastructure
docker-compose -f docker-compose.test-enhanced.yml up -d

# Install pre-commit hooks
pre-commit install
```

### 3. Run All Tests

```bash
# Run comprehensive test suite
./test-orchestrator.sh

# Run specific test category
./test-orchestrator.sh --categories unit
./test-orchestrator.sh --categories integration
./test-orchestrator.sh --categories e2e

# Run tests for specific services
./test-orchestrator.sh --services python
./test-orchestrator.sh --services go
./test-orchestrator.sh --services frontend
```

## Test Infrastructure

### Docker Test Environment

Our test infrastructure uses Docker containers for isolation and consistency:

```yaml
# docker-compose.test-enhanced.yml provides:
- PostgreSQL (multiple test databases)
- Redis (caching tests)
- Kafka (event streaming tests)
- MinIO (object storage tests)
- Selenium Grid (browser automation)
- Test runner container (all tools)
```

### Test Databases

We maintain separate databases for different test types:

- `unit_test_db`: Isolated unit tests
- `integration_test_db`: Service integration tests
- `e2e_test_db`: End-to-end test scenarios

### Environment Variables

```bash
# Database connections
export DATABASE_URL="postgresql://test_user:test_password@localhost:5434/test_db"
export REDIS_URL="redis://:test_password@localhost:6381"

# Test configuration
export TEST_ENVIRONMENT=local
export PARALLEL_JOBS=4
export COVERAGE_THRESHOLD=80
```

## Running Tests Locally

### Prerequisites

1. **Docker and Docker Compose**: For test infrastructure
2. **Python 3.11+**: For Python services
3. **Go 1.21+**: For Go services  
4. **Node.js 18+**: For frontend services

### Setting Up Local Environment

```bash
# 1. Start test services
docker-compose -f docker-compose.test-enhanced.yml up -d

# 2. Wait for services to be ready
./scripts/wait-for-services.sh

# 3. Seed test data
docker-compose -f docker-compose.test-enhanced.yml run --rm test-data-seeder

# 4. Verify environment
./test-orchestrator.sh --help
```

### Running Specific Test Types

#### Unit Tests

```bash
# All unit tests
./test-orchestrator.sh --categories unit

# Python unit tests only
cd python-services/llm-orchestrator
python -m pytest tests/unit/ -v --cov=src

# Go unit tests only
cd go-services/auth-service
go test -short -race ./test/unit/...

# Frontend unit tests only
cd frontend-services/tenant-dashboard
npm test -- --coverage --watchAll=false
```

#### Integration Tests

```bash
# All integration tests
./test-orchestrator.sh --categories integration

# With test services running
docker-compose -f docker-compose.test-enhanced.yml --profile integration-tests up -d
./test-orchestrator.sh --categories integration

# Specific service integration
cd python-services/airtable-gateway
python -m pytest tests/integration/ -v
```

#### End-to-End Tests

```bash
# All E2E tests
./test-orchestrator.sh --categories e2e

# With Selenium Grid
docker-compose -f docker-compose.test-enhanced.yml --profile e2e-tests up -d

# Frontend E2E tests
cd frontend-services/tenant-dashboard
npx playwright test
```

### Performance Tests

```bash
# Load testing with Locust
cd tests/performance
locust -f load_test.py --host=http://localhost:8000

# Benchmark tests
cd go-services/api-gateway
go test -bench=. -benchmem ./...

# Artillery.js performance tests
cd frontend-services/tenant-dashboard
npm run test:performance
```

## Test Categories

### 1. Unit Tests

**Purpose**: Test individual functions/methods in isolation

**Characteristics**:
- Fast execution (< 1 second each)
- No external dependencies
- High coverage expected (90%+)

**Examples**:
```python
# Python unit test
def test_user_validation():
    user = User(email="test@example.com")
    assert user.is_valid()

# Go unit test  
func TestUserValidation(t *testing.T) {
    user := User{Email: "test@example.com"}
    assert.True(t, user.IsValid())
}

# JavaScript unit test
test('user validation', () => {
    const user = new User('test@example.com');
    expect(user.isValid()).toBe(true);
});
```

### 2. Integration Tests

**Purpose**: Test interaction between services/components

**Characteristics**:
- Medium execution time (< 30 seconds each)
- Use test databases/external services
- Test API endpoints, database operations

**Examples**:
```python
# Python integration test
@pytest.mark.integration
def test_user_creation_api(test_client, test_db):
    response = test_client.post('/users', json={
        'email': 'test@example.com',
        'name': 'Test User'
    })
    assert response.status_code == 201
    assert test_db.query(User).count() == 1
```

### 3. End-to-End Tests

**Purpose**: Test complete user workflows

**Characteristics**:
- Slow execution (minutes)
- Test full system integration
- Browser automation for frontend

**Examples**:
```javascript
// Playwright E2E test
test('complete user registration flow', async ({ page }) => {
    await page.goto('/register');
    await page.fill('#email', 'test@example.com');
    await page.fill('#password', 'password123');
    await page.click('#submit');
    await expect(page).toHaveURL('/dashboard');
});
```

### 4. Contract Tests

**Purpose**: Ensure API contracts between services

```python
# Pact contract test
@pact.given('User exists')
@pact.upon_receiving('A request for user details')
@pact.with_request('GET', '/users/123')
@pact.will_respond_with(200, body={'id': 123, 'name': 'Test User'})
def test_get_user_contract():
    # Test implementation
```

### 5. Security Tests

**Purpose**: Identify security vulnerabilities

```bash
# Security scanning
bandit -r python-services/
gosec ./go-services/...
npm audit --audit-level moderate
```

## Service-Specific Testing

### Python Services

#### Setup
```bash
cd python-services/service-name
pip install -r requirements-test.txt
export PYTHONPATH="${PYTHONPATH}:$(pwd)/src"
```

#### Running Tests
```bash
# Unit tests with coverage
python -m pytest tests/unit/ --cov=src --cov-report=html

# Integration tests
python -m pytest tests/integration/ -v

# All tests with parallel execution
python -m pytest tests/ -n auto --dist worksteal
```

#### Test Structure
```
python-services/service-name/
├── src/
│   └── service/
├── tests/
│   ├── unit/
│   │   ├── test_models.py
│   │   └── test_services.py
│   ├── integration/
│   │   ├── test_api.py
│   │   └── test_database.py
│   ├── fixtures/
│   │   └── conftest.py
│   └── conftest.py
└── pytest.ini
```

### Go Services

#### Setup
```bash
cd go-services/service-name
go mod download
go mod tidy
```

#### Running Tests
```bash
# Unit tests
go test -short -race ./...

# With coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Benchmarks
go test -bench=. -benchmem ./...
```

#### Test Structure
```
go-services/service-name/
├── cmd/
├── internal/
├── pkg/
├── test/
│   ├── unit/
│   └── integration/
├── tests/
│   ├── fixtures/
│   └── mocks/
└── go.mod
```

### Frontend Services

#### Setup
```bash
cd frontend-services/service-name
npm ci
npx playwright install
```

#### Running Tests
```bash
# Unit tests with Jest
npm test -- --coverage

# E2E tests with Playwright
npx playwright test

# Component tests
npm run test:components

# Visual regression tests
npx playwright test --update-snapshots
```

#### Test Structure
```
frontend-services/service-name/
├── src/
├── tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── __tests__/
├── jest.config.js
└── playwright.config.ts
```

## Coverage Analysis

### Running Coverage Analysis

```bash
# Generate comprehensive coverage report
./coverage-reporter.py

# Language-specific coverage
./coverage-reporter.py --languages python
./coverage-reporter.py --languages go,javascript

# View HTML reports
open coverage/reports/coverage_report_*.html
```

### Coverage Thresholds

- **Global minimum**: 80%
- **Per-service minimum**: 75%
- **Critical modules**: 90%

### Coverage Configuration

```json
{
  "coverage": {
    "python": {
      "thresholds": {
        "global": 80,
        "per_service": 75,
        "critical_modules": 90
      }
    }
  }
}
```

## Pre-commit Hooks

### Installation

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Install hooks for push events
pre-commit install --hook-type pre-push
```

### Available Hooks

1. **Code Quality**:
   - black (Python formatting)
   - isort (import sorting)
   - eslint (JavaScript linting)
   - gofmt (Go formatting)

2. **Security**:
   - bandit (Python security)
   - gosec (Go security)
   - secrets detection
   - dependency vulnerability scanning

3. **Testing**:
   - Unit tests (fast)
   - Coverage checks
   - Security scans

### Running Hooks Manually

```bash
# Run all hooks
pre-commit run --all-files

# Run specific hook
pre-commit run python-unit-tests
pre-commit run security-scan

# Skip hooks for emergency commits
git commit --no-verify -m "Emergency fix"
```

### Hook Configuration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: python-unit-tests
        name: Run Python Unit Tests
        entry: ./scripts/pre-commit-python-tests.sh
        language: system
        files: \.py$
```

## CI/CD Testing

### GitHub Actions Workflow

Our CI/CD pipeline runs comprehensive tests:

```yaml
# .github/workflows/comprehensive-testing.yml
name: Comprehensive Testing Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test-python-services:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [llm-orchestrator, mcp-server, airtable-gateway]
        test_category: [unit, integration]
```

### Test Matrix

The CI pipeline tests:
- **3 Python services** × **2 test categories** = 6 jobs
- **8 Go services** × **2 test categories** = 16 jobs  
- **3 Frontend services** × **2 test categories** = 6 jobs
- **1 E2E integration** job
- **1 Security scanning** job

### Parallel Execution

Tests run in parallel across:
- Multiple GitHub Actions runners
- Multiple test processes per runner (pytest-xdist, go test -parallel)
- Multiple browser instances (Playwright)

### Test Artifacts

CI generates and stores:
- Test result XML/JSON files
- Coverage reports (HTML, XML, JSON)
- Performance test results
- Security scan reports
- Screenshots/videos for E2E tests

## Troubleshooting

### Common Issues

#### 1. Database Connection Errors

```bash
# Check if test database is running
docker-compose -f docker-compose.test-enhanced.yml ps postgres-test

# Reset test database
docker-compose -f docker-compose.test-enhanced.yml restart postgres-test
docker-compose -f docker-compose.test-enhanced.yml run --rm test-data-seeder
```

#### 2. Port Conflicts

```bash
# Check for port conflicts
lsof -i :5434  # PostgreSQL test port
lsof -i :6381  # Redis test port

# Use different ports
export TEST_DATABASE_PORT=5435
export TEST_REDIS_PORT=6382
```

#### 3. Flaky Tests

```bash
# Run test multiple times to identify flaky tests
for i in {1..10}; do ./test-orchestrator.sh --categories unit || echo "Failed on run $i"; done

# Use pytest-rerunfailures for automatic retries
python -m pytest tests/ --reruns 3 --reruns-delay 1
```

#### 4. Memory Issues

```bash
# Increase Docker memory limits
docker system prune -f
docker-compose -f docker-compose.test-enhanced.yml down
docker system df

# Run tests sequentially instead of parallel
./test-orchestrator.sh --parallel-jobs 1
```

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=debug
export PYTEST_ADDOPTS="--log-cli-level=DEBUG --capture=no"

# Run with verbose output
./test-orchestrator.sh --categories unit --verbose

# Debug specific test
cd python-services/llm-orchestrator
python -m pytest tests/unit/test_specific.py::test_function -vvv --pdb
```

### Performance Optimization

```bash
# Profile test execution
python -m pytest tests/ --profile-svg

# Parallel execution tuning
export PARALLEL_JOBS=$(nproc)  # Use all CPU cores
python -m pytest tests/ -n auto --dist worksteal

# Go test optimization  
go test -parallel 8 ./...
```

## Best Practices

### 1. Test Organization

```python
# Good: Descriptive test names
def test_user_registration_with_valid_email_creates_user():
    pass

def test_user_registration_with_invalid_email_returns_400():
    pass

# Bad: Generic test names
def test_user_registration():
    pass
```

### 2. Test Data Management

```python
# Use factories for consistent test data
@pytest.fixture
def user_factory():
    return UserFactory()

def test_user_creation(user_factory):
    user = user_factory.create(email="test@example.com")
    assert user.email == "test@example.com"
```

### 3. Mocking External Services

```python
# Mock external APIs
@patch('requests.get')
def test_external_api_call(mock_get):
    mock_get.return_value.json.return_value = {'status': 'success'}
    result = service.call_external_api()
    assert result['status'] == 'success'
```

### 4. Test Environment Isolation

```python
# Use database transactions for test isolation
@pytest.fixture(autouse=True)
def db_transaction(db):
    transaction = db.begin()
    yield
    transaction.rollback()
```

### 5. Async Test Patterns

```python
# Proper async test handling
@pytest.mark.asyncio
async def test_async_function():
    result = await async_function()
    assert result is not None
```

### 6. Error Testing

```python
# Test error conditions
def test_invalid_input_raises_validation_error():
    with pytest.raises(ValidationError):
        validate_user_input(invalid_input)
```

### 7. Performance Expectations

```python
# Test performance expectations
@pytest.mark.benchmark
def test_function_performance(benchmark):
    result = benchmark(expensive_function)
    assert result is not None
    assert benchmark.stats.stats.mean < 1.0  # Less than 1 second
```

## Monitoring and Metrics

### Test Metrics

Track key testing metrics:
- Test execution time
- Test success/failure rates
- Coverage percentages
- Flaky test frequency
- CI/CD pipeline duration

### Dashboards

Use our coverage dashboard:
```bash
# Generate test metrics dashboard
./coverage-reporter.py --generate-dashboard

# View dashboard
open coverage/dashboard/index.html
```

### Alerts

Set up alerts for:
- Coverage drops below threshold
- Test failures on main branch
- CI/CD pipeline failures
- Security vulnerability detection

---

## Additional Resources

- [PyTest Documentation](https://docs.pytest.org/)
- [Go Testing Package](https://pkg.go.dev/testing)
- [Jest Documentation](https://jestjs.io/docs/getting-started)
- [Playwright Documentation](https://playwright.dev/)
- [Docker Compose Testing](https://docs.docker.com/compose/)

For questions or issues, please create an issue in the repository or contact the development team.