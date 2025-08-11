# PyAirtable Integration Test Makefile

.PHONY: test test-auth test-api test-health test-smoke test-install test-quick help

# Default target
help:
	@echo "PyAirtable Integration Test Commands:"
	@echo "  make test          - Run all integration tests"
	@echo "  make test-quick    - Run core functionality smoke test"  
	@echo "  make test-auth     - Run authentication tests only"
	@echo "  make test-api      - Run API gateway tests only"
	@echo "  make test-health   - Run health check tests only"
	@echo "  make test-smoke    - Run smoke tests only"
	@echo "  make test-install  - Install test dependencies"
	@echo "  make test-clean    - Clean test results"

# Install test dependencies
test-install:
	pip install -r tests/requirements.txt

# Run all integration tests
test:
	python run_integration_tests.py

# Quick smoke test for core functionality
test-quick:
	pytest tests/integration/test_sprint1_core_functionality.py::TestSprint1CoreFunctionality::test_sprint1_smoke_test -v -s

# Run authentication tests
test-auth:
	python run_integration_tests.py --markers "auth"

# Run API gateway tests
test-api:
	python run_integration_tests.py --markers "api_gateway"

# Run health check tests
test-health:
	python run_integration_tests.py --markers "health"

# Run smoke tests
test-smoke:
	python run_integration_tests.py --markers "smoke"

# Run tests without service availability check
test-offline:
	python run_integration_tests.py --skip-service-check

# Run specific test pattern
test-pattern:
	@read -p "Enter test pattern: " pattern; \
	python run_integration_tests.py --pattern "$$pattern"

# Clean test results
test-clean:
	rm -rf test_results/
	rm -rf tests/__pycache__/
	rm -rf tests/integration/__pycache__/
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} +

# Run tests with coverage
test-coverage:
	pytest tests/integration/ --cov=. --cov-report=html:test_results/coverage --cov-report=term-missing

# Debug mode - verbose output with no capture
test-debug:
	pytest tests/integration/ -v -s --tb=long

# Check service health before tests
check-services:
	@echo "Checking service health..."
	@curl -f http://localhost:8000/api/health 2>/dev/null && echo "✅ API Gateway: Running" || echo "❌ API Gateway: Not accessible"
	@curl -f http://localhost:8007/health 2>/dev/null && echo "✅ Platform Services: Running" || echo "❌ Platform Services: Not accessible"
	@curl -f http://localhost:8002/health 2>/dev/null && echo "✅ Airtable Gateway: Running" || echo "❌ Airtable Gateway: Not accessible"  
	@curl -f http://localhost:8001/health 2>/dev/null && echo "✅ AI Processing: Running" || echo "❌ AI Processing: Not accessible"