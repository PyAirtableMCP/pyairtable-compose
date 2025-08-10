#!/bin/bash
set -e

echo "📊 Opening LGTM monitoring stack..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if monitoring services are running
echo "🔍 Checking monitoring services status..."

# Function to check if a port is open
check_port() {
    local port=$1
    local service_name=$2
    if curl -s --connect-timeout 3 http://localhost:$port/health &>/dev/null || \
       curl -s --connect-timeout 3 http://localhost:$port/ &>/dev/null; then
        echo "✅ $service_name is running on port $port"
        return 0
    else
        echo "❌ $service_name is not accessible on port $port"
        return 1
    fi
}

# Check LGTM stack services
GRAFANA_RUNNING=false
LOKI_RUNNING=false
TEMPO_RUNNING=false

if check_port 3000 "Grafana"; then
    GRAFANA_RUNNING=true
fi

if check_port 3100 "Loki"; then
    LOKI_RUNNING=true
fi

if check_port 3200 "Tempo"; then
    TEMPO_RUNNING=true
fi

# If monitoring stack is not running, offer to start it
if [ "$GRAFANA_RUNNING" = false ] && [ "$LOKI_RUNNING" = false ]; then
    echo ""
    echo "⚠️  LGTM monitoring stack doesn't appear to be running."
    echo "🚀 Would you like to start it? (y/n)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "📦 Starting LGTM monitoring stack..."
        
        if [ -f "docker-compose.observability.yml" ]; then
            docker-compose -f docker-compose.observability.yml up -d
            echo "⏳ Waiting 30 seconds for services to start..."
            sleep 30
        elif [ -f "monitoring/docker-compose.production.yml" ]; then
            docker-compose -f monitoring/docker-compose.production.yml up -d
            echo "⏳ Waiting 30 seconds for services to start..."
            sleep 30
        else
            echo "❌ No observability compose file found. Please check your monitoring setup."
            exit 1
        fi
        
        # Recheck services
        check_port 3000 "Grafana" && GRAFANA_RUNNING=true
        check_port 3100 "Loki" && LOKI_RUNNING=true
        check_port 3200 "Tempo" && TEMPO_RUNNING=true
    fi
fi

echo ""
echo "🌐 Opening monitoring services in browser..."

# Open available services
if [ "$GRAFANA_RUNNING" = true ]; then
    echo "📈 Opening Grafana dashboard..."
    open http://localhost:3000 || xdg-open http://localhost:3000 2>/dev/null || echo "Please open: http://localhost:3000"
fi

if [ "$LOKI_RUNNING" = true ]; then
    echo "📋 Loki available at: http://localhost:3100"
fi

if [ "$TEMPO_RUNNING" = true ]; then
    echo "🔍 Tempo available at: http://localhost:3200"
fi

echo ""
echo "🔧 Useful monitoring commands:"
echo "   • Query logs: curl -G \"http://localhost:3100/loki/api/v1/query\" --data-urlencode 'query=\{service=\"api-gateway\"\}'"
echo "   • Check metrics: curl http://localhost:8000/metrics"
echo "   • View traces: open http://localhost:3200"
echo ""
echo "📊 Default Grafana login (if needed): admin/admin"
echo "✅ Monitoring stack opened!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"