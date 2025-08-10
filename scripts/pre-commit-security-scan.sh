#!/bin/bash
# Pre-commit hook for security vulnerability scanning
# Runs quick security scans to catch common vulnerabilities

set -e

echo "🔒 Running security vulnerability scan..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SECURITY_ISSUES=()
SCAN_RESULTS=()

# Create temporary directory for results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "  Scanning for security vulnerabilities..."

# Python security scan with bandit
if [ -d "python-services" ]; then
    echo "    🐍 Scanning Python code with bandit..."
    if command -v bandit &> /dev/null; then
        bandit_output="$TEMP_DIR/bandit_output.json"
        
        if bandit -r python-services/ -f json -o "$bandit_output" -ll 2>/dev/null; then
            # Check if there are any high or medium severity issues
            high_issues=$(cat "$bandit_output" | jq '.results[] | select(.issue_severity == "HIGH") | .test_name' 2>/dev/null | wc -l || echo 0)
            medium_issues=$(cat "$bandit_output" | jq '.results[] | select(.issue_severity == "MEDIUM") | .test_name' 2>/dev/null | wc -l || echo 0)
            
            if [ "$high_issues" -gt 0 ] || [ "$medium_issues" -gt 0 ]; then
                SECURITY_ISSUES+=("Python: $high_issues high, $medium_issues medium severity issues")
                echo -e "      ❌ ${RED}Found security issues${NC}: $high_issues high, $medium_issues medium"
                
                # Show top issues
                echo "      Top issues:"
                cat "$bandit_output" | jq -r '.results[] | select(.issue_severity == "HIGH" or .issue_severity == "MEDIUM") | "        - \(.test_name): \(.filename):\(.line_number)"' 2>/dev/null | head -3 || true
            else
                SCAN_RESULTS+=("Python: No high/medium security issues found")
                echo -e "      ✅ ${GREEN}No high/medium security issues found${NC}"
            fi
        else
            echo -e "      ⚠️  ${YELLOW}Bandit scan failed or incomplete${NC}"
        fi
    else
        echo -e "      ⚠️  ${YELLOW}Bandit not installed, skipping Python security scan${NC}"
    fi
fi

# Go security scan with gosec (if available)
if [ -d "go-services" ] && command -v gosec &> /dev/null; then
    echo "    🔷 Scanning Go code with gosec..."
    gosec_output="$TEMP_DIR/gosec_output.json"
    
    cd go-services
    if gosec -fmt json -out "$gosec_output" ./... 2>/dev/null; then
        # Check severity levels
        high_issues=$(cat "$gosec_output" | jq '.Issues[] | select(.severity == "HIGH") | .rule_id' 2>/dev/null | wc -l || echo 0)
        medium_issues=$(cat "$gosec_output" | jq '.Issues[] | select(.severity == "MEDIUM") | .rule_id' 2>/dev/null | wc -l || echo 0)
        
        if [ "$high_issues" -gt 0 ] || [ "$medium_issues" -gt 0 ]; then
            SECURITY_ISSUES+=("Go: $high_issues high, $medium_issues medium severity issues")
            echo -e "      ❌ ${RED}Found security issues${NC}: $high_issues high, $medium_issues medium"
        else
            SCAN_RESULTS+=("Go: No high/medium security issues found")
            echo -e "      ✅ ${GREEN}No high/medium security issues found${NC}"
        fi
    else
        echo -e "      ⚠️  ${YELLOW}Gosec scan failed or incomplete${NC}"
    fi
    cd - > /dev/null
elif [ -d "go-services" ]; then
    echo -e "      ⚠️  ${YELLOW}Gosec not installed, skipping Go security scan${NC}"
fi

