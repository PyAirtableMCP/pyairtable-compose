#!/bin/bash

# Comprehensive Test Runner for PyAirtable Compose
# This script runs the complete test suite with coverage enforcement

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MINIMUM_COVERAGE=80
PYTHON_VERSION="3.11"
GO_VERSION="1.21"
TEST_DATABASE_URL="postgresql://test_user:test_password@localhost:5433/test_db"
TEST_REDIS_URL="redis://localhost:6380"

# Default values
RUN_UNIT=true
RUN_INTEGRATION=true
RUN_CONTRACT=true
RUN_E2E=false
RUN_PERFORMANCE=false
RUN_SECURITY=false
CLEAN_BEFORE=false
GENERATE_REPORTS=true
VERBOSE=false
PARALLEL=false

# Help function
show_help() {
    cat << EOF
Comprehensive Test Runner for PyAirtable Compose

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -u, --unit-only         Run only unit tests
    -i, --integration-only  Run only integration tests
    -c, --contract-only     Run only contract tests
    -e, --e2e              Include E2E tests
    -p, --performance      Include performance tests
    -s, --security         Include security tests
    -a, --all              Run all test types (including E2E, performance, security)
    --clean                Clean environment before running tests
    --no-reports           Skip report generation
    -v, --verbose          Verbose output
    --parallel             Run tests in parallel (faster but may be less stable)
    --coverage-min N       Set minimum coverage percentage (default: 80)

EXAMPLES:
    $0                     Run unit, integration, and contract tests
    $0 --unit-only         Run only unit tests
    $0 --all               Run complete test suite
    $0 --e2e --verbose     Run E2E tests with verbose output
    $0 --clean --all       Clean environment and run all tests

ENVIRONMENT VARIABLES:
    TEST_DATABASE_URL      Test database connection string
    TEST_REDIS_URL         Test Redis connection string
    MINIMUM_COVERAGE       Minimum required coverage percentage
    
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--unit-only)
            RUN_INTEGRATION=false
            RUN_CONTRACT=false
            shift
            ;;
        -i|--integration-only)
            RUN_UNIT=false
            RUN_CONTRACT=false
            shift
            ;;
        -c|--contract-only)
            RUN_UNIT=false
            RUN_INTEGRATION=false
            shift
            ;;
        -e|--e2e)
            RUN_E2E=true
            shift
            ;;
        -p|--performance)
            RUN_PERFORMANCE=true
            shift
            ;;
        -s|--security)
            RUN_SECURITY=true
            shift
            ;;
        -a|--all)
            RUN_E2E=true
            RUN_PERFORMANCE=true
            RUN_SECURITY=true
            shift
            ;;
        --clean)
            CLEAN_BEFORE=true
            shift
            ;;
        --no-reports)
            GENERATE_REPORTS=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        --coverage-min)
            MINIMUM_COVERAGE="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    # Check Python
    if ! command_exists python3; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
    
    PYTHON_VER=$(python3 --version | cut -d' ' -f2)
    log_info "Python version: $PYTHON_VER"
    
    # Check Go
    if ! command_exists go; then
        log_warning "Go is not installed, skipping Go tests"
    else
        GO_VER=$(go version | cut -d' ' -f3)
        log_info "Go version: $GO_VER"
    fi
    
    # Check Docker
    if ! command_exists docker; then
        log_warning "Docker is not installed, some tests may fail"
    fi
    
    # Check required Python packages
    if ! python3 -c "import pytest" 2>/dev/null; then
        log_error "pytest is required. Install with: pip install -r requirements-test.txt"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Setup test environment
