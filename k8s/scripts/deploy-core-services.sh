#!/bin/bash

# PyAirtable Core Services Deployment Script for Kubernetes
# This script builds Docker images for Go services and deploys them to Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="${PROJECT_ROOT:-/Users/kg/IdeaProjects/pyairtable-compose}"
NAMESPACE="${NAMESPACE:-pyairtable}"
CLUSTER_TYPE="${CLUSTER_TYPE:-minikube}"  # minikube or kind
IMAGE_REGISTRY="${IMAGE_REGISTRY:-localhost:5000}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

# Service configuration
GO_SERVICES=("api-gateway" "platform-services" "automation-services")
PYTHON_SERVICES=("llm-orchestrator" "mcp-server" "airtable-gateway" "frontend")

echo -e "${BLUE}🚀 Starting PyAirtable Core Services Deployment${NC}"
echo -e "${BLUE}📁 Project Root: ${PROJECT_ROOT}${NC}"
echo -e "${BLUE}🎯 Target Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}🏗️  Cluster Type: ${CLUSTER_TYPE}${NC}"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites${NC}"
    
    local missing_tools=()
    
    # Check required tools
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    
    if [ "$CLUSTER_TYPE" == "minikube" ]; then
        command -v minikube >/dev/null 2>&1 || missing_tools+=("minikube")
    elif [ "$CLUSTER_TYPE" == "kind" ]; then
        command -v kind >/dev/null 2>&1 || missing_tools+=("kind")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}Please install the missing tools and try again${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites satisfied${NC}"
}

# Function to setup cluster
setup_cluster() {
    echo -e "${BLUE}🏗️  Setting up Kubernetes cluster${NC}"
    
    if [ "$CLUSTER_TYPE" == "minikube" ]; then
        # Check if Minikube is running
        if ! minikube status | grep -q "Running"; then
            echo -e "${YELLOW}⚠️  Starting Minikube cluster${NC}"
            minikube start --memory=4000 --cpus=3 --disk-size=20g \
                --addons=ingress,registry,metrics-server,dashboard
        fi
        
        # Use Minikube Docker environment
        eval $(minikube docker-env)
        IMAGE_REGISTRY="localhost:5000"
        
        # Ensure registry addon is enabled
        minikube addons enable registry
        
    elif [ "$CLUSTER_TYPE" == "kind" ]; then
        # Check if Kind cluster exists
        if ! kind get clusters | grep -q "pyairtable"; then
            echo -e "${YELLOW}⚠️  Creating Kind cluster${NC}"
            cat <<EOF | kind create cluster --name pyairtable --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
    endpoint = ["http://kind-registry:5000"]
EOF
        fi
        
        # Setup local registry
        setup_kind_registry
    fi
    
    # Set kubectl context
    kubectl config use-context "$CLUSTER_TYPE" || kubectl config use-context "kind-pyairtable"
    
    echo -e "${GREEN}✅ Cluster setup complete${NC}"
}

# Function to setup Kind registry
setup_kind_registry() {
    # Check if registry container exists
    if ! docker ps -a --format 'table {{.Names}}' | grep -q "kind-registry"; then
        echo -e "${YELLOW}⚠️  Creating local registry for Kind${NC}"
        docker run -d --restart=always -p "5000:5000" --name "kind-registry" registry:2
    fi
    
    # Connect registry to kind network
    if ! docker network inspect kind | grep -q "kind-registry"; then
        docker network connect "kind" "kind-registry" 2>/dev/null || true
    fi
    
    # Document the local registry
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:5000"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
}

# Function to build Docker images
build_images() {
    echo -e "${BLUE}🔨 Building Docker images${NC}"
    
    cd "$PROJECT_ROOT"
    
    # Build Go services
    for service in "${GO_SERVICES[@]}"; do
        echo -e "${PURPLE}📦 Building Go service: ${service}${NC}"
        
        # Build the Go service
        cd go-services
        docker build \
            --platform "$BUILD_PLATFORM" \
            --build-arg SERVICE_NAME="$service" \
            -t "${IMAGE_REGISTRY}/pyairtable-${service}:latest" \
            -f "cmd/${service}/Dockerfile" \
            .
        
        # Push to registry if not using Minikube's Docker daemon
        if [ "$CLUSTER_TYPE" != "minikube" ]; then
            docker push "${IMAGE_REGISTRY}/pyairtable-${service}:latest"
        fi
        
        cd ..
    done
    
    # Build Python services (if needed)
    for service in "${PYTHON_SERVICES[@]}"; do
        if [ -d "${service}-py" ]; then
            echo -e "${PURPLE}📦 Building Python service: ${service}${NC}"
            
            cd "${service}-py"
            docker build \
                --platform "$BUILD_PLATFORM" \
                -t "${IMAGE_REGISTRY}/pyairtable-${service}:latest" \
                .
            
            # Push to registry if not using Minikube's Docker daemon
            if [ "$CLUSTER_TYPE" != "minikube" ]; then
                docker push "${IMAGE_REGISTRY}/pyairtable-${service}:latest"
            fi
            
            cd ..
        fi
    done
    
    echo -e "${GREEN}✅ All images built successfully${NC}"
}

