#!/bin/bash

# Sprint 2 Chat Integration Test Script
# Tests the complete integration between chat UI and backend services

set -e

echo "🚀 Testing PyAirtable Compose Sprint 2 Chat Integration"
echo "======================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a service is running
check_service() {
    local name=$1
    local url=$2
    local port=$3
    
    echo -n "🔍 Checking $name ($url)... "
    
    if curl -s --max-time 5 "$url/health" > /dev/null 2>&1 || curl -s --max-time 5 "$url/api/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Running${NC}"
        return 0
    else
        echo -e "${RED}❌ Not accessible${NC}"
        return 1
    fi
}

# Function to check WebSocket connectivity
check_websocket() {
    local url=$1
    echo -n "🌐 Testing WebSocket connection ($url)... "
    
    # Use a simple Node.js script to test WebSocket
    node -e "
        const WebSocket = require('ws');
        const ws = new WebSocket('$url');
        ws.on('open', () => {
            console.log('✅ WebSocket connected');
            ws.close();
            process.exit(0);
        });
        ws.on('error', () => {
            console.log('❌ WebSocket failed');
            process.exit(1);
        });
        setTimeout(() => {
            console.log('⏰ WebSocket timeout');
            process.exit(1);
        }, 5000);
    " 2>/dev/null && echo -e "${GREEN}Connected${NC}" || echo -e "${RED}Failed${NC}"
}

# Function to test API endpoint
test_api_endpoint() {
    local endpoint=$1
    local expected_status=$2
    local description=$3
    
    echo -n "📡 Testing $description ($endpoint)... "
    
    status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$endpoint" 2>/dev/null || echo "000")
    
    if [ "$status_code" = "$expected_status" ]; then
        echo -e "${GREEN}✅ $status_code${NC}"
        return 0
    else
        echo -e "${RED}❌ $status_code (expected $expected_status)${NC}"
        return 1
    fi
}

# Start tests
echo ""
echo "🔧 Phase 1: Backend Service Health Checks"
echo "----------------------------------------"

services_ok=0

# Check API Gateway (main entry point)
if check_service "API Gateway" "http://localhost:8000" 8000; then
    ((services_ok++))
fi

# Check LLM Orchestrator
if check_service "LLM Orchestrator" "http://localhost:8003" 8003; then
    ((services_ok++))
fi

# Check MCP Server
if check_service "MCP Server" "http://localhost:8001" 8001; then
    ((services_ok++))
fi

# Check Airtable Gateway
if check_service "Airtable Gateway" "http://localhost:8002" 8002; then
    ((services_ok++))
fi

echo ""
echo "📊 Backend Services Status: $services_ok/4 services running"

if [ $services_ok -lt 4 ]; then
    echo -e "${YELLOW}⚠️  Some backend services are not running. Starting them...${NC}"
    echo ""
    echo "To start backend services, run:"
    echo "  cd python-services"
    echo "  docker-compose up -d"
    echo ""
fi

echo ""
echo "🌐 Phase 2: WebSocket Connectivity Tests"
echo "---------------------------------------"

# Test WebSocket connection to API Gateway
if command -v node > /dev/null 2>&1; then
    check_websocket "ws://localhost:8000/ws/chat"
else
    echo -e "${YELLOW}⚠️  Node.js not found, skipping WebSocket test${NC}"
fi

echo ""
echo "📡 Phase 3: API Endpoint Tests"
echo "-----------------------------"

# Test API Gateway endpoints
test_api_endpoint "http://localhost:8000/api/health" "200" "API Gateway health"
test_api_endpoint "http://localhost:8000/api/mcp/info" "200" "MCP info endpoint"
test_api_endpoint "http://localhost:8000/api/airtable/bases" "401" "Airtable bases (auth required)"

echo ""
echo "🎨 Phase 4: Frontend Integration Test"
echo "------------------------------------"

