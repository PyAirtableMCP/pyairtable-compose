#!/bin/bash

# PyAirtable Platform - Observability Stack Setup Script
# Comprehensive setup for distributed tracing, metrics, and logging

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-development}
OBSERVABILITY_MODE=${OBSERVABILITY_MODE:-dev}
SKIP_DEPENDENCIES=${SKIP_DEPENDENCIES:-false}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin123}

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check available ports
    local ports=(3001 4317 4318 5044 5601 8080 8888 9090 9200 16686)
    for port in "${ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            print_warning "Port $port is already in use. This may cause conflicts."
        fi
    done
    
    print_success "Prerequisites check completed"
}

# Create necessary directories
create_directories() {
    print_info "Creating necessary directories..."
    
    local dirs=(
        "./monitoring/grafana/dashboards/platform"
        "./monitoring/grafana/dashboards/infrastructure"
        "./monitoring/grafana/dashboards/cost"
        "./monitoring/grafana/datasources"
        "./monitoring/prometheus"
        "./monitoring/otel"
        "./monitoring/logstash/pipeline"
        "./monitoring/logstash/config"
        "./monitoring/filebeat"
        "./monitoring/kibana"
        "./monitoring/alertmanager"
        "./observability"
        "./python-services/shared/telemetry"
        "./logs"
        "./data/prometheus"
        "./data/grafana"
        "./data/elasticsearch"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    print_success "Directories created"
}

# Generate configuration files
generate_configs() {
    print_info "Generating configuration files..."
    
    # Create Grafana datasources configuration
    cat > ./monitoring/grafana/datasources/datasources.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-dev:9090
    isDefault: true
    uid: prometheus
    
  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger-dev:16686
    uid: jaeger
    
  - name: Elasticsearch
    type: elasticsearch
    access: proxy
    url: http://elasticsearch-dev:9200
    database: "pyairtable-logs-*"
    uid: elasticsearch
    jsonData:
      interval: Daily
      timeField: "@timestamp"
      esVersion: "8.0.0"
EOF

    # Create Grafana dashboards configuration
    cat > ./monitoring/grafana/dashboards/dashboards.yml << EOF
apiVersion: 1

providers:
  - name: 'PyAirtable Platform'
    folder: 'PyAirtable'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/platform
      
  - name: 'Infrastructure'
    folder: 'Infrastructure'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/infrastructure
      
  - name: 'Cost Optimization'
    folder: 'Cost'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/cost
EOF

    # Create Filebeat configuration
    cat > ./monitoring/filebeat/filebeat.yml << EOF
filebeat.inputs:
- type: container
  paths:
    - '/var/lib/docker/containers/*/*.log'
  processors:
    - add_docker_metadata:
        host: "unix:///var/run/docker.sock"
    - decode_json_fields:
        fields: ["message"]
        target: ""
        overwrite_keys: true

output.logstash:
  hosts: ["logstash-dev:5044"]

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
EOF

    # Create Logstash configuration
    cat > ./monitoring/logstash/config/logstash.yml << EOF
http.host: "0.0.0.0"
xpack.monitoring.enabled: false
path.config: /usr/share/logstash/pipeline
EOF

    print_success "Configuration files generated"
}

# Install dependencies
install_dependencies() {
    if [[ "$SKIP_DEPENDENCIES" == "true" ]]; then
        print_info "Skipping dependency installation"
        return
    fi
    
    print_info "Installing Python dependencies..."
    
    # Create requirements file for telemetry library
    cat > ./python-services/shared/requirements.txt << EOF
opentelemetry-api>=1.20.0
opentelemetry-sdk>=1.20.0
opentelemetry-exporter-otlp-proto-grpc>=1.20.0
opentelemetry-instrumentation-fastapi>=0.41b0
opentelemetry-instrumentation-flask>=0.41b0
opentelemetry-instrumentation-requests>=0.41b0
opentelemetry-instrumentation-psycopg2>=0.41b0
opentelemetry-instrumentation-redis>=0.41b0
opentelemetry-semantic-conventions>=0.41b0
opentelemetry-propagator-b3>=1.20.0
opentelemetry-propagator-jaeger>=1.20.0
opentelemetry-trace>=1.0.0
opentelemetry-baggage>=1.0.0
EOF
    
    print_success "Dependencies configuration completed"
}

# Start observability stack
start_observability_stack() {
    print_info "Starting observability stack in $OBSERVABILITY_MODE mode..."
    
    local compose_file
    if [[ "$OBSERVABILITY_MODE" == "dev" ]]; then
        compose_file="docker-compose.observability-dev.yml"
    else
        compose_file="docker-compose.observability.yml"
    fi
    
    # Export environment variables
    export GRAFANA_ADMIN_PASSWORD
    export ENVIRONMENT
    
    # Pull images first
    print_info "Pulling Docker images..."
    docker-compose -f "$compose_file" pull
    
    # Start services
    print_info "Starting services..."
    docker-compose -f "$compose_file" up -d
    
    print_success "Observability stack started"
}

# Wait for services to be ready
wait_for_services() {
    print_info "Waiting for services to be ready..."
    
    local services=(
        "http://localhost:9090/-/healthy:Prometheus"
        "http://localhost:3001/api/health:Grafana"
        "http://localhost:16686/:Jaeger"
        "http://localhost:9200/_cluster/health:Elasticsearch"
    )
    
    for service in "${services[@]}"; do
        local url="${service%:*}"
        local name="${service#*:}"
        
        print_info "Waiting for $name to be ready..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if curl -s -f "$url" > /dev/null 2>&1; then
                print_success "$name is ready"
                break
            fi
            
            if [[ $attempt -eq $max_attempts ]]; then
                print_warning "$name is not responding after $max_attempts attempts"
                break
            fi
            
            echo -n "."
            sleep 2
            ((attempt++))
        done
    done
    
    print_success "Service readiness check completed"
}

# Configure Grafana dashboards
setup_grafana_dashboards() {
    print_info "Setting up Grafana dashboards..."
    
    # Wait a bit more for Grafana to be fully ready
    sleep 10
    
    # Import dashboards via API
    local grafana_url="http://admin:${GRAFANA_ADMIN_PASSWORD}@localhost:3001"
    local dashboard_files=(
        "./monitoring/grafana/dashboards/platform/request-flow-dashboard.json"
    )
    
    for dashboard_file in "${dashboard_files[@]}"; do
        if [[ -f "$dashboard_file" ]]; then
            print_info "Importing dashboard: $(basename "$dashboard_file")"
            
            # Wrap dashboard JSON in import structure
            local import_json=$(jq -n --argjson dashboard "$(cat "$dashboard_file")" '{
                "dashboard": $dashboard,
                "overwrite": true,
                "inputs": [],
                "folderId": 0
            }')
            
            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$import_json" \
                "$grafana_url/api/dashboards/import" > /dev/null || print_warning "Failed to import $(basename "$dashboard_file")"
        fi
    done
    
    print_success "Grafana dashboards configured"
}

# Setup Kibana index patterns
setup_kibana_indices() {
    print_info "Setting up Kibana index patterns..."
    
    # Wait for Elasticsearch to have some data
    sleep 15
    
    local kibana_url="http://localhost:5601"
    
    # Create index pattern for application logs
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d '{
            "attributes": {
                "title": "pyairtable-logs-*",
                "timeFieldName": "@timestamp"
            }
        }' \
        "$kibana_url/api/saved_objects/index-pattern/pyairtable-logs" > /dev/null || print_warning "Failed to create Kibana index pattern"
    
    print_success "Kibana index patterns configured"
}

