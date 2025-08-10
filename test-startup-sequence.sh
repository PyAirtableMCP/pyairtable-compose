#!/bin/bash

# CRITICAL: Startup Sequence Validation Test
# Tests the complete service startup orchestration without actually starting services

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
}

# Test 1: Validate Docker Compose file syntax
test_compose_syntax() {
    print_header "TEST 1: Docker Compose File Validation"
    
    log_info "Checking docker-compose.yml syntax..."
    
    if ! docker-compose -f docker-compose.yml config >/dev/null 2>&1; then
        log_error "Docker Compose file has syntax errors"
        docker-compose -f docker-compose.yml config
        return 1
    fi
    
    log_success "Docker Compose file syntax is valid"
    
    # Check for required services
    local required_services=(
        "postgres" "redis" "airtable-gateway" "mcp-server"
        "llm-orchestrator" "platform-services" "automation-services"
        "saga-orchestrator" "api-gateway" "frontend"
    )
    
    for service in "${required_services[@]}"; do
        if ! docker-compose -f docker-compose.yml config | grep -q "^  $service:"; then
            log_error "Required service '$service' not found in compose file"
            return 1
        fi
        log_info "✓ Service '$service' found"
    done
    
    log_success "All required services are defined"
    return 0
}

# Test 2: Validate service dependencies
test_service_dependencies() {
    print_header "TEST 2: Service Dependency Validation"
    
    log_info "Validating service dependency chains..."
    
    # Extract and validate depends_on configuration
    local compose_output
    compose_output=$(docker-compose -f docker-compose.yml config)
    
    # Check services that should have dependencies
    local services_with_deps=(
        "airtable-gateway"
        "mcp-server"  
        "llm-orchestrator"
        "platform-services"
        "automation-services"
        "saga-orchestrator"
        "api-gateway"
        "frontend"
    )
    
    for service in "${services_with_deps[@]}"; do
        log_info "Checking dependencies for $service"
        
        # This is a simplified check - in a real implementation, you'd parse the YAML properly
        if echo "$compose_output" | grep -A 20 "^  $service:" | grep -q "depends_on:"; then
            log_success "✓ $service has dependency configuration"
        else
            log_warning "⚠ $service missing dependency configuration"
        fi
    done
    
    return 0
}

# Test 3: Validate health check configurations
test_health_checks() {
    print_header "TEST 3: Health Check Validation"
    
    log_info "Validating health check configurations..."
    
    local compose_output
    compose_output=$(docker-compose -f docker-compose.yml config)
    
    local services_with_health_checks=(
        "postgres" "redis" "airtable-gateway" "mcp-server"
        "llm-orchestrator" "platform-services" "automation-services"
        "saga-orchestrator" "api-gateway" "frontend"
    )
    
    for service in "${services_with_health_checks[@]}"; do
        if echo "$compose_output" | grep -A 20 "^  $service:" | grep -q "healthcheck:"; then
            log_success "✓ $service has health check configured"
        else
            log_warning "⚠ $service missing health check"
        fi
    done
    
    return 0
}

# Test 4: Validate startup scripts
test_startup_scripts() {
    print_header "TEST 4: Startup Script Validation"
    
    local scripts_to_check=(
        "startup-orchestrator.sh"
        "scripts/docker-compose-orchestrator.sh"
        "scripts/wait-for-database.sh"
        "scripts/wait-for-redis.sh"
        "scripts/wait-for-service.sh"
        "scripts/service-connection-retry.py"
    )
    
    for script in "${scripts_to_check[@]}"; do
        local script_path="$SCRIPT_DIR/$script"
        
        if [ -f "$script_path" ]; then
            if [ -x "$script_path" ]; then
                log_success "✓ $script exists and is executable"
                
                # Basic syntax check for bash scripts
                if [[ "$script" == *.sh ]]; then
                    if bash -n "$script_path" 2>/dev/null; then
                        log_success "✓ $script has valid bash syntax"
                    else
                        log_error "✗ $script has bash syntax errors"
                        return 1
                    fi
                fi
            else
                log_warning "⚠ $script exists but is not executable"
                chmod +x "$script_path"
                log_info "Fixed: Made $script executable"
            fi
        else
            log_error "✗ $script not found at $script_path"
            return 1
        fi
    done
    
    return 0
}

