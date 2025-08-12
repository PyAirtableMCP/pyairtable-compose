#!/bin/bash

echo "🏥 Quick Health Check"
echo "===================="

# Check existing services
echo "Checking existing services..."

services=(
    "API Gateway:8000:/health"
    "MCP Server:8001:/health" 
    "Airtable Gateway:8002:/health"
    "LLM Orchestrator:8003:/health"
    "Automation Services:8006:/health"
    "Platform Services:8007:/health"
)

for service in "${services[@]}"; do
    IFS=':' read -r name port path <<< "$service"
    url="http://localhost:$port$path"
    
    if curl -s --max-time 3 "$url" > /dev/null 2>&1; then
        echo "✅ $name ($port) - OK"
    else
        echo "❌ $name ($port) - DOWN"
    fi
done

echo ""
echo "To start services: docker-compose up -d"
echo "To see logs: docker-compose logs -f [service-name]"
echo "To rebuild: docker-compose up -d --build"