setup_environment() {
    log_section "Setting Up Test Environment"
    
    # Create reports directory
    mkdir -p reports
    
    # Set environment variables
    export TEST_DATABASE_URL="${TEST_DATABASE_URL}"
    export TEST_REDIS_URL="${TEST_REDIS_URL}"
    export TEST_ENV="integration"
    
    # Clean environment if requested
    if [[ "$CLEAN_BEFORE" == "true" ]]; then
        log_info "Cleaning test environment..."
        docker-compose -f docker-compose.test.yml down -v || true
        rm -rf reports/* || true
        rm -rf htmlcov/ || true
        rm -rf .pytest_cache/ || true
        rm -rf .coverage || true
    fi
    
    # Start test services
    log_info "Starting test services..."
    if ! docker-compose -f docker-compose.test.yml up -d; then
        log_error "Failed to start test services"
        exit 1
    fi
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Check PostgreSQL
    for i in {1..30}; do
        if pg_isready -h localhost -p 5433 -U test_user >/dev/null 2>&1; then
            log_success "PostgreSQL is ready"
            break
        fi
        if [[ $i -eq 30 ]]; then
            log_error "PostgreSQL is not ready after 30 attempts"
            exit 1
        fi
        sleep 2
    done
    
    # Check Redis
    for i in {1..30}; do
        if redis-cli -h localhost -p 6380 ping >/dev/null 2>&1; then
            log_success "Redis is ready"
            break
        fi
        if [[ $i -eq 30 ]]; then
            log_error "Redis is not ready after 30 attempts"
            exit 1
        fi
        sleep 2
    done
    
    # Setup test database schema
    log_info "Setting up test database schema..."
    PGPASSWORD=test_password psql -h localhost -p 5433 -U test_user -d test_db -f migrations/000_create_test_schema.sql || log_warning "Schema setup had warnings"
    
    log_success "Test environment setup completed"
}

# Run Python unit tests
run_python_unit_tests() {
    log_section "Running Python Unit Tests"
    
    local pytest_args=""
    
    if [[ "$VERBOSE" == "true" ]]; then
        pytest_args="$pytest_args -v"
    fi
    
    if [[ "$PARALLEL" == "true" ]]; then
        pytest_args="$pytest_args -n auto"
    fi
    
    pytest_args="$pytest_args --cov=. --cov-report=xml:reports/python-unit-coverage.xml"
    pytest_args="$pytest_args --cov-report=html:reports/python-unit-coverage"
    pytest_args="$pytest_args --cov-fail-under=$MINIMUM_COVERAGE"
    pytest_args="$pytest_args --junit-xml=reports/python-unit-junit.xml"
    pytest_args="$pytest_args -m 'unit'"
    pytest_args="$pytest_args tests/unit/"
    
    if python3 -m pytest $pytest_args; then
        log_success "Python unit tests passed"
        return 0
    else
        log_error "Python unit tests failed"
        return 1
    fi
}

# Run Go unit tests
run_go_unit_tests() {
    log_section "Running Go Unit Tests"
    
    if ! command_exists go; then
        log_warning "Go not available, skipping Go unit tests"
        return 0
    fi
    
    cd go-services || return 1
    
    # Create coverage directory
    mkdir -p ../reports/go-coverage
    
    local test_failed=false
    
    # Test each Go service
    for service_dir in */; do
        if [[ -f "${service_dir}go.mod" ]]; then
            service_name=${service_dir%/}
            log_info "Testing Go service: $service_name"
            
            cd "$service_dir" || continue
            
            if go test -v -race -coverprofile="../reports/go-coverage/${service_name}.out" -covermode=atomic ./...; then
                log_success "Go service $service_name tests passed"
                
                # Generate HTML coverage report
                go tool cover -html="../reports/go-coverage/${service_name}.out" -o "../reports/go-coverage/${service_name}.html"
            else
                log_error "Go service $service_name tests failed"
                test_failed=true
            fi
            
            cd .. || exit 1
        fi
    done
    
    # Merge coverage profiles
    if ls ../reports/go-coverage/*.out 1> /dev/null 2>&1; then
        echo "mode: atomic" > ../reports/go-coverage/merged.out
        grep -h -v "mode: atomic" ../reports/go-coverage/*.out >> ../reports/go-coverage/merged.out 2>/dev/null || true
        
        # Generate merged HTML report
        go tool cover -html="../reports/go-coverage/merged.out" -o "../reports/go-coverage/merged.html"
        
        # Calculate coverage
        COVERAGE=$(go tool cover -func="../reports/go-coverage/merged.out" | grep total | awk '{print $3}' | sed 's/%//')
        log_info "Total Go coverage: ${COVERAGE}%"
        
        # Check coverage threshold
        if (( $(echo "$COVERAGE >= $MINIMUM_COVERAGE" | bc -l) )); then
            log_success "Go coverage meets minimum requirement (${COVERAGE}% >= ${MINIMUM_COVERAGE}%)"
        else
            log_error "Go coverage below minimum requirement (${COVERAGE}% < ${MINIMUM_COVERAGE}%)"
            test_failed=true
        fi
    fi
    
    cd .. || exit 1
    
    if [[ "$test_failed" == "true" ]]; then
        return 1
    else
        return 0
    fi
}

# Run integration tests
run_integration_tests() {
    log_section "Running Integration Tests"
    
    local pytest_args=""
    
    if [[ "$VERBOSE" == "true" ]]; then
        pytest_args="$pytest_args -v"
    fi
    
    pytest_args="$pytest_args --cov=. --cov-append"
    pytest_args="$pytest_args --cov-report=xml:reports/integration-coverage.xml"
    pytest_args="$pytest_args --cov-report=html:reports/integration-coverage"
    pytest_args="$pytest_args --junit-xml=reports/integration-junit.xml"
    pytest_args="$pytest_args -m 'integration'"
    pytest_args="$pytest_args tests/integration/"
    
    if python3 -m pytest $pytest_args; then
        log_success "Integration tests passed"
        return 0
    else
        log_error "Integration tests failed"
        return 1
    fi
}

# Run contract tests
run_contract_tests() {
    log_section "Running Contract Tests"
    
    local pytest_args=""
    
    if [[ "$VERBOSE" == "true" ]]; then
        pytest_args="$pytest_args -v"
    fi
    
    pytest_args="$pytest_args --junit-xml=reports/contract-junit.xml"
    pytest_args="$pytest_args -m 'contract'"
    pytest_args="$pytest_args tests/contract/"
    
    if python3 -m pytest $pytest_args; then
        log_success "Contract tests passed"
        return 0
    else
        log_error "Contract tests failed"
        return 1
    fi
}

# Run E2E tests
run_e2e_tests() {
    log_section "Running E2E Tests"
    
    # Start all services for E2E testing
    log_info "Starting services for E2E tests..."
    docker-compose up -d || log_warning "Some services may not have started"
    
    # Wait for services to be ready
    sleep 30
    
    local pytest_args=""
    
    if [[ "$VERBOSE" == "true" ]]; then
        pytest_args="$pytest_args -v"
    fi
    
    pytest_args="$pytest_args --junit-xml=reports/e2e-junit.xml"
    pytest_args="$pytest_args -m 'e2e'"
    pytest_args="$pytest_args tests/e2e/"
    
    if python3 -m pytest $pytest_args; then
        log_success "E2E tests passed"
        return 0
    else
        log_error "E2E tests failed"
        return 1
    fi
}

# Run performance tests
run_performance_tests() {
    log_section "Running Performance Tests"
    
    local pytest_args=""
    
    if [[ "$VERBOSE" == "true" ]]; then
        pytest_args="$pytest_args -v"
    fi
    
    pytest_args="$pytest_args --junit-xml=reports/performance-junit.xml"
    pytest_args="$pytest_args -m 'performance'"
    pytest_args="$pytest_args tests/performance/"
    
    if python3 -m pytest $pytest_args; then
        log_success "Performance tests passed"
        return 0
    else
        log_warning "Performance tests failed or had warnings"
        return 0  # Don't fail build on performance test failures
    fi
}

# Run security tests
run_security_tests() {
    log_section "Running Security Tests"
    
    local pytest_args=""
    
    if [[ "$VERBOSE" == "true" ]]; then
        pytest_args="$pytest_args -v"
    fi
    
    pytest_args="$pytest_args --junit-xml=reports/security-junit.xml"
    pytest_args="$pytest_args -m 'security'"
    pytest_args="$pytest_args tests/security/"
    
    if python3 -m pytest $pytest_args; then
        log_success "Security tests passed"
        return 0
    else
        log_error "Security tests failed"
        return 1
    fi
}

# Generate comprehensive reports
generate_reports() {
    if [[ "$GENERATE_REPORTS" != "true" ]]; then
        return 0
    fi
    
    log_section "Generating Test Reports"
    
    # Generate coverage badge
    if command_exists coverage-badge; then
        coverage-badge -o reports/coverage-badge.svg
        log_info "Generated coverage badge"
    fi
    
    # Generate test summary
    cat > reports/test-summary.md << EOF
# Test Execution Summary

**Executed on**: $(date)
**Minimum Coverage Requirement**: ${MINIMUM_COVERAGE}%

## Test Types Executed
$(if [[ "$RUN_UNIT" == "true" ]]; then echo "- ✅ Unit Tests"; fi)
$(if [[ "$RUN_INTEGRATION" == "true" ]]; then echo "- ✅ Integration Tests"; fi)
$(if [[ "$RUN_CONTRACT" == "true" ]]; then echo "- ✅ Contract Tests"; fi)
$(if [[ "$RUN_E2E" == "true" ]]; then echo "- ✅ E2E Tests"; fi)
$(if [[ "$RUN_PERFORMANCE" == "true" ]]; then echo "- ✅ Performance Tests"; fi)
$(if [[ "$RUN_SECURITY" == "true" ]]; then echo "- ✅ Security Tests"; fi)

## Reports Generated
- HTML Coverage Reports: \`reports/\*-coverage/index.html\`
- XML Coverage Reports: \`reports/\*-coverage.xml\`
- JUnit Test Reports: \`reports/\*-junit.xml\`

## Quick Access
- [Python Unit Coverage](python-unit-coverage/index.html)
- [Integration Coverage](integration-coverage/index.html)
$(if command_exists go; then echo "- [Go Coverage](go-coverage/merged.html)"; fi)

*Generated by run-comprehensive-tests.sh*
EOF
    
    log_success "Test summary generated: reports/test-summary.md"
    
    # List generated reports
    log_info "Generated reports:"
    find reports/ -name "*.html" -o -name "*.xml" -o -name "*.md" | sort
}

# Cleanup function
cleanup() {
    log_section "Cleaning Up"
    
    # Stop test services
    docker-compose -f docker-compose.test.yml down || true
    
    # Stop main services if they were started for E2E
    if [[ "$RUN_E2E" == "true" ]]; then
        docker-compose down || true
    fi
    
    log_success "Cleanup completed"
}

# Main execution
main() {
    local start_time=$(date +%s)
    local failed_tests=()
    
    log_section "Starting Comprehensive Test Suite"
    log_info "Minimum coverage requirement: ${MINIMUM_COVERAGE}%"
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Check prerequisites
    check_prerequisites
    
    # Setup test environment
    setup_environment
    
    # Run tests based on configuration
    if [[ "$RUN_UNIT" == "true" ]]; then
        if ! run_python_unit_tests; then
            failed_tests+=("Python Unit Tests")
        fi
        
        if command_exists go; then
            if ! run_go_unit_tests; then
                failed_tests+=("Go Unit Tests")
            fi
        fi
    fi
    
    if [[ "$RUN_INTEGRATION" == "true" ]]; then
        if ! run_integration_tests; then
            failed_tests+=("Integration Tests")
        fi
    fi
    
    if [[ "$RUN_CONTRACT" == "true" ]]; then
        if ! run_contract_tests; then
            failed_tests+=("Contract Tests")
        fi
    fi
    
    if [[ "$RUN_E2E" == "true" ]]; then
        if ! run_e2e_tests; then
            failed_tests+=("E2E Tests")
        fi
    fi
    
    if [[ "$RUN_PERFORMANCE" == "true" ]]; then
        run_performance_tests  # Don't add to failed_tests
    fi
    
    if [[ "$RUN_SECURITY" == "true" ]]; then
        if ! run_security_tests; then
            failed_tests+=("Security Tests")
        fi
    fi
    
    # Generate reports
    generate_reports
    
    # Calculate execution time
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    local minutes=$((execution_time / 60))
    local seconds=$((execution_time % 60))
    
    # Final summary
    log_section "Test Execution Summary"
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log_success "All tests passed! 🎉"
        log_info "Execution time: ${minutes}m ${seconds}s"
        log_info "Reports available in: reports/"
        exit 0
    else
        log_error "The following test suites failed:"
        for test in "${failed_tests[@]}"; do
            echo -e "  ${RED}- $test${NC}"
        done
        log_info "Execution time: ${minutes}m ${seconds}s"
        log_info "Check reports for details: reports/"
        exit 1
    fi
}

# Run main function
main "$@"