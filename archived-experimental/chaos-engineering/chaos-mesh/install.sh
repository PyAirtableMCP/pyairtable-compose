#!/bin/bash
set -euo pipefail

# Chaos Mesh Installation Script for PyAirtable
# This script installs Chaos Mesh in the Kubernetes cluster

CHAOS_MESH_VERSION="2.7.0"
NAMESPACE="chaos-engineering"

echo "🔧 Installing Chaos Mesh v${CHAOS_MESH_VERSION} for PyAirtable"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

# Create namespace
echo "📁 Creating namespace: ${NAMESPACE}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Add Chaos Mesh Helm repository
echo "📦 Adding Chaos Mesh Helm repository"
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

# Install Chaos Mesh using Helm
echo "🚀 Installing Chaos Mesh..."
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
    --namespace=${NAMESPACE} \
    --version=${CHAOS_MESH_VERSION} \
    --set chaosDaemon.runtime=containerd \
    --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
    --set dashboard.securityMode=false \
    --set dashboard.persistentVolume.enabled=true \
    --set dashboard.persistentVolume.size=1Gi \
    --wait \
    --timeout=600s

# Verify installation
echo "✅ Verifying Chaos Mesh installation..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/instance=chaos-mesh -n ${NAMESPACE} --timeout=300s

# Get dashboard access info
echo "🎯 Chaos Mesh Dashboard Access:"
echo "To access the dashboard locally, run:"
echo "kubectl port-forward svc/chaos-dashboard 2333:2333 -n ${NAMESPACE}"
echo "Then open http://localhost:2333 in your browser"

# Create RBAC for chaos experiments
echo "🔐 Setting up RBAC for chaos experiments..."
kubectl apply -f rbac.yaml

# Install custom resource definitions for PyAirtable
echo "🏗️ Installing PyAirtable-specific chaos experiments..."
kubectl apply -f custom-experiments/

echo "✨ Chaos Mesh installation completed successfully!"
echo "📋 Next steps:"
echo "1. Port-forward the dashboard: kubectl port-forward svc/chaos-dashboard 2333:2333 -n ${NAMESPACE}"
echo "2. Run your first experiment: cd ../experiments && ./run-experiment.sh basic-pod-failure"
echo "3. Monitor results in the dashboard and observability tools"