#!/bin/bash
# Comprehensive Performance Testing Suite Runner for PyAirtable Platform

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERFORMANCE_DIR="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$PERFORMANCE_DIR/reports"
LOG_FILE="$REPORTS_DIR/performance-suite-$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="${ENVIRONMENT:-development}"
TEST_SUITE="${TEST_SUITE:-all}"
PARALLEL="${PARALLEL:-false}"
MONITORING="${MONITORING:-true}"
CLEANUP="${CLEANUP:-true}"

# Create reports directory
mkdir -p "$REPORTS_DIR"

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Info message
info() {
    log "${BLUE}INFO: $1${NC}"
}

# Help function
show_help() {
    cat << EOF
PyAirtable Performance Testing Suite

Usage: $0 [OPTIONS]

Options:
    -e, --environment ENV     Test environment (development, staging, production)
    -s, --suite SUITE        Test suite to run (smoke, load, stress, soak, database, all)
    -p, --parallel           Run tests in parallel where possible
    -m, --no-monitoring      Disable monitoring stack during tests
    -c, --no-cleanup         Skip cleanup after tests
    -h, --help              Show this help message

Test Suites:
    smoke       - Quick smoke tests (2-5 minutes)
    load        - Standard load tests (10-20 minutes)
    stress      - Stress tests to find breaking points (15-30 minutes)
    soak        - Long-running stability tests (2-4 hours)
    database    - Database performance tests (15-30 minutes)
    all         - Run all test suites sequentially

Examples:
    $0 --environment staging --suite load
    $0 --suite smoke --parallel
    $0 --environment production --suite all --no-cleanup

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--suite)
            TEST_SUITE="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL="true"
            shift
            ;;
        -m|--no-monitoring)
            MONITORING="false"
            shift
            ;;
        -c|--no-cleanup)
            CLEANUP="false"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error_exit "Unknown option $1. Use --help for usage information."
            ;;
    esac
done

# Validate environment
case $ENVIRONMENT in
    development|staging|production)
        ;;
    *)
        error_exit "Invalid environment: $ENVIRONMENT. Must be development, staging, or production."
        ;;
esac

# Validate test suite
case $TEST_SUITE in
    smoke|load|stress|soak|database|all)
        ;;
    *)
        error_exit "Invalid test suite: $TEST_SUITE. Must be smoke, load, stress, soak, database, or all."
        ;;
esac

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is required but not installed"
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error_exit "Docker Compose is required but not installed"
    fi
    
    # Check if PyAirtable network exists
    if ! docker network ls | grep -q pyairtable-network; then
        warning "PyAirtable network not found. Creating it..."
        docker network create pyairtable-network || error_exit "Failed to create PyAirtable network"
    fi
    
    # Check if target services are running
    if [ "$ENVIRONMENT" != "production" ]; then
        if ! docker ps | grep -q api-gateway; then
            warning "API Gateway not running. Starting PyAirtable services..."
            cd "$PERFORMANCE_DIR/.." && docker-compose up -d || error_exit "Failed to start PyAirtable services"
            sleep 30  # Wait for services to be ready
        fi
    fi
    
    success "Prerequisites check completed"
}

# Start monitoring stack
start_monitoring() {
    if [ "$MONITORING" = "true" ]; then
        info "Starting monitoring stack..."
        cd "$PERFORMANCE_DIR"
        
        # Start LGTM stack
        docker-compose -f configs/lgtm-integration.yml up -d || {
            warning "Failed to start monitoring stack, continuing without monitoring"
            MONITORING="false"
        }
        
        if [ "$MONITORING" = "true" ]; then
            # Wait for services to be ready
            sleep 60
            success "Monitoring stack started"
            info "Grafana available at: http://localhost:3000 (admin/performance123)"
            info "Prometheus available at: http://localhost:9090"
        fi
    fi
}

