#!/bin/bash
set -euo pipefail

# Chaos Experiment Monitor Script
# Usage: ./monitor-experiment.sh <experiment-name> [duration]

EXPERIMENT_NAME="${1:-}"
DURATION="${2:-5m}"
NAMESPACE="chaos-engineering"
LOG_FILE="/tmp/chaos-experiment-${EXPERIMENT_NAME}-$(date +%Y%m%d-%H%M%S).log"

if [[ -z "$EXPERIMENT_NAME" ]]; then
    echo "❌ Usage: $0 <experiment-name> [duration]"
    exit 1
fi

echo "🔍 Monitoring chaos experiment: ${EXPERIMENT_NAME}"
echo "📊 Duration: ${DURATION}"
echo "📝 Log file: ${LOG_FILE}"

# Initialize log file
cat > "$LOG_FILE" << EOF
Chaos Experiment Monitoring Log
===============================
Experiment: ${EXPERIMENT_NAME}
Start Time: $(date)
Duration: ${DURATION}
Namespace: ${NAMESPACE}

EOF

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check experiment status
check_experiment_status() {
    local status=$(kubectl get workflows,podchaos,networkchaos,stresschaos,iochaos -n "$NAMESPACE" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "unknown")
    echo "$status"
}

# Function to collect metrics
collect_metrics() {
    log_with_timestamp "📊 Collecting system metrics..."
    
    # Pod status
    log_with_timestamp "Pod Status:"
    kubectl get pods -n pyairtable -o wide | tee -a "$LOG_FILE"
    
    # Service endpoints
    log_with_timestamp "Service Endpoints:"
    kubectl get endpoints -n pyairtable | tee -a "$LOG_FILE"
    
    # Node resource usage
    log_with_timestamp "Node Resources:"
    kubectl top nodes 2>/dev/null | tee -a "$LOG_FILE" || echo "Metrics server not available" | tee -a "$LOG_FILE"
    
    # Pod resource usage
    log_with_timestamp "Pod Resources:"
    kubectl top pods -n pyairtable 2>/dev/null | tee -a "$LOG_FILE" || echo "Metrics server not available" | tee -a "$LOG_FILE"
    
    # Events
    log_with_timestamp "Recent Events:"
    kubectl get events -n pyairtable --sort-by=.metadata.creationTimestamp | tail -10 | tee -a "$LOG_FILE"
}

