#!/bin/bash

# PyAirtable Comprehensive Integration Test Suite Runner
# This script orchestrates the complete test environment and execution

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/test-config.yml"
TEST_ENV="local"
TEST_CATEGORY="all"
PARALLEL_EXECUTION=true
CLEANUP_AFTER=true
VERBOSE=false
DEBUG_MODE=false
SMOKE_ONLY=false
HEALTH_CHECK_ONLY=false
VALIDATE_ENV_ONLY=false
TIMEOUT="30m"
OUTPUT_FORMAT="console"
REPORTS_DIR="${SCRIPT_DIR}/test-results"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --env|--environment)
            TEST_ENV="$2"
            shift 2
            ;;
        --category)
            TEST_CATEGORY="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --reports-dir)
            REPORTS_DIR="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL_EXECUTION=true
            shift
            ;;
        --no-parallel)
            PARALLEL_EXECUTION=false
            shift
            ;;
        --cleanup)
            CLEANUP_AFTER=true
            shift
            ;;
        --no-cleanup)
            CLEANUP_AFTER=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            VERBOSE=true
            shift
            ;;
        --smoke)
            SMOKE_ONLY=true
            shift
            ;;
        --health-check)
            HEALTH_CHECK_ONLY=true
            shift
            ;;
        --validate-env)
            VALIDATE_ENV_ONLY=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Help function
show_help() {
    cat << EOF
PyAirtable Comprehensive Integration Test Suite

Usage: $0 [OPTIONS]

Options:
    --config FILE          Configuration file (default: config/test-config.yml)
    --env ENV             Test environment: local, ci, production-like (default: local)
    --category CATEGORY   Test category: all, e2e, service-integration, performance, chaos, contract, security (default: all)
    --timeout DURATION    Test timeout (default: 30m)
    --output FORMAT       Output format: console, json, junit, html (default: console)
    --reports-dir DIR     Reports directory (default: test-results)
    --parallel            Enable parallel test execution (default: true)
    --no-parallel         Disable parallel test execution
    --cleanup             Cleanup after tests (default: true)
    --no-cleanup          Skip cleanup after tests
    --verbose             Enable verbose output
    --debug               Enable debug mode with detailed logging
    --smoke               Run smoke tests only
    --health-check        Run health checks only
    --validate-env        Validate environment only
    --help                Show this help message

Test Categories:
    e2e                   End-to-end architectural pattern tests (SAGA, CQRS, Event Sourcing, Outbox, UoW)
    service-integration   Service integration and communication tests
    performance           Performance and load testing
    chaos                 Chaos engineering and fault injection
    contract              API contract and compatibility testing
    security              Security and vulnerability testing

Examples:
    $0                                    # Run all tests with default settings
    $0 --category e2e --env local         # Run E2E tests in local environment
    $0 --smoke --env ci                   # Run smoke tests in CI environment
    $0 --debug --no-cleanup               # Run with debug mode, no cleanup
    $0 --health-check                     # Check service health only
    $0 --validate-env --env production-like # Validate production-like environment

EOF
}

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

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1"
    fi
}

