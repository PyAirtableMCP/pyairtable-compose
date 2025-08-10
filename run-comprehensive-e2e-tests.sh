#!/bin/bash

# Comprehensive E2E Test Execution Script for PyAirtable Compose
# This script validates all services and runs the complete test suite

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/monitoring/lgtm-stack/synthetic-user-tests"
REPORT_DIR="${SCRIPT_DIR}/e2e-test-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/e2e-test-report-${TIMESTAMP}.json"
SUMMARY_FILE="${REPORT_DIR}/e2e-test-summary-${TIMESTAMP}.txt"

# Test configuration
BASE_URL=${BASE_URL:-"http://localhost:3000"}
HEADLESS=${HEADLESS:-"true"}
WORKERS=${WORKERS:-"3"}
TIMEOUT=${TIMEOUT:-"300000"}
BROWSER=${BROWSER:-"chromium"}

# Service endpoints for validation
declare -A SERVICES=(
    ["frontend"]="http://localhost:3000"
    ["api-gateway"]="http://localhost:8000"
    ["mcp-server"]="http://localhost:8001" 
    ["airtable-gateway"]="http://localhost:8002"
    ["llm-orchestrator"]="http://localhost:8003"
    ["automation-services"]="http://localhost:8006"
    ["platform-services"]="http://localhost:8007"
    ["saga-orchestrator"]="http://localhost:8008"
)

