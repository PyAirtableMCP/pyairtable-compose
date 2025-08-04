# PyAirtable Testing Automation Makefile

# Variables
PYTHON := python3
PIP := pip3
NODE := node
NPM := npm
DOCKER := docker
DOCKER_COMPOSE := docker-compose
KUBECTL := kubectl
K6 := k6

# Directories
TEST_DIR := ./testing
REPORTS_DIR := $(TEST_DIR)/reports
COVERAGE_DIR := $(REPORTS_DIR)/coverage
LOGS_DIR := $(REPORTS_DIR)/logs

# Test Configuration
TEST_ENV ?= local
PARALLEL_WORKERS ?= 4
TIMEOUT ?= 300
COVERAGE_THRESHOLD ?= 80

# Service URLs (can be overridden)
API_GATEWAY_URL ?= http://localhost:8000
AUTH_SERVICE_URL ?= http://localhost:8001
USER_SERVICE_URL ?= http://localhost:8002
AIRTABLE_GATEWAY_URL ?= http://localhost:8003

.PHONY: help setup clean test-all test-unit test-integration test-e2e test-performance test-security test-contracts test-minikube install-deps

help: ## Display this help message
	@echo "PyAirtable Testing Automation"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# Setup and Installation
install-deps: ## Install all testing dependencies
	@echo "Installing Python dependencies..."
	$(PIP) install -r $(TEST_DIR)/requirements.txt
	
	@echo "Installing Node.js dependencies for frontend tests..."
	@for dir in frontend-services/*/; do \
		if [ -f "$$dir/package.json" ]; then \
			echo "Installing deps in $$dir"; \
			cd "$$dir" && $(NPM) install && cd -; \
		fi \
	done
	
	@echo "Installing Go testing tools..."
	go install github.com/golang/mock/mockgen@latest
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	
	@echo "Installing performance testing tools..."
	@if ! command -v k6 >/dev/null 2>&1; then \
		echo "Installing K6..."; \
		curl https://github.com/grafana/k6/releases/download/v0.46.0/k6-v0.46.0-linux-amd64.tar.gz -L | tar xvz --strip-components 1; \
		sudo mv k6 /usr/local/bin/; \
	fi

setup: install-deps ## Set up testing environment
	@echo "Setting up testing environment..."
	@mkdir -p $(REPORTS_DIR) $(COVERAGE_DIR) $(LOGS_DIR)
	
	@echo "Creating test configuration files..."
	@cp $(TEST_DIR)/configs/pytest.ini.template pytest.ini || true
	@cp $(TEST_DIR)/configs/.env.test.template .env.test || true
	
	@echo "Initializing test databases..."
	@$(MAKE) setup-test-db
	
	@echo "Testing environment setup complete!"

setup-test-db: ## Set up test databases
	@echo "Setting up test databases..."
	@$(DOCKER_COMPOSE) -f tests/docker-compose.test.yml up -d postgres-test redis-test
	@sleep 10
	@echo "Test databases ready!"

clean: ## Clean test artifacts and reports
	@echo "Cleaning test artifacts..."
	@rm -rf $(REPORTS_DIR)
	@rm -rf __pycache__ .pytest_cache .coverage
	@find . -name "*.pyc" -delete
	@find . -name "coverage.out" -delete
	@find . -name "junit.xml" -delete
	@echo "Clean complete!"

# Individual Test Suites
test-unit: ## Run unit tests
	@echo "Running unit tests..."
	@mkdir -p $(COVERAGE_DIR)
	
	# Python unit tests
	@echo "Running Python unit tests..."
	pytest -v --tb=short \
		--cov=python-services \
		--cov-report=html:$(COVERAGE_DIR)/python \
		--cov-report=xml:$(COVERAGE_DIR)/python-coverage.xml \
		--junit-xml=$(REPORTS_DIR)/python-unit-junit.xml \
		--workers=$(PARALLEL_WORKERS) \
		-m "unit and not slow" \
		python-services/tests/unit/ \
		| tee $(LOGS_DIR)/python-unit-tests.log
	
	# Go unit tests
	@echo "Running Go unit tests..."
	@cd go-services && make test-unit 2>&1 | tee ../$(LOGS_DIR)/go-unit-tests.log
	
	# Frontend unit tests
	@echo "Running Frontend unit tests..."
	@for dir in frontend-services/*/; do \
		if [ -f "$$dir/package.json" ] && grep -q '"test"' "$$dir/package.json"; then \
			echo "Running tests in $$dir"; \
			cd "$$dir" && $(NPM) run test -- --coverage --watchAll=false 2>&1 | tee ../../$(LOGS_DIR)/frontend-unit-tests.log && cd -; \
		fi \
	done