# JavaScript/Node.js security scan with npm audit
if [ -d "frontend-services" ]; then
    echo "    ⚛️  Scanning JavaScript/Node.js dependencies..."
    
    for service_dir in frontend-services/*; do
        if [ -d "$service_dir" ] && [ -f "$service_dir/package.json" ]; then
            service_name=$(basename "$service_dir")
            
            cd "$service_dir"
            if [ -f "package-lock.json" ] || [ -f "yarn.lock" ]; then
                audit_output="$TEMP_DIR/npm_audit_${service_name}.json"
                
                if npm audit --audit-level=moderate --json > "$audit_output" 2>/dev/null; then
                    # Check for high and critical vulnerabilities
                    high_vulns=$(cat "$audit_output" | jq '.metadata.vulnerabilities.high // 0' 2>/dev/null || echo 0)
                    critical_vulns=$(cat "$audit_output" | jq '.metadata.vulnerabilities.critical // 0' 2>/dev/null || echo 0)
                    
                    if [ "$high_vulns" -gt 0 ] || [ "$critical_vulns" -gt 0 ]; then
                        SECURITY_ISSUES+=("$service_name (JS): $critical_vulns critical, $high_vulns high vulnerabilities")
                        echo -e "        ❌ ${RED}$service_name: Found vulnerabilities${NC}: $critical_vulns critical, $high_vulns high"
                    else
                        SCAN_RESULTS+=("$service_name (JS): No high/critical vulnerabilities")
                        echo -e "        ✅ ${GREEN}$service_name: No high/critical vulnerabilities${NC}"
                    fi
                else
                    echo -e "        ⚠️  ${YELLOW}$service_name: Audit failed or incomplete${NC}"
                fi
            else
                echo -e "        ⚠️  ${YELLOW}$service_name: No lock file found${NC}"
            fi
            cd - > /dev/null
        fi
    done
fi

# Generic secret scanning with basic patterns
echo "    🔍 Scanning for potential secrets..."
secret_patterns=(
    "password.*=.*['\"][^'\"]*['\"]"
    "api[_-]?key.*=.*['\"][^'\"]*['\"]"
    "secret.*=.*['\"][^'\"]*['\"]"
    "token.*=.*['\"][^'\"]*['\"]"
    "-----BEGIN.*PRIVATE.*KEY-----"
    "sk-[a-zA-Z0-9]{20,}"
    "xox[baprs]-[a-zA-Z0-9-]+"
    "[0-9a-f]{32}"
)

secrets_found=0
for pattern in "${secret_patterns[@]}"; do
    # Search in common file types, excluding test files and known safe files
    if grep -r -i -E "$pattern" \
        --include="*.py" \
        --include="*.go" \
        --include="*.js" \
        --include="*.ts" \
        --include="*.json" \
        --include="*.yaml" \
        --include="*.yml" \
        --exclude-dir="node_modules" \
        --exclude-dir="venv" \
        --exclude-dir="__pycache__" \
        --exclude-dir=".git" \
        --exclude="*test*" \
        --exclude="*mock*" \
        --exclude="*example*" \
        . 2>/dev/null | head -3; then
        ((secrets_found++))
    fi
done

if [ $secrets_found -gt 0 ]; then
    SECURITY_ISSUES+=("Potential secrets: $secrets_found patterns matched")
    echo -e "      ❌ ${RED}Potential secrets detected${NC}"
else
    SCAN_RESULTS+=("Secrets: No obvious secrets detected")
    echo -e "      ✅ ${GREEN}No obvious secrets detected${NC}"
fi

# Check for common insecure patterns
echo "    🕵️  Checking for insecure patterns..."
insecure_patterns=0

# Check for SQL injection patterns
if grep -r -i "execute.*%.*%" --include="*.py" . 2>/dev/null | head -1 | grep -q .; then
    echo -e "        ⚠️  ${YELLOW}Potential SQL injection patterns found${NC}"
    ((insecure_patterns++))
fi

# Check for command injection patterns
if grep -r -E "(os\.system|subprocess\.call).*input|input.*os\.system" --include="*.py" . 2>/dev/null | head -1 | grep -q .; then
    echo -e "        ⚠️  ${YELLOW}Potential command injection patterns found${NC}"
    ((insecure_patterns++))
fi

# Check for insecure randomness
if grep -r "random\." --include="*.py" . 2>/dev/null | grep -v "secrets\." | head -1 | grep -q .; then
    echo -e "        ⚠️  ${YELLOW}Consider using 'secrets' module instead of 'random' for security-sensitive operations${NC}"
    ((insecure_patterns++))
fi

if [ $insecure_patterns -eq 0 ]; then
    SCAN_RESULTS+=("Patterns: No obvious insecure patterns detected")
    echo -e "      ✅ ${GREEN}No obvious insecure patterns detected${NC}"
else
    SECURITY_ISSUES+=("Insecure patterns: $insecure_patterns potential issues")
fi

# Print summary
echo ""
echo "🔒 Security Scan Summary:"

if [ ${#SCAN_RESULTS[@]} -gt 0 ]; then
    echo -e "  ${GREEN}✅ Clean scans:${NC}"
    for result in "${SCAN_RESULTS[@]}"; do
        echo "    - $result"
    done
fi

if [ ${#SECURITY_ISSUES[@]} -gt 0 ]; then
    echo -e "  ${RED}❌ Security issues found:${NC}"
    for issue in "${SECURITY_ISSUES[@]}"; do
        echo "    - $issue"
    done
    echo ""
    echo -e "${RED}Security vulnerabilities detected. Please review and fix before committing.${NC}"
    echo "Run 'bandit -r python-services/' for detailed Python security report."
    echo "Run 'npm audit' in frontend service directories for detailed JS dependency reports."
    exit 1
else
    echo -e "  ${GREEN}All security scans passed!${NC}"
fi

echo ""