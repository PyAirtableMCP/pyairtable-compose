#!/bin/bash

# PyAirtable Platform Smoke Test Script
# End-to-end testing of critical platform functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_BASE_URL="http://localhost:8080"
TIMEOUT=30
TEST_EMAIL="smoketest@example.com"
TEST_PASSWORD="SmokeTest123!"
TEST_USER_FIRST_NAME="Smoke"
TEST_USER_LAST_NAME="Test"

# Global variables
ACCESS_TOKEN=""
USER_ID=""
WORKSPACE_ID=""

# Function to print colored output
print_status() {
    local status=$1
    local test_name=$2
    local message=$3
    
    case $status in
        "pass")
            echo -e "${GREEN}✅ PASS${NC} - $test_name: $message"
            ;;
        "fail")
            echo -e "${RED}❌ FAIL${NC} - $test_name: $message"
            ;;
        "warn")
            echo -e "${YELLOW}⚠️  WARN${NC} - $test_name: $message"
            ;;
        "info")
            echo -e "${BLUE}ℹ️  INFO${NC} - $test_name: $message"
            ;;
    esac
}

# Function to make HTTP request with error handling
make_request() {
    local method=$1
    local url=$2
    local data=$3
    local headers=$4
    local expected_status=${5:-200}
    
    local response
    local status_code
    
    if [ -n "$data" ]; then
        if [ -n "$headers" ]; then
            response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X "$method" "$url" \
                -H "Content-Type: application/json" \
                -H "$headers" \
                -d "$data" \
                --max-time $TIMEOUT)
        else
            response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X "$method" "$url" \
                -H "Content-Type: application/json" \
                -d "$data" \
                --max-time $TIMEOUT)
        fi
    else
        if [ -n "$headers" ]; then
            response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X "$method" "$url" \
                -H "$headers" \
                --max-time $TIMEOUT)
        else
            response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X "$method" "$url" \
                --max-time $TIMEOUT)
        fi
    fi
    
    status_code=$(echo "$response" | tail -n1 | cut -d: -f2)
    response_body=$(echo "$response" | sed '$d')
    
    if [ "$status_code" -eq "$expected_status" ]; then
        echo "$response_body"
        return 0
    else
        echo "Expected status $expected_status but got $status_code: $response_body" >&2
        return 1
    fi
}

# Test 1: API Gateway Health Check
test_api_gateway_health() {
    print_status "info" "API Gateway Health" "Testing health endpoint..."
    
    if make_request "GET" "$API_BASE_URL/health" "" "" 200 > /dev/null; then
        print_status "pass" "API Gateway Health" "Health endpoint responding"
        return 0
    else
        print_status "fail" "API Gateway Health" "Health endpoint not responding"
        return 1
    fi
}

# Test 2: User Registration
test_user_registration() {
    print_status "info" "User Registration" "Registering test user..."
    
    local registration_data=$(cat <<EOF
{
    "email": "$TEST_EMAIL",
    "password": "$TEST_PASSWORD",
    "first_name": "$TEST_USER_FIRST_NAME",
    "last_name": "$TEST_USER_LAST_NAME"
}
EOF
)
    
    local response
    if response=$(make_request "POST" "$API_BASE_URL/api/v1/auth/register" "$registration_data" "" 201); then
        # Extract user ID from response
        USER_ID=$(echo "$response" | jq -r '.user.id // .id // empty' 2>/dev/null)
        print_status "pass" "User Registration" "User registered successfully (ID: $USER_ID)"
        return 0
    else
        # Check if user already exists
        if echo "$response" | grep -q "already exists\|conflict"; then
            print_status "warn" "User Registration" "User already exists, continuing..."
            return 0
        else
            print_status "fail" "User Registration" "Registration failed"
            return 1
        fi
    fi
}

# Test 3: User Authentication
test_user_authentication() {
    print_status "info" "User Authentication" "Logging in test user..."
    
    local login_data=$(cat <<EOF
{
    "email": "$TEST_EMAIL",
    "password": "$TEST_PASSWORD"
}
EOF
)
    
    local response
    if response=$(make_request "POST" "$API_BASE_URL/api/v1/auth/login" "$login_data" "" 200); then
        # Extract access token
        ACCESS_TOKEN=$(echo "$response" | jq -r '.access_token // .token // empty' 2>/dev/null)
        
        if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "null" ]; then
            # Extract user ID if not already set
            if [ -z "$USER_ID" ]; then
                USER_ID=$(echo "$response" | jq -r '.user.id // .id // empty' 2>/dev/null)
            fi
            print_status "pass" "User Authentication" "Login successful (Token: ${ACCESS_TOKEN:0:20}...)"
            return 0
        else
            print_status "fail" "User Authentication" "No access token in response"
            return 1
        fi
    else
        print_status "fail" "User Authentication" "Login failed"
        return 1
    fi
}

