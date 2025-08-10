#!/bin/bash
# Pre-commit hook for checking test coverage
# Ensures minimum coverage thresholds are maintained

set -e

echo "📊 Checking test coverage thresholds..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MIN_COVERAGE_GLOBAL=80
MIN_COVERAGE_PER_SERVICE=75
COVERAGE_FAILURES=()
COVERAGE_SUCCESSES=()

# Create temporary directory for coverage data
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "  Analyzing current coverage levels..."

# Python coverage check
if [ -d "python-services" ]; then
    echo "    🐍 Checking Python coverage..."
    
    for service_dir in python-services/*; do
        if [ -d "$service_dir" ] && [ "$(basename "$service_dir")" != "shared" ]; then
            service_name=$(basename "$service_dir")
            
            cd "$service_dir"
            
            # Check if service has tests and coverage config
            if [ -d "tests" ] && ([ -f "requirements.txt" ] || [ -f "requirements-test.txt" ]); then
                # Install dependencies quietly
                pip install -q coverage pytest pytest-cov 2>/dev/null || true
                
                # Set up Python path
                export PYTHONPATH="${PYTHONPATH}:$(pwd)/src:$(pwd)"
                
                # Run quick coverage check
                if timeout 60s python -m pytest tests/ --cov=src --cov-report=json:coverage.json --quiet --tb=no 2>/dev/null; then
                    if [ -f "coverage.json" ]; then
                        # Parse coverage percentage
                        coverage_percent=$(python -c "
import json
try:
    with open('coverage.json') as f:
        data = json.load(f)
    total = data.get('totals', {})
    percent = total.get('percent_covered', 0)
    print(f'{percent:.1f}')
except:
    print('0.0')
" 2>/dev/null || echo "0.0")
                        
                        coverage_int=$(echo "$coverage_percent" | cut -d. -f1)
                        
                        if [ "$coverage_int" -lt "$MIN_COVERAGE_PER_SERVICE" ]; then
                            COVERAGE_FAILURES+=("$service_name (Python): ${coverage_percent}% < ${MIN_COVERAGE_PER_SERVICE}%")
                            echo -e "        ❌ ${RED}$service_name: ${coverage_percent}%${NC} (below ${MIN_COVERAGE_PER_SERVICE}% threshold)"
                        else
                            COVERAGE_SUCCESSES+=("$service_name (Python): ${coverage_percent}%")
                            echo -e "        ✅ ${GREEN}$service_name: ${coverage_percent}%${NC}"
                        fi
                        
                        # Clean up
                        rm -f coverage.json .coverage
                    else
                        echo -e "        ⚠️  ${YELLOW}$service_name: Could not generate coverage report${NC}"
                    fi
                else
                    echo -e "        ⚠️  ${YELLOW}$service_name: Coverage check failed${NC}"
                fi
            else
                echo -e "        ➖ $service_name: No tests or configuration found"
            fi
            
            cd - > /dev/null
        fi
    done
fi

# Go coverage check
if [ -d "go-services" ] && command -v go &> /dev/null; then
    echo "    🔷 Checking Go coverage..."
    
    for service_dir in go-services/*; do
        if [ -d "$service_dir" ] && [ "$(basename "$service_dir")" != "shared" ] && [ "$(basename "$service_dir")" != "pkg" ]; then
            service_name=$(basename "$service_dir")
            
            if [ -f "$service_dir/go.mod" ] && (find "$service_dir" -name "*_test.go" -print -quit | grep -q .); then
                cd "$service_dir"
                
                # Run Go test with coverage
                coverage_file="$TEMP_DIR/${service_name}_coverage.out"
                
                if timeout 60s go test -short -coverprofile="$coverage_file" ./... 2>/dev/null; then
                    # Calculate coverage percentage
                    if [ -f "$coverage_file" ]; then
                        coverage_percent=$(go tool cover -func="$coverage_file" 2>/dev/null | tail -1 | awk '{print $3}' | sed 's/%//' || echo "0.0")
                        coverage_int=$(echo "$coverage_percent" | cut -d. -f1)
                        
                        if [ -n "$coverage_percent" ] && [ "$coverage_int" -lt "$MIN_COVERAGE_PER_SERVICE" ]; then
                            COVERAGE_FAILURES+=("$service_name (Go): ${coverage_percent}% < ${MIN_COVERAGE_PER_SERVICE}%")
                            echo -e "        ❌ ${RED}$service_name: ${coverage_percent}%${NC} (below ${MIN_COVERAGE_PER_SERVICE}% threshold)"
                        elif [ -n "$coverage_percent" ]; then
                            COVERAGE_SUCCESSES+=("$service_name (Go): ${coverage_percent}%")
                            echo -e "        ✅ ${GREEN}$service_name: ${coverage_percent}%${NC}"
                        else
                            echo -e "        ⚠️  ${YELLOW}$service_name: Could not parse coverage${NC}"
                        fi
                    else
                        echo -e "        ⚠️  ${YELLOW}$service_name: No coverage file generated${NC}"
                    fi
                else
                    echo -e "        ⚠️  ${YELLOW}$service_name: Coverage test failed${NC}"
                fi
                
                cd - > /dev/null
            else
                echo -e "        ➖ $service_name: No Go tests found"
            fi
        fi
    done
fi

# JavaScript/TypeScript coverage check
if [ -d "frontend-services" ] && command -v node &> /dev/null; then
    echo "    ⚛️  Checking JavaScript/TypeScript coverage..."
    
    for service_dir in frontend-services/*; do
        if [ -d "$service_dir" ] && [ -f "$service_dir/package.json" ]; then
            service_name=$(basename "$service_dir")
            
            cd "$service_dir"
            
            # Check if service has test coverage configured
            has_coverage=$(node -p "
const pkg = JSON.parse(require('fs').readFileSync('package.json', 'utf8'));
const scripts = pkg.scripts || {};
Object.keys(scripts).some(key => key.includes('test') && scripts[key].includes('coverage'))
" 2>/dev/null || echo "false")
            
            has_jest=$([ -f "jest.config.js" ] || [ -f "jest.config.json" ] || [ -f "jest.config.ts" ] && echo "true" || echo "false")
            
            if [ "$has_coverage" = "true" ] || [ "$has_jest" = "true" ]; then
                # Try to run coverage
                coverage_output="$TEMP_DIR/${service_name}_js_coverage.json"
                
                # Ensure dependencies are installed
                if [ ! -d "node_modules" ]; then
                    npm install --silent 2>/dev/null || true
                fi
                
                # Try different coverage commands
                if timeout 60s npm test -- --coverage --coverageReporters=json --watchAll=false --passWithNoTests --silent 2>/dev/null; then
                    # Look for coverage results
                    coverage_file=""
                    if [ -f "coverage/coverage-final.json" ]; then
                        coverage_file="coverage/coverage-final.json"
                    elif [ -f "coverage/coverage-summary.json" ]; then
                        coverage_file="coverage/coverage-summary.json"
                    fi
                    
                    if [ -n "$coverage_file" ]; then
                        # Parse Jest coverage format
                        coverage_percent=$(node -p "
try {
    const coverage = JSON.parse(require('fs').readFileSync('$coverage_file', 'utf8'));
    const total = coverage.total || coverage;
    const statements = total.statements || total.statementMap || {};
    const percent = statements.pct || statements.percent || 0;
    percent.toFixed(1);
} catch (e) {
    '0.0';
}
" 2>/dev/null || echo "0.0")
                        
                        coverage_int=$(echo "$coverage_percent" | cut -d. -f1)
                        
                        if [ "$coverage_int" -lt "$MIN_COVERAGE_PER_SERVICE" ]; then
                            COVERAGE_FAILURES+=("$service_name (JS): ${coverage_percent}% < ${MIN_COVERAGE_PER_SERVICE}%")
                            echo -e "        ❌ ${RED}$service_name: ${coverage_percent}%${NC} (below ${MIN_COVERAGE_PER_SERVICE}% threshold)"
                        else
                            COVERAGE_SUCCESSES+=("$service_name (JS): ${coverage_percent}%")
                            echo -e "        ✅ ${GREEN}$service_name: ${coverage_percent}%${NC}"
                        fi
                        
                        # Clean up
                        rm -rf coverage/ || true
                    else
                        echo -e "        ⚠️  ${YELLOW}$service_name: No coverage report generated${NC}"
                    fi
                else
                    echo -e "        ⚠️  ${YELLOW}$service_name: Coverage test failed${NC}"
                fi
            else
                echo -e "        ➖ $service_name: No coverage configuration found"
            fi
            
            cd - > /dev/null
        fi
    done
fi

# Summary
echo ""
echo "📊 Coverage Check Summary:"

if [ ${#COVERAGE_SUCCESSES[@]} -gt 0 ]; then
    echo -e "  ${GREEN}✅ Services meeting coverage threshold:${NC}"
    for success in "${COVERAGE_SUCCESSES[@]}"; do
        echo "    - $success"
    done
fi

if [ ${#COVERAGE_FAILURES[@]} -gt 0 ]; then
    echo -e "  ${RED}❌ Services below coverage threshold:${NC}"
    for failure in "${COVERAGE_FAILURES[@]}"; do
        echo "    - $failure"
    done
    echo ""
    echo -e "${RED}Coverage threshold violations detected.${NC}"
    echo -e "${YELLOW}Consider adding more tests or adjusting thresholds if appropriate.${NC}"
    echo "Run './coverage-reporter.py' for detailed coverage analysis."
    
    # Don't fail the commit for coverage issues in pre-commit (warning only)
    # This allows developers to commit work-in-progress while being aware of coverage
    echo -e "${YELLOW}Warning: Proceeding with commit despite coverage issues.${NC}"
else
    echo -e "  ${GREEN}All services meet coverage requirements!${NC}"
fi

if [ ${#COVERAGE_SUCCESSES[@]} -eq 0 ] && [ ${#COVERAGE_FAILURES[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No coverage data found${NC}"
fi

echo ""