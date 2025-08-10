#!/bin/bash

# PyAirtable Visual Testing Automation Script
# This script orchestrates the complete visual testing pipeline

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$PROJECT_DIR/frontend-services/tenant-dashboard"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_DIR="$PROJECT_DIR/visual-test-reports"
LOG_FILE="$REPORT_DIR/test-run-$TIMESTAMP.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Create report directory
mkdir -p "$REPORT_DIR"

log "INFO" "Starting PyAirtable Visual Testing Pipeline"
log "INFO" "Report directory: $REPORT_DIR"
log "INFO" "Frontend directory: $FRONTEND_DIR"

# Function to check if a service is running
check_service() {
    local port=$1
    local service_name=$2
    
    if curl -s -I "http://localhost:$port/health" > /dev/null 2>&1 || \
       curl -s -I "http://localhost:$port" > /dev/null 2>&1; then
        log "INFO" "$service_name is running on port $port"
        return 0
    else
        log "WARN" "$service_name is not responding on port $port"
        return 1
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local port=$1
    local service_name=$2
    local timeout=${3:-30}
    local interval=2
    local elapsed=0
    
    log "INFO" "Waiting for $service_name on port $port..."
    
    while [ $elapsed -lt $timeout ]; do
        if check_service $port "$service_name"; then
            log "INFO" "$service_name is ready"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log "DEBUG" "Waiting for $service_name... ($elapsed/${timeout}s)"
    done
    
    log "ERROR" "$service_name did not become ready within ${timeout}s"
    return 1
}