# Validation functions
validate_dependencies() {
    log_info "Validating dependencies..."
    
    local missing_deps=()
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    # Check Go
    if ! command -v go &> /dev/null; then
        missing_deps+=("go")
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

validate_config() {
    log_info "Validating configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate YAML syntax
    if ! python3 -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" &> /dev/null; then
        log_error "Invalid YAML syntax in configuration file: $CONFIG_FILE"
        exit 1
    fi
    
    log_success "Configuration file is valid"
}

# Environment management functions
start_environment() {
    log_info "Starting test environment: $TEST_ENV"
    
    # Create reports directory
    mkdir -p "$REPORTS_DIR"
    
    # Export environment variables
    export TEST_ENVIRONMENT="$TEST_ENV"
    export TEST_CONFIG="$CONFIG_FILE"
    export TEST_REPORTS_DIR="$REPORTS_DIR"
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        export LOG_LEVEL="debug"
        export VERBOSE="true"
    fi
    
    # Start Docker Compose services
    local compose_file="${SCRIPT_DIR}/docker-compose.test.yml"
    local env_override="${SCRIPT_DIR}/environments/${TEST_ENV}.yml"
    
    local compose_args="-f $compose_file"
    if [[ -f "$env_override" ]]; then
        compose_args="$compose_args -f $env_override"
    fi
    
    log_debug "Docker Compose command: docker-compose $compose_args up -d"
    
    # Start infrastructure services first
    docker-compose $compose_args up -d \
        postgres-primary \
        postgres-events \
        redis-cache \
        redis-sessions \
        zookeeper \
        kafka
    
    # Wait for infrastructure services
    wait_for_infrastructure
    
    # Start application services
    docker-compose $compose_args up -d \
        auth-service \
        user-service \
        workspace-service \
        permission-service \
        saga-orchestrator \
        api-gateway
    
    # Wait for application services
    wait_for_services
    
    # Start monitoring services if not in CI
    if [[ "$TEST_ENV" != "ci" ]]; then
        docker-compose $compose_args up -d \
            prometheus \
            grafana
    fi
    
    # Start utility services
    docker-compose $compose_args up -d \
        wiremock \
        mailhog
    
    log_success "Test environment started successfully"
}

wait_for_infrastructure() {
    log_info "Waiting for infrastructure services..."
    
    local services=("postgres-primary:5432" "postgres-events:5433" "redis-cache:6379" "redis-sessions:6380" "kafka:9092")
    
    for service in "${services[@]}"; do
        local host_port=(${service//:/ })
        local host=${host_port[0]}
        local port=${host_port[1]}
        
        log_debug "Waiting for $host:$port..."
        
        local max_attempts=60
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if docker-compose exec -T "$host" sh -c "echo > /dev/tcp/localhost/$port" &>/dev/null || \
               nc -z localhost "$port" &>/dev/null; then
                log_debug "$host:$port is ready"
                break
            fi
            
            if [[ $attempt -eq $max_attempts ]]; then
                log_error "Timeout waiting for $host:$port"
                return 1
            fi
            
            sleep 2
            ((attempt++))
        done
    done
    
    log_success "Infrastructure services are ready"
}

wait_for_services() {
    log_info "Waiting for application services..."
    
    local services=(
        "auth-service:8083:/health"
        "user-service:8084:/health"
        "workspace-service:8086:/health"
        "permission-service:8085:/health"
        "saga-orchestrator:8087:/health"
        "api-gateway:8080:/health"
    )
    
    for service in "${services[@]}"; do
        local parts=(${service//:/ })
        local name=${parts[0]}
        local port=${parts[1]}
        local path=${parts[2]}
        
        log_debug "Waiting for $name health check..."
        
        local max_attempts=60
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if curl -f -s "http://localhost:$port$path" &>/dev/null; then
                log_debug "$name is healthy"
                break
            fi
            
            if [[ $attempt -eq $max_attempts ]]; then
                log_error "Timeout waiting for $name health check"
                return 1
            fi
            
            sleep 3
            ((attempt++))
        done
    done
    
    log_success "Application services are healthy"
}

# Health check functions
health_check() {
    log_info "Performing comprehensive health check..."
    
    local health_status=0
    
    # Check service health endpoints
    local services=(
        "api-gateway:8080"
        "auth-service:8083"
        "user-service:8084"
        "workspace-service:8086"
        "permission-service:8085"
        "saga-orchestrator:8087"
    )
    
    for service in "${services[@]}"; do
        local name_port=(${service//:/ })
        local name=${name_port[0]}
        local port=${name_port[1]}
        
        if curl -f -s "http://localhost:$port/health" | jq -e '.status == "ok"' &>/dev/null; then
            log_success "$name is healthy"
        else
            log_error "$name is unhealthy"
            health_status=1
        fi
    done
    
    # Check database connectivity
    if PGPASSWORD=test_password psql -h localhost -p 5432 -U test_user -d pyairtable_test -c "SELECT 1;" &>/dev/null; then
        log_success "Primary database is accessible"
    else
        log_error "Primary database is not accessible"
        health_status=1
    fi
    
    if PGPASSWORD=test_password psql -h localhost -p 5433 -U test_user -d pyairtable_events_test -c "SELECT 1;" &>/dev/null; then
        log_success "Events database is accessible"
    else
        log_error "Events database is not accessible"
        health_status=1
    fi
    
    # Check Redis connectivity
    if redis-cli -h localhost -p 6379 -a testpassword ping | grep -q PONG; then
        log_success "Redis cache is accessible"
    else
        log_error "Redis cache is not accessible"
        health_status=1
    fi
    
    # Check Kafka connectivity
    if docker-compose exec -T kafka kafka-broker-api-versions --bootstrap-server localhost:9092 &>/dev/null; then
        log_success "Kafka is accessible"
    else
        log_error "Kafka is not accessible"
        health_status=1
    fi
    
    return $health_status
}

# Test execution functions
run_tests() {
    log_info "Running integration tests: $TEST_CATEGORY"
    
    # Create test results directory with timestamp
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local run_dir="$REPORTS_DIR/run_$timestamp"
    mkdir -p "$run_dir"
    
    # Set test execution parameters
    local test_args=""
    
    if [[ "$PARALLEL_EXECUTION" == "true" && "$TEST_CATEGORY" != "e2e" ]]; then
        test_args="$test_args --parallel"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        test_args="$test_args --verbose"
    fi
    
    if [[ "$DEBUG_MODE" == "true" ]]; then
        test_args="$test_args --debug"
    fi
    
    # Execute test categories
    case "$TEST_CATEGORY" in
        "all")
            run_test_category "e2e" "$run_dir" false
            run_test_category "service-integration" "$run_dir" true
            run_test_category "performance" "$run_dir" true
            run_test_category "chaos" "$run_dir" false
            run_test_category "contract" "$run_dir" true
            run_test_category "security" "$run_dir" true
            ;;
        "smoke")
            run_smoke_tests "$run_dir"
            ;;
        *)
            run_test_category "$TEST_CATEGORY" "$run_dir" "$PARALLEL_EXECUTION"
            ;;
    esac
    
    # Generate combined report
    generate_report "$run_dir"
}

run_test_category() {
    local category="$1"
    local run_dir="$2"
    local parallel="$3"
    
    log_info "Running $category tests..."
    
    local category_dir="$run_dir/$category"
    mkdir -p "$category_dir"
    
    local test_cmd="go test -timeout $TIMEOUT"
    
    if [[ "$parallel" == "true" ]]; then
        test_cmd="$test_cmd -parallel 4"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        test_cmd="$test_cmd -v"
    fi
    
    # Add output formatters
    case "$OUTPUT_FORMAT" in
        "json")
            test_cmd="$test_cmd -json"
            ;;
        "junit")
            test_cmd="$test_cmd -json | go-junit-report"
            ;;
    esac
    
    # Set environment variables for test execution
    export TEST_CATEGORY="$category"
    export TEST_RUN_DIR="$category_dir"
    export TEST_CONFIG="$CONFIG_FILE"
    export DATABASE_URL="postgres://test_user:test_password@localhost:5432/pyairtable_test?sslmode=disable"
    export EVENTS_DATABASE_URL="postgres://test_user:test_password@localhost:5433/pyairtable_events_test?sslmode=disable"
    export REDIS_URL="redis://:testpassword@localhost:6379/0"
    export KAFKA_BROKERS="localhost:9092"
    
    # Run tests
    local test_exit_code=0
    
    case "$category" in
        "e2e")
            $test_cmd ./e2e/... > "$category_dir/test_output.log" 2>&1 || test_exit_code=$?
            ;;
        "service-integration")
            $test_cmd ./service-integration/... > "$category_dir/test_output.log" 2>&1 || test_exit_code=$?
            ;;
        "performance")
            run_performance_tests "$category_dir" || test_exit_code=$?
            ;;
        "chaos")
            run_chaos_tests "$category_dir" || test_exit_code=$?
            ;;
        "contract")
            run_contract_tests "$category_dir" || test_exit_code=$?
            ;;
        "security")
            run_security_tests "$category_dir" || test_exit_code=$?
            ;;
    esac
    
    if [[ $test_exit_code -eq 0 ]]; then
        log_success "$category tests completed successfully"
    else
        log_error "$category tests failed with exit code $test_exit_code"
    fi
    
    return $test_exit_code
}

