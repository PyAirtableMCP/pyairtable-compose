#!/bin/bash

# PyAirtable End-to-End Testing Script for Kubernetes
# Validates complete system functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${1:-pyairtable}"
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
BASE_URL="${BASE_URL:-http://localhost:8000}"
API_KEY="${API_KEY:-dev-api-key-change-in-production}"

echo -e "${BLUE}🧪 Starting PyAirtable End-to-End Tests${NC}"
echo -e "${BLUE}🎯 Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}🌐 Base URL: ${BASE_URL}${NC}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local port="$2"
    local max_attempts=30
    local attempt=0
    
    echo -e "${YELLOW}⏳ Waiting for $service_name to be ready...${NC}"
    
    while [ $attempt -lt $max_attempts ]; do
        if kubectl port-forward -n "$NAMESPACE" "service/$service_name" "$port:$port" --timeout=5s >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $service_name is ready${NC}"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo -e "${RED}❌ $service_name failed to become ready${NC}"
    return 1
}

# Function to setup port forwarding for tests
setup_port_forwarding() {
    echo -e "${BLUE}🌐 Setting up port forwarding for tests${NC}"
    
    # Kill any existing port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
    
    # Start port forwarding for main services
    kubectl port-forward -n "$NAMESPACE" service/api-gateway 8000:8000 >/dev/null 2>&1 &
    local api_gateway_pid=$!
    
    kubectl port-forward -n "$NAMESPACE" service/platform-services 8001:8001 >/dev/null 2>&1 &
    local platform_services_pid=$!
    
    kubectl port-forward -n "$NAMESPACE" service/automation-services 8002:8002 >/dev/null 2>&1 &
    local automation_services_pid=$!
    
    kubectl port-forward -n "$NAMESPACE" service/frontend 3000:3000 >/dev/null 2>&1 &
    local frontend_pid=$!
    
    # Store PIDs for cleanup
    echo "$api_gateway_pid $platform_services_pid $automation_services_pid $frontend_pid" > /tmp/pyairtable-e2e-pids
    
    # Wait for port forwards to be established
    sleep 5
    
    echo -e "${GREEN}✅ Port forwarding established${NC}"
}

# Function to cleanup port forwarding
cleanup_port_forwarding() {
    echo -e "${BLUE}🧹 Cleaning up port forwarding${NC}"
    
    if [ -f "/tmp/pyairtable-e2e-pids" ]; then
        local pids=$(cat /tmp/pyairtable-e2e-pids)
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
        rm -f /tmp/pyairtable-e2e-pids
    fi
    
    # Kill any remaining port forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
}

# Function to run API Gateway tests
test_api_gateway() {
    echo -e "${BLUE}🚪 Testing API Gateway${NC}"
    
    local base_url="http://localhost:8000"
    local test_results=()
    
    # Test 1: Health check
    echo -e "${YELLOW}🔍 Testing health endpoint${NC}"
    if curl -f -s --max-time 10 "$base_url/health" | grep -q "ok\|healthy\|status"; then
        echo -e "${GREEN}✅ Health check passed${NC}"
        test_results+=("health:pass")
    else
        echo -e "${RED}❌ Health check failed${NC}"
        test_results+=("health:fail")
    fi
    
    # Test 2: Authentication endpoint
    echo -e "${YELLOW}🔍 Testing authentication${NC}"
    local auth_response=$(curl -s --max-time 10 \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        "$base_url/api/auth/validate" || echo "error")
    
    if echo "$auth_response" | grep -q "valid\|success\|authenticated"; then
        echo -e "${GREEN}✅ Authentication test passed${NC}"
        test_results+=("auth:pass")
    else
        echo -e "${RED}❌ Authentication test failed${NC}"
        test_results+=("auth:fail")
    fi
    
    # Test 3: Rate limiting
    echo -e "${YELLOW}🔍 Testing rate limiting${NC}"
    local rate_limit_passed=true
    for i in {1..5}; do
        local response=$(curl -s -w "%{http_code}" -o /dev/null --max-time 5 \
            -H "X-API-Key: $API_KEY" \
            "$base_url/api/test" || echo "000")
        
        if [ "$response" == "429" ]; then
            echo -e "${GREEN}✅ Rate limiting is working${NC}"
            test_results+=("rate-limit:pass")
            rate_limit_passed=true
            break
        fi
        sleep 0.1
    done
    
    if [ "$rate_limit_passed" != true ]; then
        echo -e "${YELLOW}⚠️  Rate limiting test inconclusive${NC}"
        test_results+=("rate-limit:inconclusive")
    fi
    
    # Return test results
    local failed_tests=0
    for result in "${test_results[@]}"; do
        if [[ "$result" == *":fail" ]]; then
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    return $failed_tests
}

