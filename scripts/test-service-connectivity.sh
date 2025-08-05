#!/bin/bash
# Service Connectivity Test Script for PyAirtable
# Tests actual service connections to Airtable and Gemini APIs
# Author: Claude DevOps Engineer

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test configuration
readonly TIMEOUT=30
readonly MAX_RETRIES=3

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local service_url="$2"
    local timeout="$3"
    
    print_info "Waiting for $service_name to be ready..."
    
    local count=0
    while [[ $count -lt $timeout ]]; do
        if curl -s --max-time 5 "$service_url/health" >/dev/null 2>&1; then
            print_success "$service_name is ready"
            return 0
        fi
        
        sleep 1
        ((count++))
        
        if [[ $((count % 10)) -eq 0 ]]; then
            print_info "Still waiting for $service_name... ($count/${timeout}s)"
        fi
    done
    
    print_error "$service_name failed to become ready within ${timeout}s"
    return 1
}

# Test Airtable Gateway connectivity
test_airtable_gateway() {
    print_header "Testing Airtable Gateway Service"
    
    local gateway_url="http://localhost:8002"
    local errors=0
    
    # Wait for service to be ready
    if ! wait_for_service "Airtable Gateway" "$gateway_url" 30; then
        return 1
    fi
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    local health_response=$(curl -s -w "%{http_code}" -o /tmp/gateway_health.json "$gateway_url/health" 2>/dev/null || echo "000")
    
    if [[ "$health_response" == "200" ]]; then
        print_success "Health endpoint responding"
    else
        print_error "Health endpoint failed (HTTP $health_response)"
        ((errors++))
    fi
    
    # Test Airtable connection through gateway
    print_info "Testing Airtable connection through gateway..."
    local airtable_test=$(curl -s -w "%{http_code}" -o /tmp/gateway_airtable.json \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        "$gateway_url/bases" 2>/dev/null || echo "000")
    
    if [[ "$airtable_test" == "200" ]]; then
        print_success "Airtable connection through gateway working"
        
        # Check if we got actual data
        if jq -e '.bases' /tmp/gateway_airtable.json >/dev/null 2>&1; then
            local base_count=$(jq '.bases | length' /tmp/gateway_airtable.json 2>/dev/null || echo "0")
            print_info "Found $base_count Airtable bases"
        fi
    else
        print_error "Airtable connection through gateway failed (HTTP $airtable_test)"
        ((errors++))
    fi
    
    # Test specific base access
    print_info "Testing specific base access..."
    local base_test=$(curl -s -w "%{http_code}" -o /tmp/gateway_base.json \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        "$gateway_url/bases/appVLUAubH5cFWhMV/tables" 2>/dev/null || echo "000")
    
    if [[ "$base_test" == "200" ]]; then
        print_success "Base-specific access working"
        
        # Check if we got table data
        if jq -e '.tables' /tmp/gateway_base.json >/dev/null 2>&1; then
            local table_count=$(jq '.tables | length' /tmp/gateway_base.json 2>/dev/null || echo "0")
            print_info "Found $table_count tables in base"
        fi
    else
        print_error "Base-specific access failed (HTTP $base_test)"
        ((errors++))
    fi
    
    # Clean up
    rm -f /tmp/gateway_*.json
    
    if [[ $errors -eq 0 ]]; then
        print_success "Airtable Gateway tests passed"
        return 0
    else
        print_error "Airtable Gateway tests failed with $errors errors"
        return 1
    fi
}

