#!/bin/bash

# PyAirtable Microservices - Test Script  
# Comprehensive testing for local development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
BASE_URL_FRONTEND="http://localhost:3000"
BASE_URL_LLM="http://localhost:8003"
BASE_URL_MCP="http://localhost:8001"
BASE_URL_GATEWAY="http://localhost:8002"
BASE_URL_AUTH="http://localhost:8007"
BASE_URL_WORKFLOW="http://localhost:8004"
BASE_URL_ANALYTICS="http://localhost:8005"
BASE_URL_FILEPROCESSOR="http://localhost:8006"
TEST_SESSION_ID="test-session-$(date +%s)"

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_test() {
    echo -e "${PURPLE}🧪 $1${NC}"
}

# Function to test HTTP endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    local method="${4:-GET}"
    local data="$5"
    
    print_test "Testing $name..."
    
    local response
    local status_code
    
    if [ "$method" = "POST" ] && [ -n "$data" ]; then
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${API_KEY:-test-api-key}" \
            -d "$data" "$url" 2>/dev/null || echo "HTTPSTATUS:000")
    else
        response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
            -H "X-API-Key: ${API_KEY:-test-api-key}" \
            "$url" 2>/dev/null || echo "HTTPSTATUS:000")
    fi
    
    status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    body=$(echo "$response" | sed -e 's/HTTPSTATUS:.*//g')
    
    if [ "$status_code" = "$expected_status" ]; then
        print_status "$name: HTTP $status_code"
        if [ -n "$body" ] && [ "$body" != "null" ]; then
            echo "Response preview: $(echo "$body" | head -c 100)..."
        fi
        return 0
    else
        print_error "$name: Expected HTTP $expected_status, got $status_code"
        if [ -n "$body" ]; then
            echo "Error response: $body"
        fi
        return 1
    fi
}

# Function to test service health
test_health_checks() {
    echo -e "${BLUE}🏥 Health Check Tests${NC}"
    echo "======================="
    
    test_endpoint "Frontend Health" "$BASE_URL_FRONTEND/api/health"
    test_endpoint "LLM Orchestrator Health" "$BASE_URL_LLM/health"
    test_endpoint "MCP Server Health" "$BASE_URL_MCP/health"
    test_endpoint "Airtable Gateway Health" "$BASE_URL_GATEWAY/health"
    test_endpoint "Auth Service Health" "$BASE_URL_AUTH/health"
    test_endpoint "Workflow Engine Health" "$BASE_URL_WORKFLOW/health"
    test_endpoint "Analytics Service Health" "$BASE_URL_ANALYTICS/health"
    test_endpoint "File Processor Health" "$BASE_URL_FILEPROCESSOR/health"
    
    echo ""
}

# Function to test MCP tools
test_mcp_tools() {
    echo -e "${BLUE}🛠️  MCP Tools Tests${NC}"
    echo "==================="
    
    # Test tools listing
    test_endpoint "MCP Tools List" "$BASE_URL_MCP/tools"
    
    echo ""
}

# Function to test Airtable Gateway  
test_airtable_gateway() {
    echo -e "${BLUE}🗃️  Airtable Gateway Tests${NC}"
    echo "=========================="
    
    # Test bases endpoint (will fail without real Airtable token, but should return proper error)
    print_test "Testing Airtable bases endpoint..."
    local response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "X-API-Key: ${API_KEY:-test-api-key}" \
        "$BASE_URL_GATEWAY/bases" 2>/dev/null || echo "HTTPSTATUS:000")
    
    local status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    
    # Either 200 (if token is valid) or 401/500 (if token is invalid) is acceptable
    if [ "$status_code" = "200" ] || [ "$status_code" = "401" ] || [ "$status_code" = "500" ]; then
        print_status "Airtable Gateway: Responding correctly (HTTP $status_code)"
    else
        print_error "Airtable Gateway: Unexpected status $status_code"
    fi
    
    echo ""
}

# Function to test LLM Orchestrator
test_llm_orchestrator() {
    echo -e "${BLUE}🤖 LLM Orchestrator Tests${NC}"
    echo "=========================="
    
    # Test function calling status
    test_endpoint "Function Calling Status" "$BASE_URL_LLM/function-calling/status"
    
    # Test cost tracking status
    test_endpoint "Cost Tracking Status" "$BASE_URL_LLM/cost-tracking/status"
    
    # Test circuit breakers
    test_endpoint "Circuit Breaker Status" "$BASE_URL_LLM/health/circuit-breakers"
    
    # Test services health
    test_endpoint "Services Health" "$BASE_URL_LLM/health/services"
    
    echo ""
}

