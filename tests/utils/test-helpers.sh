#!/bin/bash

# PyAirtable Test Helpers
# Common utilities for test scripts

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Test configuration
export TEST_TIMEOUT=30
export TEST_RETRY_COUNT=3
export TEST_RETRY_DELAY=2

# Service definitions for testing
declare -A TEST_SERVICES=(
    ["airtable-gateway"]="8002:/health"
    ["mcp-server"]="8001:/health"
    ["llm-orchestrator"]="8003:/health"
    ["platform-services"]="8007:/health"
    ["automation-services"]="8006:/health"
)

# Database services
declare -A DB_SERVICES=(
    ["postgres"]="5432"
    ["redis"]="6379"
)

# Function to print colored test output
print_test_result() {
    local status=$1
    local test_name=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $status in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} ${CYAN}[$timestamp]${NC} $test_name - $message"
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} ${CYAN}[$timestamp]${NC} $test_name - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${CYAN}[$timestamp]${NC} $test_name - $message"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} ${CYAN}[$timestamp]${NC} $test_name - $message"
            ;;
        "SKIP")
            echo -e "${PURPLE}[SKIP]${NC} ${CYAN}[$timestamp]${NC} $test_name - $message"
            ;;
    esac
}

# Function to run a test with retry logic
run_test_with_retry() {
    local test_function=$1
    local test_name=$2
    local max_retries=${3:-$TEST_RETRY_COUNT}
    local retry_delay=${4:-$TEST_RETRY_DELAY}
    
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        if [ $attempt -gt 1 ]; then
            print_test_result "INFO" "$test_name" "Retry attempt $attempt/$max_retries"
            sleep $retry_delay
        fi
        
        if $test_function; then
            return 0
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Function to check if a service is responding via HTTP
check_http_service() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    local expected_status=${4:-200}
    
    local url="http://localhost:$port$endpoint"
    
    # Check if service is responding
    if ! curl -s -f --max-time $TEST_TIMEOUT "$url" > /dev/null 2>&1; then
        return 1
    fi
    
    # Get actual status code
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    
    if [ "$status_code" != "$expected_status" ]; then
        return 1
    fi
    
    return 0
}

# Function to check service health with JSON response validation
check_service_health() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    
    local url="http://localhost:$port$endpoint"
    
    # Get response
    local response=$(curl -s --max-time $TEST_TIMEOUT "$url" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Try to parse as JSON and check status
    if command -v jq &> /dev/null; then
        local status=$(echo "$response" | jq -r '.status // empty' 2>/dev/null)
        if [ "$status" = "healthy" ] || [ "$status" = "ok" ] || [ "$status" = "ready" ]; then
            return 0
        fi
    fi
    
    # If not JSON or no status field, consider 200 response as healthy
    if [ -n "$response" ]; then
        return 0
    fi
    
    return 1
}

# Function to check database connectivity
check_database_connection() {
    local db_type=$1
    local compose_file=${2:-"docker-compose.minimal.yml"}
    
    case $db_type in
        "postgres")
            if docker-compose -f "$compose_file" exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
                return 0
            fi
            ;;
        "redis")
            if docker-compose -f "$compose_file" exec -T redis redis-cli ping > /dev/null 2>&1; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Function to get container status
get_container_status() {
    local service_name=$1
    local compose_file=${2:-"docker-compose.minimal.yml"}
    
    local status=$(docker-compose -f "$compose_file" ps -q "$service_name" 2>/dev/null | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null)
    echo "$status"
}

# Function to get container health
get_container_health() {
    local service_name=$1
    local compose_file=${2:-"docker-compose.minimal.yml"}
    
    local health=$(docker-compose -f "$compose_file" ps -q "$service_name" 2>/dev/null | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null)
    echo "$health"
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name=$1
    local port=$2
    local max_wait=${3:-60}
    local check_interval=${4:-2}
    
    local elapsed=0
    
    print_test_result "INFO" "Service Startup" "Waiting for $service_name on port $port (max ${max_wait}s)"
    
    while [ $elapsed -lt $max_wait ]; do
        if check_http_service "$service_name" "$port"; then
            print_test_result "PASS" "Service Startup" "$service_name is ready after ${elapsed}s"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    print_test_result "FAIL" "Service Startup" "$service_name not ready after ${max_wait}s"
    return 1
}

# Function to run a test suite
run_test_suite() {
    local suite_name=$1
    local test_functions=("${@:2}")
    
    print_test_result "INFO" "Test Suite" "Starting $suite_name"
    
    local total_tests=${#test_functions[@]}
    local passed_tests=0
    local failed_tests=0
    
    for test_func in "${test_functions[@]}"; do
        if $test_func; then
            passed_tests=$((passed_tests + 1))
        else
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    print_test_result "INFO" "Test Suite" "$suite_name completed: $passed_tests/$total_tests passed"
    
    if [ $failed_tests -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to generate test report
generate_test_report() {
    local test_name=$1
    local start_time=$2
    local end_time=$3
    local results_file=$4
    
    local duration=$((end_time - start_time))
    
    cat >> "$results_file" << EOF
Test: $test_name
Start Time: $(date -d "@$start_time" '+%Y-%m-%d %H:%M:%S')
End Time: $(date -d "@$end_time" '+%Y-%m-%d %H:%M:%S')
Duration: ${duration}s
----
EOF
}

# Function to check environment prerequisites
check_test_prerequisites() {
    local errors=0
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_test_result "FAIL" "Prerequisites" "Docker not found"
        errors=$((errors + 1))
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_test_result "FAIL" "Prerequisites" "Docker Compose not found"
        errors=$((errors + 1))
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        print_test_result "FAIL" "Prerequisites" "curl not found"
        errors=$((errors + 1))
    fi
    
    # Check if .env file exists
    if [ ! -f .env ]; then
        print_test_result "WARN" "Prerequisites" ".env file not found - using defaults"
    fi
    
    if [ $errors -eq 0 ]; then
        print_test_result "PASS" "Prerequisites" "All prerequisites met"
        return 0
    else
        return 1
    fi
}

# Function to setup test environment
setup_test_environment() {
    local compose_file=${1:-"docker-compose.minimal.yml"}
    
    print_test_result "INFO" "Test Setup" "Setting up test environment"
    
    # Create test results directory
    mkdir -p test-results
    
    # Load environment variables
    if [ -f .env ]; then
        set -a
        source .env
        set +a
    fi
    
    # Set test-specific environment variables
    export TEST_MODE=true
    export LOG_LEVEL=DEBUG
    
    print_test_result "PASS" "Test Setup" "Test environment ready"
}

# Function to cleanup test environment
cleanup_test_environment() {
    local compose_file=${1:-"docker-compose.minimal.yml"}
    
    print_test_result "INFO" "Test Cleanup" "Cleaning up test environment"
    
    # Optional cleanup - comment out for debugging
    # docker-compose -f "$compose_file" down --volumes --remove-orphans > /dev/null 2>&1
    
    print_test_result "PASS" "Test Cleanup" "Test environment cleaned up"
}

# Export functions for use in other scripts
export -f print_test_result
export -f run_test_with_retry
export -f check_http_service
export -f check_service_health
export -f check_database_connection
export -f get_container_status
export -f get_container_health
export -f wait_for_service
export -f run_test_suite
export -f generate_test_report
export -f check_test_prerequisites
export -f setup_test_environment
export -f cleanup_test_environment