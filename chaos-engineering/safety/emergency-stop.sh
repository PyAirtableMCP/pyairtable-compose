#!/bin/bash
set -euo pipefail

# Emergency Stop Script for PyAirtable Chaos Engineering
# This script immediately stops all running chaos experiments and restores system stability

NAMESPACE="chaos-engineering"
TARGET_NAMESPACE="pyairtable"

echo "🚨 EMERGENCY STOP - Halting all chaos experiments immediately!"
echo "⏰ Timestamp: $(date)"

# Function to log emergency actions
emergency_log() {
    echo "[EMERGENCY] $1"
    logger "PyAirtable Chaos Emergency: $1"
}

emergency_log "Emergency stop initiated by user: $(whoami)"
emergency_log "Target namespace: ${TARGET_NAMESPACE}"

# 1. Stop all running chaos experiments immediately
emergency_log "Step 1: Stopping all chaos experiments..."

echo "🛑 Deleting all active Chaos Mesh experiments..."

# Delete all types of chaos experiments
kubectl delete workflows --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete podchaos --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete networkchaos --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete stresschaos --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete iochaos --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete httpchaos --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete timechaos --all -n "${NAMESPACE}" --ignore-not-found=true &
kubectl delete kernelchaos --all -n "${NAMESPACE}" --ignore-not-found=true &

# Wait for all deletions to complete
wait

emergency_log "All chaos experiments terminated"

# 2. Force restart any stuck or unhealthy pods
emergency_log "Step 2: Restarting unhealthy pods..."

echo "🔄 Checking for and restarting unhealthy pods..."

