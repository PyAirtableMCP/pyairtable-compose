#!/bin/bash

# PyAirtable Comprehensive E2E Test Runner
# This script sets up the environment and runs comprehensive end-to-end tests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}PyAirtable Comprehensive End-to-End Test Suite${NC}"
echo -e "${BLUE}============================================================${NC}"

# Function to check if a service is running
check_service() {
    local service_name=$1
    local url=$2
    
    echo -n "Checking $service_name... "
    if curl -s -f "$url/health" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Running${NC}"
        return 0
    else
        echo -e "${RED}❌ Not accessible${NC}"
        return 1
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "\n${YELLOW}📦 Installing E2E test dependencies...${NC}"
    
    if [ -f "tests/requirements.e2e.txt" ]; then
        pip install -r tests/requirements.e2e.txt
    else
        echo -e "${YELLOW}⚠️  requirements.e2e.txt not found, installing basic dependencies${NC}"
        pip install httpx pytest pytest-asyncio
    fi
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "\n${YELLOW}🔍 Checking prerequisites...${NC}"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python 3 is required but not installed${NC}"
        exit 1
    fi
    
    # Check pip
    if ! command -v pip &> /dev/null; then
        echo -e "${RED}❌ pip is required but not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to check services
check_services() {
    echo -e "\n${YELLOW}🏥 Checking service health...${NC}"
    
    local all_healthy=true
    
    check_service "API Gateway" "http://localhost:8000" || all_healthy=false
    check_service "LLM Orchestrator" "http://localhost:8003" || all_healthy=false
    check_service "MCP Server" "http://localhost:8001" || all_healthy=false
    check_service "Airtable Gateway" "http://localhost:8002" || all_healthy=false
    
    if [ "$all_healthy" = false ]; then
        echo -e "\n${RED}❌ Not all services are healthy. Please start the services first:${NC}"
        echo -e "${YELLOW}   docker-compose up -d${NC}"
        echo -e "${YELLOW}   # or${NC}"
        echo -e "${YELLOW}   ./start-all-services.sh${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}✅ All services are healthy${NC}"
}

# Function to run manual tests
run_manual_tests() {
    echo -e "\n${BLUE}🧪 Running manual E2E tests...${NC}"
    
    local scenario=$1
    
    if [ -n "$scenario" ]; then
        python3 manual_e2e_test.py --scenario "$scenario"
    else
        python3 manual_e2e_test.py --all
    fi
}

# Function to run comprehensive tests
run_comprehensive_tests() {
    echo -e "\n${BLUE}🚀 Running comprehensive E2E test suite...${NC}"
    
    local verbose_flag=""
    if [ "$VERBOSE" = "true" ]; then
        verbose_flag="--verbose"
    fi
    
    python3 run_comprehensive_e2e_tests.py $verbose_flag --config-file e2e_test_config.json
}

# Function to run pytest tests
run_pytest_tests() {
    echo -e "\n${BLUE}🧪 Running pytest E2E tests...${NC}"
    
    local test_args=""
    if [ "$VERBOSE" = "true" ]; then
        test_args="-v -s"
    fi
    
    # Create reports directory
    mkdir -p tests/reports
    
    # Run tests with coverage and HTML report
    pytest tests/e2e/test_pyairtable_comprehensive_e2e.py \
        $test_args \
        --html=tests/reports/e2e_report.html \
        --self-contained-html \
        --tb=short
}

# Function to generate test report
generate_report() {
    echo -e "\n${BLUE}📊 Generating test report...${NC}"
    
    local report_file="tests/reports/e2e_test_summary_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "$report_file" << EOF
# PyAirtable E2E Test Report

**Generated:** $(date)
**Test Suite:** Comprehensive End-to-End Tests

## Test Configuration
- API Gateway: http://localhost:8000
- LLM Orchestrator: http://localhost:8003
- MCP Server: http://localhost:8001
- Airtable Gateway: http://localhost:8002
- Airtable Base: appVLUAubH5cFWhMV

## Test Scenarios
1. **Facebook Posts Analysis**: Analyze existing posts and recommend improvements
2. **Metadata Table Creation**: Create table describing all base tables
3. **Working Hours Calculation**: Calculate total hours per project
4. **Projects Status & Expenses**: List projects with status and expenses

## Results
See detailed results in:
- JSON Report: tests/reports/e2e_comprehensive_results_*.json
- HTML Report: tests/reports/e2e_report.html

EOF
    
    echo -e "${GREEN}📄 Report generated: $report_file${NC}"
}

# Parse command line arguments
VERBOSE=false
MANUAL=false
SCENARIO=""
PYTEST_ONLY=false
SKIP_DEPS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -m|--manual)
            MANUAL=true
            shift
            ;;
        -s|--scenario)
            SCENARIO="$2"
            MANUAL=true
            shift 2
            ;;
        -p|--pytest-only)
            PYTEST_ONLY=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose      Enable verbose output"
            echo "  -m, --manual       Run manual tests only"
            echo "  -s, --scenario N   Run specific scenario (1-4) in manual mode"
            echo "  -p, --pytest-only Run pytest tests only"
            echo "  --skip-deps        Skip dependency installation"
            echo "  -h, --help         Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Run all tests"
            echo "  $0 --verbose          # Run all tests with verbose output"
            echo "  $0 --manual           # Run manual tests only"
            echo "  $0 --scenario 1       # Run scenario 1 manually"
            echo "  $0 --pytest-only     # Run pytest tests only"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    check_prerequisites
    
    if [ "$SKIP_DEPS" != "true" ]; then
        install_dependencies
    fi
    
    check_services
    
    if [ "$MANUAL" = "true" ]; then
        run_manual_tests "$SCENARIO"
    elif [ "$PYTEST_ONLY" = "true" ]; then
        run_pytest_tests
    else
        # Run comprehensive test suite
        run_comprehensive_tests
        
        # Also run pytest tests for additional validation
        echo -e "\n${YELLOW}🔄 Running additional pytest validation...${NC}"
        run_pytest_tests
    fi
    
    generate_report
    
    echo -e "\n${GREEN}🎉 E2E test execution completed!${NC}"
    echo -e "${BLUE}Check the reports directory for detailed results.${NC}"
}

# Trap for cleanup
cleanup() {
    echo -e "\n${YELLOW}🧹 Cleaning up...${NC}"
    # Add any cleanup tasks here
}
trap cleanup EXIT

# Run main function
main "$@"