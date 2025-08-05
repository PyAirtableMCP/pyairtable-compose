#!/bin/bash

# PyAirtable Local Development Startup Script
# Optimized for MacBook Air M2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.local.yml"
ENV_FILE=".env.local"

# Function to print colored output
print_status() {
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

# Function to check system resources
check_system_resources() {
    print_status "Checking system resources..."
    
    # Check available memory
    available_memory=$(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024}')
    print_status "Available memory: ${available_memory}GB"
    
    if (( $(echo "$available_memory < 8" | bc -l) )); then
        print_warning "Less than 8GB RAM available. Consider closing other applications."
    fi
    
    # Check Docker Desktop status
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    print_success "System resources check completed"
}

# Function to setup local DNS
setup_local_dns() {
    print_status "Setting up local DNS..."
    
    # Check if entries already exist
    if ! grep -q "pyairtable.local" /etc/hosts; then
        print_status "Adding local DNS entries..."
        echo "127.0.0.1 pyairtable.local" | sudo tee -a /etc/hosts
        echo "127.0.0.1 monitoring.local" | sudo tee -a /etc/hosts
        print_success "DNS entries added"
    else
        print_status "DNS entries already exist"
    fi
}

# Function to create necessary directories
create_directories() {
    print_status "Creating necessary directories..."
    
    directories=(
        "logs"
        "postgres/init"
        "monitoring/grafana/provisioning/datasources"
        "monitoring/grafana/provisioning/dashboards"
        "monitoring/grafana/dashboards"
        "monitoring/prometheus/rules"
        "nginx/certs"
        "nginx/conf.d"
        "data/postgres"
        "data/redis"
        "data/loki"
        "data/tempo"
        "data/mimir"
        "data/grafana"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done
    
    print_success "Directories created"
}

# Function to configure Docker Desktop for optimal performance
configure_docker() {
    print_status "Checking Docker Desktop configuration..."
    
    # Get current Docker Desktop settings
    docker_memory=$(docker system info --format '{{.MemTotal}}' 2>/dev/null | awk '{print $1/1024/1024/1024}')
    
    if [ -n "$docker_memory" ]; then
        print_status "Docker memory allocation: ${docker_memory}GB"
        
        if (( $(echo "$docker_memory < 6" | bc -l) )); then
            print_warning "Docker Desktop has less than 6GB allocated."
            print_warning "Recommend allocating 8GB for optimal performance."
            print_warning "Go to Docker Desktop > Settings > Resources > Advanced"
        fi
    fi
    
    print_success "Docker configuration check completed"
}

# Function to start services in phases
start_services() {
    print_status "Starting PyAirtable local environment..."
    
    # Phase 1: Infrastructure services
    print_status "Phase 1: Starting infrastructure services..."
    docker-compose -f $COMPOSE_FILE up -d postgres redis
    
    # Wait for databases to be ready
    print_status "Waiting for databases to be ready..."
    sleep 10
    
    # Health check for PostgreSQL
    max_attempts=30
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if docker-compose -f $COMPOSE_FILE exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
            print_success "PostgreSQL is ready"
            break
        fi
        print_status "Waiting for PostgreSQL... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "PostgreSQL failed to start"
        exit 1
    fi
    
    # Health check for Redis
    attempt=1
    while [ $attempt -le $max_attempts ]; do
        if docker-compose -f $COMPOSE_FILE exec -T redis redis-cli ping >/dev/null 2>&1; then
            print_success "Redis is ready"
            break
        fi
        print_status "Waiting for Redis... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    # Phase 2: Monitoring stack
    print_status "Phase 2: Starting monitoring stack..."
    docker-compose -f $COMPOSE_FILE up -d loki tempo mimir prometheus
    sleep 5
    
    # Phase 3: Application services
    print_status "Phase 3: Starting application services..."
    docker-compose -f $COMPOSE_FILE up -d pyairtable-api pyairtable-worker pyairtable-scheduler pyairtable-sync pyairtable-webhook
    sleep 10
    
    # Phase 4: Frontend and ingress
    print_status "Phase 4: Starting frontend and ingress..."
    docker-compose -f $COMPOSE_FILE up -d pyairtable-frontend grafana nginx
    
    print_success "All services started"
}

# Function to display service status
show_status() {
    print_status "Service Status:"
    docker-compose -f $COMPOSE_FILE ps
    
    echo
    print_status "Service URLs:"
    echo "  Frontend:     http://pyairtable.local"
    echo "  API:          http://localhost:8000"
    echo "  Grafana:      http://monitoring.local"
    echo "  Prometheus:   http://localhost:9090"
    echo "  Loki:         http://localhost:3100"
    echo "  Tempo:        http://localhost:3200"
    echo "  Mimir:        http://localhost:9009"
    
    echo
    print_status "Database Access:"
    echo "  PostgreSQL:   localhost:5432 (postgres/postgres)"
    echo "  Redis:        localhost:6379"
}

# Function to run health checks
health_check() {
    print_status "Running health checks..."
    
    services=("pyairtable-api:8000" "pyairtable-frontend:3000" "grafana:3000")
    
    for service in "${services[@]}"; do
        service_name=$(echo $service | cut -d':' -f1)
        port=$(echo $service | cut -d':' -f2)
        
        if curl -s -f "http://localhost:$port" >/dev/null; then
            print_success "$service_name is healthy"
        else
            print_warning "$service_name may not be ready yet"
        fi
    done
}

# Function to show resource usage
show_resource_usage() {
    print_status "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════╗"
    echo "║        PyAirtable Local Development           ║"
    echo "║         MacBook Air M2 Optimized              ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check if environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        print_warning "Environment file $ENV_FILE not found. Using defaults."
    fi
    
    check_system_resources
    configure_docker
    setup_local_dns
    create_directories
    start_services
    
    # Wait for services to stabilize
    print_status "Waiting for services to stabilize..."
    sleep 30
    
    show_status
    health_check
    
    echo
    print_success "PyAirtable local environment is ready!"
    print_status "To stop: docker-compose -f $COMPOSE_FILE down"
    print_status "To view logs: docker-compose -f $COMPOSE_FILE logs -f [service-name]"
    print_status "To show resource usage: ./scripts/show-resources.sh"
    
    # Optional: Open browser
    read -p "Open frontend in browser? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "http://pyairtable.local"
    fi
}

# Handle script arguments
case "${1:-start}" in
    "start")
        main
        ;;
    "stop")
        print_status "Stopping all services..."
        docker-compose -f $COMPOSE_FILE down
        print_success "All services stopped"
        ;;
    "restart")
        print_status "Restarting all services..."
        docker-compose -f $COMPOSE_FILE down
        sleep 5
        main
        ;;
    "status")
        show_status
        ;;
    "health")
        health_check
        ;;
    "resources")
        show_resource_usage
        ;;
    "logs")
        service_name=${2:-}
        if [ -n "$service_name" ]; then
            docker-compose -f $COMPOSE_FILE logs -f "$service_name"
        else
            docker-compose -f $COMPOSE_FILE logs -f
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|health|resources|logs [service-name]}"
        exit 1
        ;;
esac