# Stop monitoring stack
stop_monitoring() {
    if [ "$MONITORING" = "true" ]; then
        info "Stopping monitoring stack..."
        cd "$PERFORMANCE_DIR"
        docker-compose -f configs/lgtm-integration.yml down
        success "Monitoring stack stopped"
    fi
}

# Run smoke tests
run_smoke_tests() {
    info "Running smoke tests..."
    
    local start_time=$(date +%s)
    local test_results=()
    
    # K6 API endpoint smoke test
    info "Running K6 API endpoint smoke test..."
    if run_k6_test "k6/api-endpoint-tests.js" "TEST_INTENSITY=light" "smoke-api-endpoints"; then
        test_results+=("✓ K6 API Endpoints")
    else
        test_results+=("✗ K6 API Endpoints")
    fi
    
    # Quick health check test
    info "Running health check test..."
    if run_health_check_test; then
        test_results+=("✓ Health Check")
    else
        test_results+=("✗ Health Check")
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "\n${BLUE}=== SMOKE TESTS SUMMARY ===${NC}"
    for result in "${test_results[@]}"; do
        log "$result"
    done
    log "Duration: ${duration}s"
    log "================================\n"
}

# Run load tests
run_load_tests() {
    info "Running load tests..."
    
    local start_time=$(date +%s)
    local test_results=()
    
    if [ "$PARALLEL" = "true" ]; then
        info "Running load tests in parallel..."
        
        # Start K6 load test in background
        run_k6_test "k6-load-tests.js" "K6_SCENARIO=load_test" "load-k6" &
        local k6_pid=$!
        
        # Start Locust test in background
        run_locust_test "locust/locustfile.py" "50" "10m" "load-locust" &
        local locust_pid=$!
        
        # Wait for both tests to complete
        wait $k6_pid && test_results+=("✓ K6 Load Test") || test_results+=("✗ K6 Load Test")
        wait $locust_pid && test_results+=("✓ Locust Load Test") || test_results+=("✗ Locust Load Test")
        
    else
        info "Running load tests sequentially..."
        
        # K6 load test
        if run_k6_test "k6-load-tests.js" "K6_SCENARIO=load_test" "load-k6"; then
            test_results+=("✓ K6 Load Test")
        else
            test_results+=("✗ K6 Load Test")
        fi
        
        # Locust load test
        if run_locust_test "locust/locustfile.py" "50" "10m" "load-locust"; then
            test_results+=("✓ Locust Load Test")
        else
            test_results+=("✗ Locust Load Test")
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "\n${BLUE}=== LOAD TESTS SUMMARY ===${NC}"
    for result in "${test_results[@]}"; do
        log "$result"
    done
    log "Duration: ${duration}s"
    log "==============================\n"
}

# Run stress tests
run_stress_tests() {
    info "Running stress tests..."
    
    local start_time=$(date +%s)
    local test_results=()
    
    # K6 stress test
    if run_k6_test "stress-tests/k6-stress-scenarios.js" "STRESS_LEVEL=high" "stress-k6"; then
        test_results+=("✓ K6 Stress Test")
    else
        test_results+=("✗ K6 Stress Test")
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "\n${BLUE}=== STRESS TESTS SUMMARY ===${NC}"
    for result in "${test_results[@]}"; do
        log "$result"
    done
    log "Duration: ${duration}s"
    log "===============================\n"
}

# Run soak tests
run_soak_tests() {
    info "Running soak tests (this will take several hours)..."
    
    local start_time=$(date +%s)
    local test_results=()
    
    # K6 soak test
    if run_k6_test "soak-tests/k6-soak-test.js" "SOAK_DURATION=2h,BASELINE_USERS=30" "soak-k6"; then
        test_results+=("✓ K6 Soak Test")
    else
        test_results+=("✗ K6 Soak Test")
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "\n${BLUE}=== SOAK TESTS SUMMARY ===${NC}"
    for result in "${test_results[@]}"; do
        log "$result"
    done
    log "Duration: ${duration}s"
    log "============================\n"
}

