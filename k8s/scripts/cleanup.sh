#!/bin/bash

# PyAirtable Cleanup Script for Kubernetes
# Removes PyAirtable services and optionally the entire cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${1:-pyairtable}"
CLUSTER_TYPE="${CLUSTER_TYPE:-minikube}"

echo -e "${BLUE}🧹 PyAirtable Cleanup Script${NC}"
echo -e "${BLUE}🎯 Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}🏗️  Cluster Type: ${CLUSTER_TYPE}${NC}"

# Function to cleanup PyAirtable services
cleanup_services() {
    echo -e "${BLUE}🗑️  Cleaning up PyAirtable services${NC}"
    
    # Remove Helm releases
    echo -e "${YELLOW}📦 Removing Helm releases${NC}"
    helm uninstall pyairtable-dev -n "$NAMESPACE" 2>/dev/null || echo -e "${YELLOW}⚠️  pyairtable-dev release not found${NC}"
    helm uninstall postgresql-dev -n "$NAMESPACE" 2>/dev/null || echo -e "${YELLOW}⚠️  postgresql-dev release not found${NC}"
    helm uninstall redis-dev -n "$NAMESPACE" 2>/dev/null || echo -e "${YELLOW}⚠️  redis-dev release not found${NC}"
    
    # Remove any remaining resources in the namespace
    echo -e "${YELLOW}🧹 Cleaning up remaining resources${NC}"
    kubectl delete all --all -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete secrets --all -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete configmaps --all -n "$NAMESPACE" 2>/dev/null || true
    
    # Remove the namespace
    echo -e "${YELLOW}🗂️  Removing namespace${NC}"
    kubectl delete namespace "$NAMESPACE" 2>/dev/null || echo -e "${YELLOW}⚠️  Namespace $NAMESPACE not found${NC}"
    
    echo -e "${GREEN}✅ PyAirtable services cleaned up${NC}"
}

# Function to cleanup Docker images
cleanup_docker_images() {
    echo -e "${BLUE}🐳 Cleaning up Docker images${NC}"
    
    # Remove PyAirtable images
    local images=(
        "pyairtable-api-gateway"
        "pyairtable-platform-services" 
        "pyairtable-automation-services"
        "pyairtable-llm-orchestrator"
        "pyairtable-mcp-server"
        "pyairtable-airtable-gateway"
        "pyairtable-frontend"
    )
    
    for image in "${images[@]}"; do
        echo -e "${YELLOW}🗑️  Removing $image images${NC}"
        docker rmi $(docker images --format "table {{.Repository}}:{{.Tag}}" | grep "$image" | tr -s ' ' ':') 2>/dev/null || true
    done
    
    # Clean up dangling images
    echo -e "${YELLOW}🧹 Removing dangling images${NC}"
    docker image prune -f 2>/dev/null || true
    
    echo -e "${GREEN}✅ Docker images cleaned up${NC}"
}

# Function to cleanup Minikube cluster
cleanup_minikube() {
    echo -e "${BLUE}🏗️  Cleaning up Minikube cluster${NC}"
    
    # Stop Minikube
    echo -e "${YELLOW}🛑 Stopping Minikube${NC}"
    minikube stop 2>/dev/null || echo -e "${YELLOW}⚠️  Minikube was not running${NC}"
    
    # Delete Minikube cluster
    echo -e "${YELLOW}🗑️  Deleting Minikube cluster${NC}"
    minikube delete 2>/dev/null || echo -e "${YELLOW}⚠️  Minikube cluster not found${NC}"
    
    echo -e "${GREEN}✅ Minikube cluster cleaned up${NC}"
}

# Function to cleanup Kind cluster
cleanup_kind() {
    echo -e "${BLUE}🏗️  Cleaning up Kind cluster${NC}"
    
    # Delete Kind cluster
    echo -e "${YELLOW}🗑️  Deleting Kind cluster 'pyairtable'${NC}"
    kind delete cluster --name pyairtable 2>/dev/null || echo -e "${YELLOW}⚠️  Kind cluster 'pyairtable' not found${NC}"
    
    # Remove local registry
    echo -e "${YELLOW}🗑️  Removing local registry${NC}"
    docker stop kind-registry 2>/dev/null || true
    docker rm kind-registry 2>/dev/null || true
    
    echo -e "${GREEN}✅ Kind cluster cleaned up${NC}"
}

# Function to cleanup persistent data
cleanup_persistent_data() {
    echo -e "${BLUE}💾 Cleaning up persistent data${NC}"
    
    # Remove Docker volumes
    echo -e "${YELLOW}🗑️  Removing Docker volumes${NC}"
    docker volume rm $(docker volume ls -q | grep -E "(postgres|redis|pyairtable)") 2>/dev/null || true
    
    # Remove temporary files
    echo -e "${YELLOW}🧹 Removing temporary files${NC}"
    rm -f /tmp/pyairtable-*-pids 2>/dev/null || true
    rm -f /tmp/pyairtable-*-report-*.txt 2>/dev/null || true
    
    echo -e "${GREEN}✅ Persistent data cleaned up${NC}"
}

# Function to cleanup Istio
cleanup_istio() {
    echo -e "${BLUE}🕸️  Cleaning up Istio${NC}"
    
    # Remove Istio injection label
    kubectl label namespace "$NAMESPACE" istio-injection- 2>/dev/null || true
    
    # Check if user wants to remove Istio completely
    read -p "Remove Istio completely from the cluster? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}🗑️  Removing Istio${NC}"
        istioctl uninstall --purge -y 2>/dev/null || echo -e "${YELLOW}⚠️  Istio not found or already removed${NC}"
        kubectl delete namespace istio-system 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Istio cleanup complete${NC}"
}

