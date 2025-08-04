#!/bin/bash

# PyAirtable Platform Observability Stack Deployment Script
# Comprehensive observability infrastructure with cost optimization

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.observability.yml"
ENV_FILE="$PROJECT_ROOT/.env"

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    # Check available disk space (minimum 10GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 10485760 ]; then  # 10GB in KB
        warning "Less than 10GB of disk space available. Observability stack may require more space."
    fi
    
    # Check available memory (minimum 4GB)
    available_memory=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_memory" -lt 4096 ]; then
        warning "Less than 4GB of memory available. Observability stack may require more memory."
    fi
    
    success "Prerequisites check completed"
}

# Create required directories
create_directories() {
    log "Creating required directories..."
    
    local dirs=(
        "$PROJECT_ROOT/monitoring/prometheus"
        "$PROJECT_ROOT/monitoring/grafana/dashboards"
        "$PROJECT_ROOT/monitoring/grafana/datasources"
        "$PROJECT_ROOT/monitoring/otel"
        "$PROJECT_ROOT/monitoring/kibana"
        "$PROJECT_ROOT/monitoring/logstash/pipeline"
        "$PROJECT_ROOT/monitoring/logstash/config"
        "$PROJECT_ROOT/monitoring/filebeat"
        "$PROJECT_ROOT/monitoring/alertmanager"
        "$PROJECT_ROOT/data/prometheus"
        "$PROJECT_ROOT/data/grafana"
        "$PROJECT_ROOT/data/elasticsearch"
        "$PROJECT_ROOT/data/alertmanager"
        "$PROJECT_ROOT/logs/observability"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        log "Created directory: $dir"
    done
    
    success "Directories created"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    if [ ! -f "$ENV_FILE" ]; then
        log "Creating .env file with default values..."
        cat > "$ENV_FILE" << EOF
# PyAirtable Platform Environment Configuration
ENVIRONMENT=development
COMPOSE_PROJECT_NAME=pyairtable

# Database Configuration
POSTGRES_DB=pyairtable
POSTGRES_USER=pyairtable
POSTGRES_PASSWORD=pyairtable_dev_password

# Redis Configuration
REDIS_PASSWORD=redis_dev_password

# Observability Configuration
GRAFANA_ADMIN_PASSWORD=admin123
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
JAEGER_ENDPOINT=http://jaeger-all-in-one:14268/api/traces

# Alerting Configuration
SMTP_HOST=localhost:587
ALERT_FROM_EMAIL=alerts@pyairtable.local
SMTP_USERNAME=
SMTP_PASSWORD=
SLACK_WEBHOOK_URL=
PAGERDUTY_SERVICE_KEY=

# Email Configuration
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
EOF
        warning "Created default .env file. Please review and update with your specific configuration."
    else
        log "Using existing .env file"
    fi
    
    success "Environment setup completed"
}

# Setup file permissions
setup_permissions() {
    log "Setting up file permissions..."
    
    # Elasticsearch data directory permissions
    if [ -d "$PROJECT_ROOT/data/elasticsearch" ]; then
        sudo chown -R 1000:1000 "$PROJECT_ROOT/data/elasticsearch" || {
            warning "Could not set Elasticsearch permissions. You may need to run: sudo chown -R 1000:1000 $PROJECT_ROOT/data/elasticsearch"
        }
    fi
    
    # Grafana data directory permissions
    if [ -d "$PROJECT_ROOT/data/grafana" ]; then
        sudo chown -R 472:472 "$PROJECT_ROOT/data/grafana" || {
            warning "Could not set Grafana permissions. You may need to run: sudo chown -R 472:472 $PROJECT_ROOT/data/grafana"
        }
    fi
    
    success "Permissions setup completed"
}

# Validate configuration files
validate_configs() {
    log "Validating configuration files..."
    
    local config_files=(
        "$PROJECT_ROOT/monitoring/prometheus/prometheus.yml"
        "$PROJECT_ROOT/monitoring/grafana/datasources/datasources.yml"
        "$PROJECT_ROOT/monitoring/otel/otel-collector-config.yml"
        "$PROJECT_ROOT/monitoring/logstash/config/logstash.yml"
        "$PROJECT_ROOT/monitoring/filebeat/filebeat.yml"
        "$PROJECT_ROOT/monitoring/alertmanager/alertmanager.yml"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ ! -f "$config_file" ]; then
            error "Required configuration file not found: $config_file"
            exit 1
        fi
        log "Validated: $config_file"
    done
    
    success "Configuration validation completed"
}

# Deploy observability stack
deploy_stack() {
    log "Deploying observability stack..."
    
    # Source environment variables
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    fi
    
    # Pull latest images
    log "Pulling Docker images..."
    docker-compose -f "$COMPOSE_FILE" pull
    
    # Start services in order
    log "Starting infrastructure services..."
    docker-compose -f "$COMPOSE_FILE" up -d elasticsearch redis
    
    # Wait for Elasticsearch to be ready
    log "Waiting for Elasticsearch to be ready..."
    timeout=120
    counter=0
    while ! curl -s http://localhost:9200/_cluster/health &> /dev/null; do
        sleep 5
        counter=$((counter + 5))
        if [ $counter -ge $timeout ]; then
            error "Elasticsearch failed to start within $timeout seconds"
            exit 1
        fi
        echo -n "."
    done
    echo
    success "Elasticsearch is ready"
    
    # Start remaining services
    log "Starting observability services..."
    docker-compose -f "$COMPOSE_FILE" up -d
    
    success "Observability stack deployed"
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    local services=(
        "Prometheus:http://localhost:9090/-/ready"
        "Grafana:http://localhost:3001/api/health"
        "Jaeger:http://localhost:16686/api/services"
        "Kibana:http://localhost:5601/api/status"
        "AlertManager:http://localhost:9093/-/ready"
    )
    
    for service_info in "${services[@]}"; do
        IFS=":" read -r service_name service_url <<< "$service_info"
        log "Waiting for $service_name..."
        
        timeout=180
        counter=0
        while ! curl -s "$service_url" &> /dev/null; do
            sleep 5
            counter=$((counter + 5))
            if [ $counter -ge $timeout ]; then
                warning "$service_name is not responding after $timeout seconds"
                break
            fi
            echo -n "."
        done
        echo
        
        if curl -s "$service_url" &> /dev/null; then
            success "$service_name is ready"
        else
            warning "$service_name may not be fully ready"
        fi
    done
}

# Setup initial configurations
setup_initial_configs() {
    log "Setting up initial configurations..."
    
    # Create Elasticsearch index templates
    log "Creating Elasticsearch index templates..."
    curl -X PUT "localhost:9200/_index_template/pyairtable-logs" \
        -H "Content-Type: application/json" \
        -d '{
            "index_patterns": ["pyairtable-logs-*"],
            "template": {
                "settings": {
                    "number_of_shards": 1,
                    "number_of_replicas": 0,
                    "refresh_interval": "5s"
                },
                "mappings": {
                    "properties": {
                        "@timestamp": {"type": "date"},
                        "service": {
                            "properties": {
                                "name": {"type": "keyword"},
                                "tier": {"type": "keyword"}
                            }
                        },
                        "log_level": {"type": "keyword"},
                        "message": {"type": "text"},
                        "trace": {
                            "properties": {
                                "id": {"type": "keyword"},
                                "span_id": {"type": "keyword"}
                            }
                        }
                    }
                }
            }
        }' || warning "Failed to create Elasticsearch index template"
    
    # Create Kibana index patterns (may need to wait for Kibana to fully start)
    sleep 30
    log "Creating Kibana index patterns..."
    curl -X POST "localhost:5601/api/saved_objects/index-pattern/pyairtable-logs" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "pyairtable-logs-*",
                "timeFieldName": "@timestamp"
            }
        }' || warning "Failed to create Kibana index pattern"
    
    success "Initial configurations setup completed"
}

