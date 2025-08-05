#!/bin/bash

# PyAirtable Basic Load Testing Script
# Tests basic performance and concurrent user capacity

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_FILE="$TEST_RESULTS_DIR/performance-results.txt"

# Performance test parameters
CONCURRENT_USERS=${TEST_CONCURRENT_USERS:-5}
REQUEST_DURATION=${TEST_REQUEST_DURATION:-30}
RAMP_UP_TIME=${TEST_RAMP_UP_TIME:-10}

# Performance thresholds
MAX_RESPONSE_TIME=${TEST_MAX_RESPONSE_TIME:-5000}  # ms
MIN_SUCCESS_RATE=${TEST_MIN_SUCCESS_RATE:-95}      # %

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to test single endpoint performance
test_endpoint_performance() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    local test_name="Performance: $service_name"
    
    local url="http://localhost:$port$endpoint"
    local total_requests=10
    local successful_requests=0
    local total_response_time=0
    
    print_test_result "INFO" "$test_name" "Testing $total_requests requests to $endpoint"
    
    for ((i=1; i<=total_requests; i++)); do
        local start_time=$(date +%s%N)
        
        if curl -s -f --max-time $((TEST_TIMEOUT * 2)) "$url" > /dev/null 2>&1; then
            successful_requests=$((successful_requests + 1))
        fi
        
        local end_time=$(date +%s%N)
        local response_time_ns=$((end_time - start_time))
        local response_time_ms=$((response_time_ns / 1000000))
        total_response_time=$((total_response_time + response_time_ms))
        
        # Small delay between requests
        sleep 0.1
    done
    
    local avg_response_time=$((total_response_time / total_requests))
    local success_rate=$((successful_requests * 100 / total_requests))
    
    if [ $success_rate -ge $MIN_SUCCESS_RATE ] && [ $avg_response_time -le $MAX_RESPONSE_TIME ]; then
        print_test_result "PASS" "$test_name" "Success rate: ${success_rate}%, Avg response: ${avg_response_time}ms"
        return 0
    else
        print_test_result "WARN" "$test_name" "Success rate: ${success_rate}%, Avg response: ${avg_response_time}ms"
        return 1
    fi
}

# Function to test concurrent requests
test_concurrent_requests() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    local concurrent_count=${4:-$CONCURRENT_USERS}
    local test_name="Concurrent: $service_name"
    
    local url="http://localhost:$port$endpoint"
    local temp_dir=$(mktemp -d)
    local success_count=0
    
    print_test_result "INFO" "$test_name" "Testing $concurrent_count concurrent requests"
    
    # Launch concurrent requests
    for ((i=1; i<=concurrent_count; i++)); do
        (
            if curl -s -f --max-time $TEST_TIMEOUT "$url" > /dev/null 2>&1; then
                echo "success" > "$temp_dir/result_$i"
            else
                echo "failure" > "$temp_dir/result_$i"
            fi
        ) &
    done
    
    # Wait for all requests to complete
    wait
    
    # Count successful requests
    for ((i=1; i<=concurrent_count; i++)); do
        if [ -f "$temp_dir/result_$i" ] && [ "$(cat "$temp_dir/result_$i")" = "success" ]; then
            success_count=$((success_count + 1))
        fi
    done
    
    # Cleanup
    rm -rf "$temp_dir"
    
    local success_rate=$((success_count * 100 / concurrent_count))
    
    if [ $success_rate -ge $MIN_SUCCESS_RATE ]; then
        print_test_result "PASS" "$test_name" "$success_count/$concurrent_count requests successful (${success_rate}%)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "$success_count/$concurrent_count requests successful (${success_rate}%)"
        return 1
    fi
}

