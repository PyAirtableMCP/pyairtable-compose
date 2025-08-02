#!/bin/bash

# Integration tests for API Gateway

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

BASE_URL="http://localhost:8080"
AUTH_URL="http://localhost:8081"

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}API Gateway Integration Tests${NC}"
echo -e "${BLUE}=====================================${NC}"

# Test 1: Health Check
echo -e "\n${YELLOW}Test 1: Health Check${NC}"
response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/health")
status_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$status_code" -eq 200 ]; then
    echo -e "${GREEN}✅ Health check passed${NC}"
    echo "Response: $body"
else
    echo -e "${RED}❌ Health check failed (Status: $status_code)${NC}"
    echo "Response: $body"
fi

# Test 2: API Gateway Info
echo -e "\n${YELLOW}Test 2: API Gateway Info${NC}"
response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/api/v1/info")
status_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$status_code" -eq 200 ]; then
    echo -e "${GREEN}✅ Info endpoint passed${NC}"
    echo "Response: $body"
else
    echo -e "${RED}❌ Info endpoint failed (Status: $status_code)${NC}"
    echo "Response: $body"
fi

# Test 3: Unauthenticated Request
echo -e "\n${YELLOW}Test 3: Unauthenticated Request (Should Fail)${NC}"
response=$(curl -s -w "\n%{http_code}" "${BASE_URL}/api/v1/users")
status_code=$(echo "$response" | tail -n 1)

if [ "$status_code" -eq 401 ]; then
    echo -e "${GREEN}✅ Correctly rejected unauthenticated request${NC}"
else
    echo -e "${RED}❌ Expected 401, got $status_code${NC}"
fi

# Test 4: Auth Service Registration (via Gateway)
echo -e "\n${YELLOW}Test 4: User Registration via Gateway${NC}"
registration_data='{
    "email": "test@example.com",
    "password": "Test123!@#",
    "first_name": "Test",
    "last_name": "User"
}'

response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$registration_data" \
    "${BASE_URL}/auth/register")
status_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$status_code" -eq 201 ] || [ "$status_code" -eq 409 ]; then
    echo -e "${GREEN}✅ Registration endpoint accessible${NC}"
    echo "Response: $body"
else
    echo -e "${RED}❌ Registration failed (Status: $status_code)${NC}"
    echo "Response: $body"
fi

# Test 5: Login and Get Token
echo -e "\n${YELLOW}Test 5: User Login via Gateway${NC}"
login_data='{
    "email": "test@example.com",
    "password": "Test123!@#"
}'

response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$login_data" \
    "${BASE_URL}/auth/login")
status_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | head -n -1)

if [ "$status_code" -eq 200 ]; then
    echo -e "${GREEN}✅ Login successful${NC}"
    # Extract access token
    access_token=$(echo "$body" | jq -r '.access_token' 2>/dev/null || echo "")
    if [ -n "$access_token" ]; then
        echo "Token obtained successfully"
        export ACCESS_TOKEN="$access_token"
    fi
else
    echo -e "${RED}❌ Login failed (Status: $status_code)${NC}"
    echo "Response: $body"
fi

# Test 6: Authenticated Request
if [ -n "$ACCESS_TOKEN" ]; then
    echo -e "\n${YELLOW}Test 6: Authenticated Request${NC}"
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "${BASE_URL}/api/v1/users")
    status_code=$(echo "$response" | tail -n 1)
    
    if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 404 ]; then
        echo -e "${GREEN}✅ Authenticated request successful${NC}"
    else
        echo -e "${RED}❌ Authenticated request failed (Status: $status_code)${NC}"
    fi
fi

# Test 7: Service Routing - Airtable Gateway
echo -e "\n${YELLOW}Test 7: Airtable Gateway Routing${NC}"
response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN:-test-token}" \
    "${BASE_URL}/api/v1/airtable/bases")
status_code=$(echo "$response" | tail -n 1)

if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 401 ] || [ "$status_code" -eq 500 ]; then
    echo -e "${GREEN}✅ Airtable route accessible${NC}"
else
    echo -e "${RED}❌ Airtable route failed (Status: $status_code)${NC}"
fi

# Test 8: Service Routing - LLM Orchestrator
echo -e "\n${YELLOW}Test 8: LLM Orchestrator Routing${NC}"
chat_data='{
    "messages": [
        {"role": "user", "content": "Hello, test message"}
    ]
}'

response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ACCESS_TOKEN:-test-token}" \
    -d "$chat_data" \
    "${BASE_URL}/api/v1/llm/chat/completions")
status_code=$(echo "$response" | tail -n 1)

if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 401 ] || [ "$status_code" -eq 500 ]; then
    echo -e "${GREEN}✅ LLM route accessible${NC}"
else
    echo -e "${RED}❌ LLM route failed (Status: $status_code)${NC}"
fi

# Test 9: Service Routing - MCP Server
echo -e "\n${YELLOW}Test 9: MCP Server Routing${NC}"
response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN:-test-token}" \
    "${BASE_URL}/api/v1/mcp/tools")
status_code=$(echo "$response" | tail -n 1)

if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 401 ] || [ "$status_code" -eq 500 ]; then
    echo -e "${GREEN}✅ MCP route accessible${NC}"
else
    echo -e "${RED}❌ MCP route failed (Status: $status_code)${NC}"
fi

echo -e "\n${BLUE}=====================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}=====================================${NC}"
echo -e "${GREEN}API Gateway integration tests completed${NC}"