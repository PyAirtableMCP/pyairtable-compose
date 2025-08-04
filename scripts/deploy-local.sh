#!/bin/bash
# PyAirtable Local Deployment Script
# One-command deployment for Minikube

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="pyairtable"
MINIKUBE_MEMORY="8192"
MINIKUBE_CPUS="4"
MINIKUBE_DISK="20g"
K8S_VERSION="v1.28.5"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
}

# Check prerequisites
log_info "Checking prerequisites..."
check_command docker
check_command minikube
check_command kubectl
check_command helm

# Check Docker is running
if ! docker info &> /dev/null; then
    log_error "Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Start Minikube
log_info "Starting Minikube with optimized settings..."
if minikube status &> /dev/null; then
    log_warn "Minikube is already running. Using existing cluster."
else
    minikube start \
        --memory=$MINIKUBE_MEMORY \
        --cpus=$MINIKUBE_CPUS \
        --disk-size=$MINIKUBE_DISK \
        --kubernetes-version=$K8S_VERSION \
        --driver=docker
fi

# Enable addons
log_info "Enabling Minikube addons..."
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard
minikube addons enable registry

# Create namespace
log_info "Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Set default namespace
kubectl config set-context --current --namespace=$NAMESPACE

# Build Docker images
log_info "Building Docker images..."
eval $(minikube docker-env)

# Build Go services
for service in api-gateway auth-service file-processing-service webhook-service plugin-service; do
    if [ -d "go-services/$service" ]; then
        log_info "Building $service..."
        docker build -t pyairtable/$service:latest -f go-services/$service/Dockerfile go-services/$service
    fi
done

# Build Python services
for service in llm-orchestrator mcp-server analytics-service workflow-engine; do
    if [ -d "python-services/$service" ]; then
        log_info "Building $service..."
        docker build -t pyairtable/$service:latest -f python-services/$service/Dockerfile python-services/$service
    fi
done

# Build frontend
if [ -d "frontend-services/tenant-dashboard" ]; then
    log_info "Building frontend..."
    docker build -t pyairtable/frontend:latest -f frontend-services/tenant-dashboard/Dockerfile frontend-services/tenant-dashboard
fi

# Generate secrets
log_info "Generating secrets..."
./scripts/generate-secrets.sh

# Deploy infrastructure
log_info "Deploying infrastructure services..."
kubectl apply -f k8s/infrastructure/postgresql.yaml
kubectl apply -f k8s/infrastructure/redis.yaml

# Wait for infrastructure
log_info "Waiting for infrastructure to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql --timeout=300s
kubectl wait --for=condition=ready pod -l app=redis --timeout=300s

# Run database migrations
log_info "Running database migrations..."
kubectl apply -f k8s/jobs/db-migration.yaml
kubectl wait --for=condition=complete job/db-migration --timeout=300s

# Deploy core services
log_info "Deploying core services..."
kubectl apply -f k8s/services/auth-service.yaml
kubectl apply -f k8s/services/api-gateway.yaml

# Wait for core services
kubectl wait --for=condition=ready pod -l app=auth-service --timeout=300s
kubectl wait --for=condition=ready pod -l app=api-gateway --timeout=300s

# Deploy application services
log_info "Deploying application services..."
for manifest in k8s/services/*.yaml; do
    kubectl apply -f $manifest
done

# Deploy frontend
log_info "Deploying frontend..."
kubectl apply -f k8s/frontend/frontend.yaml

# Wait for all deployments
log_info "Waiting for all services to be ready..."
kubectl wait --for=condition=available deployment --all --timeout=600s

# Create ingress
log_info "Creating ingress routes..."
kubectl apply -f k8s/ingress/ingress.yaml

# Port forwarding for local access
log_info "Setting up port forwarding..."
# API Gateway
kubectl port-forward service/api-gateway 8080:8080 &
# Frontend
kubectl port-forward service/frontend 3000:3000 &

# Get URLs
FRONTEND_URL="http://localhost:3000"
API_URL="http://localhost:8080"
MINIKUBE_IP=$(minikube ip)

# Run health checks
log_info "Running health checks..."
sleep 10  # Give services time to fully start

./scripts/health-check.sh

# Display access information
echo ""
echo "=========================================="
echo "✅ PyAirtable Local Deployment Complete!"
echo "=========================================="
echo ""
echo "Access URLs:"
echo "  Frontend:    $FRONTEND_URL"
echo "  API Gateway: $API_URL"
echo "  Minikube IP: $MINIKUBE_IP"
echo ""
echo "Useful commands:"
echo "  View logs:       kubectl logs -f deployment/<service-name>"
echo "  View dashboard:  minikube dashboard"
echo "  SSH to node:     minikube ssh"
echo "  Stop cluster:    minikube stop"
echo ""
echo "To run tests:"
echo "  make test-e2e"
echo "  make test-integration"
echo ""
echo "=========================================="