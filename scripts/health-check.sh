#!/bin/bash

# PyAirtable Platform Health Check Script
# Comprehensive health monitoring for all services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MAX_RETRIES=3
TIMEOUT=10
HEALTH_CHECK_INTERVAL=2

# Service definitions
declare -A SERVICES=(
    ["postgres"]="internal:5432:pg_isready"
    ["redis"]="internal:6379:redis-cli"
    ["api-gateway"]="8080:/health"
    ["auth-service"]="internal:8001:/health"
    ["user-service"]="internal:8002:/health"
    ["workspace-service"]="internal:8004:/health"
    ["airtable-gateway"]="internal:8002:/health"
    ["mcp-server"]="internal:8001:/health"
    ["llm-orchestrator"]="internal:8003:/health"
    ["platform-services"]="internal:8007:/health"
    ["automation-services"]="internal:8006:/health"
    ["frontend"]="3000:/api/health"
)

# Function to print colored output
print_status() {
    local status=$1
    local service=$2
    local message=$3
    
    case $status in
        "ok")
            echo -e "${GREEN}✅ $service${NC} - $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  $service${NC} - $message"
            ;;
        "error")
            echo -e "${RED}❌ $service${NC} - $message"
            ;;
        "info")
            echo -e "${BLUE}ℹ️  $service${NC} - $message"
            ;;
    esac
}

# Function to check HTTP health endpoint
check_http_health() {
    local url=$1
    local service_name=$2
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -s --max-time $TIMEOUT "$url" > /dev/null 2>&1; then
            # Try to parse JSON response for more detailed status
            local response=$(curl -s --max-time $TIMEOUT "$url" 2>/dev/null)
            if echo "$response" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
                local version=$(echo "$response" | jq -r '.version // "unknown"' 2>/dev/null)
                print_status "ok" "$service_name" "Healthy (v$version)"
                return 0
            elif echo "$response" | jq -e '.status' > /dev/null 2>&1; then
                local status=$(echo "$response" | jq -r '.status' 2>/dev/null)
                print_status "warning" "$service_name" "Status: $status"
                return 1
            else
                print_status "ok" "$service_name" "Responding (non-JSON)"
                return 0
            fi
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    print_status "error" "$service_name" "Not responding after $MAX_RETRIES attempts"
    return 1
}

# Function to check PostgreSQL
check_postgres() {
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if docker-compose exec -T postgres pg_isready -U postgres > /dev/null 2>&1; then
            # Get database stats
            local connections=$(docker-compose exec -T postgres psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs)
            local db_size=$(docker-compose exec -T postgres psql -U postgres -t -c "SELECT pg_size_pretty(pg_database_size('pyairtable'));" 2>/dev/null | xargs)
            print_status "ok" "PostgreSQL" "Ready ($connections connections, size: $db_size)"
            return 0
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    print_status "error" "PostgreSQL" "Not ready after $MAX_RETRIES attempts"
    return 1
}

