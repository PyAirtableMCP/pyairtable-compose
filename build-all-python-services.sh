#!/bin/bash

# PyAirtable Docker Build Test Script
# Tests all Python service builds to verify Docker dependencies

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track results
PASSED=()
FAILED=()

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

build_service() {
    local service_name="$1"
    local service_path="$2"
    local dockerfile_path="$3"
    
    log_info "Building $service_name..."
    
    if [[ ! -d "$service_path" ]]; then
        log_error "Service directory $service_path does not exist"
        FAILED+=("$service_name - directory not found")
        return 1
    fi
    
    if [[ ! -f "$dockerfile_path" ]]; then
        log_error "Dockerfile not found at $dockerfile_path"
        FAILED+=("$service_name - Dockerfile not found")
        return 1
    fi
    
    # Change to service directory and build
    pushd "$service_path" > /dev/null
    
    if timeout 600 docker build -t "pyairtable-$service_name:test" -f "$dockerfile_path" . --no-cache; then
        log_success "$service_name build completed successfully"
        PASSED+=("$service_name")
        
        # Test if container starts (quick health check)
        log_info "Testing $service_name container startup..."
        if timeout 30 docker run --rm -d --name "${service_name}-test" "pyairtable-$service_name:test"; then
            sleep 5  # Give it time to start
            # Check if container is still running
            if docker ps | grep -q "${service_name}-test"; then
                docker stop "${service_name}-test" > /dev/null 2>&1 || true
                log_success "$service_name container startup test passed"
            else
                log_error "$service_name container exited immediately"
                FAILED+=("$service_name - container startup failed")
            fi
        else
            log_error "$service_name container failed to start"
            FAILED+=("$service_name - container startup failed")
        fi
    else
        log_error "$service_name build failed"
        FAILED+=("$service_name - build failed")
    fi
    
    popd > /dev/null
    echo "----------------------------------------"
}

# Main execution
echo "========================================"
echo "PyAirtable Docker Build Test Suite"
echo "========================================"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    log_error "Docker daemon is not running"
    exit 1
fi

# Build services
log_info "Starting build tests for all Python services..."

# Python services
build_service "airtable-gateway" "./python-services/airtable-gateway" "./python-services/airtable-gateway/Dockerfile"
build_service "llm-orchestrator" "./python-services/llm-orchestrator" "./python-services/llm-orchestrator/Dockerfile"
build_service "mcp-server" "./python-services/mcp-server" "./python-services/mcp-server/Dockerfile"

# Automation services
build_service "automation-services" "./pyairtable-automation-services" "./pyairtable-automation-services/Dockerfile"

# SAGA orchestrator
build_service "saga-orchestrator" "./saga-orchestrator" "./saga-orchestrator/Dockerfile"

# Summary
echo "========================================"
echo "BUILD TEST RESULTS"
echo "========================================"

if [[ ${#PASSED[@]} -gt 0 ]]; then
    log_success "PASSED (${#PASSED[@]}):"
    for service in "${PASSED[@]}"; do
        echo "  ✅ $service"
    done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_error "FAILED (${#FAILED[@]}):"
    for service in "${FAILED[@]}"; do
        echo "  ❌ $service"
    done
    echo
    log_error "Some builds failed. Check the output above for details."
    exit 1
else
    echo
    log_success "All builds passed! 🎉"
    log_info "Total services tested: ${#PASSED[@]}"
fi

# Clean up test images
log_info "Cleaning up test images..."
docker images | grep "pyairtable-.*:test" | awk '{print $3}' | xargs -r docker rmi -f

echo "========================================"
echo "Build test completed successfully!"
echo "========================================"