# Function to setup namespaces and RBAC
setup_kubernetes_base() {
    echo -e "${BLUE}🔧 Setting up Kubernetes base configuration${NC}"
    
    # Create namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply base configurations
    if [ -d "k8s/base" ]; then
        echo -e "${YELLOW}📋 Applying base configurations${NC}"
        kubectl apply -k k8s/base/namespaces/
        kubectl apply -k k8s/base/rbac/
    fi
    
    echo -e "${GREEN}✅ Base configuration applied${NC}"
}

# Function to deploy infrastructure services
deploy_infrastructure() {
    echo -e "${BLUE}🗄️  Deploying infrastructure services${NC}"
    
    # Deploy PostgreSQL
    echo -e "${PURPLE}📊 Deploying PostgreSQL${NC}"
    helm upgrade --install postgresql-dev \
        oci://registry-1.docker.io/bitnamicharts/postgresql \
        --namespace "$NAMESPACE" \
        --set auth.postgresPassword="dev-postgres-password" \
        --set auth.database="pyairtable" \
        --set primary.persistence.enabled=true \
        --set primary.persistence.size="2Gi" \
        --set primary.resources.limits.memory="512Mi" \
        --set primary.resources.requests.memory="256Mi" \
        --wait
    
    # Deploy Redis
    echo -e "${PURPLE}🔄 Deploying Redis${NC}"
    helm upgrade --install redis-dev \
        oci://registry-1.docker.io/bitnamicharts/redis \
        --namespace "$NAMESPACE" \
        --set auth.password="dev-redis-password" \
        --set master.persistence.enabled=true \
        --set master.persistence.size="500Mi" \
        --set master.resources.limits.memory="128Mi" \
        --set master.resources.requests.memory="64Mi" \
        --set replica.replicaCount=0 \
        --wait
    
    echo -e "${GREEN}✅ Infrastructure services deployed${NC}"
}

# Function to deploy core services
deploy_core_services() {
    echo -e "${BLUE}🚀 Deploying core services${NC}"
    
    # Update Helm values with correct image registry
    local values_file="k8s/helm/pyairtable-stack/values-local.yaml"
    
    # Create local values file if it doesn't exist
    if [ ! -f "$values_file" ]; then
        cp "k8s/helm/pyairtable-stack/values-dev.yaml" "$values_file"
    fi
    
    # Update image registry in values file
    sed -i.bak "s|imageRegistry:.*|imageRegistry: ${IMAGE_REGISTRY}|g" "$values_file"
    
    # Deploy the main application stack
    helm upgrade --install pyairtable-dev ./k8s/helm/pyairtable-stack \
        --namespace "$NAMESPACE" \
        --values "$values_file" \
        --set global.imageRegistry="$IMAGE_REGISTRY" \
        --set secrets.postgresPassword="dev-postgres-password" \
        --set secrets.redisPassword="dev-redis-password" \
        --set secrets.jwtSecret="dev-jwt-secret-change-in-production" \
        --set secrets.apiKey="dev-api-key-change-in-production" \
        --timeout 10m \
        --wait
    
    echo -e "${GREEN}✅ Core services deployed${NC}"
}

# Function to setup Istio service mesh
setup_istio() {
    echo -e "${BLUE}🕸️  Setting up Istio service mesh${NC}"
    
    # Check if Istio is installed
    if ! kubectl get namespace istio-system >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Installing Istio${NC}"
        
        # Download and install Istio
        curl -L https://istio.io/downloadIstio | sh -
        local istio_version=$(ls | grep istio- | head -1)
        export PATH="$PWD/$istio_version/bin:$PATH"
        
        # Install Istio
        istioctl install --set values.defaultRevision=default -y
        
        # Enable sidecar injection for the namespace
        kubectl label namespace "$NAMESPACE" istio-injection=enabled
        
        # Apply Istio configurations
        if [ -f "k8s/service-mesh/istio-configuration.yaml" ]; then
            kubectl apply -f k8s/service-mesh/istio-configuration.yaml
        fi
    fi
    
    echo -e "${GREEN}✅ Istio service mesh configured${NC}"
}

