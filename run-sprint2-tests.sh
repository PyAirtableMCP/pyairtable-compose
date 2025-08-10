#!/bin/bash
# Sprint 2 Test Execution Script
# ==============================
# 
# This script orchestrates the complete Sprint 2 test suite execution
# including setup, automated tests, and reporting.
#
# Usage: ./run-sprint2-tests.sh [options]
# Options:
#   --automated-only    Run only automated tests
#   --manual-only      Generate only manual test guidance
#   --skip-setup       Skip environment setup
#   --verbose          Enable verbose logging

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/tests"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="sprint2_test_execution_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}INFO:${NC} $1"
}

log_warn() {
    log "${YELLOW}WARN:${NC} $1"
}

log_error() {
    log "${RED}ERROR:${NC} $1"
}

log_success() {
    log "${GREEN}SUCCESS:${NC} $1"
}

# Parse command line arguments
AUTOMATED_ONLY=false
MANUAL_ONLY=false  
SKIP_SETUP=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --automated-only)
            AUTOMATED_ONLY=true
            shift
            ;;
        --manual-only)
            MANUAL_ONLY=true
            shift
            ;;
        --skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Sprint 2 Test Execution Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --automated-only    Run only automated tests"
            echo "  --manual-only      Generate only manual test guidance"
            echo "  --skip-setup       Skip environment setup"
            echo "  --verbose          Enable verbose logging"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check service health
check_service_health() {
    local service_name=$1
    local port=$2
    local max_attempts=5
    local attempt=1
    
    log_info "Checking $service_name (port $port)..."
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z localhost $port 2>/dev/null; then
            # Port is open, now check HTTP health endpoint
            if curl -s -f "http://localhost:$port/health" >/dev/null 2>&1; then
                log_success "$service_name is healthy"
                return 0
            elif curl -s "http://localhost:$port" >/dev/null 2>&1; then
                log_warn "$service_name is responding but health endpoint not available"
                return 0
            fi
        fi
        
        log_warn "$service_name not ready (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log_error "$service_name is not responding after $max_attempts attempts"
    return 1
}

# Function to setup test environment
setup_test_environment() {
    if [ "$SKIP_SETUP" = true ]; then
        log_info "Skipping environment setup as requested"
        return 0
    fi
    
    log_info "Setting up test environment..."
    
    # Check required commands
    local required_commands=("python3" "pip3" "docker" "docker-compose" "curl" "nc")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-compose.dev.yml" ]; then
        log_error "Docker compose file not found. Please run from project root directory."
        exit 1
    fi
    
    # Install Python dependencies for testing
    if [ ! -d "tests/venv" ]; then
        log_info "Creating Python virtual environment for testing..."
        python3 -m venv tests/venv
    fi
    
    log_info "Installing test dependencies..."
    source tests/venv/bin/activate
    pip install --upgrade pip
    
    if [ -f "tests/requirements.txt" ]; then
        pip install -r tests/requirements.txt
    else
        log_warn "tests/requirements.txt not found, installing basic dependencies..."
        pip install pytest pytest-asyncio aiohttp playwright websockets
    fi
    
    # Install Playwright browsers
    log_info "Installing Playwright browsers..."
    playwright install chromium
    
    log_success "Test environment setup completed"
}

# Function to check Sprint 2 services
check_sprint2_services() {
    log_info "Checking Sprint 2 services..."
    
    local services_healthy=true
    
    # Define services and their ports
    declare -A services=(
        ["Chat UI"]="3001"
        ["API Gateway"]="8000" 
        ["Airtable Gateway"]="8002"
        ["MCP Server"]="8001"
        ["LLM Orchestrator"]="8003"
    )
    
    # Check each service
    for service in "${!services[@]}"; do
        if ! check_service_health "$service" "${services[$service]}"; then
            services_healthy=false
        fi
    done
    
    if [ "$services_healthy" = false ]; then
        log_error "Some services are not healthy. Please start all Sprint 2 services before running tests."
        log_info "You can start services with: docker-compose up -d"
        return 1
    fi
    
    log_success "All Sprint 2 services are healthy"
    return 0
}

# Function to run automated tests
run_automated_tests() {
    log_info "Running automated E2E test suite..."
    
    source tests/venv/bin/activate
    cd "$TEST_DIR"
    
    # Run the comprehensive test runner
    if [ "$VERBOSE" = true ]; then
        python3 sprint2-e2e-test-suite.py
    else
        python3 sprint2-e2e-test-suite.py 2>&1 | tee -a "../$LOG_FILE"
    fi
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Automated tests completed successfully"
    else
        log_error "Automated tests failed with exit code $exit_code"
    fi
    
    cd "$SCRIPT_DIR"
    return $exit_code
}

