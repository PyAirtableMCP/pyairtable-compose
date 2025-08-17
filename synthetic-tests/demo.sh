#!/bin/bash

# PyAirtable Synthetic Testing Demo
# This script demonstrates the comprehensive synthetic testing system

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# ASCII Art Header
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║                   PyAirtable Synthetic Testing Demo                     ║
║                                                                          ║
║  🎭 Human-like behavior simulation                                        ║
║  🔍 End-to-end user journey testing                                       ║
║  📊 Performance metrics & observability                                   ║
║  📸 Visual regression testing                                             ║
║  🚀 On-demand test execution                                              ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF

echo
echo -e "${BLUE}Welcome to the PyAirtable Synthetic Testing System Demo!${NC}"
echo

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $timestamp - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $timestamp - $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $timestamp - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $timestamp - $message"
            ;;
        DEMO)
            echo -e "${PURPLE}[DEMO]${NC} $timestamp - $message"
            ;;
    esac
}

# Function to wait for user input
wait_for_user() {
    echo
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Check if we're in the right directory
if [ ! -f "package.json" ] || [ ! -f "run-tests.sh" ]; then
    log ERROR "Please run this demo from the synthetic-tests directory"
    exit 1
fi

log INFO "Starting PyAirtable Synthetic Testing Demo"
echo

# Demo Step 1: Show system overview
log DEMO "🏗️  SYSTEM OVERVIEW"
echo "   This synthetic testing system provides:"
echo "   • Human-like behavior simulation (typing speed, mouse movements, delays)"
echo "   • Complete user journey testing (registration → data operations → AI analysis)"
echo "   • Observability integration with trace IDs for request correlation"
echo "   • Visual regression testing with screenshot comparison"
echo "   • Performance monitoring with configurable thresholds"
echo "   • Comprehensive reporting (HTML, JSON, JUnit)"
wait_for_user

# Demo Step 2: Show configuration
log DEMO "⚙️  CONFIGURATION"
echo "   Test suites available:"
echo "   • smoke    - Quick tests for core functionality (5-10 minutes)"
echo "   • regression - Full test suite (15-30 minutes)"
echo "   • full     - Complete test suite including edge cases (30-60 minutes)"
echo
echo "   Environments supported:"
echo "   • local    - http://localhost:3000 (your current setup)"
echo "   • staging  - staging.pyairtable.com"
echo "   • production - pyairtable.com"
echo
echo "   Browsers supported:"
echo "   • chromium, firefox, webkit, mobile-chrome, mobile-safari"
wait_for_user

# Demo Step 3: Check prerequisites
log DEMO "🔍 CHECKING PREREQUISITES"

# Check Node.js
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    log SUCCESS "Node.js found: $NODE_VERSION"
else
    log ERROR "Node.js not found. Please install Node.js 16+"
    exit 1
fi

# Check if PyAirtable services are running
log INFO "Checking PyAirtable services..."
SERVICES_RUNNING=0
TOTAL_SERVICES=5

check_service() {
    local port=$1
    local name=$2
    if curl -s "http://localhost:$port/health" >/dev/null 2>&1; then
        log SUCCESS "$name (port $port) - HEALTHY"
        ((SERVICES_RUNNING++))
    else
        log WARN "$name (port $port) - NOT RESPONDING"
    fi
}

check_service 3000 "Frontend"
check_service 8000 "API Gateway"
check_service 8001 "AI Processing"
check_service 8002 "Airtable Gateway"
check_service 8003 "Workspace Service"

echo
if [ $SERVICES_RUNNING -eq $TOTAL_SERVICES ]; then
    log SUCCESS "All PyAirtable services are running! ($SERVICES_RUNNING/$TOTAL_SERVICES)"
else
    log WARN "Some services are not responding ($SERVICES_RUNNING/$TOTAL_SERVICES)"
    echo "   To start all services, run: cd ../pyairtable-compose && ./start.sh"
fi
wait_for_user

# Demo Step 4: Show test execution options
log DEMO "🚀 TEST EXECUTION OPTIONS"
echo
echo "   Basic commands:"
echo "   ./run-tests.sh --suite smoke                    # Quick smoke tests"
echo "   ./run-tests.sh --suite regression --headed      # Full tests with browser UI"
echo "   ./run-tests.sh --suite smoke --browser firefox  # Test with specific browser"
echo "   ./run-tests.sh --dry-run                        # Show what would run"
echo
echo "   Advanced options:"
echo "   ./run-tests.sh --suite full --format all        # Generate all report formats"
echo "   ./run-tests.sh --sequential --headed            # Debug mode (one test at a time)"
echo "   TEST_ENV=staging ./run-tests.sh --suite smoke   # Test different environment"
wait_for_user

# Demo Step 5: Install dependencies (if needed)
if [ ! -d "node_modules" ]; then
    log DEMO "📦 INSTALLING DEPENDENCIES"
    log INFO "Installing Node.js dependencies..."
    npm install
    log INFO "Installing Playwright browsers..."
    npx playwright install
    log SUCCESS "Dependencies installed!"
    wait_for_user
fi

# Demo Step 6: Run a quick demo test
log DEMO "🎬 RUNNING DEMO TEST"
echo "   We'll run a quick smoke test to demonstrate the system."
echo "   This will:"
echo "   • Execute human-like interactions with the PyAirtable UI"
echo "   • Generate trace IDs for observability correlation"
echo "   • Capture screenshots at key decision points"
echo "   • Measure performance metrics"
echo "   • Generate a comprehensive HTML report"
echo
echo "   The test will run in headed mode so you can see the browser automation."
wait_for_user

log INFO "Executing demo test..."
export TEST_SESSION_ID="demo-$(date +%s)"

# Run a single test for demo purposes
if npm test -- tests/new-user-journey.spec.js --project=chromium --headed --grep="Registration form validation" 2>/dev/null; then
    log SUCCESS "Demo test completed successfully!"
else
    log WARN "Demo test encountered issues (this is normal if services aren't fully running)"
fi

# Demo Step 7: Show generated reports
log DEMO "📊 GENERATED REPORTS AND ARTIFACTS"
echo
echo "   Reports generated:"
if [ -d "reports" ]; then
    ls -la reports/ | head -10
    echo "   • HTML Report: reports/html-report/index.html"
    echo "   • JSON Results: reports/test-results.json"
    echo "   • Test Metrics: reports/metrics-*.json"
else
    echo "   (No reports generated yet - run a full test to see reports)"
fi

echo
echo "   Screenshots captured:"
if [ -d "screenshots" ]; then
    ls -la screenshots/ | head -5
    echo "   • Actual screenshots: screenshots/actual/"
    echo "   • Visual diffs: screenshots/diff/"
    echo "   • Baselines: screenshots/baseline/"
else
    echo "   (No screenshots captured yet - run a test to generate screenshots)"
fi
wait_for_user

# Demo Step 8: Show observability features
log DEMO "🔍 OBSERVABILITY AND MONITORING"
echo "   Trace correlation features:"
echo "   • Every test generates unique trace IDs (x-trace-id headers)"
echo "   • Trace IDs flow through all service calls"
echo "   • Test session ID: $TEST_SESSION_ID"
echo
echo "   Performance monitoring:"
echo "   • Page load times with configurable thresholds"
echo "   • First Contentful Paint, Largest Contentful Paint"
echo "   • Network request timing and response codes"
echo "   • Memory usage and resource consumption"
echo
echo "   Integration with monitoring stack:"
echo "   • Prometheus metrics export"
echo "   • Grafana dashboard compatibility"
echo "   • Structured logging for analysis"
wait_for_user

# Demo Step 9: Show test scenarios
log DEMO "🧪 TEST SCENARIOS IMPLEMENTED"
echo
echo "   1. New User Journey (@smoke)"
echo "      • User registration with validation testing"
echo "      • Airtable integration setup"
echo "      • Data exploration and navigation"
echo
echo "   2. Data Operations (@regression)"
echo "      • Browse and explore data tables"
echo "      • Search, filter, and sort functionality"
echo "      • Record editing and data export"
echo
echo "   3. AI Analysis (@regression)"
echo "      • AI-powered data querying"
echo "      • Insights and reports generation"
echo "      • Response quality validation"
echo
echo "   4. Collaboration (@regression)"
echo "      • Workspace sharing and permissions"
echo "      • Real-time collaborative editing"
echo "      • Comments and notifications"
echo
echo "   5. Error Recovery (@regression)"
echo "      • Network connectivity issues"
echo "      • Service unavailability handling"
echo "      • Data validation and error correction"
wait_for_user

# Demo Step 10: Next steps
log DEMO "🎯 NEXT STEPS"
echo
echo "   Ready to run the full synthetic test suite?"
echo
echo "   Recommended commands to try:"
echo
echo "   1. Quick smoke test (5 minutes):"
echo "      ./run-tests.sh --suite smoke"
echo
echo "   2. Full regression test with debugging:"
echo "      ./run-tests.sh --suite regression --headed --sequential"
echo
echo "   3. Cross-browser compatibility test:"
echo "      ./run-tests.sh --suite smoke --browser all"
echo
echo "   4. Performance-focused test:"
echo "      ./run-tests.sh --suite smoke --format all"
echo
echo "   Reports will be available at:"
echo "   • HTML: file://$(pwd)/reports/html-report/index.html"
echo "   • Visual Regression: file://$(pwd)/reports/visual-regression-report.html"
echo

log SUCCESS "Demo completed! The PyAirtable Synthetic Testing System is ready to use."
echo
echo -e "${GREEN}Key Benefits:${NC}"
echo "• 🎭 Human-like interactions reduce false positives"
echo "• 🔍 End-to-end testing catches integration issues"
echo "• 📊 Performance monitoring prevents regressions"
echo "• 📸 Visual testing catches UI/UX problems"
echo "• 🚀 On-demand execution fits any workflow"
echo
echo -e "${BLUE}Happy Testing! 🧪${NC}"
echo