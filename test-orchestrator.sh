#!/bin/bash

# Test Orchestrator - Comprehensive test runner for all service types
# Supports Python (pytest), Go (go test), and JavaScript (jest/playwright) tests
# Provides parallel execution, coverage reporting, and detailed test results

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
TEST_RESULTS_DIR="$PROJECT_ROOT/test-results"
COVERAGE_DIR="$PROJECT_ROOT/coverage"
LOG_DIR="$PROJECT_ROOT/test-logs"
PARALLEL_JOBS=${PARALLEL_JOBS:-4}
COVERAGE_THRESHOLD=${COVERAGE_THRESHOLD:-80}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test categories
declare -A TEST_CATEGORIES=(
    ["unit"]="Unit Tests"
    ["integration"]="Integration Tests"
    ["e2e"]="End-to-End Tests"
    ["performance"]="Performance Tests"
    ["security"]="Security Tests"
    ["contract"]="Contract Tests"
    ["smoke"]="Smoke Tests"
)

# Service types
declare -A SERVICE_TYPES=(
    ["python"]="Python Services"
    ["go"]="Go Services"
    ["frontend"]="Frontend Services"
)

# Initialize directories
init_test_environment() {
    echo -e "${BLUE}Initializing test environment...${NC}"
    
    # Create directories
    mkdir -p "$TEST_RESULTS_DIR" "$COVERAGE_DIR" "$LOG_DIR"
    
    # Create subdirectories for each service type and test category
    for service_type in "${!SERVICE_TYPES[@]}"; do
        for category in "${!TEST_CATEGORIES[@]}"; do
            mkdir -p "$TEST_RESULTS_DIR/$service_type/$category"
            mkdir -p "$COVERAGE_DIR/$service_type/$category"
        done
    done
    
    # Clean previous results
    find "$TEST_RESULTS_DIR" -type f -name "*.json" -o -name "*.xml" -o -name "*.html" | xargs rm -f
    find "$COVERAGE_DIR" -type f -name "*.json" -o -name "*.xml" -o -name "*.html" | xargs rm -f
    find "$LOG_DIR" -type f -name "*.log" | xargs rm -f
    
    echo -e "${GREEN}Test environment initialized${NC}"
}

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/orchestrator.log"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check Python dependencies
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    if ! command -v pytest &> /dev/null; then
        missing_deps+=("pytest")
    fi
    
    # Check Go dependencies
    if ! command -v go &> /dev/null; then
        missing_deps+=("go")
    fi
    
    # Check Node.js dependencies
    if ! command -v node &> /dev/null; then
        missing_deps+=("node")
    fi
    
    if ! command -v npm &> /dev/null; then
        missing_deps+=("npm")
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Start test databases and containers
start_test_containers() {
    log_info "Starting test containers..."
    
    # Check if docker-compose.test.yml exists
    if [ -f "$PROJECT_ROOT/docker-compose.test.yml" ]; then
        docker-compose -f docker-compose.test.yml up -d --remove-orphans
    elif [ -f "$PROJECT_ROOT/tests/docker-compose.test.yml" ]; then
        docker-compose -f tests/docker-compose.test.yml up -d --remove-orphans
    else
        log_warning "No test docker-compose file found. Creating minimal test infrastructure..."
        create_test_infrastructure
    fi
    
    # Wait for containers to be ready
    sleep 10
    
    log_success "Test containers started"
}

# Create minimal test infrastructure
create_test_infrastructure() {
    log_info "Creating minimal test infrastructure..."
    
    cat > "$PROJECT_ROOT/docker-compose.test.yml" << 'EOF'
version: '3.8'

services:
  postgres-test:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: test_db
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_password
    ports:
      - "5433:5432"
    volumes:
      - test_postgres_data:/var/lib/postgresql/data
      - ./tests/fixtures/sql:/docker-entrypoint-initdb.d
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test_user -d test_db"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis-test:
    image: redis:7-alpine
    ports:
      - "6380:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  test-runner:
    image: python:3.11-slim
    working_dir: /app
    volumes:
      - .:/app
    environment:
      - DATABASE_URL=postgresql://test_user:test_password@postgres-test:5432/test_db
      - REDIS_URL=redis://redis-test:6379
    depends_on:
      postgres-test:
        condition: service_healthy
      redis-test:
        condition: service_healthy

volumes:
  test_postgres_data:
EOF
    
    log_success "Test infrastructure configuration created"
}

