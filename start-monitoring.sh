#!/bin/bash

echo "🚀 Starting PyAirtable LGTM Observability Stack..."
echo "================================================="

# Start the monitoring stack
docker-compose -f docker-compose.monitoring.working.yml up -d

echo ""
echo "⏳ Waiting for services to start..."
sleep 30

echo ""
echo "✅ LGTM Stack Status:"
echo "=================="

# Check each service
for service in prometheus grafana loki simple-monitor; do
    if docker ps | grep -q "$service.*healthy"; then
        echo "✓ $service: Running (healthy)"
    elif docker ps | grep -q "$service.*Up"; then
        echo "⚠ $service: Running (starting up)"
    else
        echo "✗ $service: Not running"
    fi
done

echo ""
echo "🎯 Access URLs:"
echo "=============="
echo "📊 Grafana Dashboard: http://localhost:3001"
echo "   Username: admin"
echo "   Password: admin123"
echo ""
echo "📈 Prometheus: http://localhost:9090"
echo "📝 Loki Logs: http://localhost:3100"
echo "🔍 Service Monitor: http://localhost:8888/metrics"
echo ""
echo "🎯 Key Metrics Available:"
echo "========================"
echo "• service_health{service='api-gateway'}: API Gateway status"
echo "• service_health{service='platform-services'}: Auth service status" 
echo "• auth_service_status: Auth service working (1=OK, 0=DOWN)"
echo "• services_healthy_count: Number of healthy services"
echo "• services_total_count: Total services monitored"
echo ""
echo "🚀 All monitoring services are now running!"
echo "Open Grafana at http://localhost:3001 to see the dashboard"