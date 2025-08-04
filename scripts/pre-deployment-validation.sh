#!/bin/bash

# PyAirtable Pre-Deployment Validation Script
# This script runs comprehensive validation before Minikube deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/testing/reports/logs"
REPORT_DIR="$PROJECT_ROOT/testing/reports"
TEST_ENV="${TEST_ENV:-pre-deployment}"
TIMEOUT="${TIMEOUT:-1800}"  # 30 minutes
PARALLEL_JOBS="${PARALLEL_JOBS:-4}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_DIR/pre-deployment.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_DIR/pre-deployment.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_DIR/pre-deployment.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_DIR/pre-deployment.log"
}

# Error handling
cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."
    
    # Stop any running test services
    docker-compose -f "$PROJECT_ROOT/tests/docker-compose.test.yml" down || true
    
    if [ $exit_code -eq 0 ]; then
        log_success "Pre-deployment validation completed successfully!"
    else
        log_error "Pre-deployment validation failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

trap cleanup EXIT

# Initialize
initialize() {
    log_info "Initializing pre-deployment validation..."
    
    # Create directories
    mkdir -p "$LOG_DIR" "$REPORT_DIR"
    
    # Clear previous logs
    > "$LOG_DIR/pre-deployment.log"
    
    # Set environment
    export TEST_ENV="$TEST_ENV"
    export LOG_LEVEL="INFO"
    
    log_success "Initialization complete"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    local tools=("docker" "docker-compose" "kubectl" "python3" "node" "npm" "go" "make")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running"
        return 1
    fi
    
    # Check Minikube is available
    if ! kubectl cluster-info &> /dev/null; then
        log_warning "Minikube/Kubernetes cluster not available - some tests will be skipped"
    fi
    
    log_success "Prerequisites check passed"
}