# Test LLM Orchestrator connectivity
test_llm_orchestrator() {
    print_header "Testing LLM Orchestrator Service"
    
    local orchestrator_url="http://localhost:8003"
    local errors=0
    
    # Wait for service to be ready
    if ! wait_for_service "LLM Orchestrator" "$orchestrator_url" 30; then
        return 1
    fi
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    local health_response=$(curl -s -w "%{http_code}" -o /tmp/llm_health.json "$orchestrator_url/health" 2>/dev/null || echo "000")
    
    if [[ "$health_response" == "200" ]]; then
        print_success "Health endpoint responding"
    else
        print_error "Health endpoint failed (HTTP $health_response)"
        ((errors++))
    fi
    
    # Test Gemini API connectivity
    print_info "Testing Gemini API connectivity..."
    local gemini_test=$(curl -s -w "%{http_code}" -o /tmp/llm_gemini.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        -d '{
            "messages": [{"role": "user", "content": "Hello, this is a connectivity test. Please respond with just the word TEST."}],
            "model": "gemini-2.0-flash-exp",
            "max_tokens": 10
        }' \
        "$orchestrator_url/v1/chat/completions" 2>/dev/null || echo "000")
    
    if [[ "$gemini_test" == "200" ]]; then
        print_success "Gemini API connection working"
        
        # Check if we got a proper response
        if jq -e '.choices[0].message.content' /tmp/llm_gemini.json >/dev/null 2>&1; then
            local response_content=$(jq -r '.choices[0].message.content' /tmp/llm_gemini.json 2>/dev/null || echo "")
            print_info "Gemini response: $response_content"
        fi
    else
        print_error "Gemini API connection failed (HTTP $gemini_test)"
        ((errors++))
    fi
    
    # Test model availability
    print_info "Testing model availability..."
    local models_test=$(curl -s -w "%{http_code}" -o /tmp/llm_models.json \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        "$orchestrator_url/v1/models" 2>/dev/null || echo "000")
    
    if [[ "$models_test" == "200" ]]; then
        print_success "Model availability endpoint working"
        
        # Check if we got model data
        if jq -e '.data' /tmp/llm_models.json >/dev/null 2>&1; then
            local model_count=$(jq '.data | length' /tmp/llm_models.json 2>/dev/null || echo "0")
            print_info "Found $model_count available models"
        fi
    else
        print_error "Model availability test failed (HTTP $models_test)"
        ((errors++))
    fi
    
    # Clean up
    rm -f /tmp/llm_*.json
    
    if [[ $errors -eq 0 ]]; then
        print_success "LLM Orchestrator tests passed"
        return 0
    else
        print_error "LLM Orchestrator tests failed with $errors errors"
        return 1
    fi
}

# Test MCP Server connectivity
test_mcp_server() {
    print_header "Testing MCP Server Service"
    
    local mcp_url="http://localhost:8001"
    local errors=0
    
    # Wait for service to be ready
    if ! wait_for_service "MCP Server" "$mcp_url" 30; then
        return 1
    fi
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    local health_response=$(curl -s -w "%{http_code}" -o /tmp/mcp_health.json "$mcp_url/health" 2>/dev/null || echo "000")
    
    if [[ "$health_response" == "200" ]]; then
        print_success "Health endpoint responding"
    else
        print_error "Health endpoint failed (HTTP $health_response)"
        ((errors++))
    fi
    
    # Test MCP tools availability
    print_info "Testing MCP tools availability..."
    local tools_test=$(curl -s -w "%{http_code}" -o /tmp/mcp_tools.json \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        "$mcp_url/tools" 2>/dev/null || echo "000")
    
    if [[ "$tools_test" == "200" ]]; then
        print_success "MCP tools endpoint working"
        
        # Check if we got tool data
        if jq -e '.tools' /tmp/mcp_tools.json >/dev/null 2>&1; then
            local tool_count=$(jq '.tools | length' /tmp/mcp_tools.json 2>/dev/null || echo "0")
            print_info "Found $tool_count available MCP tools"
        fi
    else
        print_error "MCP tools test failed (HTTP $tools_test)"
        ((errors++))
    fi
    
    # Test a simple MCP tool call
    print_info "Testing MCP tool execution..."
    local tool_test=$(curl -s -w "%{http_code}" -o /tmp/mcp_tool_test.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        -d '{
            "tool": "airtable_list_bases",
            "arguments": {}
        }' \
        "$mcp_url/tools/call" 2>/dev/null || echo "000")
    
    if [[ "$tool_test" == "200" ]]; then
        print_success "MCP tool execution working"
    else
        print_error "MCP tool execution failed (HTTP $tool_test)"
        ((errors++))
    fi
    
    # Clean up
    rm -f /tmp/mcp_*.json
    
    if [[ $errors -eq 0 ]]; then
        print_success "MCP Server tests passed"
        return 0
    else
        print_error "MCP Server tests failed with $errors errors"
        return 1
    fi
}

# Test API Gateway connectivity
test_api_gateway() {
    print_header "Testing API Gateway Service"
    
    local gateway_url="http://localhost:8000"
    local errors=0
    
    # Wait for service to be ready
    if ! wait_for_service "API Gateway" "$gateway_url" 30; then
        return 1
    fi
    
    # Test health endpoint
    print_info "Testing health endpoint..."
    local health_response=$(curl -s -w "%{http_code}" -o /tmp/api_health.json "$gateway_url/health" 2>/dev/null || echo "000")
    
    if [[ "$health_response" == "200" ]]; then
        print_success "Health endpoint responding"
    else
        print_error "Health endpoint failed (HTTP $health_response)"
        ((errors++))
    fi
    
    # Test service routing
    print_info "Testing service routing..."
    local routing_test=$(curl -s -w "%{http_code}" -o /tmp/api_routing.json \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        "$gateway_url/api/v1/status" 2>/dev/null || echo "000")
    
    if [[ "$routing_test" == "200" ]]; then
        print_success "Service routing working"
    else
        print_error "Service routing failed (HTTP $routing_test)"
        ((errors++))
    fi
    
    # Clean up
    rm -f /tmp/api_*.json
    
    if [[ $errors -eq 0 ]]; then
        print_success "API Gateway tests passed"
        return 0
    else
        print_error "API Gateway tests failed with $errors errors"
        return 1
    fi
}

