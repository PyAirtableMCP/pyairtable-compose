#!/bin/bash

# PyAirtable Development Deployment Script for Kubernetes/Minikube

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting PyAirtable Development Deployment${NC}"

# Check if Minikube is running
if ! minikube status | grep -q "Running"; then
    echo -e "${RED}❌ Minikube is not running. Please start it first:${NC}"
    echo "   minikube start --memory=2500 --cpus=2"
    exit 1
fi

# Check if kubectl is configured for minikube
if ! kubectl config current-context | grep -q "minikube"; then
    echo -e "${YELLOW}⚠️  Setting kubectl context to minikube${NC}"
    kubectl config use-context minikube
fi

# Create namespace if it doesn't exist
echo -e "${BLUE}📦 Creating namespace 'pyairtable'${NC}"
kubectl create namespace pyairtable --dry-run=client -o yaml | kubectl apply -f -

# Deploy the Helm chart
echo -e "${BLUE}🎯 Deploying PyAirtable stack with Helm${NC}"
helm upgrade --install pyairtable-dev ./helm/pyairtable-stack \
    --namespace pyairtable \
    --values ./helm/pyairtable-stack/values-dev.yaml \
    --timeout 10m \
    --wait

# Check deployment status
echo -e "${BLUE}🔍 Checking deployment status${NC}"
kubectl get pods -n pyairtable

# Wait for all deployments to be ready
echo -e "${BLUE}⏳ Waiting for all services to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment --all -n pyairtable

# Get service information
echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "${BLUE}📋 Service Information:${NC}"
kubectl get services -n pyairtable

# Setup port forwarding for local access
echo -e "${BLUE}🌐 Setting up port forwarding for local access${NC}"
echo -e "${YELLOW}Run these commands in separate terminals to access services:${NC}"
echo -e "Frontend:          kubectl port-forward -n pyairtable service/frontend 3000:3000"
echo -e "API Gateway:       kubectl port-forward -n pyairtable service/api-gateway 8000:8000"
echo -e "LLM Orchestrator:  kubectl port-forward -n pyairtable service/llm-orchestrator 8003:8003"
echo -e "MCP Server:        kubectl port-forward -n pyairtable service/mcp-server 8001:8001"
echo -e "Airtable Gateway:  kubectl port-forward -n pyairtable service/airtable-gateway 8002:8002"
echo -e "Platform Services: kubectl port-forward -n pyairtable service/platform-services 8007:8007"
echo -e "Automation Services: kubectl port-forward -n pyairtable service/automation-services 8006:8006"

echo -e "\n${GREEN}🎉 PyAirtable is now running on Kubernetes!${NC}"
echo -e "${BLUE}📊 To view the Kubernetes dashboard: minikube dashboard${NC}"
echo -e "${BLUE}🔧 To debug issues: kubectl logs -f deployment/DEPLOYMENT_NAME -n pyairtable${NC}"

# Optional: Start port forwarding automatically
read -p "Start port forwarding for frontend and API gateway automatically? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🚀 Starting port forwarding...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop port forwarding${NC}"
    
    # Start port forwarding in background
    kubectl port-forward -n pyairtable service/frontend 3000:3000 &
    FRONTEND_PID=$!
    kubectl port-forward -n pyairtable service/api-gateway 8000:8000 &
    API_GATEWAY_PID=$!
    
    echo -e "${GREEN}✅ Port forwarding started:${NC}"
    echo -e "   Frontend: http://localhost:3000"
    echo -e "   API Gateway: http://localhost:8000"
    
    # Wait for user to stop
    trap "kill $FRONTEND_PID $API_GATEWAY_PID 2>/dev/null; exit" INT
    wait
fi