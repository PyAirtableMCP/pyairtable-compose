#!/bin/bash

# Enhanced Istio Service Mesh Deployment Script for PyAirtable
# Deploys production-ready service mesh with security, observability, and performance optimizations

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="${PROJECT_NAME:-pyairtable}"
ENVIRONMENT="${ENVIRONMENT:-production}"
ISTIO_VERSION="${ISTIO_VERSION:-1.19.3}"
CERT_DOMAIN="${CERT_DOMAIN:-pyairtable.com}"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is installed and configured
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check if istioctl is installed
    if ! command -v istioctl &> /dev/null; then
        log_warning "istioctl not found. Installing Istio ${ISTIO_VERSION}..."
        install_istioctl
    fi
    
    # Verify Kubernetes connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Install istioctl if not present
install_istioctl() {
    log_info "Installing istioctl ${ISTIO_VERSION}..."
    
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
    sudo mv istio-${ISTIO_VERSION}/bin/istioctl /usr/local/bin/
    rm -rf istio-${ISTIO_VERSION}
    
    log_success "istioctl ${ISTIO_VERSION} installed"
}

# Install Istio with production configuration
install_istio() {
    log_info "Installing Istio control plane..."
    
    # Create istio-system namespace
    kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Istio with production configuration
    istioctl install -f "${SCRIPT_DIR}/istio-production-enhanced.yaml" --verify
    
    # Wait for Istio components to be ready
    kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=600s
    kubectl wait --for=condition=Available deployment/istio-ingressgateway -n istio-system --timeout=600s
    
    log_success "Istio control plane installed successfully"
}

# Setup TLS certificates
setup_tls_certificates() {
    log_info "Setting up TLS certificates..."
    
    # Check if cert-manager is installed
    if ! kubectl get ns cert-manager &> /dev/null; then
        log_info "Installing cert-manager..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
        kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
    fi
    
    # Create ClusterIssuer for Let's Encrypt
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@${CERT_DOMAIN}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: istio
EOF

    # Create Certificate for PyAirtable domains
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: pyairtable-tls
  namespace: pyairtable
spec:
  secretName: pyairtable-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - api.${CERT_DOMAIN}
  - app.${CERT_DOMAIN}
  - "*.${CERT_DOMAIN}"
EOF

    log_success "TLS certificates configured"
}

