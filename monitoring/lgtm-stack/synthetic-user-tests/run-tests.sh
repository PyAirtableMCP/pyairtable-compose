#!/bin/bash

# PyAirtable Synthetic User Tests Runner
# Comprehensive test execution script with LGTM monitoring integration

set -e

# Colors for output
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
RESET=$(tput sgr0)

# Default configuration
BASE_URL=${BASE_URL:-"http://localhost:3000"}
BROWSER=${BROWSER:-"chromium"}
ENV=${NODE_ENV:-"test"}
HEADLESS=${HEADLESS:-"true"}
WORKERS=${WORKERS:-"3"}
TIMEOUT=${TIMEOUT:-"300000"}
RETRY=${RETRY:-"2"}
OUTPUT_DIR=${OUTPUT_DIR:-"test-results"}

# LGTM Stack URLs
LOKI_URL=${LOKI_URL:-"http://localhost:3100"}
MIMIR_URL=${MIMIR_URL:-"http://localhost:9009"}
TEMPO_URL=${TEMPO_URL:-"http://localhost:3200"}
GRAFANA_URL=${GRAFANA_URL:-"http://localhost:3000"}

# Test suite selection
TEST_SUITE=${1:-"all"}
AGENT_TYPE=${2:-"all"}

# Function to print colored output
print_status() {
    echo "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${RESET} $1"
}

print_success() {
    echo "${GREEN}✓${RESET} $1"
}

print_error() {
    echo "${RED}✗${RESET} $1"
}

print_warning() {
    echo "${YELLOW}⚠${RESET} $1"
}

print_info() {
    echo "${CYAN}ℹ${RESET} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed"
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        print_error "npm is not installed"
        exit 1
    fi
    
    # Check if Playwright is installed
    if ! npx playwright --version &> /dev/null; then
        print_warning "Playwright not found, installing..."
        npm install
        npx playwright install
    fi
    
    # Check PyAirtable frontend availability
    if ! curl -s "$BASE_URL" > /dev/null 2>&1; then
        print_warning "PyAirtable frontend not available at $BASE_URL"
        print_info "Make sure the frontend is running before starting tests"
    else
        print_success "PyAirtable frontend is available"
    fi
    
    print_success "Prerequisites check completed"
}

# Function to setup test environment
setup_environment() {
    print_status "Setting up test environment..."
    
    # Create necessary directories
    mkdir -p "$OUTPUT_DIR"
    mkdir -p logs
    mkdir -p screenshots
    
    # Set environment variables
    export BASE_URL="$BASE_URL"
    export NODE_ENV="$ENV"
    export LOKI_URL="$LOKI_URL"
    export MIMIR_URL="$MIMIR_URL"
    export TEMPO_URL="$TEMPO_URL"
    
    print_success "Test environment setup completed"
}

# Function to check LGTM stack availability
check_lgtm_stack() {
    print_status "Checking LGTM stack availability..."
    
    # Check Loki
    if curl -s "$LOKI_URL/ready" > /dev/null 2>&1; then
        print_success "Loki is available at $LOKI_URL"
    else
        print_warning "Loki not available at $LOKI_URL"
    fi
    
    # Check Mimir
    if curl -s "$MIMIR_URL/ready" > /dev/null 2>&1; then
        print_success "Mimir is available at $MIMIR_URL"
    else
        print_warning "Mimir not available at $MIMIR_URL"
    fi
    
    # Check Tempo
    if curl -s "$TEMPO_URL/ready" > /dev/null 2>&1; then
        print_success "Tempo is available at $TEMPO_URL"
    else
        print_warning "Tempo not available at $TEMPO_URL"
    fi
    
    # Check Grafana
    if curl -s "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        print_success "Grafana is available at $GRAFANA_URL"
    else
        print_warning "Grafana not available at $GRAFANA_URL"
    fi
}

