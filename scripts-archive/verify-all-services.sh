#!/bin/bash

# Verify All Services Script
# Tests building and basic functionality of all 22 microservices

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"
PYTHON_SERVICES_DIR="$PROJECT_ROOT/python-services"

# Service definitions
GO_SERVICES=(
    "api-gateway:8080"
    "auth-service:8081"
    "user-service:8082"
    "tenant-service:8083"
    "workspace-service:8084"
    "permission-service:8085"
    "webhook-service:8086"
    "notification-service:8087"
    "file-service:8088"
    "web-bff:8089"
    "mobile-bff:8090"
)

PYTHON_SERVICES=(
    "llm-orchestrator:8091"
    "mcp-server:8092"
    "airtable-gateway:8093"
    "schema-service:8094"
    "formula-engine:8095"
    "embedding-service:8096"
    "semantic-search:8097"
    "chat-service:8098"
    "workflow-engine:8099"
    "analytics-service:8100"
    "audit-service:8101"
)

# Tracking variables
TOTAL_SERVICES=0
SUCCESSFUL_BUILDS=0
FAILED_BUILDS=0
MISSING_SERVICES=0

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Check if service directory exists and has required files
verify_service_structure() {
    local service_type="$1"
    local service_name="$2"
    local service_dir="$3"
    
    log_step "Verifying structure for $service_type service: $service_name"
    
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory not found: $service_dir"
        ((MISSING_SERVICES++))
        return 1
    fi
    
    if [ "$service_type" = "go" ]; then
        if [ ! -f "$service_dir/go.mod" ]; then
            log_error "go.mod not found for $service_name"
            return 1
        fi
        
        if [ ! -f "$service_dir/Dockerfile" ]; then
            log_error "Dockerfile not found for $service_name"
            return 1
        fi
        
        if [ ! -d "$service_dir/cmd" ]; then
            log_error "cmd directory not found for $service_name"
            return 1
        fi
        
    elif [ "$service_type" = "python" ]; then
        if [ ! -f "$service_dir/requirements.txt" ]; then
            log_error "requirements.txt not found for $service_name"
            return 1
        fi
        
        if [ ! -f "$service_dir/Dockerfile" ]; then
            log_error "Dockerfile not found for $service_name"
            return 1
        fi
        
        if [ ! -f "$service_dir/src/main.py" ]; then
            log_error "src/main.py not found for $service_name"
            return 1
        fi
    fi
    
    log_success "Structure verification passed for $service_name"
    return 0
}

# Test Docker build for service
test_docker_build() {
    local service_name="$1"
    local service_dir="$2"
    
    log_step "Testing Docker build for $service_name"
    
    cd "$service_dir"
    
    # Build Docker image
    if docker build -t "pyairtable-$service_name:test" . >/dev/null 2>&1; then
        log_success "Docker build successful for $service_name"
        # Clean up test image
        docker rmi "pyairtable-$service_name:test" >/dev/null 2>&1 || true
        ((SUCCESSFUL_BUILDS++))
        return 0
    else
        log_error "Docker build failed for $service_name"
        ((FAILED_BUILDS++))
        return 1
    fi
}

# Test Go build (before Docker)
test_go_build() {
    local service_name="$1"
    local service_dir="$2"
    
    log_step "Testing Go build for $service_name"
    
    cd "$service_dir"
    
    # Download dependencies
    if ! go mod download >/dev/null 2>&1; then
        log_warning "Failed to download Go dependencies for $service_name"
        return 1
    fi
    
    # Tidy dependencies
    if ! go mod tidy >/dev/null 2>&1; then
        log_warning "Failed to tidy Go dependencies for $service_name"
        return 1
    fi
    
    # Try to build
    if go build -o "/tmp/$service_name-test" ./cmd/"$service_name" >/dev/null 2>&1; then
        log_success "Go build successful for $service_name"
        rm -f "/tmp/$service_name-test"
        return 0
    else
        log_warning "Go build failed for $service_name (dependencies may need fixing)"
        return 1
    fi
}

# Test Python setup
test_python_setup() {
    local service_name="$1"
    local service_dir="$2"
    
    log_step "Testing Python setup for $service_name"
    
    cd "$service_dir"
    
    # Check if requirements.txt is valid
    if python3 -m pip install --dry-run -r requirements.txt >/dev/null 2>&1; then
        log_success "Python requirements valid for $service_name"
        return 0
    else
        log_warning "Python requirements validation failed for $service_name"
        return 1
    fi
}

# Verify a single service
verify_single_service() {
    local service_type="$1"
    local service_name="$2"
    local port="$3"
    local service_dir=""
    
    ((TOTAL_SERVICES++))
    
    if [ "$service_type" = "go" ]; then
        service_dir="$GO_SERVICES_DIR/$service_name"
    else
        service_dir="$PYTHON_SERVICES_DIR/$service_name"
    fi
    
    echo ""
    echo -e "${CYAN}----------------------------------------${NC}"
    echo -e "${CYAN} Verifying: $service_name ($service_type)${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    
    # Verify structure
    if ! verify_service_structure "$service_type" "$service_name" "$service_dir"; then
        return 1
    fi
    
    # Test language-specific build
    if [ "$service_type" = "go" ]; then
        test_go_build "$service_name" "$service_dir"
    else
        test_python_setup "$service_name" "$service_dir"
    fi
    
    # Test Docker build
    test_docker_build "$service_name" "$service_dir"
    
    cd "$PROJECT_ROOT"
}

# Generate summary report
generate_summary() {
    echo ""
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}            VERIFICATION SUMMARY${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo ""
    
    echo -e "${BLUE}Total Services Checked:${NC} $TOTAL_SERVICES"
    echo -e "${GREEN}Successful Builds:${NC} $SUCCESSFUL_BUILDS"
    echo -e "${RED}Failed Builds:${NC} $FAILED_BUILDS"
    echo -e "${YELLOW}Missing Services:${NC} $MISSING_SERVICES"
    echo ""
    
    local success_rate=$(( (SUCCESSFUL_BUILDS * 100) / TOTAL_SERVICES ))
    
    if [ $success_rate -eq 100 ]; then
        echo -e "${GREEN}🎉 All services verified successfully!${NC}"
    elif [ $success_rate -ge 80 ]; then
        echo -e "${YELLOW}⚠️  Most services verified ($success_rate% success rate)${NC}"
    else
        echo -e "${RED}❌ Many services need attention ($success_rate% success rate)${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    if [ $FAILED_BUILDS -gt 0 ]; then
        echo -e "  1. Fix failed builds by checking Docker logs"
        echo -e "  2. Run: ${CYAN}./fix-go-dependencies.sh${NC} for Go services"
        echo -e "  3. Verify Python requirements for Python services"
    fi
    if [ $MISSING_SERVICES -gt 0 ]; then
        echo -e "  4. Generate missing services with: ${CYAN}./generate-all-microservices.sh${NC}"
    fi
    echo -e "  5. Update docker-compose.yml to include all services"
    echo -e "  6. Start services with: ${CYAN}docker-compose up${NC}"
    echo ""
}

# Main execution
main() {
    log_info "Starting verification of all PyAirtable microservices"
    echo ""
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Verify Go services
    log_info "Verifying Go microservices..."
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r name port <<< "$service_info"
        verify_single_service "go" "$name" "$port"
    done
    
    # Verify Python services
    log_info "Verifying Python microservices..."
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r name port <<< "$service_info"
        verify_single_service "python" "$name" "$port"
    done
    
    # Generate summary
    generate_summary
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root directory"
    exit 1
fi

# Execute main function
main "$@"