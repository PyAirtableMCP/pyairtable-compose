#!/bin/bash

# Run PyAirtable test suite
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.test.yml"
PROJECT_NAME="pyairtable-test"
REPORTS_DIR="reports"

# Default test configuration
TEST_TYPE=${TEST_TYPE:-"all"}
PARALLEL=${PARALLEL:-"auto"}
COVERAGE=${COVERAGE:-"true"}
VERBOSE=${VERBOSE:-"true"}
TIMEOUT=${TIMEOUT:-"300"}
RERUNS=${RERUNS:-"2"}
FAIL_FAST=${FAIL_FAST:-"false"}

echo -e "${BLUE}PyAirtable Test Suite Runner${NC}"
echo "============================"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [TEST_TYPE]"
    echo ""
    echo "Test Types:"
    echo "  unit         - Run unit tests only"
    echo "  integration  - Run integration tests only"
    echo "  e2e          - Run end-to-end tests only"
    echo "  performance  - Run performance tests only"
    echo "  security     - Run security tests only"
    echo "  contract     - Run contract tests only"
    echo "  chaos        - Run chaos engineering tests"
    echo "  smoke        - Run smoke tests"
    echo "  all          - Run all tests (default)"
    echo ""
    echo "Options:"
    echo "  -p, --parallel <n>     Number of parallel workers (default: auto)"
    echo "  -c, --no-coverage      Disable coverage reporting"
    echo "  -q, --quiet            Quiet output"
    echo "  -v, --verbose          Verbose output (default)"
    echo "  -f, --fail-fast        Stop on first failure"
    echo "  -r, --reruns <n>       Number of reruns for flaky tests (default: 2)"
    echo "  -t, --timeout <s>      Test timeout in seconds (default: 300)"
    echo "  -k, --keyword <expr>   Run tests matching keyword expression"
    echo "  -m, --marker <marker>  Run tests with specific marker"
    echo "  --env <env>            Test environment (unit|integration|e2e)"
    echo "  --reports-only         Generate reports without running tests"
    echo "  --cleanup              Clean up test environment after run"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 unit -p 4 -c          # Run unit tests with 4 workers, no coverage"
    echo "  $0 integration -v -f     # Run integration tests, verbose, fail fast"
    echo "  $0 -k \"test_user\"        # Run tests matching 'test_user'"
    echo "  $0 -m \"slow\"             # Run tests marked as 'slow'"
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--parallel)
                PARALLEL="$2"
                shift 2
                ;;
            -c|--no-coverage)
                COVERAGE="false"
                shift
                ;;
            -q|--quiet)
                VERBOSE="false"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -f|--fail-fast)
                FAIL_FAST="true"
                shift
                ;;
            -r|--reruns)
                RERUNS="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -k|--keyword)
                KEYWORD="$2"
                shift 2
                ;;
            -m|--marker)
                MARKER="$2"
                shift 2
                ;;
            --env)
                TEST_ENV="$2"
                shift 2
                ;;
            --reports-only)
                REPORTS_ONLY="true"
                shift
                ;;
            --cleanup)
                CLEANUP="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            unit|integration|e2e|performance|security|contract|chaos|smoke|all)
                TEST_TYPE="$1"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to check if test environment is ready
check_environment() {
    print_status "Checking test environment..."
    
    if ! docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps | grep -q "Up"; then
        print_error "Test environment is not running. Please run './scripts/setup-test-env.sh up' first."
        exit 1
    fi
    
    # Check if key services are healthy
    local services=("postgres-test" "redis-test" "api-gateway-test")
    for service in "${services[@]}"; do
        if ! docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps --filter "status=running" | grep -q "$service"; then
            print_error "$service is not running"
            exit 1
        fi
    done
    
    print_status "Test environment is ready"
}