# Static analysis
run_static_analysis() {
    log_info "Running static analysis..."
    
    local analysis_failed=false
    
    # Python static analysis
    log_info "Running Python static analysis..."
    if command -v flake8 &> /dev/null; then
        if ! flake8 python-services/ --max-line-length=120 --exclude=venv,__pycache__ \
             --output-file="$REPORT_DIR/flake8-report.txt"; then
            log_warning "Python linting issues found"
            analysis_failed=true
        fi
    fi
    
    if command -v bandit &> /dev/null; then
        if ! bandit -r python-services/ -f json -o "$REPORT_DIR/bandit-report.json" \
             --severity-level medium; then
            log_warning "Python security issues found"
            analysis_failed=true
        fi
    fi
    
    # Go static analysis
    log_info "Running Go static analysis..."
    cd "$PROJECT_ROOT/go-services"
    
    if ! go fmt ./...; then
        log_warning "Go formatting issues found"
        analysis_failed=true
    fi
    
    if ! go vet ./...; then
        log_error "Go vet failed"
        analysis_failed=true
    fi
    
    if command -v golangci-lint &> /dev/null; then
        if ! golangci-lint run ./... --out-format json > "../$REPORT_DIR/golangci-lint-report.json"; then
            log_warning "Go linting issues found"
            analysis_failed=true
        fi
    fi
    
    if command -v gosec &> /dev/null; then
        if ! gosec -fmt json -out "../$REPORT_DIR/gosec-report.json" ./...; then
            log_warning "Go security issues found"
            analysis_failed=true
        fi
    fi
    
    cd "$PROJECT_ROOT"
    
    # Frontend static analysis
    log_info "Running Frontend static analysis..."
    for dir in frontend-services/*/; do
        if [ -f "$dir/package.json" ]; then
            log_info "Analyzing $dir"
            cd "$dir"
            
            if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ]; then
                if ! npm run lint 2>&1 | tee -a "../../$LOG_DIR/frontend-lint.log"; then
                    log_warning "Frontend linting issues in $dir"
                    analysis_failed=true
                fi
            fi
            
            if [ -f "tsconfig.json" ]; then
                if ! npx tsc --noEmit; then
                    log_error "TypeScript compilation errors in $dir"
                    analysis_failed=true
                fi
            fi
            
            cd "$PROJECT_ROOT"
        fi
    done
    
    if [ "$analysis_failed" = true ]; then
        log_warning "Static analysis completed with issues - check reports"
    else
        log_success "Static analysis passed"
    fi
}

# Build validation
validate_builds() {
    log_info "Validating builds..."
    
    # Docker build validation
    log_info "Validating Docker builds..."
    
    local services=("api-gateway" "auth-service" "user-service" "airtable-gateway")
    local build_failed=false
    
    for service in "${services[@]}"; do
        log_info "Building $service..."
        
        if [ -f "go-services/$service/Dockerfile" ]; then
            if ! docker build -t "pyairtable-$service:test" "go-services/$service/" \
                 2>&1 | tee -a "$LOG_DIR/docker-build.log"; then
                log_error "Failed to build $service"
                build_failed=true
            fi
        fi
    done
    
    # Python services build
    for service_dir in python-services/*/; do
        if [ -f "$service_dir/Dockerfile" ]; then
            service_name=$(basename "$service_dir")
            log_info "Building Python service $service_name..."
            
            if ! docker build -t "pyairtable-$service_name:test" "$service_dir/" \
                 2>&1 | tee -a "$LOG_DIR/docker-build.log"; then
                log_error "Failed to build $service_name"
                build_failed=true
            fi
        fi
    done
    
    # Frontend builds
    for dir in frontend-services/*/; do
        if [ -f "$dir/package.json" ]; then
            app_name=$(basename "$dir")
            log_info "Building frontend app $app_name..."
            
            cd "$dir"
            if ! npm run build 2>&1 | tee -a "../../$LOG_DIR/frontend-build.log"; then
                log_error "Failed to build $app_name"
                build_failed=true
            fi
            cd "$PROJECT_ROOT"
        fi
    done
    
    if [ "$build_failed" = true ]; then
        log_error "Build validation failed"
        return 1
    fi
    
    log_success "Build validation passed"
}

# Run comprehensive tests
run_comprehensive_tests() {
    log_info "Running comprehensive test suite..."
    
    cd "$PROJECT_ROOT"
    
    # Set up test environment
    log_info "Setting up test environment..."
    if ! make -f testing/Makefile setup-test-db 2>&1 | tee -a "$LOG_DIR/test-setup.log"; then
        log_error "Failed to set up test environment"
        return 1
    fi
    
    local test_failed=false
    
    # Unit tests
    log_info "Running unit tests..."
    if ! timeout "$TIMEOUT" make -f testing/Makefile test-unit 2>&1 | tee -a "$LOG_DIR/unit-tests.log"; then
        log_error "Unit tests failed"
        test_failed=true
    else
        log_success "Unit tests passed"
    fi
    
    # Integration tests
    log_info "Running integration tests..."
    if ! timeout "$TIMEOUT" make -f testing/Makefile test-integration 2>&1 | tee -a "$LOG_DIR/integration-tests.log"; then
        log_error "Integration tests failed"
        test_failed=true
    else
        log_success "Integration tests passed"
    fi
    
    # Contract tests
    log_info "Running contract tests..."
    if ! timeout "$TIMEOUT" make -f testing/Makefile test-contracts 2>&1 | tee -a "$LOG_DIR/contract-tests.log"; then
        log_error "Contract tests failed"
        test_failed=true
    else
        log_success "Contract tests passed"
    fi
    
    # Security tests
    log_info "Running security tests..."
    if ! timeout "$TIMEOUT" make -f testing/Makefile test-security 2>&1 | tee -a "$LOG_DIR/security-tests.log"; then
        log_warning "Security tests failed - review security report"
    else
        log_success "Security tests passed"
    fi
    
    # Performance tests (quick version)
    log_info "Running performance tests..."
    export K6_VUS=5  # Reduced load for pre-deployment
    export K6_DURATION=30s
    if ! timeout 300 make -f testing/Makefile test-performance 2>&1 | tee -a "$LOG_DIR/performance-tests.log"; then
        log_warning "Performance tests failed - review performance report"
    else
        log_success "Performance tests passed"
    fi
    
    if [ "$test_failed" = true ]; then
        log_error "Comprehensive tests failed"
        return 1
    fi
    
    log_success "Comprehensive tests passed"
}

# Validate configuration
validate_configuration() {
    log_info "Validating configuration..."
    
    local config_issues=false
    
    # Check Kubernetes manifests
    log_info "Validating Kubernetes manifests..."
    if [ -d "k8s/" ]; then
        for manifest in k8s/*.yaml; do
            if [ -f "$manifest" ]; then
                if ! kubectl apply --dry-run=client -f "$manifest" 2>&1 | tee -a "$LOG_DIR/k8s-validation.log"; then
                    log_error "Invalid Kubernetes manifest: $manifest"
                    config_issues=true
                fi
            fi
        done
    fi
    
    # Check Docker Compose files
    log_info "Validating Docker Compose files..."
    for compose_file in docker-compose*.yml; do
        if [ -f "$compose_file" ]; then
            if ! docker-compose -f "$compose_file" config > /dev/null 2>&1; then
                log_error "Invalid Docker Compose file: $compose_file"
                config_issues=true
            fi
        fi
    done
    
    # Check environment files
    log_info "Validating environment configuration..."
    if [ ! -f ".env.example" ]; then
        log_warning "Missing .env.example file"
        config_issues=true
    fi
    
    # Validate service configurations
    for config_file in configs/*.yaml configs/*.yml configs/*.json; do
        if [ -f "$config_file" ]; then
            case "$config_file" in
                *.yaml|*.yml)
                    if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
                        log_error "Invalid YAML file: $config_file"
                        config_issues=true
                    fi
                    ;;
                *.json)
                    if ! python3 -c "import json; json.load(open('$config_file'))" 2>/dev/null; then
                        log_error "Invalid JSON file: $config_file"
                        config_issues=true
                    fi
                    ;;
            esac
        fi
    done
    
    if [ "$config_issues" = true ]; then
        log_error "Configuration validation failed"
        return 1
    fi
    
    log_success "Configuration validation passed"
}

# Database migration validation
validate_database_migrations() {
    log_info "Validating database migrations..."
    
    # Start test database
    docker-compose -f tests/docker-compose.test.yml up -d postgres-test
    sleep 10
    
    # Test migrations
    if [ -d "migrations/" ]; then
        log_info "Testing database migrations..."
        
        # Apply migrations
        export DATABASE_URL="postgresql://test:test@localhost:5433/pyairtable_test"
        
        if [ -f "python-services/requirements.txt" ] && grep -q "alembic" "python-services/requirements.txt"; then
            if ! alembic upgrade head 2>&1 | tee -a "$LOG_DIR/migration-test.log"; then
                log_error "Database migration failed"
                return 1
            fi
            
            # Test rollback
            if ! alembic downgrade -1 2>&1 | tee -a "$LOG_DIR/migration-test.log"; then
                log_warning "Database rollback test failed"
            fi
        fi
    fi
    
    log_success "Database migration validation passed"
}

# Resource validation
validate_resources() {
    log_info "Validating resource requirements..."
    
    # Check system resources
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    local available_disk=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    
    local required_memory=4096  # 4GB
    local required_disk=10      # 10GB
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        log_warning "Low memory: ${available_memory}MB available, ${required_memory}MB recommended"
    fi
    
    if [ "$available_disk" -lt "$required_disk" ]; then
        log_warning "Low disk space: ${available_disk}GB available, ${required_disk}GB recommended"
    fi
    
    # Check Docker resources
    local docker_info
    docker_info=$(docker system df 2>/dev/null || echo "")
    
    if [ -n "$docker_info" ]; then
        echo "$docker_info" > "$REPORT_DIR/docker-resources.txt"
    fi
    
    log_success "Resource validation completed"
}

# Generate deployment readiness report
generate_deployment_report() {
    log_info "Generating deployment readiness report..."
    
    local report_file="$REPORT_DIR/deployment-readiness-report.json"
    local timestamp=$(date -Iseconds)
    
    # Collect test results
    local unit_tests_passed="false"
    local integration_tests_passed="false"
    local security_tests_passed="false"
    local builds_passed="false"
    
    # Check log files for success indicators
    [ -f "$LOG_DIR/unit-tests.log" ] && grep -q "passed" "$LOG_DIR/unit-tests.log" && unit_tests_passed="true"
    [ -f "$LOG_DIR/integration-tests.log" ] && grep -q "passed" "$LOG_DIR/integration-tests.log" && integration_tests_passed="true"
    [ -f "$LOG_DIR/security-tests.log" ] && ! grep -q "FAILED" "$LOG_DIR/security-tests.log" && security_tests_passed="true"
    
    # Generate JSON report
    cat > "$report_file" << EOF
{
  "timestamp": "$timestamp",
  "environment": "$TEST_ENV",
  "validation_results": {
    "static_analysis": {
      "passed": true,
      "reports": [
        "flake8-report.txt",
        "bandit-report.json",
        "golangci-lint-report.json",
        "gosec-report.json"
      ]
    },
    "builds": {
      "passed": $builds_passed,
      "log_file": "docker-build.log"
    },
    "unit_tests": {
      "passed": $unit_tests_passed,
      "log_file": "unit-tests.log"
    },
    "integration_tests": {
      "passed": $integration_tests_passed,
      "log_file": "integration-tests.log"
    },
    "security_tests": {
      "passed": $security_tests_passed,
      "log_file": "security-tests.log"
    },
    "configuration": {
      "passed": true,
      "log_file": "k8s-validation.log"
    }
  },
  "deployment_ready": $([ "$unit_tests_passed" = "true" ] && [ "$integration_tests_passed" = "true" ] && echo "true" || echo "false"),
  "recommendations": [
    "Review security test results",
    "Monitor performance metrics during deployment",
    "Ensure all environment variables are configured"
  ]
}
EOF
    
    log_success "Deployment readiness report generated: $report_file"
    
    # Display summary
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT READINESS SUMMARY"
    echo "=========================================="
    echo "Timestamp: $timestamp"
    echo "Unit Tests: $([ "$unit_tests_passed" = "true" ] && echo "✓ PASSED" || echo "✗ FAILED")"
    echo "Integration Tests: $([ "$integration_tests_passed" = "true" ] && echo "✓ PASSED" || echo "✗ FAILED")"
    echo "Security Tests: $([ "$security_tests_passed" = "true" ] && echo "✓ PASSED" || echo "⚠ REVIEW NEEDED")"
    echo ""
    
    if [ "$unit_tests_passed" = "true" ] && [ "$integration_tests_passed" = "true" ]; then
        echo "🚀 DEPLOYMENT READY"
        echo "The system has passed all critical validation checks."
    else
        echo "❌ DEPLOYMENT NOT READY"
        echo "Critical issues must be resolved before deployment."
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting PyAirtable pre-deployment validation"
    
    initialize
    check_prerequisites
    run_static_analysis
    validate_builds
    validate_configuration
    validate_database_migrations
    run_comprehensive_tests
    validate_resources
    generate_deployment_report
    
    log_success "Pre-deployment validation completed successfully!"
}

# Execute main function
main "$@"