# Function to test chat endpoint performance
test_chat_performance() {
    local test_name="Performance: Chat Endpoint"
    local url="http://localhost:8003/chat"
    local request_count=5
    local successful_requests=0
    local total_response_time=0
    
    print_test_result "INFO" "$test_name" "Testing chat endpoint performance with $request_count requests"
    
    for ((i=1; i<=request_count; i++)); do
        local payload='{
            "message": "Performance test message '$i'",
            "session_id": "perf-test-'$(date +%s)'",
            "base_id": "'$TEST_AIRTABLE_BASE'"
        }'
        
        local start_time=$(date +%s%N)
        
        local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_LONG_TIMEOUT -X POST \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $TEST_API_KEY" \
            -d "$payload" \
            "$url" 2>/dev/null)
        
        local end_time=$(date +%s%N)
        local response_time_ns=$((end_time - start_time))
        local response_time_ms=$((response_time_ns / 1000000))
        total_response_time=$((total_response_time + response_time_ms))
        
        # Consider 200, 400, 422 as "successful" (service responding)
        if [ "$status" = "200" ] || [ "$status" = "400" ] || [ "$status" = "422" ]; then
            successful_requests=$((successful_requests + 1))
        fi
        
        # Delay between chat requests
        sleep 1
    done
    
    local avg_response_time=$((total_response_time / request_count))
    local success_rate=$((successful_requests * 100 / request_count))
    
    if [ $success_rate -ge 80 ] && [ $avg_response_time -le $((MAX_RESPONSE_TIME * 2)) ]; then
        print_test_result "PASS" "$test_name" "Success rate: ${success_rate}%, Avg response: ${avg_response_time}ms"
        return 0
    else
        print_test_result "WARN" "$test_name" "Success rate: ${success_rate}%, Avg response: ${avg_response_time}ms"
        return 1
    fi
}

# Function to monitor resource usage during tests
monitor_resource_usage() {
    local test_name="Resource Monitoring"
    local monitoring_duration=30
    
    print_test_result "INFO" "$test_name" "Monitoring resource usage for ${monitoring_duration}s"
    
    # Start resource monitoring in background
    local temp_file=$(mktemp)
    local monitor_pid
    
    # Monitor Docker stats
    (
        for ((i=1; i<=monitoring_duration; i++)); do
            docker stats --no-stream --format "{{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" >> "$temp_file" 2>/dev/null || true
            sleep 1
        done
    ) &
    monitor_pid=$!
    
    # Generate some load during monitoring
    local load_pids=()
    for ((i=1; i<=3; i++)); do
        (
            for ((j=1; j<=10; j++)); do
                curl -s --max-time 5 "http://localhost:8002/health" > /dev/null 2>&1 || true
                curl -s --max-time 5 "http://localhost:8003/health" > /dev/null 2>&1 || true
                sleep 2
            done
        ) &
        load_pids+=($!)
    done
    
    # Wait for monitoring to complete
    wait $monitor_pid
    
    # Wait for load generation to complete
    for pid in "${load_pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    # Analyze results
    if [ -s "$temp_file" ]; then
        local max_cpu=$(awk -F'\t' 'NR>1 {gsub(/%/, "", $2); if($2+0 > max) max=$2+0} END {print max}' "$temp_file")
        local avg_cpu=$(awk -F'\t' 'NR>1 {gsub(/%/, "", $2); sum+=$2; count++} END {if(count>0) print sum/count; else print 0}' "$temp_file")
        
        print_test_result "PASS" "$test_name" "Max CPU: ${max_cpu:-0}%, Avg CPU: ${avg_cpu:-0}%"
        
        # Cleanup
        rm -f "$temp_file"
        return 0
    else
        print_test_result "WARN" "$test_name" "Could not collect resource data"
        rm -f "$temp_file"
        return 1
    fi
}

# Main test functions
test_basic_performance_suite() {
    print_test_result "INFO" "Test Suite" "Starting basic performance tests"
    
    local tests_passed=0
    local tests_total=5
    
    # Test core service performance
    local services=(
        "airtable-gateway:8002:/health"
        "mcp-server:8001:/health"
        "llm-orchestrator:8003:/health"
        "platform-services:8007:/health"
        "automation-services:8006:/health"
    )
    
    for service_config in "${services[@]}"; do
        local service=$(echo "$service_config" | cut -d: -f1)
        local port=$(echo "$service_config" | cut -d: -f2)
        local endpoint=$(echo "$service_config" | cut -d: -f3)
        
        if test_endpoint_performance "$service" "$port" "$endpoint"; then
            tests_passed=$((tests_passed + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "Basic performance: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge 4 ] && echo 0 || echo 1)  # Require 4/5 to pass
}

test_concurrent_load_suite() {
    print_test_result "INFO" "Test Suite" "Starting concurrent load tests"
    
    local tests_passed=0
    local tests_total=3
    
    # Test concurrent requests on key services
    if test_concurrent_requests "llm-orchestrator" "8003" "/health" 3; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_concurrent_requests "airtable-gateway" "8002" "/health" 3; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_concurrent_requests "platform-services" "8007" "/health" 3; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Concurrent load: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge 2 ] && echo 0 || echo 1)  # Require 2/3 to pass
}

