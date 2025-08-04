#!/bin/bash

# Deploy SAGA Orchestrator Service
# This script builds and starts the SAGA orchestrator service

set -e

echo "🚀 Deploying PyAirtable SAGA Orchestrator..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    print_error "docker-compose is not installed. Please install it and try again."
    exit 1
fi

# Navigate to project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

print_status "Building SAGA Orchestrator container..."

# Build the SAGA orchestrator service
docker-compose build saga-orchestrator

if [ $? -eq 0 ]; then
    print_status "SAGA Orchestrator container built successfully"
else
    print_error "Failed to build SAGA Orchestrator container"
    exit 1
fi

# Start dependencies first
print_status "Starting dependencies (PostgreSQL, Redis)..."
docker-compose up -d postgres redis

# Wait for databases to be ready
print_status "Waiting for databases to be ready..."
sleep 10

# Check database connectivity
print_status "Checking database connectivity..."
docker-compose exec -T postgres pg_isready -U ${POSTGRES_USER:-postgres} || {
    print_error "PostgreSQL is not ready"
    exit 1
}

# Run database migrations
print_status "Running database migrations..."
if [ -f "migrations/008_create_saga_event_store.sql" ]; then
    docker-compose exec -T postgres psql -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-pyairtable} -f /docker-entrypoint-initdb.d/migrations/008_create_saga_event_store.sql || {
        print_warning "Migration might have already been applied or failed"
    }
fi

# Start platform services (required for SAGA steps)
print_status "Starting platform services..."
docker-compose up -d platform-services automation-services airtable-gateway

# Wait for services to be ready
print_status "Waiting for services to start..."
sleep 15

# Start the SAGA orchestrator
print_status "Starting SAGA Orchestrator..."
docker-compose up -d saga-orchestrator

# Wait for SAGA orchestrator to start
print_status "Waiting for SAGA Orchestrator to be ready..."
sleep 20

# Health check
print_status "Performing health check..."
HEALTH_URL="http://localhost:8008/health"
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -f "$HEALTH_URL" > /dev/null 2>&1; then
        print_status "SAGA Orchestrator is healthy and ready!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            print_error "SAGA Orchestrator health check failed after $MAX_RETRIES attempts"
            print_error "Check logs: docker-compose logs saga-orchestrator"
            exit 1
        fi
        print_warning "Health check attempt $RETRY_COUNT/$MAX_RETRIES failed, retrying in 5 seconds..."
        sleep 5
    fi
done

# Show service status
print_status "Service status:"
docker-compose ps saga-orchestrator

# Show logs
print_status "Recent logs:"
docker-compose logs --tail=20 saga-orchestrator

echo ""
print_status "✅ SAGA Orchestrator deployment completed successfully!"
echo ""
print_status "🌐 Service endpoints:"
echo "   Health Check: http://localhost:8008/health"
echo "   API Documentation: http://localhost:8008/docs"
echo "   SAGA Management: http://localhost:8008/sagas"
echo "   Event Management: http://localhost:8008/events"
echo "   Metrics: http://localhost:8008/metrics"
echo ""
print_status "📊 To view logs: docker-compose logs -f saga-orchestrator"
print_status "🛑 To stop: docker-compose stop saga-orchestrator"
echo ""

# Test SAGA availability with a simple API call
print_status "Testing SAGA types endpoint..."
if curl -s "http://localhost:8008/sagas/types/available" | grep -q "user_onboarding"; then
    print_status "✅ SAGA types endpoint is working correctly"
else
    print_warning "⚠️  SAGA types endpoint test failed"
fi

echo ""
print_status "🎉 SAGA Orchestrator is ready to handle distributed transactions!"
print_status "    The service will automatically trigger user onboarding SAGAs when users register."