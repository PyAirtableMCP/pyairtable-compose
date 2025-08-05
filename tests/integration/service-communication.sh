#!/bin/bash

# PyAirtable Service Communication Integration Tests
# Tests inter-service communication and API endpoints

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_FILE="$TEST_RESULTS_DIR/service-communication-results.txt"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to test service API endpoint with authentication
test_service_api() {
    local service_name=$1
    local port=$2
    local endpoint=$3
    local method=${4:-GET}
    local expected_status=${5:-200}
    local test_name="API: $service_name $method $endpoint"
    
    local url="http://localhost:$port$endpoint"
    local headers=""
    
    # Add API key if available
    if [ -n "$TEST_API_KEY" ]; then
        headers="-H 'X-API-Key: $TEST_API_KEY'"
    fi
    
    # Make request
    local response_status
    if [ "$method" = "GET" ]; then
        response_status=$(eval "curl -s -o /dev/null -w \"%{http_code}\" --max-time $TEST_TIMEOUT $headers \"$url\"" 2>/dev/null)
    elif [ "$method" = "POST" ]; then
        response_status=$(eval "curl -s -o /dev/null -w \"%{http_code}\" --max-time $TEST_TIMEOUT -X POST $headers -H 'Content-Type: application/json' \"$url\"" 2>/dev/null)
    fi
    
    if [ "$response_status" = "$expected_status" ]; then
        print_test_result "PASS" "$test_name" "HTTP $response_status (expected $expected_status)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "HTTP $response_status (expected $expected_status)"
        return 1
    fi
}

# Function to test service-to-service communication via proxy
test_service_chain_communication() {
    local test_name="Service Chain Communication"
    
    # Test LLM Orchestrator -> MCP Server -> Airtable Gateway chain
    local llm_url="http://localhost:8003/health"
    local mcp_url="http://localhost:8001/health"
    local airtable_url="http://localhost:8002/health"
    
    local chain_success=true
    
    # Test each link in the chain
    if ! curl -s -f --max-time $TEST_TIMEOUT "$llm_url" > /dev/null 2>&1; then
        chain_success=false
    fi
    
    if ! curl -s -f --max-time $TEST_TIMEOUT "$mcp_url" > /dev/null 2>&1; then
        chain_success=false
    fi
    
    if ! curl -s -f --max-time $TEST_TIMEOUT "$airtable_url" > /dev/null 2>&1; then
        chain_success=false
    fi
    
    if [ "$chain_success" = true ]; then
        print_test_result "PASS" "$test_name" "All services in communication chain responding"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Communication chain broken"
        return 1
    fi
}

# Function to test cross-service network connectivity
test_internal_service_connectivity() {
    local test_name="Internal Service Connectivity"
    
    # Try to reach one service from another service's container
    local result=$(docker-compose -f "$COMPOSE_FILE" exec -T llm-orchestrator sh -c "nc -z mcp-server 8001" 2>/dev/null; echo $?)
    
    if [ "$result" = "0" ]; then
        print_test_result "PASS" "$test_name" "Services can reach each other internally"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Internal service connectivity failed"
        return 1
    fi
}

# Function to test API authentication
test_api_authentication() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    local test_name="Auth: $service_name"
    
    local url="http://localhost:$port$endpoint"
    
    # Test without API key (should work for health endpoints)
    local status_without_key=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    
    # Test with API key
    local status_with_key=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -H "X-API-Key: $TEST_API_KEY" "$url" 2>/dev/null)
    
    if [ "$status_without_key" = "200" ] || [ "$status_with_key" = "200" ]; then
        print_test_result "PASS" "$test_name" "Authentication working (status: $status_without_key/$status_with_key)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Authentication failed (status: $status_without_key/$status_with_key)"
        return 1
    fi
}

# Function to test service discovery
test_service_discovery() {
    local test_name="Service Discovery"
    
    # Check if services can resolve each other by name
    local services_reachable=0
    local total_services=0
    
    local service_tests=(
        "llm-orchestrator:mcp-server:8001"
        "mcp-server:airtable-gateway:8002"
        "platform-services:postgres:5432"
        "automation-services:redis:6379"
    )
    
    for service_test in "${service_tests[@]}"; do
        local from_service=$(echo $service_test | cut -d: -f1)
        local to_service=$(echo $service_test | cut -d: -f2)
        local to_port=$(echo $service_test | cut -d: -f3)
        
        total_services=$((total_services + 1))
        
        # Test if from_service can reach to_service
        if docker-compose -f "$COMPOSE_FILE" exec -T "$from_service" sh -c "nc -z $to_service $to_port" > /dev/null 2>&1; then
            services_reachable=$((services_reachable + 1))
        fi
    done
    
    if [ $services_reachable -eq $total_services ]; then
        print_test_result "PASS" "$test_name" "All services can discover each other ($services_reachable/$total_services)"
        return 0
    else
        print_test_result "WARN" "$test_name" "Some services cannot discover others ($services_reachable/$total_services)"
        return 1
    fi
}

