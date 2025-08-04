#!/bin/bash

# Setup PyAirtable test environment
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.test.yml"
PROJECT_NAME="pyairtable-test"
TIMEOUT=300

echo -e "${BLUE}Setting up PyAirtable Test Environment${NC}"
echo "========================================="

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    print_status "Checking Docker..."
    if ! docker --version > /dev/null 2>&1; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker compose version > /dev/null 2>&1; then
        print_error "Docker Compose is not available"
        exit 1
    fi

    if ! docker system info > /dev/null 2>&1; then
        print_error "Docker daemon is not running"
        exit 1
    fi

    print_status "Docker is ready"
}

# Function to cleanup existing test environment
cleanup_existing() {
    print_status "Cleaning up existing test environment..."
    
    # Stop and remove containers
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME down --volumes --remove-orphans 2>/dev/null || true
    
    # Remove test volumes
    docker volume rm \
        ${PROJECT_NAME}_postgres-test-data \
        ${PROJECT_NAME}_rabbitmq-test-data \
        ${PROJECT_NAME}_test-reports 2>/dev/null || true
    
    # Remove test network
    docker network rm ${PROJECT_NAME}_test-network 2>/dev/null || true
    
    print_status "Cleanup completed"
}

# Function to build test images
build_images() {
    print_status "Building test images..."
    
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME build --no-cache --parallel
    
    if [ $? -ne 0 ]; then
        print_error "Failed to build test images"
        exit 1
    fi
    
    print_status "Test images built successfully"
}

# Function to start infrastructure services
start_infrastructure() {
    print_status "Starting infrastructure services..."
    
    # Start database, cache, and message queue first
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d \
        postgres-test \
        redis-test \
        rabbitmq-test \
        mock-airtable-api \
        mock-openai-api
    
    # Wait for services to be healthy
    print_status "Waiting for infrastructure services to be ready..."
    
    local services=("postgres-test" "redis-test" "rabbitmq-test")
    local max_attempts=60
    local attempt=0
    
    for service in "${services[@]}"; do
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps --filter "status=running" --format json | jq -r ".[].Name" | grep -q "$service"; then
                health=$(docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps --format json | jq -r ".[] | select(.Name | contains(\"$service\")) | .Health")
                if [ "$health" = "healthy" ] || [ "$health" = "" ]; then
                    print_status "$service is ready"
                    break
                fi
            fi
            
            attempt=$((attempt + 1))
            if [ $attempt -eq $max_attempts ]; then
                print_error "$service failed to become ready within timeout"
                exit 1
            fi
            
            sleep 2
        done
    done
    
    print_status "Infrastructure services are ready"
}

