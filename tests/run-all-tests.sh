#!/bin/bash

# PyAirtable Integration Test Suite Master Script
# Runs all tests in proper sequence with comprehensive reporting

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils/test-helpers.sh"
source "$SCRIPT_DIR/utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_DIR="test-results"
MASTER_RESULTS_FILE="$TEST_RESULTS_DIR/master-test-results.txt"
TEST_SUMMARY_FILE="$TEST_RESULTS_DIR/test-summary.json"

# Test suite configuration
RUN_SMOKE_TESTS=${RUN_SMOKE_TESTS:-true}
RUN_INTEGRATION_TESTS=${RUN_INTEGRATION_TESTS:-true}
RUN_PERFORMANCE_TESTS=${RUN_PERFORMANCE_TESTS:-false}
RUN_SECURITY_TESTS=${RUN_SECURITY_TESTS:-false}

# Test execution options
STOP_ON_FIRST_FAILURE=${STOP_ON_FIRST_FAILURE:-false}
PARALLEL_EXECUTION=${PARALLEL_EXECUTION:-false}
GENERATE_REPORT=${GENERATE_REPORT:-true}

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Test suite definitions
declare -A TEST_SUITES=(
    ["smoke_basic"]="smoke/basic-connectivity.sh"
    ["smoke_health"]="smoke/service-health.sh"
    ["smoke_database"]="smoke/database-connectivity.sh"
    ["integration_communication"]="integration/service-communication.sh"
    ["integration_chat"]="integration/chat-functionality.sh"
)

# Optional test suites
declare -A OPTIONAL_TEST_SUITES=(
    ["performance_load"]="performance/load-test.sh"
    ["security_auth"]="security/auth-validation.sh"
)

# Function to run a single test suite
run_test_suite() {
    local suite_name=$1
    local test_script=$2
    local test_name="Test Suite: $suite_name"
    
    print_test_result "INFO" "$test_name" "Starting test suite"
    
    local start_time=$(date +%s)
    local script_path="$SCRIPT_DIR/$test_script"
    
    # Check if test script exists
    if [ ! -f "$script_path" ]; then
        print_test_result "SKIP" "$test_name" "Test script not found: $test_script"
        return 2  # Return 2 for skipped
    fi
    
    # Check if script is executable
    if [ ! -x "$script_path" ]; then
        chmod +x "$script_path"
    fi
    
    # Run the test suite
    local suite_result=0
    if "$script_path" --compose-file "$COMPOSE_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_test_result "PASS" "$test_name" "Completed successfully in ${duration}s"
        suite_result=0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_test_result "FAIL" "$test_name" "Failed after ${duration}s"
        suite_result=1
    fi
    
    # Log results to master file
    echo "Suite: $suite_name | Result: $([ $suite_result -eq 0 ] && echo "PASS" || echo "FAIL") | Duration: ${duration}s | Timestamp: $(date)" >> "$MASTER_RESULTS_FILE"
    
    return $suite_result
}

