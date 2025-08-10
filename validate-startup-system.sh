#!/bin/bash

# PyAirtable Startup System Validation Script
# Tests the service orchestration system components

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="docker-compose.yml"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Test result tracking
pass_test() {
    ((TESTS_PASSED++))
    ((TOTAL_TESTS++))
    log_success "$1"
}

fail_test() {
    ((TESTS_FAILED++))
    ((TOTAL_TESTS++))
    log_error "$1"
}

# Test file existence and permissions
test_file_exists() {
    local file=$1
    local description=$2
    
    if [[ -f "$file" ]]; then
        if [[ -x "$file" ]]; then
            pass_test "$description exists and is executable"
        else
            fail_test "$description exists but is not executable"
        fi
    else
        fail_test "$description does not exist"
    fi
}

# Test docker-compose file validity
test_compose_file() {
    log_info "Testing Docker Compose file..."
    
    if [[ -f "$COMPOSE_FILE" ]]; then
        if docker-compose -f "$COMPOSE_FILE" config &> /dev/null; then
            pass_test "Docker Compose file is valid"
        else
            fail_test "Docker Compose file has syntax errors"
        fi
    else
        fail_test "Docker Compose file not found"
    fi
}

# Test health check configurations
test_health_checks() {
    log_info "Testing health check configurations..."
    
    local services_with_healthchecks=("postgres" "redis" "airtable-gateway" "mcp-server" "llm-orchestrator" "platform-services" "automation-services" "saga-orchestrator" "api-gateway" "frontend")
    
    for service in "${services_with_healthchecks[@]}"; do
        if docker-compose -f "$COMPOSE_FILE" config | grep -A 10 "^  $service:" | grep -q "healthcheck:"; then
            pass_test "Health check configured for $service"
        else
            fail_test "Health check missing for $service"
        fi
    done
}

# Test dependency configurations
test_dependencies() {
    log_info "Testing service dependencies..."
    
    # Test that dependent services have condition: service_healthy
    local dependencies=(
        "airtable-gateway:postgres:service_healthy"
        "airtable-gateway:redis:service_healthy"
        "mcp-server:airtable-gateway:service_healthy"
        "llm-orchestrator:mcp-server:service_healthy"
        "api-gateway:saga-orchestrator:service_healthy"
    )
    
    for dep in "${dependencies[@]}"; do
        local service=$(echo "$dep" | cut -d: -f1)
        local dependency=$(echo "$dep" | cut -d: -f2)
        local condition=$(echo "$dep" | cut -d: -f3)
        
        if docker-compose -f "$COMPOSE_FILE" config | grep -A 20 "^  $service:" | grep -A 10 "depends_on:" | grep -q "$dependency:.*condition:.*$condition"; then
            pass_test "$service properly depends on $dependency with $condition"
        else
            fail_test "$service dependency on $dependency with $condition not found"
        fi
    done
}

# Test wait-for scripts
test_wait_scripts() {
    log_info "Testing wait-for scripts..."
    
    # Test script existence and executability
    test_file_exists "$SCRIPT_DIR/scripts/wait-for-database.sh" "wait-for-database.sh script"
    test_file_exists "$SCRIPT_DIR/scripts/wait-for-redis.sh" "wait-for-redis.sh script"
    test_file_exists "$SCRIPT_DIR/scripts/wait-for-service.sh" "wait-for-service.sh script"
    
    # Test script syntax
    local scripts=("wait-for-database.sh" "wait-for-redis.sh" "wait-for-service.sh")
    
    for script in "${scripts[@]}"; do
        if bash -n "$SCRIPT_DIR/scripts/$script" 2>/dev/null; then
            pass_test "$script has valid syntax"
        else
            fail_test "$script has syntax errors"
        fi
    done
}

# Test orchestration scripts
test_orchestration_scripts() {
    log_info "Testing orchestration scripts..."
    
    test_file_exists "$SCRIPT_DIR/start-services.sh" "start-services.sh script"
    test_file_exists "$SCRIPT_DIR/stop-services.sh" "stop-services.sh script"
    
    # Test script syntax
    local scripts=("start-services.sh" "stop-services.sh")
    
    for script in "${scripts[@]}"; do
        if bash -n "$SCRIPT_DIR/$script" 2>/dev/null; then
            pass_test "$script has valid syntax"
        else
            fail_test "$script has syntax errors"
        fi
    done
    
    # Test help functionality
    if "$SCRIPT_DIR/start-services.sh" help &> /dev/null; then
        pass_test "start-services.sh help command works"
    else
        fail_test "start-services.sh help command failed"
    fi
    
    if "$SCRIPT_DIR/stop-services.sh" help &> /dev/null; then
        pass_test "stop-services.sh help command works"
    else
        fail_test "stop-services.sh help command failed"
    fi
}

