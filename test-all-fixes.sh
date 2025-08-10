#\!/bin/bash

echo "🧪 Testing PyAirtable Compose Fixes"
echo "===================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to test endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected="$3"
    
    echo -n "Testing $name... "
    response=$(curl -s "$url" 2>/dev/null)
    
    if echo "$response" | grep -q "$expected"; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        echo "  Expected: $expected"
        echo "  Got: $response"
        ((TESTS_FAILED++))
    fi
}

echo "1. Testing Health Endpoints"
echo "----------------------------"
test_endpoint "PostgreSQL" "http://localhost:5433" "no pg_hba.conf entry" # Expected to fail without auth
test_endpoint "Redis" "http://localhost:6380" "wrong number of arguments" # Expected Redis protocol error
test_endpoint "Airtable Gateway" "http://localhost:8002/health" "healthy"
test_endpoint "MCP Server" "http://localhost:8001/health" "healthy"
test_endpoint "LLM Orchestrator" "http://localhost:8003/health" "healthy"

echo ""
echo "2. Testing Service Info Endpoints"
echo "----------------------------------"
test_endpoint "MCP Server Info" "http://localhost:8001/api/v1/info" "Model Context Protocol server"
test_endpoint "Airtable Gateway Root" "http://localhost:8002/" "airtable-gateway"
test_endpoint "LLM Orchestrator Root" "http://localhost:8003/" "llm-orchestrator"

echo ""
echo "3. Testing Inter-Service Communication"
echo "---------------------------------------"
# Test from within containers
echo -n "Testing MCP -> Airtable Gateway... "
docker exec pyairtable-mcp-server python -c "
import requests
try:
    r = requests.get('http://airtable-gateway:8002/health', timeout=5)
    if r.status_code == 200:
        print('PASSED')
    else:
        print('FAILED: Status', r.status_code)
except Exception as e:
    print('FAILED:', str(e))
" | while read result; do
    if [[ "$result" == "PASSED" ]]; then
        echo -e "${GREEN}✓ $result${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ $result${NC}"
        ((TESTS_FAILED++))
    fi
done

echo -n "Testing LLM -> MCP Server... "
docker exec pyairtable-llm-orchestrator python -c "
import requests
try:
    r = requests.get('http://mcp-server:8001/health', timeout=5)
    if r.status_code == 200:
        print('PASSED')
    else:
        print('FAILED: Status', r.status_code)
except Exception as e:
    print('FAILED:', str(e))
" | while read result; do
    if [[ "$result" == "PASSED" ]]; then
        echo -e "${GREEN}✓ $result${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ $result${NC}"
        ((TESTS_FAILED++))
    fi
done

echo ""
echo "4. Checking Container Health Status"
echo "------------------------------------"
docker-compose -f docker-compose.minimal.yml ps --format json | python3 -c "
import json
import sys

services = []
for line in sys.stdin:
    if line.strip():
        services.append(json.loads(line))

healthy_count = 0
unhealthy_count = 0

for service in services:
    name = service.get('Service', 'unknown')
    status = service.get('Status', '')
    if 'healthy' in status:
        print(f'✓ {name}: healthy')
        healthy_count += 1
    elif 'starting' in status:
        print(f'⚠ {name}: starting')
    else:
        print(f'✗ {name}: unhealthy or unknown')
        unhealthy_count += 1

print(f'\nSummary: {healthy_count} healthy, {unhealthy_count} unhealthy')
"

echo ""
echo "5. Checking for Import Errors"
echo "------------------------------"
echo -n "Checking Airtable Gateway imports... "
docker exec pyairtable-airtable-gateway python -c "
try:
    from routes import health
    from config import get_settings
    print('PASSED')
except ImportError as e:
    print(f'FAILED: {e}')
" | while read result; do
    if [[ "$result" == "PASSED" ]]; then
        echo -e "${GREEN}✓ $result${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ $result${NC}"
        ((TESTS_FAILED++))
    fi
done

echo -n "Checking MCP Server imports... "
docker exec pyairtable-mcp-server python -c "
import sys
sys.path.append('/app/src')
try:
    from routes import health
    from config import get_settings
    print('PASSED')
except ImportError as e:
    print(f'FAILED: {e}')
" | while read result; do
    if [[ "$result" == "PASSED" ]]; then
        echo -e "${GREEN}✓ $result${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ $result${NC}"
        ((TESTS_FAILED++))
    fi
done

echo ""
echo "===================================="
echo "Test Results Summary"
echo "===================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All critical fixes verified successfully\!${NC}"
    exit 0
else
    echo -e "\n${RED}⚠️  Some tests failed. Please review the output above.${NC}"
    exit 1
fi