# Run health checks
run_health_checks() {
    print_info "Running health checks..."
    
    # Check Prometheus targets
    local prometheus_targets=$(curl -s "http://localhost:9090/api/v1/targets" | jq -r '.data.activeTargets | length')
    print_info "Prometheus is monitoring $prometheus_targets targets"
    
    # Check Jaeger services
    local jaeger_services=$(curl -s "http://localhost:16686/api/services" | jq -r '.data | length')
    print_info "Jaeger has $jaeger_services services registered"
    
    # Check Elasticsearch indices
    local es_indices=$(curl -s "http://localhost:9200/_cat/indices?format=json" | jq -r 'length')
    print_info "Elasticsearch has $es_indices indices"
    
    print_success "Health checks completed"
}

# Print access information
print_access_info() {
    print_success "Observability stack is ready!"
    echo
    print_info "Access URLs:"
    echo "  📊 Grafana (Dashboards):     http://localhost:3001 (admin/$GRAFANA_ADMIN_PASSWORD)"
    echo "  🔍 Prometheus (Metrics):     http://localhost:9090"
    echo "  🕸️  Jaeger (Tracing):        http://localhost:16686"
    echo "  📋 Kibana (Logs):           http://localhost:5601"
    echo "  🔎 Elasticsearch (Search):   http://localhost:9200"
    echo "  📈 cAdvisor (Containers):    http://localhost:8080"
    echo "  🖥️  Node Exporter (System):  http://localhost:9100"
    
    if [[ "$OBSERVABILITY_MODE" == "dev" ]]; then
        echo
        print_info "Development Tools:"
        echo "  📧 MailHog (Email Testing):  http://localhost:8025"
        echo "  🗃️  Redis Commander:         http://localhost:8081"
        echo "  🐘 pgAdmin (PostgreSQL):     http://localhost:8082"
        echo "  🌐 Envoy Proxy Admin:       http://localhost:9901"
    fi
    
    echo
    print_info "Next Steps:"
    echo "1. Configure your services to send telemetry data"
    echo "2. Check the example instrumentation in the documentation"
    echo "3. View request flows in Grafana dashboards"
    echo "4. Search logs in Kibana"
    echo "5. Trace requests in Jaeger"
    echo
    print_info "For troubleshooting, run: docker-compose -f $compose_file logs [service-name]"
}

# Main function
main() {
    echo "🚀 PyAirtable Platform - Observability Stack Setup"
    echo "=================================================="
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --mode)
                OBSERVABILITY_MODE="$2"
                shift 2
                ;;
            --skip-deps)
                SKIP_DEPENDENCIES="true"
                shift
                ;;
            --grafana-password)
                GRAFANA_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --environment ENV        Set environment (development|staging|production)"
                echo "  --mode MODE             Set observability mode (dev|production)"
                echo "  --skip-deps             Skip dependency installation"
                echo "  --grafana-password PWD  Set Grafana admin password"
                echo "  --help                  Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    print_info "Configuration:"
    echo "  Environment: $ENVIRONMENT"
    echo "  Mode: $OBSERVABILITY_MODE"
    echo "  Skip Dependencies: $SKIP_DEPENDENCIES"
    echo
    
    # Execute setup steps
    check_prerequisites
    create_directories
    generate_configs
    install_dependencies
    start_observability_stack
    wait_for_services
    setup_grafana_dashboards
    setup_kibana_indices
    run_health_checks
    print_access_info
    
    print_success "Setup completed successfully! 🎉"
}

# Run main function
main "$@"