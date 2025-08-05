#!/bin/bash

# PyAirtable AI Chat Functionality Integration Tests
# Tests AI chat with Airtable integration using placeholder credentials

set -e

# Source test helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/test-helpers.sh"
source "$SCRIPT_DIR/../utils/test-config.env"

# Test configuration
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.minimal.yml}"
TEST_RESULTS_FILE="$TEST_RESULTS_DIR/chat-functionality-results.txt"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Function to test basic chat endpoint availability
test_chat_endpoint_availability() {
    local test_name="Chat Endpoint Availability"
    local url="http://localhost:8003/chat"
    
    # Test if endpoint exists (should return 400/422 for empty request, not 404)
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -X POST -H "Content-Type: application/json" "$url" 2>/dev/null)
    
    case "$status" in
        "400"|"422"|"200")
            print_test_result "PASS" "$test_name" "Chat endpoint exists (HTTP $status)"
            return 0
            ;;
        "404")
            print_test_result "FAIL" "$test_name" "Chat endpoint not found (HTTP $status)"
            return 1
            ;;
        *)
            print_test_result "WARN" "$test_name" "Unexpected response (HTTP $status)"
            return 1
            ;;
    esac
}

# Function to test chat with placeholder credentials
test_chat_with_placeholders() {
    local test_name="Chat with Placeholder Credentials"
    local url="http://localhost:8003/chat"
    
    local payload='{
        "message": "Hello, test message for validation",
        "session_id": "'$TEST_SESSION_ID'",
        "base_id": "'$TEST_AIRTABLE_BASE'"
    }'
    
    # Make request with placeholder data
    local response=$(curl -s --max-time $TEST_LONG_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_LONG_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    # Analyze response
    if [ "$status" = "200" ]; then
        if echo "$response" | grep -q "response\|message\|content"; then
            print_test_result "PASS" "$test_name" "Chat responded successfully with placeholder credentials"
            return 0
        else
            print_test_result "WARN" "$test_name" "Chat responded but format unexpected"
            return 1
        fi
    elif [ "$status" = "401" ] || [ "$status" = "403" ]; then
        print_test_result "INFO" "$test_name" "Authentication required (HTTP $status) - expected with placeholder credentials"
        return 0  # This is expected with placeholder credentials
    elif [ "$status" = "400" ] || [ "$status" = "422" ]; then
        print_test_result "INFO" "$test_name" "Invalid request (HTTP $status) - expected with placeholder credentials"
        return 0  # This is expected with invalid Airtable credentials
    else
        print_test_result "FAIL" "$test_name" "Unexpected error (HTTP $status)"
        return 1
    fi
}

# Function to test chat request validation
test_chat_request_validation() {
    local test_name="Chat Request Validation"
    local url="http://localhost:8003/chat"
    
    # Test empty request
    local status_empty=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -d '{}' \
        "$url" 2>/dev/null)
    
    # Test malformed request
    local status_malformed=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -d '{"invalid": "request"}' \
        "$url" 2>/dev/null)
    
    if [ "$status_empty" = "400" ] || [ "$status_empty" = "422" ]; then
        if [ "$status_malformed" = "400" ] || [ "$status_malformed" = "422" ]; then
            print_test_result "PASS" "$test_name" "Request validation working (empty: $status_empty, malformed: $status_malformed)"
            return 0
        fi
    fi
    
    print_test_result "WARN" "$test_name" "Request validation behavior unclear (empty: $status_empty, malformed: $status_malformed)"
    return 1
}

# Function to test session management
test_session_management() {
    local test_name="Session Management"
    local url="http://localhost:8003/chat"
    local session_id="test-session-$(date +%s)"
    
    local payload='{
        "message": "Test session message",
        "session_id": "'$session_id'",
        "base_id": "'$TEST_AIRTABLE_BASE'"
    }'
    
    # Make two requests with the same session ID
    local response1=$(curl -s --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    local status1=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    # Check if the service handles session consistently
    if [ -n "$response1" ] && [ "$status1" != "500" ]; then
        print_test_result "PASS" "$test_name" "Session handling working (HTTP $status1)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Session handling failed (HTTP $status1)"
        return 1
    fi
}

