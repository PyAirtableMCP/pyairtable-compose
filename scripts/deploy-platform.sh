#!/bin/bash

# PyAirtable Platform Deployment Script
# Automated deployment with health checks and rollback capability

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="docker-compose.production.yml"
BACKUP_SUFFIX=$(date +"%Y%m%d_%H%M%S")
MAX_WAIT_TIME=300  # 5 minutes
HEALTH_CHECK_INTERVAL=10

# Deployment options
SKIP_BACKUP=false
SKIP_HEALTH_CHECK=false
DEPLOYMENT_MODE="production"  # production, staging, development
SERVICES_TO_DEPLOY=""  # Empty means all services

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "success")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "error")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "info")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if docker-compose file exists
check_compose_file() {
    cd "$PROJECT_ROOT"
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_status "error" "Docker compose file not found: $COMPOSE_FILE"
        return 1
    fi
    
    print_status "success" "Found docker compose file: $COMPOSE_FILE"
    return 0
}

# Function to validate environment
validate_environment() {
    print_status "info" "Validating environment..."
    
    cd "$PROJECT_ROOT"
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        print_status "error" "Environment file (.env) not found"
        print_status "info" "Run: ./scripts/setup-environment.sh"
        return 1
    fi
    
    # Source environment file
    set -a
    source .env
    set +a
    
    # Check critical variables
    local required_vars=(
        "API_KEY"
        "JWT_SECRET"
        "AIRTABLE_TOKEN"
        "GEMINI_API_KEY"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_status "error" "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    print_status "success" "Environment validation passed"
    return 0
}

# Function to backup current state
backup_current_state() {
    if [ "$SKIP_BACKUP" = true ]; then
        print_status "info" "Skipping backup (--skip-backup flag)"
        return 0
    fi
    
    print_status "info" "Creating backup of current state..."
    
    cd "$PROJECT_ROOT"
    
    # Create backup directory
    local backup_dir="backups/$BACKUP_SUFFIX"
    mkdir -p "$backup_dir"
    
    # Backup environment file
    if [ -f ".env" ]; then
        cp .env "$backup_dir/env.backup"
    fi
    
    # Backup docker-compose override
    if [ -f "docker-compose.override.yml" ]; then
        cp docker-compose.override.yml "$backup_dir/"
    fi
    
    # Export current container list
    docker-compose ps --services > "$backup_dir/services.list" 2>/dev/null || true
    
    # Backup database (if running)
    if docker-compose ps postgres | grep -q "Up"; then
        print_status "info" "Backing up database..."
        docker-compose exec -T postgres pg_dumpall -U postgres > "$backup_dir/database.sql" 2>/dev/null || {
            print_status "warning" "Database backup failed - continuing without backup"
        }
    fi
    
    print_status "success" "Backup created in $backup_dir"
    echo "$backup_dir" > .last_backup_path
}

# Function to pull latest images
pull_images() {
    print_status "info" "Pulling latest Docker images..."
    
    cd "$PROJECT_ROOT"
    
    if [ -n "$SERVICES_TO_DEPLOY" ]; then
        for service in $SERVICES_TO_DEPLOY; do
            docker-compose -f "$COMPOSE_FILE" pull "$service" || {
                print_status "warning" "Failed to pull image for $service"
            }
        done
    else
        docker-compose -f "$COMPOSE_FILE" pull || {
            print_status "warning" "Some images failed to pull - continuing with local images"
        }
    fi
    
    print_status "success" "Image pull completed"
}

# Function to start infrastructure services
start_infrastructure() {
    print_status "info" "Starting infrastructure services..."
    
    cd "$PROJECT_ROOT"
    
    # Start PostgreSQL and Redis first
    docker-compose -f "$COMPOSE_FILE" up -d postgres redis
    
    # Wait for infrastructure to be ready
    local wait_time=0
    while [ $wait_time -lt $MAX_WAIT_TIME ]; do
        if docker-compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U postgres > /dev/null 2>&1 && \
           docker-compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping > /dev/null 2>&1; then
            print_status "success" "Infrastructure services are ready"
            return 0
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
        wait_time=$((wait_time + HEALTH_CHECK_INTERVAL))
        print_status "info" "Waiting for infrastructure... (${wait_time}s/${MAX_WAIT_TIME}s)"
    done
    
    print_status "error" "Infrastructure services failed to start within $MAX_WAIT_TIME seconds"
    return 1
}

# Function to run database migrations
run_migrations() {
    print_status "info" "Running database migrations..."
    
    cd "$PROJECT_ROOT"
    
    # Check if migrations directory exists
    if [ -d "migrations" ]; then
        if [ -f "migrations/run-migrations.sh" ]; then
            cd migrations
            ./run-migrations.sh || {
                print_status "error" "Database migrations failed"
                return 1
            }
            cd ..
        else
            print_status "warning" "No migration script found, skipping..."
        fi
    fi
    
    print_status "success" "Database migrations completed"
}

# Function to deploy services in stages
deploy_services() {
    print_status "info" "Deploying services..."
    
    cd "$PROJECT_ROOT"
    
    if [ -n "$SERVICES_TO_DEPLOY" ]; then
        # Deploy specific services
        print_status "info" "Deploying specific services: $SERVICES_TO_DEPLOY"
        docker-compose -f "$COMPOSE_FILE" up -d $SERVICES_TO_DEPLOY
    else
        # Deploy all services in stages
        
        # Stage 1: Core services
        print_status "info" "Stage 1: Deploying core services..."
        docker-compose -f "$COMPOSE_FILE" up -d airtable-gateway mcp-server
        sleep 20
        
        # Stage 2: Go microservices
        print_status "info" "Stage 2: Deploying Go microservices..."
        docker-compose -f "$COMPOSE_FILE" up -d auth-service user-service workspace-service
        sleep 15
        
        # Stage 3: Platform services
        print_status "info" "Stage 3: Deploying platform services..."
        docker-compose -f "$COMPOSE_FILE" up -d platform-services automation-services llm-orchestrator
        sleep 15
        
        # Stage 4: API Gateway
        print_status "info" "Stage 4: Deploying API Gateway..."
        docker-compose -f "$COMPOSE_FILE" up -d api-gateway
        sleep 10
        
        # Stage 5: Frontend (optional)
        print_status "info" "Stage 5: Deploying frontend..."
        docker-compose -f "$COMPOSE_FILE" up -d frontend || {
            print_status "warning" "Frontend deployment failed - continuing without frontend"
        }
    fi
    
    print_status "success" "Service deployment completed"
}

# Function to wait for services to be healthy
wait_for_health() {
    if [ "$SKIP_HEALTH_CHECK" = true ]; then
        print_status "info" "Skipping health check (--skip-health-check flag)"
        return 0
    fi
    
    print_status "info" "Waiting for services to become healthy..."
    
    local wait_time=0
    local health_check_script="$SCRIPT_DIR/health-check.sh"
    
    while [ $wait_time -lt $MAX_WAIT_TIME ]; do
        if [ -f "$health_check_script" ]; then
            if "$health_check_script" --quick > /dev/null 2>&1; then
                print_status "success" "All services are healthy"
                return 0
            fi
        else
            # Fallback: check if containers are running
            local running_count=$(docker-compose -f "$COMPOSE_FILE" ps --services | wc -l)
            local healthy_count=$(docker-compose -f "$COMPOSE_FILE" ps | grep -c "Up" || echo "0")
            
            if [ "$healthy_count" -eq "$running_count" ]; then
                print_status "success" "All services are running"
                return 0
            fi
        fi
        
        sleep $HEALTH_CHECK_INTERVAL
        wait_time=$((wait_time + HEALTH_CHECK_INTERVAL))
        print_status "info" "Waiting for services to be healthy... (${wait_time}s/${MAX_WAIT_TIME}s)"
    done
    
    print_status "error" "Services failed to become healthy within $MAX_WAIT_TIME seconds"
    return 1
}

# Function to run smoke tests
run_smoke_tests() {
    print_status "info" "Running smoke tests..."
    
    local smoke_test_script="$SCRIPT_DIR/smoke-test.sh"
    
    if [ -f "$smoke_test_script" ]; then
        if "$smoke_test_script" --timeout 10; then
            print_status "success" "Smoke tests passed"
            return 0
        else
            print_status "error" "Smoke tests failed"
            return 1
        fi
    else
        print_status "warning" "No smoke test script found, skipping..."
        return 0
    fi
}

# Function to rollback deployment
rollback_deployment() {
    print_status "warning" "Rolling back deployment..."
    
    cd "$PROJECT_ROOT"
    
    # Stop current services
    docker-compose -f "$COMPOSE_FILE" down
    
    # Restore from backup if available
    if [ -f ".last_backup_path" ]; then
        local backup_path=$(cat .last_backup_path)
        if [ -d "$backup_path" ]; then
            print_status "info" "Restoring from backup: $backup_path"
            
            # Restore environment file
            if [ -f "$backup_path/env.backup" ]; then
                cp "$backup_path/env.backup" .env
            fi
            
            # Restore database
            if [ -f "$backup_path/database.sql" ]; then
                docker-compose -f "$COMPOSE_FILE" up -d postgres
                sleep 10
                docker-compose -f "$COMPOSE_FILE" exec -T postgres psql -U postgres < "$backup_path/database.sql"
            fi
            
            print_status "success" "Rollback completed"
        else
            print_status "error" "Backup path not found: $backup_path"
        fi
    else
        print_status "warning" "No backup available for rollback"
    fi
}

# Function to show deployment status
show_deployment_status() {
    print_status "info" "Deployment Status"
    echo "=================="
    
    cd "$PROJECT_ROOT"
    
    # Show container status
    docker-compose -f "$COMPOSE_FILE" ps
    
    echo ""
    
    # Show service URLs
    echo "Service URLs:"
    echo "  - API Gateway: http://localhost:8080"
    echo "  - Frontend: http://localhost:3000"
    echo "  - Prometheus: http://localhost:9090"
    
    # Show logs location
    echo ""
    echo "To view logs:"
    echo "  docker-compose -f $COMPOSE_FILE logs -f [service-name]"
    
    # Show health check command
    echo ""
    echo "To check health:"
    echo "  ./scripts/health-check.sh"
}

# Function to cleanup old backups
cleanup_old_backups() {
    print_status "info" "Cleaning up old backups..."
    
    cd "$PROJECT_ROOT"
    
    if [ -d "backups" ]; then
        # Keep only last 5 backups
        find backups -maxdepth 1 -type d -name "20*" | sort -r | tail -n +6 | xargs rm -rf
        print_status "success" "Old backups cleaned up"
    fi
}

# Main deployment function
main() {
    echo -e "${BLUE}🚀 PyAirtable Platform Deployment${NC}"
    echo "=================================="
    echo "Mode: $DEPLOYMENT_MODE"
    echo "Compose file: $COMPOSE_FILE"
    echo "Started at: $(date)"
    echo ""
    
    # Pre-deployment checks
    log "Starting pre-deployment checks..."
    
    if ! check_compose_file; then
        exit 1
    fi
    
    if ! validate_environment; then
        exit 1
    fi
    
    # Create backup
    log "Creating backup..."
    if ! backup_current_state; then
        print_status "error" "Backup failed"
        exit 1
    fi
    
    # Pull latest images
    log "Pulling images..."
    pull_images
    
    # Start deployment
    log "Starting deployment..."
    
    # Deploy infrastructure
    if ! start_infrastructure; then
        print_status "error" "Infrastructure deployment failed"
        rollback_deployment
        exit 1
    fi
    
    # Run migrations
    if ! run_migrations; then
        print_status "error" "Database migration failed"
        rollback_deployment
        exit 1
    fi
    
    # Deploy services
    if ! deploy_services; then
        print_status "error" "Service deployment failed"
        rollback_deployment
        exit 1
    fi
    
    # Wait for health
    if ! wait_for_health; then
        print_status "error" "Health check failed"
        rollback_deployment
        exit 1
    fi
    
    # Run smoke tests
    if ! run_smoke_tests; then
        print_status "error" "Smoke tests failed"
        
        read -p "Continue despite test failures? (y/N): " continue_anyway
        if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
            rollback_deployment
            exit 1
        fi
    fi
    
    # Success!
    log "Deployment completed successfully!"
    print_status "success" "PyAirtable platform deployed successfully!"
    
    show_deployment_status
    cleanup_old_backups
    
    echo ""
    echo "🎉 Deployment Complete!"
    echo "Access your platform at: http://localhost:8080"
}

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "PyAirtable Platform Deployment Script"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  --mode <mode>             Deployment mode (production|staging|development)"
    echo "  --compose-file <file>     Docker compose file to use"
    echo "  --services <list>         Space-separated list of services to deploy"
    echo "  --skip-backup             Skip backup creation"
    echo "  --skip-health-check       Skip health check verification"
    echo "  --skip-tests              Skip smoke tests"
    echo "  --rollback                Rollback to last backup"
    echo ""
    echo "Examples:"
    echo "  $0                        # Full deployment"
    echo "  $0 --mode staging         # Staging deployment"
    echo "  $0 --services \"api-gateway auth-service\"  # Deploy specific services"
    echo "  $0 --rollback             # Rollback deployment"
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            DEPLOYMENT_MODE="$2"
            shift 2
            ;;
        --compose-file)
            COMPOSE_FILE="$2"
            shift 2
            ;;
        --services)
            SERVICES_TO_DEPLOY="$2"
            shift 2
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-health-check)
            SKIP_HEALTH_CHECK=true
            shift
            ;;
        --skip-tests)
            SKIP_HEALTH_CHECK=true
            shift
            ;;
        --rollback)
            rollback_deployment
            exit $?
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set compose file based on mode
case $DEPLOYMENT_MODE in
    "development")
        COMPOSE_FILE="docker-compose.yml"
        ;;
    "staging")
        COMPOSE_FILE="docker-compose.staging.yml"
        ;;
    "production")
        COMPOSE_FILE="docker-compose.production.yml"
        ;;
    *)
        print_status "error" "Invalid deployment mode: $DEPLOYMENT_MODE"
        exit 1
        ;;
esac

# Run main function
main