# Function to run test suites in sequence
run_sequential_tests() {
    local total_suites=0
    local passed_suites=0
    local failed_suites=0
    local skipped_suites=0
    
    print_test_result "INFO" "Test Execution" "Running tests in sequential mode"
    
    # Run smoke tests if enabled
    if [ "$RUN_SMOKE_TESTS" = "true" ]; then
        print_test_result "INFO" "Test Phase" "Starting smoke tests"
        
        for suite_name in "smoke_basic" "smoke_health" "smoke_database"; do
            if [ -n "${TEST_SUITES[$suite_name]}" ]; then
                total_suites=$((total_suites + 1))
                
                case $(run_test_suite "$suite_name" "${TEST_SUITES[$suite_name]}"; echo $?) in
                    0) passed_suites=$((passed_suites + 1)) ;;
                    1) 
                        failed_suites=$((failed_suites + 1))
                        if [ "$STOP_ON_FIRST_FAILURE" = "true" ]; then
                            print_test_result "FAIL" "Test Execution" "Stopping on first failure as requested"
                            return 1
                        fi
                        ;;
                    2) skipped_suites=$((skipped_suites + 1)) ;;
                esac
            fi
        done
    fi
    
    # Run integration tests if enabled
    if [ "$RUN_INTEGRATION_TESTS" = "true" ]; then
        print_test_result "INFO" "Test Phase" "Starting integration tests"
        
        for suite_name in "integration_communication" "integration_chat"; do
            if [ -n "${TEST_SUITES[$suite_name]}" ]; then
                total_suites=$((total_suites + 1))
                
                case $(run_test_suite "$suite_name" "${TEST_SUITES[$suite_name]}"; echo $?) in
                    0) passed_suites=$((passed_suites + 1)) ;;
                    1) 
                        failed_suites=$((failed_suites + 1))
                        if [ "$STOP_ON_FIRST_FAILURE" = "true" ]; then
                            print_test_result "FAIL" "Test Execution" "Stopping on first failure as requested"
                            return 1
                        fi
                        ;;
                    2) skipped_suites=$((skipped_suites + 1)) ;;
                esac
            fi
        done
    fi
    
    # Run optional tests if enabled
    if [ "$RUN_PERFORMANCE_TESTS" = "true" ] || [ "$RUN_SECURITY_TESTS" = "true" ]; then
        print_test_result "INFO" "Test Phase" "Starting optional tests"
        
        for suite_name in "${!OPTIONAL_TEST_SUITES[@]}"; do
            local should_run=false
            
            case "$suite_name" in
                performance_*) [ "$RUN_PERFORMANCE_TESTS" = "true" ] && should_run=true ;;
                security_*) [ "$RUN_SECURITY_TESTS" = "true" ] && should_run=true ;;
            esac
            
            if [ "$should_run" = "true" ]; then
                total_suites=$((total_suites + 1))
                
                case $(run_test_suite "$suite_name" "${OPTIONAL_TEST_SUITES[$suite_name]}"; echo $?) in
                    0) passed_suites=$((passed_suites + 1)) ;;
                    1) 
                        failed_suites=$((failed_suites + 1))
                        if [ "$STOP_ON_FIRST_FAILURE" = "true" ]; then
                            print_test_result "FAIL" "Test Execution" "Stopping on first failure as requested"
                            return 1
                        fi
                        ;;
                    2) skipped_suites=$((skipped_suites + 1)) ;;
                esac
            fi
        done
    fi
    
    # Return summary
    export TEST_TOTAL_SUITES=$total_suites
    export TEST_PASSED_SUITES=$passed_suites
    export TEST_FAILED_SUITES=$failed_suites
    export TEST_SKIPPED_SUITES=$skipped_suites
    
    return $([ $failed_suites -eq 0 ] && echo 0 || echo 1)
}

# Function to check deployment readiness
check_deployment_readiness() {
    local test_name="Deployment Readiness"
    
    print_test_result "INFO" "$test_name" "Checking deployment prerequisites"
    
    # Check if services are running
    local running_services=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
    local total_services=$(docker-compose -f "$COMPOSE_FILE" config --services | wc -l)
    
    if [ "$running_services" -eq "$total_services" ]; then
        print_test_result "PASS" "$test_name" "All $total_services services are running"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Only $running_services/$total_services services running"
        print_test_result "INFO" "$test_name" "Starting services..."
        
        # Try to start services
        if docker-compose -f "$COMPOSE_FILE" up -d --build; then
            sleep 30  # Wait for services to stabilize
            
            running_services=$(docker-compose -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l)
            if [ "$running_services" -eq "$total_services" ]; then
                print_test_result "PASS" "$test_name" "All services started successfully"
                return 0
            else
                print_test_result "FAIL" "$test_name" "Failed to start all services"
                return 1
            fi
        else
            print_test_result "FAIL" "$test_name" "Failed to start deployment"
            return 1
        fi
    fi
}