# Function to show cleanup options
show_cleanup_options() {
    echo -e "${BLUE}🧹 Cleanup Options:${NC}"
    echo -e "1. Services only (keep cluster)"
    echo -e "2. Services + Docker images"
    echo -e "3. Services + Persistent data"
    echo -e "4. Complete cleanup (services + cluster)"
    echo -e "5. Custom cleanup"
    echo -e "6. Cancel"
    echo ""
}

# Function to perform custom cleanup
custom_cleanup() {
    echo -e "${BLUE}🎛️  Custom Cleanup Options:${NC}"
    echo ""
    
    # Services cleanup
    read -p "Remove PyAirtable services? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        CLEANUP_SERVICES=false
    else
        CLEANUP_SERVICES=true
    fi
    
    # Docker images cleanup
    read -p "Remove Docker images? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_IMAGES=true
    else
        CLEANUP_IMAGES=false
    fi
    
    # Persistent data cleanup
    read -p "Remove persistent data (volumes, files)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_DATA=true
    else
        CLEANUP_DATA=false
    fi
    
    # Istio cleanup
    if kubectl get namespace istio-system >/dev/null 2>&1; then
        read -p "Cleanup Istio? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            CLEANUP_ISTIO=true
        else
            CLEANUP_ISTIO=false
        fi
    else
        CLEANUP_ISTIO=false
    fi
    
    # Cluster cleanup
    read -p "Remove entire cluster? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_CLUSTER=true
    else
        CLEANUP_CLUSTER=false
    fi
    
    # Execute custom cleanup
    echo -e "${BLUE}🚀 Starting custom cleanup...${NC}"
    
    if [ "$CLEANUP_SERVICES" = true ]; then
        cleanup_services
    fi
    
    if [ "$CLEANUP_IMAGES" = true ]; then
        cleanup_docker_images
    fi
    
    if [ "$CLEANUP_DATA" = true ]; then
        cleanup_persistent_data
    fi
    
    if [ "$CLEANUP_ISTIO" = true ]; then
        cleanup_istio
    fi
    
    if [ "$CLEANUP_CLUSTER" = true ]; then
        if [ "$CLUSTER_TYPE" == "minikube" ]; then
            cleanup_minikube
        elif [ "$CLUSTER_TYPE" == "kind" ]; then
            cleanup_kind
        fi
    fi
}

# Main cleanup function
main() {
    echo -e "${YELLOW}⚠️  WARNING: This will remove PyAirtable components!${NC}"
    echo -e "${YELLOW}Make sure you have backed up any important data.${NC}"
    echo ""
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Namespace '$NAMESPACE' not found. Services may already be cleaned up.${NC}"
        
        # Still offer cluster cleanup
        read -p "Remove the entire cluster anyway? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ "$CLUSTER_TYPE" == "minikube" ]; then
                cleanup_minikube
            elif [ "$CLUSTER_TYPE" == "kind" ]; then
                cleanup_kind
            fi
        fi
        return 0
    fi
    
    # Show current status
    echo -e "${BLUE}📋 Current Status:${NC}"
    kubectl get all -n "$NAMESPACE" 2>/dev/null || echo "No resources found"
    echo ""
    
    # Show cleanup options
    show_cleanup_options
    
    read -p "Select an option (1-6): " -n 1 -r
    echo
    echo ""
    
    case $REPLY in
        1)
            echo -e "${BLUE}🧹 Services only cleanup${NC}"
            cleanup_services
            ;;
        2)
            echo -e "${BLUE}🧹 Services + Docker images cleanup${NC}"
            cleanup_services
            cleanup_docker_images
            ;;
        3)
            echo -e "${BLUE}🧹 Services + Persistent data cleanup${NC}"
            cleanup_services
            cleanup_persistent_data
            ;;
        4)
            echo -e "${BLUE}🧹 Complete cleanup${NC}"
            cleanup_services
            cleanup_docker_images
            cleanup_persistent_data
            if [ "$CLUSTER_TYPE" == "minikube" ]; then
                cleanup_minikube
            elif [ "$CLUSTER_TYPE" == "kind" ]; then
                cleanup_kind
            fi
            ;;
        5)
            custom_cleanup
            ;;
        6)
            echo -e "${YELLOW}Cleanup cancelled${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
    
    # Show final status
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${BLUE}📋 Remaining resources in namespace '$NAMESPACE':${NC}"
        kubectl get all -n "$NAMESPACE" 2>/dev/null || echo "No resources found"
    else
        echo -e "${GREEN}✅ Namespace '$NAMESPACE' has been removed${NC}"
    fi
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-type)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [NAMESPACE] [OPTIONS]"
            echo "Options:"
            echo "  NAMESPACE            Target Kubernetes namespace (default: pyairtable)"
            echo "  --cluster-type TYPE  Cluster type: minikube or kind (default: minikube)"
            echo "  --force             Skip confirmations and force cleanup"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            NAMESPACE="$1"
            shift
            ;;
    esac
done

# Force cleanup mode
if [ "$FORCE_CLEANUP" = true ]; then
    echo -e "${RED}🚨 FORCE CLEANUP MODE - No confirmations will be asked${NC}"
    cleanup_services
    cleanup_docker_images
    cleanup_persistent_data
    if [ "$CLUSTER_TYPE" == "minikube" ]; then
        cleanup_minikube
    elif [ "$CLUSTER_TYPE" == "kind" ]; then
        cleanup_kind
    fi
    echo -e "${GREEN}🎉 Force cleanup completed!${NC}"
    exit 0
fi

# Execute main function
main "$@"