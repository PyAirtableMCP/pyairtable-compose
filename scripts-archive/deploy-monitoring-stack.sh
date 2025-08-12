#!/bin/bash

# PyAirtable Monitoring Stack Deployment Script
# Deploys comprehensive observability stack with Prometheus, Grafana, Jaeger, Loki, and Alertmanager
# Supports both lightweight (Loki) and comprehensive (ELK) logging stacks

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.observability.yml"
ENV_FILE="${SCRIPT_DIR}/.env"

# Default configuration
DEFAULT_MODE="loki"  # Options: loki, elk, both
DEFAULT_RETENTION_DAYS="14"
DEFAULT_ADMIN_PASSWORD="admin123"

# Function to print colored output
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $*" ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log "ERROR" "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker daemon is not running"
        exit 1
    fi
    
    # Check available disk space (minimum 5GB)
    available_space=$(df / | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 5242880 ]; then  # 5GB in KB
        log "WARN" "Less than 5GB disk space available. Monitoring stack may consume significant storage."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Function to setup environment
setup_environment() {
    log "INFO" "Setting up environment..."
    
    # Create .env file if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        log "INFO" "Creating .env file with default values..."
        cat > "$ENV_FILE" << EOF
# PyAirtable Monitoring Stack Configuration

# Grafana Configuration
GRAFANA_ADMIN_PASSWORD=${DEFAULT_ADMIN_PASSWORD}

# Alert Manager Configuration
SMTP_HOST=localhost:587
ALERT_FROM_EMAIL=alerts@pyairtable.local
SMTP_USERNAME=
SMTP_PASSWORD=
SLACK_WEBHOOK_URL=
PAGERDUTY_SERVICE_KEY=

# Email Notifications
CRITICAL_EMAIL=ops@pyairtable.local
ONCALL_EMAIL=oncall@pyairtable.local
DBA_EMAIL=dba@pyairtable.local
SECURITY_EMAIL=security@pyairtable.local
FINOPS_EMAIL=finops@pyairtable.local
AI_TEAM_EMAIL=ai-team@pyairtable.local
BUSINESS_EMAIL=business@pyairtable.local

# Webhook Configuration
WEBHOOK_USERNAME=admin
WEBHOOK_PASSWORD=password

# Data Retention (days)
PROMETHEUS_RETENTION=${DEFAULT_RETENTION_DAYS}d
LOKI_RETENTION=${DEFAULT_RETENTION_DAYS}d

# Environment
ENVIRONMENT=development
EOF
        log "WARN" "Please edit $ENV_FILE with your specific configuration before running the stack"
    else
        log "INFO" "Using existing .env file"
    fi
}

# Function to create necessary directories
create_directories() {
    log "INFO" "Creating necessary directories..."
    
    local dirs=(
        "${SCRIPT_DIR}/monitoring/loki"
        "${SCRIPT_DIR}/monitoring/promtail"
        "${SCRIPT_DIR}/monitoring/grafana/dashboards/platform"
        "${SCRIPT_DIR}/monitoring/grafana/dashboards/infrastructure"
        "${SCRIPT_DIR}/monitoring/grafana/dashboards/cost"
        "${SCRIPT_DIR}/monitoring/prometheus"
        "${SCRIPT_DIR}/monitoring/alertmanager"
        "${SCRIPT_DIR}/monitoring/otel"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "DEBUG" "Created directory: $dir"
    done
}

# Function to check service health
check_service_health() {
    local service=$1
    local port=$2
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Checking health of $service (port $port)..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://localhost:$port" > /dev/null 2>&1; then
            log "INFO" "$service is healthy (attempt $attempt/$max_attempts)"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log "WARN" "$service health check failed after $max_attempts attempts"
            return 1
        fi
        
        log "DEBUG" "$service not ready yet (attempt $attempt/$max_attempts), waiting..."
        sleep 10
        attempt=$((attempt + 1))
    done
}

# Function to deploy monitoring stack
deploy_stack() {
    local mode=$1
    
    log "INFO" "Deploying monitoring stack in '$mode' mode..."
    
    # Build the docker-compose command
    local compose_cmd="docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE"
    
    case $mode in
        "loki")
            log "INFO" "Deploying with Loki (lightweight logging)"
            $compose_cmd up -d prometheus grafana jaeger-all-in-one otel-collector loki promtail alertmanager node-exporter cadvisor redis-exporter postgres-exporter
            ;;
        "elk")
            log "INFO" "Deploying with ELK stack (comprehensive logging)"
            $compose_cmd --profile elk up -d prometheus grafana jaeger-all-in-one otel-collector elasticsearch kibana logstash filebeat alertmanager node-exporter cadvisor redis-exporter postgres-exporter
            ;;
        "both")
            log "INFO" "Deploying with both Loki and ELK stack"
            $compose_cmd --profile elk up -d
            ;;
        *)
            log "ERROR" "Invalid deployment mode: $mode"
            exit 1
            ;;
    esac
    
    log "INFO" "Monitoring stack deployment initiated"
}

