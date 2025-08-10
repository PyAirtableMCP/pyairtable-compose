#!/bin/bash

# Service Health Check Wait Script
# Generic script to wait for HTTP services to be healthy

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="wait-for-service"
readonly MAX_RETRIES=${MAX_RETRIES:-30}
readonly RETRY_INTERVAL=${RETRY_INTERVAL:-5}
readonly TIMEOUT=${TIMEOUT:-150}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Show usage
show_usage() {
    echo "Usage: $0 <service_url> [health_endpoint]"
    echo
    echo "Arguments:"
    echo "  service_url      Base URL of the service (e.g., http://api-gateway:8000)"
    echo "  health_endpoint  Health check endpoint path (default: /health)"
    echo
    echo "Environment Variables:"
    echo "  MAX_RETRIES      Maximum number of retry attempts (default: 30)"
    echo "  RETRY_INTERVAL   Seconds between retries (default: 5)"
    echo "  TIMEOUT          Total timeout in seconds (default: 150)"
    echo
    echo "Examples:"
    echo "  $0 http://api-gateway:8000"
    echo "  $0 http://mcp-server:8001 /health"
    echo "  $0 http://platform-services:8007 /api/health"
    exit 1
}

# Parse command line arguments
parse_arguments() {
    if [[ $# -eq 0 ]]; then
        log_error "Missing required arguments"
        show_usage
    fi
    
    SERVICE_URL="$1"
    HEALTH_ENDPOINT="${2:-/health}"
    
    # Validate URL format
    if ! [[ "$SERVICE_URL" =~ ^https?://[^/]+(:([0-9]+))?$ ]]; then
        log_error "Invalid service URL format: $SERVICE_URL"
        log_error "Expected format: http://hostname:port or https://hostname:port"
        exit 1
    fi
    
    # Extract service name from URL for logging
    SERVICE_NAME=$(echo "$SERVICE_URL" | sed 's|^https\?://||' | cut -d: -f1)
    
    FULL_HEALTH_URL="${SERVICE_URL}${HEALTH_ENDPOINT}"
}

# Test service health
test_service_health() {
    local http_code
    local response_time
    
    # Use curl to check service health
    local curl_output
    curl_output=$(curl -s -w "%{http_code}|%{time_total}" --connect-timeout 5 --max-time 10 "$FULL_HEALTH_URL" 2>/dev/null || echo "000|0")
    
    http_code=$(echo "$curl_output" | cut -d'|' -f1)
    response_time=$(echo "$curl_output" | cut -d'|' -f2)
    
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        # Success - HTTP 2xx response
        LAST_RESPONSE_TIME="$response_time"
        return 0
    else
        return 1
    fi
}

# Get service info
get_service_info() {
    log_info "Getting service information..."
    
    # Try to get service version or info
    local info_endpoints=("/version" "/info" "/api/version" "/api/info")
    
    for endpoint in "${info_endpoints[@]}"; do
        local info_url="${SERVICE_URL}${endpoint}"
        local response
        
        if response=$(curl -s --connect-timeout 3 --max-time 5 "$info_url" 2>/dev/null); then
            if [[ -n "$response" && "$response" != "Not Found" ]]; then
                log_info "Service info from $endpoint:"
                # Pretty print JSON if possible
                if echo "$response" | jq . >/dev/null 2>&1; then
                    echo "$response" | jq . | head -10
                else
                    echo "$response" | head -3
                fi
                break
            fi
        fi
    done
}

# Wait for service to be healthy
wait_for_service() {
    log_info "Waiting for service at $FULL_HEALTH_URL..."
    
    local attempt=0
    local start_time=$(date +%s)
    
    while [[ $attempt -lt $MAX_RETRIES ]]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            log_error "Timeout ($TIMEOUT seconds) waiting for $SERVICE_NAME"
            return 1
        fi
        
        attempt=$((attempt + 1))
        
        if test_service_health; then
            local total_time=$(($(date +%s) - start_time))
            local response_ms=$(echo "$LAST_RESPONSE_TIME * 1000" | bc -l 2>/dev/null | cut -d. -f1 2>/dev/null || echo "N/A")
            log_success "$SERVICE_NAME is healthy! (attempt $attempt, ${total_time}s total, ${response_ms}ms response)"
            return 0
        else
            if [[ $((attempt % 5)) -eq 0 ]]; then
                log_info "Still waiting for $SERVICE_NAME... (attempt $attempt/$MAX_RETRIES, ${elapsed}s elapsed)"
            fi
            sleep "$RETRY_INTERVAL"
        fi
    done
    
    log_error "Failed to connect to $SERVICE_NAME after $MAX_RETRIES attempts"
    return 1
}

# Test service endpoints
test_service_endpoints() {
    log_info "Testing additional service endpoints..."
    
    # Common endpoints to test
    local endpoints=("/" "/api" "/docs" "/swagger" "/metrics" "/ready")
    local working_endpoints=()
    
    for endpoint in "${endpoints[@]}"; do
        local test_url="${SERVICE_URL}${endpoint}"
        local http_code
        
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "$test_url" 2>/dev/null || echo "000")
        
        if [[ "$http_code" =~ ^[23][0-9][0-9]$ ]]; then
            working_endpoints+=("$endpoint")
        fi
    done
    
    if [[ ${#working_endpoints[@]} -gt 0 ]]; then
        log_info "Available endpoints: ${working_endpoints[*]}"
    else
        log_warning "No additional endpoints found (this may be normal)"
    fi
}

# Main execution
main() {
    log_info "=== Service Health Check Wait Script ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "Max retries: $MAX_RETRIES"
    log_info "Retry interval: ${RETRY_INTERVAL}s"
    log_info "Timeout: ${TIMEOUT}s"
    echo
    
    # Parse arguments
    parse_arguments "$@"
    
    log_info "Service: $SERVICE_NAME"
    log_info "Health URL: $FULL_HEALTH_URL"
    echo
    
    # Wait for service
    if wait_for_service; then
        # Additional checks
        get_service_info
        test_service_endpoints
        
        log_success "Service $SERVICE_NAME is ready!"
        exit 0
    else
        log_error "Service $SERVICE_NAME health check failed"
        
        # Try to provide debugging information
        log_info "Debugging information:"
        log_info "- Check if the service is running: docker ps"
        log_info "- Check service logs: docker logs <container_name>"
        log_info "- Test connectivity: curl -v $FULL_HEALTH_URL"
        
        exit 1
    fi
}

# Handle signals
trap 'log_warning "Received interrupt signal, exiting..."; exit 130' INT TERM

# Run main function
main "$@"