# Python service tests
run_python_tests() {
    local category="$1"
    local service_path="$2"
    local service_name=$(basename "$service_path")
    
    log_info "Running Python $category tests for $service_name..."
    
    local result_file="$TEST_RESULTS_DIR/python/$category/${service_name}.json"
    local coverage_file="$COVERAGE_DIR/python/$category/${service_name}.json"
    local log_file="$LOG_DIR/python_${category}_${service_name}.log"
    
    cd "$service_path"
    
    # Install dependencies if requirements.txt exists
    if [ -f "requirements.txt" ] || [ -f "requirements-test.txt" ]; then
        log_info "Installing Python dependencies for $service_name..."
        python -m pip install -r requirements*.txt >> "$log_file" 2>&1 || true
    fi
    
    # Run tests based on category
    case "$category" in
        "unit")
            python -m pytest tests/unit/ \
                --junitxml="$result_file" \
                --cov=src \
                --cov-report=json:"$coverage_file" \
                --cov-report=html:"$COVERAGE_DIR/python/$category/${service_name}_html" \
                -v >> "$log_file" 2>&1
            ;;
        "integration")
            python -m pytest tests/integration/ \
                --junitxml="$result_file" \
                --cov=src \
                --cov-report=json:"$coverage_file" \
                -v >> "$log_file" 2>&1
            ;;
        "e2e")
            python -m pytest tests/e2e/ \
                --junitxml="$result_file" \
                -v >> "$log_file" 2>&1
            ;;
        *)
            python -m pytest tests/ \
                --junitxml="$result_file" \
                --cov=src \
                --cov-report=json:"$coverage_file" \
                -v >> "$log_file" 2>&1
            ;;
    esac
    
    local exit_code=$?
    cd "$PROJECT_ROOT"
    
    if [ $exit_code -eq 0 ]; then
        log_success "Python $category tests passed for $service_name"
    else
        log_error "Python $category tests failed for $service_name (exit code: $exit_code)"
    fi
    
    return $exit_code
}

# Go service tests
run_go_tests() {
    local category="$1"
    local service_path="$2"
    local service_name=$(basename "$service_path")
    
    log_info "Running Go $category tests for $service_name..."
    
    local result_file="$TEST_RESULTS_DIR/go/$category/${service_name}.json"
    local coverage_file="$COVERAGE_DIR/go/$category/${service_name}.out"
    local log_file="$LOG_DIR/go_${category}_${service_name}.log"
    
    cd "$service_path"
    
    # Download dependencies
    go mod download >> "$log_file" 2>&1 || true
    
    # Run tests based on category
    case "$category" in
        "unit")
            go test -v -coverprofile="$coverage_file" -json ./test/unit/... > "$result_file" 2>> "$log_file"
            ;;
        "integration")
            go test -v -coverprofile="$coverage_file" -json ./test/integration/... > "$result_file" 2>> "$log_file"
            ;;
        "e2e")
            go test -v -json ./test/e2e/... > "$result_file" 2>> "$log_file"
            ;;
        *)
            go test -v -coverprofile="$coverage_file" -json ./... > "$result_file" 2>> "$log_file"
            ;;
    esac
    
    local exit_code=$?
    
    # Generate coverage HTML report
    if [ -f "$coverage_file" ]; then
        go tool cover -html="$coverage_file" -o "$COVERAGE_DIR/go/$category/${service_name}.html"
    fi
    
    cd "$PROJECT_ROOT"
    
    if [ $exit_code -eq 0 ]; then
        log_success "Go $category tests passed for $service_name"
    else
        log_error "Go $category tests failed for $service_name (exit code: $exit_code)"
    fi
    
    return $exit_code
}

