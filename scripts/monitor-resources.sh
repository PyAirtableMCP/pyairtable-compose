#!/bin/bash

# Resource monitoring script for PyAirtable local development
# Optimized for MacBook Air M2

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}$1${NC}"
    echo "$(printf '=%.0s' {1..60})"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# System resources
show_system_resources() {
    print_header "SYSTEM RESOURCES"
    
    # Memory usage
    echo "Memory Usage:"
    vm_stat | awk '
    /Pages free/ { free = $3 * 4096 / 1024 / 1024 / 1024 }
    /Pages active/ { active = $3 * 4096 / 1024 / 1024 / 1024 }
    /Pages inactive/ { inactive = $3 * 4096 / 1024 / 1024 / 1024 }
    /Pages wired/ { wired = $3 * 4096 / 1024 / 1024 / 1024 }
    END {
        total = free + active + inactive + wired
        used = active + inactive + wired
        printf "  Total: %.1fGB\n", total
        printf "  Used:  %.1fGB (%.1f%%)\n", used, (used/total)*100
        printf "  Free:  %.1fGB (%.1f%%)\n", free, (free/total)*100
    }'
    
    echo
    echo "CPU Usage:"
    top -l 1 -n 0 | grep "CPU usage" | awk '{print "  " $0}'
    
    echo
    echo "Disk Usage:"
    df -h / | tail -1 | awk '{print "  Used: " $3 " / " $2 " (" $5 ")"}'
    
    echo
}

# Docker resources
show_docker_resources() {
    print_header "DOCKER RESOURCES"
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        return 1
    fi
    
    echo "Docker System Info:"
    docker system info --format "  Memory: {{.MemTotal | printf \"%.1fGB\"}}"
    docker system info --format "  CPUs: {{.NCPU}}"
    docker system info --format "  Storage Driver: {{.Driver}}"
    
    echo
    echo "Docker System Usage:"
    docker system df
    
    echo
}

# Container resources
show_container_resources() {
    print_header "CONTAINER RESOURCES"
    
    if ! docker ps -q >/dev/null 2>&1; then
        echo "No containers running"
        return 0
    fi
    
    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
    
    echo
    echo "Memory Usage by Service:"
    docker stats --no-stream --format "{{.Name}} {{.MemUsage}}" | sort -k2 -hr | while read name mem; do
        echo "  $name: $mem"
    done
    
    echo
}

# Service health
show_service_health() {
    print_header "SERVICE HEALTH"
    
    services=(
        "pyairtable-api:8000:/health"
        "pyairtable-frontend:3000:/"
        "grafana:3000:/api/health"
        "prometheus:9090:/-/healthy"
        "loki:3100:/ready"
        "tempo:3200:/ready"
        "mimir:9009:/ready"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service port path <<< "$service_info"
        
        if docker ps --filter "name=$service" --format "{{.Names}}" | grep -q "$service"; then
            if curl -s -f "http://localhost:$port$path" >/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} $service - Healthy"
            else
                echo -e "  ${YELLOW}?${NC} $service - May not be ready"
            fi
        else
            echo -e "  ${RED}✗${NC} $service - Not running"
        fi
    done
    
    echo
}

# Database connections
show_database_status() {
    print_header "DATABASE STATUS"
    
    # PostgreSQL
    if docker ps --filter "name=postgres" --format "{{.Names}}" | grep -q "postgres"; then
        if docker exec postgres pg_isready -U postgres >/dev/null 2>&1; then
            connections=$(docker exec postgres psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
            echo -e "  ${GREEN}✓${NC} PostgreSQL - $connections active connections"
            
            # Show database size
            db_size=$(docker exec postgres psql -U postgres -t -c "SELECT pg_size_pretty(pg_database_size('pyairtable'));" 2>/dev/null | tr -d ' ')
            echo "    Database size: $db_size"
        else
            echo -e "  ${RED}✗${NC} PostgreSQL - Not ready"
        fi
    else
        echo -e "  ${RED}✗${NC} PostgreSQL - Not running"
    fi
    
    # Redis
    if docker ps --filter "name=redis" --format "{{.Names}}" | grep -q "redis"; then
        if docker exec redis redis-cli ping >/dev/null 2>&1; then
            connections=$(docker exec redis redis-cli info clients | grep "connected_clients" | cut -d: -f2 | tr -d '\r')
            memory=$(docker exec redis redis-cli info memory | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
            echo -e "  ${GREEN}✓${NC} Redis - $connections connections, $memory memory used"
        else
            echo -e "  ${RED}✗${NC} Redis - Not ready"
        fi
    else
        echo -e "  ${RED}✗${NC} Redis - Not running"
    fi
    
    echo
}

# Recommendations
show_recommendations() {
    print_header "RECOMMENDATIONS"
    
    # Check total memory usage
    total_mem=$(docker stats --no-stream --format "{{.MemUsage}}" | awk -F'/' '{sum += $1} END {print sum}' 2>/dev/null || echo "0")
    
    if [ "$total_mem" -gt 6000 ]; then  # 6GB in MB
        print_warning "High memory usage detected. Consider:"
        echo "  - Reducing resource limits in docker-compose.local.yml"
        echo "  - Stopping unused services"
        echo "  - Increasing Docker Desktop memory allocation"
    fi
    
    # Check for unhealthy services
    unhealthy=$(docker ps --filter "health=unhealthy" -q | wc -l | tr -d ' ')
    if [ "$unhealthy" -gt 0 ]; then
        print_warning "$unhealthy unhealthy containers detected"
        echo "  - Check container logs: docker-compose logs [service-name]"
        echo "  - Restart unhealthy services: docker-compose restart [service-name]"
    fi
    
    # Check disk space
    disk_usage=$(df / | tail -1 | awk '{print $(NF-1)}' | sed 's/%//')
    if [ "$disk_usage" -gt 80 ]; then
        print_warning "Disk usage is high ($disk_usage%)"
        echo "  - Clean Docker: docker system prune -a"
        echo "  - Remove old volumes: docker volume prune"
    fi
    
    echo
}

# Logs summary
show_recent_errors() {
    print_header "RECENT ERRORS (Last 10 minutes)"
    
    services=$(docker-compose -f docker-compose.local.yml ps --services 2>/dev/null || echo "")
    
    if [ -n "$services" ]; then
        for service in $services; do
            error_count=$(docker-compose -f docker-compose.local.yml logs --since=10m "$service" 2>/dev/null | grep -i error | wc -l | tr -d ' ')
            if [ "$error_count" -gt 0 ]; then
                echo -e "  ${YELLOW}!${NC} $service: $error_count errors"
            fi
        done
    fi
    
    echo
}

# Main function
main() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           PyAirtable Resource Monitor          ║"
    echo "║             $(date '+%Y-%m-%d %H:%M:%S')              ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    show_system_resources
    show_docker_resources
    show_container_resources
    show_service_health
    show_database_status
    show_recent_errors
    show_recommendations
    
    echo -e "${GREEN}Resource monitoring complete!${NC}"
    echo
    echo "Commands:"
    echo "  - Refresh: $0"
    echo "  - Continuous monitoring: watch -n 30 $0"
    echo "  - Service logs: docker-compose -f docker-compose.local.yml logs -f [service]"
}

# Handle arguments
case "${1:-}" in
    "watch")
        watch -n 30 "$0"
        ;;
    "continuous")
        while true; do
            main
            sleep 30
        done
        ;;
    *)
        main
        ;;
esac