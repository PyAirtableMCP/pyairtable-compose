#!/bin/bash
# Pre-commit hook for running Frontend unit tests
# Runs fast unit tests to provide quick feedback during development

set -e

echo "⚛️  Running Frontend unit tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Find Frontend services
FRONTEND_SERVICES_DIR="frontend-services"
FAILED_SERVICES=()
PASSED_SERVICES=()
TOTAL_TIME=0

if [ ! -d "$FRONTEND_SERVICES_DIR" ]; then
    echo -e "${YELLOW}No Frontend services directory found, skipping Frontend tests${NC}"
    exit 0
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}Node.js not installed, skipping Frontend tests${NC}"
    exit 0
fi

# Run tests for each Frontend service that has unit tests
for service_dir in "$FRONTEND_SERVICES_DIR"/*; do
    if [ -d "$service_dir" ] && [ -f "$service_dir/package.json" ]; then
        service_name=$(basename "$service_dir")
        
        echo "  Testing $service_name..."
        
        cd "$service_dir"
        
        # Check if dependencies are installed, install if needed
        if [ ! -d "node_modules" ] || [ ! -f "node_modules/.package-lock.json" ]; then
            echo "    Installing dependencies..."
            npm ci --silent 2>/dev/null || npm install --silent 2>/dev/null || true
        fi
        
        # Check if service has test scripts or test files
        has_test_script=$(node -p "JSON.parse(require('fs').readFileSync('package.json', 'utf8')).scripts?.test ? 'true' : 'false'" 2>/dev/null || echo "false")
        has_jest_config=$([ -f "jest.config.js" ] || [ -f "jest.config.json" ] || [ -f "jest.config.ts" ] && echo "true" || echo "false")
        has_test_files=$(find . -name "*.test.*" -o -name "*.spec.*" | head -1 | wc -l)
        
        start_time=$(date +%s)
        
        if [ "$has_test_script" = "true" ] || [ "$has_jest_config" = "true" ] || [ "$has_test_files" -gt 0 ]; then
            # Try to run tests with timeout
            if timeout 60s npm test -- --passWithNoTests --watchAll=false --coverage=false --silent 2>/dev/null; then
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                TOTAL_TIME=$((TOTAL_TIME + duration))
                PASSED_SERVICES+=("$service_name (${duration}s)")
                echo -e "    ✅ ${GREEN}PASSED${NC} in ${duration}s"
            else
                # Try alternative test commands
                test_passed=false
                
                # Try jest directly
                if command -v jest &> /dev/null && timeout 30s npx jest --passWithNoTests --silent 2>/dev/null; then
                    test_passed=true
                # Try with different test script variants
                elif timeout 30s npm run test:unit 2>/dev/null; then
                    test_passed=true
                elif timeout 30s npm run test:ci 2>/dev/null; then
                    test_passed=true
                fi
                
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                TOTAL_TIME=$((TOTAL_TIME + duration))
                
                if [ "$test_passed" = true ]; then
                    PASSED_SERVICES+=("$service_name (${duration}s)")
                    echo -e "    ✅ ${GREEN}PASSED${NC} in ${duration}s"
                else
                    FAILED_SERVICES+=("$service_name")
                    echo -e "    ❌ ${RED}FAILED${NC} in ${duration}s"
                    
                    # Show brief error details
                    echo "    Running with verbose output for details..."
                    timeout 20s npm test -- --passWithNoTests --watchAll=false --verbose 2>&1 | head -10 || true
                fi
            fi
        else
            end_time=$(date +%s)
            duration=$((end_time - start_time))
            echo "    Skipping $service_name (no tests configured)"
        fi
        
        cd - > /dev/null
    fi
done

# Print summary
echo ""
echo "📊 Frontend Unit Test Summary:"
echo "  Total time: ${TOTAL_TIME}s"

if [ ${#PASSED_SERVICES[@]} -gt 0 ]; then
    echo -e "  ${GREEN}✅ Passed (${#PASSED_SERVICES[@]}):${NC}"
    for service in "${PASSED_SERVICES[@]}"; do
        echo "    - $service"
    done
fi

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo -e "  ${RED}❌ Failed (${#FAILED_SERVICES[@]}):${NC}"
    for service in "${FAILED_SERVICES[@]}"; do
        echo "    - $service"
    done
    echo ""
    echo -e "${RED}Some Frontend unit tests failed. Please fix the issues before committing.${NC}"
    echo "Run './test-orchestrator.sh --categories unit --services frontend' for detailed output."
    exit 1
fi

if [ ${#PASSED_SERVICES[@]} -eq 0 ] && [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No Frontend unit tests found${NC}"
else
    echo -e "  ${GREEN}All Frontend unit tests passed!${NC}"
fi

echo ""