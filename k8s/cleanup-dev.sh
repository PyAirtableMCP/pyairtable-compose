#!/bin/bash

# PyAirtable Development Cleanup Script for Kubernetes/Minikube

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧹 Starting PyAirtable Development Cleanup${NC}"

# Check if kubectl is configured for minikube
if ! kubectl config current-context | grep -q "minikube"; then
    echo -e "${YELLOW}⚠️  Setting kubectl context to minikube${NC}"
    kubectl config use-context minikube
fi

# Warning prompt
echo -e "${YELLOW}⚠️  This will delete ALL PyAirtable resources from the 'pyairtable' namespace${NC}"
echo -e "${RED}🚨 This action is IRREVERSIBLE and will delete all data!${NC}"
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY == "yes" ]]; then
    echo -e "${GREEN}✅ Cleanup cancelled${NC}"
    exit 0
fi

# Uninstall Helm chart
echo -e "${BLUE}📦 Uninstalling Helm chart 'pyairtable-dev'${NC}"
if helm list -n pyairtable | grep -q pyairtable-dev; then
    helm uninstall pyairtable-dev --namespace pyairtable
    echo -e "${GREEN}✅ Helm chart uninstalled${NC}"
else
    echo -e "${YELLOW}⚠️  Helm chart 'pyairtable-dev' not found${NC}"
fi

# Delete any remaining resources in the namespace
echo -e "${BLUE}🗑️  Deleting remaining resources in 'pyairtable' namespace${NC}"
kubectl delete all --all -n pyairtable || true
kubectl delete pvc --all -n pyairtable || true
kubectl delete secrets --all -n pyairtable || true
kubectl delete configmaps --all -n pyairtable || true
kubectl delete ingress --all -n pyairtable || true

# Delete the namespace
echo -e "${BLUE}🗑️  Deleting 'pyairtable' namespace${NC}"
kubectl delete namespace pyairtable || true

# Wait for namespace deletion
echo -e "${BLUE}⏳ Waiting for namespace to be fully deleted...${NC}"
while kubectl get namespace pyairtable >/dev/null 2>&1; do
    echo -e "${YELLOW}⏳ Still waiting for namespace deletion...${NC}"
    sleep 5
done

echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
echo -e "${BLUE}📊 Remaining namespaces:${NC}"
kubectl get namespaces

# Optional: Also clean up Minikube
echo ""
read -p "Do you also want to delete the entire Minikube cluster? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🗑️  Deleting Minikube cluster${NC}"
    minikube delete
    echo -e "${GREEN}✅ Minikube cluster deleted${NC}"
else
    echo -e "${BLUE}💡 Minikube cluster preserved. You can access it with 'kubectl' commands${NC}"
fi

echo -e "${GREEN}🎉 All cleanup operations completed!${NC}"