# Get all pods that are not in Running state
UNHEALTHY_PODS=$(kubectl get pods -n "${TARGET_NAMESPACE}" --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$UNHEALTHY_PODS" ]]; then
    emergency_log "Found unhealthy pods: $UNHEALTHY_PODS"
    echo "🔄 Restarting unhealthy pods..."
    
    for pod in $UNHEALTHY_PODS; do
        echo "  Deleting pod: $pod"
        kubectl delete pod "$pod" -n "${TARGET_NAMESPACE}" --force --grace-period=0 &
    done
    wait
else
    emergency_log "No unhealthy pods found"
fi

# 3. Restart deployments to ensure clean state
emergency_log "Step 3: Rolling restart of critical services..."

echo "🔄 Rolling restart of critical services..."

CRITICAL_DEPLOYMENTS=("api-gateway" "auth-service" "platform-services" "automation-services")

for deployment in "${CRITICAL_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" -n "${TARGET_NAMESPACE}" &>/dev/null; then
        echo "  Restarting deployment: $deployment"
        kubectl rollout restart deployment/"$deployment" -n "${TARGET_NAMESPACE}" &
        emergency_log "Initiated restart for deployment: $deployment"
    else
        emergency_log "Deployment $deployment not found, skipping"
    fi
done

# Wait for all rollouts to complete
echo "⏳ Waiting for rollouts to complete..."
for deployment in "${CRITICAL_DEPLOYMENTS[@]}"; do
    if kubectl get deployment "$deployment" -n "${TARGET_NAMESPACE}" &>/dev/null; then
        kubectl rollout status deployment/"$deployment" -n "${TARGET_NAMESPACE}" --timeout=300s || {
            emergency_log "WARNING: Rollout for $deployment did not complete within timeout"
        }
    fi
done

# 4. Clear any network policies or restrictions
emergency_log "Step 4: Clearing network restrictions..."

echo "🌐 Clearing any chaos-induced network policies..."
kubectl delete networkpolicies -l "created-by=chaos-engineering" -n "${TARGET_NAMESPACE}" --ignore-not-found=true

# 5. Verify system health
emergency_log "Step 5: Verifying system health..."

echo "🏥 Running post-emergency health check..."

# Wait a bit for services to stabilize
sleep 30

# Check pod status
echo "📊 Checking pod status..."
kubectl get pods -n "${TARGET_NAMESPACE}" -o wide

# Check service endpoints
echo "📊 Checking service endpoints..."
kubectl get endpoints -n "${TARGET_NAMESPACE}"

# Verify service health endpoints
echo "🔍 Verifying service health..."

SERVICES=("api-gateway:8080" "auth-service:8081" "platform-services:8000")
HEALTHY_SERVICES=0
TOTAL_SERVICES=${#SERVICES[@]}

for service in "${SERVICES[@]}"; do
    IFS=':' read -r service_name port <<< "$service"
    
    # Get a pod for the service
    pod=$(kubectl get pods -n "${TARGET_NAMESPACE}" -l "app=${service_name}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -n "$pod" ]]; then
        if kubectl exec -n "${TARGET_NAMESPACE}" "$pod" -- curl -f -m 10 "localhost:${port}/health" &>/dev/null; then
            echo "  ✅ ${service_name}: Healthy"
            ((HEALTHY_SERVICES++))
        else
            echo "  ❌ ${service_name}: Unhealthy"
            emergency_log "WARNING: Service $service_name is still unhealthy after emergency recovery"
        fi
    else
        echo "  ❌ ${service_name}: No pod found"
        emergency_log "ERROR: No pod found for service $service_name"
    fi
done

# 6. Generate emergency report
emergency_log "Step 6: Generating emergency report..."

REPORT_FILE="/tmp/chaos-emergency-report-$(date +%Y%m%d-%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
PyAirtable Chaos Engineering Emergency Stop Report
================================================

Timestamp: $(date)
Executed by: $(whoami)
Target namespace: ${TARGET_NAMESPACE}

Actions Taken:
1. ✅ All chaos experiments terminated
2. ✅ Unhealthy pods restarted
3. ✅ Critical services rolling restarted
4. ✅ Network restrictions cleared
5. ✅ System health verified

Health Status After Recovery:
- Total services checked: ${TOTAL_SERVICES}
- Healthy services: ${HEALTHY_SERVICES}
- Success rate: $(( HEALTHY_SERVICES * 100 / TOTAL_SERVICES ))%

Pod Status:
$(kubectl get pods -n "${TARGET_NAMESPACE}" -o wide)

Service Endpoints:
$(kubectl get endpoints -n "${TARGET_NAMESPACE}")

Recent Events:
$(kubectl get events -n "${TARGET_NAMESPACE}" --sort-by=.metadata.creationTimestamp | tail -20)

Recommendations:
$(if [[ $HEALTHY_SERVICES -eq $TOTAL_SERVICES ]]; then
    echo "✅ All services are healthy. System recovery successful."
else
    echo "⚠️ Some services are still unhealthy. Manual intervention may be required."
    echo "- Check service logs: kubectl logs -n ${TARGET_NAMESPACE} -l app=<service-name>"
    echo "- Verify configuration and secrets"
    echo "- Consider redeploying affected services"
fi)
EOF

emergency_log "Emergency report generated: $REPORT_FILE"

# 7. Final status
echo ""
echo "🚨 EMERGENCY STOP COMPLETED"
echo "⏰ Total time: $(date)"
echo "📊 Service health: ${HEALTHY_SERVICES}/${TOTAL_SERVICES} services healthy"
echo "📝 Report: $REPORT_FILE"

if [[ $HEALTHY_SERVICES -eq $TOTAL_SERVICES ]]; then
    echo "✅ System recovery successful!"
    emergency_log "Emergency recovery completed successfully"
    exit 0
else
    echo "⚠️ Some services may need manual attention"
    echo "📋 Next steps:"
    echo "  1. Check logs: kubectl logs -n ${TARGET_NAMESPACE} -l app=<unhealthy-service>"
    echo "  2. Verify secrets and config: kubectl get secrets,configmaps -n ${TARGET_NAMESPACE}"
    echo "  3. Check resource availability: kubectl describe nodes"
    echo "  4. Consider manual service restart if needed"
    
    emergency_log "Emergency recovery completed with warnings - manual intervention may be required"
    exit 1
fi