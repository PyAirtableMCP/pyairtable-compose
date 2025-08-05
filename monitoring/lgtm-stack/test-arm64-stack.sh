#!/bin/bash

# Test script for ARM64 LGTM Stack
# This script validates the ARM64 configuration and tests basic functionality

set -e

echo "🔍 Testing ARM64 LGTM Stack Configuration..."

# Change to the script directory
cd "$(dirname "$0")"

# Validate docker-compose configuration
echo "✅ Validating docker-compose configuration..."
docker-compose -f docker-compose.lgtm.yml config --quiet
echo "✅ Configuration is valid"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Check system architecture
ARCH=$(uname -m)
echo "🔍 System architecture: $ARCH"

if [[ "$ARCH" != "arm64" ]]; then
    echo "⚠️  Warning: This system is not ARM64. Testing may not reflect actual ARM64 behavior."
fi

# Pull images to verify ARM64 availability
echo "🔄 Pulling ARM64 images..."
docker-compose -f docker-compose.lgtm.yml pull --quiet

# Start the stack
echo "🚀 Starting LGTM stack..."
docker-compose -f docker-compose.lgtm.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 30

# Test service endpoints
echo "🔍 Testing service endpoints..."

# Test MinIO
if curl -f -s http://localhost:9000/minio/health/live > /dev/null; then
    echo "✅ MinIO is healthy"
else
    echo "❌ MinIO health check failed"
fi

# Test Loki
if curl -f -s http://localhost:3100/ready > /dev/null; then
    echo "✅ Loki is ready"
else
    echo "❌ Loki health check failed"
fi

# Test Tempo
if curl -f -s http://localhost:3200/ready > /dev/null; then
    echo "✅ Tempo is ready"
else
    echo "❌ Tempo health check failed"
fi

# Test Mimir
if curl -f -s http://localhost:8081/ready > /dev/null; then
    echo "✅ Mimir is ready"
else
    echo "❌ Mimir health check failed"
fi

# Test Grafana
if curl -f -s http://localhost:3001/api/health > /dev/null; then
    echo "✅ Grafana is healthy"
else
    echo "❌ Grafana health check failed"
fi

# Show resource usage
echo "📊 Resource usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
    $(docker-compose -f docker-compose.lgtm.yml ps -q)

echo "🎉 ARM64 LGTM Stack test completed!"
echo ""
echo "📋 Service URLs:"
echo "  - Grafana: http://localhost:3001 (admin/admin123)"
echo "  - MinIO Console: http://localhost:9001 (minioadmin/minioadmin123)"
echo "  - Loki: http://localhost:3100"
echo "  - Tempo: http://localhost:3200"
echo "  - Mimir: http://localhost:8081"
echo ""
echo "🛑 To stop the stack: docker-compose -f docker-compose.lgtm.yml down"