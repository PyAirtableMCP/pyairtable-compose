#!/bin/bash
set -euo pipefail

# Chaos Experiment Runner for PyAirtable
# Usage: ./run-experiment.sh <experiment-name> [duration] [--dry-run]

EXPERIMENT_NAME="${1:-}"
DURATION="${2:-5m}"
DRY_RUN="${3:-}"
NAMESPACE="chaos-engineering"

if [[ -z "$EXPERIMENT_NAME" ]]; then
    echo "❌ Usage: $0 <experiment-name> [duration] [--dry-run]"
    echo ""
    echo "Available experiments:"
    echo "  basic-pod-failure       - Kill random pods and test recovery"
    echo "  network-resilience      - Test network delays and partitions"
    echo "  database-stress         - Stress database connections and I/O"
    echo "  cache-unavailability    - Simulate Redis cache failures"
    echo "  resource-exhaustion     - CPU/Memory/Disk stress testing"
    echo "  full-resilience-suite   - Complete resilience testing workflow"
    echo "  gradual-failure         - Progressive failure simulation"
    echo "  disaster-recovery       - Multi-component failure testing"
    exit 1
fi

echo "🧪 Running chaos experiment: ${EXPERIMENT_NAME}"
echo "⏱️ Duration: ${DURATION}"
echo "🎯 Target namespace: pyairtable"

# Safety check - ensure monitoring is running
echo "🔍 Checking monitoring stack..."
if ! kubectl get pods -n monitoring | grep -q "prometheus.*Running"; then
    echo "⚠️ Warning: Prometheus monitoring not detected. Consider deploying monitoring first."
fi

if ! kubectl get pods -n pyairtable | grep -q "Running"; then
    echo "❌ Error: No running pods found in pyairtable namespace"
    exit 1
fi

# Pre-experiment health check
echo "🏥 Running pre-experiment health check..."
./health-check.sh pre || {
    echo "❌ Pre-experiment health check failed. Aborting experiment."
    exit 1
}

# Execute the specific experiment
case "$EXPERIMENT_NAME" in
    "basic-pod-failure")
        echo "🎯 Executing basic pod failure experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/basic-pod-failure.yaml
        else
            kubectl apply -f experiments/basic-pod-failure.yaml
            ./monitor-experiment.sh basic-pod-failure "$DURATION"
        fi
        ;;
    
    "network-resilience")
        echo "🌐 Executing network resilience experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/network-resilience.yaml
        else
            kubectl apply -f experiments/network-resilience.yaml
            ./monitor-experiment.sh network-resilience "$DURATION"
        fi
        ;;
    
    "database-stress")
        echo "🗄️ Executing database stress experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/database-stress.yaml
        else
            kubectl apply -f experiments/database-stress.yaml
            ./monitor-experiment.sh database-stress "$DURATION"
        fi
        ;;
    
    "cache-unavailability")
        echo "⚡ Executing cache unavailability experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/cache-unavailability.yaml
        else
            kubectl apply -f experiments/cache-unavailability.yaml
            ./monitor-experiment.sh cache-unavailability "$DURATION"
        fi
        ;;
    
    "resource-exhaustion")
        echo "💾 Executing resource exhaustion experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/resource-exhaustion.yaml
        else
            kubectl apply -f experiments/resource-exhaustion.yaml
            ./monitor-experiment.sh resource-exhaustion "$DURATION"
        fi
        ;;
    
    "full-resilience-suite")
        echo "🚀 Executing full resilience suite..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f ../chaos-mesh/custom-experiments/pyairtable-workflow.yaml
        else
            kubectl apply -f ../chaos-mesh/custom-experiments/pyairtable-workflow.yaml
            ./monitor-workflow.sh pyairtable-resilience-test
        fi
        ;;
    
    "gradual-failure")
        echo "📈 Executing gradual failure experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/gradual-failure.yaml
        else
            kubectl apply -f experiments/gradual-failure.yaml
            ./monitor-experiment.sh gradual-failure "$DURATION"
        fi
        ;;
    
    "disaster-recovery")
        echo "🆘 Executing disaster recovery experiment..."
        if [[ "$DRY_RUN" == "--dry-run" ]]; then
            kubectl apply --dry-run=client -f experiments/disaster-recovery.yaml
        else
            kubectl apply -f experiments/disaster-recovery.yaml
            ./monitor-experiment.sh disaster-recovery "$DURATION"
        fi
        ;;
    
    *)
        echo "❌ Unknown experiment: $EXPERIMENT_NAME"
        exit 1
        ;;
esac

if [[ "$DRY_RUN" != "--dry-run" ]]; then
    # Post-experiment health check
    echo "🏥 Running post-experiment health check..."
    sleep 30  # Allow time for recovery
    ./health-check.sh post
    
    echo "📊 Experiment completed. Check monitoring dashboards for results."
    echo "🔗 Grafana: kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    echo "🔗 Chaos Dashboard: kubectl port-forward svc/chaos-dashboard 2333:2333 -n chaos-engineering"
fi