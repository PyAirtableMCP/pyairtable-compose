#!/bin/bash

# Run integration tests for PyAirtable microservices

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}PyAirtable Integration Test Suite${NC}"
echo -e "${BLUE}=====================================${NC}"

# Check if services are running
check_service() {
    local service_name=$1
    local port=$2
    
    if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ $service_name is running${NC}"
        return 0
    else
        echo -e "${RED}❌ $service_name is not running${NC}"
        return 1
    fi
}

echo -e "\n${YELLOW}Checking core services...${NC}"

all_running=true
check_service "API Gateway" 8080 || all_running=false
check_service "Auth Service" 8081 || all_running=false
check_service "Airtable Gateway" 8093 || all_running=false
check_service "LLM Orchestrator" 8091 || all_running=false
check_service "MCP Server" 8092 || all_running=false

if [ "$all_running" = false ]; then
    echo -e "\n${RED}Not all core services are running!${NC}"
    echo "Please start services with: docker-compose up -d"
    exit 1
fi

echo -e "\n${GREEN}All core services are running${NC}"

# Run shell-based tests
echo -e "\n${YELLOW}Running API Gateway tests...${NC}"
if [ -f "tests/integration/test_api_gateway.sh" ]; then
    chmod +x tests/integration/test_api_gateway.sh
    ./tests/integration/test_api_gateway.sh
else
    echo -e "${RED}API Gateway test script not found${NC}"
fi

# Install Python test dependencies if needed
echo -e "\n${YELLOW}Checking Python test dependencies...${NC}"
if ! python -c "import pytest" 2>/dev/null; then
    echo "Installing pytest..."
    pip install pytest pytest-asyncio httpx
fi

# Run Python-based tests
echo -e "\n${YELLOW}Running Python integration tests...${NC}"
python -m pytest tests/integration/test_core_services.py -v --tb=short

echo -e "\n${BLUE}=====================================${NC}"
echo -e "${BLUE}Integration Test Summary${NC}"
echo -e "${BLUE}=====================================${NC}"
echo -e "${GREEN}Integration tests completed${NC}"
echo ""
echo "To run specific tests:"
echo "  - API Gateway only: ./tests/integration/test_api_gateway.sh"
echo "  - Python tests only: pytest tests/integration/test_core_services.py -v"
echo "  - Specific test: pytest tests/integration/test_core_services.py::TestCoreServices::test_auth_flow -v"