# Function to run database migrations
run_migrations() {
    print_status "Running database migrations..."
    
    # Wait a bit more for postgres to be fully ready
    sleep 5
    
    # Run migrations using the postgres container
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T postgres-test psql -U test_user -d pyairtable_test -c "
        CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";
        CREATE EXTENSION IF NOT EXISTS \"pg_stat_statements\";
        CREATE EXTENSION IF NOT EXISTS \"pg_trgm\";
    " || print_warning "Some extensions may already exist"
    
    # Apply schema migrations if they exist
    if [ -d "../migrations" ]; then
        print_status "Applying schema migrations..."
        for migration in ../migrations/*.sql; do
            if [ -f "$migration" ]; then
                docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T postgres-test \
                    psql -U test_user -d pyairtable_test -f "/docker-entrypoint-initdb.d/$(basename $migration)" || true
            fi
        done
    fi
    
    print_status "Database migrations completed"
}

# Function to start application services
start_services() {
    print_status "Starting application services..."
    
    # Start services in dependency order
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d \
        auth-service-test \
        airtable-gateway-test \
        mcp-server-test
    
    sleep 10
    
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME up -d \
        llm-orchestrator-test \
        api-gateway-test
    
    # Wait for services to be healthy
    print_status "Waiting for application services to be ready..."
    
    local services=("auth-service-test" "airtable-gateway-test" "mcp-server-test" "llm-orchestrator-test" "api-gateway-test")
    local max_attempts=60
    
    for service in "${services[@]}"; do
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps --filter "status=running" --format json | jq -r ".[].Name" | grep -q "$service"; then
                health=$(docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps --format json | jq -r ".[] | select(.Name | contains(\"$service\")) | .Health")
                if [ "$health" = "healthy" ] || [ "$health" = "" ]; then
                    print_status "$service is ready"
                    break
                fi
            fi
            
            attempt=$((attempt + 1))
            if [ $attempt -eq $max_attempts ]; then
                print_warning "$service may not be fully ready, continuing anyway"
                break
            fi
            
            sleep 3
        done
    done
    
    print_status "Application services started"
}

# Function to verify test environment
verify_environment() {
    print_status "Verifying test environment..."
    
    # Test database connection
    if docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T postgres-test pg_isready -U test_user -d pyairtable_test; then
        print_status "Database connection verified"
    else
        print_error "Database connection failed"
        return 1
    fi
    
    # Test Redis connection
    if docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T redis-test redis-cli -a test_password ping | grep -q "PONG"; then
        print_status "Redis connection verified"
    else
        print_error "Redis connection failed"
        return 1
    fi
    
    # Test API Gateway health
    local gateway_health=$(docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T api-gateway-test curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health || echo "000")
    if [ "$gateway_health" = "200" ]; then
        print_status "API Gateway health check passed"
    else
        print_warning "API Gateway health check returned status: $gateway_health"
    fi
    
    print_status "Environment verification completed"
}

# Function to show service status
show_status() {
    print_status "Test Environment Status:"
    echo "========================"
    
    docker compose -f $COMPOSE_FILE -p $PROJECT_NAME ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    print_status "Service URLs:"
    echo "  API Gateway:     http://localhost:8000"
    echo "  Auth Service:    http://localhost:8004" 
    echo "  LLM Orchestrator: http://localhost:8003"
    echo "  Airtable Gateway: http://localhost:8001"
    echo "  MCP Server:      http://localhost:8002"
    echo "  PostgreSQL:      localhost:5433"
    echo "  Redis:           localhost:6380"
    echo "  RabbitMQ:        http://localhost:15673"
    echo "  Prometheus:      http://localhost:9091"
    echo "  Grafana:         http://localhost:3001"
}

# Function to create test data
create_test_data() {
    if [ "$CREATE_TEST_DATA" = "true" ]; then
        print_status "Creating test data..."
        
        # Insert test users
        docker compose -f $COMPOSE_FILE -p $PROJECT_NAME exec -T postgres-test psql -U test_user -d pyairtable_test -c "
            INSERT INTO users (id, email, username, first_name, last_name, hashed_password, is_active, is_verified)
            VALUES 
                ('550e8400-e29b-41d4-a716-446655440000', 'test@example.com', 'testuser', 'Test', 'User', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewfEXvLLxEkCz5.q', true, true),
                ('550e8400-e29b-41d4-a716-446655440001', 'admin@example.com', 'adminuser', 'Admin', 'User', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewfEXvLLxEkCz5.q', true, true)
            ON CONFLICT (email) DO NOTHING;
        " 2>/dev/null || print_warning "Test users may already exist"
        
        print_status "Test data created"
    fi
}

# Main execution
main() {
    local command=${1:-"up"}
    
    case $command in
        "up"|"start")
            check_docker
            cleanup_existing
            build_images
            start_infrastructure
            run_migrations
            start_services
            verify_environment
            create_test_data
            show_status
            ;;
        "down"|"stop")
            print_status "Stopping test environment..."
            docker compose -f $COMPOSE_FILE -p $PROJECT_NAME down
            ;;
        "clean"|"cleanup")
            print_status "Cleaning up test environment..."
            cleanup_existing
            docker system prune -f --volumes
            ;;
        "status")
            show_status
            ;;
        "logs")
            local service=${2:-""}
            if [ -n "$service" ]; then
                docker compose -f $COMPOSE_FILE -p $PROJECT_NAME logs -f $service
            else
                docker compose -f $COMPOSE_FILE -p $PROJECT_NAME logs -f
            fi
            ;;
        "rebuild")
            cleanup_existing
            build_images
            print_status "Images rebuilt. Run '$0 up' to start services."
            ;;
        *)
            echo "Usage: $0 {up|down|clean|status|logs|rebuild}"
            echo ""
            echo "Commands:"
            echo "  up/start    - Start the test environment"
            echo "  down/stop   - Stop the test environment"
            echo "  clean       - Clean up all test resources"
            echo "  status      - Show service status"
            echo "  logs [svc]  - Show logs (optionally for specific service)"
            echo "  rebuild     - Rebuild test images"
            echo ""
            echo "Environment variables:"
            echo "  CREATE_TEST_DATA=true  - Create sample test data"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"