# Test end-to-end workflow
test_e2e_workflow() {
    print_header "Testing End-to-End Workflow"
    
    print_info "Testing complete Airtable + Gemini workflow..."
    
    # Test a complete workflow: Get Airtable data, process with Gemini
    local workflow_test=$(curl -s -w "%{http_code}" -o /tmp/e2e_workflow.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${API_KEY:-pya_efe1764855b2300ebc87363fb26b71da645a1e6c}" \
        -d '{
            "messages": [
                {
                    "role": "user", 
                    "content": "Please list the available tables in my Airtable base and provide a brief summary of what data might be stored."
                }
            ],
            "tools": ["airtable_list_bases", "airtable_get_schema"],
            "model": "gemini-2.0-flash-exp"
        }' \
        "http://localhost:8000/api/v1/chat/completions" 2>/dev/null || echo "000")
    
    if [[ "$workflow_test" == "200" ]]; then
        print_success "End-to-end workflow test passed"
        
        # Check if we got a proper response
        if jq -e '.choices[0].message.content' /tmp/e2e_workflow.json >/dev/null 2>&1; then
            local response_length=$(jq -r '.choices[0].message.content | length' /tmp/e2e_workflow.json 2>/dev/null || echo "0")
            print_info "Received response of $response_length characters"
        fi
    else
        print_error "End-to-end workflow test failed (HTTP $workflow_test)"
        return 1
    fi
    
    # Clean up
    rm -f /tmp/e2e_*.json
    
    print_success "End-to-end workflow tests passed"
    return 0
}

# Generate test report
generate_test_report() {
    local total_errors="$1"
    
    print_header "Service Connectivity Test Report"
    
    echo "Test Summary:"
    echo "=============="
    echo "Timestamp: $(date)"
    echo "Total Service Errors: $total_errors"
    echo ""
    
    if [[ $total_errors -eq 0 ]]; then
        print_success "ALL SERVICE CONNECTIVITY TESTS PASSED!"
        echo ""
        echo "✅ Airtable Gateway - CONNECTED & WORKING"
        echo "✅ LLM Orchestrator (Gemini) - CONNECTED & WORKING"  
        echo "✅ MCP Server - CONNECTED & WORKING"
        echo "✅ API Gateway - CONNECTED & WORKING"
        echo "✅ End-to-End Workflow - WORKING"
        echo ""
        echo "🎉 SYSTEM IS FULLY OPERATIONAL!"
        echo ""
        echo "All services are successfully connecting to:"
        echo "• Airtable API with base: appVLUAubH5cFWhMV"
        echo "• Google Gemini API"
        echo "• Internal service mesh"
        echo ""
        echo "Ready for production use!"
    else
        print_error "SERVICE CONNECTIVITY TESTS FAILED!"
        echo ""
        echo "❌ Found $total_errors service connectivity issues"
        echo ""
        echo "Please check the errors above and verify:"
        echo "1. All services are running (docker-compose up -d)"
        echo "2. Environment variables are correctly set"
        echo "3. Network connectivity is working"
        echo "4. API keys and credentials are valid"
    fi
}

# Main test function
main() {
    local total_errors=0
    
    print_header "PyAirtable Service Connectivity Tests"
    print_info "Testing all services with production credentials..."
    
    # Load environment variables
    if [[ -f "$PROJECT_ROOT/.env.local" ]]; then
        source "$PROJECT_ROOT/.env.local"
    fi
    
    print_info "Using Airtable Base: ${AIRTABLE_BASE:-appVLUAubH5cFWhMV}"
    print_info "Testing with production credentials"
    echo ""
    
    # Test individual services
    test_airtable_gateway || ((total_errors++))
    test_llm_orchestrator || ((total_errors++))
    test_mcp_server || ((total_errors++))
    test_api_gateway || ((total_errors++))
    
    # Test end-to-end workflow if all services are working
    if [[ $total_errors -eq 0 ]]; then
        test_e2e_workflow || ((total_errors++))
    else
        print_warning "Skipping end-to-end test due to service failures"
    fi
    
    # Generate final report
    generate_test_report "$total_errors"
    
    # Exit with appropriate code
    if [[ $total_errors -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"