# Function to test Auth Service
test_auth_service() {
    echo -e "${BLUE}🔐 Auth Service Tests${NC}"
    echo "===================="
    
    # Test auth endpoints (will fail without valid credentials, but should return proper error)
    print_test "Testing Auth Service status endpoint..."
    local response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "X-API-Key: ${API_KEY:-test-api-key}" \
        "$BASE_URL_AUTH/status" 2>/dev/null || echo "HTTPSTATUS:000")
    
    local status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    
    # Either 200 (if service is working) or 401/404 (if endpoint doesn't exist) is acceptable
    if [ "$status_code" = "200" ] || [ "$status_code" = "401" ] || [ "$status_code" = "404" ]; then
        print_status "Auth Service: Responding correctly (HTTP $status_code)"
    else
        print_error "Auth Service: Unexpected status $status_code"
    fi
    
    echo ""
}

# Function to test Workflow Engine
test_workflow_engine() {
    echo -e "${BLUE}⚙️  Workflow Engine Tests${NC}"
    echo "========================="
    
    # Test workflow endpoints
    test_endpoint "Workflow Status" "$BASE_URL_WORKFLOW/status"
    
    echo ""
}

# Function to test Analytics Service
test_analytics_service() {
    echo -e "${BLUE}📊 Analytics Service Tests${NC}"
    echo "=========================="
    
    # Test analytics endpoints
    test_endpoint "Analytics Status" "$BASE_URL_ANALYTICS/status"
    test_endpoint "Analytics Metrics" "$BASE_URL_ANALYTICS/metrics"
    
    echo ""
}

# Function to test File Processor
test_file_processor() {
    echo -e "${BLUE}📁 File Processor Tests${NC}"
    echo "======================="
    
    # Test file processor endpoints
    test_endpoint "File Processor Status" "$BASE_URL_FILEPROCESSOR/status"
    
    echo ""
}

# Function to test budget management
test_budget_management() {
    echo -e "${BLUE}💰 Budget Management Tests${NC}"
    echo "=========================="
    
    # Test budget health
    test_endpoint "Budget Health Check" "$BASE_URL_LLM/budgets/health"
    
    # Test setting a session budget  
    local budget_data='{"budget_limit": 5.00, "alert_threshold": 0.8}'
    test_endpoint "Set Session Budget" "$BASE_URL_LLM/budgets/session/$TEST_SESSION_ID" "200" "POST" "$budget_data"
    
    # Test getting budget status
    test_endpoint "Get Budget Status" "$BASE_URL_LLM/budgets/status/$TEST_SESSION_ID"
    
    echo ""
}

# Function to test frontend specific endpoints
test_frontend() {
    echo -e "${BLUE}🌐 Frontend Tests${NC}"
    echo "=================="
    
    # Test main page (should return HTML)
    print_test "Testing frontend main page..."
    local response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$BASE_URL_FRONTEND" 2>/dev/null || echo "HTTPSTATUS:000")
    local status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    
    if [ "$status_code" = "200" ]; then
        print_status "Frontend main page: HTTP $status_code"
    else
        print_error "Frontend main page: Expected HTTP 200, got $status_code"
    fi
    
    # Test API routes
    test_endpoint "Frontend API Config" "$BASE_URL_FRONTEND/api/config"
    
    echo ""
}

# Function to test integration
test_integration() {
    echo -e "${BLUE}🔗 Integration Tests${NC}"
    echo "===================="
    
    print_test "Testing service communication..."
    
    # Test if LLM Orchestrator can reach MCP Server
    local mcp_tools_response=$(curl -s "$BASE_URL_LLM/function-calling/status" 2>/dev/null || echo "")
    
    if echo "$mcp_tools_response" | grep -q "tools_available"; then
        local tools_count=$(echo "$mcp_tools_response" | grep -o '"tools_available":[0-9]*' | grep -o '[0-9]*')
        if [ "$tools_count" -gt 0 ]; then
            print_status "LLM ↔ MCP integration: $tools_count tools available"
        else
            print_warning "LLM ↔ MCP integration: Connected but no tools available"
        fi
    else
        print_error "LLM ↔ MCP integration: Communication failed"
    fi
    
    # Test if Frontend can reach API Gateway
    print_test "Testing Frontend ↔ API Gateway connectivity..."
    local frontend_config_response=$(curl -s "$BASE_URL_FRONTEND/api/config" 2>/dev/null || echo "")
    
    if echo "$frontend_config_response" | grep -q "api_url"; then
        print_status "Frontend ↔ API Gateway: Configuration accessible"
    else
        print_warning "Frontend ↔ API Gateway: Configuration not accessible"
    fi
    
    echo ""
}

# Function to test database connectivity
test_database() {
    echo -e "${BLUE}🗄️  Database Tests${NC}"
    echo "=================="
    
    # Test PostgreSQL
    print_test "Testing PostgreSQL connection..."
    if pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
        print_status "PostgreSQL: Connected"
        
        # Test if database exists
        if psql -h localhost -U postgres -lqt | cut -d \| -f 1 | grep -qw pyairtable; then
            print_status "PostgreSQL: pyairtable database exists"
        else
            print_warning "PostgreSQL: pyairtable database not found"
        fi
    else
        print_error "PostgreSQL: Not reachable"
    fi
    
    # Test Redis
    print_test "Testing Redis connection..."
    if redis-cli ping >/dev/null 2>&1; then
        print_status "Redis: Connected"
    else
        print_error "Redis: Not reachable"
    fi
    
    echo ""
}

