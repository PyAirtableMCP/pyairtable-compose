#!/bin/bash

# =============================================================================
# PyAirtable Service Connectivity Test
# =============================================================================
# This script tests connectivity between all PyAirtable services
# Run after starting services to verify proper networking configuration
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test HTTP endpoint
test_endpoint() {
    local service="$1"
    local url="$2"
    local expected_status="${3:-200}"
    local timeout="${4:-10}"
    
    ((TOTAL_TESTS++))
    
    log_info "Testing $service: $url"
    
    if response=$(curl -s -w "%{http_code}" -m "$timeout" --fail-with-body "$url" 2>/dev/null); then
        status_code="${response: -3}"
        if [[ "$status_code" == "$expected_status" ]]; then
            log_success "$service is responding correctly (HTTP $status_code)"
            return 0
        else
            log_error "$service returned HTTP $status_code (expected $expected_status)"
            return 1
        fi
    else
        log_error "$service is not responding or connection failed"
        return 1
    fi
}

# Test internal service connectivity
test_internal_connectivity() {
    local from_service="$1"
    local to_service="$2"
    local to_url="$3"
    
    ((TOTAL_TESTS++))
    
    log_info "Testing internal connectivity: $from_service -> $to_service"
    
    if docker-compose exec -T "$from_service" curl -s -f -m 5 "$to_url" >/dev/null 2>&1; then
        log_success "Internal connectivity: $from_service -> $to_service"
        return 0
    else
        log_error "Internal connectivity failed: $from_service -> $to_service"
        return 1
    fi
}

# Test database connectivity
test_database() {
    ((TOTAL_TESTS++))
    
    log_info "Testing PostgreSQL database connectivity"
    
    if docker-compose exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
        log_success "PostgreSQL is ready and accepting connections"
    else
        log_error "PostgreSQL is not responding"
        return 1
    fi
    
    # Test database connection with credentials
    if docker-compose exec -T postgres psql -U postgres -d pyairtable -c "SELECT 1;" >/dev/null 2>&1; then
        log_success "PostgreSQL authentication and database access working"
        return 0
    else
        log_error "PostgreSQL authentication or database access failed"
        return 1
    fi
}

# Test Redis connectivity
test_redis() {
    ((TOTAL_TESTS++))
    
    log_info "Testing Redis connectivity"
    
    # Load environment to get Redis password
    if [ -f .env ]; then
        source .env
    fi
    
    if docker-compose exec -T redis redis-cli -a "${REDIS_PASSWORD}" ping >/dev/null 2>&1; then
        log_success "Redis is responding to ping"
        return 0
    else
        log_error "Redis is not responding or authentication failed"
        return 1
    fi
}