# Function to prepare test environment
prepare_environment() {
    print_status "Preparing test environment for $TEST_TYPE tests..."
    
    # Create reports directory
    mkdir -p $REPORTS_DIR
    
    # Clean previous test data if needed
    case $TEST_TYPE in
        "integration"|"e2e"|"all")
            print_status "Cleaning test database..."
            docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T postgres-test psql -U test_user -d pyairtable_test -c "
                TRUNCATE TABLE users, workspaces, workspace_members CASCADE;
            " 2>/dev/null || print_warning "Some tables may not exist yet"
            ;;
    esac
    
    # Set environment variables for test runner
    export TEST_ENV=${TEST_ENV:-$TEST_TYPE}
    export DATABASE_URL="postgresql://test_user:test_password@postgres-test:5432/pyairtable_test"
    export REDIS_URL="redis://:test_password@redis-test:6379"
    export API_GATEWAY_URL="http://api-gateway-test:8000"
    export AUTH_SERVICE_URL="http://auth-service-test:8004"
    export LLM_ORCHESTRATOR_URL="http://llm-orchestrator-test:8003"
    export AIRTABLE_GATEWAY_URL="http://airtable-gateway-test:8001"
    export MCP_SERVER_URL="http://mcp-server-test:8002"
}

# Function to build pytest command
build_pytest_command() {
    local cmd="pytest"
    
    # Add verbosity
    if [ "$VERBOSE" = "true" ]; then
        cmd="$cmd -v"
    else
        cmd="$cmd -q"
    fi
    
    # Add parallel execution
    if [ "$PARALLEL" != "1" ] && [ "$PARALLEL" != "false" ]; then
        if [ "$PARALLEL" = "auto" ]; then
            cmd="$cmd -n auto"
        else
            cmd="$cmd -n $PARALLEL"
        fi
    fi
    
    # Add coverage
    if [ "$COVERAGE" = "true" ]; then
        cmd="$cmd --cov=. --cov-report=html:$REPORTS_DIR/coverage --cov-report=xml:$REPORTS_DIR/coverage.xml --cov-report=term-missing"
    fi
    
    # Add test markers based on test type
    case $TEST_TYPE in
        "unit")
            cmd="$cmd -m 'unit and not slow'"
            ;;
        "integration")
            cmd="$cmd -m 'integration'"
            ;;
        "e2e")
            cmd="$cmd -m 'e2e'"
            ;;
        "performance")
            cmd="$cmd -m 'performance'"
            ;;
        "security")
            cmd="$cmd -m 'security'"
            ;;
        "contract")
            cmd="$cmd -m 'contract'"
            ;;
        "chaos")
            cmd="$cmd -m 'chaos'"
            ;;
        "smoke")
            cmd="$cmd -m 'smoke'"
            ;;
        "all")
            # Run all tests
            ;;
    esac
    
    # Add custom marker if specified
    if [ -n "$MARKER" ]; then
        if [[ "$cmd" == *"-m "* ]]; then
            cmd="${cmd} and ${MARKER}"
        else
            cmd="$cmd -m '$MARKER'"
        fi
    fi
    
    # Add keyword filter
    if [ -n "$KEYWORD" ]; then
        cmd="$cmd -k '$KEYWORD'"
    fi
    
    # Add timeout
    cmd="$cmd --timeout=$TIMEOUT"
    
    # Add reruns for flaky tests
    if [ "$RERUNS" -gt "0" ]; then
        cmd="$cmd --reruns=$RERUNS --reruns-delay=2"
    fi
    
    # Add fail fast
    if [ "$FAIL_FAST" = "true" ]; then
        cmd="$cmd --maxfail=1"
    fi
    
    # Add output options
    cmd="$cmd --tb=short --junit-xml=$REPORTS_DIR/junit.xml --html=$REPORTS_DIR/report.html --self-contained-html"
    
    echo "$cmd"
}

# Function to run tests
run_tests() {
    if [ "$REPORTS_ONLY" = "true" ]; then
        print_status "Generating reports from existing test data..."
        generate_reports
        return
    fi
    
    print_status "Running $TEST_TYPE tests..."
    
    local pytest_cmd=$(build_pytest_command)
    
    print_status "Executing: $pytest_cmd"
    
    # Run tests inside test runner container
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME run --rm \
        -e TEST_ENV="$TEST_ENV" \
        -e DATABASE_URL="$DATABASE_URL" \
        -e REDIS_URL="$REDIS_URL" \
        -e API_GATEWAY_URL="$API_GATEWAY_URL" \
        -e AUTH_SERVICE_URL="$AUTH_SERVICE_URL" \
        -e LLM_ORCHESTRATOR_URL="$LLM_ORCHESTRATOR_URL" \
        -e AIRTABLE_GATEWAY_URL="$AIRTABLE_GATEWAY_URL" \
        -e MCP_SERVER_URL="$MCP_SERVER_URL" \
        test-runner \
        bash -c "$pytest_cmd"
    
    local exit_code=$?
    
    # Copy reports from container
    print_status "Copying test reports..."
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME run --rm \
        -v "$(pwd)/$REPORTS_DIR:/host_reports" \
        test-runner \
        bash -c "cp -r /app/reports/* /host_reports/ 2>/dev/null || true"
    
    return $exit_code
}