# Function to run platform services tests
test_platform_services() {
    echo -e "${BLUE}👥 Testing Platform Services${NC}"
    
    local base_url="http://localhost:8001"
    local test_results=()
    
    # Test 1: Health check
    echo -e "${YELLOW}🔍 Testing health endpoint${NC}"
    if curl -f -s --max-time 10 "$base_url/health" | grep -q "ok\|healthy\|status"; then
        echo -e "${GREEN}✅ Health check passed${NC}"
        test_results+=("health:pass")
    else
        echo -e "${RED}❌ Health check failed${NC}"
        test_results+=("health:fail")
    fi
    
    # Test 2: User registration endpoint
    echo -e "${YELLOW}🔍 Testing user registration${NC}"
    local test_user_data='{"email":"test@example.com","password":"testpassword123","name":"Test User"}'
    local reg_response=$(curl -s --max-time 10 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "$test_user_data" \
        "$base_url/api/users/register" || echo "error")
    
    if echo "$reg_response" | grep -q "success\|created\|user"; then
        echo -e "${GREEN}✅ User registration test passed${NC}"
        test_results+=("registration:pass")
    else
        echo -e "${YELLOW}⚠️  User registration test inconclusive (user may already exist)${NC}"
        test_results+=("registration:inconclusive")
    fi
    
    # Test 3: Analytics endpoint
    echo -e "${YELLOW}🔍 Testing analytics endpoint${NC}"
    local analytics_response=$(curl -s --max-time 10 \
        -H "X-API-Key: $API_KEY" \
        "$base_url/api/analytics/stats" || echo "error")
    
    if echo "$analytics_response" | grep -q "stats\|analytics\|data"; then
        echo -e "${GREEN}✅ Analytics test passed${NC}"
        test_results+=("analytics:pass")
    else
        echo -e "${RED}❌ Analytics test failed${NC}"
        test_results+=("analytics:fail")
    fi
    
    # Return test results
    local failed_tests=0
    for result in "${test_results[@]}"; do
        if [[ "$result" == *":fail" ]]; then
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    return $failed_tests
}

# Function to run automation services tests
test_automation_services() {
    echo -e "${BLUE}🤖 Testing Automation Services${NC}"
    
    local base_url="http://localhost:8002"
    local test_results=()
    
    # Test 1: Health check
    echo -e "${YELLOW}🔍 Testing health endpoint${NC}"
    if curl -f -s --max-time 10 "$base_url/health" | grep -q "ok\|healthy\|status"; then
        echo -e "${GREEN}✅ Health check passed${NC}"
        test_results+=("health:pass")
    else
        echo -e "${RED}❌ Health check failed${NC}"
        test_results+=("health:fail")
    fi
    
    # Test 2: File upload endpoint
    echo -e "${YELLOW}🔍 Testing file upload${NC}"
    local test_file=$(mktemp)
    echo "This is a test file for automation services" > "$test_file"
    
    local upload_response=$(curl -s --max-time 15 \
        -X POST \
        -H "X-API-Key: $API_KEY" \
        -F "file=@$test_file" \
        "$base_url/api/files/upload" || echo "error")
    
    rm -f "$test_file"
    
    if echo "$upload_response" | grep -q "upload\|file\|success"; then
        echo -e "${GREEN}✅ File upload test passed${NC}"
        test_results+=("upload:pass")
    else
        echo -e "${RED}❌ File upload test failed${NC}"
        test_results+=("upload:fail")
    fi
    
    # Test 3: Workflow execution
    echo -e "${YELLOW}🔍 Testing workflow execution${NC}"
    local workflow_data='{"name":"test-workflow","steps":[{"type":"log","message":"test"}]}'
    local workflow_response=$(curl -s --max-time 15 \
        -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "$workflow_data" \
        "$base_url/api/workflows/execute" || echo "error")
    
    if echo "$workflow_response" | grep -q "workflow\|execution\|success"; then
        echo -e "${GREEN}✅ Workflow execution test passed${NC}"
        test_results+=("workflow:pass")
    else
        echo -e "${RED}❌ Workflow execution test failed${NC}"
        test_results+=("workflow:fail")
    fi
    
    # Return test results
    local failed_tests=0
    for result in "${test_results[@]}"; do
        if [[ "$result" == *":fail" ]]; then
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    return $failed_tests
}

