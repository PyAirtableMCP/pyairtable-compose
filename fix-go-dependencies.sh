#!/bin/bash

# Fix Go Dependencies Script
# Fixes module path issues for Go shared library and all Go services

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"
SHARED_LIB_DIR="$PROJECT_ROOT/pyairtable-infrastructure/pyairtable-go-shared"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fix shared library go.mod to use local path references
fix_shared_library() {
    log_info "Fixing shared library dependencies..."
    
    cd "$SHARED_LIB_DIR"
    
    # Ensure we have a proper go.mod
    if [ ! -f "go.mod" ]; then
        log_error "go.mod not found in shared library directory"
        return 1
    fi
    
    # Update dependencies and tidy
    go mod download
    go mod tidy
    
    log_success "Fixed shared library dependencies"
}

# Fix Go service dependencies
fix_service_dependencies() {
    local service_name="$1"
    local service_dir="$GO_SERVICES_DIR/$service_name"
    
    if [ ! -d "$service_dir" ]; then
        log_warning "Service directory not found: $service_dir"
        return 0
    fi
    
    log_info "Fixing dependencies for $service_name"
    
    cd "$service_dir"
    
    if [ ! -f "go.mod" ]; then
        log_warning "go.mod not found for $service_name"
        return 0
    fi
    
    # Add replace directive to use local shared library
    if ! grep -q "replace github.com/Reg-Kris/pyairtable-go-shared" go.mod; then
        echo "" >> go.mod
        echo "replace github.com/Reg-Kris/pyairtable-go-shared => ../../pyairtable-infrastructure/pyairtable-go-shared" >> go.mod
    fi
    
    # Download dependencies and tidy
    go mod download 2>/dev/null || log_warning "Failed to download dependencies for $service_name"
    go mod tidy 2>/dev/null || log_warning "Failed to tidy dependencies for $service_name"
    
    log_success "Fixed dependencies for $service_name"
}

# Create go.work file for workspace management
create_workspace() {
    log_info "Creating Go workspace..."
    
    cd "$PROJECT_ROOT"
    
    cat > go.work << EOF
go 1.21

use (
    ./pyairtable-infrastructure/pyairtable-go-shared
    ./go-services/api-gateway
    ./go-services/auth-service
    ./go-services/user-service
    ./go-services/tenant-service
    ./go-services/workspace-service
    ./go-services/permission-service
    ./go-services/webhook-service
    ./go-services/notification-service
    ./go-services/file-service
    ./go-services/web-bff
    ./go-services/mobile-bff
)
EOF
    
    log_success "Created Go workspace"
}

# Main execution
main() {
    log_info "Fixing Go dependencies for all services"
    echo ""
    
    # Fix shared library first
    fix_shared_library
    
    # Fix each Go service
    GO_SERVICES=(
        "api-gateway"
        "auth-service"
        "user-service"
        "tenant-service"
        "workspace-service"
        "permission-service"
        "webhook-service"
        "notification-service"
        "file-service"
        "web-bff"
        "mobile-bff"
    )
    
    for service in "${GO_SERVICES[@]}"; do
        fix_service_dependencies "$service"
    done
    
    # Create workspace
    create_workspace
    
    echo ""
    log_success "All Go dependencies fixed!"
    log_info "You can now build services using 'go build' from each service directory"
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root directory"
    exit 1
fi

# Execute main function
main "$@"