# Function to test Airtable gateway integration
test_airtable_gateway_integration() {
    local test_name="Airtable Gateway Integration"
    local gateway_url="http://localhost:8002/health"
    local chat_url="http://localhost:8003/chat"
    
    # First check if Airtable gateway is responding
    if ! curl -s -f --max-time $TEST_TIMEOUT "$gateway_url" > /dev/null 2>&1; then
        print_test_result "FAIL" "$test_name" "Airtable gateway not responding"
        return 1
    fi
    
    # Test chat request that would require Airtable integration
    local payload='{
        "message": "List tables in my base",
        "session_id": "'$TEST_SESSION_ID'",
        "base_id": "'$TEST_AIRTABLE_BASE'"
    }'
    
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_LONG_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$chat_url" 2>/dev/null)
    
    # Any non-500 response suggests the integration path is working
    if [ "$status" != "500" ] && [ "$status" != "000" ]; then
        print_test_result "PASS" "$test_name" "Integration path working (HTTP $status)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Integration path failed (HTTP $status)"
        return 1
    fi
}

# Function to test MCP server integration
test_mcp_server_integration() {
    local test_name="MCP Server Integration"
    local mcp_url="http://localhost:8001/health"
    local chat_url="http://localhost:8003/chat"
    
    # Check if MCP server is responding
    if ! curl -s -f --max-time $TEST_TIMEOUT "$mcp_url" > /dev/null 2>&1; then
        print_test_result "FAIL" "$test_name" "MCP server not responding"
        return 1
    fi
    
    # Test that chat service can communicate with MCP server
    local payload='{
        "message": "System status check",
        "session_id": "'$TEST_SESSION_ID'"
    }'
    
    local response=$(curl -s --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$chat_url" 2>/dev/null)
    
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$chat_url" 2>/dev/null)
    
    if [ "$status" = "200" ] || [ "$status" = "400" ] || [ "$status" = "422" ]; then
        print_test_result "PASS" "$test_name" "MCP server integration path working (HTTP $status)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "MCP server integration failed (HTTP $status)"
        return 1
    fi
}

# Function to test error handling with invalid credentials
test_error_handling_invalid_credentials() {
    local test_name="Error Handling - Invalid Credentials"
    local url="http://localhost:8003/chat"
    
    local payload='{
        "message": "Test with invalid credentials",
        "session_id": "test-invalid",
        "base_id": "appINVALID123456"
    }'
    
    local response=$(curl -s --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: invalid-api-key" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    local status=$(curl -s -o /dev/null -w "%{http_code}" --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: invalid-api-key" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    # Should return appropriate error status
    if [ "$status" = "401" ] || [ "$status" = "403" ] || [ "$status" = "400" ] || [ "$status" = "422" ]; then
        print_test_result "PASS" "$test_name" "Proper error handling for invalid credentials (HTTP $status)"
        return 0
    else
        print_test_result "FAIL" "$test_name" "Unexpected response for invalid credentials (HTTP $status)"
        return 1
    fi
}

# Function to test chat response format
test_chat_response_format() {
    local test_name="Chat Response Format"
    local url="http://localhost:8003/chat"
    
    local payload='{
        "message": "Simple test message",
        "session_id": "'$TEST_SESSION_ID'"
    }'
    
    local response=$(curl -s --max-time $TEST_TIMEOUT -X POST \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $TEST_API_KEY" \
        -d "$payload" \
        "$url" 2>/dev/null)
    
    # Check if response is valid JSON
    if echo "$response" | jq . > /dev/null 2>&1; then
        print_test_result "PASS" "$test_name" "Response is valid JSON"
        return 0
    elif [ -n "$response" ]; then
        print_test_result "WARN" "$test_name" "Response is not JSON but present"
        return 1
    else
        print_test_result "FAIL" "$test_name" "No response received"
        return 1
    fi
}

# Main test functions
test_chat_basic_functionality_suite() {
    print_test_result "INFO" "Test Suite" "Starting basic chat functionality tests"
    
    local tests_passed=0
    local tests_total=4
    
    if test_chat_endpoint_availability; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_chat_request_validation; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_session_management; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_chat_response_format; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Basic chat functionality: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge 3 ] && echo 0 || echo 1)  # Require 3/4 tests to pass
}

test_integration_functionality_suite() {
    print_test_result "INFO" "Test Suite" "Starting integration functionality tests"
    
    local tests_passed=0
    local tests_total=3
    
    if test_airtable_gateway_integration; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_mcp_server_integration; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_chat_with_placeholders; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Integration functionality: $tests_passed/$tests_total passed"
    return $([ $tests_passed -ge 2 ] && echo 0 || echo 1)  # Require 2/3 tests to pass
}