# Function to run specific test suite
run_test_suite() {
    local suite_name=$1
    local browser_name=$2
    
    print_status "Running test suite: $suite_name on $browser_name"
    
    local test_file=""
    case $suite_name in
        "new-user")
            test_file="tests/user-journeys/new-user-onboarding.spec.js"
            ;;
        "power-user")
            test_file="tests/user-journeys/power-user-workflows.spec.js"
            ;;
        "error-handling")
            test_file="tests/error-scenarios/error-handling.spec.js"
            ;;
        "mobile")
            test_file="tests/mobile/mobile-responsive.spec.js"
            ;;
        "accessibility")
            test_file="tests/accessibility/accessibility.spec.js"
            ;;
        "performance")
            test_file="tests/performance/performance.spec.js"
            ;;
        *)
            print_error "Unknown test suite: $suite_name"
            return 1
            ;;
    esac
    
    local project_name=""
    case $browser_name in
        "chromium")
            project_name="Desktop Chrome"
            ;;
        "firefox")
            project_name="Desktop Firefox"
            ;;
        "webkit")
            project_name="Desktop Safari"
            ;;
        "mobile-chrome")
            project_name="Mobile Chrome"
            ;;
        "mobile-safari")
            project_name="Mobile Safari"
            ;;
        *)
            project_name="Desktop Chrome"
            ;;
    esac
    
    # Run the test
    npx playwright test "$test_file" \
        --project="$project_name" \
        --workers="$WORKERS" \
        --timeout="$TIMEOUT" \
        --retries="$RETRY" \
        --output-dir="$OUTPUT_DIR" \
        --reporter=html,json,./src/reporters/lgtm-reporter.js \
        || return 1
    
    print_success "Test suite $suite_name completed"
}

