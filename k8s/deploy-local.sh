#!/bin/bash

# Deploy PyAirtable to local Kubernetes (Minikube/Docker Desktop)

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}PyAirtable Kubernetes Deployment${NC}"
echo -e "${BLUE}=====================================${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Kubernetes cluster not accessible. Please start minikube or enable Kubernetes in Docker Desktop.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Kubernetes cluster is accessible${NC}"

# Create namespace
echo -e "\n${YELLOW}Creating namespace...${NC}"
kubectl apply -f k8s/namespace.yaml

# Create secrets (you should modify these values)
echo -e "\n${YELLOW}Creating secrets...${NC}"
kubectl create secret generic pyairtable-secrets \
    --namespace=pyairtable \
    --from-literal=postgres-password=changeme \
    --from-literal=redis-password=changeme \
    --from-literal=jwt-secret=your-jwt-secret-at-least-32-chars \
    --from-literal=airtable-token=${AIRTABLE_TOKEN:-your-airtable-token} \
    --from-literal=gemini-api-key=${GEMINI_API_KEY:-your-gemini-api-key} \
    --from-literal=api-key=your-internal-api-key \
    --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap for init SQL
echo -e "\n${YELLOW}Creating PostgreSQL init ConfigMap...${NC}"
kubectl create configmap postgres-init-sql \
    --namespace=pyairtable \
    --from-file=init.sql=init-db.sql \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply configurations
echo -e "\n${YELLOW}Applying configurations...${NC}"
kubectl apply -f k8s/configmap.yaml

# Deploy infrastructure services
echo -e "\n${YELLOW}Deploying infrastructure services...${NC}"
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/redis-deployment.yaml

# Wait for infrastructure to be ready
echo -e "\n${YELLOW}Waiting for infrastructure services...${NC}"
kubectl wait --namespace=pyairtable --for=condition=ready pod -l app=postgres --timeout=120s
kubectl wait --namespace=pyairtable --for=condition=ready pod -l app=redis --timeout=120s

# Build and load Docker images (for local development)
echo -e "\n${YELLOW}Building Docker images...${NC}"
echo "Note: In production, you would push these to a registry"

# Function to build and load image
build_and_load() {
    local service=$1
    local path=$2
    
    echo -e "${BLUE}Building $service...${NC}"
    docker build -t pyairtable/$service:latest $path
    
    # If using minikube, load the image
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        echo "Loading image to minikube..."
        minikube image load pyairtable/$service:latest
    fi
}

# Build Go services
echo -e "\n${BLUE}Building Go services...${NC}"
build_and_load "api-gateway" "go-services/api-gateway"
build_and_load "auth-service" "go-services/auth-service"
build_and_load "user-service" "go-services/user-service"
build_and_load "notification-service" "go-services/notification-service"
build_and_load "audit-service" "go-services/audit-service"
build_and_load "config-service" "go-services/config-service"
build_and_load "metrics-service" "go-services/metrics-service"
build_and_load "scheduler-service" "go-services/scheduler-service"
build_and_load "webhook-service" "go-services/webhook-service"
build_and_load "cache-service" "go-services/cache-service"
build_and_load "search-service" "go-services/search-service"

# Build Python services
echo -e "\n${BLUE}Building Python services...${NC}"
build_and_load "airtable-gateway" "python-services/airtable-gateway"
build_and_load "llm-orchestrator" "python-services/llm-orchestrator"
build_and_load "mcp-server" "python-services/mcp-server"
build_and_load "analytics-service" "python-services/analytics-service"
build_and_load "workflow-engine" "python-services/workflow-engine"
build_and_load "file-processor" "python-services/file-processor"
build_and_load "data-pipeline" "python-services/data-pipeline"
build_and_load "report-generator" "python-services/report-generator"
build_and_load "webhook-handler" "python-services/webhook-handler"
build_and_load "storage-service" "python-services/storage-service"

# Deploy all services
echo -e "\n${YELLOW}Deploying all services...${NC}"
kubectl apply -f k8s/api-gateway-deployment.yaml
kubectl apply -f k8s/auth-service-deployment.yaml
kubectl apply -f k8s/core-services-deployment.yaml
kubectl apply -f k8s/go-services-deployment.yaml
kubectl apply -f k8s/python-services-deployment.yaml

# Wait for core deployments first
echo -e "\n${YELLOW}Waiting for core deployments to be ready...${NC}"
kubectl wait --namespace=pyairtable --for=condition=available deployment/api-gateway --timeout=180s
kubectl wait --namespace=pyairtable --for=condition=available deployment/auth-service --timeout=180s
kubectl wait --namespace=pyairtable --for=condition=available deployment/airtable-gateway --timeout=180s
kubectl wait --namespace=pyairtable --for=condition=available deployment/llm-orchestrator --timeout=180s
kubectl wait --namespace=pyairtable --for=condition=available deployment/mcp-server --timeout=180s

# Wait for remaining deployments
echo -e "\n${YELLOW}Waiting for all remaining deployments...${NC}"
kubectl wait --namespace=pyairtable --for=condition=available deployment --all --timeout=300s

# Get service URLs
echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"

# Get API Gateway URL
if command -v minikube &> /dev/null && minikube status &> /dev/null; then
    API_URL=$(minikube service api-gateway --namespace=pyairtable --url)
    echo -e "\n${BLUE}API Gateway URL (Minikube):${NC} $API_URL"
else
    echo -e "\n${BLUE}API Gateway URL (NodePort):${NC} http://localhost:30080"
fi

echo -e "\n${BLUE}Service Status:${NC}"
kubectl get pods -n pyairtable

echo -e "\n${BLUE}Services:${NC}"
kubectl get services -n pyairtable

echo -e "\n${YELLOW}Useful commands:${NC}"
echo "  View logs: kubectl logs -n pyairtable deployment/api-gateway"
echo "  Port forward: kubectl port-forward -n pyairtable service/api-gateway 8080:8080"
echo "  Get pods: kubectl get pods -n pyairtable"
echo "  Describe pod: kubectl describe pod -n pyairtable <pod-name>"
echo "  Delete deployment: kubectl delete -f k8s/"