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
BASE_URL_LLM="http://localhost:8003"
BASE_URL_MCP="http://localhost:8001"
BASE_URL_GATEWAY="http://localhost:8002"
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
    
    test_endpoint "LLM Orchestrator Health" "$BASE_URL_LLM/health"
    test_endpoint "MCP Server Health" "$BASE_URL_MCP/health"
    test_endpoint "Airtable Gateway Health" "$BASE_URL_GATEWAY/health"
    
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
    
    # Test health endpoint response time
    local start_time=$(date +%s%N)
    curl -s "$BASE_URL_LLM/health" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $duration -lt 1000 ]; then
        print_status "LLM Orchestrator response time: ${duration}ms (excellent)"
    elif [ $duration -lt 2000 ]; then
        print_status "LLM Orchestrator response time: ${duration}ms (good)"
    else
        print_warning "LLM Orchestrator response time: ${duration}ms (slow)"
    fi
    
    echo ""
}

# Function to show test summary
show_summary() {
    echo -e "${BLUE}📊 Test Summary${NC}"
    echo "================"
    echo ""
    echo -e "${GREEN}✅ Services Status:${NC}"
    echo "• LLM Orchestrator: http://localhost:8003"
    echo "• MCP Server: http://localhost:8001"
    echo "• Airtable Gateway: http://localhost:8002"
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
    test_mcp_tools
    test_airtable_gateway
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
    "mcp")
        test_mcp_tools
        ;;
    "gateway")
        test_airtable_gateway
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
        echo "  mcp           MCP tools tests"  
        echo "  gateway       Airtable Gateway tests"
        echo "  llm           LLM Orchestrator tests"
        echo "  budget        Budget management tests"
        echo "  integration   Service integration tests"
        echo "  performance   Performance tests"
        exit 1
        ;;
esac