# Function to generate test report
generate_test_report() {
    local test_name="Test Report Generation"
    
    if [ "$GENERATE_REPORT" != "true" ]; then
        return 0
    fi
    
    print_test_result "INFO" "$test_name" "Generating comprehensive test report"
    
    # Create JSON summary
    cat > "$TEST_SUMMARY_FILE" << EOF
{
    "test_execution": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "compose_file": "$COMPOSE_FILE",
        "test_environment": "$TEST_ENVIRONMENT",
        "total_suites": $TEST_TOTAL_SUITES,
        "passed_suites": $TEST_PASSED_SUITES,
        "failed_suites": $TEST_FAILED_SUITES,
        "skipped_suites": $TEST_SKIPPED_SUITES,
        "success_rate": $(awk "BEGIN {printf \"%.2f\", ($TEST_PASSED_SUITES / $TEST_TOTAL_SUITES) * 100}")
    },
    "test_configuration": {
        "smoke_tests": $RUN_SMOKE_TESTS,
        "integration_tests": $RUN_INTEGRATION_TESTS,
        "performance_tests": $RUN_PERFORMANCE_TESTS,
        "security_tests": $RUN_SECURITY_TESTS,
        "stop_on_failure": $STOP_ON_FIRST_FAILURE,
        "parallel_execution": $PARALLEL_EXECUTION
    },
    "environment": {
        "test_timeout": $TEST_TIMEOUT,
        "test_retry_count": $TEST_RETRY_COUNT,
        "has_real_credentials": false
    }
}
EOF
    
    # Create human-readable report
    local report_file="$TEST_RESULTS_DIR/test-execution-report.md"
    
    cat > "$report_file" << EOF
# PyAirtable Test Execution Report

## Summary

- **Execution Time**: $(date)
- **Compose File**: $COMPOSE_FILE  
- **Test Environment**: $TEST_ENVIRONMENT
- **Total Test Suites**: $TEST_TOTAL_SUITES
- **Passed**: $TEST_PASSED_SUITES
- **Failed**: $TEST_FAILED_SUITES
- **Skipped**: $TEST_SKIPPED_SUITES
- **Success Rate**: $(awk "BEGIN {printf \"%.1f%%\", ($TEST_PASSED_SUITES / $TEST_TOTAL_SUITES) * 100}")

## Test Configuration