# Test suites to run
declare -A TEST_SUITES=(
    ["infrastructure-health"]="tests/infrastructure/service-health.spec.js"
    ["api-operations"]="tests/api/airtable-operations.spec.js"
    ["authentication"]="tests/auth/authentication-flows.spec.js"
    ["data-flows"]="tests/data-flows/crud-operations.spec.js"
    ["error-handling"]="tests/error-handling/recovery-scenarios.spec.js"
    ["performance"]="tests/performance/benchmark-tests.spec.js"
    ["user-journeys"]="tests/user-journeys/"
    ["error-scenarios"]="tests/error-scenarios/"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

debug() {
    echo -e "${PURPLE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}"
}

# Create report directory
mkdir -p "$REPORT_DIR"

# Initialize test results
declare -A TEST_RESULTS
declare -A SERVICE_STATUS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
START_TIME=$(date +%s)

print_header() {
    echo -e "${CYAN}"
    echo "=============================================================================="
    echo "                    PyAirtable Compose E2E Test Suite"
    echo "=============================================================================="
    echo "Test Execution Started: $(date)"
    echo "Base URL: $BASE_URL"
    echo "Browser: $BROWSER (headless: $HEADLESS)"
    echo "Workers: $WORKERS"
    echo "Timeout: ${TIMEOUT}ms"
    echo "Report Directory: $REPORT_DIR"
    echo "=============================================================================="
    echo -e "${NC}"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Node.js is available
    if ! command -v node &> /dev/null; then
        error "Node.js is required but not installed"
        exit 1
    fi
    
    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        error "npm is required but not installed"
        exit 1
    fi
    
    # Check if Docker is running
    if ! command -v docker &> /dev/null; then
        warn "Docker not found - some services may not be available"
    elif ! docker info &> /dev/null; then
        warn "Docker is not running - some services may not be available"
    fi
    
    # Check if test directory exists
    if [ ! -d "$TEST_DIR" ]; then
        error "Test directory not found: $TEST_DIR"
        exit 1
    fi
    
    log "Prerequisites check completed"
}

validate_services() {
    log "Validating service availability..."
    
    local healthy_services=0
    local total_services=${#SERVICES[@]}
    
    for service_name in "${!SERVICES[@]}"; do
        local service_url="${SERVICES[$service_name]}"
        info "Checking $service_name at $service_url"
        
        if curl -f -s -m 10 "$service_url/health" > /dev/null 2>&1 || \
           curl -f -s -m 10 "$service_url/api/health" > /dev/null 2>&1 || \
           curl -f -s -m 10 "$service_url" > /dev/null 2>&1; then
            SERVICE_STATUS[$service_name]="healthy"
            log "✅ $service_name is healthy"
            ((healthy_services++))
        else
            SERVICE_STATUS[$service_name]="unhealthy"
            warn "❌ $service_name is not responding"
        fi
    done
    
    local health_percentage=$((healthy_services * 100 / total_services))
    
    log "Service Health Summary: $healthy_services/$total_services services healthy ($health_percentage%)"
    
    if [ $healthy_services -lt $((total_services / 2)) ]; then
        error "Less than 50% of services are healthy. Aborting tests."
        exit 1
    elif [ $healthy_services -lt $((total_services * 3 / 4)) ]; then
        warn "Some services are unavailable. Tests may fail."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

setup_test_environment() {
    log "Setting up test environment..."
    
    cd "$TEST_DIR"
    
    # Install dependencies if node_modules doesn't exist
    if [ ! -d "node_modules" ]; then
        info "Installing test dependencies..."
        npm install
    fi
    
    # Install Playwright browsers if not already installed
    info "Ensuring Playwright browsers are available..."
    npx playwright install --with-deps
    
    # Set environment variables for tests
    export BASE_URL="$BASE_URL"
    export HEADLESS="$HEADLESS"
    export WORKERS="$WORKERS"
    export TIMEOUT="$TIMEOUT"
    
    # Load additional environment variables from .env if it exists
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        info "Loading environment variables from .env"
        set -a
        source "${SCRIPT_DIR}/.env"
        set +a
    fi
    
    log "Test environment setup completed"
}

run_test_suite() {
    local suite_name="$1"
    local test_path="$2"
    
    info "Running test suite: $suite_name"
    debug "Test path: $test_path"
    
    local suite_start_time=$(date +%s)
    local test_output_file="${REPORT_DIR}/${suite_name}-output-${TIMESTAMP}.log"
    local test_json_file="${REPORT_DIR}/${suite_name}-results-${TIMESTAMP}.json"
    
    # Run the test suite
    local exit_code=0
    
    npx playwright test "$test_path" \
        --browser="$BROWSER" \
        --workers="$WORKERS" \
        --timeout="$TIMEOUT" \
        --reporter=json:"$test_json_file" \
        --reporter=line \
        > "$test_output_file" 2>&1 || exit_code=$?
    
    local suite_end_time=$(date +%s)
    local suite_duration=$((suite_end_time - suite_start_time))
    
    # Parse results
    local tests_passed=0
    local tests_failed=0
    local tests_skipped=0
    
    if [ -f "$test_json_file" ]; then
        # Parse JSON results if available
        if command -v jq &> /dev/null; then
            tests_passed=$(jq -r '.stats.passed // 0' "$test_json_file")
            tests_failed=$(jq -r '.stats.failed // 0' "$test_json_file")
            tests_skipped=$(jq -r '.stats.skipped // 0' "$test_json_file")
        else
            # Fallback: parse from output log
            tests_passed=$(grep -c "✓" "$test_output_file" 2>/dev/null || echo "0")
            tests_failed=$(grep -c "✗" "$test_output_file" 2>/dev/null || echo "0")
        fi
    else
        # Parse from output log
        tests_passed=$(grep -c "✓" "$test_output_file" 2>/dev/null || echo "0")
        tests_failed=$(grep -c "✗" "$test_output_file" 2>/dev/null || echo "0")
    fi
    
    # Store results
    TEST_RESULTS[$suite_name]="passed:$tests_passed,failed:$tests_failed,skipped:$tests_skipped,duration:$suite_duration,exit_code:$exit_code"
    
    TOTAL_TESTS=$((TOTAL_TESTS + tests_passed + tests_failed))
    PASSED_TESTS=$((PASSED_TESTS + tests_passed))
    FAILED_TESTS=$((FAILED_TESTS + tests_failed))
    
    if [ $exit_code -eq 0 ]; then
        log "✅ $suite_name completed successfully ($tests_passed passed, $tests_failed failed, ${suite_duration}s)"
    else
        warn "❌ $suite_name completed with errors (exit code: $exit_code, $tests_passed passed, $tests_failed failed, ${suite_duration}s)"
    fi
    
    # Show key failures if any
    if [ $tests_failed -gt 0 ]; then
        warn "Failures in $suite_name:"
        grep "✗\|Error:\|Failed:" "$test_output_file" | head -5 | while read -r line; do
            echo "  $line"
        done
        if [ $(grep -c "✗\|Error:\|Failed:" "$test_output_file" 2>/dev/null || echo "0") -gt 5 ]; then
            echo "  ... and more (see $test_output_file for details)"
        fi
    fi
}

run_all_tests() {
    log "Starting comprehensive test suite execution..."
    
    local critical_suites=("infrastructure-health" "api-operations" "authentication")
    local optional_suites=("data-flows" "error-handling" "performance" "user-journeys" "error-scenarios")
    
    # Run critical test suites first
    log "Running critical test suites..."
    for suite in "${critical_suites[@]}"; do
        if [[ ${TEST_SUITES[$suite]+_} ]]; then
            run_test_suite "$suite" "${TEST_SUITES[$suite]}"
            
            # Check if critical test failed
            local result="${TEST_RESULTS[$suite]}"
            local exit_code=$(echo "$result" | sed -n 's/.*exit_code:\([0-9]*\).*/\1/p')
            
            if [ "$exit_code" -ne 0 ]; then
                error "Critical test suite '$suite' failed. Consider stopping here."
                read -p "Continue with remaining tests? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
        fi
    done
    
    # Run optional test suites
    log "Running additional test suites..."
    for suite in "${optional_suites[@]}"; do
        if [[ ${TEST_SUITES[$suite]+_} ]]; then
            run_test_suite "$suite" "${TEST_SUITES[$suite]}"
        fi
    done
    
    log "All test suites completed"
}

generate_comprehensive_report() {
    log "Generating comprehensive test report..."
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local success_rate=0
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    # Generate JSON report
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "execution_time": {
    "start": "$START_TIME",
    "end": "$end_time", 
    "duration_seconds": $total_duration
  },
  "configuration": {
    "base_url": "$BASE_URL",
    "browser": "$BROWSER",
    "headless": $HEADLESS,
    "workers": $WORKERS,
    "timeout": $TIMEOUT
  },
  "services": {
EOF
    
    # Add service status to JSON
    local first_service=true
    for service_name in "${!SERVICE_STATUS[@]}"; do
        if [ "$first_service" = false ]; then
            echo "," >> "$REPORT_FILE"
        fi
        echo "    \"$service_name\": \"${SERVICE_STATUS[$service_name]}\"" >> "$REPORT_FILE"
        first_service=false
    done
    
    cat >> "$REPORT_FILE" <<EOF
  },
  "summary": {
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "success_rate_percentage": $success_rate,
    "total_suites": ${#TEST_RESULTS[@]}
  },
  "test_suites": {
EOF
    
    # Add test results to JSON
    local first_result=true
    for suite_name in "${!TEST_RESULTS[@]}"; do
        if [ "$first_result" = false ]; then
            echo "," >> "$REPORT_FILE"
        fi
        
        local result="${TEST_RESULTS[$suite_name]}"
        local passed=$(echo "$result" | sed -n 's/.*passed:\([0-9]*\).*/\1/p')
        local failed=$(echo "$result" | sed -n 's/.*failed:\([0-9]*\).*/\1/p')
        local skipped=$(echo "$result" | sed -n 's/.*skipped:\([0-9]*\).*/\1/p')
        local duration=$(echo "$result" | sed -n 's/.*duration:\([0-9]*\).*/\1/p')
        local exit_code=$(echo "$result" | sed -n 's/.*exit_code:\([0-9]*\).*/\1/p')
        
        cat >> "$REPORT_FILE" <<EOF
    "$suite_name": {
      "passed": $passed,
      "failed": $failed,
      "skipped": $skipped,
      "duration_seconds": $duration,
      "exit_code": $exit_code,
      "status": "$([ $exit_code -eq 0 ] && echo "success" || echo "failed")"
    }
EOF
        first_result=false
    done
    
    cat >> "$REPORT_FILE" <<EOF
  }
}
EOF
    
    # Generate text summary
    cat > "$SUMMARY_FILE" <<EOF
PyAirtable Compose E2E Test Summary
==================================

Execution Time: $(date)
Duration: $total_duration seconds
Base URL: $BASE_URL
Browser: $BROWSER

Service Health Status:
EOF
    
    for service_name in "${!SERVICE_STATUS[@]}"; do
        local status_icon="❌"
        if [ "${SERVICE_STATUS[$service_name]}" = "healthy" ]; then
            status_icon="✅"
        fi
        echo "  $status_icon $service_name: ${SERVICE_STATUS[$service_name]}" >> "$SUMMARY_FILE"
    done
    
    cat >> "$SUMMARY_FILE" <<EOF

Test Results Summary:
  Total Tests: $TOTAL_TESTS
  Passed: $PASSED_TESTS
  Failed: $FAILED_TESTS
  Success Rate: $success_rate%

Test Suite Results:
EOF
    
    for suite_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$suite_name]}"
        local passed=$(echo "$result" | sed -n 's/.*passed:\([0-9]*\).*/\1/p')
        local failed=$(echo "$result" | sed -n 's/.*failed:\([0-9]*\).*/\1/p')
        local duration=$(echo "$result" | sed -n 's/.*duration:\([0-9]*\).*/\1/p')
        local exit_code=$(echo "$result" | sed -n 's/.*exit_code:\([0-9]*\).*/\1/p')
        
        local status_icon="❌"
        if [ $exit_code -eq 0 ]; then
            status_icon="✅"
        fi
        
        echo "  $status_icon $suite_name: $passed passed, $failed failed (${duration}s)" >> "$SUMMARY_FILE"
    done
    
    cat >> "$SUMMARY_FILE" <<EOF

Recommendations:
EOF
    
    # Generate recommendations based on results
    if [ $success_rate -lt 90 ]; then
        echo "  - Success rate is below 90%. Review failed tests and system stability." >> "$SUMMARY_FILE"
    fi
    
    local unhealthy_services=0
    for status in "${SERVICE_STATUS[@]}"; do
        if [ "$status" != "healthy" ]; then
            ((unhealthy_services++))
        fi
    done
    
    if [ $unhealthy_services -gt 0 ]; then
        echo "  - $unhealthy_services services are unhealthy. Check service logs and configuration." >> "$SUMMARY_FILE"
    fi
    
    if [ $FAILED_TESTS -gt 0 ]; then
        echo "  - Review individual test failures in the detailed logs." >> "$SUMMARY_FILE"
    fi
    
    echo "" >> "$SUMMARY_FILE"
    echo "Detailed logs and reports available in: $REPORT_DIR" >> "$SUMMARY_FILE"
    
    log "Reports generated:"
    info "  JSON Report: $REPORT_FILE"
    info "  Summary: $SUMMARY_FILE"
}

print_final_summary() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    local success_rate=0
    
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi
    
    echo -e "${CYAN}"
    echo "=============================================================================="
    echo "                          E2E Test Execution Complete"
    echo "=============================================================================="
    echo -e "${NC}"
    
    if [ $success_rate -ge 90 ]; then
        log "🎉 Test execution completed successfully!"
        log "   Success Rate: $success_rate% ($PASSED_TESTS/$TOTAL_TESTS)"
        log "   Duration: $total_duration seconds"
    elif [ $success_rate -ge 75 ]; then
        warn "⚠️  Test execution completed with some issues"
        warn "   Success Rate: $success_rate% ($PASSED_TESTS/$TOTAL_TESTS)"
        warn "   Duration: $total_duration seconds"
    else
        error "❌ Test execution completed with significant failures"
        error "   Success Rate: $success_rate% ($PASSED_TESTS/$TOTAL_TESTS)"
        error "   Duration: $total_duration seconds"
    fi
    
    echo
    info "📋 Test Summary:"
    echo "   Total Tests: $TOTAL_TESTS"
    echo "   Passed: $PASSED_TESTS"
    echo "   Failed: $FAILED_TESTS" 
    echo "   Success Rate: $success_rate%"
    echo
    info "📁 Reports Location: $REPORT_DIR"
    echo
    
    # Display the summary file content
    if [ -f "$SUMMARY_FILE" ]; then
        echo -e "${BLUE}--- Test Summary ---${NC}"
        cat "$SUMMARY_FILE"
    fi
    
    # Set exit code based on success rate
    if [ $success_rate -ge 90 ]; then
        exit 0
    elif [ $success_rate -ge 75 ]; then
        exit 1
    else
        exit 2
    fi
}

# Main execution
main() {
    print_header
    check_prerequisites
    validate_services
    setup_test_environment
    
    if run_all_tests; then
        log "Test execution completed"
    else
        warn "Test execution had issues"
    fi
    
    generate_comprehensive_report
    print_final_summary
}

# Handle interruption
trap 'echo -e "\n${RED}Test execution interrupted by user${NC}"; exit 130' INT

# Run main function
main "$@"