#!/bin/bash

# PyAirtable Minimal Deployment Test Script
# Tests the core working services after fixing Docker build issues

set -e

echo "🚀 Testing PyAirtable Minimal Deployment"
echo "==========================================="

# Check if .env file exists
if [[ ! -f .env ]]; then
    echo "❌ .env file not found! Please create it from .env.example"
    exit 1
fi

echo "✅ .env file found"

# Check if Docker and Docker Compose are available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found! Please install Docker"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found! Please install Docker Compose"
    exit 1
fi

echo "✅ Docker and Docker Compose available"

# Stop any existing containers
echo "🧹 Cleaning up existing containers..."
docker-compose -f docker-compose.minimal.yml down --volumes --remove-orphans

# Build and start services
echo "🏗️  Building and starting minimal services..."
docker-compose -f docker-compose.minimal.yml up -d --build

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 30

# Test service health
echo "🏥 Testing service health..."

services=(
    "airtable-gateway:8002"
    "mcp-server:8001"
    "llm-orchestrator:8003"
    "platform-services:8007"
    "automation-services:8006"
)

for service in "${services[@]}"; do
    name=$(echo $service | cut -d: -f1)
    port=$(echo $service | cut -d: -f2)
    
    echo "Testing $name on port $port..."
    
    # Test health endpoint
    if curl -f -s "http://localhost:$port/health" > /dev/null; then
        echo "✅ $name is healthy"
    else
        echo "❌ $name health check failed"
        echo "📋 Container logs for $name:"
        docker-compose -f docker-compose.minimal.yml logs --tail=20 $name
    fi
done

# Test Redis and PostgreSQL
echo "🗄️  Testing database connections..."

# Test Redis
if docker-compose -f docker-compose.minimal.yml exec -T redis redis-cli ping > /dev/null 2>&1; then
    echo "✅ Redis is responding"
else
    echo "❌ Redis connection failed"
fi

# Test PostgreSQL
if docker-compose -f docker-compose.minimal.yml exec -T postgres pg_isready > /dev/null 2>&1; then
    echo "✅ PostgreSQL is ready"
else
    echo "❌ PostgreSQL connection failed"
fi

# Show running containers
echo "📊 Current container status:"
docker-compose -f docker-compose.minimal.yml ps

# Test basic functionality
echo "🧪 Testing basic functionality..."

# Test Airtable Gateway
echo "Testing Airtable Gateway..."
if curl -f -s -H "X-API-Key: ${API_KEY:-test}" "http://localhost:8002/health" > /dev/null; then
    echo "✅ Airtable Gateway responding"
else
    echo "❌ Airtable Gateway not responding"
fi

# Test LLM Orchestrator
echo "Testing LLM Orchestrator..."
if curl -f -s "http://localhost:8003/health" > /dev/null; then
    echo "✅ LLM Orchestrator responding"
else
    echo "❌ LLM Orchestrator not responding"
fi

echo ""
echo "🎉 Minimal deployment test completed!"
echo ""
echo "📋 Next Steps:"
echo "1. Update .env with actual customer credentials:"
echo "   - AIRTABLE_TOKEN=pat14.your_actual_token"
echo "   - AIRTABLE_BASE=app1234567890ABCDEF"
echo "   - GEMINI_API_KEY=AIzaSy-your_actual_key"
echo ""
echo "2. Test with real data:"
echo "   curl -X POST http://localhost:8003/chat \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"message\": \"List my tables\", \"session_id\": \"test\"}'"
echo ""
echo "3. For Minikube deployment, run: kubectl apply -f minikube-manifests/"
echo ""
echo "🔗 Service URLs:"
echo "   - Airtable Gateway: http://localhost:8002"
echo "   - MCP Server: http://localhost:8001"
echo "   - LLM Orchestrator: http://localhost:8003"
echo "   - Platform Services: http://localhost:8007"
echo "   - Automation Services: http://localhost:8006"