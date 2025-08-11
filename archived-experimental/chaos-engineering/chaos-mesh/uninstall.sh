#!/bin/bash
set -euo pipefail

# Chaos Mesh Uninstallation Script
NAMESPACE="chaos-engineering"

echo "🗑️ Uninstalling Chaos Mesh from PyAirtable"

# Stop any running experiments
echo "🛑 Stopping all running chaos experiments..."
kubectl delete workflows --all -n ${NAMESPACE} || true
kubectl delete podchaos --all -n ${NAMESPACE} || true
kubectl delete networkchaos --all -n ${NAMESPACE} || true
kubectl delete stresschaos --all -n ${NAMESPACE} || true
kubectl delete iochaos --all -n ${NAMESPACE} || true

# Uninstall Chaos Mesh using Helm
echo "📦 Uninstalling Chaos Mesh Helm release..."
helm uninstall chaos-mesh -n ${NAMESPACE} || true

# Remove RBAC
echo "🔐 Removing RBAC configurations..."
kubectl delete -f rbac.yaml || true

# Remove custom experiments
echo "🏗️ Removing custom experiments..."
kubectl delete -f custom-experiments/ || true

# Remove namespace (optional - uncomment if you want to remove it completely)
# echo "📁 Removing namespace: ${NAMESPACE}"
# kubectl delete namespace ${NAMESPACE} || true

echo "✅ Chaos Mesh uninstallation completed!"
echo "Note: The namespace '${NAMESPACE}' was preserved. Delete it manually if needed."