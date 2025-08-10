#!/bin/bash

# PyAirtable Service Startup Orchestrator
# Intelligent tiered startup with dependency management and health validation

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
readonly STARTUP_MODE="${STARTUP_MODE:-production}"

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
readonly TIER_WAIT_TIME=30
readonly SERVICE_STARTUP_DELAY=10
readonly HEALTH_CHECK_TIMEOUT=120
readonly MAX_STARTUP_TIME=600

# Service tiers (startup order)
declare -A TIER_1=(
    ["postgres"]="PostgreSQL Database"
    ["redis"]="Redis Cache"
)

declare -A TIER_2=(
    ["airtable-gateway"]="Airtable Gateway"
    ["platform-services"]="Platform Services"
)

declare -A TIER_3=(
    ["mcp-server"]="MCP Server"
)

declare -A TIER_4=(
    ["llm-orchestrator"]="LLM Orchestrator"
    ["automation-services"]="Automation Services"
)

declare -A TIER_5=(
    ["saga-orchestrator"]="SAGA Orchestrator"
)

declare -A TIER_6=(
    ["api-gateway"]="API Gateway"
)

declare -A TIER_7=(
    ["frontend"]="Frontend Dashboard"
)

# Service health endpoints
declare -A SERVICE_HEALTH_URLS=(
    ["postgres"]="postgres:5432"
    ["redis"]="redis:6379"
    ["airtable-gateway"]="http://airtable-gateway:8002/health"
    ["mcp-server"]="http://mcp-server:8001/health"
    ["llm-orchestrator"]="http://llm-orchestrator:8003/health"
    ["platform-services"]="http://platform-services:8007/health"
    ["automation-services"]="http://automation-services:8006/health"
    ["saga-orchestrator"]="http://saga-orchestrator:8008/health"
    ["api-gateway"]="http://api-gateway:8000/health"
    ["frontend"]="http://frontend:3000/api/health"
)

# State tracking
declare -A SERVICE_STATUS=()
declare -A SERVICE_START_TIME=()
declare -A TIER_STATUS=()

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
║                   🚀 PyAirtable Service Orchestrator                        ║
║                                                                              ║
║  Intelligent tiered startup • Health validation • Dependency management     ║
║  • Tier 1: Infrastructure (PostgreSQL, Redis)                              ║
║  • Tier 2: Platform Services (Airtable Gateway, Platform Services)         ║
║  • Tier 3: MCP Server                                                       ║
║  • Tier 4: LLM & Automation Services                                        ║
║  • Tier 5: SAGA Orchestrator                                                ║
║  • Tier 6: API Gateway                                                      ║
║  • Tier 7: Frontend Dashboard                                               ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose not found. Please install Docker Compose."
        exit 1
    fi
    
    # Check compose file
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    # Check .env file
    if [[ ! -f .env ]]; then
        log_warning ".env file not found. Creating from example..."
        if [[ -f .env.example ]]; then
            cp .env.example .env
            log_warning "Please update .env file with your credentials before starting services."
            exit 1
        else
            log_error ".env.example not found. Cannot proceed."
            exit 1
        fi
    fi
    
    # Check required environment variables
    local required_vars=("AIRTABLE_TOKEN" "GEMINI_API_KEY" "POSTGRES_PASSWORD" "REDIS_PASSWORD" "JWT_SECRET" "API_KEY")
    local missing_vars=()
    
    # Source .env file
    set -a
    source .env
    set +a
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]] || [[ "${!var:-}" == "changeme" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing or invalid environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_error "Please update your .env file with valid values."
        exit 1
    fi
    
    # Check wait-for scripts
    if [[ ! -f "$SCRIPT_DIR/scripts/wait-for-database.sh" ]]; then
        log_warning "wait-for-database.sh not found. Using basic health checks."
    fi
    
    log_success "Prerequisites check passed"
}

# Clean up any existing containers
cleanup_existing() {
    log_info "Cleaning up existing containers..."
    
    if docker-compose -f "$COMPOSE_FILE" ps -q &> /dev/null; then
        docker-compose -f "$COMPOSE_FILE" down --remove-orphans
        log_info "Stopped existing containers"
    fi
    
    # Clean up any dangling networks
    docker network prune -f &> /dev/null || true
}

# Start services in a tier
start_tier_services() {
    local -n tier_services=$1
    local tier_name=$2
    
    log_tier "Starting $tier_name..."
    
    local services=()
    for service in "${!tier_services[@]}"; do
        services+=("$service")
    done
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_warning "No services found in $tier_name"
        return 0
    fi
    
    log_info "Services in $tier_name: ${services[*]}"
    
    # Start all services in this tier
    for service in "${services[@]}"; do
        local description="${tier_services[$service]}"
        log_info "Starting $service ($description)..."
        SERVICE_START_TIME["$service"]=$(date +%s)
        SERVICE_STATUS["$service"]="starting"
    done
    
    # Use Docker Compose to start the tier
    if ! docker-compose -f "$COMPOSE_FILE" up -d "${services[@]}"; then
        log_error "Failed to start services in $tier_name"
        TIER_STATUS["$tier_name"]="failed"
        return 1
    fi
    
    # Wait a bit for containers to initialize
    sleep "$SERVICE_STARTUP_DELAY"
    
    # Wait for all services in tier to be healthy
    local all_healthy=true
    for service in "${services[@]}"; do
        if wait_for_service_health "$service"; then
            SERVICE_STATUS["$service"]="healthy"
            log_success "✅ $service is healthy"
        else
            SERVICE_STATUS["$service"]="unhealthy"
            log_error "❌ $service failed health check"
            all_healthy=false
        fi
    done
    
    if [[ "$all_healthy" == true ]]; then
        TIER_STATUS["$tier_name"]="healthy"
        log_success "🎉 $tier_name started successfully"
        return 0
    else
        TIER_STATUS["$tier_name"]="failed"
        log_error "💥 $tier_name startup failed"
        return 1
    fi
}

# Wait for service health
wait_for_service_health() {
    local service=$1
    local health_url="${SERVICE_HEALTH_URLS[$service]}"
    local max_wait=$HEALTH_CHECK_TIMEOUT
    
    log_info "Waiting for $service health check..."
    
    # Handle different types of health checks
    case "$service" in
        "postgres")
            if [[ -f "$SCRIPT_DIR/scripts/wait-for-database.sh" ]]; then
                "$SCRIPT_DIR/scripts/wait-for-database.sh"
                return $?
            else
                return wait_for_postgres_simple
            fi
            ;;
        "redis")
            if [[ -f "$SCRIPT_DIR/scripts/wait-for-redis.sh" ]]; then
                "$SCRIPT_DIR/scripts/wait-for-redis.sh"
                return $?
            else
                return wait_for_redis_simple
            fi
            ;;
        *)
            if [[ -f "$SCRIPT_DIR/scripts/wait-for-service.sh" ]]; then
                "$SCRIPT_DIR/scripts/wait-for-service.sh" "$health_url"
                return $?
            else
                return wait_for_http_service "$health_url" "$max_wait"
            fi
            ;;
    esac
}