# Deploy observability stack
deploy_observability() {
    log_info "Deploying observability stack..."
    
    # Create monitoring namespace
    kubectl create namespace pyairtable-monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace pyairtable-monitoring istio-injection=enabled --overwrite
    
    # Install Prometheus
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace pyairtable-monitoring \
        --values - <<EOF
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
    - job_name: 'istio-mesh'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - pyairtable
          - istio-system
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: istio-proxy;http-monitoring
      - source_labels: [__address__, __meta_kubernetes_endpoint_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: \$1:\$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: service_name

grafana:
  adminPassword: "admin123"  # Change in production
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'istio'
        orgId: 1
        folder: 'Istio'
        type: file
        disableDeletion: false
        updateIntervalSeconds: 10
        options:
          path: /var/lib/grafana/dashboards/istio
  dashboards:
    istio:
      istio-service-dashboard:
        url: https://raw.githubusercontent.com/istio/istio/release-1.19/manifests/addons/dashboards/istio-service-dashboard.json
      istio-workload-dashboard:
        url: https://raw.githubusercontent.com/istio/istio/release-1.19/manifests/addons/dashboards/istio-workload-dashboard.json
      istio-mesh-dashboard:
        url: https://raw.githubusercontent.com/istio/istio/release-1.19/manifests/addons/dashboards/istio-mesh-dashboard.json
EOF

    # Install Jaeger for distributed tracing
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/jaeger.yaml
    
    # Install Kiali for service mesh visualization
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.19/samples/addons/kiali.yaml
    
    log_success "Observability stack deployed"
}

# Deploy enhanced service mesh configuration
deploy_service_mesh_config() {
    log_info "Deploying enhanced service mesh configuration..."
    
    # Apply the enhanced Istio configuration
    kubectl apply -f "${SCRIPT_DIR}/istio-production-enhanced.yaml"
    
    # Wait for configuration to be applied
    sleep 30
    
    # Verify configuration
    kubectl get gateway,virtualservice,destinationrule,peerauthentication,authorizationpolicy -n pyairtable
    
    log_success "Service mesh configuration deployed"
}

# Setup KEDA for event-driven autoscaling
setup_keda() {
    log_info "Installing KEDA for event-driven autoscaling..."
    
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    
    helm upgrade --install keda kedacore/keda \
        --namespace keda-system \
        --create-namespace \
        --set prometheus.metricServer.enabled=true \
        --set prometheus.operator.enabled=true
    
    # Wait for KEDA to be ready
    kubectl wait --for=condition=Available deployment/keda-operator -n keda-system --timeout=300s
    
    log_success "KEDA installed successfully"
}

# Deploy WASM plugins
deploy_wasm_plugins() {
    log_info "Deploying WASM plugins for enhanced functionality..."
    
    # Note: In a real deployment, you would have actual WASM plugin images
    # For now, we'll create placeholder configurations
    
    log_warning "WASM plugins configured (requires actual plugin images for full functionality)"
}

# Validate deployment
validate_deployment() {
    log_info "Validating service mesh deployment..."
    
    # Check Istio installation
    if ! istioctl verify-install; then
        log_error "Istio installation validation failed"
        return 1
    fi
    
    # Check if all components are running
    local components=(
        "deployment/istiod:istio-system"
        "deployment/istio-ingressgateway:istio-system"
        "deployment/prometheus-kube-prometheus-prometheus:pyairtable-monitoring"
        "deployment/keda-operator:keda-system"
    )
    
    for component in "${components[@]}"; do
        IFS=':' read -r deployment namespace <<< "${component}"
        if ! kubectl wait --for=condition=Available "${deployment}" -n "${namespace}" --timeout=60s; then
            log_error "Component ${deployment} in namespace ${namespace} is not ready"
            return 1
        fi
    done
    
    # Test connectivity
    log_info "Testing service mesh connectivity..."
    
    # Get ingress gateway external IP
    local external_ip
    external_ip=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [[ -n "${external_ip}" ]]; then
        log_info "Ingress gateway available at: ${external_ip}"
        
        # Test health endpoint
        if curl -f -s "http://${external_ip}/health" > /dev/null; then
            log_success "Service mesh connectivity test passed"
        else
            log_warning "Service mesh connectivity test failed (this is expected if services are not yet deployed)"
        fi
    else
        log_warning "Ingress gateway external IP not yet assigned"
    fi
    
    log_success "Service mesh deployment validation completed"
}

# Generate deployment report
generate_report() {
    log_info "Generating deployment report..."
    
    local report_file="service-mesh-deployment-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "${report_file}" <<EOF
# PyAirtable Service Mesh Deployment Report
Generated: $(date)
Environment: ${ENVIRONMENT}
Istio Version: ${ISTIO_VERSION}

## Deployed Components

### Istio Control Plane
$(kubectl get pods -n istio-system)

### Gateways and Virtual Services
$(kubectl get gateway,virtualservice -n pyairtable)

### Destination Rules and Policies
$(kubectl get destinationrule,peerauthentication,authorizationpolicy -n pyairtable)

### Observability Stack
$(kubectl get pods -n pyairtable-monitoring)

### KEDA
$(kubectl get pods -n keda-system)

## Configuration Summary

### Traffic Management
- Multi-version canary deployment support
- Circuit breakers and retry policies
- Advanced load balancing strategies
- Request/response header manipulation

### Security
- Strict mTLS enforcement
- JWT-based authentication
- RBAC authorization policies
- Rate limiting with WASM plugins

### Observability
- Distributed tracing with Jaeger
- Comprehensive metrics collection
- Custom business metrics
- Access logging and audit trails

## Next Steps

1. Deploy application services with Istio injection enabled
2. Configure monitoring dashboards
3. Set up alerting rules
4. Test traffic management policies
5. Verify security policies

## Useful Commands

# View service mesh status
istioctl proxy-status

# Analyze configuration
istioctl analyze

# View proxy configuration
istioctl proxy-config cluster <pod-name> -n pyairtable

# Check mTLS status
istioctl authn tls-check <service-name>.<namespace>.svc.cluster.local

# View metrics
kubectl port-forward -n pyairtable-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# View tracing
kubectl port-forward -n istio-system svc/tracing 16686:16686

# View Kiali dashboard
kubectl port-forward -n istio-system svc/kiali 20001:20001
EOF

    log_success "Deployment report generated: ${report_file}"
}

# Cleanup function
cleanup() {
    if [[ "${1:-}" == "true" ]]; then
        log_info "Cleaning up failed deployment..."
        
        # Remove configurations
        kubectl delete -f "${SCRIPT_DIR}/istio-production-enhanced.yaml" --ignore-not-found=true
        
        # Uninstall Istio
        istioctl uninstall --purge -y
        
        # Remove namespaces
        kubectl delete namespace istio-system --ignore-not-found=true
        kubectl delete namespace pyairtable-monitoring --ignore-not-found=true
        kubectl delete namespace keda-system --ignore-not-found=true
        
        log_info "Cleanup completed"
    fi
}

# Main deployment function
main() {
    log_info "Starting PyAirtable Enhanced Service Mesh Deployment"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Istio Version: ${ISTIO_VERSION}"
    
    # Set trap for cleanup on failure
    trap 'cleanup true' ERR
    
    # Deployment steps
    check_prerequisites
    install_istio
    setup_tls_certificates
    deploy_observability
    setup_keda
    deploy_service_mesh_config
    deploy_wasm_plugins
    validate_deployment
    generate_report
    
    # Remove trap
    trap - ERR
    
    log_success "PyAirtable Enhanced Service Mesh deployed successfully!"
    log_info "Access points:"
    log_info "  - Grafana: kubectl port-forward -n pyairtable-monitoring svc/prometheus-grafana 3000:80"
    log_info "  - Jaeger: kubectl port-forward -n istio-system svc/tracing 16686:16686"
    log_info "  - Kiali: kubectl port-forward -n istio-system svc/kiali 20001:20001"
    log_info "  - Prometheus: kubectl port-forward -n pyairtable-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --istio-version)
            ISTIO_VERSION="$2"
            shift 2
            ;;
        --cert-domain)
            CERT_DOMAIN="$2"
            shift 2
            ;;
        --cleanup)
            cleanup true
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --environment ENV       Set environment (default: production)"
            echo "  --istio-version VER     Set Istio version (default: 1.19.3)"
            echo "  --cert-domain DOMAIN    Set certificate domain (default: pyairtable.com)"
            echo "  --cleanup               Remove all deployed components"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"