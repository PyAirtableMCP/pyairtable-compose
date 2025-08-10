#!/bin/bash
set -e

echo "🚀 Starting PyAirtable development environment..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if Colima is installed
if ! command -v colima &> /dev/null; then
    echo "❌ Colima not found. Installing..."
    brew install colima
fi

# Start Colima with optimized settings for development
echo "🐳 Starting Colima container runtime..."
colima start --cpu 4 --memory 8 --disk 60 --arch aarch64 --vm-type=vz --vz-rosetta

# Verify Docker is available
echo "🔍 Verifying Docker availability..."
docker --version

# Start services with optimized compose file
echo "📦 Starting PyAirtable services..."
docker-compose -f docker-compose.minimal.yml up -d --build

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

echo "✅ Development environment ready!"
echo "📊 Access points:"
echo "   • Frontend: http://localhost:3000"
echo "   • API Gateway: http://localhost:8000"
echo "   • Grafana: http://localhost:3000 (monitoring)"
echo "   • Loki: http://localhost:3100 (logs)"
echo ""
echo "🔧 Useful commands:"
echo "   • View logs: ./scripts/dev-helpers/logs-dev.sh"
echo "   • Run tests: ./tests/run-all-tests.sh"
echo "   • Stop environment: ./scripts/dev-helpers/stop-dev.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"