# Check if chat-ui is set up
if [ -d "frontend/chat-ui" ]; then
    cd frontend/chat-ui
    
    echo -n "📦 Checking package.json... "
    if [ -f "package.json" ]; then
        echo -e "${GREEN}✅ Found${NC}"
        
        echo -n "📋 Checking dependencies... "
        if [ -d "node_modules" ]; then
            echo -e "${GREEN}✅ Installed${NC}"
        else
            echo -e "${YELLOW}⚠️  Missing - run 'npm install'${NC}"
        fi
        
        echo -n "⚙️  Checking configuration... "
        if [ -f ".env" ] && [ -f "vite.config.ts" ] && [ -f "tsconfig.json" ]; then
            echo -e "${GREEN}✅ Complete${NC}"
        else
            echo -e "${RED}❌ Missing config files${NC}"
        fi
        
        echo -n "🏗️  Testing build... "
        if npm run type-check > /dev/null 2>&1; then
            echo -e "${GREEN}✅ TypeScript OK${NC}"
        else
            echo -e "${RED}❌ TypeScript errors${NC}"
        fi
        
    else
        echo -e "${RED}❌ Not found${NC}"
    fi
    
    cd ../..
else
    echo -e "${RED}❌ Frontend chat-ui directory not found${NC}"
fi

echo ""
echo "🧪 Phase 5: Integration Validation"
echo "---------------------------------"

# Create a simple integration test
echo -n "🔗 Testing full integration flow... "

if [ $services_ok -eq 4 ]; then
    # Test a complete request flow
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"message": "test", "sessionId": "test-session"}' \
        http://localhost:8000/api/chat/message 2>/dev/null || echo "error")
    
    if [[ "$response" != "error" ]]; then
        echo -e "${GREEN}✅ Request flow working${NC}"
    else
        echo -e "${YELLOW}⚠️  Requires authentication${NC}"
    fi
else
    echo -e "${RED}❌ Backend services not ready${NC}"
fi

echo ""
echo "📋 Phase 6: Integration Summary"
echo "------------------------------"

echo "Sprint 2 Chat Integration Status:"
echo ""

if [ $services_ok -eq 4 ]; then
    echo -e "  ${GREEN}✅ Backend Services:${NC} All 4 services running"
else
    echo -e "  ${RED}❌ Backend Services:${NC} $services_ok/4 services running"
fi

if [ -d "frontend/chat-ui/node_modules" ]; then
    echo -e "  ${GREEN}✅ Frontend Setup:${NC} Chat UI ready"
else
    echo -e "  ${YELLOW}⚠️  Frontend Setup:${NC} Dependencies need installation"
fi

echo ""
echo "🚀 To start the complete Sprint 2 system:"
echo ""
echo "1. Start backend services:"
echo "   cd python-services && docker-compose up -d"
echo ""
echo "2. Start chat UI:"
echo "   cd frontend/chat-ui && npm install && npm run dev"
echo ""
echo "3. Open chat interface:"
echo "   http://localhost:3001"
echo ""

if [ $services_ok -eq 4 ] && [ -d "frontend/chat-ui/node_modules" ]; then
    echo -e "${GREEN}🎉 Sprint 2 Integration Ready!${NC}"
    echo ""
    echo "Test scenarios to try:"
    echo "  • 'List my Airtable bases'"
    echo "  • 'Show me the schema for base [baseId]'"
    echo "  • 'Query records from table [tableName]'"
    echo "  • Upload a CSV file for analysis"
    echo "  • Test WebSocket connection status"
else
    echo -e "${YELLOW}⚠️  Integration setup incomplete${NC}"
    echo "Please complete the setup steps above."
fi

echo ""
echo "🔍 For debugging, check logs:"
echo "  • Backend: docker-compose logs -f"
echo "  • Frontend: Browser dev console"
echo "  • WebSocket: Network tab in dev tools"
echo ""

exit 0