# Frontend service tests
run_frontend_tests() {
    local category="$1"
    local service_path="$2"
    local service_name=$(basename "$service_path")
    
    log_info "Running Frontend $category tests for $service_name..."
    
    local result_file="$TEST_RESULTS_DIR/frontend/$category/${service_name}.json"
    local coverage_file="$COVERAGE_DIR/frontend/$category/${service_name}.json"
    local log_file="$LOG_DIR/frontend_${category}_${service_name}.log"
    
    cd "$service_path"
    
    # Install dependencies
    if [ -f "package.json" ]; then
        log_info "Installing Node.js dependencies for $service_name..."
        npm ci >> "$log_file" 2>&1 || npm install >> "$log_file" 2>&1
    fi
    
    # Run tests based on category
    case "$category" in
        "unit")
            if [ -f "jest.config.js" ] || [ -f "jest.config.json" ]; then
                npx jest --coverage --outputFile="$result_file" --coverageReporters=json --coverageDirectory="$COVERAGE_DIR/frontend/$category/${service_name}" >> "$log_file" 2>&1
            else
                npm test -- --coverage --watchAll=false >> "$log_file" 2>&1
            fi
            ;;
        "e2e")
            if [ -f "playwright.config.ts" ] || [ -f "playwright.config.js" ]; then
                npx playwright test --reporter=json --output-file="$result_file" >> "$log_file" 2>&1
            elif command -v cypress &> /dev/null; then
                npx cypress run --reporter json --reporter-options "output=$result_file" >> "$log_file" 2>&1
            else
                log_warning "No E2E testing framework found for $service_name"
            fi
            ;;
        *)
            npm test >> "$log_file" 2>&1
            ;;
    esac
    
    local exit_code=$?
    cd "$PROJECT_ROOT"
    
    if [ $exit_code -eq 0 ]; then
        log_success "Frontend $category tests passed for $service_name"
    else
        log_error "Frontend $category tests failed for $service_name (exit code: $exit_code)"
    fi
    
    return $exit_code
}

