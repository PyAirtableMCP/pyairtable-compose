# PyAirtable Deployment Test Suite

## Overview

Comprehensive test automation suite for validating PyAirtable deployment after consolidation and Docker fixes. Designed for practical deployment validation with focus on quick issue identification and customer handoff.

## Quick Start

```bash
# Run all tests
./run-all-tests.sh

# Run smoke tests only
./run-all-tests.sh --smoke-only

# Run with performance tests
./run-all-tests.sh --include-performance

# View help
./run-all-tests.sh --help
```

## Test Structure

```
tests/
├── README.md                          # This file
├── run-all-tests.sh                   # Master test suite runner
├── smoke/                            # Basic functionality tests
│   ├── basic-connectivity.sh         # Port and HTTP connectivity
│   ├── service-health.sh             # Health endpoint validation
│   └── database-connectivity.sh      # Database operations
├── integration/                      # End-to-end integration tests
│   ├── service-communication.sh      # Service-to-service communication
│   └── chat-functionality.sh         # AI chat with Airtable integration
├── performance/                      # Load and performance tests
│   └── load-test.sh                  # Basic concurrent user testing
└── utils/                           # Test utilities and configuration
    ├── test-helpers.sh              # Common test functions
    └── test-config.env              # Test configuration and placeholders
```

## Test Categories

### Smoke Tests (2-3 minutes)
- **Purpose**: Basic service availability and connectivity
- **Prerequisites**: Docker Compose deployment running
- **Coverage**: Port connectivity, health endpoints, database operations

### Integration Tests (3-5 minutes)
- **Purpose**: Service communication and AI functionality validation
- **Prerequisites**: All services healthy
- **Coverage**: API endpoints, service chains, chat functionality

### Performance Tests (2-3 minutes)
- **Purpose**: Basic load testing and resource monitoring
- **Prerequisites**: Stable deployment
- **Coverage**: Concurrent users, response times, resource usage

## Key Features

### ✅ Placeholder Credential Testing
Tests work without real customer credentials, using safe placeholder values that trigger expected responses.

### ✅ Comprehensive Reporting
- Color-coded console output with timestamps
- Individual test result files for each test suite
- Master test summary with pass/fail counts
- JSON and Markdown reports for integration

### ✅ Configurable Execution
- Individual test scripts can be run independently
- Master test suite with multiple execution options
- Quick vs comprehensive test modes
- Stop-on-failure support for rapid debugging

### ✅ Real Credential Integration
Easy transition from placeholder testing to real credential validation when customer provides actual API keys.

## Usage Examples

### Basic Deployment Validation
```bash
# Start deployment
docker-compose -f docker-compose.minimal.yml up -d --build

# Run smoke tests to verify basic functionality
./smoke/basic-connectivity.sh
./smoke/service-health.sh
./smoke/database-connectivity.sh

# Run integration tests
./integration/service-communication.sh
./integration/chat-functionality.sh
```

### Complete Test Suite with Reporting
```bash
# Run all tests with full reporting
./run-all-tests.sh

# View results
ls test-results/
cat test-results/test-execution-report.md
```

### Customer Credential Testing
```bash
# Update .env with real credentials
vim ../.env  # Add real AIRTABLE_TOKEN, AIRTABLE_BASE, GEMINI_API_KEY

# Test with real credentials
./integration/chat-functionality.sh --with-real-creds
```

## Test Results

### Output Locations
- `test-results/` - All test result files
- `test-results/master-test-results.txt` - Summary of all test executions
- `test-results/test-summary.json` - Machine-readable test results
- `test-results/test-execution-report.md` - Executive summary report

### Result Interpretation
- **PASS** ✅ - Test completed successfully
- **FAIL** ❌ - Test failed, requires immediate attention
- **WARN** ⚠️ - Test passed with warnings or minor issues
- **INFO** ℹ️ - Informational message or status update
- **SKIP** ⏭️ - Test skipped due to missing dependencies

## Configuration