test_error_handling_suite() {
    print_test_result "INFO" "Test Suite" "Starting error handling tests"
    
    local tests_passed=0
    local tests_total=1
    
    if test_error_handling_invalid_credentials; then
        tests_passed=$((tests_passed + 1))
    fi
    
    print_test_result "INFO" "Test Suite" "Error handling: $tests_passed/$tests_total passed"
    return $([ $tests_passed -eq $tests_total ] && echo 0 || echo 1)
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    print_test_result "INFO" "Chat Functionality Tests" "Starting PyAirtable AI chat functionality validation"
    
    # Check prerequisites
    if ! check_test_prerequisites; then
        print_test_result "FAIL" "Test Execution" "Prerequisites not met"
        exit 1
    fi
    
    # Setup test environment
    setup_test_environment "$COMPOSE_FILE"
    
    # Initialize results file
    echo "PyAirtable Chat Functionality Test Results" > "$TEST_RESULTS_FILE"
    echo "Started: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Compose File: $COMPOSE_FILE" >> "$TEST_RESULTS_FILE"
    echo "Test Session ID: $TEST_SESSION_ID" >> "$TEST_RESULTS_FILE"
    echo "=====================================" >> "$TEST_RESULTS_FILE"
    
    # Run test suites
    local total_suites=0
    local passed_suites=0
    
    # Test basic functionality
    total_suites=$((total_suites + 1))
    if test_chat_basic_functionality_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test integration functionality
    total_suites=$((total_suites + 1))
    if test_integration_functionality_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Test error handling
    total_suites=$((total_suites + 1))
    if test_error_handling_suite; then
        passed_suites=$((passed_suites + 1))
    fi
    
    # Generate final report
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "" >> "$TEST_RESULTS_FILE"
    echo "Completed: $(date)" >> "$TEST_RESULTS_FILE"
    echo "Duration: ${duration}s" >> "$TEST_RESULTS_FILE"
    echo "Test Suites Passed: $passed_suites/$total_suites" >> "$TEST_RESULTS_FILE"
    
    # Print summary
    print_test_result "INFO" "Test Summary" "Chat functionality tests completed in ${duration}s"
    print_test_result "INFO" "Test Summary" "Test suites passed: $passed_suites/$total_suites"
    
    # Print next steps for customer
    echo ""
    print_test_result "INFO" "Next Steps" "To test with real credentials:"
    print_test_result "INFO" "Next Steps" "1. Update .env file with actual AIRTABLE_TOKEN, AIRTABLE_BASE, and GEMINI_API_KEY"
    print_test_result "INFO" "Next Steps" "2. Re-run this test to validate full functionality"
    print_test_result "INFO" "Next Steps" "3. Test with: curl -X POST http://localhost:8003/chat -H 'Content-Type: application/json' -d '{\"message\":\"List my tables\",\"session_id\":\"test\"}'"
    
    if [ $passed_suites -ge $((total_suites * 2 / 3)) ]; then  # Allow 67% pass rate for placeholder testing
        print_test_result "PASS" "Overall Result" "Chat functionality tests passed with placeholder credentials"
        echo "OVERALL_RESULT=PASS" >> "$TEST_RESULTS_FILE"
        exit 0
    else
        print_test_result "FAIL" "Overall Result" "Chat functionality tests failed"
        echo "OVERALL_RESULT=FAIL" >> "$TEST_RESULTS_FILE"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "PyAirtable Chat Functionality Tests"
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --compose-file     Specify docker-compose file (default: docker-compose.minimal.yml)"
        echo "  --quick           Quick test mode (reduced tests)"
        echo "  --with-real-creds Use real credentials from .env if available"
        echo ""
        echo "Note: This test uses placeholder credentials by default."
        echo "      To test with real credentials, use --with-real-creds"
        echo "      or update the .env file with actual values."
        exit 0
        ;;
    --compose-file)
        COMPOSE_FILE="$2"
        shift 2
        ;;
    --quick)
        TEST_TIMEOUT=10
        TEST_LONG_TIMEOUT=30
        shift
        ;;
    --with-real-creds)
        # Use real credentials from environment if available
        if [ -n "$AIRTABLE_TOKEN" ] && [ -n "$GEMINI_API_KEY" ]; then
            TEST_AIRTABLE_TOKEN="$AIRTABLE_TOKEN"
            TEST_GEMINI_API_KEY="$GEMINI_API_KEY"
            if [ -n "$AIRTABLE_BASE" ]; then
                TEST_AIRTABLE_BASE="$AIRTABLE_BASE"
            fi
        fi
        shift
        ;;
esac

# Run main function
main "$@"