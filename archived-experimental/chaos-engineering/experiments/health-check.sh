#!/bin/bash
set -euo pipefail

# Health Check Script for PyAirtable Chaos Engineering
# Usage: ./health-check.sh [pre|post]

CHECK_TYPE="${1:-pre}"
NAMESPACE="pyairtable"

echo "🏥 Running ${CHECK_TYPE}-experiment health check..."

# Define service endpoints
declare -A SERVICES=(
    ["api-gateway"]="http://api-gateway.${NAMESPACE}.svc.cluster.local:8080/health"
    ["auth-service"]="http://auth-service.${NAMESPACE}.svc.cluster.local:8081/health"
    ["platform-services"]="http://platform-services.${NAMESPACE}.svc.cluster.local:8000/health"
    ["automation-services"]="http://automation-services.${NAMESPACE}.svc.cluster.local:8002/health"
)

FAILED_CHECKS=0
TOTAL_CHECKS=0

# Function to check service health
check_service_health() {
    local service_name="$1"
    local endpoint="$2"
    
    echo "🔍 Checking ${service_name}..."
    
    # Check if pods are running
    if ! kubectl get pods -n "${NAMESPACE}" -l "app=${service_name}" | grep -q "Running"; then
        echo "❌ ${service_name}: No running pods found"
        ((FAILED_CHECKS++))
        return 1
    fi
    
    # Port-forward and check health endpoint
    local port=$(echo "$endpoint" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    local pod_name=$(kubectl get pods -n "${NAMESPACE}" -l "app=${service_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod_name" ]]; then
        if kubectl exec -n "${NAMESPACE}" "$pod_name" -- curl -f -m 5 "localhost:${port}/health" &>/dev/null; then
            echo "✅ ${service_name}: Healthy"
        else
            echo "❌ ${service_name}: Health check failed"
            ((FAILED_CHECKS++))
            return 1
        fi
    else
        echo "❌ ${service_name}: No pod found"
        ((FAILED_CHECKS++))
        return 1
    fi
    
    return 0
}

# Check Kubernetes cluster connectivity
echo "🔗 Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi
echo "✅ Kubernetes cluster is accessible"

# Check namespace exists
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    echo "❌ Namespace '${NAMESPACE}' does not exist"
    exit 1
fi
echo "✅ Namespace '${NAMESPACE}' exists"

# Check each service
for service in "${!SERVICES[@]}"; do
    ((TOTAL_CHECKS++))
    check_service_health "$service" "${SERVICES[$service]}" || true
done

# Check database connectivity
echo "🗄️ Checking database connectivity..."
((TOTAL_CHECKS++))
if kubectl get pods -n "${NAMESPACE}" -l "app=postgres" | grep -q "Running"; then
    echo "✅ PostgreSQL: Running"
else
    echo "❌ PostgreSQL: Not running"
    ((FAILED_CHECKS++))
fi

# Check cache connectivity
echo "⚡ Checking cache connectivity..."
((TOTAL_CHECKS++))
if kubectl get pods -n "${NAMESPACE}" -l "app=redis" | grep -q "Running"; then
    echo "✅ Redis: Running"
else
    echo "❌ Redis: Not running"
    ((FAILED_CHECKS++))
fi

# Check monitoring stack (if in post mode)
if [[ "$CHECK_TYPE" == "post" ]]; then
    echo "📊 Checking monitoring stack..."
    ((TOTAL_CHECKS++))
    if kubectl get pods -n monitoring 2>/dev/null | grep -q "prometheus.*Running"; then
        echo "✅ Prometheus: Running"
    else
        echo "⚠️ Prometheus: Not detected (monitoring may not be deployed)"
    fi
fi

# Summary
echo ""
echo "📋 Health Check Summary:"
echo "  Total checks: ${TOTAL_CHECKS}"
echo "  Failed checks: ${FAILED_CHECKS}"
echo "  Success rate: $(( (TOTAL_CHECKS - FAILED_CHECKS) * 100 / TOTAL_CHECKS ))%"

if [[ "$FAILED_CHECKS" -gt 0 ]]; then
    echo "❌ Health check failed. ${FAILED_CHECKS} service(s) are unhealthy."
    
    if [[ "$CHECK_TYPE" == "pre" ]]; then
        echo "🛑 Aborting chaos experiment due to unhealthy services."
        echo "💡 Fix the failing services before running chaos experiments."
    else
        echo "⚠️ Some services may not have recovered from the chaos experiment."
        echo "🔍 Check logs and monitoring dashboards for more details."
    fi
    
    exit 1
else
    echo "✅ All health checks passed successfully!"
    
    if [[ "$CHECK_TYPE" == "pre" ]]; then
        echo "🚀 System is healthy and ready for chaos experiments."
    else
        echo "🎉 System has successfully recovered from chaos experiments."
    fi
fi