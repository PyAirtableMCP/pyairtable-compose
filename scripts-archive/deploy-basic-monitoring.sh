#!/bin/bash

# PyAirtable Basic Monitoring Stack Deployment
# Deploys Prometheus + Grafana + Loki for immediate service visibility

set -euo pipefail

# Configuration
MONITORING_NETWORK="pyairtable-monitoring-basic"
SERVICES_NETWORK="pyairtable-network"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check if main services network exists
    if ! docker network inspect "$SERVICES_NETWORK" &> /dev/null; then
        warning "Main services network '$SERVICES_NETWORK' not found. Creating it..."
        docker network create "$SERVICES_NETWORK" || {
            error "Failed to create main services network"
            exit 1
        }
    fi
    
    success "Prerequisites check passed"
}

# Create monitoring directories
setup_directories() {
    log "Setting up monitoring directories..."
    
    mkdir -p monitoring/grafana-basic/{provisioning/{datasources,dashboards},dashboards}
    
    # Set proper permissions for Grafana
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo chown -R 472:472 monitoring/grafana-basic/ 2>/dev/null || warning "Could not set Grafana permissions"
    fi
    
    success "Directories created successfully"
}

# Validate configuration files
validate_config() {
    log "Validating configuration files..."
    
    local required_files=(
        "monitoring/prometheus-basic.yml"
        "monitoring/alert_rules_basic.yml"
        "monitoring/alertmanager-basic.yml"
        "monitoring/loki-basic.yml"
        "monitoring/promtail-basic.yml"
        "monitoring/blackbox-basic.yml"
        "monitoring/grafana-basic/provisioning/datasources/datasources.yml"
        "monitoring/grafana-basic/provisioning/dashboards/dashboards.yml"
        "monitoring/grafana-basic/dashboards/service-overview.json"
        "monitoring/grafana-basic/dashboards/infrastructure-overview.json"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error "Required configuration file missing: $file"
            exit 1
        fi
    done
    
    success "Configuration files validated"
}

# Check if services are running
check_services() {
    log "Checking if PyAirtable services are running..."
    
    local services=("api-gateway" "airtable-gateway" "mcp-server" "llm-orchestrator")
    local running_services=0
    
    for service in "${services[@]}"; do
        if docker ps --filter "name=$service" --format "{{.Names}}" | grep -q "$service"; then
            success "✓ $service is running"
            ((running_services++))
        else
            warning "✗ $service is not running"
        fi
    done
    
    if [[ $running_services -eq 0 ]]; then
        error "No PyAirtable services are running. Start them first with:"
        error "  docker-compose -f docker-compose.minimal-working.yml up -d"
        exit 1
    fi
    
    log "Found $running_services/4 services running"
}

# Deploy monitoring stack
deploy_monitoring() {
    log "Deploying basic monitoring stack..."
    
    # Pull images first
    log "Pulling monitoring images..."
    docker-compose -f docker-compose.monitoring-basic.yml pull
    
    # Start monitoring services
    log "Starting monitoring services..."
    docker-compose -f docker-compose.monitoring-basic.yml up -d
    
    success "Monitoring stack deployed"
}

# Wait for services to be healthy
wait_for_services() {
    log "Waiting for monitoring services to be healthy..."
    
    local services=("prometheus-basic" "grafana-basic" "loki-basic" "alertmanager-basic")
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local healthy_count=0
        
        for service in "${services[@]}"; do
            if docker ps --filter "name=$service" --filter "health=healthy" --format "{{.Names}}" | grep -q "$service"; then
                ((healthy_count++))
            fi
        done
        
        if [[ $healthy_count -eq ${#services[@]} ]]; then
            success "All monitoring services are healthy"
            return 0
        fi
        
        log "Waiting for services to be healthy ($healthy_count/${#services[@]} ready)..."
        sleep 10
        ((wait_time += 10))
    done
    
    warning "Some services may not be fully healthy yet. Check docker-compose logs."
}

# Validate monitoring endpoints
validate_endpoints() {
    log "Validating monitoring endpoints..."
    
    local endpoints=(
        "http://localhost:9091/-/healthy:Prometheus"
        "http://localhost:3002/api/health:Grafana"
        "http://localhost:3101/ready:Loki"
        "http://localhost:9094/-/healthy:AlertManager"
        "http://localhost:9116/metrics:BlackBox Exporter"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r url name <<< "$endpoint_info"
        
        if curl -s -f "$url" > /dev/null 2>&1; then
            success "✓ $name is responding at $url"
        else
            warning "✗ $name is not responding at $url"
        fi
    done
}

# Display access information
show_access_info() {
    log "Monitoring stack deployed successfully!"
    echo
    echo "=== MONITORING ACCESS INFORMATION ==="
    echo
    echo "🔍 Grafana Dashboard:    http://localhost:3002"
    echo "   Username: admin"
    echo "   Password: pyairtable2025"
    echo
    echo "📊 Prometheus:           http://localhost:9091"
    echo "📋 AlertManager:         http://localhost:9094"
    echo "📝 Loki Logs:           http://localhost:3101"
    echo "🔬 BlackBox Exporter:   http://localhost:9116"
    echo "💾 Node Exporter:       http://localhost:9101"
    echo "🐳 cAdvisor:            http://localhost:8082"
    echo
    echo "=== GRAFANA DASHBOARDS ==="
    echo "• Service Overview:      http://localhost:3002/d/service-overview"
    echo "• Infrastructure:        http://localhost:3002/d/infrastructure-overview"
    echo "• Service Status:        http://localhost:3002/d/service-status-tracker"
    echo
    echo "=== USEFUL COMMANDS ==="
    echo "• View logs:             docker-compose -f docker-compose.monitoring-basic.yml logs -f"
    echo "• Stop monitoring:       docker-compose -f docker-compose.monitoring-basic.yml down"
    echo "• Restart monitoring:    docker-compose -f docker-compose.monitoring-basic.yml restart"
    echo
}

# Cleanup function
cleanup() {
    if [[ ${1:-} == "full" ]]; then
        log "Performing full cleanup..."
        docker-compose -f docker-compose.monitoring-basic.yml down -v
        docker system prune -f
        success "Full cleanup completed"
    else
        log "Stopping monitoring services..."
        docker-compose -f docker-compose.monitoring-basic.yml down
        success "Monitoring services stopped"
    fi
}

# Main execution
main() {
    log "Starting PyAirtable Basic Monitoring Deployment"
    echo
    
    # Handle cleanup if requested
    if [[ ${1:-} == "cleanup" ]]; then
        cleanup "${2:-}"
        exit 0
    fi
    
    # Deploy monitoring
    check_prerequisites
    setup_directories
    validate_config
    check_services
    deploy_monitoring
    wait_for_services
    validate_endpoints
    show_access_info
    
    success "Basic monitoring deployment completed successfully!"
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Run main function with all arguments
main "$@"