test_chat_performance_suite() {
    print_test_result "INFO" "Test Suite" "Starting chat performance tests"
    
    local tests_passed=0
    local tests_total=1
    
    if test_chat_performance; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Chat performance: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Performance Tests" "Starting PyAirtable performance validation"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Initialize results file
    echo "PyAirtable Performance Test Results" > "$TEST_RESULTS_FILE"
    echo "Started: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$TEST_RESULTS_FILE"
    echo "Concurrent Users: $CONCURRENT_USERS" >> "$TEST_RESULTS_FILE"
    echo "Max Response Time: ${MAX_RESPONSE_TIME}ms" >> "$TEST_RESULTS_FILE"
    echo "Min Success Rate: ${MIN_SUCCESS_RATE}%" >> "$TEST_RESULTS_FILE"
    echo "=====================================" >> "$TEST_RESULTS_FILE"
    
    # Run test suites
    local total_suites=0
    local passed_suites=0
    
    # Test basic performance
    total_suites=$((total_suites + 1))
    if test_basic_performance_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test concurrent load
    total_suites=$((total_suites + 1))
    if test_concurrent_load_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test chat performance
    total_suites=$((total_suites + 1))
    if test_chat_performance_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Monitor resource usage
    total_suites=$((total_suites + 1))
    if monitor_resource_usage; then
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
    print_test_result "INFO" "Test Summary" "Performance tests completed in ${duration}s"
    print_test_result "INFO" "Test Summary" "Test suites passed: $passed_suites/$total_suites"
    
    # Print performance recommendations
    echo ""
    print_test_result "INFO" "Performance Notes" "These are basic load tests with placeholder credentials"
    print_test_result "INFO" "Performance Notes" "Real performance will vary with actual Airtable and Gemini API calls"
    print_test_result "INFO" "Performance Notes" "For production load testing, use tools like k6, JMeter, or Apache Bench"
    
    if [ $passed_suites -ge $((total_suites * 3 / 4)) ]; then  # Allow 75% pass rate
        print_test_result "PASS" "Overall Result" "Performance tests indicate system can handle basic load"
        echo "OVERALL_RESULT=PASS" >> "$TEST_RESULTS_FILE"
        exit 0
    else
        print_test_result "WARN" "Overall Result" "Performance tests indicate potential issues under load"
        echo "OVERALL_RESULT=WARN" >> "$TEST_RESULTS_FILE"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "PyAirtable Performance Tests"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --compose-file     Specify docker-compose file (default: docker-compose.minimal.yml)"
        echo "  --concurrent N     Number of concurrent users (default: 5)"
        echo "  --duration N       Test duration in seconds (default: 30)"
        echo "  --quick           Quick performance test (reduced load)"
        echo ""
        echo "Environment Variables:"
        echo "  TEST_CONCURRENT_USERS    Number of concurrent users"
        echo "  TEST_MAX_RESPONSE_TIME   Maximum acceptable response time (ms)"
        echo "  TEST_MIN_SUCCESS_RATE    Minimum acceptable success rate (%)"
        echo ""
        exit 0
        ;;
    --compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
    --concurrent)
        CONCURRENT_USERS="$2"
        shift 2
        ;;
    --duration)
        REQUEST_DURATION="$2"
        shift 2
        ;;
    --quick)
        CONCURRENT_USERS=2
        REQUEST_DURATION=15
        MAX_RESPONSE_TIME=3000
        shift
        ;;
esac

# Run main function
main "$@"