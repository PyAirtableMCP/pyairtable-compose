#!/bin/bash

# PyAirtable Synthetic Testing System
# On-demand synthetic tests with human-like behavior and observability integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SUITE="smoke"
ENVIRONMENT="local"
BROWSER="chromium"
HEADLESS="true"
PARALLEL="true"
REPORT_FORMAT="html"
DRY_RUN="false"
TRACE_ENABLED="true"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$SCRIPT_DIR/reports"
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"

# Function to display usage
usage() {
    cat << EOF
PyAirtable Synthetic Testing System

Usage: $0 [OPTIONS]

OPTIONS:
    --suite SUITE           Test suite to run (smoke|regression|full) [default: smoke]
    --env ENVIRONMENT       Target environment (local|staging|production) [default: local]
    --browser BROWSER       Browser to use (chromium|firefox|webkit|all) [default: chromium]
    --headed                Run tests in headed mode (with browser UI)
    --sequential            Run tests sequentially instead of parallel
    --format FORMAT         Report format (html|json|junit|all) [default: html]
    --dry-run               Show what would be executed without running tests
    --no-trace              Disable trace correlation
    --help                  Show this help message

EXAMPLES:
    # Run smoke tests on local environment
    $0 --suite smoke

    # Run full regression suite with headed browser
    $0 --suite regression --headed --browser firefox

    # Run tests sequentially for debugging
    $0 --suite smoke --sequential --headed

    # Dry run to see what would be executed
    $0 --suite full --dry-run

ENVIRONMENT VARIABLES:
    TEST_SESSION_ID         Unique identifier for this test session
    API_KEY                 API key for PyAirtable services
    AIRTABLE_TOKEN         Airtable personal access token
    AIRTABLE_BASE          Airtable base ID for testing

EOF
}

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $timestamp - $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $timestamp - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $timestamp - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message"
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."

    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log ERROR "Node.js is not installed. Please install Node.js 16+ to continue."
        exit 1
    fi

    # Check Node.js version
    local node_version=$(node --version | cut -d'v' -f2)
    local major_version=$(echo $node_version | cut -d'.' -f1)
    if [ "$major_version" -lt 16 ]; then
        log ERROR "Node.js version $node_version is too old. Please upgrade to Node.js 16+."
        exit 1
    fi

    # Check if we're in the right directory
    if [ ! -f "$SCRIPT_DIR/package.json" ]; then
        log ERROR "package.json not found. Make sure you're running this from the synthetic-tests directory."
        exit 1
    fi

    # Check if PyAirtable services are running (for local environment)
    if [ "$ENVIRONMENT" = "local" ]; then
        log INFO "Checking if PyAirtable services are running..."
        
        local services=("3000" "8000" "8001" "8002" "8003" "8006" "8007" "8008")
        local failed_services=()
        
        for port in "${services[@]}"; do
            if ! curl -s "http://localhost:$port/health" >/dev/null 2>&1; then
                failed_services+=("$port")
            fi
        done
        
        if [ ${#failed_services[@]} -gt 0 ]; then
            log WARN "Some services are not responding on ports: ${failed_services[*]}"
            log WARN "Make sure to start PyAirtable services with: cd $PROJECT_ROOT && ./start.sh"
            
            if [ "$DRY_RUN" = "false" ]; then
                read -p "Continue anyway? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 1
                fi
            fi
        fi
    fi

    log SUCCESS "Prerequisites check completed"
}

# Function to setup test environment
setup_test_environment() {
    log INFO "Setting up test environment..."

    # Create directories
    mkdir -p "$REPORTS_DIR" "$SCREENSHOTS_DIR"

    # Generate test session ID if not provided
    if [ -z "${TEST_SESSION_ID:-}" ]; then
        export TEST_SESSION_ID="synthetic-test-$(date +%s)-$$"
        log INFO "Generated TEST_SESSION_ID: $TEST_SESSION_ID"
    fi

    # Set environment variables for tests
    export TEST_ENV="$ENVIRONMENT"
    export PWTEST_SKIP_TEST_OUTPUT=1

    # Install dependencies if needed
    if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
        log INFO "Installing dependencies..."
        cd "$SCRIPT_DIR"
        npm install
        npx playwright install
    fi

    log SUCCESS "Test environment setup completed"
}

# Function to validate test configuration
validate_configuration() {
    log INFO "Validating test configuration..."

    # Check if test config exists
    if [ ! -f "$SCRIPT_DIR/config/test-config.json" ]; then
        log ERROR "Test configuration file not found: config/test-config.json"
        exit 1
    fi

    # Validate suite
    case $SUITE in
        smoke|regression|full)
            ;;
        *)
            log ERROR "Invalid test suite: $SUITE. Valid options: smoke, regression, full"
            exit 1
            ;;
    esac

    # Validate environment
    case $ENVIRONMENT in
        local|staging|production)
            ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT. Valid options: local, staging, production"
            exit 1
            ;;
    esac

    # Validate browser
    case $BROWSER in
        chromium|firefox|webkit|all)
            ;;
        *)
            log ERROR "Invalid browser: $BROWSER. Valid options: chromium, firefox, webkit, all"
            exit 1
            ;;
    esac

    log SUCCESS "Configuration validation completed"
}

