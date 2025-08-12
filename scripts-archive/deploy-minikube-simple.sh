#!/bin/bash

# Simple PyAirtable Minikube Deployment Script
# Deploys only the working services after fixing Docker build issues

set -e

echo "🚀 Deploying Fixed PyAirtable Services to Minikube"
echo "=================================================="

# Configuration
NAMESPACE="pyairtable-customer"

# Check prerequisites
echo "✅ Checking prerequisites..."
if ! command -v minikube &> /dev/null; then
    echo "❌ Minikube not found! Please install Minikube"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found! Please install kubectl"
    exit 1
fi

# Start Minikube if not running
if ! minikube status &> /dev/null; then
    echo "🏁 Starting Minikube..."
    minikube start --memory=4096 --cpus=2
fi

echo "✅ Minikube is running"

# Apply all manifests
echo "📦 Applying Kubernetes manifests..."
kubectl apply -f minikube-manifests/

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
echo "This may take a few minutes for the first deployment..."

# Wait for databases first
kubectl wait --for=condition=available deployment/postgres -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/redis -n $NAMESPACE --timeout=300s

# Wait for application services
kubectl wait --for=condition=available deployment/airtable-gateway -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/mcp-server -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/llm-orchestrator -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/platform-services -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=available deployment/automation-services -n $NAMESPACE --timeout=300s

# Show deployment status
echo ""
echo "📊 Deployment Status:"
kubectl get pods -n $NAMESPACE
echo ""
kubectl get services -n $NAMESPACE

echo ""
echo "🎉 PyAirtable deployed successfully to Minikube!"
echo ""
echo "📋 Important: Update secrets with actual customer credentials:"
echo "kubectl edit secret pyairtable-secrets -n $NAMESPACE"
echo ""
echo "Replace the base64 encoded values with:"
echo "  AIRTABLE_TOKEN: [customer's Airtable PAT]"
echo "  AIRTABLE_BASE: [customer's base ID]" 
echo "  GEMINI_API_KEY: [customer's Gemini API key]"
echo ""
echo "🌐 Access services via port forwarding:"
echo "kubectl port-forward -n $NAMESPACE service/airtable-gateway-service 8002:8002 &"
echo "kubectl port-forward -n $NAMESPACE service/mcp-server-service 8001:8001 &"
echo "kubectl port-forward -n $NAMESPACE service/llm-orchestrator-service 8003:8003 &"
echo "kubectl port-forward -n $NAMESPACE service/platform-services-service 8007:8007 &"
echo "kubectl port-forward -n $NAMESPACE service/automation-services-service 8006:8006 &"
echo ""
echo "🧪 Test the deployment:"
echo "curl http://localhost:8003/health"
echo ""
echo "📜 View logs:"
echo "kubectl logs -f deployment/llm-orchestrator -n $NAMESPACE"