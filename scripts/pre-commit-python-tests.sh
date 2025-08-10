#!/bin/bash
# Pre-commit hook for running Python unit tests
# Runs fast unit tests to provide quick feedback during development

set -e

echo "🐍 Running Python unit tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Find Python services
PYTHON_SERVICES_DIR="python-services"
FAILED_SERVICES=()
PASSED_SERVICES=()
TOTAL_TIME=0

if [ ! -d "$PYTHON_SERVICES_DIR" ]; then
    echo -e "${YELLOW}No Python services directory found, skipping Python tests${NC}"
    exit 0
fi

# Run tests for each Python service that has unit tests
for service_dir in "$PYTHON_SERVICES_DIR"/*; do
    if [ -d "$service_dir" ] && [ "$(basename "$service_dir")" != "shared" ]; then
        service_name=$(basename "$service_dir")
        
        # Check if service has unit tests
        if [ -d "$service_dir/tests/unit" ] || [ -d "$service_dir/tests" ]; then
            echo "  Testing $service_name..."
            
            cd "$service_dir"
            
            # Check if requirements exist and install if needed
            if [ -f "requirements.txt" ] || [ -f "requirements-test.txt" ]; then
                pip install -q -r requirements*.txt 2>/dev/null || true
            fi
            
            # Set up test environment
            export PYTHONPATH="${PYTHONPATH}:$(pwd)/src:$(pwd)"
            
            # Run unit tests with timeout and coverage
            start_time=$(date +%s)
            
            if timeout 60s python -m pytest tests/unit/ -x -q --tb=short --disable-warnings 2>/dev/null; then
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                TOTAL_TIME=$((TOTAL_TIME + duration))
                PASSED_SERVICES+=("$service_name (${duration}s)")
                echo -e "    ✅ ${GREEN}PASSED${NC} in ${duration}s"
            else
                end_time=$(date +%s)
                duration=$((end_time - start_time))
                TOTAL_TIME=$((TOTAL_TIME + duration))
                FAILED_SERVICES+=("$service_name")
                echo -e "    ❌ ${RED}FAILED${NC} in ${duration}s"
                
                # Show brief error details
                echo "    Running with verbose output for details..."
                timeout 30s python -m pytest tests/unit/ -x --tb=short --disable-warnings -v || true
            fi
            
            cd - > /dev/null
        else
            echo "  Skipping $service_name (no unit tests found)"
        fi
    fi
done

# Print summary
echo ""
echo "📊 Python Unit Test Summary:"
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
    echo -e "${RED}Some Python unit tests failed. Please fix the issues before committing.${NC}"
    echo "Run './test-orchestrator.sh --categories unit --services python' for detailed output."
    exit 1
fi

if [ ${#PASSED_SERVICES[@]} -eq 0 ] && [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No Python unit tests found${NC}"
else
    echo -e "  ${GREEN}All Python unit tests passed!${NC}"
fi

echo ""