# Test 4: Authenticated User Profile Access
test_user_profile_access() {
    print_status "info" "User Profile Access" "Fetching user profile..."
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_status "fail" "User Profile Access" "No access token available"
        return 1
    fi
    
    local response
    if response=$(make_request "GET" "$API_BASE_URL/api/v1/users/me" "" "Authorization: Bearer $ACCESS_TOKEN" 200); then
        local email=$(echo "$response" | jq -r '.email // empty' 2>/dev/null)
        if [ "$email" = "$TEST_EMAIL" ]; then
            print_status "pass" "User Profile Access" "Profile retrieved successfully"
            return 0
        else
            print_status "fail" "User Profile Access" "Profile data mismatch"
            return 1
        fi
    else
        print_status "fail" "User Profile Access" "Profile access failed"
        return 1
    fi
}

# Test 5: Workspace Creation
test_workspace_creation() {
    print_status "info" "Workspace Creation" "Creating test workspace..."
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_status "fail" "Workspace Creation" "No access token available"
        return 1
    fi
    
    local workspace_data=$(cat <<EOF
{
    "name": "Smoke Test Workspace",
    "description": "Workspace created by smoke test"
}
EOF
)
    
    local response
    if response=$(make_request "POST" "$API_BASE_URL/api/v1/workspaces" "$workspace_data" "Authorization: Bearer $ACCESS_TOKEN" 201); then
        WORKSPACE_ID=$(echo "$response" | jq -r '.id // .workspace_id // empty' 2>/dev/null)
        if [ -n "$WORKSPACE_ID" ] && [ "$WORKSPACE_ID" != "null" ]; then
            print_status "pass" "Workspace Creation" "Workspace created (ID: $WORKSPACE_ID)"
            return 0
        else
            print_status "fail" "Workspace Creation" "No workspace ID in response"
            return 1
        fi
    else
        print_status "fail" "Workspace Creation" "Workspace creation failed"
        return 1
    fi
}

# Test 6: Airtable Integration
test_airtable_integration() {
    print_status "info" "Airtable Integration" "Testing Airtable gateway..."
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_status "fail" "Airtable Integration" "No access token available"
        return 1
    fi
    
    # Test Airtable bases endpoint
    local response
    if response=$(make_request "GET" "$API_BASE_URL/api/v1/airtable/bases" "" "Authorization: Bearer $ACCESS_TOKEN" 200); then
        # Check if we get a valid response (could be empty array if no bases)
        if echo "$response" | jq -e '. | type == "array"' > /dev/null 2>&1; then
            local base_count=$(echo "$response" | jq '. | length' 2>/dev/null)
            print_status "pass" "Airtable Integration" "Airtable gateway responding ($base_count bases)"
            return 0
        else
            print_status "warn" "Airtable Integration" "Unexpected response format"
            return 1
        fi
    else
        print_status "fail" "Airtable Integration" "Airtable gateway not responding"
        return 1
    fi
}

# Test 7: LLM Integration
test_llm_integration() {
    print_status "info" "LLM Integration" "Testing LLM orchestrator..."
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_status "fail" "LLM Integration" "No access token available"
        return 1
    fi
    
    # Test simple LLM query
    local llm_data=$(cat <<EOF
{
    "message": "Hello, this is a smoke test. Please respond with 'Hello, smoke test successful!'",
    "temperature": 0.1
}
EOF
)
    
    local response
    if response=$(make_request "POST" "$API_BASE_URL/api/v1/chat" "$llm_data" "Authorization: Bearer $ACCESS_TOKEN" 200); then
        # Check if we get a response with content
        local content=$(echo "$response" | jq -r '.response // .content // .message // empty' 2>/dev/null)
        if [ -n "$content" ] && [ "$content" != "null" ]; then
            print_status "pass" "LLM Integration" "LLM responding: ${content:0:50}..."
            return 0
        else
            print_status "warn" "LLM Integration" "LLM response but no content"
            return 1
        fi
    else
        print_status "fail" "LLM Integration" "LLM not responding"
        return 1
    fi
}

# Test 8: File Upload (Automation Services)
test_file_upload() {
    print_status "info" "File Upload" "Testing file upload functionality..."
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_status "fail" "File Upload" "No access token available"
        return 1
    fi
    
    # Create a test file
    local test_file="/tmp/smoke_test.txt"
    echo "This is a smoke test file created at $(date)" > "$test_file"
    
    # Upload file
    local response
    if response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
        -X POST "$API_BASE_URL/api/v1/files/upload" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "file=@$test_file" \
        --max-time $TIMEOUT); then
        
        local status_code=$(echo "$response" | tail -n1 | cut -d: -f2)
        local response_body=$(echo "$response" | sed '$d')
        
        if [ "$status_code" -eq 200 ] || [ "$status_code" -eq 201 ]; then
            local file_id=$(echo "$response_body" | jq -r '.id // .file_id // empty' 2>/dev/null)
            print_status "pass" "File Upload" "File uploaded successfully (ID: $file_id)"
            rm -f "$test_file"
            return 0
        else
            print_status "fail" "File Upload" "Upload failed with status $status_code"
            rm -f "$test_file"
            return 1
        fi
    else
        print_status "fail" "File Upload" "Upload request failed"
        rm -f "$test_file"
        return 1
    fi
}

