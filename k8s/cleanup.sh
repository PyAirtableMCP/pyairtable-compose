#!/bin/bash

# Cleanup script for PyAirtable Kubernetes deployment

set -e

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}PyAirtable K8s Cleanup${NC}"
echo -e "${BLUE}=====================================${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Confirm deletion
echo -e "\n${YELLOW}⚠️  WARNING: This will delete all PyAirtable resources!${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo "  - All deployments and pods"
echo "  - All services"
echo "  - All ConfigMaps and Secrets"
echo "  - PostgreSQL data (PersistentVolumeClaims)"
echo "  - The pyairtable namespace"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${BLUE}Cleanup cancelled.${NC}"
    exit 0
fi

# Delete all resources
echo -e "\n${YELLOW}Deleting deployments...${NC}"
kubectl delete -f k8s/api-gateway-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/auth-service-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/core-services-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/go-services-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/python-services-deployment.yaml --ignore-not-found=true

echo -e "\n${YELLOW}Deleting infrastructure...${NC}"
kubectl delete -f k8s/postgres-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/redis-deployment.yaml --ignore-not-found=true

echo -e "\n${YELLOW}Deleting ConfigMaps and Secrets...${NC}"
kubectl delete -f k8s/configmap.yaml --ignore-not-found=true
kubectl delete secret pyairtable-secrets -n pyairtable --ignore-not-found=true
kubectl delete configmap postgres-init-sql -n pyairtable --ignore-not-found=true

# Delete PVCs (this will delete data)
echo -e "\n${YELLOW}Deleting PersistentVolumeClaims...${NC}"
kubectl delete pvc --all -n pyairtable --ignore-not-found=true

# Wait for pods to terminate
echo -e "\n${YELLOW}Waiting for pods to terminate...${NC}"
kubectl wait --for=delete pod --all -n pyairtable --timeout=60s || true

# Delete namespace (this will delete everything else)
echo -e "\n${YELLOW}Deleting namespace...${NC}"
kubectl delete -f k8s/namespace.yaml --ignore-not-found=true

# Clean up local Docker images if requested
echo ""
read -p "Do you also want to remove local Docker images? (yes/no): " remove_images

if [ "$remove_images" = "yes" ]; then
    echo -e "\n${YELLOW}Removing Docker images...${NC}"
    
    # List of all service images
    images=(
        "pyairtable/api-gateway"
        "pyairtable/auth-service"
        "pyairtable/user-service"
        "pyairtable/notification-service"
        "pyairtable/audit-service"
        "pyairtable/config-service"
        "pyairtable/metrics-service"
        "pyairtable/scheduler-service"
        "pyairtable/webhook-service"
        "pyairtable/cache-service"
        "pyairtable/search-service"
        "pyairtable/airtable-gateway"
        "pyairtable/llm-orchestrator"
        "pyairtable/mcp-server"
        "pyairtable/analytics-service"
        "pyairtable/workflow-engine"
        "pyairtable/file-processor"
        "pyairtable/data-pipeline"
        "pyairtable/report-generator"
        "pyairtable/webhook-handler"
        "pyairtable/storage-service"
    )
    
    for image in "${images[@]}"; do
        if docker image inspect "$image:latest" &> /dev/null; then
            echo "Removing $image:latest"
            docker rmi "$image:latest" || true
        fi
    done
    
    # If using minikube, also clean from minikube
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        echo -e "\n${YELLOW}Cleaning Minikube cache...${NC}"
        for image in "${images[@]}"; do
            minikube image rm "$image:latest" || true
        done
    fi
fi

echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"

# Show remaining resources
echo -e "\n${BLUE}Checking for remaining resources...${NC}"
remaining=$(kubectl get all -n pyairtable 2>&1 || echo "")
if echo "$remaining" | grep -q "No resources found"; then
    echo -e "${GREEN}✓ All PyAirtable resources have been removed${NC}"
elif echo "$remaining" | grep -q "NotFound"; then
    echo -e "${GREEN}✓ PyAirtable namespace has been deleted${NC}"
else
    echo -e "${YELLOW}⚠️  Some resources might still exist:${NC}"
    echo "$remaining"
fi