# Run database tests
run_database_tests() {
    info "Running database performance tests..."
    
    local start_time=$(date +%s)
    local test_results=()
    
    # K6 database performance test
    if run_k6_test "k6/database-performance-tests.js" "DB_TEST_MODE=comprehensive" "database-k6"; then
        test_results+=("✓ K6 Database Test")
    else
        test_results+=("✗ K6 Database Test")
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "\n${BLUE}=== DATABASE TESTS SUMMARY ===${NC}"
    for result in "${test_results[@]}"; do
        log "$result"
    done
    log "Duration: ${duration}s"
    log "================================\n"
}

# Run K6 test
run_k6_test() {
    local script="$1"
    local env_vars="$2"
    local test_name="$3"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="$REPORTS_DIR/${test_name}-${timestamp}.json"
    
    # Build environment variables
    local env_args=""
    IFS=',' read -ra ENV_ARRAY <<< "$env_vars"
    for env_var in "${ENV_ARRAY[@]}"; do
        env_args="$env_args -e $env_var"
    done
    
    # Run K6 test
    docker run --rm \
        --network pyairtable-network \
        -v "$PERFORMANCE_DIR:/scripts:ro" \
        -v "$REPORTS_DIR:/reports:rw" \
        -e "BASE_URL=http://api-gateway:8000" \
        -e "ENVIRONMENT=$ENVIRONMENT" \
        $env_args \
        grafana/k6:latest \
        run \
        --out "json=/reports/$(basename "$output_file")" \
        "/scripts/$script" 2>&1 | tee -a "$LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        success "K6 test completed: $test_name"
        return 0
    else
        warning "K6 test failed: $test_name (exit code: $exit_code)"
        return 1
    fi
}

# Run Locust test
run_locust_test() {
    local script="$1"
    local users="$2"
    local duration="$3"
    local test_name="$4"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Run Locust test
    docker run --rm \
        --network pyairtable-network \
        -v "$PERFORMANCE_DIR/locust:/mnt/locust:ro" \
        -v "$REPORTS_DIR:/reports:rw" \
        -e "BASE_URL=http://api-gateway:8000" \
        -e "ENVIRONMENT=$ENVIRONMENT" \
        locustio/locust:latest \
        locust \
        -f "/mnt/locust/$(basename "$script")" \
        --headless \
        --users "$users" \
        --spawn-rate 10 \
        --run-time "$duration" \
        --host "http://api-gateway:8000" \
        --html "/reports/${test_name}-${timestamp}-report.html" \
        --csv "/reports/${test_name}-${timestamp}" 2>&1 | tee -a "$LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        success "Locust test completed: $test_name"
        return 0
    else
        warning "Locust test failed: $test_name (exit code: $exit_code)"
        return 1
    fi
}

# Run health check test
run_health_check_test() {
    local base_url="http://localhost:8000"
    if [ "$ENVIRONMENT" = "production" ]; then
        base_url="https://api.pyairtable.com"
    fi
    
    info "Testing health endpoint: $base_url/api/health"
    
    # Test health endpoint
    local response=$(curl -s -w "%{http_code}" -o /tmp/health_response "$base_url/api/health" || echo "000")
    
    if [ "$response" = "200" ]; then
        success "Health check passed"
        return 0
    else
        warning "Health check failed (HTTP $response)"
        if [ -f /tmp/health_response ]; then
            log "Response: $(cat /tmp/health_response)"
        fi
        return 1
    fi
}