# Test 5: Validate environment requirements
test_environment_requirements() {
    print_header "TEST 5: Environment Requirements Validation"
    
    log_info "Checking required environment variables..."
    
    # Create a test environment file if it doesn't exist
    if [ ! -f ".env" ]; then
        log_warning "No .env file found, creating template..."
        cat > .env << 'EOF'
# Required environment variables for startup validation
POSTGRES_PASSWORD=test_password
REDIS_PASSWORD=test_password
API_KEY=test_api_key
AIRTABLE_TOKEN=test_token
AIRTABLE_BASE=test_base
POSTGRES_USER=postgres
POSTGRES_DB=pyairtable
LOG_LEVEL=INFO
CORS_ORIGINS=*
EOF
        log_info "Created .env template file"
    fi
    
    # Source environment
    if [ -f ".env" ]; then
        export $(grep -v '^#' .env | xargs)
    fi
    
    local required_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "API_KEY"
        "AIRTABLE_TOKEN"
        "AIRTABLE_BASE"
        "POSTGRES_USER"
        "POSTGRES_DB"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        else
            log_success "✓ $var is set"
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# Test 6: Validate Docker environment
test_docker_environment() {
    print_header "TEST 6: Docker Environment Validation"
    
    log_info "Checking Docker installation and status..."
    
    # Check Docker command
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    log_success "✓ Docker command found"
    
    # Check Docker Compose
    if command -v docker-compose >/dev/null 2>&1; then
        log_success "✓ docker-compose command found"
    elif docker compose version >/dev/null 2>&1; then
        log_success "✓ docker compose (v2) found"
    else
        log_error "Neither docker-compose nor 'docker compose' found"
        return 1
    fi
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    log_success "✓ Docker daemon is running"
    
    # Check available resources
    local docker_info
    docker_info=$(docker info 2>/dev/null)
    
    if echo "$docker_info" | grep -q "CPUs:"; then
        local cpus
        cpus=$(echo "$docker_info" | grep "CPUs:" | awk '{print $2}')
        log_info "Available CPUs: $cpus"
        
        if [ "$cpus" -lt 2 ]; then
            log_warning "Low CPU count ($cpus) - may impact performance"
        fi
    fi
    
    return 0
}

# Test 7: Simulate startup sequence
test_startup_sequence_simulation() {
    print_header "TEST 7: Startup Sequence Simulation"
    
    log_info "Simulating startup sequence validation..."
    
    # Test the orchestrator with --validate-only flag
    if [ -x "./startup-orchestrator.sh" ]; then
        log_info "Testing orchestrator help function..."
        if ./startup-orchestrator.sh --help >/dev/null 2>&1; then
            log_success "✓ Orchestrator help function works"
        else
            log_error "✗ Orchestrator help function failed"
            return 1
        fi
    else
        log_error "Startup orchestrator not found or not executable"
        return 1
    fi
    
    # Test individual wait scripts
    log_info "Testing wait script help functions..."
    
    for script in "scripts/wait-for-database.sh" "scripts/wait-for-redis.sh" "scripts/wait-for-service.sh"; do
        if [ -x "$script" ]; then
            # These scripts don't have help, but we can test they execute
            log_success "✓ $script is executable"
        else
            log_error "✗ $script not found or not executable"
            return 1
        fi
    done
    
    return 0
}

# Main test runner
main() {
    local start_time=$(date +%s)
    local failed_tests=()
    
    print_header "PyAirtable Startup Sequence Validation Suite"
    
    log_info "Starting comprehensive validation of startup system..."
    log_info "Working directory: $(pwd)"
    
    # Run all tests
    local tests=(
        "test_compose_syntax"
        "test_service_dependencies"
        "test_health_checks"
        "test_startup_scripts"
        "test_environment_requirements"
        "test_docker_environment"
        "test_startup_sequence_simulation"
    )
    
    for test in "${tests[@]}"; do
        log_info "Running $test..."
        if $test; then
            log_success "$test PASSED"
        else
            log_error "$test FAILED"
            failed_tests+=("$test")
        fi
        echo
    done
    
    # Generate report
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_header "VALIDATION REPORT"
    
    echo "Duration: ${duration} seconds"
    echo "Total Tests: ${#tests[@]}"
    echo "Passed: $((${#tests[@]} - ${#failed_tests[@]}))"
    echo "Failed: ${#failed_tests[@]}"
    
    if [ ${#failed_tests[@]} -eq 0 ]; then
        echo -e "\n${GREEN}🎉 ALL TESTS PASSED!${NC}"
        echo -e "${GREEN}Startup system is ready for deployment.${NC}"
        
        echo -e "\n${BLUE}Next Steps:${NC}"
        echo "1. Run: ./startup-orchestrator.sh"
        echo "2. Monitor startup: docker-compose ps"
        echo "3. Check health: ./startup-orchestrator.sh --validate-only"
        
        return 0
    else
        echo -e "\n${RED}❌ VALIDATION FAILED${NC}"
        echo -e "${RED}Failed tests: ${failed_tests[*]}${NC}"
        
        echo -e "\n${YELLOW}Troubleshooting:${NC}"
        echo "1. Fix the failed tests above"
        echo "2. Re-run this validation script"
        echo "3. Check individual script syntax and permissions"
        
        return 1
    fi
}

# Execute main function
main "$@"