# Test 9: Service Metrics
test_service_metrics() {
    print_status "info" "Service Metrics" "Testing metrics endpoints..."
    
    # Test Prometheus metrics if available
    if curl -s --max-time 5 "http://localhost:9090/api/v1/query?query=up" > /dev/null 2>&1; then
        print_status "pass" "Service Metrics" "Prometheus metrics available"
        return 0
    else
        # Test individual service metrics
        local services=("8080" "8001" "8002")
        local metrics_available=0
        
        for port in "${services[@]}"; do
            if curl -s --max-time 5 "http://localhost:$port/metrics" > /dev/null 2>&1; then
                metrics_available=$((metrics_available + 1))
            fi
        done
        
        if [ $metrics_available -gt 0 ]; then
            print_status "pass" "Service Metrics" "$metrics_available services exposing metrics"
            return 0
        else
            print_status "warn" "Service Metrics" "No metrics endpoints found"
            return 1
        fi
    fi
}

# Test 10: Database Connectivity
test_database_connectivity() {
    print_status "info" "Database Connectivity" "Testing database connectivity..."
    
    # Test if we can connect to PostgreSQL through a service
    if [ -z "$ACCESS_TOKEN" ]; then
        print_status "fail" "Database Connectivity" "No access token available"
        return 1
    fi
    
    # Make a request that requires database access
    if make_request "GET" "$API_BASE_URL/api/v1/users/me" "" "Authorization: Bearer $ACCESS_TOKEN" 200 > /dev/null; then
        print_status "pass" "Database Connectivity" "Services can access database"
        return 0
    else
        print_status "fail" "Database Connectivity" "Database connectivity issues"
        return 1
    fi
}

# Cleanup function
cleanup_test_data() {
    print_status "info" "Cleanup" "Cleaning up test data..."
    
    # Delete test workspace if created
    if [ -n "$WORKSPACE_ID" ] && [ -n "$ACCESS_TOKEN" ]; then
        if make_request "DELETE" "$API_BASE_URL/api/v1/workspaces/$WORKSPACE_ID" "" "Authorization: Bearer $ACCESS_TOKEN" 200 > /dev/null 2>&1; then
            print_status "info" "Cleanup" "Test workspace deleted"
        fi
    fi
    
    # Note: We don't delete the test user as it might be useful for future tests
    print_status "info" "Cleanup" "Test user preserved for future tests"
}

# Main test runner
main() {
    echo -e "${BLUE}🧪 PyAirtable Platform Smoke Test${NC}"
    echo "=================================="
    echo "Started at: $(date)"
    echo "API Base URL: $API_BASE_URL"
    echo ""
    
    local tests=(
        "test_api_gateway_health"
        "test_user_registration"
        "test_user_authentication"
        "test_user_profile_access"
        "test_workspace_creation"
        "test_airtable_integration"
        "test_llm_integration"
        "test_file_upload"
        "test_service_metrics"
        "test_database_connectivity"
    )
    
    local passed=0
    local failed=0
    local total=${#tests[@]}
    
    # Run all tests
    for test_func in "${tests[@]}"; do
        echo ""
        if $test_func; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    # Cleanup
    echo ""
    cleanup_test_data
    
    # Summary
    echo -e "\n${BLUE}📊 Smoke Test Summary${NC}"
    echo "====================="
    echo "Total Tests: $total"
    echo "Passed: $passed"
    echo "Failed: $failed"
    
    if [ $failed -eq 0 ]; then
        print_status "pass" "Overall Result" "All smoke tests passed! 🎉"
        echo -e "\n${GREEN}✅ Platform is functioning correctly${NC}"
        exit 0
    else
        print_status "fail" "Overall Result" "$failed out of $total tests failed"
        echo -e "\n${RED}❌ Platform has functional issues${NC}"
        exit 1
    fi
}

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "PyAirtable Platform Smoke Test"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  --url <url>         Override API base URL (default: http://localhost:8080)"
    echo "  --timeout <sec>     Set request timeout (default: 30)"
    echo "  --email <email>     Override test email (default: smoketest@example.com)"
    echo "  --password <pass>   Override test password"
    echo ""
    echo "This script performs end-to-end testing of the PyAirtable platform"
    echo "to verify that all critical functionality is working."
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            API_BASE_URL="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --email)
            TEST_EMAIL="$2"
            shift 2
            ;;
        --password)
            TEST_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check dependencies
if ! command -v curl &> /dev/null; then
    print_status "fail" "Dependencies" "curl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    print_status "fail" "Dependencies" "jq is required but not installed"
    exit 1
fi

# Run main function
main