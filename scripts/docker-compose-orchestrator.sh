#!/bin/bash

# CRITICAL: Docker Compose Service Startup Orchestrator
# Enforces proper service dependency ordering with comprehensive health validation
# ZERO TOLERANCE for startup failures or dependency violations

set -euo pipefail

# Color codes for clear communication
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration - SECURITY: No hardcoded values
readonly SCRIPT_NAME="docker-compose-orchestrator"
readonly COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
readonly PROJECT_NAME="${COMPOSE_PROJECT_NAME:-pyairtable}"
readonly MAX_STARTUP_TIME=900  # 15 minutes MAXIMUM - this is generous
readonly HEALTH_CHECK_INTERVAL=5
readonly RETRY_LIMIT=3

# Service startup phases - ENFORCED ordering
readonly -a STARTUP_PHASES=(
    "postgres redis"                                    # Phase 1: Infrastructure
    "airtable-gateway platform-services"               # Phase 2: Core Platform 
    "mcp-server"                                        # Phase 3: Protocol Server
    "llm-orchestrator automation-services"             # Phase 4: AI and Automation
    "saga-orchestrator"                                 # Phase 5: Transaction Coordination
    "api-gateway"                                       # Phase 6: API Gateway
    "frontend"                                          # Phase 7: Frontend
)

# Service health check endpoints - COMPREHENSIVE validation
declare -A HEALTH_ENDPOINTS=(
    ["postgres"]=""
    ["redis"]=""
    ["airtable-gateway"]="http://localhost:8002/health"
    ["mcp-server"]="http://localhost:8001/health"
    ["llm-orchestrator"]="http://localhost:8003/health"
    ["platform-services"]="http://localhost:8007/health"
    ["automation-services"]="http://localhost:8006/health"
    ["saga-orchestrator"]="http://localhost:8008/health"
    ["api-gateway"]="http://localhost:8000/health"
    ["frontend"]="http://localhost:3000/api/health"
)

# Service startup timeouts - AGGRESSIVE but reasonable
declare -A SERVICE_TIMEOUTS=(
    ["postgres"]="120"
    ["redis"]="60"
    ["airtable-gateway"]="90"
    ["mcp-server"]="60"
    ["llm-orchestrator"]="120"
    ["platform-services"]="90"
    ["automation-services"]="90"
    ["saga-orchestrator"]="90"
    ["api-gateway"]="60"
    ["frontend"]="120"
)

# Critical dependency matrix - VIOLATIONS are UNACCEPTABLE
declare -A CRITICAL_DEPENDENCIES=(
    ["airtable-gateway"]="postgres redis"
    ["mcp-server"]="airtable-gateway"
    ["llm-orchestrator"]="mcp-server redis"
    ["platform-services"]="postgres redis"
    ["automation-services"]="postgres redis mcp-server platform-services"
    ["saga-orchestrator"]="postgres redis platform-services automation-services airtable-gateway"
    ["api-gateway"]="llm-orchestrator mcp-server airtable-gateway platform-services automation-services saga-orchestrator"
    ["frontend"]="api-gateway"
)

# Logging functions with timestamps and severity
log_critical() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] CRITICAL: $*${NC}" >&2
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" >&2
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

print_phase_header() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  PHASE $1: $2${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}\n"
}

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating environment prerequisites..."
    
    # Check Docker and Docker Compose
    if ! command -v docker >/dev/null 2>&1; then
        log_critical "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_critical "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check compose file exists
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_critical "Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    # Check required environment variables
    local missing_vars=()
    
    # Critical environment variables
    local required_vars=(
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD" 
        "API_KEY"
        "AIRTABLE_TOKEN"
        "AIRTABLE_BASE"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_critical "Missing required environment variables: ${missing_vars[*]}"
        log_critical "Set these variables before continuing. This is a SECURITY requirement."
        exit 1
    fi
    
    # Check Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_critical "Docker daemon is not running"
        exit 1
    fi
    
    log_success "Environment validation passed"
}

# Check if service is running via Docker Compose
is_service_running() {
    local service="$1"
    local status
    
    status=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null) || return 1
    [ -n "$status" ] && docker inspect "$status" --format '{{.State.Running}}' 2>/dev/null | grep -q true
}