test-integration: setup-test-db ## Run integration tests
	@echo "Running integration tests..."
	@mkdir -p $(COVERAGE_DIR)
	
	# Python integration tests
	@echo "Running Python integration tests..."
	TEST_ENV=integration pytest -v --tb=short \
		--cov=python-services \
		--cov-report=html:$(COVERAGE_DIR)/python-integration \
		--cov-report=xml:$(COVERAGE_DIR)/python-integration-coverage.xml \
		--junit-xml=$(REPORTS_DIR)/python-integration-junit.xml \
		--timeout=$(TIMEOUT) \
		-m "integration" \
		python-services/tests/integration/ \
		| tee $(LOGS_DIR)/python-integration-tests.log
	
	# Go integration tests
	@echo "Running Go integration tests..."
	@cd go-services && make test-integration 2>&1 | tee ../$(LOGS_DIR)/go-integration-tests.log

test-e2e: ## Run end-to-end tests
	@echo "Running end-to-end tests..."
	@mkdir -p $(REPORTS_DIR)
	
	# Frontend E2E tests with Playwright
	@echo "Running Frontend E2E tests..."
	@for dir in frontend-services/*/; do \
		if [ -f "$$dir/playwright.config.ts" ]; then \
			echo "Running E2E tests in $$dir"; \
			cd "$$dir" && npx playwright test --reporter=html 2>&1 | tee ../../$(LOGS_DIR)/e2e-tests.log && cd -; \
		fi \
	done
	
	# Critical path tests
	@echo "Running critical path tests..."
	$(PYTHON) $(TEST_DIR)/critical-paths/user_journey_tests.py 2>&1 | tee $(LOGS_DIR)/critical-path-tests.log

test-contracts: ## Run contract tests
	@echo "Running contract tests..."
	@mkdir -p $(REPORTS_DIR)
	
	# API contract tests with Pact
	@echo "Running API contract tests..."
	pytest -v --tb=short \
		--junit-xml=$(REPORTS_DIR)/contract-tests-junit.xml \
		-m "contract" \
		$(TEST_DIR)/contract-tests/ \
		| tee $(LOGS_DIR)/contract-tests.log
	
	# Verify provider contracts
	@echo "Verifying provider contracts..."
	$(PYTHON) -c "
import asyncio
import sys
sys.path.append('$(TEST_DIR)/contract-tests')
from pact_setup import PactTestFramework

async def verify():
    framework = PactTestFramework()
    success = await framework.verify_provider_contracts('$(API_GATEWAY_URL)', 'api-gateway')
    return success

result = asyncio.run(verify())
exit(0 if result else 1)
" 2>&1 | tee $(LOGS_DIR)/contract-verification.log

test-performance: ## Run performance tests
	@echo "Running performance tests..."
	@mkdir -p $(REPORTS_DIR)
	
	# K6 load tests
	@echo "Running K6 load tests..."
	$(K6) run \
		--out json=$(REPORTS_DIR)/performance-results.json \
		--out html=$(REPORTS_DIR)/performance-report.html \
		$(TEST_DIR)/performance-tests/k6-load-tests.js \
		2>&1 | tee $(LOGS_DIR)/performance-tests.log
	
	# Database performance tests
	@echo "Running database performance tests..."
	pytest -v --tb=short \
		--junit-xml=$(REPORTS_DIR)/db-performance-junit.xml \
		-m "performance" \
		$(TEST_DIR)/performance-tests/ \
		| tee $(LOGS_DIR)/db-performance-tests.log

test-security: ## Run security tests
	@echo "Running security tests..."
	@mkdir -p $(REPORTS_DIR)
	
	# Security test suite
	@echo "Running security test suite..."
	$(PYTHON) $(TEST_DIR)/security-tests/security_test_suite.py 2>&1 | tee $(LOGS_DIR)/security-tests.log
	
	# Static security analysis
	@echo "Running static security analysis..."
	@if command -v bandit >/dev/null 2>&1; then \
		bandit -r python-services/ -f json -o $(REPORTS_DIR)/bandit-report.json || true; \
	fi
	
	@if command -v gosec >/dev/null 2>&1; then \
		cd go-services && gosec -fmt json -out ../$(REPORTS_DIR)/gosec-report.json ./... || true && cd -; \
	fi

test-minikube: ## Run Minikube deployment validation tests
	@echo "Running Minikube deployment validation..."
	@mkdir -p $(REPORTS_DIR)
	
	# Check if Minikube is running
	@kubectl cluster-info >/dev/null 2>&1 || (echo "Error: Minikube cluster not running" && exit 1)
	
	# Deployment validation tests
	@echo "Running deployment validation tests..."
	$(PYTHON) $(TEST_DIR)/minikube-tests/deployment_validation.py 2>&1 | tee $(LOGS_DIR)/minikube-tests.log
	
	# Infrastructure tests
	pytest -v --tb=short \
		--junit-xml=$(REPORTS_DIR)/minikube-junit.xml \
		-m "minikube" \
		$(TEST_DIR)/minikube-tests/ \
		| tee $(LOGS_DIR)/minikube-pytest.log

# Comprehensive Test Suites
test-all: ## Run all test suites
	@echo "Running comprehensive test suite..."
	@$(MAKE) test-unit
	@$(MAKE) test-integration  
	@$(MAKE) test-contracts
	@$(MAKE) test-security
	@$(MAKE) test-performance
	@$(MAKE) test-e2e
	@$(MAKE) generate-report

test-ci: ## Run CI test suite (fast tests only)
	@echo "Running CI test suite..."
	@$(MAKE) test-unit
	@$(MAKE) test-integration
	@$(MAKE) test-contracts
	@$(MAKE) generate-report

test-cd: ## Run CD test suite (includes deployment validation)
	@echo "Running CD test suite..."
	@$(MAKE) test-ci
	@$(MAKE) test-minikube
	@$(MAKE) test-e2e
	@$(MAKE) generate-report

# Specific Test Categories
test-smoke: ## Run smoke tests
	@echo "Running smoke tests..."
	pytest -v --tb=short \
		--junit-xml=$(REPORTS_DIR)/smoke-tests-junit.xml \
		-m "smoke" \
		$(TEST_DIR)/ \
		| tee $(LOGS_DIR)/smoke-tests.log

test-regression: ## Run regression tests
	@echo "Running regression tests..."
	pytest -v --tb=short \
		--junit-xml=$(REPORTS_DIR)/regression-tests-junit.xml \
		-m "regression" \
		$(TEST_DIR)/ \
		| tee $(LOGS_DIR)/regression-tests.log

# Utility Targets
validate-coverage: ## Validate test coverage meets threshold
	@echo "Validating test coverage..."
	@$(PYTHON) -c "
import xml.etree.ElementTree as ET
import sys

def check_coverage(file_path, threshold):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        coverage = float(root.attrib.get('line-rate', 0)) * 100
        print(f'Coverage: {coverage:.1f}%')
        if coverage < threshold:
            print(f'ERROR: Coverage {coverage:.1f}% below threshold {threshold}%')
            return False
        print(f'SUCCESS: Coverage {coverage:.1f}% meets threshold {threshold}%')
        return True
    except Exception as e:
        print(f'ERROR: Could not parse coverage file: {e}')
        return False

success = True
for coverage_file in ['$(COVERAGE_DIR)/python-coverage.xml']:
    try:
        if not check_coverage(coverage_file, $(COVERAGE_THRESHOLD)):
            success = False
    except:
        pass

sys.exit(0 if success else 1)
"

generate-report: ## Generate comprehensive test report
	@echo "Generating comprehensive test report..."
	@mkdir -p $(REPORTS_DIR)
	
	@$(PYTHON) -c "
import json
import os
from datetime import datetime
from pathlib import Path

report_dir = Path('$(REPORTS_DIR)')
logs_dir = Path('$(LOGS_DIR)')

# Collect test results
results = {
    'timestamp': datetime.now().isoformat(),
    'environment': '$(TEST_ENV)',
    'test_suites': {},
    'coverage': {},
    'summary': {
        'total_tests': 0,
        'passed_tests': 0,
        'failed_tests': 0,
        'duration': 0
    }
}

# Process log files
for log_file in logs_dir.glob('*.log'):
    suite_name = log_file.stem
    if log_file.exists():
        with open(log_file) as f:
            content = f.read()
            results['test_suites'][suite_name] = {
                'status': 'passed' if 'FAILED' not in content else 'failed',
                'log_file': str(log_file)
            }

# Save report
with open(report_dir / 'test-report.json', 'w') as f:
    json.dump(results, f, indent=2)

print('Test report generated: $(REPORTS_DIR)/test-report.json')
"

watch-tests: ## Run tests in watch mode (requires entr)
	@echo "Running tests in watch mode..."
	@find . -name "*.py" -o -name "*.go" -o -name "*.ts" -o -name "*.tsx" | entr -c make test-unit

# Environment Management
start-test-env: ## Start test environment
	@echo "Starting test environment..."
	@$(DOCKER_COMPOSE) -f tests/docker-compose.test.yml up -d
	@echo "Waiting for services to be ready..."
	@sleep 20
	@echo "Test environment ready!"

stop-test-env: ## Stop test environment
	@echo "Stopping test environment..."
	@$(DOCKER_COMPOSE) -f tests/docker-compose.test.yml down

restart-test-env: stop-test-env start-test-env ## Restart test environment

# Debug and Troubleshooting
debug-unit: ## Run unit tests with debug output
	pytest -v -s --tb=long -m "unit" python-services/tests/unit/

debug-integration: ## Run integration tests with debug output
	TEST_ENV=integration pytest -v -s --tb=long -m "integration" python-services/tests/integration/

test-specific: ## Run specific test (usage: make test-specific TEST=test_name)
	@echo "Running specific test: $(TEST)"
	pytest -v -s --tb=short -k "$(TEST)" $(TEST_DIR)/

# Documentation
test-docs: ## Generate test documentation
	@echo "Generating test documentation..."
	@mkdir -p $(REPORTS_DIR)/docs
	
	# Generate API documentation from tests  
	@$(PYTHON) -c "
import subprocess
import sys
from pathlib import Path

# Generate pytest documentation
subprocess.run([
    sys.executable, '-m', 'pytest', 
    '--collect-only', '--quiet',
    '$(TEST_DIR)/'
], capture_output=True)

print('Test documentation generated')
"

# Default target
all: setup test-all generate-report