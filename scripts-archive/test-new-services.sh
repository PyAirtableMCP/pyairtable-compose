#!/bin/bash

echo "🧪 Testing New Services"
echo "======================="

echo "Building and starting new services..."
docker-compose -f docker-compose.test-new.yml up -d --build

echo "Waiting for services to start..."
sleep 15

echo "Testing services..."

test_service() {
    local name=$1
    local url=$2
    
    if curl -s --max-time 5 "$url" > /dev/null; then
        echo "✅ $name - OK"
        curl -s "$url" | jq . 2>/dev/null || curl -s "$url"
        echo ""
    else
        echo "❌ $name - FAILED"
    fi
}

test_service "Auth Service (Go)" "http://localhost:8100/health"
test_service "AI Service (Python)" "http://localhost:8200/health"  
test_service "Auth Frontend" "http://localhost:3001/"

echo ""
echo "🎯 Access URLs:"
echo "- Auth Service: http://localhost:8100"
echo "- AI Service: http://localhost:8200"
echo "- Auth Frontend: http://localhost:3001"
echo ""
echo "Stop test services: docker-compose -f docker-compose.test-new.yml down"
