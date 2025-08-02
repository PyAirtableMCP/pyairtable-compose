#!/bin/bash

# Test script for Kubernetes deployment

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}PyAirtable K8s Deployment Test${NC}"
echo -e "${BLUE}=====================================${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Get API Gateway URL
if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    API_URL=$(minikube service api-gateway --namespace=pyairtable --url)
else
    API_URL="http://localhost:30080"
fi

echo -e "\n${BLUE}API Gateway URL:${NC} $API_URL"

# Function to test endpoint
test_endpoint() {
    local name=$1
    local endpoint=$2
    local method=${3:-GET}
    local data=$4
    
    echo -e "\n${YELLOW}Testing $name...${NC}"
    
    if [ "$method" = "POST" ] && [ -n "$data" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$API_URL$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null || echo "CURL_ERROR")
    else
        response=$(curl -s -w "\n%{http_code}" "$API_URL$endpoint" 2>/dev/null || echo "CURL_ERROR")
    fi
    
    if [ "$response" = "CURL_ERROR" ]; then
        echo -e "${RED}✗ Failed to connect${NC}"
        return 1
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo -e "${GREEN}✓ Success (HTTP $http_code)${NC}"
        if [ -n "$body" ]; then
            echo "Response: $body" | head -n3
        fi
    else
        echo -e "${RED}✗ Failed (HTTP $http_code)${NC}"
        if [ -n "$body" ]; then
            echo "Error: $body"
        fi
    fi
}

# Test health endpoints
echo -e "\n${BLUE}=== Testing Health Endpoints ===${NC}"
test_endpoint "API Gateway Health" "/health"
test_endpoint "Auth Service Health" "/auth/health"
test_endpoint "Airtable Gateway Health" "/airtable/health"
test_endpoint "LLM Orchestrator Health" "/llm/health"
test_endpoint "MCP Server Health" "/mcp/health"

# Test authentication
echo -e "\n${BLUE}=== Testing Authentication ===${NC}"

# Register a test user
echo -e "\n${YELLOW}Registering test user...${NC}"
REGISTER_RESPONSE=$(curl -s -X POST "$API_URL/auth/register" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"TestPassword123!","name":"Test User"}' 2>/dev/null)

if echo "$REGISTER_RESPONSE" | grep -q "access_token"; then
    echo -e "${GREEN}✓ User registered successfully${NC}"
    ACCESS_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    echo "Access token obtained"
else
    echo -e "${YELLOW}! User might already exist, trying login...${NC}"
    
    # Try to login
    LOGIN_RESPONSE=$(curl -s -X POST "$API_URL/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"test@example.com","password":"TestPassword123!"}' 2>/dev/null)
    
    if echo "$LOGIN_RESPONSE" | grep -q "access_token"; then
        echo -e "${GREEN}✓ Login successful${NC}"
        ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
        echo "Access token obtained"
    else
        echo -e "${RED}✗ Authentication failed${NC}"
        ACCESS_TOKEN=""
    fi
fi

# Test authenticated endpoints if we have a token
if [ -n "$ACCESS_TOKEN" ]; then
    echo -e "\n${BLUE}=== Testing Authenticated Endpoints ===${NC}"
    
    # Test user profile
    echo -e "\n${YELLOW}Testing user profile...${NC}"
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_URL/auth/me" | head -n3
    
    # Test MCP tools list
    echo -e "\n${YELLOW}Testing MCP tools list...${NC}"
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$API_URL/mcp/tools" | head -n5
fi

# Check pod status
echo -e "\n${BLUE}=== Pod Status ===${NC}"
kubectl get pods -n pyairtable --no-headers | while read line; do
    pod=$(echo $line | awk '{print $1}')
    ready=$(echo $line | awk '{print $2}')
    status=$(echo $line | awk '{print $3}')
    
    if [ "$status" = "Running" ]; then
        echo -e "${GREEN}✓ $pod - $ready - $status${NC}"
    else
        echo -e "${RED}✗ $pod - $ready - $status${NC}"
    fi
done

# Check service endpoints
echo -e "\n${BLUE}=== Service Endpoints ===${NC}"
kubectl get endpoints -n pyairtable --no-headers | while read line; do
    service=$(echo $line | awk '{print $1}')
    endpoints=$(echo $line | awk '{print $2}')
    
    if [ "$endpoints" != "<none>" ] && [ -n "$endpoints" ]; then
        echo -e "${GREEN}✓ $service - $endpoints${NC}"
    else
        echo -e "${RED}✗ $service - No endpoints${NC}"
    fi
done

# Summary
echo -e "\n${BLUE}=====================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}=====================================${NC}"

TOTAL_PODS=$(kubectl get pods -n pyairtable --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -n pyairtable --no-headers | grep Running | wc -l)

if [ "$TOTAL_PODS" -eq "$RUNNING_PODS" ] && [ "$RUNNING_PODS" -gt 0 ]; then
    echo -e "${GREEN}All $TOTAL_PODS pods are running!${NC}"
    echo -e "${GREEN}Deployment successful!${NC}"
else
    echo -e "${YELLOW}$RUNNING_PODS out of $TOTAL_PODS pods are running${NC}"
    echo -e "${YELLOW}Check pod logs for any issues${NC}"
fi

echo -e "\n${BLUE}Useful debugging commands:${NC}"
echo "  View logs: kubectl logs -n pyairtable <pod-name>"
echo "  Describe pod: kubectl describe pod -n pyairtable <pod-name>"
echo "  Get events: kubectl get events -n pyairtable --sort-by='.lastTimestamp'"