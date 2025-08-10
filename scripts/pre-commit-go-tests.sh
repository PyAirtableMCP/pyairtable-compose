#!/bin/bash
# Pre-commit hook for running Go unit tests
# Runs fast unit tests to provide quick feedback during development

set -e

echo "🔷 Running Go unit tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Find Go services
GO_SERVICES_DIR="go-services"
FAILED_SERVICES=()
PASSED_SERVICES=()
TOTAL_TIME=0

if [ ! -d "$GO_SERVICES_DIR" ]; then
    echo -e "${YELLOW}No Go services directory found, skipping Go tests${NC}"
    exit 0
fi

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${YELLOW}Go not installed, skipping Go tests${NC}"
    exit 0
fi

# Run tests for each Go service that has unit tests
for service_dir in "$GO_SERVICES_DIR"/*; do
    if [ -d "$service_dir" ] && [ "$(basename "$service_dir")" != "shared" ] && [ "$(basename "$service_dir")" != "pkg" ]; then
        service_name=$(basename "$service_dir")
        
        # Check if service has Go files and tests
        if [ -f "$service_dir/go.mod" ] && ([ -d "$service_dir/test" ] || [ -d "$service_dir/tests" ] || find "$service_dir" -name "*_test.go" -print -quit | grep -q .); then
            echo "  Testing $service_name..."
            
            cd "$service_dir"
            
            # Download dependencies
            go mod download 2>/dev/null || true
            go mod tidy 2>/dev/null || true
            
            # Run unit tests with timeout
            start_time=$(date +%s)
            
            # Try different test directory structures
            test_cmd=""
            if [ -d "test/unit" ]; then
                test_cmd="go test -short -race -timeout=30s ./test/unit/..."
            elif [ -d "tests/unit" ]; then
                test_cmd="go test -short -race -timeout=30s ./tests/unit/..."
            else
                # Run all tests but with short flag to skip integration tests
                test_cmd="go test -short -race -timeout=30s ./..."
            fi
            
            if eval $test_cmd 2>/dev/null; then
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
                eval $test_cmd -v 2>&1 | head -20 || true
            fi
            
            cd - > /dev/null
        else
            echo "  Skipping $service_name (no Go tests found)"
        fi
    fi
done

# Print summary
echo ""
echo "📊 Go Unit Test Summary:"
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
    echo -e "${RED}Some Go unit tests failed. Please fix the issues before committing.${NC}"
    echo "Run './test-orchestrator.sh --categories unit --services go' for detailed output."
    exit 1
fi

if [ ${#PASSED_SERVICES[@]} -eq 0 ] && [ ${#FAILED_SERVICES[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No Go unit tests found${NC}"
else
    echo -e "  ${GREEN}All Go unit tests passed!${NC}"
fi

echo ""