# Function to check backend services health
check_backend_services() {
    log "INFO" "Checking backend services health..."
    
    local services=(
        "8000:API Gateway"
        "8001:MCP Server"
        "8002:Airtable Gateway"
        "8003:LLM Orchestrator"
        "8006:Automation Services"
        "8007:Platform Services"
        "8008:Saga Orchestrator"
    )
    
    local healthy_services=0
    local total_services=${#services[@]}
    
    for service in "${services[@]}"; do
        IFS=':' read -r port name <<< "$service"
        if check_service "$port" "$name"; then
            ((healthy_services++))
        fi
    done
    
    log "INFO" "Backend services health: $healthy_services/$total_services services healthy"
    
    if [ $healthy_services -lt $((total_services / 2)) ]; then
        log "ERROR" "Less than half of backend services are healthy"
        return 1
    fi
    
    return 0
}

# Function to start frontend service if not running
ensure_frontend_running() {
    log "INFO" "Ensuring frontend service is running..."
    
    if check_service 3000 "Frontend"; then
        log "INFO" "Frontend is already running"
        return 0
    fi
    
    log "INFO" "Starting frontend service..."
    cd "$FRONTEND_DIR"
    
    # Check if build exists
    if [ ! -d ".next" ]; then
        log "INFO" "Building frontend application..."
        npm run build
    fi
    
    # Start the service in background
    nohup npm run start > "$REPORT_DIR/frontend-$TIMESTAMP.log" 2>&1 &
    local frontend_pid=$!
    echo $frontend_pid > "$REPORT_DIR/frontend.pid"
    
    # Wait for it to be ready
    if wait_for_service 3000 "Frontend" 60; then
        log "INFO" "Frontend service started successfully (PID: $frontend_pid)"
        return 0
    else
        log "ERROR" "Failed to start frontend service"
        kill $frontend_pid 2>/dev/null || true
        return 1
    fi
}

# Function to run Playwright tests
run_playwright_tests() {
    local test_suite=$1
    local output_name=$2
    
    log "INFO" "Running $test_suite tests..."
    
    cd "$FRONTEND_DIR"
    
    local test_output_dir="$REPORT_DIR/$output_name-$TIMESTAMP"
    mkdir -p "$test_output_dir"
    
    # Run tests with detailed reporting
    if npx playwright test \
        --config=playwright.visual.config.ts \
        --project=chromium-visual \
        --reporter=json:"$test_output_dir/results.json" \
        --reporter=html:"$test_output_dir/html" \
        --reporter=junit:"$test_output_dir/junit.xml" \
        $test_suite > "$test_output_dir/output.log" 2>&1; then
        
        log "INFO" "$test_suite tests completed successfully"
        
        # Generate summary
        local passed_tests=$(grep -o '"pass":[0-9]*' "$test_output_dir/results.json" | head -1 | cut -d':' -f2 || echo "0")
        local failed_tests=$(grep -o '"fail":[0-9]*' "$test_output_dir/results.json" | head -1 | cut -d':' -f2 || echo "0")
        local total_tests=$((passed_tests + failed_tests))
        
        log "INFO" "$test_suite Results: $passed_tests passed, $failed_tests failed, $total_tests total"
        
        return 0
    else
        log "ERROR" "$test_suite tests failed"
        cat "$test_output_dir/output.log" | tail -20 | while read line; do
            log "ERROR" "Test output: $line"
        done
        return 1
    fi
}

# Function to generate comprehensive report
generate_report() {
    log "INFO" "Generating comprehensive test report..."
    
    local report_file="$REPORT_DIR/comprehensive-report-$TIMESTAMP.md"
    
    cat > "$report_file" << EOF
# PyAirtable Visual Testing Report
**Generated:** $(date '+%Y-%m-%d %H:%M:%S')  
**Test Run ID:** $TIMESTAMP

## Executive Summary
This report contains the results of the comprehensive visual testing suite for PyAirtable.

## Service Health Check
EOF
    
    # Add service health to report
    if check_backend_services; then
        echo "✅ Backend services are healthy" >> "$report_file"
    else
        echo "⚠️ Some backend services are not healthy" >> "$report_file"
    fi
    
    if check_service 3000 "Frontend"; then
        echo "✅ Frontend service is running" >> "$report_file"
    else
        echo "❌ Frontend service is not running" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Test Results Summary

### Visual Regression Tests
EOF
    
    # Add test results if they exist
    local visual_results="$REPORT_DIR/visual-regression-$TIMESTAMP/results.json"
    if [ -f "$visual_results" ]; then
        local passed=$(grep -o '"pass":[0-9]*' "$visual_results" | head -1 | cut -d':' -f2 || echo "0")
        local failed=$(grep -o '"fail":[0-9]*' "$visual_results" | head -1 | cut -d':' -f2 || echo "0")
        echo "- Passed: $passed" >> "$report_file"
        echo "- Failed: $failed" >> "$report_file"
    else
        echo "- No results available" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

### Authentication Tests
EOF
    
    local auth_results="$REPORT_DIR/auth-tests-$TIMESTAMP/results.json"
    if [ -f "$auth_results" ]; then
        local passed=$(grep -o '"pass":[0-9]*' "$auth_results" | head -1 | cut -d':' -f2 || echo "0")
        local failed=$(grep -o '"fail":[0-9]*' "$auth_results" | head -1 | cut -d':' -f2 || echo "0")
        echo "- Passed: $passed" >> "$report_file"
        echo "- Failed: $failed" >> "$report_file"
    else
        echo "- No results available" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Artifacts
- **Log File:** \`$LOG_FILE\`
- **Screenshots:** Available in test result directories
- **HTML Reports:** Available in each test suite directory
- **JUnit Results:** Available for CI/CD integration

## Next Steps
1. Review failed tests in HTML reports
2. Update baseline screenshots if UI changes are intentional
3. Fix any critical issues identified
4. Schedule regular test runs

---
Generated by PyAirtable Visual Testing Pipeline
EOF
    
    log "INFO" "Comprehensive report generated: $report_file"
    echo "$report_file"
}

# Function to send metrics to LGTM stack (if available)
send_metrics() {
    local test_results_file="$1"
    local test_suite_name="$2"
    
    if [ ! -f "$test_results_file" ]; then
        log "WARN" "No test results file found for metrics: $test_results_file"
        return 1
    fi
    
    # Extract metrics
    local passed_tests=$(grep -o '"pass":[0-9]*' "$test_results_file" | head -1 | cut -d':' -f2 || echo "0")
    local failed_tests=$(grep -o '"fail":[0-9]*' "$test_results_file" | head -1 | cut -d':' -f2 || echo "0")
    local duration=$(grep -o '"duration":[0-9]*' "$test_results_file" | head -1 | cut -d':' -f2 || echo "0")
    
    # Send to Prometheus pushgateway if available
    if command -v curl > /dev/null && [ -n "${PROMETHEUS_PUSHGATEWAY_URL:-}" ]; then
        log "INFO" "Sending metrics to Prometheus pushgateway..."
        
        cat << EOF | curl -s -X POST "${PROMETHEUS_PUSHGATEWAY_URL}/metrics/job/playwright_tests/instance/$HOSTNAME" --data-binary @-
# HELP playwright_tests_passed Number of passed Playwright tests
# TYPE playwright_tests_passed gauge
playwright_tests_passed{suite="$test_suite_name"} $passed_tests
# HELP playwright_tests_failed Number of failed Playwright tests
# TYPE playwright_tests_failed gauge
playwright_tests_failed{suite="$test_suite_name"} $failed_tests
# HELP playwright_test_duration_ms Duration of Playwright test suite in milliseconds
# TYPE playwright_test_duration_ms gauge
playwright_test_duration_ms{suite="$test_suite_name"} $duration
EOF
        
        if [ $? -eq 0 ]; then
            log "INFO" "Metrics sent successfully"
        else
            log "WARN" "Failed to send metrics to pushgateway"
        fi
    else
        log "DEBUG" "Prometheus pushgateway not configured, skipping metrics"
    fi
    
    # Log structured metrics for potential ingestion by Loki
    log "INFO" "METRICS: suite=$test_suite_name passed=$passed_tests failed=$failed_tests duration_ms=$duration timestamp=$(date +%s)"
}

# Function to cleanup on exit
cleanup() {
    log "INFO" "Cleaning up..."
    
    # Stop frontend if we started it
    if [ -f "$REPORT_DIR/frontend.pid" ]; then
        local frontend_pid=$(cat "$REPORT_DIR/frontend.pid")
        if kill -0 $frontend_pid 2>/dev/null; then
            log "INFO" "Stopping frontend service (PID: $frontend_pid)"
            kill $frontend_pid
        fi
        rm -f "$REPORT_DIR/frontend.pid"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Main execution flow
main() {
    log "INFO" "=== Starting PyAirtable Visual Testing Pipeline ==="
    
    # Check backend services
    if ! check_backend_services; then
        log "WARN" "Backend services are not fully healthy, but continuing with tests"
    fi
    
    # Ensure frontend is running
    if ! ensure_frontend_running; then
        log "ERROR" "Cannot proceed without frontend service"
        exit 1
    fi
    
    # Run visual regression tests
    if run_playwright_tests "visual-regression" "visual-regression"; then
        send_metrics "$REPORT_DIR/visual-regression-$TIMESTAMP/results.json" "visual-regression"
    fi
    
    # Run authentication tests
    if run_playwright_tests "auth-ui-validation" "auth-tests"; then
        send_metrics "$REPORT_DIR/auth-tests-$TIMESTAMP/results.json" "auth-ui-validation"
    fi
    
    # Run Airtable tests
    if run_playwright_tests "airtable-operations" "airtable-tests"; then
        send_metrics "$REPORT_DIR/airtable-tests-$TIMESTAMP/results.json" "airtable-operations"
    fi
    
    # Generate comprehensive report
    local report_file=$(generate_report)
    
    log "INFO" "=== Visual Testing Pipeline Complete ==="
    log "INFO" "Results available in: $REPORT_DIR"
    log "INFO" "Comprehensive report: $report_file"
    
    # Open HTML report if in interactive mode
    if [ -t 1 ] && command -v open > /dev/null; then
        log "INFO" "Opening HTML report in browser..."
        open "$REPORT_DIR/visual-regression-$TIMESTAMP/html/index.html" 2>/dev/null || true
    fi
}

# Run main function
main "$@"