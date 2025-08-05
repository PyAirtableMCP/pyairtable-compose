#!/bin/bash

# PyAirtable Startup Orchestrator
# Intelligent dependency-aware service startup with health validation
# Ensures proper initialization order and service readiness

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NAMESPACE="${NAMESPACE:-pyairtable-dev}"
readonly MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-pyairtable-dev}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Timeouts and intervals
readonly MAX_WAIT_TIME=300  # 5 minutes max wait
readonly HEALTH_CHECK_INTERVAL=5
readonly STARTUP_DELAY=10
readonly DEPENDENCY_WAIT=30

# Service dependency graph (topological order)
declare -A SERVICE_DEPENDENCIES=(
    ["postgres"]=""
    ["redis"]=""
    ["airtable-gateway"]="postgres redis"
    ["mcp-server"]="postgres redis airtable-gateway"
    ["llm-orchestrator"]="postgres redis mcp-server"
    ["platform-services"]="postgres redis"
    ["automation-services"]="postgres redis mcp-server platform-services"
)

# Service health check endpoints
declare -A HEALTH_ENDPOINTS=(
    ["postgres"]="5432"
    ["redis"]="6379"
    ["airtable-gateway"]="8002/health"
    ["mcp-server"]="8001/health"
    ["llm-orchestrator"]="8003/health"
    ["platform-services"]="8007/health"
    ["automation-services"]="8006/health"
)

# Service startup priority (lower = higher priority)
declare -A STARTUP_PRIORITY=(
    ["postgres"]=1
    ["redis"]=1
    ["airtable-gateway"]=2
    ["mcp-server"]=3
    ["platform-services"]=3
    ["llm-orchestrator"]=4
    ["automation-services"]=5
)

# State tracking
declare -A SERVICE_STATUS=()
declare -A SERVICE_START_TIME=()
declare -A SERVICE_READY_TIME=()

# Logging functions
log() {
    echo -e "${WHITE}[$(date +'%H:%M:%S')]${NC} $*"
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

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║              🚀 PyAirtable Startup Orchestrator                             ║
║                                                                              ║
║  Intelligent dependency-aware service startup with health validation        ║
║  • Service dependency resolution • Health monitoring • Progress tracking    ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

print_section() {
    echo -e "\n${PURPLE}═══ $* ═══${NC}\n"
}

# Check if service exists in cluster
service_exists() {
    local service="$1"
    kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null
}

# Get service pod status
get_service_status() {
    local service="$1"
    
    if ! service_exists "$service"; then
        echo "NotFound"
        return
    fi
    
    local pod_status
    pod_status=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | head -1 | awk '{print $3}' || echo "Unknown")
    echo "$pod_status"
}

# Check if service is ready (all containers ready)
is_service_ready() {
    local service="$1"
    
    if ! service_exists "$service"; then
        return 1
    fi
    
    local ready_status
    ready_status=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | head -1 | awk '{print $2}' || echo "0/0")
    
    if [[ "$ready_status" == "1/1" ]]; then
        return 0
    else
        return 1
    fi
}

# Health check for database services
check_database_health() {
    local service="$1"
    local port="$2"
    
    kubectl run health-check-"$service"-$(date +%s) \
        --rm -i --restart=Never --image=postgres:16-alpine \
        --namespace="$NAMESPACE" -- \
        sh -c "pg_isready -h $service -p $port -U pyairtable" &> /dev/null
}

# Health check for Redis
check_redis_health() {
    kubectl run health-check-redis-$(date +%s) \
        --rm -i --restart=Never --image=redis:7-alpine \
        --namespace="$NAMESPACE" -- \
        sh -c "redis-cli -h redis ping" &> /dev/null
}

# Health check for HTTP services
check_http_health() {
    local service="$1"
    local endpoint="$2"
    
    kubectl run health-check-"$service"-$(date +%s) \
        --rm -i --restart=Never --image=curlimages/curl:latest \
        --namespace="$NAMESPACE" -- \
        sh -c "curl -f -m 5 http://$service:$endpoint" &> /dev/null
}

# Comprehensive health check
check_service_health() {
    local service="$1"
    local endpoint="${HEALTH_ENDPOINTS[$service]}"
    
    case "$service" in
        "postgres")
            check_database_health "$service" "$endpoint"
            ;;
        "redis")
            check_redis_health
            ;;
        *)
            check_http_health "$service" "$endpoint"
            ;;
    esac
}

# Wait for service to be healthy
wait_for_service_health() {
    local service="$1"
    local max_wait="${2:-$MAX_WAIT_TIME}"
    local start_time=$(date +%s)
    
    log_info "Waiting for $service to be healthy..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $max_wait ]]; then
            log_error "Timeout waiting for $service to be healthy (${max_wait}s)"
            return 1
        fi
        
        if check_service_health "$service"; then
            SERVICE_READY_TIME["$service"]=$(date +%s)
            local total_time=$((SERVICE_READY_TIME["$service"] - SERVICE_START_TIME["$service"]))
            log_success "$service is healthy (${total_time}s startup time)"
            return 0
        fi
        
        # Show progress every 10 seconds
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            log_info "$service health check... (${elapsed}s elapsed)"
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# Check if all dependencies are ready
dependencies_ready() {
    local service="$1"
    local deps="${SERVICE_DEPENDENCIES[$service]}"
    
    if [[ -z "$deps" ]]; then
        return 0  # No dependencies
    fi
    
    for dep in $deps; do
        if [[ "${SERVICE_STATUS[$dep]:-}" != "ready" ]]; then
            log_info "Waiting for dependency: $dep (status: ${SERVICE_STATUS[$dep]:-unknown})"
            return 1
        fi
    done
    
    return 0
}

# Start a single service
start_service() {
    local service="$1"
    
    log_info "Starting $service..."
    SERVICE_START_TIME["$service"]=$(date +%s)
    SERVICE_STATUS["$service"]="starting"
    
    # Check if service deployment exists
    if ! service_exists "$service"; then
        log_error "Service $service deployment not found"
        SERVICE_STATUS["$service"]="error"
        return 1
    fi
    
    # Ensure deployment is not paused
    kubectl rollout resume deployment/"$service" -n "$NAMESPACE" &> /dev/null || true
    
    # Scale up if needed
    local replicas
    replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    if [[ "$replicas" -eq 0 ]]; then
        kubectl scale deployment/"$service" --replicas=1 -n "$NAMESPACE"
    fi
    
    # Wait for pod to be running
    log_info "Waiting for $service pod to be running..."
    if ! kubectl wait --for=condition=available deployment/"$service" \
        --namespace="$NAMESPACE" --timeout="${DEPENDENCY_WAIT}s"; then
        log_error "Failed to start $service deployment"
        SERVICE_STATUS["$service"]="error"
        return 1
    fi
    
    # Wait for service readiness
    if wait_for_service_health "$service"; then
        SERVICE_STATUS["$service"]="ready"
        log_success "$service started successfully"
        return 0
    else
        SERVICE_STATUS["$service"]="unhealthy"
        log_error "$service failed health check"
        return 1
    fi
}

# Get services in startup order
get_startup_order() {
    local services=()
    
    # Sort by priority, then by dependency depth
    for service in "${!STARTUP_PRIORITY[@]}"; do
        services+=("${STARTUP_PRIORITY[$service]}:$service")
    done
    
    printf '%s\n' "${services[@]}" | sort -n | cut -d: -f2
}

# Start all services in proper order
start_all_services() {
    print_section "STARTING SERVICES IN DEPENDENCY ORDER"
    
    local services
    mapfile -t services < <(get_startup_order)
    
    log_info "Startup order: ${services[*]}"
    echo
    
    local failed_services=()
    local total_start_time=$(date +%s)
    
    for service in "${services[@]}"; do
        # Check dependencies
        log_info "Checking dependencies for $service..."
        local attempts=0
        while ! dependencies_ready "$service"; do
            attempts=$((attempts + 1))
            if [[ $attempts -gt 20 ]]; then  # 20 * 5s = 100s timeout
                log_error "Dependency timeout for $service"
                failed_services+=("$service")
                SERVICE_STATUS["$service"]="dependency_error"
                break
            fi
            sleep 5
        done
        
        # Skip if dependency failed
        if [[ "${SERVICE_STATUS[$service]:-}" == "dependency_error" ]]; then
            continue
        fi
        
        # Start the service
        if start_service "$service"; then
            log_success "✅ $service ready"
        else
            log_error "❌ $service failed"
            failed_services+=("$service")
        fi
        
        # Small delay between services
        if [[ "$service" != "${services[-1]}" ]]; then
            sleep "$STARTUP_DELAY"
        fi
        
        echo
    done
    
    local total_end_time=$(date +%s)
    local total_time=$((total_end_time - total_start_time))
    
    # Summary
    print_section "STARTUP SUMMARY"
    
    log_info "Total startup time: ${total_time}s"
    echo
    
    # Success summary
    local ready_services=()
    for service in "${services[@]}"; do
        if [[ "${SERVICE_STATUS[$service]:-}" == "ready" ]]; then
            ready_services+=("$service")
            local startup_time=$((SERVICE_READY_TIME["$service"] - SERVICE_START_TIME["$service"]))
            log_success "✅ $service (${startup_time}s)"
        fi
    done
    
    echo
    
    # Failure summary
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_error "Failed services:"
        for service in "${failed_services[@]}"; do
            log_error "❌ $service (${SERVICE_STATUS[$service]:-unknown})"
        done
        echo
        return 1
    else
        log_success "🎉 All services started successfully!"
        return 0
    fi
}

# Stop all services
stop_all_services() {
    print_section "STOPPING ALL SERVICES"
    
    local services
    mapfile -t services < <(get_startup_order)
    
    # Stop in reverse order
    local reverse_services=()
    for ((i=${#services[@]}-1; i>=0; i--)); do
        reverse_services+=("${services[i]}")
    done
    
    for service in "${reverse_services[@]}"; do
        if service_exists "$service"; then
            log_info "Stopping $service..."
            kubectl scale deployment/"$service" --replicas=0 -n "$NAMESPACE" &> /dev/null || true
            SERVICE_STATUS["$service"]="stopped"
        fi
    done
    
    log_success "All services stopped"
}

# Restart services
restart_services() {
    local services=("$@")
    
    if [[ ${#services[@]} -eq 0 ]]; then
        services=($(get_startup_order))
    fi
    
    print_section "RESTARTING SERVICES: ${services[*]}"
    
    # Stop services in reverse order
    for ((i=${#services[@]}-1; i>=0; i--)); do
        local service="${services[i]}"
        if service_exists "$service"; then
            log_info "Stopping $service..."
            kubectl scale deployment/"$service" --replicas=0 -n "$NAMESPACE"
            kubectl wait --for=delete pod -l app="$service" -n "$NAMESPACE" --timeout=60s || true
        fi
    done
    
    sleep 5
    
    # Start services in correct order
    for service in "${services[@]}"; do
        if service_exists "$service"; then
            start_service "$service"
        fi
    done
}

# Show current status
show_status() {
    print_section "CURRENT SERVICE STATUS"
    
    local services
    mapfile -t services < <(get_startup_order)
    
    printf "%-20s %-12s %-10s %-10s\n" "Service" "Status" "Ready" "Health"
    echo "────────────────────────────────────────────────────────────"
    
    for service in "${services[@]}"; do
        local pod_status
        pod_status=$(get_service_status "$service")
        
        local ready_status="No"
        if is_service_ready "$service"; then
            ready_status="Yes"
        fi
        
        local health_status="Unknown"
        if check_service_health "$service" 2>/dev/null; then
            health_status="Healthy"
        elif [[ "$pod_status" == "Running" ]]; then
            health_status="Unhealthy"
        fi
        
        # Color coding
        local color="${RED}"
        case "$pod_status" in
            "Running") color="${GREEN}" ;;
            "Pending") color="${YELLOW}" ;;
        esac
        
        printf "${color}%-20s %-12s %-10s %-10s${NC}\n" \
            "$service" "$pod_status" "$ready_status" "$health_status"
    done
    echo
}

# Main menu
show_menu() {
    echo -e "${CYAN}PyAirtable Startup Orchestrator${NC}\n"
    echo "1. Start all services"
    echo "2. Stop all services"
    echo "3. Restart all services"
    echo "4. Restart specific service"
    echo "5. Show current status"
    echo "6. Health check all services"
    echo "0. Exit"
    echo
}

# Interactive mode
interactive_mode() {
    while true; do
        show_menu
        read -p "Select option (0-6): " choice
        echo
        
        case "$choice" in
            1)
                start_all_services
                ;;
            2)
                stop_all_services
                ;;
            3)
                restart_services
                ;;
            4)
                echo "Available services:"
                local services
                mapfile -t services < <(get_startup_order)
                for i in "${!services[@]}"; do
                    echo "  $((i+1)). ${services[i]}"
                done
                echo
                read -p "Select service (1-${#services[@]}): " svc_num
                
                if [[ "$svc_num" -ge 1 && "$svc_num" -le "${#services[@]}" ]]; then
                    local selected="${services[$((svc_num-1))]}"
                    restart_services "$selected"
                fi
                ;;
            5)
                show_status
                ;;
            6)
                print_section "HEALTH CHECK RESULTS"
                for service in $(get_startup_order); do
                    if check_service_health "$service"; then
                        log_success "$service is healthy"
                    else
                        log_error "$service is unhealthy"
                    fi
                done
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
        clear
    done
}

# Main execution
main() {
    print_banner
    
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace $NAMESPACE not found"
        exit 1
    fi
    
    # Initialize service status
    for service in "${!SERVICE_DEPENDENCIES[@]}"; do
        SERVICE_STATUS["$service"]="unknown"
    done
    
    case "${1:-interactive}" in
        "start")
            start_all_services
            ;;
        "stop")
            stop_all_services
            ;;
        "restart")
            shift
            restart_services "$@"
            ;;
        "status")
            show_status
            ;;
        "health")
            for service in $(get_startup_order); do
                if check_service_health "$service"; then
                    log_success "$service is healthy"
                else
                    log_error "$service is unhealthy"
                fi
            done
            ;;
        "interactive"|*)
            interactive_mode
            ;;
    esac
}

# Command line handling
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Startup Orchestrator"
        echo
        echo "Usage: $0 [command] [options]"
        echo
        echo "Commands:"
        echo "  start              Start all services in dependency order"
        echo "  stop               Stop all services"
        echo "  restart [services] Restart services (all if none specified)"
        echo "  status             Show current service status"
        echo "  health             Check health of all services"
        echo "  interactive        Interactive mode (default)"
        echo "  help               Show this help"
        echo
        echo "Environment Variables:"
        echo "  NAMESPACE          Kubernetes namespace (default: pyairtable-dev)"
        echo "  MINIKUBE_PROFILE   Minikube profile (default: pyairtable-dev)"
        echo
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac