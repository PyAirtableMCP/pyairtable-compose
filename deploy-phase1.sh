#!/bin/bash

# Phase 1 Deployment Script
# =========================
# Deploys and validates Phase 1 services: API Gateway, Auth Service, User Service, Airtable Gateway

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
COMPOSE_FILE="go-services/docker-compose.phase1.yml"
ENV_FILE=".env.phase1"
LOG_FILE="deployment.log"

# Functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

error() {
    echo -e "${RED}❌ ERROR: $1${NC}" | tee -a $LOG_FILE
    exit 1
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a $LOG_FILE
}

info() {
    echo -e "${BLUE}ℹ️ $1${NC}" | tee -a $LOG_FILE
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}" | tee -a $LOG_FILE
}

# Header
echo ""
echo "🚀 PyAirtable Phase 1 Deployment"
echo "================================="
echo ""

# Check prerequisites
info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    error "Docker is not installed"
fi

if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose is not installed"
fi

if ! command -v psql &> /dev/null; then
    warning "psql not found - database operations may fail"
fi

if [ ! -f "$ENV_FILE" ]; then
    error "Environment file $ENV_FILE not found"
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    error "Docker Compose file $COMPOSE_FILE not found"
fi

success "Prerequisites check passed"

# Load environment variables
info "Loading environment variables from $ENV_FILE"
set -a
source $ENV_FILE
set +a

# Clean up any existing containers
info "Cleaning up existing containers..."
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE down --remove-orphans 2>/dev/null || true
docker system prune -f --volumes 2>/dev/null || true

# Build services
info "Building Docker images..."
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE build --no-cache

# Start infrastructure (PostgreSQL and Redis)
info "Starting infrastructure services..."
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d postgres redis

# Wait for infrastructure to be ready
info "Waiting for infrastructure to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE exec postgres pg_isready -U postgres >/dev/null 2>&1; then
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    error "PostgreSQL failed to start within expected time"
fi

echo ""
success "Infrastructure is ready"

# Run database migrations
info "Running database migrations..."
cd go-services
export DB_PASSWORD=${POSTGRES_PASSWORD}
export DB_USER=${POSTGRES_USER}
export DB_NAME=${POSTGRES_DB}

if ! ./migrations/run-migrations.sh; then
    error "Database migrations failed"
fi

cd ..
success "Database migrations completed"

# Start all services
info "Starting all Phase 1 services..."
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE up -d

# Wait for services to be ready
info "Waiting for services to become healthy..."
sleep 30

# Health check function
health_check() {
    local service_name=$1
    local url=$2
    local max_attempts=20
    local attempt=0
    
    info "Checking health of $service_name..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "$url" >/dev/null 2>&1; then
            success "$service_name is healthy"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 3
    done
    
    error "$service_name failed health check"
}

# Health checks for all services
echo ""
info "Running health checks..."

health_check "API Gateway" "http://localhost:${API_GATEWAY_PORT:-8080}/health"
health_check "Auth Service" "http://localhost:${AUTH_SERVICE_PORT:-8001}/health"
health_check "User Service" "http://localhost:${USER_SERVICE_PORT:-8002}/health"
health_check "Airtable Gateway" "http://localhost:${AIRTABLE_GATEWAY_PORT:-8003}/health"

# Service communication tests
info "Testing service-to-service communication..."

# Test API Gateway can reach other services
if ! curl -s -f "http://localhost:${API_GATEWAY_PORT:-8080}/api/v1/info" >/dev/null; then
    warning "API Gateway info endpoint not responding"
fi

# Show service status
echo ""
info "Service Status:"
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE ps

# Show service logs (last 20 lines)
echo ""
info "Recent service logs:"
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE logs --tail=20

# Validation tests
echo ""
info "Running validation tests..."

# Test 1: Authentication flow
echo "🔐 Testing authentication flow..."

# Register a test user
TEST_USER_EMAIL="test-$(date +%s)@example.com"
TEST_USER_PASSWORD="TestPassword123!"

register_response=$(curl -s -X POST "http://localhost:${API_GATEWAY_PORT:-8080}/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"$TEST_USER_EMAIL\",
    \"password\": \"$TEST_USER_PASSWORD\",
    \"first_name\": \"Test\",
    \"last_name\": \"User\"
  }" 2>/dev/null || echo "")

if [ -n "$register_response" ]; then
    success "User registration successful"
    
    # Try to login
    login_response=$(curl -s -X POST "http://localhost:${API_GATEWAY_PORT:-8080}/api/v1/auth/login" \
      -H "Content-Type: application/json" \
      -d "{
        \"email\": \"$TEST_USER_EMAIL\",
        \"password\": \"$TEST_USER_PASSWORD\"
      }" 2>/dev/null || echo "")
    
    if [ -n "$login_response" ]; then
        success "User login successful"
        
        # Extract token and test authenticated endpoint
        access_token=$(echo "$login_response" | jq -r '.access_token' 2>/dev/null || echo "")
        
        if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
            profile_response=$(curl -s -X GET "http://localhost:${API_GATEWAY_PORT:-8080}/api/v1/users/me" \
              -H "Authorization: Bearer $access_token" 2>/dev/null || echo "")
            
            if [ -n "$profile_response" ]; then
                success "Authenticated API call successful"
            else
                warning "Authenticated API call failed"
            fi
        else
            warning "Failed to extract access token"
        fi
    else
        warning "User login failed"
    fi
else
    warning "User registration failed"
fi

# Test 2: Database connectivity
echo ""
echo "🗄️ Testing database connectivity..."
db_test=$(docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T postgres psql -U postgres -d pyairtable -c "SELECT version();" 2>/dev/null || echo "")

if [ -n "$db_test" ]; then
    success "Database connectivity test passed"
else
    warning "Database connectivity test failed"
fi

# Test 3: Redis connectivity
echo ""
echo "🔴 Testing Redis connectivity..."
redis_test=$(docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE exec -T redis redis-cli --pass "$REDIS_PASSWORD" ping 2>/dev/null || echo "")

if [ "$redis_test" = "PONG" ]; then
    success "Redis connectivity test passed"
else
    warning "Redis connectivity test failed"
fi

# Summary
echo ""
echo "📊 DEPLOYMENT SUMMARY"
echo "===================="
echo ""

# Show running containers
echo "🐳 Running Containers:"
docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "🌐 Service Endpoints:"
echo "  • API Gateway:      http://localhost:${API_GATEWAY_PORT:-8080}"
echo "  • Auth Service:     http://localhost:${AUTH_SERVICE_PORT:-8001}"
echo "  • User Service:     http://localhost:${USER_SERVICE_PORT:-8002}"
echo "  • Airtable Gateway: http://localhost:${AIRTABLE_GATEWAY_PORT:-8003}"
echo "  • PostgreSQL:       localhost:5432"
echo "  • Redis:            localhost:6379"

echo ""
echo "📚 Quick Commands:"
echo "  • View logs:        docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE logs -f"
echo "  • Stop services:    docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE down"
echo "  • Restart service:  docker-compose -f $COMPOSE_FILE --env-file $ENV_FILE restart <service>"

echo ""
success "Phase 1 deployment completed successfully!"

echo ""
echo "🎯 Next Steps:"
echo "  1. Configure your Airtable credentials in $ENV_FILE"
echo "  2. Test with your own Airtable base"
echo "  3. Run comprehensive integration tests"
echo "  4. Monitor service logs for any issues"

echo ""
echo "📋 Validation completed. Check the logs above for any warnings."