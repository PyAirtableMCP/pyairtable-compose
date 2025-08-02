#!/bin/bash

echo "🚀 Starting Current PyAirtable Services"
echo "======================================="

# Ensure we have an .env file
if [ ! -f ".env" ]; then
    echo "❌ No .env file found. Please create one from .env.template"
    exit 1
fi

# Start infrastructure first
echo "📦 Starting infrastructure..."
docker-compose up -d postgres redis

echo "⏳ Waiting for infrastructure (15 seconds)..."
sleep 15

# Start core services
echo "🔧 Starting core services..."
docker-compose up -d \
    api-gateway \
    mcp-server \
    airtable-gateway \
    llm-orchestrator \
    platform-services \
    automation-services

echo "⏳ Waiting for services to initialize (20 seconds)..."
sleep 20

# Start frontend
echo "🌐 Starting frontend..."
docker-compose up -d frontend

echo "✅ Services started! Running health check..."
sleep 10

./quick-health-check.sh

echo ""
echo "🎯 Access your services:"
echo "- Main API: http://localhost:8000"
echo "- Frontend: http://localhost:3000"
echo "- MCP Server: http://localhost:8001"
echo ""
echo "View logs: docker-compose logs -f"
echo "Stop all: docker-compose down"
