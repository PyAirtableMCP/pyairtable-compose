#!/bin/bash

# LGTM Stack Deployment Script for PyAirtable Platform
# Deploys Loki, Grafana, Tempo, Mimir observability stack with MinIO storage

set -e

echo "🚀 Starting LGTM Stack Deployment for PyAirtable Platform"
echo "========================================================"

# Check if Docker and Docker Compose are available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Navigate to the LGTM stack directory
cd "$(dirname "$0")"

echo "📍 Working directory: $(pwd)"

# Step 1: Deploy MinIO storage backend
echo ""
echo "1️⃣  Deploying MinIO storage backend..."
docker-compose -f docker-compose.lgtm.yml up -d minio minio-init

# Wait for MinIO to be ready
echo "⏳ Waiting for MinIO to initialize..."
sleep 15

# Verify MinIO buckets are created
echo "✅ Verifying MinIO bucket creation..."
if docker-compose -f docker-compose.lgtm.yml logs minio-init | grep -q "created successfully"; then
    echo "✅ MinIO buckets created successfully"
else
    echo "⚠️  MinIO bucket creation may have issues, continuing..."
fi

# Step 2: Deploy Loki for log aggregation
echo ""
echo "2️⃣  Deploying Loki for log aggregation..."
docker-compose -f docker-compose.lgtm.yml up -d loki

# Wait for Loki to be ready
echo "⏳ Waiting for Loki to start..."
sleep 20

# Step 3: Deploy Grafana
echo ""
echo "3️⃣  Deploying Grafana with unified dashboard..."
docker-compose -f docker-compose.lgtm.yml up -d grafana

# Wait for Grafana to be ready
echo "⏳ Waiting for Grafana to start..."
sleep 15

# Step 4: Deploy remaining services (these may need configuration fixes)
echo ""
echo "4️⃣  Attempting to deploy Tempo and Mimir..."
echo "ℹ️  Note: These services may need configuration fixes"
docker-compose -f docker-compose.lgtm.yml up -d tempo mimir || echo "⚠️  Tempo/Mimir deployment issues - continuing with available services"

# Step 5: Check service status
echo ""
echo "5️⃣  Checking service status..."
docker-compose -f docker-compose.lgtm.yml ps

# Step 6: Test connectivity
echo ""
echo "6️⃣  Testing service connectivity..."

# Test Loki
if curl -s "http://localhost:3100/ready" > /dev/null; then
    echo "✅ Loki is ready at http://localhost:3100"
else
    echo "❌ Loki is not responding"
fi

# Test Grafana
if curl -s "http://localhost:3001" > /dev/null; then
    echo "✅ Grafana is ready at http://localhost:3001"
    echo "   📝 Login: admin / admin123"
else
    echo "❌ Grafana is not responding"
fi

# Test MinIO
if curl -s "http://localhost:9000/minio/health/live" > /dev/null; then
    echo "✅ MinIO is ready at http://localhost:9000"
    echo "   📝 Console: http://localhost:9001 (minioadmin / minioadmin123)"
else
    echo "❌ MinIO is not responding"
fi

# Test Mimir
if curl -s "http://localhost:8081/ready" > /dev/null; then
    echo "✅ Mimir is ready at http://localhost:8081"
else
    echo "⚠️  Mimir is not responding (may need configuration fix)"
fi

# Test Tempo
if curl -s "http://localhost:3200/ready" > /dev/null; then
    echo "✅ Tempo is ready at http://localhost:3200"
else
    echo "⚠️  Tempo is not responding (may need configuration fix)"
fi

echo ""
echo "🎉 LGTM Stack Deployment Complete!"
echo "=================================="
echo ""
echo "📊 Available Services:"
echo "  • Grafana Dashboard: http://localhost:3001 (admin/admin123)"
echo "  • Loki Logs: http://localhost:3100"
echo "  • MinIO Storage: http://localhost:9000"
echo "  • MinIO Console: http://localhost:9001"
echo ""
echo "⚠️  Note: Tempo and Mimir may need configuration fixes for full functionality"
echo ""
echo "📋 Next Steps:"
echo "  1. Access Grafana at http://localhost:3001"
echo "  2. Configure your applications to send telemetry to the LGTM stack"
echo "  3. Set up custom dashboards for your services"
echo "  4. Configure alerting rules as needed"
echo ""
echo "🔧 Troubleshooting:"
echo "  - Check logs: docker-compose -f docker-compose.lgtm.yml logs [service]"
echo "  - Restart services: docker-compose -f docker-compose.lgtm.yml restart [service]"
echo "  - Stop all: docker-compose -f docker-compose.lgtm.yml down"
echo ""