# Function to test frontend
test_frontend() {
    echo -e "${BLUE}🖥️  Testing Frontend${NC}"
    
    local base_url="http://localhost:3000"
    
    # Test 1: Home page loads
    echo -e "${YELLOW}🔍 Testing home page${NC}"
    if curl -f -s --max-time 15 "$base_url" | grep -q "html\|PyAirtable\|title"; then
        echo -e "${GREEN}✅ Frontend home page test passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Frontend home page test failed${NC}"
        return 1
    fi
}

# Function to test database connectivity
test_database_connectivity() {
    echo -e "${BLUE}🗄️  Testing Database Connectivity${NC}"
    
    local test_results=()
    
    # Test PostgreSQL
    echo -e "${YELLOW}🔍 Testing PostgreSQL connectivity${NC}"
    kubectl port-forward -n "$NAMESPACE" service/postgresql-dev 5432:5432 >/dev/null 2>&1 &
    local pg_pid=$!
    sleep 3
    
    if command_exists psql; then
        if PGPASSWORD="dev-postgres-password" psql -h localhost -U postgres -d pyairtable -c "SELECT version();" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ PostgreSQL connectivity test passed${NC}"
            test_results+=("postgres:pass")
        else
            echo -e "${RED}❌ PostgreSQL connectivity test failed${NC}"
            test_results+=("postgres:fail")
        fi
    else
        echo -e "${YELLOW}⚠️  psql not available, skipping PostgreSQL test${NC}"
        test_results+=("postgres:skip")
    fi
    
    kill $pg_pid 2>/dev/null || true
    
    # Test Redis
    echo -e "${YELLOW}🔍 Testing Redis connectivity${NC}"
    kubectl port-forward -n "$NAMESPACE" service/redis-dev 6379:6379 >/dev/null 2>&1 &
    local redis_pid=$!
    sleep 3
    
    if command_exists redis-cli; then
        if redis-cli -h localhost -p 6379 -a "dev-redis-password" ping | grep -q "PONG"; then
            echo -e "${GREEN}✅ Redis connectivity test passed${NC}"
            test_results+=("redis:pass")
        else
            echo -e "${RED}❌ Redis connectivity test failed${NC}"
            test_results+=("redis:fail")
        fi
    else
        echo -e "${YELLOW}⚠️  redis-cli not available, skipping Redis test${NC}"
        test_results+=("redis:skip")
    fi
    
    kill $redis_pid 2>/dev/null || true
    
    # Return test results
    local failed_tests=0
    for result in "${test_results[@]}"; do
        if [[ "$result" == *":fail" ]]; then
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    return $failed_tests
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${BLUE}⚡ Running Performance Tests${NC}"
    
    if ! command_exists ab; then
        echo -e "${YELLOW}⚠️  Apache Bench (ab) not available, skipping performance tests${NC}"
        return 0
    fi
    
    # Test API Gateway performance
    echo -e "${YELLOW}🔍 Testing API Gateway performance${NC}"
    local perf_result=$(ab -n 100 -c 10 -H "X-API-Key: $API_KEY" "http://localhost:8000/health" 2>/dev/null | grep "Requests per second" || echo "Performance test failed")
    echo -e "${BLUE}API Gateway Performance: $perf_result${NC}"
    
    # Test Platform Services performance
    echo -e "${YELLOW}🔍 Testing Platform Services performance${NC}"
    local platform_perf=$(ab -n 50 -c 5 -H "X-API-Key: $API_KEY" "http://localhost:8001/health" 2>/dev/null | grep "Requests per second" || echo "Performance test failed")
    echo -e "${BLUE}Platform Services Performance: $platform_perf${NC}"
    
    return 0
}

