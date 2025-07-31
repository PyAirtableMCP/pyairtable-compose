#!/bin/bash
# Test health check for all services

echo "🔍 Testing PyAirtable microservices health..."
echo

# Test API Gateway health (which checks all services)
echo "📊 Checking overall system health..."
curl -s http://localhost:8000/api/health | jq '.'
echo

# Test individual services
echo "🔗 Testing individual service endpoints..."

echo "API Gateway (8000):"
curl -s http://localhost:8000/ | jq '.service'

echo "Airtable Gateway (8002):"
curl -s http://localhost:8002/health | jq '.status'

echo "LLM Orchestrator (8003):"
curl -s http://localhost:8003/health | jq '.status'

echo
echo "✅ Health check complete!"
echo "If any service shows errors, check logs with: docker-compose logs [service-name]"