# Function to health check services
health_check_services() {
    log_with_timestamp "🏥 Health checking services..."
    
    local services=("api-gateway:8080" "auth-service:8081" "platform-services:8000")
    
    for service in "${services[@]}"; do
        IFS=':' read -r service_name port <<< "$service"
        
        # Get a pod for the service
        local pod=$(kubectl get pods -n pyairtable -l "app=${service_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [[ -n "$pod" ]]; then
            if kubectl exec -n pyairtable "$pod" -- curl -f -m 5 "localhost:${port}/health" &>/dev/null; then
                log_with_timestamp "✅ ${service_name}: Healthy"
            else
                log_with_timestamp "❌ ${service_name}: Unhealthy"
            fi
        else
            log_with_timestamp "❌ ${service_name}: No pod found"
        fi
    done
}

# Function to check database connectivity
check_database() {
    log_with_timestamp "🗄️ Checking database connectivity..."
    
    local pg_pod=$(kubectl get pods -n pyairtable -l "app=postgres" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pg_pod" ]]; then
        if kubectl exec -n pyairtable "$pg_pod" -- pg_isready -U postgres &>/dev/null; then
            log_with_timestamp "✅ PostgreSQL: Connected"
        else
            log_with_timestamp "❌ PostgreSQL: Connection failed"
        fi
    else
        log_with_timestamp "❌ PostgreSQL: No pod found"
    fi
}

# Function to check cache
check_cache() {
    log_with_timestamp "⚡ Checking cache connectivity..."
    
    local redis_pod=$(kubectl get pods -n pyairtable -l "app=redis" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$redis_pod" ]]; then
        if kubectl exec -n pyairtable "$redis_pod" -- redis-cli ping | grep -q "PONG"; then
            log_with_timestamp "✅ Redis: Connected"
        else
            log_with_timestamp "❌ Redis: Connection failed"
        fi
    else
        log_with_timestamp "❌ Redis: No pod found"
    fi
}

# Function to monitor performance
monitor_performance() {
    log_with_timestamp "⚡ Monitoring performance metrics..."
    
    # Check if Prometheus is available for queries
    local prometheus_pod=$(kubectl get pods -n monitoring -l "app=prometheus" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$prometheus_pod" ]]; then
        # Port forward to Prometheus (in background)
        kubectl port-forward -n monitoring "$prometheus_pod" 9090:9090 &>/dev/null &
        local pf_pid=$!
        sleep 2
        
        # Query some basic metrics
        local response_time=$(curl -s "http://localhost:9090/api/v1/query?query=histogram_quantile(0.95,%20rate(http_request_duration_seconds_bucket[5m]))" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
        local error_rate=$(curl -s "http://localhost:9090/api/v1/query?query=rate(http_requests_total{status=~\"5..\"}[5m])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
        
        log_with_timestamp "📊 95th percentile response time: ${response_time}s"
        log_with_timestamp "📊 Error rate: ${error_rate} req/s"
        
        # Kill port-forward
        kill $pf_pid 2>/dev/null || true
    else
        log_with_timestamp "⚠️ Prometheus not available for metrics collection"
    fi
}

# Function to cleanup experiments
cleanup_experiments() {
    log_with_timestamp "🧹 Cleaning up completed experiments..."
    
    # Remove completed workflows
    kubectl delete workflows -n "$NAMESPACE" --field-selector=status.phase=Succeeded &>/dev/null || true
    kubectl delete workflows -n "$NAMESPACE" --field-selector=status.phase=Failed &>/dev/null || true
    
    # Remove completed chaos experiments
    kubectl delete podchaos,networkchaos,stresschaos,iochaos -n "$NAMESPACE" --all &>/dev/null || true
}

# Main monitoring loop
log_with_timestamp "🚀 Starting experiment monitoring..."

# Initial collection
collect_metrics
health_check_services
check_database
check_cache
monitor_performance

# Convert duration to seconds
if [[ "$DURATION" =~ ^([0-9]+)m$ ]]; then
    DURATION_SECONDS=$((${BASH_REMATCH[1]} * 60))
elif [[ "$DURATION" =~ ^([0-9]+)s$ ]]; then
    DURATION_SECONDS=${BASH_REMATCH[1]}
else
    DURATION_SECONDS=300  # Default 5 minutes
fi

log_with_timestamp "⏱️ Monitoring for ${DURATION_SECONDS} seconds..."

# Monitor during experiment
START_TIME=$(date +%s)
CURRENT_TIME=$START_TIME

while [[ $((CURRENT_TIME - START_TIME)) -lt $DURATION_SECONDS ]]; do
    sleep 30
    
    log_with_timestamp "📊 Periodic check ($(( (CURRENT_TIME - START_TIME) / 60 )) minutes elapsed)..."
    
    # Quick health checks
    health_check_services
    check_database
    check_cache
    
    # Check for any alerts or issues
    local failing_pods=$(kubectl get pods -n pyairtable --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$failing_pods" ]]; then
        log_with_timestamp "⚠️ Failing pods detected: $failing_pods"
    fi
    
    CURRENT_TIME=$(date +%s)
done

# Final collection
log_with_timestamp "🏁 Experiment completed. Final metrics collection..."
collect_metrics
health_check_services
check_database
check_cache
monitor_performance

# Cleanup
cleanup_experiments

log_with_timestamp "✅ Monitoring completed successfully!"
log_with_timestamp "📝 Full log available at: ${LOG_FILE}"

echo ""
echo "📋 Monitoring Summary:"
echo "  Experiment: ${EXPERIMENT_NAME}"
echo "  Duration: ${DURATION}"
echo "  Log file: ${LOG_FILE}"
echo ""
echo "🔗 View dashboards:"
echo "  Grafana: kubectl port-forward svc/chaos-grafana 3000:3000 -n chaos-engineering"
echo "  Prometheus: kubectl port-forward svc/chaos-prometheus 9090:9090 -n chaos-engineering"