# Simple PostgreSQL health check
wait_for_postgres_simple() {
    local attempts=0
    local max_attempts=$((HEALTH_CHECK_TIMEOUT / 5))
    
    while [[ $attempts -lt $max_attempts ]]; do
        if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U "${POSTGRES_USER}" &> /dev/null; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 5
    done
    return 1
}

# Simple Redis health check
wait_for_redis_simple() {
    local attempts=0
    local max_attempts=$((HEALTH_CHECK_TIMEOUT / 5))
    
    while [[ $attempts -lt $max_attempts ]]; do
        if docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli -a "${REDIS_PASSWORD}" ping &> /dev/null; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 5
    done
    return 1
}

# Simple HTTP service health check
wait_for_http_service() {
    local url=$1
    local max_wait=$2
    local attempts=0
    local max_attempts=$((max_wait / 5))
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -f -s --connect-timeout 5 --max-time 10 "$url" &> /dev/null; then
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 5
    done
    return 1
}

# Wait between tiers
wait_between_tiers() {
    local tier_name=$1
    log_info "Waiting ${TIER_WAIT_TIME}s before starting next tier..."
    sleep "$TIER_WAIT_TIME"
}

# Start all services in proper order
start_all_services() {
    local total_start_time=$(date +%s)
    local failed_tiers=()
    
    log_info "Starting all services in tiered approach..."
    echo
    
    # Tier 1: Infrastructure
    if start_tier_services TIER_1 "Tier 1: Infrastructure"; then
        wait_between_tiers "Tier 1"
    else
        failed_tiers+=("Tier 1")
    fi
    
    # Tier 2: Platform Services (only if Tier 1 succeeded)
    if [[ "${TIER_STATUS["Tier 1: Infrastructure"]:-}" == "healthy" ]]; then
        if start_tier_services TIER_2 "Tier 2: Platform Services"; then
            wait_between_tiers "Tier 2"
        else
            failed_tiers+=("Tier 2")
        fi
    else
        log_error "Skipping Tier 2 due to Tier 1 failures"
        failed_tiers+=("Tier 2")
    fi
    
    # Tier 3: MCP Server
    if [[ "${TIER_STATUS["Tier 2: Platform Services"]:-}" == "healthy" ]]; then
        if start_tier_services TIER_3 "Tier 3: MCP Server"; then
            wait_between_tiers "Tier 3"
        else
            failed_tiers+=("Tier 3")
        fi
    else
        log_error "Skipping Tier 3 due to previous tier failures"
        failed_tiers+=("Tier 3")
    fi
    
    # Tier 4: LLM & Automation
    if [[ "${TIER_STATUS["Tier 3: MCP Server"]:-}" == "healthy" ]]; then
        if start_tier_services TIER_4 "Tier 4: LLM & Automation"; then
            wait_between_tiers "Tier 4"
        else
            failed_tiers+=("Tier 4")
        fi
    else
        log_error "Skipping Tier 4 due to previous tier failures"
        failed_tiers+=("Tier 4")
    fi
    
    # Tier 5: SAGA Orchestrator
    if [[ "${TIER_STATUS["Tier 4: LLM & Automation"]:-}" == "healthy" ]]; then
        if start_tier_services TIER_5 "Tier 5: SAGA Orchestrator"; then
            wait_between_tiers "Tier 5"
        else
            failed_tiers+=("Tier 5")
        fi
    else
        log_error "Skipping Tier 5 due to previous tier failures"
        failed_tiers+=("Tier 5")
    fi
    
    # Tier 6: API Gateway
    if [[ "${TIER_STATUS["Tier 5: SAGA Orchestrator"]:-}" == "healthy" ]]; then
        if start_tier_services TIER_6 "Tier 6: API Gateway"; then
            wait_between_tiers "Tier 6"
        else
            failed_tiers+=("Tier 6")
        fi
    else
        log_error "Skipping Tier 6 due to previous tier failures"
        failed_tiers+=("Tier 6")
    fi
    
    # Tier 7: Frontend
    if [[ "${TIER_STATUS["Tier 6: API Gateway"]:-}" == "healthy" ]]; then
        if start_tier_services TIER_7 "Tier 7: Frontend"; then
            log_success "All tiers completed"
        else
            failed_tiers+=("Tier 7")
        fi
    else
        log_error "Skipping Tier 7 due to previous tier failures"
        failed_tiers+=("Tier 7")
    fi
    
    # Summary
    local total_time=$(($(date +%s) - total_start_time))
    echo
    log_info "=== STARTUP SUMMARY ==="
    log_info "Total startup time: ${total_time}s"
    
    if [[ ${#failed_tiers[@]} -eq 0 ]]; then
        log_success "🎉 All services started successfully!"
        show_service_urls
        return 0
    else
        log_error "❌ Failed tiers: ${failed_tiers[*]}"
        show_troubleshooting_info
        return 1
    fi
}

# Show service URLs
show_service_urls() {
    echo
    log_success "=== SERVICE URLS ==="
    echo "🌐 Frontend Dashboard:    http://localhost:3000"
    echo "🚪 API Gateway:          http://localhost:8000"
    echo "🔗 MCP Server:           http://localhost:8001"
    echo "📊 Airtable Gateway:     http://localhost:8002"
    echo "🤖 LLM Orchestrator:     http://localhost:8003"
    echo "⚙️  Automation Services:  http://localhost:8006"
    echo "🏢 Platform Services:    http://localhost:8007"
    echo "🔄 SAGA Orchestrator:    http://localhost:8008"
    echo
    echo "📊 Health Checks:"
    echo "   curl http://localhost:8000/health"
    echo "   curl http://localhost:8007/health"
    echo
    echo "📋 Monitoring:"
    echo "   docker-compose logs -f"
    echo "   docker-compose ps"
}

# Show troubleshooting information
show_troubleshooting_info() {
    echo
    log_warning "=== TROUBLESHOOTING ==="
    echo "1. Check service logs:"
    echo "   docker-compose logs [service-name]"
    echo
    echo "2. Check service status:"
    echo "   docker-compose ps"
    echo
    echo "3. Test individual service health:"
    echo "   curl -v http://localhost:8000/health"
    echo
    echo "4. Restart specific tier:"
    echo "   docker-compose restart [service-name]"
    echo
    echo "5. Full cleanup and restart:"
    echo "   docker-compose down && ./start-services.sh"
}

# Handle cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Startup failed with exit code $exit_code"
        log_info "Run with DEBUG=1 for more verbose output"
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
    
    log_info "PyAirtable Service Orchestrator"
    log_info "Compose file: $COMPOSE_FILE"
    log_info "Startup mode: $STARTUP_MODE"
    echo
    
    # Execute startup sequence
    check_prerequisites
    cleanup_existing
    start_all_services
}

# Handle command line arguments
case "${1:-start}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Service Startup Orchestrator"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  start     Start all services (default)"
        echo "  stop      Stop all services"
        echo "  restart   Restart all services"
        echo "  status    Show service status"
        echo "  help      Show this help"
        echo
        echo "Environment Variables:"
        echo "  COMPOSE_FILE    Docker Compose file (default: docker-compose.yml)"
        echo "  STARTUP_MODE    Startup mode (default: production)"
        echo "  DEBUG           Enable debug output (DEBUG=1)"
        echo
        exit 0
        ;;
    "stop")
        log_info "Stopping all services..."
        docker-compose -f "$COMPOSE_FILE" down --remove-orphans
        log_success "All services stopped"
        exit 0
        ;;
    "restart")
        log_info "Restarting all services..."
        docker-compose -f "$COMPOSE_FILE" down --remove-orphans
        exec "$0" start
        ;;
    "status")
        log_info "Service status:"
        docker-compose -f "$COMPOSE_FILE" ps
        exit 0
        ;;
    "start"|*)
        main
        ;;
esac