#!/bin/bash

# =============================================================================
# PyAirtable Secure Deployment Test Script
# =============================================================================
# This script validates the secure deployment configuration and tests basic
# connectivity to ensure all security measures are working correctly.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((TESTS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((TESTS_FAILED++))
}

test_environment_validation() {
    log_info "Testing environment validation..."
    
    # Run validation and capture output
    local validation_output=$(./validate-environment.sh 2>&1)
    local validation_exit_code=$?
    
    # Check if validation completed successfully (exit code 0)
    if [ $validation_exit_code -eq 0 ]; then
        log_success "Environment validation passed"
    else
        log_error "Environment validation failed"
        echo "$validation_output" | tail -n 10
    fi
    
    # Count warnings for information
    local warning_count=$(echo "$validation_output" | grep -c "WARNING" || true)
    if [ $warning_count -gt 0 ]; then
        log_warning "Found $warning_count warnings (non-critical)"
    fi
}

test_docker_compose_config() {
    log_info "Testing Docker Compose configuration..."
    
    if docker-compose config --quiet; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration is invalid"
    fi
}

test_database_services() {
    log_info "Testing database services startup..."
    
    # Start database services
    docker-compose up -d postgres redis
    
    # Wait for services to be healthy
    log_info "Waiting for database services to be healthy..."
    sleep 30
    
    # Check PostgreSQL
    if docker-compose exec postgres pg_isready -U postgres -d pyairtable >/dev/null 2>&1; then
        log_success "PostgreSQL is healthy and accepting connections"
    else
        log_error "PostgreSQL connection failed"
    fi
    
    # Check Redis authentication
    local redis_password=$(docker-compose exec redis env | grep REDIS_PASSWORD | cut -d'=' -f2)
    if docker-compose exec redis redis-cli --no-auth-warning -p 6380 -a "$redis_password" ping >/dev/null 2>&1; then
        log_success "Redis authentication working on custom port 6380"
    else
        log_error "Redis authentication failed"
    fi
}

test_security_configuration() {
    log_info "Testing security configuration..."
    
    # Load environment variables
    source .env
    
    # Test JWT secret strength
    if [ ${#JWT_SECRET} -ge 32 ]; then
        log_success "JWT secret meets 256-bit security requirement"
    else
        log_error "JWT secret is too weak (${#JWT_SECRET} characters)"
    fi
    
    # Test API key strength
    if [ ${#API_KEY} -ge 64 ]; then
        log_success "API key meets 256-bit security requirement"
    else
        log_error "API key is too weak (${#API_KEY} characters)"
    fi
    
    # Test password complexity
    if [ ${#POSTGRES_PASSWORD} -ge 32 ]; then
        log_success "PostgreSQL password meets security requirement"
    else
        log_error "PostgreSQL password is too weak (${#POSTGRES_PASSWORD} characters)"
    fi
    
    # Test Redis password
    if [ ${#REDIS_PASSWORD} -ge 16 ]; then
        log_success "Redis password meets security requirement"
    else
        log_error "Redis password is too weak (${#REDIS_PASSWORD} characters)"
    fi
}

test_network_security() {
    log_info "Testing network security configuration..."
    
    # Check if Redis is not exposed on default port
    if ! netstat -tulpn 2>/dev/null | grep -q ":6379 "; then
        log_success "Redis is not exposed on default port 6379"
    else
        log_warning "Redis may be exposed on default port 6379"
    fi
    
    # Check Docker networks
    if docker network ls | grep -q "pyairtable-network"; then
        log_success "Custom Docker network is configured"
    else
        log_error "Custom Docker network not found"
    fi
}

test_cors_configuration() {
    log_info "Testing CORS configuration..."
    
    source .env
    
    # Check CORS origins are not wildcard in production-like environments
    if [[ "$ENVIRONMENT" == "production" ]] || [[ "$ENVIRONMENT" == "staging" ]]; then
        if [[ "$CORS_ORIGINS" == "*" ]]; then
            log_error "CORS origins should not be wildcard (*) in $ENVIRONMENT environment"
        else
            log_success "CORS origins properly restricted for $ENVIRONMENT environment"
        fi
    else
        log_success "CORS configuration appropriate for development environment"
    fi
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    docker-compose down >/dev/null 2>&1 || true
}

main() {
    echo "============================================================================="
    echo "PyAirtable Secure Deployment Test Suite"
    echo "============================================================================="
    
    # Run tests
    test_environment_validation
    test_docker_compose_config
    test_security_configuration
    test_cors_configuration
    test_database_services
    test_network_security
    
    # Cleanup
    cleanup_test_environment
    
    echo ""
    echo "============================================================================="
    echo "Test Results Summary"
    echo "============================================================================="
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed! ($TESTS_PASSED/$((TESTS_PASSED + TESTS_FAILED)))"
        log_success "Secure deployment configuration is ready for production use"
        echo ""
        log_info "Next steps:"
        log_info "1. Deploy to your target environment: docker-compose up -d"
        log_info "2. Monitor logs: docker-compose logs -f"
        log_info "3. Verify all services are healthy: docker-compose ps"
        exit 0
    else
        log_error "Some tests failed! ($TESTS_FAILED failures, $TESTS_PASSED successes)"
        log_error "Please review and fix the issues above before deploying"
        echo ""
        log_info "For help, refer to:"
        log_info "- SECURE_DEPLOYMENT_GUIDE.md for detailed instructions"
        log_info "- ./validate-environment.sh for environment validation"
        exit 1
    fi
}

# Run main function
main "$@"