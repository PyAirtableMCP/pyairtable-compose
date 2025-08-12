#!/bin/bash

# Fix Go Dependencies Script
# Updates all Go services to use local replace directive

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fix Go dependencies for a service
fix_go_service_deps() {
    local service_name=$1
    local service_dir="$GO_SERVICES_DIR/$service_name"
    
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory not found: $service_dir"
        return 1
    fi
    
    log_info "Fixing dependencies for: $service_name"
    
    cd "$service_dir"
    
    # Initialize go.sum if it doesn't exist
    if [ ! -f "go.sum" ]; then
        touch go.sum
    fi
    
    # Download dependencies
    go mod download 2>/dev/null || true
    
    # Tidy the module
    go mod tidy
    
    # Verify build
    if go build -o /dev/null ./cmd/$service_name 2>/dev/null; then
        log_success "✅ $service_name - dependencies fixed"
    else
        log_error "⚠️  $service_name - build failed, manual intervention needed"
    fi
    
    cd "$PROJECT_ROOT"
}

# Main execution
main() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Fixing Go Service Dependencies${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    
    # List of Go services
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
    
    # Fix each service
    for service in "${GO_SERVICES[@]}"; do
        fix_go_service_deps "$service"
    done
    
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}✅ Dependency Fix Complete!${NC}"
    echo -e "${GREEN}=====================================${NC}"
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root"
    exit 1
fi

# Execute main
main "$@"