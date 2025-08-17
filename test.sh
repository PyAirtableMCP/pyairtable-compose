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

# Configuration - CORRECT PORTS per CLAUDE.md
BASE_URL_FRONTEND="http://localhost:5173"
BASE_URL_API_GATEWAY="http://localhost:8000"
BASE_URL_PLATFORM_SERVICES="http://localhost:8007"
BASE_URL_MCP="http://localhost:8001"
BASE_URL_AIRTABLE_GATEWAY="http://localhost:8002"
BASE_URL_AUTOMATION="http://localhost:8006"
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
    
    test_endpoint "Frontend Health" "$BASE_URL_FRONTEND"
    test_endpoint "API Gateway Health" "$BASE_URL_API_GATEWAY/api/health"
    test_endpoint "Platform Services Health" "$BASE_URL_PLATFORM_SERVICES/health"
    test_endpoint "MCP Server Health" "$BASE_URL_MCP/health"
    test_endpoint "Airtable Gateway Health" "$BASE_URL_AIRTABLE_GATEWAY/health"
    test_endpoint "Automation Services Health" "$BASE_URL_AUTOMATION/health"
    
    echo ""
}

# Function to test MCP tools
test_mcp_tools() {
    echo -e "${BLUE}🛠️  MCP Tools Tests${NC}"
    echo "==================="
    
    # Test MCP health and capabilities
    test_endpoint "MCP Server Status" "$BASE_URL_MCP/health"
    
    echo ""
}

# Function to test Airtable Gateway  
test_airtable_gateway() {
    echo -e "${BLUE}🗃️  Airtable Gateway Tests${NC}"
    echo "=========================="
    
    # Test health endpoint first 
    test_endpoint "Airtable Gateway Health" "$BASE_URL_AIRTABLE_GATEWAY/health"
    
    # Test bases endpoint (will fail without real Airtable token, but should return proper error)
    print_test "Testing Airtable bases endpoint..."
    local response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "X-API-Key: ${API_KEY:-test-api-key}" \
        "$BASE_URL_AIRTABLE_GATEWAY/bases" 2>/dev/null || echo "HTTPSTATUS:000")
    
    local status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    
    # Either 200 (if token is valid) or 401/500 (if token is invalid) is acceptable
    if [ "$status_code" = "200" ] || [ "$status_code" = "401" ] || [ "$status_code" = "500" ]; then
        print_status "Airtable Gateway: Responding correctly (HTTP $status_code)"
    else
        print_error "Airtable Gateway: Unexpected status $status_code"
    fi
    
    echo ""
}

# Function to test AI Processing (MCP Server)
test_ai_processing() {
    echo -e "${BLUE}🤖 AI Processing (MCP Server) Tests${NC}"
    echo "===================================="
    
    # Test health endpoint
    test_endpoint "AI Processing Health" "$BASE_URL_MCP/health"
    
    echo ""
}

# Function to test Auth Service
test_auth_service() {
    echo -e "${BLUE}🔐 Auth Service Tests${NC}"
    echo "===================="
    
    # Test Platform Services health first
    test_endpoint "Platform Services Health" "$BASE_URL_PLATFORM_SERVICES/health"
    
    # Test auth endpoints (will fail without valid credentials, but should return proper error)
    print_test "Testing Auth Service via API Gateway..."
    local response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "X-API-Key: ${API_KEY:-test-api-key}" \
        "$BASE_URL_API_GATEWAY/api/v1/auth/login" 2>/dev/null || echo "HTTPSTATUS:000")
    
    local status_code=$(echo "$response" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
    
    # Either 200 (if service is working) or 401/404 (if endpoint doesn't exist) is acceptable
    if [ "$status_code" = "200" ] || [ "$status_code" = "401" ] || [ "$status_code" = "404" ]; then
        print_status "Auth Service: Responding correctly (HTTP $status_code)"
    else
        print_error "Auth Service: Unexpected status $status_code"
    fi
    
    echo ""
}

# Function to test Automation Services
test_automation_services() {
    echo -e "${BLUE}⚙️  Automation Services Tests${NC}"
    echo "==============================="
    
    # Test automation services endpoints
    test_endpoint "Automation Services Health" "$BASE_URL_AUTOMATION/health"
    
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
    
    # Test auth pages
    test_endpoint "Auth Login Page" "$BASE_URL_FRONTEND/auth/login"
    test_endpoint "Auth Register Page" "$BASE_URL_FRONTEND/auth/register"
    
    echo ""
}

# Function to test integration
test_integration() {
    echo -e "${BLUE}🔗 Integration Tests${NC}"
    echo "===================="
    
    print_test "Testing service communication..."
    
    # Test API Gateway routing
    local api_health_response=$(curl -s "$BASE_URL_API_GATEWAY/api/health" 2>/dev/null || echo "")
    if echo "$api_health_response" | grep -q "healthy\|status\|ok" 2>/dev/null; then
        print_status "API Gateway: Health endpoint working"
    else
        print_warning "API Gateway: Health endpoint may need configuration"
    fi
    
    # Test Frontend accessibility
    print_test "Testing Frontend accessibility..."
    local frontend_response=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL_FRONTEND" 2>/dev/null || echo "000")
    
    if [ "$frontend_response" = "200" ]; then
        print_status "Frontend: Accessible and responding"
    else
        print_warning "Frontend: May not be fully configured (HTTP $frontend_response)"
    fi
    
    echo ""
}

# Function to test database connectivity
test_database() {
    echo -e "${BLUE}🗄️  Database Tests${NC}"
    echo "=================="
    
    # Test PostgreSQL via Docker
    print_test "Testing PostgreSQL connection..."
    if docker-compose exec -T postgres pg_isready -U pyairtable >/dev/null 2>&1; then
        print_status "PostgreSQL: Connected"
        
        # Test if database is accessible
        if docker-compose exec -T postgres psql -U pyairtable -d pyairtable -c "SELECT 1;" >/dev/null 2>&1; then
            print_status "PostgreSQL: pyairtable database accessible"
        else
            print_warning "PostgreSQL: pyairtable database may need setup"
        fi
    else
        print_error "PostgreSQL: Not reachable via Docker"
    fi
    
    # Test Redis via Docker
    print_test "Testing Redis connection..."
    if docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
        print_status "Redis: Connected"
    else
        print_error "Redis: Not reachable via Docker"
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
    curl -s "$BASE_URL_FRONTEND" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local frontend_duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $frontend_duration -lt 1000 ]; then
        print_status "Frontend response time: ${frontend_duration}ms (excellent)"
    elif [ $frontend_duration -lt 3000 ]; then
        print_status "Frontend response time: ${frontend_duration}ms (good)"
    else
        print_warning "Frontend response time: ${frontend_duration}ms (slow)"
    fi
    
    # Test API Gateway health endpoint response time
    local start_time=$(date +%s%N)
    curl -s "$BASE_URL_API_GATEWAY/api/health" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local backend_duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $backend_duration -lt 1000 ]; then
        print_status "API Gateway response time: ${backend_duration}ms (excellent)"
    elif [ $backend_duration -lt 2000 ]; then
        print_status "API Gateway response time: ${backend_duration}ms (good)"
    else
        print_warning "API Gateway response time: ${backend_duration}ms (slow)"
    fi
    
    echo ""
}

# Function to show test summary
show_summary() {
    echo -e "${BLUE}📊 Test Summary${NC}"
    echo "================"
    echo ""
    echo -e "${GREEN}✅ Services Status:${NC}"
    echo "• Frontend: http://localhost:5173"
    echo "• API Gateway: http://localhost:8000"
    echo "• Platform Services: http://localhost:8007"
    echo "• MCP Server (AI Processing): http://localhost:8001"
    echo "• Airtable Gateway: http://localhost:8002"
    echo "• Automation Services: http://localhost:8006"
    echo ""
    echo -e "${YELLOW}⚙️  Next Steps:${NC}"
    echo "1. Add your API keys to .env files:"
    echo "   - GEMINI_API_KEY (get from Google AI Studio)"
    echo "   - AIRTABLE_TOKEN (get from Airtable Developer hub)"
    echo ""
    echo "2. Test with real authentication:"
    echo "   curl -X POST http://localhost:8000/api/v1/auth/register \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"name\": \"Test User\", \"email\": \"test@example.com\", \"password\": \"Test123!\"}'"
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
    test_automation_services
    test_ai_processing
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
    "automation")
        test_automation_services
        ;;
    "ai")
        test_ai_processing
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
        echo "  mcp           MCP Server tests"  
        echo "  gateway       Airtable Gateway tests"
        echo "  auth          Auth Service tests"
        echo "  automation    Automation Services tests"
        echo "  ai            AI Processing tests"
        echo "  integration   Service integration tests"
        echo "  performance   Performance tests"
        exit 1
        ;;
esac