# Function to run all test suites
run_all_tests() {
    print_status "Running all test suites..."
    
    local suites=("new-user" "power-user" "error-handling" "mobile" "accessibility" "performance")
    local browsers=("chromium")
    
    if [ "$BROWSER" != "chromium" ]; then
        browsers=("$BROWSER")
    fi
    
    local total_suites=$((${#suites[@]} * ${#browsers[@]}))
    local completed_suites=0
    local failed_suites=0
    
    for suite in "${suites[@]}"; do
        for browser in "${browsers[@]}"; do
            if run_test_suite "$suite" "$browser"; then
                ((completed_suites++))
                print_success "Suite $suite ($browser) completed successfully"
            else
                ((failed_suites++))
                print_error "Suite $suite ($browser) failed"
            fi
        done
    done
    
    print_status "Test execution summary:"
    print_info "Total suites: $total_suites"
    print_success "Completed: $completed_suites"
    print_error "Failed: $failed_suites"
    
    if [ $failed_suites -gt 0 ]; then
        return 1
    fi
}

# Function to run orchestrated tests using Node.js orchestrator
run_orchestrated_tests() {
    print_status "Running orchestrated tests with Node.js orchestrator..."
    
    node src/orchestrator/test-orchestrator.js \
        --base-url="$BASE_URL" \
        --browser="$BROWSER" \
        --workers="$WORKERS" \
        --timeout="$TIMEOUT" \
        --output-dir="$OUTPUT_DIR" \
        --suite="$TEST_SUITE" \
        --agent="$AGENT_TYPE"
}

# Function to generate reports
generate_reports() {
    print_status "Generating comprehensive reports..."
    
    # Generate HTML report
    if [ -f "$OUTPUT_DIR/results.json" ]; then
        npx playwright show-report "$OUTPUT_DIR"
    fi
    
    # Generate metrics report
    node -e "
        const MetricsCollector = require('./src/monitoring/metrics-collector');
        const collector = new MetricsCollector();
        collector.generateTestReport('$OUTPUT_DIR').then(() => {
            console.log('✓ Metrics report generated');
        }).catch(err => {
            console.error('✗ Failed to generate metrics report:', err.message);
        });
    "
    
    print_success "Reports generated in $OUTPUT_DIR"
}

# Function to display help
show_help() {
    echo "${WHITE}PyAirtable Synthetic User Tests Runner${RESET}"
    echo ""
    echo "${YELLOW}Usage:${RESET}"
    echo "  $0 [TEST_SUITE] [AGENT_TYPE] [OPTIONS]"
    echo ""
    echo "${YELLOW}Test Suites:${RESET}"
    echo "  all              Run all test suites (default)"
    echo "  new-user         New user onboarding tests"
    echo "  power-user       Advanced power user workflows"
    echo "  error-handling   Error scenarios and recovery"
    echo "  mobile           Mobile and responsive design"
    echo "  accessibility    Accessibility compliance"
    echo "  performance      Performance benchmarking"
    echo ""
    echo "${YELLOW}Agent Types:${RESET}"
    echo "  all              All synthetic user agents (default)"
    echo "  new-user         New user exploration agent"
    echo "  power-user       Advanced workflow agent"
    echo "  error-prone      Error testing agent"
    echo "  mobile           Mobile device agent"
    echo ""
    echo "${YELLOW}Environment Variables:${RESET}"
    echo "  BASE_URL         PyAirtable frontend URL (default: http://localhost:3000)"
    echo "  BROWSER          Browser to use (chromium|firefox|webkit) (default: chromium)"
    echo "  HEADLESS         Run in headless mode (true|false) (default: true)"
    echo "  WORKERS          Number of parallel workers (default: 3)"
    echo "  TIMEOUT          Test timeout in milliseconds (default: 300000)"
    echo "  OUTPUT_DIR       Output directory for results (default: test-results)"
    echo "  LOKI_URL         Loki URL for logs (default: http://localhost:3100)"
    echo "  MIMIR_URL        Mimir URL for metrics (default: http://localhost:9009)"
    echo "  TEMPO_URL        Tempo URL for traces (default: http://localhost:3200)"
    echo ""
    echo "${YELLOW}Examples:${RESET}"
    echo "  $0                           # Run all tests"
    echo "  $0 new-user                  # Run new user tests only"
    echo "  $0 power-user power-user     # Run power user tests with power user agent"
    echo "  BASE_URL=http://prod.example.com $0  # Run against production"
    echo "  BROWSER=firefox $0           # Run tests in Firefox"
    echo "  HEADLESS=false $0 new-user   # Run new user tests with visible browser"
}

# Main execution flow
main() {
    # Print banner
    echo "${MAGENTA}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                PyAirtable Synthetic User Tests                ║"
    echo "║                    LGTM Stack Integration                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo "${RESET}"
    
    # Handle help
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Check LGTM stack
    check_lgtm_stack
    
    # Record start time
    local start_time=$(date +%s)
    
    # Run tests based on suite selection
    case $TEST_SUITE in
        "all")
            if run_all_tests; then
                print_success "All test suites completed successfully"
                exit_code=0
            else
                print_error "Some test suites failed"
                exit_code=1
            fi
            ;;
        "orchestrated")
            if run_orchestrated_tests; then
                print_success "Orchestrated tests completed successfully"
                exit_code=0
            else
                print_error "Orchestrated tests failed"
                exit_code=1
            fi
            ;;
        *)
            if run_test_suite "$TEST_SUITE" "$BROWSER"; then
                print_success "Test suite $TEST_SUITE completed successfully"
                exit_code=0
            else
                print_error "Test suite $TEST_SUITE failed"
                exit_code=1
            fi
            ;;
    esac
    
    # Calculate execution time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    # Generate reports
    generate_reports
    
    # Print final summary
    echo ""
    print_status "Execution completed in ${minutes}m ${seconds}s"
    
    if [ $exit_code -eq 0 ]; then
        print_success "All tests passed! 🎉"
        print_info "View results:"
        print_info "  • HTML Report: file://$PWD/$OUTPUT_DIR/index.html"
        print_info "  • Grafana Dashboard: $GRAFANA_URL"
        print_info "  • Loki Logs: $LOKI_URL"
    else
        print_error "Some tests failed. Check the reports for details."
    fi
    
    exit $exit_code
}

# Run main function with all arguments
main "$@"