# Show deployment summary
show_summary() {
    echo
    echo "=================================="
    echo "   OBSERVABILITY STACK DEPLOYED"
    echo "=================================="
    echo
    echo "🔍 Services Access URLs:"
    echo "  • Prometheus:     http://localhost:9090"
    echo "  • Grafana:        http://localhost:3001 (admin/admin123)"
    echo "  • Jaeger UI:      http://localhost:16686"
    echo "  • Kibana:         http://localhost:5601"
    echo "  • Elasticsearch:  http://localhost:9200"
    echo "  • AlertManager:   http://localhost:9093"
    echo
    echo "📊 Monitoring Capabilities:"
    echo "  • ✅ Metrics collection (Prometheus)"
    echo "  • ✅ Distributed tracing (Jaeger + OpenTelemetry)"
    echo "  • ✅ Log aggregation (ELK Stack)"
    echo "  • ✅ Alerting (AlertManager)"
    echo "  • ✅ Visualization (Grafana + Kibana)"
    echo "  • ✅ Cost tracking and optimization"
    echo
    echo "🚀 Next Steps:"
    echo "  1. Configure your services to send telemetry data"
    echo "  2. Import Grafana dashboards from monitoring/grafana/dashboards/"
    echo "  3. Set up alerting channels in AlertManager"
    echo "  4. Configure log shipping from your applications"
    echo
    echo "📚 Documentation:"
    echo "  • Monitoring setup: $PROJECT_ROOT/docs/monitoring-setup.md"
    echo "  • Cost optimization: $PROJECT_ROOT/docs/cost-optimization.md"
    echo "  • Troubleshooting: $PROJECT_ROOT/docs/troubleshooting.md"
    echo
    echo "💡 Quick Health Check:"
    echo "  docker-compose -f $COMPOSE_FILE ps"
    echo
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check the logs above for details."
        echo
        echo "🔧 Troubleshooting Commands:"
        echo "  • Check services: docker-compose -f $COMPOSE_FILE ps"
        echo "  • View logs: docker-compose -f $COMPOSE_FILE logs [service_name]"
        echo "  • Restart stack: docker-compose -f $COMPOSE_FILE restart"
        echo "  • Remove stack: docker-compose -f $COMPOSE_FILE down -v"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    echo "🚀 PyAirtable Platform Observability Stack Deployment"
    echo "=================================================="
    echo
    
    check_prerequisites
    create_directories
    setup_environment
    setup_permissions
    validate_configs
    deploy_stack
    wait_for_services
    setup_initial_configs
    show_summary
    
    success "Observability stack deployment completed successfully!"
}

# Run main function
main "$@"