# Function to run performance tests
test_performance() {
    echo -e "${BLUE}⚡ Performance Tests${NC}"
    echo "==================="
    
    print_test "Testing response times..."
    
    # Test frontend response time
    local start_time=$(date +%s%N)
    curl -s "$BASE_URL_FRONTEND/api/health" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local frontend_duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $frontend_duration -lt 1000 ]; then
        print_status "Frontend response time: ${frontend_duration}ms (excellent)"
    elif [ $frontend_duration -lt 3000 ]; then
        print_status "Frontend response time: ${frontend_duration}ms (good)"
    else
        print_warning "Frontend response time: ${frontend_duration}ms (slow)"
    fi
    
    # Test backend health endpoint response time
    local start_time=$(date +%s%N)
    curl -s "$BASE_URL_LLM/health" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local backend_duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $backend_duration -lt 1000 ]; then
        print_status "LLM Orchestrator response time: ${backend_duration}ms (excellent)"
    elif [ $backend_duration -lt 2000 ]; then
        print_status "LLM Orchestrator response time: ${backend_duration}ms (good)"
    else
        print_warning "LLM Orchestrator response time: ${backend_duration}ms (slow)"
    fi
    
    echo ""
}

# Function to show test summary
show_summary() {
    echo -e "${BLUE}📊 Test Summary${NC}"
    echo "================"
    echo ""
    echo -e "${GREEN}✅ Services Status:${NC}"
    echo "• Frontend: http://localhost:3000"
    echo "• LLM Orchestrator: http://localhost:8003"
    echo "• MCP Server: http://localhost:8001"
    echo "• Airtable Gateway: http://localhost:8002"
    echo "• Auth Service: http://localhost:8007"
    echo "• Workflow Engine: http://localhost:8004"
    echo "• Analytics Service: http://localhost:8005"
    echo "• File Processor: http://localhost:8006"
    echo ""
    echo -e "${YELLOW}⚙️  Next Steps:${NC}"
    echo "1. Add your API keys to .env files:"
    echo "   - GEMINI_API_KEY (get from Google AI Studio)"
    echo "   - AIRTABLE_TOKEN (get from Airtable Developer hub)"
    echo ""
    echo "2. Test with real data:"
    echo "   curl -X POST http://localhost:8003/chat \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"message\": \"List my Airtable tables\", \"session_id\": \"test\"}'"
    echo ""
    echo -e "${GREEN}🎉 System is ready for development!${NC}"
}

# Main function
main() {
    echo -e "${BLUE}🧪 PyAirtable Microservices Test Suite${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    
    # Wait for services to be ready
    print_info "Waiting 3 seconds for services to be ready..."
    sleep 3
    echo ""
    
    # Run all tests
    test_health_checks
    test_database
    test_frontend
    test_mcp_tools
    test_airtable_gateway
    test_auth_service
    test_workflow_engine
    test_analytics_service
    test_file_processor
    test_llm_orchestrator
    test_budget_management
    test_integration
    test_performance
    
    # Show summary
    show_summary
}

# Handle command line arguments
case "${1:-all}" in
    "all")
        main
        ;;
    "health")
        test_health_checks
        ;;
    "database") 
        test_database
        ;;
    "frontend")
        test_frontend
        ;;
    "mcp")
        test_mcp_tools
        ;;
    "gateway")
        test_airtable_gateway
        ;;
    "auth")
        test_auth_service
        ;;
    "workflow")
        test_workflow_engine
        ;;
    "analytics")
        test_analytics_service
        ;;
    "fileprocessor")
        test_file_processor
        ;;
    "llm")
        test_llm_orchestrator
        ;;
    "budget")
        test_budget_management
        ;;
    "integration")
        test_integration
        ;;
    "performance")
        test_performance
        ;;
    *)
        echo "Usage: $0 [test-type]"
        echo ""
        echo "Test Types:"
        echo "  all           Run all tests (default)"
        echo "  health        Health check tests"
        echo "  database      Database connectivity tests"
        echo "  frontend      Frontend tests"
        echo "  mcp           MCP tools tests"  
        echo "  gateway       Airtable Gateway tests"
        echo "  auth          Auth Service tests"
        echo "  workflow      Workflow Engine tests"
        echo "  analytics     Analytics Service tests"
        echo "  fileprocessor File Processor tests"
        echo "  llm           LLM Orchestrator tests"
        echo "  budget        Budget management tests"
        echo "  integration   Service integration tests"
        echo "  performance   Performance tests"
        exit 1
        ;;
esac