run_smoke_tests() {
    local run_dir="$1"
    
    log_info "Running smoke tests..."
    
    local smoke_dir="$run_dir/smoke"
    mkdir -p "$smoke_dir"
    
    # Basic connectivity tests
    local smoke_tests=(
        "health_check"
        "database_connectivity"
        "service_authentication"
        "basic_api_operations"
    )
    
    local failed_tests=()
    
    for test in "${smoke_tests[@]}"; do
        log_debug "Running smoke test: $test"
        
        case "$test" in
            "health_check")
                if health_check; then
                    log_success "Smoke test passed: $test"
                else
                    log_error "Smoke test failed: $test"
                    failed_tests+=("$test")
                fi
                ;;
            "database_connectivity")
                if test_database_connectivity; then
                    log_success "Smoke test passed: $test"
                else
                    log_error "Smoke test failed: $test"
                    failed_tests+=("$test")
                fi
                ;;
            "service_authentication")
                if test_service_authentication; then
                    log_success "Smoke test passed: $test"
                else
                    log_error "Smoke test failed: $test"
                    failed_tests+=("$test")
                fi
                ;;
            "basic_api_operations")
                if test_basic_api_operations; then
                    log_success "Smoke test passed: $test"
                else
                    log_error "Smoke test failed: $test"
                    failed_tests+=("$test")
                fi
                ;;
        esac
    done
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log_success "All smoke tests passed"
        return 0
    else
        log_error "Smoke tests failed: ${failed_tests[*]}"
        return 1
    fi
}