# Check if service is healthy via Docker health check
is_service_healthy() {
    local service="$1"
    local container_id
    
    container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null) || return 1
    [ -n "$container_id" ] || return 1
    
    local health_status
    health_status=$(docker inspect "$container_id" --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
    
    case "$health_status" in
        "healthy") return 0 ;;
        "none") 
            # No health check defined, check if running
            is_service_running "$service"
            ;;
        *) return 1 ;;
    esac
}

# Validate service health via HTTP endpoint
validate_service_endpoint() {
    local service="$1"
    local endpoint="${HEALTH_ENDPOINTS[$service]:-}"
    
    if [ -z "$endpoint" ]; then
        log_info "$service: No HTTP endpoint defined, using container health check"
        return 0
    fi
    
    local attempts=0
    local max_attempts=5
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -sf --connect-timeout 3 --max-time 8 "$endpoint" >/dev/null 2>&1; then
            return 0
        fi
        
        ((attempts++))
        sleep 2
    done
    
    log_error "$service: HTTP endpoint $endpoint is not responding"
    return 1
}

# Wait for service to be ready with timeout and comprehensive validation
wait_for_service() {
    local service="$1"
    local timeout="${SERVICE_TIMEOUTS[$service]:-60}"
    local start_time=$(date +%s)
    
    log_info "Waiting for $service to be ready (timeout: ${timeout}s)..."
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            log_critical "$service FAILED to become ready within ${timeout}s - UNACCEPTABLE"
            return 1
        fi
        
        if is_service_running "$service"; then
            if is_service_healthy "$service"; then
                if validate_service_endpoint "$service"; then
                    log_success "$service is READY and HEALTHY (${elapsed}s)"
                    return 0
                else
                    log_warning "$service is running but endpoint validation failed"
                fi
            else
                log_info "$service is running but health check is not passing yet..."
            fi
        else
            log_info "$service is not running yet..."
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
    done
}

# Validate all critical dependencies are met
validate_dependencies() {
    local service="$1"
    local dependencies="${CRITICAL_DEPENDENCIES[$service]:-}"
    
    if [ -z "$dependencies" ]; then
        return 0
    fi
    
    log_info "Validating dependencies for $service: $dependencies"
    
    for dep in $dependencies; do
        if ! is_service_running "$dep"; then
            log_error "DEPENDENCY VIOLATION: $dep is not running (required by $service)"
            return 1
        fi
        
        if ! is_service_healthy "$dep"; then
            log_error "DEPENDENCY VIOLATION: $dep is not healthy (required by $service)"
            return 1
        fi
        
        if ! validate_service_endpoint "$dep"; then
            log_error "DEPENDENCY VIOLATION: $dep endpoint is not responding (required by $service)"
            return 1
        fi
    done
    
    log_success "All dependencies validated for $service"
    return 0
}

# Start a single service with comprehensive validation
start_service() {
    local service="$1"
    
    # Check if already running and healthy
    if is_service_running "$service" && is_service_healthy "$service"; then
        log_info "$service is already running and healthy"
        return 0
    fi
    
    log_info "Starting $service..."
    
    # Start the service
    if ! docker-compose -f "$COMPOSE_FILE" up -d "$service"; then
        log_critical "FAILED to start $service via docker-compose"
        return 1
    fi
    
    # Wait for service to be ready
    if ! wait_for_service "$service"; then
        log_critical "$service startup FAILED - this is unacceptable"
        show_service_logs "$service"
        return 1
    fi
    
    return 0
}

# Show service logs for debugging
show_service_logs() {
    local service="$1"
    
    log_error "Showing last 50 lines of logs for $service:"
    echo -e "${YELLOW}----------------------------------------${NC}"
    docker-compose -f "$COMPOSE_FILE" logs --tail=50 "$service" || true
    echo -e "${YELLOW}----------------------------------------${NC}"
}

