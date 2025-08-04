#!/bin/bash

# PyAirtable Minikube Setup Script
# Automated setup for local development environment
# Optimized for development workflow with proper resource allocation

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MINIKUBE_PROFILE="pyairtable"
MEMORY="6g"
CPUS="4"
DISK_SIZE="40g"
KUBERNETES_VERSION="v1.28.3"
DRIVER="docker"

# Required addons
ADDONS=(
    "ingress"
    "registry"
    "metrics-server"
    "dashboard"
    "storage-provisioner"
    "default-storageclass"
)

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v minikube &> /dev/null; then
        missing_tools+=("minikube")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Installation instructions:"
        echo "- minikube: https://minikube.sigs.k8s.io/docs/start/"
        echo "- kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "- helm: https://helm.sh/docs/intro/install/"
        echo "- docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Check system resources
check_system_resources() {
    print_header "Checking System Resources"
    
    # Check available memory (in GB)
    local available_memory
    if [[ "$OSTYPE" == "darwin"* ]]; then
        available_memory=$(echo "$(sysctl -n hw.memsize) / 1024 / 1024 / 1024" | bc)
    else
        available_memory=$(free -g | awk '/^Mem:/{print $7}')
    fi
    
    if [ "$available_memory" -lt 8 ]; then
        print_warning "System has less than 8GB available memory. Consider reducing Minikube memory allocation."
        read -p "Continue with current settings? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    print_success "System resources adequate"
}

# Clean up existing cluster
cleanup_existing() {
    print_header "Cleaning Up Existing Cluster"
    
    if minikube profile list | grep -q "$MINIKUBE_PROFILE"; then
        print_info "Stopping existing Minikube profile: $MINIKUBE_PROFILE"
        minikube stop -p "$MINIKUBE_PROFILE" || true
        
        print_info "Deleting existing Minikube profile: $MINIKUBE_PROFILE"
        minikube delete -p "$MINIKUBE_PROFILE" || true
    fi
    
    print_success "Cleanup completed"
}

# Start Minikube cluster
start_minikube() {
    print_header "Starting Minikube Cluster"
    
    print_info "Starting Minikube with profile: $MINIKUBE_PROFILE"
    print_info "Configuration: Memory=$MEMORY, CPUs=$CPUS, Disk=$DISK_SIZE"
    
    minikube start \
        --profile="$MINIKUBE_PROFILE" \
        --memory="$MEMORY" \
        --cpus="$CPUS" \
        --disk-size="$DISK_SIZE" \
        --kubernetes-version="$KUBERNETES_VERSION" \
        --driver="$DRIVER" \
        --container-runtime=containerd \
        --feature-gates="GracefulNodeShutdown=true" \
        --extra-config=kubelet.housekeeping-interval=10s \
        --extra-config=kubelet.max-pods=110 \
        --extra-config=controller-manager.horizontal-pod-autoscaler-upscale-delay=1m \
        --extra-config=controller-manager.horizontal-pod-autoscaler-downscale-delay=2m \
        --extra-config=controller-manager.horizontal-pod-autoscaler-downscale-stabilization=1m \
        --bootstrapper=kubeadm
    
    print_success "Minikube cluster started"
}

# Enable addons
enable_addons() {
    print_header "Enabling Minikube Addons"
    
    for addon in "${ADDONS[@]}"; do
        print_info "Enabling addon: $addon"
        minikube addons enable "$addon" -p "$MINIKUBE_PROFILE"
    done
    
    print_success "All addons enabled"
}

# Setup kubectl context
setup_kubectl() {
    print_header "Configuring Kubectl"
    
    # Set kubectl context to use Minikube
    kubectl config use-context "$MINIKUBE_PROFILE"
    
    # Verify connection
    kubectl cluster-info
    
    print_success "Kubectl configured successfully"
}

# Create namespaces
create_namespaces() {
    print_header "Creating Namespaces"
    
    local namespaces=(
        "pyairtable"
        "pyairtable-monitoring"
        "pyairtable-system"
    )
    
    for ns in "${namespaces[@]}"; do
        if ! kubectl get namespace "$ns" &> /dev/null; then
            print_info "Creating namespace: $ns"
            kubectl create namespace "$ns"
        else
            print_info "Namespace already exists: $ns"
        fi
    done
    
    print_success "Namespaces configured"
}

# Setup storage classes
setup_storage() {
    print_header "Setting Up Storage Classes"
    
    # Apply storage class configuration
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: postgres-dev-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: k8s.io/minikube-hostpath
parameters:
  type: pd-ssd
volumeBindingMode: Immediate
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: postgres-backup-standard
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: k8s.io/minikube-hostpath
parameters:
  type: pd-standard
volumeBindingMode: Immediate
allowVolumeExpansion: true
reclaimPolicy: Retain
EOF
    
    print_success "Storage classes configured"
}

# Setup local registry
setup_local_registry() {
    print_header "Setting Up Local Registry"
    
    # Enable registry addon
    minikube addons enable registry -p "$MINIKUBE_PROFILE"
    
    # Get registry endpoint
    local registry_endpoint
    registry_endpoint=$(minikube service --url registry -p "$MINIKUBE_PROFILE" | head -1)
    
    print_info "Local registry available at: $registry_endpoint"
    print_info "To push images: docker tag <image> localhost:5000/<image> && docker push localhost:5000/<image>"
    
    print_success "Local registry configured"
}

# Setup monitoring prerequisites
setup_monitoring_prerequisites() {
    print_header "Setting Up Monitoring Prerequisites"
    
    # Add Helm repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
    helm repo update
    
    print_success "Monitoring repositories added"
}

# Display connection information
display_connection_info() {
    print_header "Connection Information"
    
    echo "Minikube Profile: $MINIKUBE_PROFILE"
    echo "Kubernetes Version: $(kubectl version --short --client)"
    echo ""
    echo "Useful Commands:"
    echo "  minikube profile list"
    echo "  minikube dashboard -p $MINIKUBE_PROFILE"
    echo "  kubectl get pods --all-namespaces"
    echo ""
    echo "Service URLs (after deployment):"
    echo "  Frontend: http://$(minikube ip -p "$MINIKUBE_PROFILE"):30000"
    echo "  API Gateway: http://$(minikube ip -p "$MINIKUBE_PROFILE"):30800"
    echo "  Dashboard: minikube dashboard -p $MINIKUBE_PROFILE"
    echo ""
    echo "To deploy PyAirtable:"
    echo "  cd k8s && make dev-setup"
}

# Main execution
main() {
    print_header "PyAirtable Minikube Setup"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                cleanup_existing
                shift
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --cpus)
                CPUS="$2"
                shift 2
                ;;
            --disk-size)
                DISK_SIZE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --clean           Clean up existing cluster before setup"
                echo "  --memory SIZE     Set memory allocation (default: $MEMORY)"
                echo "  --cpus COUNT      Set CPU count (default: $CPUS)"
                echo "  --disk-size SIZE  Set disk size (default: $DISK_SIZE)"
                echo "  --help, -h        Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute setup steps
    check_prerequisites
    check_system_resources
    start_minikube
    enable_addons
    setup_kubectl
    create_namespaces
    setup_storage
    setup_local_registry
    setup_monitoring_prerequisites
    
    print_success "Minikube setup completed successfully!"
    display_connection_info
}

# Execute main function
main "$@"