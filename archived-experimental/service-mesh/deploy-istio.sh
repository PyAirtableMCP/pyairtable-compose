#!/bin/bash
# Deploy Istio Service Mesh for PyAirtable
# Production-ready deployment script with comprehensive validation

set -euo pipefail

# Configuration
ISTIO_VERSION="${ISTIO_VERSION:-1.20.2}"
NAMESPACE="${NAMESPACE:-pyairtable}"
ENVIRONMENT="${ENVIRONMENT:-production}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as non-root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Unable to connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if Istio is already installed
    if kubectl get namespace "$ISTIO_NAMESPACE" &> /dev/null; then
        log_warning "Istio namespace already exists. Continuing with upgrade/update..."
    fi
    
    log_success "Prerequisites check passed"
}

# Function to install Istio
install_istio() {
    log_info "Installing Istio $ISTIO_VERSION..."
    
    # Download Istio if not present
    if [[ ! -d "istio-$ISTIO_VERSION" ]]; then
        log_info "Downloading Istio $ISTIO_VERSION..."
        curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION sh -
    fi
    
    # Add Istio to PATH
    export PATH="$PWD/istio-$ISTIO_VERSION/bin:$PATH"
    
    # Verify installation
    if ! command -v istioctl &> /dev/null; then
        log_error "istioctl not found after installation"
        exit 1
    fi
    
    # Pre-check the cluster
    log_info "Running Istio pre-installation checks..."
    if ! istioctl x precheck; then
        log_error "Istio pre-installation checks failed"
        exit 1
    fi
    
    # Install Istio control plane
    log_info "Installing Istio control plane..."
    kubectl apply -f "$SCRIPT_DIR/istio-installation.yaml"
    
    # Wait for Istio to be ready
    log_info "Waiting for Istio control plane to be ready..."
    kubectl wait --for=condition=Available deployment/istiod -n "$ISTIO_NAMESPACE" --timeout=300s
    
    log_success "Istio control plane installed successfully"
}

# Function to create and configure namespace
setup_namespace() {
    log_info "Setting up PyAirtable namespace..."
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Apply security policies (includes namespace configuration)
    kubectl apply -f "$SCRIPT_DIR/pyairtable-security-policies.yaml"
    
    # Verify sidecar injection is enabled
    local injection_status
    injection_status=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.istio-injection}')
    
    if [[ "$injection_status" != "enabled" ]]; then
        log_error "Sidecar injection not enabled for namespace $NAMESPACE"
        exit 1
    fi
    
    log_success "Namespace $NAMESPACE configured with Istio injection"
}

# Function to apply traffic management
apply_traffic_management() {
    log_info "Applying traffic management configuration..."
    
    kubectl apply -f "$SCRIPT_DIR/pyairtable-traffic-management.yaml"
    
    # Verify VirtualServices and DestinationRules
    log_info "Verifying traffic management resources..."
    
    # Check if VirtualServices are created
    local vs_count
    vs_count=$(kubectl get virtualservices -n "$NAMESPACE" --no-headers | wc -l)
    if [[ $vs_count -eq 0 ]]; then
        log_warning "No VirtualServices found"
    else
        log_success "$vs_count VirtualServices configured"
    fi
    
    # Check if DestinationRules are created
    local dr_count
    dr_count=$(kubectl get destinationrules -n "$NAMESPACE" --no-headers | wc -l)
    if [[ $dr_count -eq 0 ]]; then
        log_warning "No DestinationRules found"
    else
        log_success "$dr_count DestinationRules configured"
    fi
}

# Function to setup observability
setup_observability() {
    log_info "Setting up observability configuration..."
    
    kubectl apply -f "$SCRIPT_DIR/pyairtable-observability.yaml"
    
    # Install Prometheus Operator if not present
    if ! kubectl get crd prometheuses.monitoring.coreos.com &> /dev/null; then
        log_info "Installing Prometheus Operator..."
        kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml
        
        # Wait for CRDs to be established
        kubectl wait --for condition=established --timeout=60s crd/prometheuses.monitoring.coreos.com
        kubectl wait --for condition=established --timeout=60s crd/servicemonitors.monitoring.coreos.com
    fi
    
    # Install Jaeger Operator if not present
    if ! kubectl get deployment jaeger-operator -n observability &> /dev/null; then
        log_info "Installing Jaeger Operator..."
        kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -n observability -f https://github.com/jaegertracing/jaeger-operator/releases/latest/download/jaeger-operator.yaml
    fi
    
    log_success "Observability configuration applied"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating Istio deployment..."
    
    # Check Istio control plane status
    if ! istioctl proxy-status; then
        log_error "Istio proxy status check failed"
        return 1
    fi
    
    # Verify mesh configuration
    local config_status
    config_status=$(istioctl analyze --color=false -n "$NAMESPACE" 2>&1 || true)
    
    if echo "$config_status" | grep -q "Error"; then
        log_error "Istio configuration analysis found errors:"
        echo "$config_status"
        return 1
    elif echo "$config_status" | grep -q "Warning"; then
        log_warning "Istio configuration analysis found warnings:"
        echo "$config_status"
    else
        log_success "Istio configuration analysis passed"
    fi
    
    # Check mTLS status
    log_info "Checking mTLS status..."
    if istioctl authn tls-check -n "$NAMESPACE" | grep -q "STRICT"; then
        log_success "Strict mTLS is enabled"
    else
        log_warning "Strict mTLS may not be properly configured"
    fi
    
    # Verify gateways
    local gateway_count
    gateway_count=$(kubectl get gateways -n "$NAMESPACE" --no-headers | wc -l)
    if [[ $gateway_count -gt 0 ]]; then
        log_success "$gateway_count Gateways configured"
    else
        log_warning "No Gateways found"
    fi
    
    log_success "Istio deployment validation completed"
}

