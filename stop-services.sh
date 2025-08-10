#!/bin/bash

# PyAirtable Service Graceful Shutdown Script
# Intelligent shutdown with proper service dependency order

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
readonly SHUTDOWN_MODE="${SHUTDOWN_MODE:-graceful}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Timeouts
readonly GRACEFUL_TIMEOUT=30
readonly FORCE_TIMEOUT=10
readonly TIER_SHUTDOWN_DELAY=5

# Service shutdown order (reverse of startup)
declare -A SHUTDOWN_TIER_1=(
    ["frontend"]="Frontend Dashboard"
)

declare -A SHUTDOWN_TIER_2=(
    ["api-gateway"]="API Gateway"
)

declare -A SHUTDOWN_TIER_3=(
    ["saga-orchestrator"]="SAGA Orchestrator"
)

declare -A SHUTDOWN_TIER_4=(
    ["llm-orchestrator"]="LLM Orchestrator"
    ["automation-services"]="Automation Services"
)

declare -A SHUTDOWN_TIER_5=(
    ["mcp-server"]="MCP Server"
)

declare -A SHUTDOWN_TIER_6=(
    ["airtable-gateway"]="Airtable Gateway"
    ["platform-services"]="Platform Services"
)

declare -A SHUTDOWN_TIER_7=(
    ["postgres"]="PostgreSQL Database"
    ["redis"]="Redis Cache"
)

# Service shutdown strategies
declare -A SERVICE_SHUTDOWN_STRATEGY=(
    ["frontend"]="graceful"
    ["api-gateway"]="graceful"
    ["saga-orchestrator"]="graceful"
    ["llm-orchestrator"]="graceful"
    ["automation-services"]="graceful"
    ["mcp-server"]="graceful"
    ["airtable-gateway"]="graceful"
    ["platform-services"]="graceful"
    ["postgres"]="graceful"
    ["redis"]="immediate"
)

# State tracking
declare -A SERVICE_SHUTDOWN_STATUS=()
declare -A TIER_SHUTDOWN_STATUS=()

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

log_tier() {
    echo -e "${PURPLE}[TIER]${NC} $*"
}

# Banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                  🛑 PyAirtable Service Shutdown Manager                      ║
║                                                                              ║
║  Graceful shutdown • Dependency-aware ordering • Data safety first         ║
║  • Tier 1: Frontend Dashboard                                              ║
║  • Tier 2: API Gateway                                                     ║
║  • Tier 3: SAGA Orchestrator                                               ║
║  • Tier 4: LLM & Automation Services                                       ║
║  • Tier 5: MCP Server                                                      ║
║  • Tier 6: Platform Services                                               ║
║  • Tier 7: Infrastructure (PostgreSQL, Redis)                              ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# Check if service is running
is_service_running() {
    local service=$1
    docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | grep -q .
}

# Get running services
get_running_services() {
    docker-compose -f "$COMPOSE_FILE" ps --services 2>/dev/null | grep -v '^$' || true
}

# Send graceful shutdown signal to service
send_graceful_shutdown() {
    local service=$1
    local strategy="${SERVICE_SHUTDOWN_STRATEGY[$service]:-graceful}"
    
    log_info "Sending shutdown signal to $service (strategy: $strategy)..."
    
    case "$strategy" in
        "graceful")
            # Send SIGTERM for graceful shutdown
            docker-compose -f "$COMPOSE_FILE" kill -s TERM "$service" 2>/dev/null || true
            ;;
        "immediate")
            # Send SIGKILL for immediate shutdown
            docker-compose -f "$COMPOSE_FILE" kill -s KILL "$service" 2>/dev/null || true
            ;;
    esac
}

# Wait for service to stop
wait_for_service_stop() {
    local service=$1
    local timeout=${2:-$GRACEFUL_TIMEOUT}
    local start_time=$(date +%s)
    
    while is_service_running "$service"; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $timeout ]]; then
            log_warning "$service did not stop gracefully within ${timeout}s"
            return 1
        fi
        
        sleep 2
    done
    
    local total_time=$((($(date +%s) - start_time)))
    log_success "$service stopped gracefully in ${total_time}s"
    return 0
}

# Force stop service
force_stop_service() {
    local service=$1
    
    log_warning "Force stopping $service..."
    
    # First try SIGKILL
    docker-compose -f "$COMPOSE_FILE" kill -s KILL "$service" 2>/dev/null || true
    
    # Wait a bit
    sleep 2
    
    # Then try docker-compose stop with short timeout
    docker-compose -f "$COMPOSE_FILE" stop -t "$FORCE_TIMEOUT" "$service" 2>/dev/null || true
    
    # Final check
    if is_service_running "$service"; then
        log_error "Failed to force stop $service"
        return 1
    else
        log_success "Force stopped $service"
        return 0
    fi
}

# Shutdown services in a tier
shutdown_tier_services() {
    local -n tier_services=$1
    local tier_name=$2
    
    log_tier "Shutting down $tier_name..."
    
    local services=()
    for service in "${!tier_services[@]}"; do
        if is_service_running "$service"; then
            services+=("$service")
        fi
    done
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_info "No running services found in $tier_name"
        TIER_SHUTDOWN_STATUS["$tier_name"]="skipped"
        return 0
    fi
    
    log_info "Running services in $tier_name: ${services[*]}"
    
    # Send shutdown signals to all services in tier
    for service in "${services[@]}"; do
        local description="${tier_services[$service]}"
        log_info "Initiating shutdown for $service ($description)..."
        send_graceful_shutdown "$service"
        SERVICE_SHUTDOWN_STATUS["$service"]="stopping"
    done
    
    # Wait for all services in tier to stop gracefully
    local all_stopped=true
    for service in "${services[@]}"; do
        if wait_for_service_stop "$service" "$GRACEFUL_TIMEOUT"; then
            SERVICE_SHUTDOWN_STATUS["$service"]="stopped"
            log_success "✅ $service stopped gracefully"
        else
            # Try force stop
            if force_stop_service "$service"; then
                SERVICE_SHUTDOWN_STATUS["$service"]="force_stopped"
                log_warning "⚠️  $service force stopped"
            else
                SERVICE_SHUTDOWN_STATUS["$service"]="failed"
                log_error "❌ $service shutdown failed"
                all_stopped=false
            fi
        fi
    done
    
    if [[ "$all_stopped" == true ]]; then
        TIER_SHUTDOWN_STATUS["$tier_name"]="stopped"
        log_success "🎉 $tier_name shutdown completed"
        return 0
    else
        TIER_SHUTDOWN_STATUS["$tier_name"]="failed"
        log_error "💥 $tier_name shutdown had failures"
        return 1
    fi
}

# Wait between tier shutdowns
wait_between_tier_shutdowns() {
    if [[ $TIER_SHUTDOWN_DELAY -gt 0 ]]; then
        log_info "Waiting ${TIER_SHUTDOWN_DELAY}s before shutting down next tier..."
        sleep "$TIER_SHUTDOWN_DELAY"
    fi
}

# Backup critical data before shutdown
backup_critical_data() {
    if [[ "$SHUTDOWN_MODE" == "emergency" ]]; then
        log_warning "Emergency shutdown - skipping data backup"
        return 0
    fi
    
    log_info "Checking for critical data backup needs..."
    
    # Check if database has pending transactions
    if is_service_running "postgres"; then
        log_info "Postgres is running - allowing graceful database shutdown"
        
        # You could add specific backup commands here if needed
        # docker-compose exec postgres pg_dump ...
    fi
    
    # Check Redis persistence
    if is_service_running "redis"; then
        log_info "Triggering Redis save before shutdown..."
        docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli -a "${REDIS_PASSWORD:-}" BGSAVE 2>/dev/null || true
        sleep 2  # Give Redis a moment to start the background save
    fi
    
    log_success "Critical data backup checks completed"
}

# Cleanup resources
cleanup_resources() {
    log_info "Cleaning up resources..."
    
    # Remove any orphaned containers
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
    
    # Clean up networks
    docker network prune -f &>/dev/null || true
    
    # Clean up anonymous volumes (only if explicitly requested)
    if [[ "${CLEANUP_VOLUMES:-}" == "true" ]]; then
        log_warning "Removing anonymous volumes..."
        docker volume prune -f &>/dev/null || true
    fi
    
    log_success "Resource cleanup completed"
}

# Shutdown all services in proper order
shutdown_all_services() {
    local total_start_time=$(date +%s)
    local failed_tiers=()
    
    log_info "Starting graceful shutdown of all services..."
    echo
    
    # Check if any services are running
    local running_services
    running_services=$(get_running_services)
    
    if [[ -z "$running_services" ]]; then
        log_info "No services are currently running"
        return 0
    fi
    
    log_info "Running services: $(echo $running_services | tr '\n' ' ')"
    echo
    
    # Backup critical data first
    backup_critical_data
    echo
    
    # Tier 1: Frontend (least critical, shutdown first)
    if shutdown_tier_services SHUTDOWN_TIER_1 "Tier 1: Frontend"; then
        wait_between_tier_shutdowns
    else
        failed_tiers+=("Tier 1")
    fi
    
    # Tier 2: API Gateway
    if shutdown_tier_services SHUTDOWN_TIER_2 "Tier 2: API Gateway"; then
        wait_between_tier_shutdowns
    else
        failed_tiers+=("Tier 2")
    fi
    
    # Tier 3: SAGA Orchestrator
    if shutdown_tier_services SHUTDOWN_TIER_3 "Tier 3: SAGA Orchestrator"; then
        wait_between_tier_shutdowns
    else
        failed_tiers+=("Tier 3")
    fi
    
    # Tier 4: LLM & Automation
    if shutdown_tier_services SHUTDOWN_TIER_4 "Tier 4: LLM & Automation"; then
        wait_between_tier_shutdowns
    else
        failed_tiers+=("Tier 4")
    fi
    
    # Tier 5: MCP Server
    if shutdown_tier_services SHUTDOWN_TIER_5 "Tier 5: MCP Server"; then
        wait_between_tier_shutdowns
    else
        failed_tiers+=("Tier 5")
    fi
    
    # Tier 6: Platform Services
    if shutdown_tier_services SHUTDOWN_TIER_6 "Tier 6: Platform Services"; then
        wait_between_tier_shutdowns
    else
        failed_tiers+=("Tier 6")
    fi
    
    # Tier 7: Infrastructure (most critical, shutdown last)
    if shutdown_tier_services SHUTDOWN_TIER_7 "Tier 7: Infrastructure"; then
        log_success "All tiers shutdown completed"
    else
        failed_tiers+=("Tier 7")
    fi
    
    # Final cleanup
    cleanup_resources
    
    # Summary
    local total_time=$(($(date +%s) - total_start_time))
    echo
    log_info "=== SHUTDOWN SUMMARY ==="
    log_info "Total shutdown time: ${total_time}s"
    
    if [[ ${#failed_tiers[@]} -eq 0 ]]; then
        log_success "🎉 All services shut down successfully!"
        return 0
    else
        log_warning "⚠️  Some tiers had shutdown issues: ${failed_tiers[*]}"
        show_remaining_processes
        return 1
    fi
}

# Show any remaining processes
show_remaining_processes() {
    log_warning "Checking for remaining processes..."
    
    local remaining_services
    remaining_services=$(get_running_services)
    
    if [[ -n "$remaining_services" ]]; then
        log_warning "Services still running:"
        echo "$remaining_services" | while read -r service; do
            if [[ -n "$service" ]]; then
                log_warning "  - $service"
            fi
        done
        echo
        log_info "To force stop remaining services:"
        echo "  docker-compose -f $COMPOSE_FILE down --remove-orphans"
        echo "  docker-compose -f $COMPOSE_FILE kill"
    else
        log_success "All services have been shut down"
    fi
}

# Emergency shutdown
emergency_shutdown() {
    log_error "=== EMERGENCY SHUTDOWN ==="
    log_warning "Force stopping all services immediately..."
    
    # Kill all services
    docker-compose -f "$COMPOSE_FILE" kill 2>/dev/null || true
    
    # Wait a moment
    sleep 3
    
    # Force down
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
    
    # Final cleanup
    cleanup_resources
    
    log_warning "Emergency shutdown completed"
}

# Handle cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Shutdown encountered issues (exit code: $exit_code)"
    fi
}

# Main execution
main() {
    print_banner
    
    # Set up cleanup
    trap cleanup_on_exit EXIT
    
    # Enable debug mode if requested
    if [[ "${DEBUG:-}" == "1" ]]; then
        set -x
    fi
    
    log_info "PyAirtable Service Shutdown Manager"
    log_info "Compose file: $COMPOSE_FILE"
    log_info "Shutdown mode: $SHUTDOWN_MODE"
    echo
    
    # Check prerequisites
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    # Execute shutdown based on mode
    case "$SHUTDOWN_MODE" in
        "graceful")
            shutdown_all_services
            ;;
        "emergency")
            emergency_shutdown
            ;;
        *)
            log_error "Unknown shutdown mode: $SHUTDOWN_MODE"
            exit 1
            ;;
    esac
}

# Handle command line arguments
case "${1:-graceful}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Service Graceful Shutdown Script"
        echo
        echo "Usage: $0 [mode]"
        echo
        echo "Shutdown Modes:"
        echo "  graceful    Graceful shutdown with dependency ordering (default)"
        echo "  emergency   Emergency shutdown - force stop all services"
        echo "  force       Alias for emergency"
        echo "  help        Show this help"
        echo
        echo "Environment Variables:"
        echo "  COMPOSE_FILE      Docker Compose file (default: docker-compose.yml)"
        echo "  SHUTDOWN_MODE     Override shutdown mode"
        echo "  CLEANUP_VOLUMES   Remove anonymous volumes (CLEANUP_VOLUMES=true)"
        echo "  DEBUG             Enable debug output (DEBUG=1)"
        echo
        exit 0
        ;;
    "emergency"|"force")
        SHUTDOWN_MODE="emergency"
        main
        ;;
    "graceful"|*)
        SHUTDOWN_MODE="graceful"
        main
        ;;
esac