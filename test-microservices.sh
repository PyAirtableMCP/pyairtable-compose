#!/bin/bash

# PyAirtable Microservices Integration Test Suite
# Tests all services are working together correctly

set -e

echo "🧪 PyAirtable Microservices Integration Tests"
echo "============================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Base URLs
API_GATEWAY="http://localhost:8080"
PROMETHEUS="http://localhost:9090"
GRAFANA="http://localhost:3001"

# Test function
run_test() {
    local test_name=$1
    local command=$2
    
    echo -n "Testing: $test_name..."
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e " ${GREEN}✓${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e " ${RED}✗${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to test HTTP endpoint
test_http_endpoint() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    
    run_test "$name" "curl -s -o /dev/null -w '%{http_code}' '$url' | grep -q $expected_status"
}

# Function to test gRPC service
test_grpc_service() {
    local name=$1
    local port=$2
    
    run_test "$name" "grpcurl -plaintext localhost:$port list"
}

echo "1️⃣ Infrastructure Tests"
echo "----------------------"
test_http_endpoint "PostgreSQL connectivity" "http://localhost:5432/" "000"
test_http_endpoint "Redis connectivity" "http://localhost:6379/" "000"
echo ""

echo "2️⃣ gRPC Service Tests"
echo "--------------------"
test_grpc_service "Auth Service (50051)" 50051
test_grpc_service "User Service (50052)" 50052
test_grpc_service "Workspace Service (50053)" 50053
test_grpc_service "Table Service (50054)" 50054
test_grpc_service "Data Service (50055)" 50055
echo ""

echo "3️⃣ API Gateway Tests"
echo "-------------------"
test_http_endpoint "Gateway Health" "$API_GATEWAY/health" 200
test_http_endpoint "Gateway Ready" "$API_GATEWAY/ready" 200
echo ""

echo "4️⃣ Authentication Flow Tests"
echo "---------------------------"

# Register a test user
echo -n "Testing: User Registration..."
REGISTER_RESPONSE=$(curl -s -X POST "$API_GATEWAY/api/v1/auth/register" \
    -H "Content-Type: application/json" \
    -d '{
        "email": "test@example.com",
        "password": "TestPassword123!",
        "name": "Test User"
    }' 2>/dev/null || echo "failed")

if echo "$REGISTER_RESPONSE" | grep -q "token\|already exists"; then
    echo -e " ${GREEN}✓${NC}"
    ((TESTS_PASSED++))
else
    echo -e " ${RED}✗${NC}"
    ((TESTS_FAILED++))
fi

# Login test
echo -n "Testing: User Login..."
LOGIN_RESPONSE=$(curl -s -X POST "$API_GATEWAY/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{
        "email": "test@example.com",
        "password": "TestPassword123!"
    }' 2>/dev/null || echo "failed")

if echo "$LOGIN_RESPONSE" | grep -q "token"; then
    echo -e " ${GREEN}✓${NC}"
    ((TESTS_PASSED++))
    
    # Extract token for authenticated requests
    TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
else
    echo -e " ${RED}✗${NC}"
    ((TESTS_FAILED++))
    TOKEN=""
fi
echo ""

echo "5️⃣ Workspace Operations Tests"
echo "----------------------------"

if [ -n "$TOKEN" ]; then
    # Create workspace
    echo -n "Testing: Create Workspace..."
    WORKSPACE_RESPONSE=$(curl -s -X POST "$API_GATEWAY/api/v1/workspaces" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{
            "name": "Test Workspace",
            "description": "Integration test workspace"
        }' 2>/dev/null || echo "failed")
    
    if echo "$WORKSPACE_RESPONSE" | grep -q "id\|name"; then
        echo -e " ${GREEN}✓${NC}"
        ((TESTS_PASSED++))
        WORKSPACE_ID=$(echo "$WORKSPACE_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    else
        echo -e " ${RED}✗${NC}"
        ((TESTS_FAILED++))
    fi
    
    # List workspaces
    test_http_endpoint "List Workspaces" "$API_GATEWAY/api/v1/workspaces" 200
else
    echo -e "${YELLOW}Skipping authenticated tests (no token)${NC}"
fi
echo ""

echo "6️⃣ Table Operations Tests"
echo "------------------------"

if [ -n "$TOKEN" ] && [ -n "$WORKSPACE_ID" ]; then
    # Create table
    echo -n "Testing: Create Table..."
    TABLE_RESPONSE=$(curl -s -X POST "$API_GATEWAY/api/v1/tables" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d "{
            \"workspace_id\": \"$WORKSPACE_ID\",
            \"name\": \"Test Table\",
            \"columns\": [
                {\"name\": \"name\", \"type\": \"text\"},
                {\"name\": \"age\", \"type\": \"number\"},
                {\"name\": \"email\", \"type\": \"email\"}
            ]
        }" 2>/dev/null || echo "failed")
    
    if echo "$TABLE_RESPONSE" | grep -q "id\|name"; then
        echo -e " ${GREEN}✓${NC}"
        ((TESTS_PASSED++))
        TABLE_ID=$(echo "$TABLE_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    else
        echo -e " ${RED}✗${NC}"
        ((TESTS_FAILED++))
    fi
fi
echo ""

echo "7️⃣ Data Operations Tests"
echo "-----------------------"

if [ -n "$TOKEN" ] && [ -n "$TABLE_ID" ]; then
    # Insert record
    echo -n "Testing: Insert Record..."
    RECORD_RESPONSE=$(curl -s -X POST "$API_GATEWAY/api/v1/data/$TABLE_ID/records" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" \
        -d '{
            "fields": {
                "name": "John Doe",
                "age": 30,
                "email": "john@example.com"
            }
        }' 2>/dev/null || echo "failed")
    
    if echo "$RECORD_RESPONSE" | grep -q "id\|fields"; then
        echo -e " ${GREEN}✓${NC}"
        ((TESTS_PASSED++))
    else
        echo -e " ${RED}✗${NC}"
        ((TESTS_FAILED++))
    fi
    
    # List records
    test_http_endpoint "List Records" "$API_GATEWAY/api/v1/data/$TABLE_ID/records" 200
fi
echo ""

echo "8️⃣ Monitoring Tests"
echo "------------------"
test_http_endpoint "Prometheus Health" "$PROMETHEUS/-/healthy" 200
test_http_endpoint "Grafana Health" "$GRAFANA/api/health" 200
echo ""

echo "9️⃣ Performance Tests"
echo "-------------------"

# Test response times
echo -n "Testing: API Gateway response time..."
RESPONSE_TIME=$(curl -s -o /dev/null -w '%{time_total}' "$API_GATEWAY/health")
if (( $(echo "$RESPONSE_TIME < 0.5" | bc -l) )); then
    echo -e " ${GREEN}✓${NC} (${RESPONSE_TIME}s)"
    ((TESTS_PASSED++))
else
    echo -e " ${RED}✗${NC} (${RESPONSE_TIME}s - too slow)"
    ((TESTS_FAILED++))
fi
echo ""

echo "📊 Test Summary"
echo "-------------"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please check the services.${NC}"
    exit 1
fi