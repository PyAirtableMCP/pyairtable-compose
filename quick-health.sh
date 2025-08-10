#!/bin/bash

echo "=== PyAirtable System Health Check ==="
echo "Date: $(date)"
echo "================================================"
echo

# Check Docker services
echo "🐳 Docker Services Status:"
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo

# Check actual running containers
echo "📦 Running Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep pyairtable
echo

# Service health checks
echo "🏥 Service Health Checks:"
echo "------------------------"

# Infrastructure services
echo -n "PostgreSQL (5433): "
if pg_isready -h localhost -p 5433 >/dev/null 2>&1; then
    echo "✅ HEALTHY"
else
    echo "❌ UNREACHABLE"
fi

echo -n "Redis (6380): "
if redis-cli -p 6380 -a "${REDIS_PASSWORD:-redis}" ping 2>/dev/null | grep -q PONG; then
    echo "✅ HEALTHY"
else
    echo "❌ UNREACHABLE"
fi

# Check services on their actual mapped ports
services=(
    "7002:Airtable-Gateway"
    "7007:Platform-Services"
    "7000:API-Gateway"
    "8001:MCP-Server"
    "8003:LLM-Orchestrator"
    "8006:Automation-Services"
    "8008:SAGA-Orchestrator"
    "3000:Frontend"
)

for service in "${services[@]}"; do
    port=$(echo $service | cut -d: -f1)
    name=$(echo $service | cut -d: -f2)
    echo -n "$name ($port): "
    
    if curl -s -f -m 2 "http://localhost:$port/health" >/dev/null 2>&1; then
        echo "✅ HEALTHY"
    elif curl -s -f -m 2 "http://localhost:$port/" >/dev/null 2>&1; then
        echo "⚠️  RUNNING (no health endpoint)"
    else
        echo "❌ UNREACHABLE"
    fi
done

echo
echo "📊 Summary:"
echo "----------"
total_services=10
healthy_count=$(docker-compose ps | grep -c "healthy\|running" || echo 0)
echo "Services Running: $healthy_count/$total_services"
availability=$((healthy_count * 100 / total_services))
echo "System Availability: ${availability}%"

if [ $availability -lt 50 ]; then
    echo "⚠️  WARNING: System availability below 50%!"
    echo "Run './fix-services.sh' to attempt automatic recovery"
elif [ $availability -lt 80 ]; then
    echo "⚠️  Some services need attention"
else
    echo "✅ System is healthy"
fi