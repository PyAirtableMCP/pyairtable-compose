#!/bin/bash

# PyAirtable Service Health Smoke Tests
# Tests detailed service health and readiness

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_FILE="$TEST_RESULTS_DIR/service-health-results.txt"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to test service health endpoint
test_service_health_endpoint() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    local test_name="Health Check: $service_name"
    
    local url="http://localhost:$port$endpoint"
    
    # Get response with detailed information
    local response=$(curl -s --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    
    if [ "$status_code" != "200" ]; then
        print_test_result "FAIL" "$test_name" "HTTP $status_code response from health endpoint"
        return 1
    fi
    
    # Try to parse JSON response
    if command -v jq &> /dev/null && echo "$response" | jq . > /dev/null 2>&1; then
        local health_status=$(echo "$response" | jq -r '.status // empty' 2>/dev/null)
        local version=$(echo "$response" | jq -r '.version // "unknown"' 2>/dev/null)
        local timestamp=$(echo "$response" | jq -r '.timestamp // empty' 2>/dev/null)
        
        case "$health_status" in
            "healthy"|"ok"|"ready")
                print_test_result "PASS" "$test_name" "Service is $health_status (v$version)"
                return 0
                ;;
            "")
                print_test_result "WARN" "$test_name" "Health status not found in response"
                return 1
                ;;
            *)
                print_test_result "FAIL" "$test_name" "Service status: $health_status"
                return 1
                ;;
        esac
    else
        # Non-JSON response, just check if we got content
        if [ -n "$response" ]; then
            print_test_result "PASS" "$test_name" "Service responding (non-JSON response)"
            return 0
        else
            print_test_result "FAIL" "$test_name" "Empty response from health endpoint"
            return 1
        fi
    fi
}

