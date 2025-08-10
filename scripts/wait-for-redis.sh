#!/bin/bash

# Redis Connection Wait Script with Retry Logic
# Ensures Redis is ready before starting dependent services

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="wait-for-redis"
readonly MAX_RETRIES=${MAX_RETRIES:-30}
readonly RETRY_INTERVAL=${RETRY_INTERVAL:-5}
readonly TIMEOUT=${TIMEOUT:-150}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Redis configuration from environment
readonly REDIS_HOST="${REDIS_HOST:-redis}"
readonly REDIS_PORT="${REDIS_PORT:-6379}"
readonly REDIS_PASSWORD="${REDIS_PASSWORD}"

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

# Check if required environment variables are set
check_environment() {
    local missing_vars=()
    
    if [[ -z "${REDIS_PASSWORD:-}" ]]; then
        missing_vars+=("REDIS_PASSWORD")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        exit 1
    fi
}

# Test Redis connection
test_redis_connection() {
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning ping > /dev/null 2>&1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null 2>&1
    fi
}

# Test Redis operations
test_redis_operations() {
    local test_key="test:connection:$(date +%s)"
    local test_value="connection_test"
    
    log_info "Testing Redis operations..."
    
    # Test SET operation
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning set "$test_key" "$test_value" > /dev/null 2>&1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" set "$test_key" "$test_value" > /dev/null 2>&1
    fi
    
    # Test GET operation
    local retrieved_value
    if [[ -n "$REDIS_PASSWORD" ]]; then
        retrieved_value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning get "$test_key" 2>/dev/null)
    else
        retrieved_value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" get "$test_key" 2>/dev/null)
    fi
    
    # Test DELETE operation
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning del "$test_key" > /dev/null 2>&1
    else
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" del "$test_key" > /dev/null 2>&1
    fi
    
    if [[ "$retrieved_value" == "$test_value" ]]; then
        log_success "Redis operations test passed"
        return 0
    else
        log_error "Redis operations test failed"
        return 1
    fi
}

# Get Redis info
get_redis_info() {
    log_info "Getting Redis server information..."
    
    local redis_info
    if [[ -n "$REDIS_PASSWORD" ]]; then
        redis_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning info server 2>/dev/null | head -10)
    else
        redis_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" info server 2>/dev/null | head -10)
    fi
    
    if [[ -n "$redis_info" ]]; then
        # Extract Redis version
        local redis_version
        redis_version=$(echo "$redis_info" | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
        if [[ -n "$redis_version" ]]; then
            log_info "Redis version: $redis_version"
        fi
        
        # Extract uptime
        local uptime_seconds
        uptime_seconds=$(echo "$redis_info" | grep "uptime_in_seconds:" | cut -d: -f2 | tr -d '\r')
        if [[ -n "$uptime_seconds" && "$uptime_seconds" =~ ^[0-9]+$ ]]; then
            local uptime_minutes=$((uptime_seconds / 60))
            log_info "Redis uptime: ${uptime_minutes} minutes"
        fi
    else
        log_warning "Could not retrieve Redis server information"
    fi
}

# Wait for Redis to be ready
wait_for_redis() {
    log_info "Waiting for Redis at $REDIS_HOST:$REDIS_PORT..."
    
    local attempt=0
    local start_time=$(date +%s)
    
    while [[ $attempt -lt $MAX_RETRIES ]]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            log_error "Timeout ($TIMEOUT seconds) waiting for Redis"
            return 1
        fi
        
        attempt=$((attempt + 1))
        
        if test_redis_connection; then
            local total_time=$(($(date +%s) - start_time))
            log_success "Redis is responding to PING! (attempt $attempt, ${total_time}s total)"
            return 0
        else
            if [[ $((attempt % 5)) -eq 0 ]]; then
                log_info "Still waiting for Redis... (attempt $attempt/$MAX_RETRIES, ${elapsed}s elapsed)"
            fi
            sleep "$RETRY_INTERVAL"
        fi
    done
    
    log_error "Failed to connect to Redis after $MAX_RETRIES attempts"
    return 1
}

# Check Redis memory and performance
check_redis_health() {
    log_info "Checking Redis health metrics..."
    
    local memory_info
    if [[ -n "$REDIS_PASSWORD" ]]; then
        memory_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" --no-auth-warning info memory 2>/dev/null)
    else
        memory_info=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" info memory 2>/dev/null)
    fi
    
    if [[ -n "$memory_info" ]]; then
        # Extract used memory
        local used_memory
        used_memory=$(echo "$memory_info" | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
        if [[ -n "$used_memory" ]]; then
            log_info "Redis memory usage: $used_memory"
        fi
        
        # Check if Redis is saving data
        local rdb_bgsave_in_progress
        rdb_bgsave_in_progress=$(echo "$memory_info" | grep "rdb_bgsave_in_progress:" | cut -d: -f2 | tr -d '\r')
        if [[ "$rdb_bgsave_in_progress" == "1" ]]; then
            log_info "Redis is currently saving data to disk"
        fi
    fi
}

# Main execution
main() {
    log_info "=== Redis Connection Wait Script ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "Max retries: $MAX_RETRIES"
    log_info "Retry interval: ${RETRY_INTERVAL}s"
    log_info "Timeout: ${TIMEOUT}s"
    echo
    
    # Check environment
    check_environment
    
    # Wait for Redis
    if wait_for_redis; then
        # Additional checks
        get_redis_info
        test_redis_operations
        check_redis_health
        
        log_success "Redis is ready for connections!"
        exit 0
    else
        log_error "Redis connection failed"
        exit 1
    fi
}

# Handle signals
trap 'log_warning "Received interrupt signal, exiting..."; exit 130' INT TERM

# Run main function
main "$@"