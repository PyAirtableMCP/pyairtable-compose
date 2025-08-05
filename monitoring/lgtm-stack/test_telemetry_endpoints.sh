#!/bin/bash

echo "Testing LGTM Stack Telemetry Endpoints..."
echo "========================================"

# Test Tempo (traces)
echo -n "Testing Tempo OTLP traces endpoint (localhost:4317): "
if nc -z localhost 4317; then
    echo "✅ Available"
else
    echo "❌ Not available"
fi

# Test OTEL Collector (metrics)
echo -n "Testing OTEL Collector metrics endpoint (localhost:4318): "
if nc -z localhost 4318; then
    echo "✅ Available"
else
    echo "❌ Not available"
fi

# Test Grafana
echo -n "Testing Grafana (localhost:3000): "
if nc -z localhost 3000; then
    echo "✅ Available"
else
    echo "❌ Not available"
fi

# Test Loki
echo -n "Testing Loki (localhost:3100): "
if nc -z localhost 3100; then
    echo "✅ Available"
else
    echo "❌ Not available"
fi

# Test Mimir
echo -n "Testing Mimir (localhost:9009): "
if nc -z localhost 9009; then
    echo "✅ Available"
else
    echo "❌ Not available"
fi

echo ""
echo "To start the LGTM stack:"
echo "docker-compose up -d"
echo ""
echo "To test telemetry from Go services:"
echo "cd /Users/kg/IdeaProjects/pyairtable-gateway && go run cmd/gateway/main.go"
echo "cd /Users/kg/IdeaProjects/pyairtable-auth && go run cmd/auth/main.go"