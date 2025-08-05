#!/bin/bash

# PyAirtable Basic Connectivity Smoke Tests
# Tests basic service availability and network connectivity

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_FILE="$TEST_RESULTS_DIR/basic-connectivity-results.txt"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to test port connectivity
test_port_connectivity() {
    local service_name=$1
    local port=$2
    local test_name="Port Connectivity: $service_name:$port"
    
    if nc -z localhost "$port" 2>/dev/null; then
        print_test_result "PASS" "$test_name" "Port $port is open and accepting connections"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Port $port is not accessible"
        return 1
    fi
}

# Function to test HTTP connectivity
test_http_connectivity() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/"}
    local test_name="HTTP Connectivity: $service_name"
    
    local url="http://localhost:$port$endpoint"
    
    if curl -s -f --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" > /dev/null 2>&1; then
        print_test_result "PASS" "$test_name" "HTTP service responding at $url"
        return 0
    else
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" 2>/dev/null || echo "000")
        print_test_result "FAIL" "$test_name" "HTTP service not responding at $url (status: $status_code)"
        return 1
    fi
}

# Function to test database connectivity
test_database_connectivity() {
    local db_type=$1
    local test_name="Database Connectivity: $db_type"
    
    if check_database_connection "$db_type" "$COMPOSE_FILE"; then
        print_test_result "PASS" "$test_name" "$db_type database is accessible"
        return 0
    else
        print_test_result "FAIL" "$test_name" "$db_type database is not accessible"
        return 1
    fi
}

# Function to test container status
test_container_status() {
    local service_name=$1
    local test_name="Container Status: $service_name"
    
    local status=$(get_container_status "$service_name" "$COMPOSE_FILE")
    
    if [ "$status" = "running" ]; then
        local health=$(get_container_health "$service_name" "$COMPOSE_FILE")
        if [ "$health" = "healthy" ] || [ -z "$health" ]; then
            print_test_result "PASS" "$test_name" "Container is running and healthy"
            return 0
        else
            print_test_result "WARN" "$test_name" "Container is running but health status: $health"
            return 1
        fi
    else
        print_test_result "FAIL" "$test_name" "Container status: ${status:-not found}"
        return 1
    fi
}

# Function to test network connectivity between containers
test_internal_network_connectivity() {
    local test_name="Internal Network Connectivity"
    
    # Test if services can reach each other through Docker network
    local network_name=$(docker-compose -f "$COMPOSE_FILE" config | grep -A 5 "networks:" | grep -o "pyairtable-network" | head -1)
    
    if [ -n "$network_name" ]; then
        print_test_result "PASS" "$test_name" "Docker network '$network_name' is configured"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Docker network not found or misconfigured"
        return 1
    fi
}

# Main test functions
test_port_connectivity_suite() {
    print_test_result "INFO" "Test Suite" "Starting port connectivity tests"
    
    local tests_passed=0
    local tests_total=0
    
    # Test core service ports
    for service_port in "airtable-gateway:8002" "mcp-server:8001" "llm-orchestrator:8003" "platform-services:8007" "automation-services:8006"; do
        local service=$(echo $service_port | cut -d: -f1)
        local port=$(echo $service_port | cut -d: -f2)
        
        tests_total=$((tests_total + 1))
        if test_port_connectivity "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Port connectivity tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

test_http_connectivity_suite() {
    print_test_result "INFO" "Test Suite" "Starting HTTP connectivity tests"
    
    local tests_passed=0
    local tests_total=0
    
    # Test HTTP endpoints
    for service_port_endpoint in "airtable-gateway:8002:/health" "mcp-server:8001:/health" "llm-orchestrator:8003:/health" "platform-services:8007:/health" "automation-services:8006:/health"; do
        local service=$(echo $service_port_endpoint | cut -d: -f1)
        local port=$(echo $service_port_endpoint | cut -d: -f2)
        local endpoint=$(echo $service_port_endpoint | cut -d: -f3)
        
        tests_total=$((tests_total + 1))
        if test_http_connectivity "$service" "$port" "$endpoint"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "HTTP connectivity tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

test_database_connectivity_suite() {
    print_test_result "INFO" "Test Suite" "Starting database connectivity tests"
    
    local tests_passed=0
    local tests_total=2
    
    if test_database_connectivity "postgres"; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_database_connectivity "redis"; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Database connectivity tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

test_container_status_suite() {
    print_test_result "INFO" "Test Suite" "Starting container status tests"
    
    local tests_passed=0
    local tests_total=0
    
    # Test container status for all services
    for service in "airtable-gateway" "mcp-server" "llm-orchestrator" "platform-services" "automation-services" "postgres" "redis"; do
        tests_total=$((tests_total + 1))
        if test_container_status "$service"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Container status tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Basic Connectivity Tests" "Starting PyAirtable basic connectivity validation"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Initialize results file
    echo "PyAirtable Basic Connectivity Test Results" > "$TEST_RESULTS_FILE"
    echo "Started: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$TEST_RESULTS_FILE"
    echo "=====================================" >> "$TEST_RESULTS_FILE"
    
    # Run test suites
    local total_suites=0
    local passed_suites=0
    
    # Test network connectivity
    total_suites=$((total_suites + 1))
    if test_internal_network_connectivity; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test container status
    total_suites=$((total_suites + 1))
    if test_container_status_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test port connectivity
    total_suites=$((total_suites + 1))
    if test_port_connectivity_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test HTTP connectivity
    total_suites=$((total_suites + 1))
    if test_http_connectivity_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test database connectivity
    total_suites=$((total_suites + 1))
    if test_database_connectivity_suite; then
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
    print_test_result "INFO" "Test Summary" "Basic connectivity tests completed in ${duration}s"
    print_test_result "INFO" "Test Summary" "Test suites passed: $passed_suites/$total_suites"
    
    if [ $passed_suites -eq $total_suites ]; then
        print_test_result "PASS" "Overall Result" "All basic connectivity tests passed"
        echo "OVERALL_RESULT=PASS" >> "$TEST_RESULTS_FILE"
        exit 0
    else
        print_test_result "FAIL" "Overall Result" "Some basic connectivity tests failed"
        echo "OVERALL_RESULT=FAIL" >> "$TEST_RESULTS_FILE"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "PyAirtable Basic Connectivity Tests"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --compose-file     Specify docker-compose file (default: docker-compose.minimal.yml)"
        echo "  --quick           Quick test mode (reduced timeouts)"
        echo ""
        echo "Environment Variables:"
        echo "  COMPOSE_FILE      Docker compose file to use"
        echo "  TEST_TIMEOUT      Timeout for individual tests (default: 30s)"
        echo ""
        exit 0
        ;;
    --compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
    --quick)
        TEST_TIMEOUT=10
        TEST_RETRY_COUNT=1
        shift
        ;;
esac

# Run main function
main "$@"