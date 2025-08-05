#!/bin/bash

# PyAirtable Production Monitoring Deployment Script
# Deploys LGTM stack with comprehensive monitoring, alerting, and dashboards

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MONITORING_DIR="$SCRIPT_DIR"
DATA_ROOT="/opt/pyairtable/monitoring/data"
LOG_FILE="$MONITORING_DIR/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [$level] $message" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
trap 'error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! command -v docker-compose >/dev/null 2>&1; then
        error "docker-compose is not installed."
        exit 1
    fi
    
    # Check available disk space (need at least 10GB)
    local available_space=$(df "$MONITORING_DIR" | awk 'NR==2 {print $4}')
    local required_space=$((10 * 1024 * 1024)) # 10GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        error "Insufficient disk space. Need at least 10GB available."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Create necessary directories
setup_directories() {
    info "Setting up data directories..."
    
    sudo mkdir -p "$DATA_ROOT"/{minio,grafana,mimir,loki,tempo,alertmanager,alertmanager-backup,promtail,node-exporter}
    
    # Set proper permissions
    sudo chown -R "$(id -u):$(id -g)" "$DATA_ROOT"
    sudo chmod -R 755 "$DATA_ROOT"
    
    # Create additional directories for configuration
    mkdir -p "$MONITORING_DIR/logs"
    mkdir -p "$MONITORING_DIR/backup"
    
    success "Directories created successfully"
}

# Validate environment file
validate_environment() {
    info "Validating environment configuration..."
    
    local env_file="$MONITORING_DIR/.env.production.local"
    
    if [ ! -f "$env_file" ]; then
        warn "Production environment file not found. Creating from template..."
        cp "$MONITORING_DIR/.env.production" "$env_file"
        warn "Please edit $env_file with your actual credentials before proceeding."
        read -p "Press Enter after updating the environment file..."
    fi
    
    # Source environment file
    set -a
    source "$env_file"
    set +a
    
    # Validate critical variables
    local required_vars=(
        "MINIO_ROOT_USER"
        "MINIO_ROOT_PASSWORD"
        "GRAFANA_ADMIN_PASSWORD"
        "SMTP_HOST"
        "ALERT_FROM_EMAIL"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    success "Environment validation passed"
}

# Deploy LGTM stack
deploy_lgtm_stack() {
    info "Deploying LGTM stack..."
    
    cd "$MONITORING_DIR"
    
    # Pull latest images
    info "Pulling latest Docker images..."
    docker-compose -f docker-compose.production.yml pull
    
    # Start the stack
    info "Starting LGTM stack..."
    docker-compose -f docker-compose.production.yml up -d
    
    # Wait for services to be healthy
    info "Waiting for services to become healthy..."
    local max_wait=300
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local healthy_services=$(docker-compose -f docker-compose.production.yml ps --services | xargs -I {} docker-compose -f docker-compose.production.yml ps {} | grep -c "healthy" || true)
        local total_services=$(docker-compose -f docker-compose.production.yml ps --services | wc -l)
        
        if [ "$healthy_services" -eq "$total_services" ]; then
            success "All services are healthy"
            break
        fi
        
        info "Waiting for services to become healthy ($healthy_services/$total_services ready)..."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        error "Timeout waiting for services to become healthy"
        docker-compose -f docker-compose.production.yml ps
        exit 1
    fi
    
    success "LGTM stack deployed successfully"
}

# Configure Grafana dashboards
configure_dashboards() {
    info "Configuring Grafana dashboards..."
    
    # Wait for Grafana to be fully ready
    local grafana_url="http://localhost:3000"
    local max_wait=60
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if curl -s "$grafana_url/api/health" >/dev/null 2>&1; then
            break
        fi
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        error "Grafana did not become ready in time"
        exit 1
    fi
    
    # Import dashboards via API
    local dashboard_dir="$MONITORING_DIR/grafana/dashboards/production"
    
    for dashboard_file in "$dashboard_dir"/*.json; do
        if [ -f "$dashboard_file" ]; then
            local dashboard_name=$(basename "$dashboard_file" .json)
            info "Importing dashboard: $dashboard_name"
            
            # Create dashboard import payload
            local import_payload=$(jq -n --argjson dashboard "$(cat "$dashboard_file")" '{
                dashboard: $dashboard,
                overwrite: true,
                inputs: []
            }')
            
            # Import dashboard
            curl -X POST \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $GRAFANA_ADMIN_PASSWORD" \
                -d "$import_payload" \
                "$grafana_url/api/dashboards/import" >/dev/null 2>&1 || true
        fi
    done
    
    success "Grafana dashboards configured"
}

# Setup alerting rules
setup_alerting() {
    info "Setting up alerting rules..."
    
    # Copy alert rules to Mimir
    local alert_rules_file="$MONITORING_DIR/prometheus/alert-rules-production.yml"
    
    if [ -f "$alert_rules_file" ]; then
        # Upload rules to Mimir via API
        curl -X POST \
            -H "Content-Type: application/yaml" \
            -H "X-Scope-OrgID: pyairtable" \
            --data-binary "@$alert_rules_file" \
            "http://localhost:8080/api/v1/rules/pyairtable" >/dev/null 2>&1 || true
        
        success "Alert rules configured"
    else
        warn "Alert rules file not found: $alert_rules_file"
    fi
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    # Check service health
    local services=(
        "http://localhost:3000/api/health:Grafana"
        "http://localhost:3100/ready:Loki"
        "http://localhost:3200/ready:Tempo"
        "http://localhost:8080/ready:Mimir"
        "http://localhost:9093/-/healthy:AlertManager"
        "http://localhost:9000/minio/health/live:MinIO"
    )
    
    for service_info in "${services[@]}"; do
        local url="${service_info%:*}"
        local name="${service_info#*:}"
        
        if curl -s "$url" >/dev/null 2>&1; then
            success "$name is healthy"
        else
            error "$name health check failed"
        fi
    done
    
    # Check data ingestion
    info "Checking data ingestion..."
    
    # Test Loki ingestion
    local loki_query='http://localhost:3100/loki/api/v1/query?query=%7Bjob%3D~%22.*%22%7D'
    if curl -s "$loki_query" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        success "Loki is ingesting logs"
    else
        warn "Loki may not be ingesting logs yet"
    fi
    
    # Test Mimir ingestion
    local mimir_query='http://localhost:8080/prometheus/api/v1/query?query=up'
    if curl -s "$mimir_query" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        success "Mimir is ingesting metrics"
    else
        warn "Mimir may not be ingesting metrics yet"
    fi
    
    success "Deployment verification completed"
}

# Create backup script
create_backup_script() {
    info "Creating backup script..."
    
    cat > "$MONITORING_DIR/backup-monitoring-data.sh" << 'EOF'
#!/bin/bash

# PyAirtable Monitoring Data Backup Script

set -euo pipefail

BACKUP_DIR="/opt/pyairtable/monitoring/backup"
DATA_ROOT="/opt/pyairtable/monitoring/data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="monitoring_backup_$TIMESTAMP"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Stop services for consistent backup
echo "Stopping monitoring services..."
cd "$(dirname "$0")"
docker-compose -f docker-compose.production.yml stop

# Create backup
echo "Creating backup: $BACKUP_NAME"
tar -czf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" -C "$DATA_ROOT" .

# Start services
echo "Starting monitoring services..."
docker-compose -f docker-compose.production.yml start

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "monitoring_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/$BACKUP_NAME.tar.gz"
EOF
    
    chmod +x "$MONITORING_DIR/backup-monitoring-data.sh"
    
    success "Backup script created"
}

# Setup log rotation
setup_log_rotation() {
    info "Setting up log rotation..."
    
    cat > "/etc/logrotate.d/pyairtable-monitoring" << 'EOF'
/opt/pyairtable/monitoring/data/*/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        docker kill --signal=USR1 $(docker ps -q --filter name=pyairtable-monitoring) 2>/dev/null || true
    endscript
}
EOF
    
    success "Log rotation configured"
}

