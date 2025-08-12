#!/bin/bash

# Test all 22 microservices health endpoints

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

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

# Test function
test_service() {
    local service_name=$1
    local port=$2
    local service_type=$3
    
    printf "%-20s %-10s " "$service_name" "($port)"
    
    if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Testing All PyAirtable Services${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    
    local total_services=0
    local healthy_services=0
    
    echo -e "${YELLOW}Go Services:${NC}"
    echo "------------------------------------"
    for service_info in "${GO_SERVICES[@]}"; do
        IFS=':' read -r name port <<< "$service_info"
        ((total_services++))
        if test_service "$name" "$port" "go"; then
            ((healthy_services++))
        fi
    done
    
    echo ""
    echo -e "${YELLOW}Python Services:${NC}"
    echo "------------------------------------"
    for service_info in "${PYTHON_SERVICES[@]}"; do
        IFS=':' read -r name port <<< "$service_info"
        ((total_services++))
        if test_service "$name" "$port" "python"; then
            ((healthy_services++))
        fi
    done
    
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Summary:${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "Total Services: $total_services"
    echo -e "Healthy Services: ${GREEN}$healthy_services${NC}"
    echo -e "Failed Services: ${RED}$((total_services - healthy_services))${NC}"
    
    if [ $healthy_services -eq $total_services ]; then
        echo -e "\n${GREEN}🎉 All services are healthy!${NC}"
    else
        echo -e "\n${YELLOW}⚠️  Some services need attention${NC}"
    fi
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Execute main
main "$@"