# Start services in a phase with parallel execution
start_phase() {
    local phase_services=($1)
    local phase_number=$2
    
    print_phase_header "$phase_number" "${phase_services[*]}"
    
    local failed_services=()
    local pids=()
    
    # Start all services in this phase in parallel
    for service in "${phase_services[@]}"; do
        (
            # Validate dependencies
            if ! validate_dependencies "$service"; then
                log_critical "Dependencies not met for $service"
                exit 1
            fi
            
            # Start service
            if ! start_service "$service"; then
                log_critical "Failed to start $service"
                exit 1
            fi
        ) &
        pids+=($!)
    done
    
    # Wait for all services in this phase
    local all_succeeded=true
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local service=${phase_services[$i]}
        
        if wait $pid; then
            log_success "Phase $phase_number: $service started successfully"
        else
            log_critical "Phase $phase_number: $service FAILED"
            failed_services+=("$service")
            all_succeeded=false
        fi
    done
    
    if [ "$all_succeeded" != true ]; then
        log_critical "Phase $phase_number FAILED. Failed services: ${failed_services[*]}"
        return 1
    fi
    
    log_success "Phase $phase_number completed successfully"
    return 0
}

# Perform comprehensive post-startup validation
post_startup_validation() {
    log_info "Performing comprehensive post-startup validation..."
    
    local failed_validations=()
    
    # Check all services are running and healthy
    for service in postgres redis airtable-gateway mcp-server llm-orchestrator platform-services automation-services saga-orchestrator api-gateway frontend; do
        local validation_failed=false
        
        if ! is_service_running "$service"; then
            log_error "Post-validation FAILED: $service is not running"
            validation_failed=true
        elif ! is_service_healthy "$service"; then
            log_error "Post-validation FAILED: $service is not healthy"
            validation_failed=true
        elif ! validate_service_endpoint "$service"; then
            log_error "Post-validation FAILED: $service endpoint is not responding"
            validation_failed=true
        fi
        
        if [ "$validation_failed" = true ]; then
            failed_validations+=("$service")
        else
            log_success "$service: VALIDATED ✓"
        fi
    done
    
    # Check service connectivity matrix
    log_info "Validating service connectivity..."
    
    # Test API Gateway can reach all backend services
    local api_connectivity_test="curl -sf --connect-timeout 5 --max-time 10 http://localhost:8000/health"
    if ! eval $api_connectivity_test >/dev/null 2>&1; then
        log_error "API Gateway connectivity test failed"
        failed_validations+=("api-connectivity")
    fi
    
    if [ ${#failed_validations[@]} -gt 0 ]; then
        log_critical "POST-STARTUP VALIDATION FAILED for: ${failed_validations[*]}"
        return 1
    fi
    
    log_success "All services passed post-startup validation"
    return 0
}

# Emergency shutdown with cleanup
emergency_shutdown() {
    log_critical "EMERGENCY SHUTDOWN INITIATED"
    
    log_warning "Stopping all services..."
    docker-compose -f "$COMPOSE_FILE" down --remove-orphans || true
    
    log_warning "Cleaning up containers..."
    docker system prune -f || true
    
    log_info "Emergency shutdown completed"
}

# Generate comprehensive startup report
generate_startup_report() {
    local start_time=$1
    local success=$2
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  STARTUP ORCHESTRATION REPORT${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${BLUE}Execution Summary:${NC}"
    echo "Start Time: $(date -d @$start_time 2>/dev/null || date -r $start_time 2>/dev/null || echo 'N/A')"
    echo "End Time: $(date -d @$end_time 2>/dev/null || date -r $end_time 2>/dev/null || echo 'N/A')"
    echo "Duration: ${duration} seconds"
    echo "Result: $([ $success -eq 0 ] && echo -e "${GREEN}SUCCESS ✅${NC}" || echo -e "${RED}FAILED ❌${NC}")"
    
    echo -e "\n${BLUE}Service Status Matrix:${NC}"
    echo "┌─────────────────────┬─────────┬──────────┬──────────────┐"
    echo "│ Service             │ Running │ Healthy  │ Endpoint     │"
    echo "├─────────────────────┼─────────┼──────────┼──────────────┤"
    
    for service in postgres redis airtable-gateway mcp-server llm-orchestrator platform-services automation-services saga-orchestrator api-gateway frontend; do
        local running="❌"
        local healthy="❌"
        local endpoint="❌"
        
        if is_service_running "$service"; then
            running="✅"
            if is_service_healthy "$service"; then
                healthy="✅"
                if validate_service_endpoint "$service"; then
                    endpoint="✅"
                fi
            fi
        fi
        
        printf "│ %-19s │ %-7s │ %-8s │ %-12s │\n" "$service" "$running" "$healthy" "$endpoint"
    done
    
    echo "└─────────────────────┴─────────┴──────────┴──────────────┘"
    
    if [ $success -eq 0 ]; then
        echo -e "\n${GREEN}🎉 DEPLOYMENT SUCCESSFUL!${NC}"
        echo -e "\n${BLUE}Access Points:${NC}"
        echo "• Frontend: http://localhost:3000"
        echo "• API Gateway: http://localhost:8000"
        echo "• API Documentation: http://localhost:8000/docs"
        
        echo -e "\n${BLUE}Management Commands:${NC}"
        echo "• Monitor services: docker-compose ps"
        echo "• View logs: docker-compose logs -f [service_name]"
        echo "• Stop services: docker-compose down"
        echo "• Restart service: docker-compose restart [service_name]"
    else
        echo -e "\n${RED}❌ DEPLOYMENT FAILED${NC}"
        echo -e "\n${YELLOW}Troubleshooting Commands:${NC}"
        echo "• Check service status: docker-compose ps"
        echo "• View service logs: docker-compose logs [service_name]"
        echo "• Debug container: docker-compose exec [service_name] sh"
        echo "• Emergency cleanup: docker-compose down --volumes --remove-orphans"
        echo "• System cleanup: docker system prune -f"
    fi
}

# Main orchestration logic
main() {
    local start_time=$(date +%s)
    local success=0
    
    log_info "Starting PyAirtable Docker Compose Orchestrator"
    log_info "Compose File: $COMPOSE_FILE"
    log_info "Project Name: $PROJECT_NAME"
    
    # Parse arguments
    local force_restart=false
    local emergency_stop=false
    local validate_only=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-restart)
                force_restart=true
                shift
                ;;
            --emergency-stop)
                emergency_stop=true
                shift
                ;;
            --validate-only)
                validate_only=true
                shift
                ;;
            --compose-file|-f)
                COMPOSE_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force-restart      Stop and restart all services"
                echo "  --emergency-stop     Emergency shutdown of all services"
                echo "  --validate-only      Only validate current deployment"
                echo "  --compose-file, -f   Specify compose file (default: docker-compose.yml)"
                echo "  --help, -h          Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Handle special modes
    if [ "$emergency_stop" = true ]; then
        emergency_shutdown
        exit 0
    fi
    
    if [ "$validate_only" = true ]; then
        validate_environment
        if post_startup_validation; then
            exit 0
        else
            exit 1
        fi
    fi
    
    # Validate environment first
    validate_environment
    
    # Force restart if requested
    if [ "$force_restart" = true ]; then
        log_warning "Force restart requested - stopping all services"
        docker-compose -f "$COMPOSE_FILE" down || true
        sleep 5
    fi
    
    # Execute startup phases
    local phase_number=1
    for phase in "${STARTUP_PHASES[@]}"; do
        if ! start_phase "$phase" $phase_number; then
            success=1
            log_critical "Phase $phase_number failed - initiating emergency shutdown"
            emergency_shutdown
            break
        fi
        
        ((phase_number++))
        
        # Brief pause between phases for system stability
        if [ $phase_number -le ${#STARTUP_PHASES[@]} ]; then
            log_info "Phase $((phase_number-1)) completed. Waiting 10s before next phase..."
            sleep 10
        fi
    done
    
    # Post-startup validation
    if [ $success -eq 0 ]; then
        log_info "All phases completed. Performing final validation..."
        if ! post_startup_validation; then
            success=1
            log_critical "Post-startup validation failed"
        fi
    fi
    
    # Generate comprehensive report
    generate_startup_report $start_time $success
    
    exit $success
}

# Signal handlers for graceful cleanup
trap 'log_critical "Interrupted by user"; emergency_shutdown; exit 130' INT TERM

# Execute main function
main "$@"