# Function to build test command
build_test_command() {
    local cmd="npx playwright test"
    
    # Add config
    cmd="$cmd --config=config/playwright.config.js"
    
    # Add suite filter
    case $SUITE in
        smoke)
            cmd="$cmd --grep=@smoke"
            ;;
        regression)
            cmd="$cmd --grep=@regression|@smoke"
            ;;
        full)
            # No filter for full suite
            ;;
    esac
    
    # Add browser
    if [ "$BROWSER" != "all" ]; then
        cmd="$cmd --project=$BROWSER"
    fi
    
    # Add headless/headed mode
    if [ "$HEADLESS" = "false" ]; then
        cmd="$cmd --headed"
    fi
    
    # Add parallel/sequential
    if [ "$PARALLEL" = "false" ]; then
        cmd="$cmd --workers=1"
    fi
    
    # Add reporter format
    case $REPORT_FORMAT in
        html)
            cmd="$cmd --reporter=html"
            ;;
        json)
            cmd="$cmd --reporter=json"
            ;;
        junit)
            cmd="$cmd --reporter=junit"
            ;;
        all)
            cmd="$cmd --reporter=html,json,junit"
            ;;
    esac
    
    echo "$cmd"
}

# Function to run tests
run_tests() {
    log INFO "Starting synthetic tests..."
    log INFO "Suite: $SUITE"
    log INFO "Environment: $ENVIRONMENT"
    log INFO "Browser: $BROWSER"
    log INFO "Session ID: $TEST_SESSION_ID"

    cd "$SCRIPT_DIR"
    
    local test_cmd=$(build_test_command)
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN - Would execute: $test_cmd"
        return 0
    fi

    log INFO "Executing: $test_cmd"
    
    local start_time=$(date +%s)
    local exit_code=0
    
    # Run the tests
    eval "$test_cmd" || exit_code=$?
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $exit_code -eq 0 ]; then
        log SUCCESS "Tests completed successfully in ${duration}s"
    else
        log ERROR "Tests failed with exit code $exit_code after ${duration}s"
    fi
    
    return $exit_code
}

# Function to generate summary report
generate_summary() {
    log INFO "Generating test summary..."

    local summary_file="$REPORTS_DIR/test-summary-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$summary_file" << EOF
{
    "testSession": "$TEST_SESSION_ID",
    "suite": "$SUITE",
    "environment": "$ENVIRONMENT",
    "browser": "$BROWSER",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "duration": "${duration:-0}",
    "exitCode": "${exit_code:-0}",
    "reportsGenerated": {
        "html": "$REPORTS_DIR/html-report/index.html",
        "json": "$REPORTS_DIR/test-results.json",
        "junit": "$REPORTS_DIR/test-results.xml"
    },
    "screenshots": "$SCREENSHOTS_DIR"
}
EOF

    log INFO "Summary report generated: $summary_file"
    
    # Display quick summary
    echo
    echo "=========================================="
    echo "           TEST SUMMARY"
    echo "=========================================="
    echo "Session ID: $TEST_SESSION_ID"
    echo "Suite: $SUITE"
    echo "Environment: $ENVIRONMENT"
    echo "Browser: $BROWSER"
    echo "Duration: ${duration:-0}s"
    echo "Status: $([ "${exit_code:-0}" -eq 0 ] && echo "PASSED" || echo "FAILED")"
    echo "HTML Report: file://$REPORTS_DIR/html-report/index.html"
    echo "Screenshots: $SCREENSHOTS_DIR"
    echo "=========================================="
}

# Function to cleanup
cleanup() {
    log INFO "Cleaning up..."
    
    # Remove old screenshots (keep last 10 test runs)
    if [ -d "$SCREENSHOTS_DIR" ]; then
        find "$SCREENSHOTS_DIR" -name "*.png" -type f -mtime +7 -delete 2>/dev/null || true
    fi
    
    # Remove old reports (keep last 10 test runs)
    if [ -d "$REPORTS_DIR" ]; then
        find "$REPORTS_DIR" -name "test-summary-*.json" -type f -mtime +7 -delete 2>/dev/null || true
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --suite)
            SUITE="$2"
            shift 2
            ;;
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --browser)
            BROWSER="$2"
            shift 2
            ;;
        --headed)
            HEADLESS="false"
            shift
            ;;
        --sequential)
            PARALLEL="false"
            shift
            ;;
        --format)
            REPORT_FORMAT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --no-trace)
            TRACE_ENABLED="false"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log INFO "PyAirtable Synthetic Testing System starting..."
    
    check_prerequisites
    validate_configuration
    setup_test_environment
    
    # Run tests
    run_tests
    local test_exit_code=$?
    
    # Generate summary regardless of test outcome
    generate_summary
    cleanup
    
    if [ $test_exit_code -eq 0 ]; then
        log SUCCESS "Synthetic testing completed successfully!"
    else
        log ERROR "Synthetic testing failed!"
    fi
    
    exit $test_exit_code
}

# Handle interrupts gracefully
trap 'log WARN "Test execution interrupted"; cleanup; exit 130' INT TERM

# Run main function
main "$@"