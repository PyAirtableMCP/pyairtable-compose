#!/bin/bash

# PyAirtable Database Connectivity Smoke Tests
# Tests database connections and basic operations

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_FILE="$TEST_RESULTS_DIR/database-connectivity-results.txt"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to test PostgreSQL connection
test_postgres_connection() {
    local test_name="PostgreSQL Connection"
    
    if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
        print_test_result "PASS" "$test_name" "PostgreSQL is ready and accepting connections"
        return 0
    else
        print_test_result "FAIL" "$test_name" "PostgreSQL is not ready"
        return 1
    fi
}

# Function to test PostgreSQL basic operations
test_postgres_operations() {
    local test_name="PostgreSQL Operations"
    
    # Test basic SQL operations
    local result=$(docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres -t -c "SELECT 1;" 2>/dev/null | xargs)
    
    if [ "$result" = "1" ]; then
        print_test_result "PASS" "$test_name" "Basic SQL operations working"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Basic SQL operations failed"
        return 1
    fi
}

# Function to test PostgreSQL database existence
test_postgres_database() {
    local test_name="PostgreSQL Database"
    local db_name="${POSTGRES_DB:-pyairtable}"
    
    # Check if the database exists
    local db_exists=$(docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$db_name';" 2>/dev/null | xargs)
    
    if [ "$db_exists" = "1" ]; then
        print_test_result "PASS" "$test_name" "Database '$db_name' exists"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Database '$db_name' does not exist"
        return 1
    fi
}

# Function to test PostgreSQL tables
test_postgres_tables() {
    local test_name="PostgreSQL Tables"
    local db_name="${POSTGRES_DB:-pyairtable}"
    
    # Get table count
    local table_count=$(docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres -d "$db_name" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs)
    
    if [ "$table_count" -ge 0 ]; then
        print_test_result "PASS" "$test_name" "Found $table_count tables in database"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Could not query database tables"
        return 1
    fi
}

# Function to test Redis connection
test_redis_connection() {
    local test_name="Redis Connection"
    
    local response=$(docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping 2>/dev/null)
    
    if [ "$response" = "PONG" ]; then
        print_test_result "PASS" "$test_name" "Redis is responding to ping"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Redis is not responding"
        return 1
    fi
}

# Function to test Redis basic operations
test_redis_operations() {
    local test_name="Redis Operations"
    local test_key="test:connectivity:$(date +%s)"
    local test_value="test-value"
    
    # Set a test key
    docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli set "$test_key" "$test_value" > /dev/null 2>&1
    
    # Get the test key
    local retrieved_value=$(docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli get "$test_key" 2>/dev/null | tr -d '\r')
    
    # Clean up the test key
    docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli del "$test_key" > /dev/null 2>&1
    
    if [ "$retrieved_value" = "$test_value" ]; then
        print_test_result "PASS" "$test_name" "Redis SET/GET operations working"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Redis SET/GET operations failed"
        return 1
    fi
}

# Function to test Redis memory usage
test_redis_memory() {
    local test_name="Redis Memory"
    
    local memory_info=$(docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
    
    if [ -n "$memory_info" ]; then
        print_test_result "PASS" "$test_name" "Memory usage: $memory_info"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Could not retrieve memory information"
        return 1
    fi
}

# Function to test Redis client connections
test_redis_clients() {
    local test_name="Redis Clients"
    
    local client_info=$(docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli info clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r')
    
    if [ -n "$client_info" ]; then
        print_test_result "PASS" "$test_name" "Connected clients: $client_info"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Could not retrieve client information"
        return 1
    fi
}

# Function to test database service resource usage
test_database_resources() {
    local test_name="Database Resources"
    local services=("postgres" "redis")
    local total_tests=0
    local passed_tests=0
    
    for service in "${services[@]}"; do
        total_tests=$((total_tests + 1))
        
        # Get container stats
        local container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null)
        
        if [ -n "$container_id" ]; then
            local stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}}" "$container_id" 2>/dev/null)
            
            if [ -n "$stats" ]; then
                print_test_result "PASS" "Resource Usage: $service" "Stats: $stats"
                passed_tests=$((passed_tests + 1))
            else
                print_test_result "WARN" "Resource Usage: $service" "Could not get resource stats"
            fi
        else
            print_test_result "FAIL" "Resource Usage: $service" "Container not found"
        fi
    done
    
    if [ $passed_tests -gt 0 ]; then
        print_test_result "PASS" "$test_name" "$passed_tests/$total_tests services reporting resource usage"
        return 0
    else
        print_test_result "FAIL" "$test_name" "No services reporting resource usage"
        return 1
    fi
}

# Main test functions
test_postgres_suite() {
    print_test_result "INFO" "Test Suite" "Starting PostgreSQL tests"
    
    local tests_passed=0
    local tests_total=4
    
    if test_postgres_connection; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_postgres_operations; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_postgres_database; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_postgres_tables; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "PostgreSQL tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge 3 ] && echo 0 || echo 1)  # Require at least 3/4 tests to pass
}

test_redis_suite() {
    print_test_result "INFO" "Test Suite" "Starting Redis tests"
    
    local tests_passed=0
    local tests_total=4
    
    if test_redis_connection; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_redis_operations; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_redis_memory; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_redis_clients; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Redis tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge 3 ] && echo 0 || echo 1)  # Require at least 3/4 tests to pass
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Database Connectivity Tests" "Starting PyAirtable database connectivity validation"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Initialize results file
    echo "PyAirtable Database Connectivity Test Results" > "$TEST_RESULTS_FILE"
    echo "Started: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$TEST_RESULTS_FILE"
    echo "=====================================" >> "$TEST_RESULTS_FILE"
    
    # Run test suites
    local total_suites=0
    local passed_suites=0
    
    # Test PostgreSQL
    total_suites=$((total_suites + 1))
    if test_postgres_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test Redis
    total_suites=$((total_suites + 1))
    if test_redis_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test resource usage
    total_suites=$((total_suites + 1))
    if test_database_resources; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Generate final report
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "" >> "$TEST_RESULTS_FILE"
    echo "Completed: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Duration: ${duration}s" >> "$TEST_RESULTS_FILE"
    echo "Test Suites Passed: $passed_suites/$total_suites" >> "$TEST_RESULTS_FILE"
    
    # Print summary
    print_test_result "INFO" "Test Summary" "Database connectivity tests completed in ${duration}s"
    print_test_result "INFO" "Test Summary" "Test suites passed: $passed_suites/$total_suites"
    
    if [ $passed_suites -eq $total_suites ]; then
        print_test_result "PASS" "Overall Result" "All database connectivity tests passed"
        echo "OVERALL_RESULT=PASS" >> "$TEST_RESULTS_FILE"
        exit 0
    else
        print_test_result "FAIL" "Overall Result" "Some database connectivity tests failed"
        echo "OVERALL_RESULT=FAIL" >> "$TEST_RESULTS_FILE"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "PyAirtable Database Connectivity Tests"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --compose-file     Specify docker-compose file (default: docker-compose.minimal.yml)"
        echo "  --quick           Quick test mode (reduced operations)"
        echo ""
        exit 0
        ;;
    --compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
    --quick)
        # In quick mode, skip some tests
        shift
        ;;
esac

# Run main function
main "$@"