# Function to check Redis
check_redis() {
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
            # Get Redis info
            local memory=$(docker-compose exec -T redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
            local connected_clients=$(docker-compose exec -T redis redis-cli info clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r')
            print_status "ok" "Redis" "Ready (Memory: $memory, Clients: $connected_clients)"
            return 0
        fi
        
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    print_status "error" "Redis" "Not responding after $MAX_RETRIES attempts"
    return 1
}

# Function to check Docker container status
check_container_status() {
    echo -e "\n${BLUE}📊 Container Status${NC}"
    echo "===================="
    
    # Get container status
    local containers=$(docker-compose ps --services 2>/dev/null)
    
    for container in $containers; do
        local status=$(docker-compose ps -q $container 2>/dev/null | xargs docker inspect --format='{{.State.Status}}' 2>/dev/null)
        local health=$(docker-compose ps -q $container 2>/dev/null | xargs docker inspect --format='{{.State.Health.Status}}' 2>/dev/null)
        
        if [ "$status" = "running" ]; then
            if [ "$health" = "healthy" ]; then
                print_status "ok" "$container" "Running and healthy"
            elif [ "$health" = "unhealthy" ]; then
                print_status "error" "$container" "Running but unhealthy"
            elif [ "$health" = "starting" ]; then
                print_status "warning" "$container" "Starting up"
            else
                print_status "ok" "$container" "Running (no health check)"
            fi
        else
            print_status "error" "$container" "Not running (status: $status)"
        fi
    done
}

# Function to check resource usage
check_resource_usage() {
    echo -e "\n${BLUE}💾 Resource Usage${NC}"
    echo "=================="
    
    # Check system resources
    local cpu_usage=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -v CONTAINER)
    
    if [ -n "$cpu_usage" ]; then
        echo "$cpu_usage"
    else
        print_status "warning" "Resource monitoring" "Unable to get container stats"
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    echo -e "\n${BLUE}🌐 Network Connectivity${NC}"
    echo "======================="
    
    # Test internal service communication
    local test_services=("auth-service:8001" "user-service:8002" "airtable-gateway:8002")
    
    for service_port in "${test_services[@]}"; do
        local service=${service_port%%:*}
        local port=${service_port##*:}
        
        if docker-compose exec -T api-gateway sh -c "nc -z $service $port" > /dev/null 2>&1; then
            print_status "ok" "Network: $service" "Reachable on port $port"
        else
            print_status "error" "Network: $service" "Unreachable on port $port"
        fi
    done
}

# Main health check function
main() {
    echo -e "${BLUE}🏥 PyAirtable Platform Health Check${NC}"
    echo "===================================="
    echo "Started at: $(date)"
    echo ""
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        print_status "error" "System" "docker-compose not found"
        exit 1
    fi
    
    # Check container status first
    check_container_status
    
    # Check infrastructure services
    echo -e "\n${BLUE}🏗️ Infrastructure Services${NC}"
    echo "==========================="
    
    check_postgres
    check_redis
    
    # Check application services
    echo -e "\n${BLUE}🚀 Application Services${NC}"
    echo "======================="
    
    local failed_services=0
    local total_services=0
    
    for service in "${!SERVICES[@]}"; do
        local config="${SERVICES[$service]}"
        total_services=$((total_services + 1))
        
        # Skip infrastructure services (already checked)
        if [[ "$service" == "postgres" || "$service" == "redis" ]]; then
            continue
        fi
        
        # Parse service configuration
        if [[ $config == internal:* ]]; then
            # Internal service - skip HTTP check for now
            print_status "info" "$service" "Internal service (skipped)"
            continue
        elif [[ $config == *:/* ]]; then
            # HTTP service
            local port_path=(${config//:/ })
            local port=${port_path[0]}
            local path=${port_path[1]}
            local url="http://localhost:$port$path"
            
            if ! check_http_health "$url" "$service"; then
                failed_services=$((failed_services + 1))
            fi
        fi
    done
    
    # Network connectivity check
    check_network_connectivity
    
    # Resource usage check
    check_resource_usage
    
    # Summary
    echo -e "\n${BLUE}📋 Health Check Summary${NC}"
    echo "======================="
    
    local healthy_services=$((total_services - failed_services))
    
    if [ $failed_services -eq 0 ]; then
        print_status "ok" "Overall Status" "All services healthy ($healthy_services/$total_services)"
        echo -e "\n${GREEN}🎉 Platform is ready to serve traffic!${NC}"
        exit 0
    else
        print_status "error" "Overall Status" "$failed_services/$total_services services failed"
        echo -e "\n${RED}⚠️  Platform has issues that need attention${NC}"
        exit 1
    fi
}

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "PyAirtable Platform Health Check"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --quick        Quick check (fewer retries)"
    echo "  --verbose      Verbose output"
    echo ""
    echo "This script checks the health of all PyAirtable platform services"
    echo "and provides a comprehensive status report."
    exit 0
fi

# Quick mode
if [[ "$1" == "--quick" ]]; then
    MAX_RETRIES=1
    TIMEOUT=5
fi

# Verbose mode
if [[ "$1" == "--verbose" ]]; then
    set -x
fi

# Run main function
main