#!/bin/bash
# PyAirtable Integration Test Runner Script
# Agent #6 - Integration Test Automation
# Usage: ./run_integration_tests.sh [quick|full|services-only]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default mode
MODE=${1:-"quick"}

echo -e "${BLUE}🚀 PyAirtable Integration Test Suite${NC}"
echo -e "${BLUE}📋 Sprint 4 - Service Enablement - Agent #6${NC}"
echo "============================================================"
echo -e "🕐 Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "⚙️  Mode: $MODE"
echo "============================================================"

# Check if dependencies are installed
echo -e "${YELLOW}📦 Checking test dependencies...${NC}"
if python3 -c "import httpx, faker, pytest, asyncpg, docker" 2>/dev/null; then
    echo -e "${GREEN}✅ All test dependencies installed${NC}"
else
    echo -e "${RED}❌ Missing test dependencies. Installing...${NC}"
    pip3 install --break-system-packages httpx faker pytest-asyncio asyncpg docker
    echo -e "${GREEN}✅ Dependencies installed${NC}"
fi

# Function to run E2E tests
run_e2e_tests() {
    local test_mode=$1
    echo -e "${YELLOW}🔄 Running E2E integration tests ($test_mode mode)...${NC}"
    
    case $test_mode in
        "quick")
            python3 run_e2e_integration_tests.py --quick
            ;;
        "services-only")
            python3 run_e2e_integration_tests.py --services-only
            ;;
        "full")
            python3 run_e2e_integration_tests.py
            ;;
    esac
}

# Function to run pytest integration tests
run_pytest_tests() {
    echo -e "${YELLOW}🔄 Running pytest integration tests...${NC}"
    python3 -m pytest tests/integration/test_pyairtable_e2e_integration.py -v --tb=short
}

# Function to check service health
check_service_health() {
    echo -e "${YELLOW}🏥 Checking service health...${NC}"
    
    services=(
        "http://localhost:8000/api/health|API Gateway"
        "http://localhost:8002/health|Airtable Gateway" 
        "http://localhost:8003/health|LLM Orchestrator"
        "http://localhost:8007/health|Platform Services"
        "http://localhost:8009/health|Auth Service"
        "http://localhost:8010/health|User Service"
    )
    
    healthy=0
    total=${#services[@]}
    
    for service in "${services[@]}"; do
        IFS='|' read -r url name <<< "$service"
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ $name: HEALTHY${NC}"
            ((healthy++))
        else
            echo -e "${RED}❌ $name: UNHEALTHY${NC}"
        fi
    done
    
    echo "----------------------------------------"
    echo -e "🎯 Service Health: $healthy/$total services healthy"
    
    if [ $healthy -ge 4 ]; then
        echo -e "${GREEN}✅ Sufficient services healthy for testing${NC}"
        return 0
    else
        echo -e "${RED}⚠️  Only $healthy/$total services healthy${NC}"
        return 1
    fi
}

# Function to generate test report
generate_report() {
    echo -e "${YELLOW}📄 Generating test report...${NC}"
    
    # Find the latest test report
    latest_report=$(find . -name "pyairtable_e2e_integration_report_*.json" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_report" ] && [ -f "$latest_report" ]; then
        echo -e "${GREEN}📄 Latest test report: $latest_report${NC}"
        echo -e "${GREEN}📄 Summary report: integration_test_report.md${NC}"
        
        # Extract key metrics from JSON report
        if command -v jq > /dev/null 2>&1; then
            echo -e "${BLUE}📊 Quick Summary:${NC}"
            echo -n "   Service Health: "
            jq -r '.service_health.health_rate // "Unknown"' "$latest_report"
            echo -n "   Overall Success: " 
            jq -r '.overall_metrics.overall_success_rate // "Unknown"' "$latest_report"
            echo -n "   Completion Status: "
            jq -r '.sprint_info.completion_status // "Unknown"' "$latest_report"
        fi
    else
        echo -e "${YELLOW}⚠️  No test report found${NC}"
    fi
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    echo -e "${YELLOW}🧹 Cleaning up test artifacts...${NC}"
    
    # Remove old test reports (keep latest 5)
    find . -name "pyairtable_e2e_integration_report_*.json" -type f | sort -r | tail -n +6 | xargs rm -f
    
    # Clean pytest cache
    rm -rf tests/.pytest_cache tests/__pycache__ 2>/dev/null || true
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Main execution logic
main() {
    # Pre-flight checks
    if ! check_service_health; then
        echo -e "${YELLOW}⚠️  Continuing with limited services...${NC}"
    fi
    
    # Run tests based on mode
    case $MODE in
        "health-only")
            echo -e "${GREEN}✅ Service health check completed${NC}"
            exit 0
            ;;
        "cleanup")
            cleanup_test_artifacts
            exit 0
            ;;
        *)
            # Run E2E integration tests
            if run_e2e_tests "$MODE"; then
                echo -e "${GREEN}✅ E2E integration tests completed successfully${NC}"
                e2e_success=true
            else
                echo -e "${YELLOW}⚠️  E2E integration tests completed with issues${NC}"
                e2e_success=false
            fi
            
            # Run pytest integration tests
            if run_pytest_tests; then
                echo -e "${GREEN}✅ Pytest integration tests completed successfully${NC}"
                pytest_success=true
            else
                echo -e "${YELLOW}⚠️  Pytest integration tests completed with issues${NC}"
                pytest_success=false
            fi
            ;;
    esac
    
    # Generate final report
    generate_report
    
    # Final summary
    echo ""
    echo "============================================================"
    echo -e "${BLUE}🏁 Integration Test Suite Summary${NC}"
    echo "============================================================"
    echo -e "🕐 Completed: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "⚙️  Mode: $MODE"
    
    if [ "$e2e_success" = true ] && [ "$pytest_success" = true ]; then
        echo -e "${GREEN}✅ Overall Status: SUCCESS${NC}"
        echo -e "${GREEN}🚀 Integration tests ready for CI/CD pipeline${NC}"
        exit 0
    elif [ "$e2e_success" = true ] || [ "$pytest_success" = true ]; then
        echo -e "${YELLOW}⚠️  Overall Status: PARTIAL SUCCESS${NC}"
        echo -e "${YELLOW}📋 Some tests passed, review report for details${NC}"
        exit 1
    else
        echo -e "${RED}❌ Overall Status: NEEDS ATTENTION${NC}"
        echo -e "${RED}🔧 Critical issues need to be resolved${NC}"
        exit 2
    fi
}

# Run main function
main "$@"