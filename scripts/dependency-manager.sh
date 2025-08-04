#!/bin/bash

# PyAirtable Service Dependency Manager
# Manages service startup order, health checks, and dependencies
# Author: Claude Deployment Engineer

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly NAMESPACE="${NAMESPACE:-pyairtable}"
readonly TIMEOUT_SERVICE_READY="${TIMEOUT_SERVICE_READY:-300}"
readonly TIMEOUT_HEALTH_CHECK="${TIMEOUT_HEALTH_CHECK:-30}"
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-5}"
readonly MAX_HEALTH_RETRIES="${MAX_HEALTH_RETRIES:-6}"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Service dependency graph
declare -A SERVICE_DEPENDENCIES=(
    ["postgres"]=""
    ["redis"]=""
    ["airtable-gateway"]="postgres redis"
    ["mcp-server"]="airtable-gateway"
    ["llm-orchestrator"]="mcp-server redis"
    ["platform-services"]="postgres redis"
    ["automation-services"]="postgres redis mcp-server platform-services"
    ["api-gateway"]="airtable-gateway mcp-server llm-orchestrator platform-services automation-services"
    ["frontend"]="api-gateway"
)

declare -A SERVICE_HEALTH_ENDPOINTS=(
    ["postgres"]="exec:pg_isready -U admin -d pyairtablemcp"
    ["redis"]="exec:redis-cli -a \$REDIS_PASSWORD ping"
    ["airtable-gateway"]="http:8002/health"
    ["mcp-server"]="http:8001/health"
    ["llm-orchestrator"]="http:8003/health"
    ["platform-services"]="http:8007/health"
    ["automation-services"]="http:8006/health"
    ["api-gateway"]="http:8000/health"
    ["frontend"]="http:3000/api/health"
)

declare -A SERVICE_CRITICAL_LEVEL=(
    ["postgres"]="critical"
    ["redis"]="critical"
    ["airtable-gateway"]="high"
    ["mcp-server"]="high"
    ["llm-orchestrator"]="high"
    ["platform-services"]="high"
    ["automation-services"]="medium"
    ["api-gateway"]="critical"
    ["frontend"]="low"
)

# Logging functions
log() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $*"
}

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

log_section() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}  $*${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Check if service exists
service_exists() {
    local service="$1"
    kubectl get deployment "$service" -n "$NAMESPACE" &>/dev/null
}

# Check if service is ready (deployment available)
service_deployment_ready() {
    local service="$1"
    local condition
    condition=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    [[ "$condition" == "True" ]]
}

# Check service health using appropriate method
check_service_health() {
    local service="$1"
    local health_check="${SERVICE_HEALTH_ENDPOINTS[$service]:-}"
    
    if [[ -z "$health_check" ]]; then
        log_warning "No health check defined for $service"
        return 1
    fi
    
    local method="${health_check%%:*}"
    local endpoint="${health_check#*:}"
    
    case "$method" in
        "http")
            # HTTP health check
            local url="http://$service.$NAMESPACE.svc.cluster.local:$endpoint"
            kubectl run "health-check-$service-$$" \
                --namespace="$NAMESPACE" \
                --image=curlimages/curl:latest \
                --rm --restart=Never \
                --timeout="$TIMEOUT_HEALTH_CHECK" \
                --command -- curl -sf "$url" &>/dev/null
            ;;
        "exec")
            # Execute command in pod
            local pod
            pod=$(kubectl get pods -n "$NAMESPACE" -l "app=$service" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            if [[ -n "$pod" ]]; then
                kubectl exec -n "$NAMESPACE" "$pod" -- sh -c "$endpoint" &>/dev/null
            else
                return 1
            fi
            ;;
        *)
            log_error "Unknown health check method: $method"
            return 1
            ;;
    esac
}

# Wait for service to be ready
wait_for_service() {
    local service="$1"
    local timeout="${2:-$TIMEOUT_SERVICE_READY}"
    
    log_info "Waiting for $service to be ready..."
    
    # First wait for deployment to be available
    if ! kubectl wait --namespace="$NAMESPACE" \
                     --for=condition=available \
                     "deployment/$service" \
                     --timeout="${timeout}s" &>/dev/null; then
        log_error "$service deployment failed to become available within ${timeout}s"
        return 1
    fi
    
    # Then perform health checks
    local retries=0
    while [[ $retries -lt $MAX_HEALTH_RETRIES ]]; do
        if check_service_health "$service"; then
            log_success "$service is healthy"
            return 0
        fi
        
        retries=$((retries + 1))
        log_info "Health check $retries/$MAX_HEALTH_RETRIES failed for $service, retrying in ${HEALTH_CHECK_INTERVAL}s..."
        sleep "$HEALTH_CHECK_INTERVAL"
    done
    
    log_error "$service failed health checks after $MAX_HEALTH_RETRIES attempts"
    return 1
}