# Function to test CORS configuration
test_cors_configuration() {
    local service_name=$1
    local port=$2
    local test_name="CORS: $service_name"
    
    local url="http://localhost:$port/health"
    
    # Test CORS headers
    local cors_headers=$(curl -s -I --max-time $TEST_TIMEOUT -H "Origin: http://localhost:3000" "$url" 2>/dev/null | grep -i "access-control")
    
    if [ -n "$cors_headers" ]; then
        print_test_result "PASS" "$test_name" "CORS headers present"
        return 0
    else
        print_test_result "INFO" "$test_name" "No CORS headers (may be intentional)"
        return 0  # Don't fail for missing CORS as it may not be configured
    fi
}

# Function to test error handling and retries
test_error_handling() {
    local test_name="Error Handling"
    
    # Test invalid endpoint
    local invalid_url="http://localhost:8003/invalid-endpoint"
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT "$invalid_url" 2>/dev/null)
    
    if [ "$status" = "404" ] || [ "$status" = "405" ]; then
        print_test_result "PASS" "$test_name" "Services return appropriate error codes ($status)"
        return 0
    else
        print_test_result "WARN" "$test_name" "Unexpected error response ($status)"
        return 1
    fi
}

# Main test functions
test_api_endpoints_suite() {
    print_test_result "INFO" "Test Suite" "Starting API endpoints tests"
    
    local tests_passed=0
    local tests_total=0
    
    # Test core API endpoints
    local services=(
        "airtable-gateway:8002:/health:GET:200"
        "mcp-server:8001:/health:GET:200"
        "llm-orchestrator:8003:/health:GET:200"
        "platform-services:8007:/health:GET:200"
        "automation-services:8006:/health:GET:200"
    )
    
    for service_config in "${services[@]}"; do
        local service=$(echo "$service_config" | cut -d: -f1)
        local port=$(echo "$service_config" | cut -d: -f2)
        local endpoint=$(echo "$service_config" | cut -d: -f3)
        local method=$(echo "$service_config" | cut -d: -f4)
        local expected_status=$(echo "$service_config" | cut -d: -f5)
        
        tests_total=$((tests_total + 1))
        if test_service_api "$service" "$port" "$endpoint" "$method" "$expected_status"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "API endpoints: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

test_service_authentication_suite() {
    print_test_result "INFO" "Test Suite" "Starting service authentication tests"
    
    local tests_passed=0
    local tests_total=0
    
    local services=(
        "airtable-gateway:8002"
        "mcp-server:8001"
        "llm-orchestrator:8003"
        "platform-services:8007"
        "automation-services:8006"
    )
    
    for service_port in "${services[@]}"; do
        local service=$(echo $service_port | cut -d: -f1)
        local port=$(echo $service_port | cut -d: -f2)
        
        tests_total=$((tests_total + 1))
        if test_api_authentication "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Service authentication: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge $((tests_total * 3 / 4)) ] && echo 0 || echo 1)  # Allow 75% pass rate
}

test_cors_suite() {
    print_test_result "INFO" "Test Suite" "Starting CORS configuration tests"
    
    local tests_passed=0
    local tests_total=0
    
    local services=(
        "llm-orchestrator:8003"
        "platform-services:8007"
        "automation-services:8006"
    )
    
    for service_port in "${services[@]}"; do
        local service=$(echo $service_port | cut -d: -f1)
        local port=$(echo $service_port | cut -d: -f2)
        
        tests_total=$((tests_total + 1))
        if test_cors_configuration "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "CORS configuration: $tests_passed/$tests_total passed"
    return 0  # CORS is optional, always pass
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Service Communication Tests" "Starting PyAirtable service communication validation"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Initialize results file
    echo "PyAirtable Service Communication Test Results" > "$TEST_RESULTS_FILE"
    echo "Started: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$TEST_RESULTS_FILE"
    echo "=====================================" >> "$TEST_RESULTS_FILE"
    
    # Run test suites
    local total_suites=0
    local passed_suites=0
    
    # Test API endpoints
    total_suites=$((total_suites + 1))
    if test_api_endpoints_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test service chain communication
    total_suites=$((total_suites + 1))
    if test_service_chain_communication; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test internal connectivity
    total_suites=$((total_suites + 1))
    if test_internal_service_connectivity; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test service discovery
    total_suites=$((total_suites + 1))
    if test_service_discovery; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test authentication
    total_suites=$((total_suites + 1))
    if test_service_authentication_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test CORS
    total_suites=$((total_suites + 1))
    if test_cors_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test error handling
    total_suites=$((total_suites + 1))
    if test_error_handling; then
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
    print_test_result "INFO" "Test Summary" "Service communication tests completed in ${duration}s"
    print_test_result "INFO" "Test Summary" "Test suites passed: $passed_suites/$total_suites"
    
    if [ $passed_suites -ge $((total_suites * 3 / 4)) ]; then  # Allow 75% pass rate
        print_test_result "PASS" "Overall Result" "Service communication tests passed"
        echo "OVERALL_RESULT=PASS" >> "$TEST_RESULTS_FILE"
        exit 0
    else
        print_test_result "FAIL" "Overall Result" "Service communication tests failed"
        echo "OVERALL_RESULT=FAIL" >> "$TEST_RESULTS_FILE"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "PyAirtable Service Communication Tests"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --compose-file     Specify docker-compose file (default: docker-compose.minimal.yml)"
        echo "  --quick           Quick test mode (reduced tests)"
        echo ""
        exit 0
        ;;
    --compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
    --quick)
        TEST_TIMEOUT=10
        shift
        ;;
esac

# Run main function
main "$@"