run_performance_tests() {
    local run_dir="$1"
    
    log_info "Running performance tests..."
    
    # Use k6 for load testing
    k6 run --out json="$run_dir/k6_results.json" ./performance/load_test.js
    
    # Use wrk for HTTP benchmarking
    wrk -t12 -c400 -d30s --latency http://localhost:8080/health > "$run_dir/wrk_results.txt"
    
    # Custom Go performance tests
    go test -timeout 10m -run TestPerformance ./performance/... > "$run_dir/go_perf_results.log" 2>&1
}

run_chaos_tests() {
    local run_dir="$1"
    
    log_info "Running chaos engineering tests..."
    
    # Custom chaos injection tests
    go test -timeout 15m -run TestChaos ./chaos/... > "$run_dir/chaos_results.log" 2>&1
}

run_contract_tests() {
    local run_dir="$1"
    
    log_info "Running contract tests..."
    
    # Pact contract testing
    go test -timeout 10m -run TestContract ./contract/... > "$run_dir/contract_results.log" 2>&1
}

run_security_tests() {
    local run_dir="$1"
    
    log_info "Running security tests..."
    
    # Security-specific tests
    go test -timeout 10m -run TestSecurity ./security/... > "$run_dir/security_results.log" 2>&1
}

# Helper test functions
test_database_connectivity() {
    PGPASSWORD=test_password psql -h localhost -p 5432 -U test_user -d pyairtable_test -c "SELECT COUNT(*) FROM information_schema.tables;" &>/dev/null &&
    PGPASSWORD=test_password psql -h localhost -p 5433 -U test_user -d pyairtable_events_test -c "SELECT COUNT(*) FROM information_schema.tables;" &>/dev/null
}

test_service_authentication() {
    local auth_response=$(curl -s -X POST http://localhost:8083/auth/login \
        -H "Content-Type: application/json" \
        -d '{"email":"admin@alpha.test.com","password":"test123"}')
    
    echo "$auth_response" | jq -e '.token' &>/dev/null
}