# Get all dependencies for a service (recursive)
get_all_dependencies() {
    local service="$1"
    local -A visited
    local dependencies=()
    
    _get_dependencies_recursive() {
        local svc="$1"
        local deps="${SERVICE_DEPENDENCIES[$svc]:-}"
        
        if [[ -n "$deps" ]]; then
            for dep in $deps; do
                if [[ -z "${visited[$dep]:-}" ]]; then
                    visited["$dep"]=1
                    _get_dependencies_recursive "$dep"
                    dependencies+=("$dep")
                fi
            done
        fi
    }
    
    _get_dependencies_recursive "$service"
    printf '%s\n' "${dependencies[@]}" | sort -u
}

# Generate deployment order based on dependencies
get_deployment_order() {
    local services=("$@")
    local -A in_degree
    local -A adjacency
    local queue=()
    local result=()
    
    # Initialize in-degree and adjacency list
    for service in "${services[@]}"; do
        in_degree["$service"]=0
        adjacency["$service"]=""
    done
    
    # Build adjacency list and calculate in-degrees
    for service in "${services[@]}"; do
        local deps="${SERVICE_DEPENDENCIES[$service]:-}"
        if [[ -n "$deps" ]]; then
            for dep in $deps; do
                if [[ -n "${in_degree[$dep]+x}" ]]; then
                    adjacency["$dep"]+=" $service"
                    in_degree["$service"]=$((in_degree["$service"] + 1))
                fi
            done
        fi
    done
    
    # Find services with no dependencies
    for service in "${services[@]}"; do
        if [[ ${in_degree["$service"]} -eq 0 ]]; then
            queue+=("$service")
        fi
    done
    
    # Topological sort
    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        result+=("$current")
        
        local neighbors="${adjacency[$current]}"
        if [[ -n "$neighbors" ]]; then
            for neighbor in $neighbors; do
                in_degree["$neighbor"]=$((in_degree["$neighbor"] - 1))
                if [[ ${in_degree["$neighbor"]} -eq 0 ]]; then
                    queue+=("$neighbor")
                fi
            done
        fi
    done
    
    # Check for cycles
    if [[ ${#result[@]} -ne ${#services[@]} ]]; then
        log_error "Circular dependency detected in services"
        return 1
    fi
    
    printf '%s\n' "${result[@]}"
}

# Start services in dependency order
start_services() {
    local services=("$@")
    log_section "STARTING SERVICES IN DEPENDENCY ORDER"
    
    local deployment_order
    if ! deployment_order=($(get_deployment_order "${services[@]}")); then
        log_error "Failed to determine deployment order"
        return 1
    fi
    
    log_info "Deployment order: ${deployment_order[*]}"
    echo
    
    local failed_services=()
    
    for service in "${deployment_order[@]}"; do
        if ! service_exists "$service"; then
            log_warning "Service $service does not exist, skipping..."
            continue
        fi
        
        log_info "Starting $service..."
        
        # Scale up the service
        kubectl scale deployment "$service" --replicas=1 -n "$NAMESPACE" &>/dev/null
        
        # Wait for service to be ready
        if wait_for_service "$service"; then
            log_success "$service started successfully"
        else
            log_error "$service failed to start"
            failed_services+=("$service")
            
            # Check if this is a critical service
            local level="${SERVICE_CRITICAL_LEVEL[$service]:-medium}"
            if [[ "$level" == "critical" ]]; then
                log_error "Critical service $service failed - stopping deployment"
                return 1
            fi
        fi
        echo
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warning "Failed services: ${failed_services[*]}"
        return 1
    fi
    
    log_success "All services started successfully"
}

# Stop services in reverse dependency order
stop_services() {
    local services=("$@")
    log_section "STOPPING SERVICES IN REVERSE DEPENDENCY ORDER"
    
    local deployment_order
    if ! deployment_order=($(get_deployment_order "${services[@]}")); then
        log_error "Failed to determine deployment order"
        return 1
    fi
    
    # Reverse the order for stopping
    local stop_order=()
    for ((i=${#deployment_order[@]}-1; i>=0; i--)); do
        stop_order+=("${deployment_order[i]}")
    done
    
    log_info "Stop order: ${stop_order[*]}"
    echo
    
    for service in "${stop_order[@]}"; do
        if ! service_exists "$service"; then
            log_warning "Service $service does not exist, skipping..."
            continue
        fi
        
        log_info "Stopping $service..."
        kubectl scale deployment "$service" --replicas=0 -n "$NAMESPACE" &>/dev/null
        
        # Wait for pods to terminate
        kubectl wait --namespace="$NAMESPACE" \
                     --for=delete \
                     pod -l "app=$service" \
                     --timeout=60s &>/dev/null || true
        
        log_success "$service stopped"
    done
    
    log_success "All services stopped successfully"
}

# Restart services with dependency awareness
restart_services() {
    local services=("$@")
    log_section "RESTARTING SERVICES WITH DEPENDENCY AWARENESS"
    
    # For restart, we need to consider which services depend on the ones being restarted
    local affected_services=()
    
    for service in "${services[@]}"; do
        affected_services+=("$service")
        
        # Find services that depend on this service
        for svc in "${!SERVICE_DEPENDENCIES[@]}"; do
            local deps="${SERVICE_DEPENDENCIES[$svc]}"
            if [[ " $deps " == *" $service "* ]]; then
                affected_services+=("$svc")
            fi
        done
    done
    
    # Remove duplicates
    IFS=' ' read -r -a affected_services <<< "$(printf '%s\n' "${affected_services[@]}" | sort -u | tr '\n' ' ')"
    
    log_info "Services affected by restart: ${affected_services[*]}"
    echo
    
    # Stop affected services
    stop_services "${affected_services[@]}"
    
    echo
    
    # Start affected services
    start_services "${affected_services[@]}"
}

# Check health of all services
health_check_all() {
    log_section "COMPREHENSIVE HEALTH CHECK"
    
    local healthy_services=()
    local unhealthy_services=()
    local missing_services=()
    
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        if ! service_exists "$service"; then
            missing_services+=("$service")
            continue
        fi
        
        if ! service_deployment_ready "$service"; then
            unhealthy_services+=("$service (deployment not ready)")
            continue
        fi
        
        if check_service_health "$service"; then
            healthy_services+=("$service")
        else
            unhealthy_services+=("$service (health check failed)")
        fi
    done
    
    echo -e "${GREEN}✅ Healthy Services (${#healthy_services[@]}):${NC}"
    for service in "${healthy_services[@]}"; do
        local level="${SERVICE_CRITICAL_LEVEL[$service]:-medium}"
        echo -e "  • $service ${CYAN}($level)${NC}"
    done
    echo
    
    if [[ ${#unhealthy_services[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Unhealthy Services (${#unhealthy_services[@]}):${NC}"
        for service in "${unhealthy_services[@]}"; do
            echo -e "  • $service"
        done
        echo
    fi
    
    if [[ ${#missing_services[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Missing Services (${#missing_services[@]}):${NC}"
        for service in "${missing_services[@]}"; do
            echo -e "  • $service"
        done
        echo
    fi
    
    # Overall health status
    local total_services=${#SERVICE_DEPENDENCIES[@]}
    local healthy_count=${#healthy_services[@]}
    local health_percentage=$((healthy_count * 100 / total_services))
    
    echo -e "${CYAN}📊 Overall Health: ${healthy_count}/${total_services} services (${health_percentage}%)${NC}"
    
    if [[ $health_percentage -ge 90 ]]; then
        echo -e "${GREEN}🎉 System is healthy!${NC}"
        return 0
    elif [[ $health_percentage -ge 70 ]]; then
        echo -e "${YELLOW}⚠️  System has some issues but is mostly operational${NC}"
        return 1
    else
        echo -e "${RED}🚨 System is unhealthy - immediate attention required${NC}"
        return 2
    fi
}

# Show service dependency graph
show_dependencies() {
    log_section "SERVICE DEPENDENCY GRAPH"
    
    echo -e "${CYAN}Service Dependencies:${NC}"
    echo
    
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        local deps="${SERVICE_DEPENDENCIES[$service]}"
        local level="${SERVICE_CRITICAL_LEVEL[$service]:-medium}"
        local color
        
        case "$level" in
            "critical") color="$RED" ;;
            "high") color="$YELLOW" ;;
            "medium") color="$BLUE" ;;
            "low") color="$GREEN" ;;
        esac
        
        if [[ -n "$deps" ]]; then
            echo -e "${color}$service${NC} ${CYAN}($level)${NC} depends on:"
            for dep in $deps; do
                echo -e "  └─ $dep"
            done
        else
            echo -e "${color}$service${NC} ${CYAN}($level)${NC} (no dependencies)"
        fi
        echo
    done
}

# Monitor services continuously
monitor_services() {
    local interval="${1:-30}"
    log_section "CONTINUOUS SERVICE MONITORING"
    
    log_info "Starting continuous monitoring (interval: ${interval}s)"
    log_info "Press Ctrl+C to stop monitoring"
    echo
    
    while true; do
        clear
        echo -e "${PURPLE}PyAirtable Service Monitor - $(date)${NC}"
        echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
        echo
        
        health_check_all
        
        echo
        echo -e "${CYAN}Next check in ${interval} seconds...${NC}"
        sleep "$interval"
    done
}

# Get service status summary
service_status() {
    local service="${1:-}"
    
    if [[ -n "$service" ]]; then
        # Single service status
        log_section "STATUS FOR $service"
        
        if ! service_exists "$service"; then
            log_error "Service $service does not exist"
            return 1
        fi
        
        # Deployment status
        echo -e "${CYAN}Deployment Status:${NC}"
        kubectl get deployment "$service" -n "$NAMESPACE"
        echo
        
        # Pod status
        echo -e "${CYAN}Pod Status:${NC}"
        kubectl get pods -n "$NAMESPACE" -l "app=$service"
        echo
        
        # Service status
        echo -e "${CYAN}Service Status:${NC}"
        kubectl get service "$service" -n "$NAMESPACE"
        echo
        
        # Health check
        echo -e "${CYAN}Health Check:${NC}"
        if check_service_health "$service"; then
            echo -e "${GREEN}✅ Service is healthy${NC}"
        else
            echo -e "${RED}❌ Service health check failed${NC}"
        fi
        echo
        
        # Dependencies
        local deps="${SERVICE_DEPENDENCIES[$service]:-}"
        if [[ -n "$deps" ]]; then
            echo -e "${CYAN}Dependencies:${NC}"
            for dep in $deps; do
                if check_service_health "$dep" 2>/dev/null; then
                    echo -e "  ✅ $dep"
                else
                    echo -e "  ❌ $dep"
                fi
            done
        else
            echo -e "${CYAN}Dependencies:${NC} None"
        fi
    else
        # All services status
        health_check_all
    fi
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "start")
            local services=("$@")
            if [[ ${#services[@]} -eq 0 ]]; then
                services=("${!SERVICE_DEPENDENCIES[@]}")
            fi
            start_services "${services[@]}"
            ;;
        "stop")
            local services=("$@")
            if [[ ${#services[@]} -eq 0 ]]; then
                services=("${!SERVICE_DEPENDENCIES[@]}")
            fi
            stop_services "${services[@]}"
            ;;
        "restart")
            local services=("$@")
            if [[ ${#services[@]} -eq 0 ]]; then
                services=("${!SERVICE_DEPENDENCIES[@]}")
            fi
            restart_services "${services[@]}"
            ;;
        "health"|"check")
            health_check_all
            ;;
        "status")
            service_status "$@"
            ;;
        "deps"|"dependencies")
            show_dependencies
            ;;
        "monitor")
            monitor_services "$@"
            ;;
        "order")
            echo "Deployment order:"
            get_deployment_order "${!SERVICE_DEPENDENCIES[@]}"
            ;;
        "help"|"-h"|"--help")
            cat << EOF
PyAirtable Service Dependency Manager

Usage: $0 <command> [options]

Commands:
  start [services...]     Start services in dependency order
  stop [services...]      Stop services in reverse dependency order  
  restart [services...]   Restart services with dependency awareness
  health                  Check health of all services
  status [service]        Show detailed status for service(s)
  deps                    Show service dependency graph
  monitor [interval]      Continuously monitor services (default: 30s)
  order                   Show deployment order
  help                    Show this help message

Examples:
  $0 start                       # Start all services
  $0 start api-gateway          # Start api-gateway and its dependencies
  $0 restart llm-orchestrator   # Restart llm-orchestrator and dependent services
  $0 health                     # Check health of all services
  $0 status api-gateway         # Show detailed status for api-gateway
  $0 monitor 60                 # Monitor services every 60 seconds

Environment Variables:
  NAMESPACE                     Kubernetes namespace (default: pyairtable)
  TIMEOUT_SERVICE_READY         Service ready timeout in seconds (default: 300)
  TIMEOUT_HEALTH_CHECK          Health check timeout in seconds (default: 30)
  HEALTH_CHECK_INTERVAL         Health check retry interval in seconds (default: 5)
  MAX_HEALTH_RETRIES           Maximum health check retries (default: 6)
EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"