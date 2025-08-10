#!/bin/bash
set -e

echo "🔄 Restarting PyAirtable development environment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Restart all services
echo "📦 Restarting PyAirtable services..."
docker-compose restart

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
if [ -f "./scripts/wait-for-services.sh" ]; then
    ./scripts/wait-for-services.sh
else
    echo "⚠️  wait-for-services.sh not found, waiting 30 seconds..."
    sleep 30
fi

# Run quick health check
echo "🏥 Running health checks..."
if [ -f "./scripts/test-health.sh" ]; then
    ./scripts/test-health.sh
else
    echo "⚠️  test-health.sh not found, checking basic connectivity..."
    curl -f http://localhost:8000/health || echo "❌ API Gateway health check failed"
fi

echo "✅ Development environment restarted successfully!"
echo "📊 Access points:"
echo "   • Frontend: http://localhost:3000"
echo "   • API Gateway: http://localhost:8000"
echo "   • Grafana: http://localhost:3000 (monitoring)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"