# Generate comprehensive report
generate_comprehensive_report() {
    info "Generating comprehensive performance report..."
    
    local report_file="$REPORTS_DIR/comprehensive-report-$(date +%Y%m%d_%H%M%S).html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PyAirtable Performance Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .metric { text-align: center; padding: 10px; background-color: #e9ecef; border-radius: 5px; }
        .test-results { margin: 20px 0; }
        .test-result { margin: 10px 0; padding: 10px; border-left: 4px solid #007bff; background-color: #f8f9fa; }
        .passed { border-left-color: #28a745; }
        .failed { border-left-color: #dc3545; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>PyAirtable Performance Test Report</h1>
        <p><strong>Environment:</strong> $ENVIRONMENT</p>
        <p><strong>Test Suite:</strong> $TEST_SUITE</p>
        <p><strong>Execution Time:</strong> $(date)</p>
        <p><strong>Parallel Execution:</strong> $PARALLEL</p>
        <p><strong>Monitoring Enabled:</strong> $MONITORING</p>
    </div>
    
    <h2>Test Artifacts</h2>
    <ul>
$(find "$REPORTS_DIR" -name "*.json" -o -name "*.html" -o -name "*.csv" | head -20 | while read file; do echo "        <li><a href=\"$(basename "$file")\">$(basename "$file")</a></li>"; done)
    </ul>
    
    <h2>Log Output</h2>
    <pre>
$(tail -100 "$LOG_FILE" | sed 's/\x1b\[[0-9;]*m//g')
    </pre>
</body>
</html>
EOF
    
    success "Comprehensive report generated: $report_file"
}

# Cleanup function
cleanup_resources() {
    if [ "$CLEANUP" = "true" ]; then
        info "Cleaning up resources..."
        
        # Stop any running test containers
        docker ps -q --filter "ancestor=grafana/k6:latest" | xargs -r docker stop
        docker ps -q --filter "ancestor=locustio/locust:latest" | xargs -r docker stop
        docker ps -q --filter "ancestor=justb4/jmeter:latest" | xargs -r docker stop
        
        # Clean up old report files (keep last 10)
        find "$REPORTS_DIR" -name "*.json" -o -name "*.html" -o -name "*.csv" | sort -r | tail -n +11 | xargs -r rm
        
        success "Cleanup completed"
    fi
}

# Main execution function
main() {
    log "${BLUE}Starting PyAirtable Performance Testing Suite${NC}"
    log "Environment: $ENVIRONMENT"
    log "Test Suite: $TEST_SUITE"
    log "Parallel: $PARALLEL"
    log "Monitoring: $MONITORING"
    log "Cleanup: $CLEANUP"
    log ""
    
    # Setup
    check_prerequisites
    start_monitoring
    
    local overall_start=$(date +%s)
    local test_success=true
    
    # Run tests based on suite selection
    case $TEST_SUITE in
        smoke)
            run_smoke_tests || test_success=false
            ;;
        load)
            run_load_tests || test_success=false
            ;;
        stress)
            run_stress_tests || test_success=false
            ;;
        soak)
            run_soak_tests || test_success=false
            ;;
        database)
            run_database_tests || test_success=false
            ;;
        all)
            run_smoke_tests || test_success=false
            run_load_tests || test_success=false
            run_database_tests || test_success=false
            run_stress_tests || test_success=false
            # Skip soak tests in 'all' suite by default (too long)
            warning "Skipping soak tests in 'all' suite (run separately if needed)"
            ;;
    esac
    
    local overall_end=$(date +%s)
    local total_duration=$((overall_end - overall_start))
    
    # Generate reports
    generate_comprehensive_report
    
    # Cleanup
    stop_monitoring
    cleanup_resources
    
    # Final summary
    log "\n${BLUE}=== FINAL SUMMARY ===${NC}"
    log "Total Duration: ${total_duration}s"
    log "Environment: $ENVIRONMENT"
    log "Test Suite: $TEST_SUITE"
    
    if [ "$test_success" = "true" ]; then
        success "All tests completed successfully!"
        log "Reports available in: $REPORTS_DIR"
        exit 0
    else
        warning "Some tests failed. Check the logs and reports for details."
        log "Reports available in: $REPORTS_DIR"
        exit 1
    fi
}

# Trap for cleanup on exit
trap 'cleanup_resources; stop_monitoring' EXIT

# Run main function
main "$@"