# Test environment file
test_environment() {
    log_info "Testing environment configuration..."
    
    if [[ -f ".env.example" ]]; then
        pass_test ".env.example file exists"
    else
        fail_test ".env.example file missing"
    fi
    
    if [[ -f ".env" ]]; then
        pass_test ".env file exists"
        
        # Test required variables are present (not necessarily valid)
        local required_vars=("POSTGRES_PASSWORD" "REDIS_PASSWORD" "AIRTABLE_TOKEN" "GEMINI_API_KEY" "JWT_SECRET" "API_KEY")
        
        for var in "${required_vars[@]}"; do
            if grep -q "^$var=" .env; then
                pass_test "$var is defined in .env"
            else
                fail_test "$var is missing from .env"
            fi
        done
    else
        log_warning ".env file not found (this is expected for fresh installations)"
    fi
}

# Test Docker and Docker Compose availability
test_docker() {
    log_info "Testing Docker availability..."
    
    if command -v docker &> /dev/null; then
        pass_test "Docker is installed"
        
        if docker info &> /dev/null; then
            pass_test "Docker daemon is running"
        else
            fail_test "Docker daemon is not running"
        fi
    else
        fail_test "Docker is not installed"
    fi
    
    if command -v docker-compose &> /dev/null; then
        pass_test "Docker Compose is installed"
    elif docker compose version &> /dev/null; then
        pass_test "Docker Compose (v2) is installed"
    else
        fail_test "Docker Compose is not installed"
    fi
}

# Test service tier configuration
test_service_tiers() {
    log_info "Testing service tier configuration..."
    
    # Define expected tiers
    local tier1=("postgres" "redis")
    local tier2=("airtable-gateway" "platform-services")
    local tier3=("mcp-server")
    local tier4=("llm-orchestrator" "automation-services")
    local tier5=("saga-orchestrator")
    local tier6=("api-gateway")
    local tier7=("frontend")
    
    # Check that all services are defined in compose file
    local all_services=("${tier1[@]}" "${tier2[@]}" "${tier3[@]}" "${tier4[@]}" "${tier5[@]}" "${tier6[@]}" "${tier7[@]}")
    
    for service in "${all_services[@]}"; do
        if docker-compose -f "$COMPOSE_FILE" config | grep -q "^  $service:"; then
            pass_test "Service $service is defined in compose file"
        else
            fail_test "Service $service is missing from compose file"
        fi
    done
    
    # Check that tier dependencies are correct
    # Tier 2 should depend on Tier 1
    for service in "${tier2[@]}"; do
        local depends_on_tier1=false
        for dep in "${tier1[@]}"; do
            if docker-compose -f "$COMPOSE_FILE" config | grep -A 20 "^  $service:" | grep -q "$dep:"; then
                depends_on_tier1=true
                break
            fi
        done
        
        if [[ "$depends_on_tier1" == true ]]; then
            pass_test "$service correctly depends on Tier 1 services"
        else
            fail_test "$service does not depend on Tier 1 services"
        fi
    done
}

# Generate summary report
generate_summary() {
    echo
    echo "=================================="
    echo "VALIDATION SUMMARY"
    echo "=================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "ALL TESTS PASSED! 🎉"
        log_info "The startup orchestration system is ready to use."
        echo
        log_info "Next steps:"
        echo "  1. Update your .env file with valid credentials"
        echo "  2. Run: ./start-services.sh"
        echo "  3. Monitor services: docker-compose ps"
        echo "  4. Access frontend: http://localhost:3000"
        return 0
    else
        log_error "SOME TESTS FAILED! ❌"
        log_info "Please fix the failed tests before using the system."
        echo
        log_info "Common fixes:"
        echo "  - Make scripts executable: chmod +x scripts/*.sh *.sh"
        echo "  - Fix Docker Compose syntax errors"
        echo "  - Install missing dependencies"
        return 1
    fi
}

# Main execution
main() {
    echo "PyAirtable Startup System Validation"
    echo "======================================"
    echo
    
    test_docker
    test_compose_file
    test_health_checks
    test_dependencies
    test_wait_scripts
    test_orchestration_scripts
    test_environment
    test_service_tiers
    
    generate_summary
}

# Run main function
main "$@"