# Function to generate manual test guidance
generate_manual_test_guidance() {
    log_info "Generating manual test guidance..."
    
    source tests/venv/bin/activate
    cd "$TEST_DIR"
    
    if [ "$VERBOSE" = true ]; then
        python3 sprint2-manual-test-scenarios.py
    else
        python3 sprint2-manual-test-scenarios.py 2>&1 | tee -a "../$LOG_FILE"
    fi
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Manual test guidance generated successfully"
    else
        log_error "Manual test guidance generation failed with exit code $exit_code"
    fi
    
    cd "$SCRIPT_DIR"
    return $exit_code
}

# Function to run comprehensive test suite
run_comprehensive_tests() {
    log_info "Running comprehensive test suite..."
    
    source tests/venv/bin/activate
    cd "$TEST_DIR"
    
    if [ "$VERBOSE" = true ]; then
        python3 sprint2-comprehensive-test-runner.py
    else
        python3 sprint2-comprehensive-test-runner.py 2>&1 | tee -a "../$LOG_FILE"
    fi
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Comprehensive test suite completed successfully"
    else
        log_error "Comprehensive test suite failed with exit code $exit_code"
    fi
    
    cd "$SCRIPT_DIR"
    return $exit_code
}

# Function to display results summary
display_results_summary() {
    log_info "Test execution completed. Generating summary..."
    
    # Find the latest test results
    local latest_report=$(ls -t sprint2_*_comprehensive_test_report_*.json 2>/dev/null | head -n1)
    local latest_deliverables=$(ls -td sprint2_test_deliverables_* 2>/dev/null | head -n1)
    
    echo ""
    echo "=================================================================="
    echo "                    SPRINT 2 TEST EXECUTION SUMMARY"
    echo "=================================================================="
    echo ""
    
    if [ -f "$latest_report" ]; then
        log_info "Latest test report: $latest_report"
        
        # Extract key metrics using jq if available
        if command_exists jq; then
            local total_tests=$(jq -r '.automated_tests.test_execution.total_tests // 0' "$latest_report")
            local passed_tests=$(jq -r '.automated_tests.test_execution.passed // 0' "$latest_report")
            local failed_tests=$(jq -r '.automated_tests.test_execution.failed // 0' "$latest_report")
            local pass_rate=$(jq -r '.automated_tests.test_execution.pass_rate // 0' "$latest_report")
            local overall_readiness=$(jq -r '.final_assessment.overall_readiness // "UNKNOWN"' "$latest_report" 2>/dev/null || echo "UNKNOWN")
            
            echo "Automated Tests:"
            echo "  Total: $total_tests"
            echo "  Passed: $passed_tests"  
            echo "  Failed: $failed_tests"
            echo "  Pass Rate: $pass_rate%"
            echo ""
            echo "Overall Readiness: $overall_readiness"
        fi
    else
        log_warn "No test report found"
    fi
    
    if [ -d "$latest_deliverables" ]; then
        log_info "Test deliverables created in: $latest_deliverables"
        echo ""
        echo "Generated Files:"
        find "$latest_deliverables" -type f -exec basename {} \; | sort | sed 's/^/  - /'
    fi
    
    echo ""
    echo "Full execution log: $LOG_FILE"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "=================================================================="
    echo "                    SPRINT 2 TEST EXECUTION"
    echo "=================================================================="
    echo "Started: $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Setup test environment
    setup_test_environment
    
    # Check services if running automated tests
    if [ "$MANUAL_ONLY" = false ]; then
        if ! check_sprint2_services; then
            exit 1
        fi
    fi
    
    # Execute tests based on options
    local exit_code=0
    
    if [ "$MANUAL_ONLY" = true ]; then
        generate_manual_test_guidance
        exit_code=$?
    elif [ "$AUTOMATED_ONLY" = true ]; then
        run_automated_tests
        exit_code=$?
    else
        # Run comprehensive test suite (includes both automated and manual guidance)
        run_comprehensive_tests
        exit_code=$?
    fi
    
    # Display results summary
    display_results_summary
    
    echo ""
    echo "=================================================================="
    if [ $exit_code -eq 0 ]; then
        log_success "Sprint 2 test execution completed successfully"
        echo "Next Steps:"
        echo "  1. Review generated test reports and deliverables"
        echo "  2. Address any identified issues"
        echo "  3. Execute manual test scenarios if not already done"
        echo "  4. Plan production deployment based on results"
    else
        log_error "Sprint 2 test execution completed with errors (exit code: $exit_code)"
        echo "Next Steps:"
        echo "  1. Review error logs and test failures"
        echo "  2. Fix identified issues"
        echo "  3. Re-run test suite after fixes"
    fi
    echo "=================================================================="
    echo ""
    
    exit $exit_code
}

# Execute main function
main "$@"