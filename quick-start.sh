#!/bin/bash
# PyAirtableMCP Quick Start Script
set -e

echo "🚀 PyAirtableMCP Quick Start"
echo "============================"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

print_success "Docker and Docker Compose are available"

# Check if .env exists
if [ ! -f ".env" ]; then
    print_step "Setting up credentials..."
    echo ""
    echo "No .env file found. Let's set up your credentials:"
    ./generate-secure-credentials.sh
else
    print_success ".env file already exists"
fi

# Build services
print_step "Building services..."
echo ""
echo "This will build all required Docker images..."
read -p "Continue with build? (y/N): " build_confirm
if [[ $build_confirm =~ ^[Yy]$ ]]; then
    ./build-all-services.sh
else
    print_warning "Skipping build step. Make sure images are available."
fi

# Start services
print_step "Starting services..."
echo ""
echo "This will start all services using docker-compose..."
read -p "Start services now? (y/N): " start_confirm
if [[ $start_confirm =~ ^[Yy]$ ]]; then
    echo ""
    print_step "Starting PyAirtableMCP services..."
    
    # Use the minimal working configuration
    docker-compose -f docker-compose.minimal-working.yml up -d
    
    echo ""
    print_success "Services are starting up!"
    
    # Wait for services to be ready
    print_step "Waiting for services to be ready..."
    sleep 30
    
    # Check service health
    echo ""
    print_step "Service Health Check:"
    
    services=("redis:6379" "postgres:5432" "airtable-gateway:8002" "mcp-server:8001" "llm-orchestrator:8003")
    
    for service in "${services[@]}"; do
        IFS=":" read -r name port <<< "$service"
        if nc -z localhost "$port" 2>/dev/null; then
            print_success "$name is running on port $port"
        else
            print_warning "$name may not be ready yet on port $port"
        fi
    done
    
    echo ""
    print_step "Service URLs:"
    echo "  🌐 Airtable Gateway:  http://localhost:8002"
    echo "  🤖 MCP Server:        http://localhost:8001"
    echo "  🧠 LLM Orchestrator:  http://localhost:8003"
    echo "  📊 Redis:             localhost:6379 (internal)"
    echo "  🐘 PostgreSQL:        localhost:5432 (internal)"
    
    echo ""
    print_step "Testing basic connectivity..."
    
    # Test airtable-gateway health
    if curl -s http://localhost:8002/health >/dev/null 2>&1; then
        print_success "Airtable Gateway health check passed"
    else
        print_warning "Airtable Gateway health check failed - check logs with: docker-compose logs airtable-gateway"
    fi
    
    # Test mcp-server health
    if curl -s http://localhost:8001/health >/dev/null 2>&1; then
        print_success "MCP Server health check passed"
    else
        print_warning "MCP Server health check failed - check logs with: docker-compose logs mcp-server"
    fi
    
    echo ""
    print_success "🎉 PyAirtableMCP is running!"
    
    echo ""
    print_step "Useful commands:"
    echo "  📋 View logs:         docker-compose -f docker-compose.minimal-working.yml logs"
    echo "  🔍 View service logs: docker-compose -f docker-compose.minimal-working.yml logs [service-name]"
    echo "  ⏹️  Stop services:     docker-compose -f docker-compose.minimal-working.yml down"
    echo "  🔄 Restart services:  docker-compose -f docker-compose.minimal-working.yml restart"
    echo "  📊 Service status:    docker-compose -f docker-compose.minimal-working.yml ps"
    
else
    print_warning "Services not started. To start manually:"
    echo "  docker-compose -f docker-compose.minimal-working.yml up -d"
fi

echo ""
print_success "Quick start completed! 🚀"