test_basic_api_operations() {
    # Test API Gateway health
    curl -f -s http://localhost:8080/health &>/dev/null &&
    # Test basic API endpoint
    curl -f -s -H "X-API-Key: test-api-key-12345" http://localhost:8080/api/v1/tenants &>/dev/null
}

# Report generation
generate_report() {
    local run_dir="$1"
    
    log_info "Generating test reports..."
    
    # Generate HTML report
    if [[ "$OUTPUT_FORMAT" == "html" || "$OUTPUT_FORMAT" == "all" ]]; then
        generate_html_report "$run_dir"
    fi
    
    # Generate JUnit XML report
    if [[ "$OUTPUT_FORMAT" == "junit" || "$OUTPUT_FORMAT" == "all" ]]; then
        generate_junit_report "$run_dir"
    fi
    
    # Generate JSON report
    if [[ "$OUTPUT_FORMAT" == "json" || "$OUTPUT_FORMAT" == "all" ]]; then
        generate_json_report "$run_dir"
    fi
    
    # Generate summary
    generate_summary_report "$run_dir"
}

generate_html_report() {
    local run_dir="$1"
    
    # This would generate an HTML report
    # Implementation depends on your reporting requirements
    log_debug "Generating HTML report in $run_dir/report.html"
}

generate_junit_report() {
    local run_dir="$1"
    
    # This would generate a JUnit XML report
    log_debug "Generating JUnit report in $run_dir/junit.xml"
}

generate_json_report() {
    local run_dir="$1"
    
    # This would generate a JSON report
    log_debug "Generating JSON report in $run_dir/report.json"
}

generate_summary_report() {
    local run_dir="$1"
    
    local summary_file="$run_dir/summary.txt"
    
    cat > "$summary_file" << EOF
PyAirtable Integration Test Suite Summary
=========================================

Execution Time: $(date)
Environment: $TEST_ENV
Category: $TEST_CATEGORY
Configuration: $CONFIG_FILE

Test Results:
$(find "$run_dir" -name "*.log" -exec echo "- {}" \; | head -10)

For detailed results, see individual test category directories.
EOF
    
    log_success "Test summary generated: $summary_file"
}

# Cleanup functions
cleanup_environment() {
    if [[ "$CLEANUP_AFTER" == "true" ]]; then
        log_info "Cleaning up test environment..."
        
        # Stop and remove containers
        docker-compose -f "${SCRIPT_DIR}/docker-compose.test.yml" down -v --remove-orphans
        
        # Remove test data volumes (optional)
        if [[ "$TEST_ENV" == "ci" ]]; then
            docker volume prune -f
        fi
        
        log_success "Environment cleanup completed"
    else
        log_info "Skipping environment cleanup (--no-cleanup specified)"
    fi
}

# Signal handlers
trap cleanup_environment EXIT

# Main execution flow
main() {
    log_info "Starting PyAirtable Integration Test Suite"
    log_info "Environment: $TEST_ENV, Category: $TEST_CATEGORY"
    
    # Validate prerequisites
    validate_dependencies
    validate_config
    
    if [[ "$VALIDATE_ENV_ONLY" == "true" ]]; then
        log_success "Environment validation completed"
        exit 0
    fi
    
    # Start test environment
    start_environment
    
    if [[ "$HEALTH_CHECK_ONLY" == "true" ]]; then
        health_check
        exit $?
    fi
    
    # Run tests
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_info "Debug mode enabled - environment will remain running"
        log_info "You can manually run tests or inspect services"
        log_info "Press Ctrl+C to stop and cleanup"
        
        # Keep running in debug mode
        while true; do
            sleep 30
            if ! health_check &>/dev/null; then
                log_warning "Health check failed in debug mode"
            fi
        done
    else
        run_tests
    fi
    
    log_success "Integration test suite completed"
}

# Execute main function
main "$@"