# Function to verify deployment
verify_deployment() {
    local mode=$1
    
    log "INFO" "Verifying deployment..."
    
    # Core services to check
    local core_services=(
        "prometheus:9090"
        "grafana:3001"
        "jaeger:16686"
        "alertmanager:9093"
    )
    
    # Mode-specific services
    case $mode in
        "loki"|"both")
            core_services+=("loki:3100")
            ;;
        "elk"|"both")
            core_services+=("elasticsearch:9200")
            core_services+=("kibana:5601")
            ;;
    esac
    
    local failed_services=()
    
    for service_port in "${core_services[@]}"; do
        IFS=':' read -r service port <<< "$service_port"
        if ! check_service_health "$service" "$port"; then
            failed_services+=("$service")
        fi
    done
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log "INFO" "All monitoring services are healthy!"
        return 0
    else
        log "ERROR" "The following services failed health checks: ${failed_services[*]}"
        return 1
    fi
}

# Function to show service URLs
show_service_urls() {
    log "INFO" "Monitoring Stack URLs:"
    echo
    echo "📊 Core Monitoring:"
    echo "  - Grafana:     http://localhost:3001 (admin/admin123)"
    echo "  - Prometheus:  http://localhost:9090"
    echo "  - AlertManager: http://localhost:9093"
    echo
    echo "🔍 Tracing & Logs:"
    echo "  - Jaeger:      http://localhost:16686"
    echo "  - Loki:        http://localhost:3100"
    if docker-compose -f "$COMPOSE_FILE" ps elasticsearch &> /dev/null; then
        echo "  - Kibana:      http://localhost:5601"
        echo "  - Elasticsearch: http://localhost:9200"
    fi
    echo
    echo "🔧 Infrastructure:"
    echo "  - Node Exporter: http://localhost:9100"
    echo "  - cAdvisor:    http://localhost:8080"
    echo "  - OTel Collector: http://localhost:8888"
    echo
}

# Function to show dashboard information
show_dashboards() {
    log "INFO" "Available Grafana Dashboards:"
    echo
    echo "Platform Dashboards:"
    echo "  - PyAirtable Platform Overview"
    echo "  - AI/LLM Cost Tracking"
    echo "  - Business Metrics"
    echo
    echo "Infrastructure Dashboards:"
    echo "  - Infrastructure Overview"
    echo "  - Container Resource Usage"
    echo "  - Database Performance"
    echo
    echo "Access dashboards at: http://localhost:3001"
    echo "Default credentials: admin/admin123"
}

# Function to show logs
show_logs() {
    local service=${1:-""}
    
    if [ -n "$service" ]; then
        log "INFO" "Showing logs for $service..."
        docker-compose -f "$COMPOSE_FILE" logs -f "$service"
    else
        log "INFO" "Showing logs for all monitoring services..."
        docker-compose -f "$COMPOSE_FILE" logs -f
    fi
}

# Function to stop the stack
stop_stack() {
    log "INFO" "Stopping monitoring stack..."
    docker-compose -f "$COMPOSE_FILE" down
    log "INFO" "Monitoring stack stopped"
}

# Function to cleanup (remove containers and volumes)
cleanup_stack() {
    log "WARN" "This will remove all monitoring containers and data volumes!"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Cleaning up monitoring stack..."
        docker-compose -f "$COMPOSE_FILE" down -v --remove-orphans
        log "INFO" "Cleanup completed"
    else
        log "INFO" "Cleanup cancelled"
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
PyAirtable Monitoring Stack Deployment Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    deploy [MODE]   Deploy the monitoring stack
                    MODE: loki (default), elk, both
    verify [MODE]   Verify deployment health
    urls            Show service URLs
    dashboards      Show available dashboards
    logs [SERVICE]  Show logs (optionally for specific service)
    stop            Stop the monitoring stack
    cleanup         Remove containers and volumes
    help            Show this help message

Examples:
    $0 deploy loki          # Deploy with Loki logging (lightweight)
    $0 deploy elk           # Deploy with ELK stack (comprehensive)
    $0 deploy both          # Deploy with both logging stacks
    $0 verify loki          # Verify Loki deployment
    $0 logs prometheus      # Show Prometheus logs
    $0 urls                 # Show all service URLs

Configuration:
    Edit .env file to customize settings before deployment.
    Default admin password: admin123
    Default retention: 14 days

EOF
}

# Main script logic
main() {
    local command=${1:-"help"}
    local mode=${2:-$DEFAULT_MODE}
    
    case $command in
        "deploy")
            check_prerequisites
            setup_environment
            create_directories
            deploy_stack "$mode"
            sleep 30  # Give services time to start
            if verify_deployment "$mode"; then
                show_service_urls
                show_dashboards
                log "INFO" "Monitoring stack deployed successfully!"
            else
                log "ERROR" "Deployment verification failed. Check logs with: $0 logs"
                exit 1
            fi
            ;;
        "verify")
            verify_deployment "$mode"
            ;;
        "urls")
            show_service_urls
            ;;
        "dashboards")
            show_dashboards
            ;;
        "logs")
            show_logs "$mode"
            ;;
        "stop")
            stop_stack
            ;;
        "cleanup")
            cleanup_stack
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# Run main function with all arguments
main "$@"