# Test Docker network
test_docker_network() {
    ((TOTAL_TESTS++))
    
    log_info "Testing Docker network configuration"
    
    # Check if network exists
    if docker network ls | grep -q "pyairtable-network"; then
        log_success "Docker network 'pyairtable-network' exists"
    else
        log_error "Docker network 'pyairtable-network' not found"
        return 1
    fi
    
    # Check if services are connected to network
    local network_services
    network_services=$(docker network inspect pyairtable-compose_pyairtable-network --format='{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || true)
    
    if [[ -n "$network_services" ]]; then
        log_success "Services connected to network: $network_services"
        return 0
    else
        log_warning "No services found on network (services may not be running)"
        return 1
    fi
}

# Check service status
check_service_status() {
    log_info "Checking Docker Compose service status"
    
    local running_services
    running_services=$(docker-compose ps --services --filter "status=running" 2>/dev/null || true)
    
    if [[ -n "$running_services" ]]; then
        log_info "Running services:"
        echo "$running_services" | while read -r service; do
            echo "  ✓ $service"
        done
    else
        log_warning "No services are currently running"
        log_info "Start services with: docker-compose up -d"
    fi
    
    echo ""
    
    local stopped_services
    stopped_services=$(docker-compose ps --services --filter "status=exited" 2>/dev/null || true)
    
    if [[ -n "$stopped_services" ]]; then
        log_warning "Stopped services:"
        echo "$stopped_services" | while read -r service; do
            echo "  ✗ $service"
        done
        echo ""
    fi
}

# Main test function
run_connectivity_tests() {
    echo "============================================================================="
    echo "PyAirtable Service Connectivity Test"
    echo "============================================================================="
    
    # Check if Docker Compose is available
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check service status first
    check_service_status
    
    log_info "Testing basic infrastructure..."
    
    # Test Docker network
    test_docker_network
    
    # Test databases
    test_database
    test_redis
    
    echo ""
    log_info "Testing external service endpoints..."
    
    # Test external endpoints (from host)
    test_endpoint "API Gateway" "http://localhost:8000/health" "200" 10
    test_endpoint "MCP Server" "http://localhost:8001/health" "200" 10
    test_endpoint "Airtable Gateway" "http://localhost:8002/health" "200" 10
    test_endpoint "LLM Orchestrator" "http://localhost:8003/health" "200" 10
    test_endpoint "Automation Services" "http://localhost:8006/health" "200" 10
    test_endpoint "Platform Services" "http://localhost:8007/health" "200" 10
    test_endpoint "SAGA Orchestrator" "http://localhost:8008/health" "200" 10
    test_endpoint "Frontend" "http://localhost:3000" "200" 10
    
    echo ""
    log_info "Testing internal service connectivity..."
    
    # Test internal connectivity (service-to-service)
    # Only test if services are running
    if docker-compose ps api-gateway | grep -q "Up"; then
        test_internal_connectivity "api-gateway" "airtable-gateway" "http://airtable-gateway:8002/health"
        test_internal_connectivity "api-gateway" "mcp-server" "http://mcp-server:8001/health"
        test_internal_connectivity "api-gateway" "llm-orchestrator" "http://llm-orchestrator:8003/health"
    else
        log_warning "API Gateway not running, skipping internal connectivity tests"
    fi
    
    if docker-compose ps llm-orchestrator | grep -q "Up"; then
        test_internal_connectivity "llm-orchestrator" "mcp-server" "http://mcp-server:8001/health"
        test_internal_connectivity "llm-orchestrator" "redis" "http://redis:6379" || true # Redis doesn't have HTTP endpoint
    else
        log_warning "LLM Orchestrator not running, skipping some connectivity tests"
    fi
    
    echo ""
    echo "============================================================================="
    echo "Test Results Summary"
    echo "============================================================================="
    
    log_info "Total tests run: $TOTAL_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All tests passed! ✅"
        log_info "PyAirtable services are properly configured and communicating"
    else
        log_error "Failed tests: $FAILED_TESTS"
        log_success "Passed tests: $PASSED_TESTS"
        
        echo ""
        log_info "Troubleshooting steps:"
        log_info "1. Check service logs: docker-compose logs [service-name]"
        log_info "2. Verify environment configuration: ./validate-environment.sh"
        log_info "3. Restart failed services: docker-compose restart [service-name]"
        log_info "4. Check Docker network: docker network inspect pyairtable-compose_pyairtable-network"
        
        return 1
    fi
    
    echo ""
    log_info "Next steps:"
    log_info "1. Test the complete workflow with: python test_complete_workflow.py"
    log_info "2. Access the frontend at: http://localhost:3000"
    log_info "3. Check API documentation at: http://localhost:8000/docs"
}

# Performance test
run_performance_test() {
    echo ""
    log_info "Running basic performance test..."
    
    # Test response times
    for endpoint in \
        "http://localhost:8000/health" \
        "http://localhost:8001/health" \
        "http://localhost:8002/health" \
        "http://localhost:8003/health"; do
        
        if response_time=$(curl -o /dev/null -s -w "%{time_total}" "$endpoint" 2>/dev/null); then
            if (( $(echo "$response_time < 1.0" | bc -l) )); then
                log_success "Response time for $endpoint: ${response_time}s"
            else
                log_warning "Slow response time for $endpoint: ${response_time}s"
            fi
        fi
    done
}

# Main execution
main() {
    # Change to project directory
    cd "$(dirname "$0")"
    
    # Run connectivity tests
    if run_connectivity_tests; then
        # Run performance test if all connectivity tests pass
        if command -v bc &> /dev/null; then
            run_performance_test
        fi
        
        echo ""
        log_success "Service connectivity test completed successfully!"
        exit 0
    else
        log_error "Service connectivity test failed!"
        exit 1
    fi
}

# Run main function
main "$@"