# Run tests for all services of a specific type and category
run_service_type_tests() {
    local service_type="$1"
    local category="$2"
    
    log_info "Running $category tests for $service_type services..."
    
    local services_dir=""
    local test_function=""
    
    case "$service_type" in
        "python")
            services_dir="python-services"
            test_function="run_python_tests"
            ;;
        "go")
            services_dir="go-services"
            test_function="run_go_tests"
            ;;
        "frontend")
            services_dir="frontend-services"
            test_function="run_frontend_tests"
            ;;
        *)
            log_error "Unknown service type: $service_type"
            return 1
            ;;
    esac
    
    if [ ! -d "$PROJECT_ROOT/$services_dir" ]; then
        log_warning "Directory $services_dir not found, skipping $service_type tests"
        return 0
    fi
    
    local failed_services=()
    local passed_services=()
    
    # Run tests for each service in parallel batches
    local pids=()
    local count=0
    
    for service_path in "$PROJECT_ROOT/$services_dir"/*; do
        if [ -d "$service_path" ] && [ "$(basename "$service_path")" != "shared" ]; then
            # Run test in background
            $test_function "$category" "$service_path" &
            pids+=($!)
            ((count++))
            
            # Wait for batch completion when we reach the parallel job limit
            if [ $count -ge $PARALLEL_JOBS ]; then
                wait_for_batch "${pids[@]}"
                pids=()
                count=0
            fi
        fi
    done
    
    # Wait for remaining jobs
    if [ ${#pids[@]} -gt 0 ]; then
        wait_for_batch "${pids[@]}"
    fi
    
    log_success "Completed $category tests for $service_type services"
}

# Wait for a batch of background jobs with status tracking
wait_for_batch() {
    local pids=("$@")
    local failed=0
    
    for pid in "${pids[@]}"; do
        if ! wait $pid; then
            ((failed++))
        fi
    done
    
    return $failed
}

# Advanced parallel execution with work stealing
run_tests_parallel() {
    local service_type="$1"
    local category="$2"
    local services_dir="$3"
    local test_function="$4"
    
    log_info "Running $category tests for $service_type services in parallel..."
    
    local work_queue=()
    local active_jobs=()
    local completed_jobs=0
    local failed_jobs=0
    local total_jobs=0
    
    # Build work queue
    for service_path in "$PROJECT_ROOT/$services_dir"/*; do
        if [ -d "$service_path" ] && [ "$(basename "$service_path")" != "shared" ] && [ "$(basename "$service_path")" != "pkg" ]; then
            work_queue+=("$service_path")
            ((total_jobs++))
        fi
    done
    
    log_info "Found $total_jobs services to test"
    
    # Process work queue with parallel execution
    while [ ${#work_queue[@]} -gt 0 ] || [ ${#active_jobs[@]} -gt 0 ]; do
        # Start new jobs if we have capacity and work
        while [ ${#active_jobs[@]} -lt $PARALLEL_JOBS ] && [ ${#work_queue[@]} -gt 0 ]; do
            local service_path="${work_queue[0]}"
            work_queue=("${work_queue[@]:1}")  # Remove first element
            
            # Start job in background
            log_info "Starting test for $(basename "$service_path")..."
            $test_function "$category" "$service_path" &
            local job_pid=$!
            active_jobs+=("$job_pid:$(basename "$service_path")")
        done
        
        # Check for completed jobs
        local still_active=()
        for job in "${active_jobs[@]}"; do
            local pid="${job%%:*}"
            local service_name="${job##*:}"
            
            if ! kill -0 "$pid" 2>/dev/null; then
                # Job completed, check exit status
                if wait "$pid"; then
                    log_success "$service_name tests completed"
                    ((completed_jobs++))
                else
                    log_error "$service_name tests failed"
                    ((failed_jobs++))
                fi
            else
                still_active+=("$job")
            fi
        done
        active_jobs=("${still_active[@]}")
        
        # Brief pause to prevent busy waiting
        sleep 0.5
    done
    
    log_info "Parallel execution completed: $completed_jobs passed, $failed_jobs failed"
    return $failed_jobs
}

# Generate comprehensive test report
generate_test_report() {
    log_info "Generating comprehensive test report..."
    
    local report_file="$TEST_RESULTS_DIR/comprehensive_report.html"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>PyAirtable Compose - Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .section { margin: 20px 0; }
        .success { color: green; }
        .failure { color: red; }
        .warning { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .coverage-bar { background: #ddd; border-radius: 3px; overflow: hidden; height: 20px; }
        .coverage-fill { height: 100%; background: linear-gradient(90deg, red 0%, yellow 70%, green 80%); }
    </style>
</head>
<body>
    <div class="header">
        <h1>PyAirtable Compose - Test Results</h1>
        <p>Generated on: $timestamp</p>
    </div>
EOF
    
    # Add test results summary
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Test Summary</h2>" >> "$report_file"
    echo "<table>" >> "$report_file"
    echo "<tr><th>Service Type</th><th>Test Category</th><th>Status</th><th>Coverage</th></tr>" >> "$report_file"
    
    # Analyze results from each service type and category
    for service_type in "${!SERVICE_TYPES[@]}"; do
        for category in "${!TEST_CATEGORIES[@]}"; do
            local category_dir="$TEST_RESULTS_DIR/$service_type/$category"
            if [ -d "$category_dir" ] && [ "$(ls -A "$category_dir")" ]; then
                local passed=0
                local failed=0
                local coverage=0
                
                # Count results and calculate average coverage
                for result_file in "$category_dir"/*.json; do
                    if [ -f "$result_file" ]; then
                        # Simple heuristic: if file contains "failures": 0 or similar, it's a pass
                        if grep -q '"failures": 0\|"failed": 0\|"errors": 0' "$result_file" 2>/dev/null; then
                            ((passed++))
                        else
                            ((failed++))
                        fi
                    fi
                done
                
                # Calculate coverage if available
                local coverage_dir="$COVERAGE_DIR/$service_type/$category"
                if [ -d "$coverage_dir" ]; then
                    local coverage_count=0
                    local coverage_total=0
                    for coverage_file in "$coverage_dir"/*.json; do
                        if [ -f "$coverage_file" ]; then
                            # Extract coverage percentage (simplified)
                            local cov=$(grep -o '"percent": [0-9.]*' "$coverage_file" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' ' || echo "0")
                            coverage_total=$(echo "$coverage_total + $cov" | bc 2>/dev/null || echo "$coverage_total")
                            ((coverage_count++))
                        fi
                    done
                    if [ $coverage_count -gt 0 ]; then
                        coverage=$(echo "scale=1; $coverage_total / $coverage_count" | bc 2>/dev/null || echo "0")
                    fi
                fi
                
                local status_class="success"
                local status_text="PASS ($passed)"
                if [ $failed -gt 0 ]; then
                    status_class="failure"
                    status_text="FAIL ($failed failed, $passed passed)"
                fi
                
                echo "<tr>" >> "$report_file"
                echo "<td>${SERVICE_TYPES[$service_type]}</td>" >> "$report_file"
                echo "<td>${TEST_CATEGORIES[$category]}</td>" >> "$report_file"
                echo "<td class='$status_class'>$status_text</td>" >> "$report_file"
                echo "<td>" >> "$report_file"
                echo "<div class='coverage-bar'>" >> "$report_file"
                echo "<div class='coverage-fill' style='width: ${coverage}%'></div>" >> "$report_file"
                echo "</div>${coverage}%" >> "$report_file"
                echo "</td>" >> "$report_file"
                echo "</tr>" >> "$report_file"
            fi
        done
    done
    
    echo "</table>" >> "$report_file"
    echo "</div>" >> "$report_file"
    
    # Add coverage details
    echo "<div class='section'>" >> "$report_file"
    echo "<h2>Coverage Details</h2>" >> "$report_file"
    echo "<p>Coverage reports are available in the following locations:</p>" >> "$report_file"
    echo "<ul>" >> "$report_file"
    
    find "$COVERAGE_DIR" -name "*.html" | while read -r coverage_html; do
        local relative_path=$(realpath --relative-to="$TEST_RESULTS_DIR" "$coverage_html")
        echo "<li><a href='$relative_path'>$relative_path</a></li>" >> "$report_file"
    done
    
    echo "</ul>" >> "$report_file"
    echo "</div>" >> "$report_file"
    
    echo "</body></html>" >> "$report_file"
    
    log_success "Comprehensive test report generated: $report_file"
}

# Cleanup test containers
cleanup_test_containers() {
    log_info "Cleaning up test containers..."
    
    if [ -f "$PROJECT_ROOT/docker-compose.test.yml" ]; then
        docker-compose -f docker-compose.test.yml down -v --remove-orphans
    elif [ -f "$PROJECT_ROOT/tests/docker-compose.test.yml" ]; then
        docker-compose -f tests/docker-compose.test.yml down -v --remove-orphans
    fi
    
    log_success "Test containers cleaned up"
}

# Main execution flow
main() {
    local test_categories=()
    local service_types=()
    local skip_cleanup=false
    local generate_report=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --categories)
                IFS=',' read -ra test_categories <<< "$2"
                shift 2
                ;;
            --services)
                IFS=',' read -ra service_types <<< "$2"
                shift 2
                ;;
            --skip-cleanup)
                skip_cleanup=true
                shift
                ;;
            --no-report)
                generate_report=false
                shift
                ;;
            --parallel-jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            --coverage-threshold)
                COVERAGE_THRESHOLD="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --categories CATEGORIES    Comma-separated list of test categories to run"
                echo "                            Available: unit,integration,e2e,performance,security,contract,smoke"
                echo "  --services SERVICES       Comma-separated list of service types to test"
                echo "                            Available: python,go,frontend"
                echo "  --skip-cleanup            Skip cleanup of test containers"
                echo "  --no-report              Skip generation of test report"
                echo "  --parallel-jobs JOBS      Number of parallel test jobs (default: 4)"
                echo "  --coverage-threshold PCT  Minimum coverage percentage (default: 80)"
                echo "  -h, --help               Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Run all tests"
                echo "  $0 --categories unit,integration      # Run only unit and integration tests"
                echo "  $0 --services python,go              # Run tests only for Python and Go services"
                echo "  $0 --categories unit --services python --parallel-jobs 8"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Set defaults if not specified
    if [ ${#test_categories[@]} -eq 0 ]; then
        test_categories=("unit" "integration" "e2e")
    fi
    
    if [ ${#service_types[@]} -eq 0 ]; then
        service_types=("python" "go" "frontend")
    fi
    
    log_info "Starting comprehensive test orchestration..."
    log_info "Test categories: ${test_categories[*]}"
    log_info "Service types: ${service_types[*]}"
    log_info "Parallel jobs: $PARALLEL_JOBS"
    log_info "Coverage threshold: $COVERAGE_THRESHOLD%"
    
    # Initialize environment
    init_test_environment
    check_dependencies
    start_test_containers
    
    # Run tests
    local overall_exit_code=0
    
    for service_type in "${service_types[@]}"; do
        for category in "${test_categories[@]}"; do
            if ! run_service_type_tests "$service_type" "$category"; then
                overall_exit_code=1
            fi
        done
    done
    
    # Generate report
    if [ "$generate_report" = true ]; then
        generate_test_report
    fi
    
    # Cleanup
    if [ "$skip_cleanup" = false ]; then
        cleanup_test_containers
    fi
    
    # Final summary
    if [ $overall_exit_code -eq 0 ]; then
        log_success "All tests completed successfully!"
        log_success "Test results available in: $TEST_RESULTS_DIR"
        log_success "Coverage reports available in: $COVERAGE_DIR"
    else
        log_error "Some tests failed. Check the logs and reports for details."
        log_info "Test results available in: $TEST_RESULTS_DIR"
        log_info "Test logs available in: $LOG_DIR"
    fi
    
    exit $overall_exit_code
}

# Handle script interruption
trap cleanup_test_containers INT TERM

# Run main function
main "$@"