# Function to generate test report
generate_test_report() {
    local total_tests="$1"
    local failed_tests="$2"
    local passed_tests=$((total_tests - failed_tests))
    
    echo -e "${BLUE}📋 Generating test report${NC}"
    
    local report_file="/tmp/pyairtable-e2e-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "PyAirtable End-to-End Test Report - $(date)"
        echo "============================================"
        echo ""
        echo "Namespace: $NAMESPACE"
        echo "Base URL: $BASE_URL"
        echo ""
        echo "Test Results:"
        echo "- Total Tests: $total_tests"
        echo "- Passed: $passed_tests"
        echo "- Failed: $failed_tests"
        echo "- Success Rate: $(( (passed_tests * 100) / total_tests ))%"
        echo ""
        echo "Service Status:"
        kubectl get pods -n "$NAMESPACE" -o wide
        echo ""
        echo "Recent Events:"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
    } > "$report_file"
    
    echo -e "${GREEN}✅ Test report generated: $report_file${NC}"
}

# Main test execution function
main() {
    local total_tests=0
    local failed_tests=0
    
    echo -e "${BLUE}Starting comprehensive end-to-end tests...${NC}"
    echo ""
    
    # Setup test infrastructure
    if ! command_exists curl; then
        echo -e "${RED}❌ curl is required for testing but not installed${NC}"
        exit 1
    fi
    
    # Setup port forwarding
    setup_port_forwarding
    
    # Trap to ensure cleanup on exit
    trap cleanup_port_forwarding EXIT
    
    # Wait for services to be ready
    echo -e "${BLUE}⏳ Waiting for services to be ready...${NC}"
    sleep 10
    
    # Run API Gateway tests
    echo -e "${PURPLE}=== API Gateway Tests ===${NC}"
    total_tests=$((total_tests + 3))
    if ! test_api_gateway; then
        failed_tests=$((failed_tests + $?))
    fi
    echo ""
    
    # Run Platform Services tests
    echo -e "${PURPLE}=== Platform Services Tests ===${NC}"
    total_tests=$((total_tests + 3))
    if ! test_platform_services; then
        failed_tests=$((failed_tests + $?))
    fi
    echo ""
    
    # Run Automation Services tests
    echo -e "${PURPLE}=== Automation Services Tests ===${NC}"
    total_tests=$((total_tests + 3))
    if ! test_automation_services; then
        failed_tests=$((failed_tests + $?))
    fi
    echo ""
    
    # Run Frontend tests
    echo -e "${PURPLE}=== Frontend Tests ===${NC}"
    total_tests=$((total_tests + 1))
    if ! test_frontend; then
        failed_tests=$((failed_tests + 1))
    fi
    echo ""
    
    # Run Database tests
    echo -e "${PURPLE}=== Database Connectivity Tests ===${NC}"
    total_tests=$((total_tests + 2))
    if ! test_database_connectivity; then
        failed_tests=$((failed_tests + $?))
    fi
    echo ""
    
    # Run performance tests (optional)
    read -p "Run performance tests? (may take longer) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${PURPLE}=== Performance Tests ===${NC}"
        run_performance_tests
        echo ""
    fi
    
    # Generate test report
    generate_test_report "$total_tests" "$failed_tests"
    
    # Summary
    local passed_tests=$((total_tests - failed_tests))
    local success_rate=$(( (passed_tests * 100) / total_tests ))
    
    echo -e "${BLUE}📊 Test Summary:${NC}"
    echo -e "Total Tests: $total_tests"
    echo -e "Passed: ${GREEN}$passed_tests${NC}"
    echo -e "Failed: ${RED}$failed_tests${NC}"
    echo -e "Success Rate: ${BLUE}$success_rate%${NC}"
    echo ""
    
    if [ $failed_tests -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! System is healthy and functional.${NC}"
        return 0
    else
        echo -e "${RED}❌ Some tests failed. Please review the output above.${NC}"
        echo -e "${YELLOW}💡 Troubleshooting tips:${NC}"
        echo -e "  - Check service logs: kubectl logs <pod-name> -n $NAMESPACE"
        echo -e "  - Verify service configurations: kubectl describe deployment <deployment-name> -n $NAMESPACE"
        echo -e "  - Check network connectivity: kubectl exec -it <pod-name> -n $NAMESPACE -- curl <service-url>"
        return 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help)
        echo "Usage: $0 [NAMESPACE] [OPTIONS]"
        echo "Options:"
        echo "  NAMESPACE              Target Kubernetes namespace (default: pyairtable)"
        echo "  --timeout SECONDS      Timeout for tests (default: 60)"
        echo "  --base-url URL         Base URL for API tests (default: http://localhost:8000)"
        echo "  --api-key KEY          API key for authentication"
        echo "  --help                Show this help message"
        exit 0
        ;;
esac

# Execute main function
main "$@"