# Function to verify deployment
verify_deployment() {
    echo -e "${BLUE}🔍 Verifying deployment${NC}"
    
    # Wait for all deployments to be ready
    echo -e "${YELLOW}⏳ Waiting for deployments to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment --all -n "$NAMESPACE"
    
    # Check pod status
    echo -e "${BLUE}📋 Pod Status:${NC}"
    kubectl get pods -n "$NAMESPACE"
    
    # Check service status
    echo -e "${BLUE}🌐 Service Status:${NC}"
    kubectl get services -n "$NAMESPACE"
    
    # Run health checks
    echo -e "${BLUE}🏥 Running health checks${NC}"
    ./k8s/scripts/health-check.sh "$NAMESPACE"
    
    echo -e "${GREEN}✅ Deployment verification complete${NC}"
}

# Function to setup port forwarding
setup_port_forwarding() {
    echo -e "${BLUE}🌐 Setting up port forwarding${NC}"
    
    echo -e "${YELLOW}Available services for port forwarding:${NC}"
    kubectl get services -n "$NAMESPACE" -o name | sed 's/service\///'
    
    echo -e "${BLUE}To access services locally, run:${NC}"
    echo -e "Frontend:              kubectl port-forward -n $NAMESPACE service/frontend 3000:3000"
    echo -e "API Gateway:           kubectl port-forward -n $NAMESPACE service/api-gateway 8000:8000"
    echo -e "Platform Services:     kubectl port-forward -n $NAMESPACE service/platform-services 8001:8001"
    echo -e "Automation Services:   kubectl port-forward -n $NAMESPACE service/automation-services 8002:8002"
    echo -e "PostgreSQL:            kubectl port-forward -n $NAMESPACE service/postgresql-dev 5432:5432"
    echo -e "Redis:                 kubectl port-forward -n $NAMESPACE service/redis-dev 6379:6379"
}

# Function to display next steps
display_next_steps() {
    echo -e "${GREEN}🎉 PyAirtable Core Services Deployment Complete!${NC}"
    echo -e ""
    echo -e "${BLUE}📊 Monitoring and Management:${NC}"
    echo -e "Kubernetes Dashboard:  minikube dashboard  # (if using Minikube)"
    echo -e "Logs:                  kubectl logs -f deployment/DEPLOYMENT_NAME -n $NAMESPACE"
    echo -e "Events:                kubectl get events -n $NAMESPACE"
    echo -e ""
    echo -e "${BLUE}🧪 Testing:${NC}"
    echo -e "Health Check:          ./k8s/scripts/health-check.sh $NAMESPACE"
    echo -e "E2E Tests:             ./k8s/scripts/e2e-test.sh $NAMESPACE"
    echo -e ""
    echo -e "${BLUE}🧹 Cleanup:${NC}"
    echo -e "Remove Services:       ./k8s/scripts/cleanup.sh $NAMESPACE"
    echo -e "Remove Cluster:        minikube delete  # or kind delete cluster --name pyairtable"
}

# Main execution flow
main() {
    echo -e "${BLUE}Starting deployment with the following options:${NC}"
    echo -e "  Project Root: $PROJECT_ROOT"
    echo -e "  Namespace: $NAMESPACE"
    echo -e "  Cluster Type: $CLUSTER_TYPE"
    echo -e "  Image Registry: $IMAGE_REGISTRY"
    echo -e ""
    
    # Check if user wants to continue
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
    
    check_prerequisites
    setup_cluster
    build_images
    setup_kubernetes_base
    deploy_infrastructure
    deploy_core_services
    
    # Optional Istio setup
    read -p "Setup Istio service mesh? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_istio
    fi
    
    verify_deployment
    setup_port_forwarding
    display_next_steps
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --cluster-type)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        --registry)
            IMAGE_REGISTRY="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --namespace NAMESPACE    Target Kubernetes namespace (default: pyairtable)"
            echo "  --cluster-type TYPE      Cluster type: minikube or kind (default: minikube)"
            echo "  --registry REGISTRY     Image registry (default: localhost:5000)"
            echo "  --skip-build            Skip Docker image building"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"