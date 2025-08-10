#!/bin/bash

# Secure Local Deployment Script
# This script safely starts all PyAirtable services with proper security checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if Docker is running
check_docker() {
    print_status "Checking Docker status..."
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Check if environment file exists
check_env_file() {
    if [ ! -f ".env.local" ]; then
        print_error ".env.local file not found!"
        echo ""
        echo "Please run the following commands first:"
        echo "  1. chmod +x generate-secure-env.sh"
        echo "  2. ./generate-secure-env.sh"
        echo "  3. Edit .env.local with your actual API credentials"
        exit 1
    fi
    
    # Check for placeholder values
    if grep -q "pat_your_airtable_token_here\|app_your_airtable_base_id_here\|AIza_your_gemini_api_key_here" .env.local; then
        print_error "Found placeholder values in .env.local!"
        echo ""
        echo "Please edit .env.local and replace the following:"
        echo "  - AIRTABLE_TOKEN=pat_your_airtable_token_here"
        echo "  - AIRTABLE_BASE=app_your_airtable_base_id_here"
        echo "  - GEMINI_API_KEY=AIza_your_gemini_api_key_here"
        exit 1
    fi
    
    print_success "Environment configuration validated"
}

# Clean up existing containers
cleanup_containers() {
    print_status "Cleaning up existing containers..."
    docker-compose -f docker-compose.local-minimal.yml down --remove-orphans || true
    print_success "Cleanup completed"
}

# Build and start services
start_services() {
    print_status "Building and starting services..."
    
    # Load environment variables
    export $(cat .env.local | grep -v '^#' | xargs)
    
    # Start with minimal services first
    docker-compose -f docker-compose.local-minimal.yml up --build -d
    
    print_success "Services started successfully"
}

# Health check function
check_service_health() {
    local service=$1
    local url=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Checking health of $service..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 5 "$url" > /dev/null 2>&1; then
            print_success "$service is healthy"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_warning "$service failed health check after $max_attempts attempts"
    return 1
}

# Wait for services to be ready
wait_for_services() {
    print_status "Waiting for services to start..."
    sleep 10
    
    # Check service health
    check_service_health "Airtable Gateway" "http://localhost:8002/health" || true
    check_service_health "MCP Server" "http://localhost:8001/health" || true
    check_service_health "LLM Orchestrator" "http://localhost:8003/health" || true
    check_service_health "Automation Services" "http://localhost:8006/health" || true
    check_service_health "SAGA Orchestrator" "http://localhost:8008/health" || true
}

# Show service status
show_status() {
    print_status "Service Status:"
    docker-compose -f docker-compose.local-minimal.yml ps
    
    echo ""
    print_status "Available Services:"
    echo "  🔗 Airtable Gateway:    http://localhost:8002"
    echo "  🤖 MCP Server:          http://localhost:8001"
    echo "  🧠 LLM Orchestrator:    http://localhost:8003"
    echo "  ⚙️  Automation Services: http://localhost:8006"
    echo "  🔄 SAGA Orchestrator:   http://localhost:8008"
    echo ""
    print_status "Database Services:"
    echo "  🗃️  PostgreSQL:         localhost:5432 (internal only)"
    echo "  🔴 Redis:               localhost:6379 (internal only)"
    echo ""
    print_status "View logs with:"
    echo "  docker-compose -f docker-compose.local-minimal.yml logs -f [service-name]"
    echo ""
    print_status "Stop all services with:"
    echo "  docker-compose -f docker-compose.local-minimal.yml down"
}

# Main execution
main() {
    echo "🚀 Starting PyAirtable Compose - Secure Local Deployment"
    echo "========================================================"
    echo ""
    
    check_docker
    check_env_file
    cleanup_containers
    start_services
    wait_for_services
    show_status
    
    echo ""
    print_success "🎉 Local deployment completed successfully!"
    echo ""
    print_warning "⚠️  Security Reminders:"
    echo "  - Never commit .env.local to version control"
    echo "  - Rotate credentials regularly"
    echo "  - Monitor service logs for errors"
    echo ""
}

# Handle script interruption
trap 'echo ""; print_warning "Deployment interrupted"; exit 130' INT

# Run main function
main