# Print deployment summary
print_deployment_summary() {
    success "PyAirtable Production Monitoring Deployment Complete!"
    echo
    echo "==================== DEPLOYMENT SUMMARY ===================="
    echo
    echo "🔍 Grafana Dashboard: http://localhost:3000"
    echo "   Username: ${GRAFANA_ADMIN_USER:-admin}"
    echo "   Password: $GRAFANA_ADMIN_PASSWORD"
    echo
    echo "📊 Available Dashboards:"
    echo "   - Service Health Overview"
    echo "   - Business Metrics"
    echo "   - Cost Tracking & LLM Usage"
    echo
    echo "🚨 AlertManager: http://localhost:9093"
    echo "📝 Loki Logs: http://localhost:3100"
    echo "🔍 Tempo Traces: http://localhost:3200"
    echo "📈 Mimir Metrics: http://localhost:8080"
    echo "💾 MinIO Storage: http://localhost:9001"
    echo
    echo "🔧 Management Commands:"
    echo "   View logs: docker-compose -f docker-compose.production.yml logs -f"
    echo "   Stop stack: docker-compose -f docker-compose.production.yml down"
    echo "   Backup data: ./backup-monitoring-data.sh"
    echo
    echo "📖 Documentation:"
    echo "   Runbooks: https://runbooks.pyairtable.com"
    echo "   Deployment logs: $LOG_FILE"
    echo
    echo "⚠️  Next Steps:"
    echo "   1. Configure external access (reverse proxy/ingress)"
    echo "   2. Set up SSL/TLS certificates"
    echo "   3. Configure backup automation"
    echo "   4. Test alert delivery channels"
    echo "   5. Update DNS records for monitoring domains"
    echo
    echo "========================================================="
}

# Main deployment function
main() {
    echo "🚀 Starting PyAirtable Production Monitoring Deployment"
    echo "Deployment log: $LOG_FILE"
    echo
    
    check_prerequisites
    setup_directories
    validate_environment
    deploy_lgtm_stack
    configure_dashboards
    setup_alerting
    verify_deployment
    create_backup_script
    setup_log_rotation
    print_deployment_summary
    
    success "Monitoring deployment completed successfully!"
}

# Run main function
main "$@"