### Environment Variables
```bash
# Test timeouts and retries
TEST_TIMEOUT=30                    # Individual test timeout (seconds)
TEST_LONG_TIMEOUT=120             # Long-running test timeout
TEST_RETRY_COUNT=3                # Number of retry attempts

# Performance test parameters
TEST_CONCURRENT_USERS=5           # Concurrent user simulation
TEST_MAX_RESPONSE_TIME=5000       # Max acceptable response time (ms)
TEST_MIN_SUCCESS_RATE=95          # Minimum success rate (%)

# Test credentials (safe placeholders)
TEST_AIRTABLE_TOKEN=pat14.eUy...  # Safe placeholder token
TEST_AIRTABLE_BASE=appTEST123...  # Test base ID
TEST_GEMINI_API_KEY=AIza...       # Test API key
```

### Docker Compose Files
- `docker-compose.minimal.yml` (default) - Core services only
- `docker-compose.yml` - Full service stack with all components
- Custom compose file can be specified with `--compose-file` option

## Troubleshooting

### Common Issues

#### Tests Fail with "Connection Refused"
```bash
# Check if services are running
docker-compose -f docker-compose.minimal.yml ps

# Start services if needed
docker-compose -f docker-compose.minimal.yml up -d --build

# Wait for services to stabilize
sleep 30
```

#### Database Connection Errors
```bash
# Check database container logs
docker-compose -f docker-compose.minimal.yml logs postgres
docker-compose -f docker-compose.minimal.yml logs redis

# Restart database services
docker-compose -f docker-compose.minimal.yml restart postgres redis
```

#### Test Scripts Not Executable
```bash
# Make all test scripts executable
chmod +x run-all-tests.sh
find . -name "*.sh" -exec chmod +x {} \;
```

### Debug Mode
```bash
# Run with verbose bash output
bash -x ./run-all-tests.sh

# Run individual test with debug information
bash -x ./smoke/basic-connectivity.sh --verbose
```

## Integration with Deployment

### Deployment Validation Workflow
1. Deploy services: `docker-compose -f docker-compose.minimal.yml up -d --build`
2. Run smoke tests to verify basic functionality
3. Run integration tests to validate service communication
4. Update `.env` file with customer-provided credentials
5. Run final validation with real credentials
6. Review comprehensive test reports
7. Follow deployment checklist for customer handoff

### CI/CD Integration Example
```yaml
# GitHub Actions integration
- name: Run PyAirtable Deployment Tests
  run: |
    cd pyairtable-compose
    docker-compose -f docker-compose.minimal.yml up -d --build
    sleep 30
    ./tests/run-all-tests.sh --smoke-only
    if [ $? -eq 0 ]; then
      echo "Deployment tests passed"
    else
      echo "Deployment tests failed"
      exit 1
    fi
```

## Documentation Links

### Core Documentation
- `../DEPLOYMENT_TEST_PLAN.md` - Comprehensive test strategy and approach
- `../DEPLOYMENT_VALIDATION_CHECKLIST.md` - Step-by-step validation checklist
- `../CUSTOMER_DEPLOYMENT_GUIDE.md` - Customer deployment instructions
- `../TEST_ENGINEER_SUMMARY.md` - Complete test engineer assessment

### Related Guides
- `../README.md` - Main PyAirtable deployment guide
- `../docker-compose.minimal.yml` - Minimal service configuration
- `../.env.example` - Environment variable template

## Test Development

### Adding New Tests
1. Follow existing patterns in `utils/test-helpers.sh`
2. Use configuration from `utils/test-config.env`
3. Include proper error handling and retry logic
4. Add color-coded output using `print_test_result` function
5. Update this README with new test information

### Test Standards
- All tests must work with placeholder credentials
- Provide clear pass/fail criteria
- Include timeout handling for network operations
- Generate useful error messages for debugging
- Follow modular design for reusability

---

**Test Suite Version**: 1.0  
**Last Updated**: August 4, 2025  
**Compatible With**: PyAirtable post-consolidation deployment  
**Status**: Production ready for customer validation  
**Test Engineer**: Comprehensive deployment validation complete