- Smoke Tests: $([ "$RUN_SMOKE_TESTS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")
- Integration Tests: $([ "$RUN_INTEGRATION_TESTS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")
- Performance Tests: $([ "$RUN_PERFORMANCE_TESTS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")
- Security Tests: $([ "$RUN_SECURITY_TESTS" = "true" ] && echo "✅ Enabled" || echo "❌ Disabled")

## Test Results Details

$(cat "$MASTER_RESULTS_FILE" | while read line; do echo "- $line"; done)

## Deployment Status

$(if [ $TEST_FAILED_SUITES -eq 0 ]; then
    echo "🟢 **DEPLOYMENT READY** - All critical tests passed"
elif [ $TEST_FAILED_SUITES -le 2 ]; then
    echo "🟡 **DEPLOYMENT READY WITH NOTES** - Minor issues detected"
else
    echo "🔴 **DEPLOYMENT NOT READY** - Critical issues must be resolved"
fi)

## Next Steps

$(if [ $TEST_FAILED_SUITES -eq 0 ]; then
    echo "1. Deploy to customer environment"
    echo "2. Integrate real customer credentials"
    echo "3. Perform final validation with customer data"
    echo "4. Provide training and documentation"
else
    echo "1. Review failed test results in individual test logs"
    echo "2. Fix identified issues"
    echo "3. Re-run failed test suites"
    echo "4. Validate fixes before deployment"
fi)

---
Generated by PyAirtable Test Suite v1.0
EOF
    
    print_test_result "PASS" "$test_name" "Reports generated in $TEST_RESULTS_DIR/"
    return 0
}

# Function to cleanup test environment
cleanup_test_environment() {
    local test_name="Test Cleanup"
    
    print_test_result "INFO" "$test_name" "Cleaning up test environment"
    
    # Optional: Stop services (commented out for debugging)
    # docker-compose -f "$COMPOSE_FILE" down --volumes --remove-orphans
    
    # Clean up temporary files (keep results)
    find "$TEST_RESULTS_DIR" -name "*.tmp" -delete 2>/dev/null || true
    
    print_test_result "PASS" "$test_name" "Test environment cleaned up"
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Master Test Suite" "Starting PyAirtable comprehensive test validation"
    
    # Initialize master results file
    echo "PyAirtable Master Test Results" > "$MASTER_RESULTS_FILE"
    echo "Started: $(date)" >> "$MASTER_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$MASTER_RESULTS_FILE"
    echo "==========================================" >> "$MASTER_RESULTS_FILE"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Check deployment readiness
    if ! check_deployment_readiness; then
        print_test_result "FAIL" "Test Execution" "Deployment not ready"
        exit 1
    fi
    
    # Wait for services to stabilize
    print_test_result "INFO" "Test Preparation" "Waiting for services to stabilize..."
    sleep 30
    
    # Run test suites
    local test_result=0
    if ! run_sequential_tests; then
        test_result=1
    fi
    
    # Generate final report
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    echo "" >> "$MASTER_RESULTS_FILE"
    echo "Completed: $(date)" >> "$MASTER_RESULTS_FILE"
    echo "Total Duration: ${total_duration}s" >> "$MASTER_RESULTS_FILE"
    echo "Overall Result: $([ $test_result -eq 0 ] && echo "PASS" || echo "FAIL")" >> "$MASTER_RESULTS_FILE"
    
    # Generate comprehensive report
    generate_test_report
    
    # Print final summary
    print_test_result "INFO" "Test Summary" "Master test suite completed in ${total_duration}s"
    print_test_result "INFO" "Test Summary" "Test suites: $TEST_PASSED_SUITES passed, $TEST_FAILED_SUITES failed, $TEST_SKIPPED_SUITES skipped"
    
    if [ $test_result -eq 0 ]; then
        print_test_result "PASS" "Overall Result" "PyAirtable deployment validation successful"
        echo ""
        print_test_result "INFO" "Next Steps" "1. Review test reports in $TEST_RESULTS_DIR/"
        print_test_result "INFO" "Next Steps" "2. Integrate customer credentials"
        print_test_result "INFO" "Next Steps" "3. Run final validation: ./tests/integration/chat-functionality.sh --with-real-creds"
        print_test_result "INFO" "Next Steps" "4. Follow deployment checklist: DEPLOYMENT_VALIDATION_CHECKLIST.md"
    else
        print_test_result "FAIL" "Overall Result" "PyAirtable deployment validation failed"
        echo ""
        print_test_result "INFO" "Troubleshooting" "1. Check individual test logs in $TEST_RESULTS_DIR/"
        print_test_result "INFO" "Troubleshooting" "2. Review service logs: docker-compose logs service-name"
        print_test_result "INFO" "Troubleshooting" "3. Verify environment configuration in .env file"
        print_test_result "INFO" "Troubleshooting" "4. Check deployment guide: CUSTOMER_DEPLOYMENT_GUIDE.md"
    fi
    
    # Cleanup
    cleanup_test_environment
    
    exit $test_result
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "PyAirtable Master Test Suite"
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -h, --help              Show this help message"
            echo "  --compose-file FILE     Docker compose file to use (default: docker-compose.minimal.yml)"
            echo "  --smoke-only            Run only smoke tests"
            echo "  --integration-only      Run only integration tests"
            echo "  --skip-smoke            Skip smoke tests"
            echo "  --skip-integration      Skip integration tests"
            echo "  --include-performance   Include performance tests"
            echo "  --include-security      Include security tests"
            echo "  --stop-on-failure       Stop on first test suite failure"
            echo "  --no-report             Skip report generation"
            echo "  --quick                 Quick test mode (reduced timeouts)"
            echo ""
            echo "Examples:"
            echo "  $0                      # Run all default tests"
            echo "  $0 --smoke-only         # Run only smoke tests"
            echo "  $0 --include-performance # Run with performance tests"
            echo "  $0 --stop-on-failure    # Stop on first failure"
            echo ""
            exit 0
            ;;
        --compose-file)
            COMPOSE_FILE="$2"
            shift 2
            ;;
        --smoke-only)
            RUN_SMOKE_TESTS=true
            RUN_INTEGRATION_TESTS=false
            RUN_PERFORMANCE_TESTS=false
            RUN_SECURITY_TESTS=false
            shift
            ;;
        --integration-only)
            RUN_SMOKE_TESTS=false
            RUN_INTEGRATION_TESTS=true
            RUN_PERFORMANCE_TESTS=false
            RUN_SECURITY_TESTS=false
            shift
            ;;
        --skip-smoke)
            RUN_SMOKE_TESTS=false
            shift
            ;;
        --skip-integration)
            RUN_INTEGRATION_TESTS=false
            shift
            ;;
        --include-performance)
            RUN_PERFORMANCE_TESTS=true
            shift
            ;;
        --include-security)
            RUN_SECURITY_TESTS=true
            shift
            ;;
        --stop-on-failure)
            STOP_ON_FIRST_FAILURE=true
            shift
            ;;
        --no-report)
            GENERATE_REPORT=false
            shift
            ;;
        --quick)
            TEST_TIMEOUT=10
            TEST_LONG_TIMEOUT=30
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"