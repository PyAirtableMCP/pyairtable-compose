#!/bin/bash

# Final Service Status Report
# Provides comprehensive status of all 22 microservices

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

# Service definitions with expected status
GO_SERVICES=(
    "api-gateway:8080:Generated from template"
    "auth-service:8081:Fixed structure, ready"
    "user-service:8082:Generated from template"
    "tenant-service:8083:Generated from template"
    "workspace-service:8084:Generated from template"
    "permission-service:8085:Generated from template"
    "webhook-service:8086:Generated from template"
    "notification-service:8087:Generated from template"
    "file-service:8088:Generated from template"
    "web-bff:8089:Generated from template"
    "mobile-bff:8090:Generated from template"
)

PYTHON_SERVICES=(
    "llm-orchestrator:8091:Generated with FastAPI"
    "mcp-server:8092:Generated with FastAPI"
    "airtable-gateway:8093:Generated with FastAPI"
    "schema-service:8094:Generated with FastAPI"
    "formula-engine:8095:Generated with FastAPI"
    "embedding-service:8096:Generated with FastAPI"
    "semantic-search:8097:Generated with FastAPI"
    "chat-service:8098:Generated with FastAPI"
    "workflow-engine:8099:Generated with FastAPI"
    "analytics-service:8100:Generated with FastAPI"
    "audit-service:8101:Generated with FastAPI"
)

# Tracking variables
TOTAL_SERVICES=0
READY_SERVICES=0
INCOMPLETE_SERVICES=0

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

# Check service completeness
check_service_status() {
    local service_type="$1"
    local service_name="$2"
    local port="$3"
    local description="$4"
    
    ((TOTAL_SERVICES++))
    
    local service_dir=""
    if [ "$service_type" = "go" ]; then
        service_dir="$GO_SERVICES_DIR/$service_name"
    else
        service_dir="$PYTHON_SERVICES_DIR/$service_name"
    fi
    
    local status="❌ MISSING"
    local issues=()
    
    if [ -d "$service_dir" ]; then
        status="✅ READY"
        ((READY_SERVICES++))
        
        # Check Go service structure
        if [ "$service_type" = "go" ]; then
            [ ! -f "$service_dir/go.mod" ] && issues+=("Missing go.mod")
            [ ! -f "$service_dir/Dockerfile" ] && issues+=("Missing Dockerfile")
            [ ! -d "$service_dir/cmd/$service_name" ] && issues+=("Missing cmd directory")
            [ ! -f "$service_dir/cmd/$service_name/main.go" ] && issues+=("Missing main.go")
        else
            # Check Python service structure
            [ ! -f "$service_dir/requirements.txt" ] && issues+=("Missing requirements.txt")
            [ ! -f "$service_dir/Dockerfile" ] && issues+=("Missing Dockerfile")
            [ ! -f "$service_dir/src/main.py" ] && issues+=("Missing src/main.py")
            [ ! -d "$service_dir/src/routes" ] && issues+=("Missing routes directory")
        fi
        
        if [ ${#issues[@]} -gt 0 ]; then
            status="⚠️  INCOMPLETE"
            ((READY_SERVICES--))
            ((INCOMPLETE_SERVICES++))
        fi
    else
        ((INCOMPLETE_SERVICES++))
    fi
    
    # Print service status
    printf "%-20s %-8s %-15s %s\n" "$service_name" "$port" "$status" "$description"
    
    # Print issues if any
    for issue in "${issues[@]}"; do
        echo -e "    ${RED}→ $issue${NC}"
    done
}

# Test Docker build capability
test_build_capability() {
    local service_type="$1"
    local service_name="$2"
    
    local service_dir=""
    if [ "$service_type" = "go" ]; then
        service_dir="$GO_SERVICES_DIR/$service_name"
    else
        service_dir="$PYTHON_SERVICES_DIR/$service_name"
    fi
    
    if [ ! -d "$service_dir" ]; then
        echo "❌ MISSING"
        return
    fi
    
    cd "$service_dir"
    
    # Quick Docker build test (dry run)
    if docker build --dry-run -t "$service_name:test" . >/dev/null 2>&1; then
        echo "✅ CAN BUILD"
    else
        echo "⚠️  BUILD ISSUES"
    fi
    
    cd "$PROJECT_ROOT"
}

# Main execution
main() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}           PyAirtable Microservices Status Report${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    
    echo -e "${YELLOW}Go Microservices (11 services):${NC}"
    echo ""
    printf "%-20s %-8s %-15s %s\n" "SERVICE" "PORT" "STATUS" "DESCRIPTION"
    echo "--------------------------------------------------------------------"
    
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        check_service_status "go" "$name" "$port" "$desc"
    done
    
    echo ""
    echo -e "${YELLOW}Python Microservices (11 services):${NC}"
    echo ""
    printf "%-20s %-8s %-15s %s\n" "SERVICE" "PORT" "STATUS" "DESCRIPTION"
    echo "--------------------------------------------------------------------"
    
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r name port desc <<< "$service_info"
        check_service_status "python" "$name" "$port" "$desc"
    done
    
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}                         SUMMARY${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo ""
    
    echo -e "${BLUE}Total Services:${NC} $TOTAL_SERVICES"
    echo -e "${GREEN}Ready Services:${NC} $READY_SERVICES"
    echo -e "${YELLOW}Incomplete Services:${NC} $INCOMPLETE_SERVICES"
    echo ""
    
    local completion_rate=$(( (READY_SERVICES * 100) / TOTAL_SERVICES ))
    
    echo -e "${BLUE}Completion Rate:${NC} ${completion_rate}%"
    echo ""
    
    if [ $completion_rate -eq 100 ]; then
        echo -e "${GREEN}🎉 ALL SERVICES READY!${NC}"
        echo -e "${GREEN}All 22 microservices have been successfully generated.${NC}"
    elif [ $completion_rate -ge 90 ]; then
        echo -e "${YELLOW}🔧 NEARLY COMPLETE!${NC}"
        echo -e "${YELLOW}Most services are ready. Minor fixes needed.${NC}"
    else
        echo -e "${RED}⚠️  WORK REMAINING${NC}"
        echo -e "${RED}Several services need attention.${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}File Structure Summary:${NC}"
    echo -e "  📁 go-services/        - Go microservices (Fiber framework)"
    echo -e "  📁 python-services/    - Python microservices (FastAPI framework)"
    echo -e "  📁 pyairtable-infrastructure/ - Shared libraries & templates"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. ${CYAN}docker-compose up${NC} - Start all services"
    echo -e "  2. Test health endpoints for each service"
    echo -e "  3. Configure inter-service communication"
    echo -e "  4. Set up API Gateway routing"
    echo -e "  5. Configure monitoring and logging"
    echo ""
    
    echo -e "${BLUE}Port Allocation:${NC}"
    echo -e "  Go Services:     8080-8090"
    echo -e "  Python Services: 8091-8101"
    echo ""
    
    if [ $INCOMPLETE_SERVICES -gt 0 ]; then
        echo -e "${YELLOW}To fix incomplete services:${NC}"
        echo -e "  Run: ${CYAN}./fix-go-dependencies.sh${NC}"
        echo -e "  Check individual service directories for missing files"
    fi
    
    echo ""
}

# Check if running from correct directory
if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
    log_error "Please run this script from the pyairtable-compose project root directory"
    exit 1
fi

# Execute main function
main "$@"