# Function to generate reports
generate_reports() {
    print_status "Generating test reports..."
    
    # Generate HTML coverage report if coverage data exists
    if [ -f "$REPORTS_DIR/.coverage" ]; then
        coverage html -d "$REPORTS_DIR/coverage"
        coverage xml -o "$REPORTS_DIR/coverage.xml"
    fi
    
    # Generate test metrics
    python3 -c "
import json
import xml.etree.ElementTree as ET
from pathlib import Path

reports_dir = Path('$REPORTS_DIR')

# Parse JUnit XML if it exists
junit_file = reports_dir / 'junit.xml'
if junit_file.exists():
    tree = ET.parse(junit_file)
    root = tree.getroot()
    
    metrics = {
        'total_tests': int(root.get('tests', 0)),
        'failures': int(root.get('failures', 0)),
        'errors': int(root.get('errors', 0)),
        'skipped': int(root.get('skipped', 0)),
        'time': float(root.get('time', 0)),
        'success_rate': 0
    }
    
    if metrics['total_tests'] > 0:
        passed = metrics['total_tests'] - metrics['failures'] - metrics['errors'] - metrics['skipped']
        metrics['success_rate'] = (passed / metrics['total_tests']) * 100
    
    with open(reports_dir / 'metrics.json', 'w') as f:
        json.dump(metrics, f, indent=2)
    
    print(f\"Test Results Summary:\")
    print(f\"  Total: {metrics['total_tests']}\")
    print(f\"  Passed: {metrics['total_tests'] - metrics['failures'] - metrics['errors'] - metrics['skipped']}\")
    print(f\"  Failed: {metrics['failures']}\")
    print(f\"  Errors: {metrics['errors']}\")
    print(f\"  Skipped: {metrics['skipped']}\")
    print(f\"  Success Rate: {metrics['success_rate']:.1f}%\")
    print(f\"  Duration: {metrics['time']:.2f}s\")
" 2>/dev/null || print_warning "Could not generate test metrics"
    
    print_status "Reports generated in $REPORTS_DIR/"
}

# Function to cleanup test environment
cleanup_environment() {
    if [ "$CLEANUP" = "true" ]; then
        print_status "Cleaning up test environment..."
        ./scripts/setup-test-env.sh down
    fi
}

# Function to show test results
show_results() {
    local exit_code=$1
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        print_status "✅ All tests passed!"
    else
        print_error "❌ Some tests failed (exit code: $exit_code)"
    fi
    
    # Show report locations
    echo ""
    print_status "Test Reports:"
    
    if [ -f "$REPORTS_DIR/report.html" ]; then
        echo "  HTML Report:     file://$(pwd)/$REPORTS_DIR/report.html"
    fi
    
    if [ -f "$REPORTS_DIR/junit.xml" ]; then
        echo "  JUnit XML:       $REPORTS_DIR/junit.xml"
    fi
    
    if [ -f "$REPORTS_DIR/coverage.xml" ]; then
        echo "  Coverage XML:    $REPORTS_DIR/coverage.xml"
    fi
    
    if [ -d "$REPORTS_DIR/coverage" ]; then
        echo "  Coverage HTML:   file://$(pwd)/$REPORTS_DIR/coverage/index.html"
    fi
    
    if [ -f "$REPORTS_DIR/metrics.json" ]; then
        echo "  Test Metrics:    $REPORTS_DIR/metrics.json"
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    if [ "$REPORTS_ONLY" != "true" ]; then
        check_environment
    fi
    
    prepare_environment
    
    local exit_code=0
    run_tests || exit_code=$?
    
    generate_reports
    show_results $exit_code
    cleanup_environment
    
    exit $exit_code
}

# Execute main function
main "$@"