# Function to test service dependencies
test_service_dependencies() {
    local service_name=$1
    local port=$2
    local test_name="Dependencies: $service_name"
    
    local url="http://localhost:$port/health"
    local response=$(curl -s --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    
    if command -v jq &> /dev/null && echo "$response" | jq . > /dev/null 2>&1; then
        local dependencies=$(echo "$response" | jq -r '.dependencies // empty' 2>/dev/null)
        
        if [ -n "$dependencies" ] && [ "$dependencies" != "null" ]; then
            # Check each dependency status
            local dep_count=$(echo "$dependencies" | jq length 2>/dev/null)
            local healthy_deps=0
            
            for ((i=0; i<dep_count; i++)); do
                local dep_name=$(echo "$dependencies" | jq -r ".[$i].name // empty" 2>/dev/null)
                local dep_status=$(echo "$dependencies" | jq -r ".[$i].status // empty" 2>/dev/null)
                
                if [ "$dep_status" = "healthy" ] || [ "$dep_status" = "ok" ]; then
                    healthy_deps=$((healthy_deps + 1))
                fi
            done
            
            if [ $healthy_deps -eq $dep_count ]; then
                print_test_result "PASS" "$test_name" "All $dep_count dependencies healthy"
                return 0
            else
                print_test_result "WARN" "$test_name" "$healthy_deps/$dep_count dependencies healthy"
                return 1
            fi
        else
            print_test_result "INFO" "$test_name" "No dependency information available"
            return 0
        fi
    else
        print_test_result "INFO" "$test_name" "Cannot parse dependency information"
        return 0
    fi
}

# Function to test service metrics
test_service_metrics() {
    local service_name=$1
    local port=$2
    local test_name="Metrics: $service_name"
    
    local url="http://localhost:$port/metrics"
    
    # Try to get metrics (not all services may have this endpoint)
    if curl -s -f --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" > /dev/null 2>&1; then
        print_test_result "PASS" "$test_name" "Metrics endpoint available"
        return 0
    else
        print_test_result "INFO" "$test_name" "Metrics endpoint not available (optional)"
        return 0
    fi
}

# Function to test service response time
test_service_response_time() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    local max_response_time=${4:-$TEST_EXPECTED_RESPONSE_TIME_HEALTH}
    local test_name="Response Time: $service_name"
    
    local url="http://localhost:$port$endpoint"
    
    # Measure response time
    local start_time=$(date +%s%N)
    local response=$(curl -s --connect-timeout 5 --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    local end_time=$(date +%s%N)
    
    local response_time_ns=$((end_time - start_time))
    local response_time_ms=$((response_time_ns / 1000000))
    
    if [ $response_time_ms -le $max_response_time ]; then
        print_test_result "PASS" "$test_name" "Response time: ${response_time_ms}ms (< ${max_response_time}ms)"
        return 0
    else
        print_test_result "WARN" "$test_name" "Response time: ${response_time_ms}ms (> ${max_response_time}ms)"
        return 1
    fi
}

# Function to test service startup time
test_service_startup_time() {
    local service_name=$1
    local port=$2
    local test_name="Startup Time: $service_name"
    
    # Get container start time
    local container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service_name" 2>/dev/null)
    
    if [ -n "$container_id" ]; then
        local start_time=$(docker inspect --format='{{.State.StartedAt}}' "$container_id" 2>/dev/null)
        local current_time=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
        
        if [ -n "$start_time" ]; then
            print_test_result "PASS" "$test_name" "Container started at $start_time"
            return 0
        else
            print_test_result "WARN" "$test_name" "Cannot determine startup time"
            return 1
        fi
    else
        print_test_result "FAIL" "$test_name" "Container not found"
        return 1
    fi
}

# Main test functions
test_core_services_health() {
    print_test_result "INFO" "Test Suite" "Starting core services health tests"
    
    local tests_passed=0
    local tests_total=0
    
    # Core services health checks
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
        if test_service_health_endpoint "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Core services health: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

test_service_dependencies_suite() {
    print_test_result "INFO" "Test Suite" "Starting service dependencies tests"
    
    local tests_passed=0
    local tests_total=0
    
    # Services that may report dependency status
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
        if test_service_dependencies "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Service dependencies: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge $((tests_total / 2)) ] && echo 0 || echo 1)  # Allow 50% pass rate for dependencies
}

test_service_response_times() {
    print_test_result "INFO" "Test Suite" "Starting service response time tests"
    
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
        if test_service_response_time "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Response time tests: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge $((tests_total * 3 / 4)) ] && echo 0 || echo 1)  # Allow 75% pass rate for response times
}

test_service_metrics_suite() {
    print_test_result "INFO" "Test Suite" "Starting service metrics tests"
    
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
        if test_service_metrics "$service" "$port"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Service metrics: $tests_passed/$tests_total available"
    return 0  # Metrics are optional, so always pass
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Service Health Tests" "Starting PyAirtable service health validation"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Initialize results file
    echo "PyAirtable Service Health Test Results" > "$TEST_RESULTS_FILE"
    echo "Started: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$TEST_RESULTS_FILE"
    echo "=====================================" >> "$TEST_RESULTS_FILE"
    
    # Run test suites
    local total_suites=0
    local passed_suites=0
    
    # Test core services health
    total_suites=$((total_suites + 1))
    if test_core_services_health; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test service dependencies
    total_suites=$((total_suites + 1))
    if test_service_dependencies_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test response times
    total_suites=$((total_suites + 1))
    if test_service_response_times; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test metrics availability
    total_suites=$((total_suites + 1))
    if test_service_metrics_suite; then
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
    print_test_result "INFO" "Test Summary" "Service health tests completed in ${duration}s"
    print_test_result "INFO" "Test Summary" "Test suites passed: $passed_suites/$total_suites"
    
    if [ $passed_suites -ge $((total_suites * 3 / 4)) ]; then  # Allow 75% pass rate
        print_test_result "PASS" "Overall Result" "Service health tests passed"
        echo "OVERALL_RESULT=PASS" >> "$TEST_RESULTS_FILE"
        exit 0
    else
        print_test_result "FAIL" "Overall Result" "Service health tests failed"
        echo "OVERALL_RESULT=FAIL" >> "$TEST_RESULTS_FILE"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "PyAirtable Service Health Tests"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --compose-file     Specify docker-compose file (default: docker-compose.minimal.yml)"
        echo "  --quick           Quick test mode (reduced timeouts)"
        echo ""
        exit 0
        ;;
    --compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
    --quick)
        TEST_TIMEOUT=10
        TEST_EXPECTED_RESPONSE_TIME_HEALTH=1000
        shift
        ;;
esac

# Run main function
main "$@"