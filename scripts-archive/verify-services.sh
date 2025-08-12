#!/bin/bash

# Verify All Services Script
# Comprehensive verification of all 22 microservices

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

PROJECT_ROOT="/Users/kg/IdeaProjects/pyairtable-compose"
GO_SERVICES_DIR="$PROJECT_ROOT/go-services"
PYTHON_SERVICES_DIR="$PROJECT_ROOT/python-services"

# Counters
TOTAL_SERVICES=0
SERVICES_EXIST=0
SERVICES_BUILDABLE=0
SERVICES_WITH_DOCKER=0

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

# Check Go service
check_go_service() {
    local service_name=$1
    local port=$2
    local service_dir="$GO_SERVICES_DIR/$service_name"
    
    ((TOTAL_SERVICES++))
    
    echo -e "\n${PURPLE}Checking Go Service: $service_name (port $port)${NC}"
    
    # Check if directory exists
    if [ ! -d "$service_dir" ]; then
        log_error "❌ Directory not found"
        return
    fi
    ((SERVICES_EXIST++))
    
    # Check required files
    local missing_files=()
    [ ! -f "$service_dir/go.mod" ] && missing_files+=("go.mod")
    [ ! -f "$service_dir/Dockerfile" ] && missing_files+=("Dockerfile")
    [ ! -f "$service_dir/cmd/$service_name/main.go" ] && missing_files+=("main.go")
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        log_success "✅ All required files present"
    else
        log_warning "⚠️  Missing files: ${missing_files[*]}"
    fi
    
    # Try to build
    if [ -f "$service_dir/go.mod" ]; then
        cd "$service_dir"
        if go build -o /dev/null ./cmd/$service_name 2>/dev/null; then
            log_success "✅ Build successful"
            ((SERVICES_BUILDABLE++))
        else
            log_error "❌ Build failed"
        fi
        cd "$PROJECT_ROOT"
    fi
    
    # Check Dockerfile
    if [ -f "$service_dir/Dockerfile" ]; then
        log_success "✅ Dockerfile exists"
        ((SERVICES_WITH_DOCKER++))
    fi
}

# Check Python service
check_python_service() {
    local service_name=$1
    local port=$2
    local service_dir="$PYTHON_SERVICES_DIR/$service_name"
    
    ((TOTAL_SERVICES++))
    
    echo -e "\n${PURPLE}Checking Python Service: $service_name (port $port)${NC}"
    
    # Check if directory exists
    if [ ! -d "$service_dir" ]; then
        log_error "❌ Directory not found"
        return
    fi
    ((SERVICES_EXIST++))
    
    # Check required files
    local missing_files=()
    [ ! -f "$service_dir/requirements.txt" ] && missing_files+=("requirements.txt")
    [ ! -f "$service_dir/Dockerfile" ] && missing_files+=("Dockerfile")
    [ ! -f "$service_dir/src/main.py" ] && missing_files+=("src/main.py")
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        log_success "✅ All required files present"
        ((SERVICES_BUILDABLE++))
    else
        log_warning "⚠️  Missing files: ${missing_files[*]}"
    fi
    
    # Check Dockerfile
    if [ -f "$service_dir/Dockerfile" ]; then
        log_success "✅ Dockerfile exists"
        ((SERVICES_WITH_DOCKER++))
    fi
}

# Main execution
main() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}PyAirtable Services Verification${NC}"
    echo -e "${BLUE}=====================================${NC}"
    
    # Check Go services
    echo -e "\n${YELLOW}=== Go Services (11) ===${NC}"
    check_go_service "api-gateway" "8080"
    check_go_service "auth-service" "8081"
    check_go_service "user-service" "8082"
    check_go_service "tenant-service" "8083"
    check_go_service "workspace-service" "8084"
    check_go_service "permission-service" "8085"
    check_go_service "webhook-service" "8086"
    check_go_service "notification-service" "8087"
    check_go_service "file-service" "8088"
    check_go_service "web-bff" "8089"
    check_go_service "mobile-bff" "8090"
    
    # Check Python services
    echo -e "\n${YELLOW}=== Python Services (11) ===${NC}"
    check_python_service "llm-orchestrator" "8091"
    check_python_service "mcp-server" "8092"
    check_python_service "airtable-gateway" "8093"
    check_python_service "schema-service" "8094"
    check_python_service "formula-engine" "8095"
    check_python_service "embedding-service" "8096"
    check_python_service "semantic-search" "8097"
    check_python_service "chat-service" "8098"
    check_python_service "workflow-engine" "8099"
    check_python_service "analytics-service" "8100"
    check_python_service "audit-service" "8101"
    
    # Summary
    echo -e "\n${BLUE}=====================================${NC}"
    echo -e "${BLUE}VERIFICATION SUMMARY${NC}"
    echo -e "${BLUE}=====================================${NC}"
    
    echo -e "${BLUE}Total Services:${NC} $TOTAL_SERVICES"
    echo -e "${GREEN}Services Exist:${NC} $SERVICES_EXIST"
    echo -e "${GREEN}Services Buildable:${NC} $SERVICES_BUILDABLE"
    echo -e "${GREEN}Services with Docker:${NC} $SERVICES_WITH_DOCKER"
    
    local completion_rate=$(( (SERVICES_EXIST * 100) / TOTAL_SERVICES ))
    echo -e "\n${BLUE}Completion Rate:${NC} ${completion_rate}%"
    
    if [ $SERVICES_EXIST -eq $TOTAL_SERVICES ]; then
        echo -e "\n${GREEN}🎉 ALL SERVICES CREATED!${NC}"
    else
        local missing=$(( TOTAL_SERVICES - SERVICES_EXIST ))
        echo -e "\n${YELLOW}⚠️  $missing services need to be created${NC}"
    fi
    
    echo -e "\n${BLUE}Directory Structure:${NC}"
    echo "📁 $GO_SERVICES_DIR/"
    ls -la "$GO_SERVICES_DIR" 2>/dev/null | grep "^d" | awk '{print "  └── " $9}' | grep -v "^\s*└──\s*$"
    
    echo "📁 $PYTHON_SERVICES_DIR/"
    ls -la "$PYTHON_SERVICES_DIR" 2>/dev/null | grep "^d" | awk '{print "  └── " $9}' | grep -v "^\s*└──\s*$"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    if [ $SERVICES_EXIST -lt $TOTAL_SERVICES ]; then
        echo "1. Run: ./create-all-services.sh"
    fi
    if [ $SERVICES_BUILDABLE -lt $SERVICES_EXIST ]; then
        echo "2. Run: ./fix-all-go-deps.sh"
    fi
    echo "3. Create docker-compose configuration"
    echo "4. Start services: docker-compose up -d"
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root"
    exit 1
fi

# Execute main
main "$@"