# Function to setup TLS certificates
setup_certificates() {
    log_info "Setting up TLS certificates..."
    
    # Check if cert-manager is installed
    if ! kubectl get crd certificates.cert-manager.io &> /dev/null; then
        log_info "Installing cert-manager..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
        
        # Wait for cert-manager to be ready
        kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
        kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=300s
        kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=300s
    fi
    
    # Create self-signed issuer for development
    if [[ "$ENVIRONMENT" == "development" ]]; then
        log_info "Creating self-signed certificate issuer for development..."
        cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: pyairtable-tls-secret
  namespace: $NAMESPACE
spec:
  secretName: pyairtable-tls-secret
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - pyairtable.local
  - api.pyairtable.local
  - "*.pyairtable.local"
EOF
    fi
    
    log_success "TLS certificates configured"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Environment: $ENVIRONMENT"
    echo "Istio Version: $ISTIO_VERSION"
    echo "Namespace: $NAMESPACE"
    echo "Istio Namespace: $ISTIO_NAMESPACE"
    echo ""
    
    log_info "Istio Components:"
    kubectl get pods -n "$ISTIO_NAMESPACE"
    echo ""
    
    log_info "PyAirtable Istio Resources:"
    kubectl get gateways,virtualservices,destinationrules,peerauthentications,authorizationpolicies -n "$NAMESPACE"
    echo ""
    
    log_info "Access Information:"
    if kubectl get service istio-ingressgateway -n "$ISTIO_NAMESPACE" &> /dev/null; then
        local external_ip
        external_ip=$(kubectl get service istio-ingressgateway -n "$ISTIO_NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        if [[ -n "$external_ip" ]]; then
            echo "External IP: $external_ip"
            echo "Access URL: https://$external_ip"
        else
            echo "LoadBalancer service is pending external IP"
            echo "Use: kubectl port-forward -n $ISTIO_NAMESPACE svc/istio-ingressgateway 8080:80"
        fi
    fi
    
    log_info "Useful Commands:"
    echo "Check proxy status: istioctl proxy-status"
    echo "Analyze configuration: istioctl analyze -n $NAMESPACE"
    echo "View proxy config: istioctl proxy-config cluster <pod-name> -n $NAMESPACE"
    echo "Check mTLS: istioctl authn tls-check -n $NAMESPACE"
    echo "View access logs: kubectl logs -n $NAMESPACE <pod-name> -c istio-proxy"
}

# Function to cleanup on failure
cleanup() {
    log_error "Deployment failed. Cleaning up..."
    
    # Remove applied configurations (optional)
    # kubectl delete -f "$SCRIPT_DIR/pyairtable-observability.yaml" --ignore-not-found=true
    # kubectl delete -f "$SCRIPT_DIR/pyairtable-traffic-management.yaml" --ignore-not-found=true
    # kubectl delete -f "$SCRIPT_DIR/pyairtable-security-policies.yaml" --ignore-not-found=true
    
    exit 1
}

# Main deployment function
main() {
    log_info "Starting Istio deployment for PyAirtable..."
    log_info "Environment: $ENVIRONMENT"
    log_info "Target namespace: $NAMESPACE"
    
    # Set trap for cleanup on error
    trap cleanup ERR
    
    # Execute deployment steps
    check_prerequisites
    install_istio
    setup_certificates
    setup_namespace
    apply_traffic_management
    setup_observability
    validate_deployment
    display_summary
    
    log_success "🎉 Istio deployment completed successfully!"
    log_info "Your PyAirtable service mesh is now ready for production use."
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi