#!/bin/bash
# PyAirtable Service Deployment Automation Script
# ==============================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
NAMESPACE="${NAMESPACE:-pyairtable}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
CLUSTER_NAME="${CLUSTER_NAME:-pyairtable-prod}"
ENVIRONMENT="${ENVIRONMENT:-production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Service groups in deployment order
declare -a INFRASTRUCTURE_SERVICES=("postgres" "redis" "kafka" "istio-system")
declare -a CORE_SERVICES=("api-gateway" "auth-service")
declare -a PLATFORM_SERVICES=("user-service" "workspace-service" "permission-service")
declare -a DOMAIN_SERVICES=("airtable-gateway" "llm-orchestrator" "mcp-server" "automation-service")
declare -a FRONTEND_SERVICES=("web-bff" "mobile-bff" "auth-frontend" "event-sourcing-ui")
declare -a UTILITY_SERVICES=("notification-service" "file-service" "webhook-service")

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local tools=("kubectl" "helm" "aws" "docker" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl not connected to cluster"
        exit 1
    fi
    
    # Update kubeconfig for EKS
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
    
    log_success "Prerequisites check completed"
}

# Function to create namespace if not exists
create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace "$NAMESPACE"
        
        # Label namespace for service mesh
        kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite
        kubectl label namespace "$NAMESPACE" environment="$ENVIRONMENT" --overwrite
        
        log_success "Namespace $NAMESPACE created"
    fi
}

# Function to deploy secrets
deploy_secrets() {
    log_info "Deploying secrets..."
    
    # Create secret from environment variables
    kubectl create secret generic app-secrets \
        --namespace="$NAMESPACE" \
        --from-literal=DATABASE_URL="${DATABASE_URL:-}" \
        --from-literal=REDIS_URL="${REDIS_URL:-}" \
        --from-literal=KAFKA_BROKERS="${KAFKA_BROKERS:-}" \
        --from-literal=AIRTABLE_TOKEN="${AIRTABLE_TOKEN:-}" \
        --from-literal=GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
        --from-literal=API_KEY="${API_KEY:-}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy TLS certificates
    if [[ -n "${SSL_CERT_ARN:-}" ]]; then
        kubectl annotate service istio-ingressgateway \
            service.beta.kubernetes.io/aws-load-balancer-ssl-cert="$SSL_CERT_ARN" \
            --namespace=istio-system --overwrite
    fi
    
    log_success "Secrets deployed"
}

# Function to build and push Docker images
build_and_push_images() {
    log_info "Building and pushing Docker images..."
    
    local ecr_registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ecr_registry"
    
    # Build Go services
    log_info "Building Go services..."
    cd "$PROJECT_ROOT/go-services"
    
    local go_services=("api-gateway" "auth-service" "user-service" "workspace-service" "permission-service")
    for service in "${go_services[@]}"; do
        log_info "Building $service..."
        
        cd "$service"
        
        # Build Docker image
        docker build -t "$service:latest" .
        docker tag "$service:latest" "$ecr_registry/$service:$BUILD_VERSION"
        docker tag "$service:latest" "$ecr_registry/$service:latest"
        
        # Push to ECR
        docker push "$ecr_registry/$service:$BUILD_VERSION"
        docker push "$ecr_registry/$service:latest"
        
        cd ..
    done
    
    # Build Python services
    log_info "Building Python services..."
    cd "$PROJECT_ROOT"
    
    local python_services=("pyairtable-airtable-domain" "pyairtable-automation-domain" "pyairtable-ai-domain")
    for service in "${python_services[@]}"; do
        log_info "Building $service..."
        
        cd "$service"
        
        # Build Docker image
        docker build -t "$service:latest" .
        docker tag "$service:latest" "$ecr_registry/$service:$BUILD_VERSION"
        docker tag "$service:latest" "$ecr_registry/$service:latest"
        
        # Push to ECR
        docker push "$ecr_registry/$service:$BUILD_VERSION"
        docker push "$ecr_registry/$service:latest"
        
        cd ..
    done
    
    log_success "All images built and pushed"
}

# Function to deploy service group
deploy_service_group() {
    local group_name="$1"
    shift
    local services=("$@")
    
    log_info "Deploying service group: $group_name"
    
    for service in "${services[@]}"; do
        deploy_single_service "$service"
    done
    
    # Wait for group to be ready
    log_info "Waiting for $group_name services to be ready..."
    for service in "${services[@]}"; do
        wait_for_service_ready "$service"
    done
    
    log_success "Service group $group_name deployed successfully"
}

# Function to deploy single service
deploy_single_service() {
    local service="$1"
    
    log_info "Deploying service: $service"
    
    # Check if service has Helm chart
    local helm_chart_path="$PROJECT_ROOT/k8s/helm/pyairtable-stack/charts/$service"
    if [[ -d "$helm_chart_path" ]]; then
        deploy_service_with_helm "$service"
    else
        deploy_service_with_kubectl "$service"
    fi
}

# Function to deploy service with Helm
deploy_service_with_helm() {
    local service="$1"
    
    log_info "Deploying $service with Helm..."
    
    helm upgrade --install "$service" \
        "$PROJECT_ROOT/k8s/helm/pyairtable-stack/charts/$service" \
        --namespace="$NAMESPACE" \
        --values="$PROJECT_ROOT/k8s/helm/pyairtable-stack/values-$ENVIRONMENT.yaml" \
        --set image.tag="$BUILD_VERSION" \
        --set environment="$ENVIRONMENT" \
        --wait --timeout=300s
}

# Function to deploy service with kubectl
deploy_service_with_kubectl() {
    local service="$1"
    
    log_info "Deploying $service with kubectl..."
    
    local manifest_path="$PROJECT_ROOT/k8s/manifests/$service-deployment.yaml"
    if [[ -f "$manifest_path" ]]; then
        # Replace environment variables in manifest
        envsubst < "$manifest_path" | kubectl apply -f -
    else
        log_warning "No manifest found for $service, skipping..."
        return
    fi
}

# Function to wait for service to be ready
wait_for_service_ready() {
    local service="$1"
    local timeout=300
    local interval=10
    local elapsed=0
    
    log_info "Waiting for $service to be ready..."
    
    while [[ $elapsed -lt $timeout ]]; do
        if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
            local ready_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired_replicas=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
            
            if [[ "$ready_replicas" == "$desired_replicas" ]] && [[ "$ready_replicas" != "0" ]]; then
                log_success "$service is ready ($ready_replicas/$desired_replicas replicas)"
                return 0
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Waiting for $service... ($elapsed/${timeout}s)"
    done
    
    log_error "$service failed to become ready within $timeout seconds"
    return 1
}

# Function to validate service health
validate_service_health() {
    local service="$1"
    
    log_info "Validating health of $service..."
    
    # Get service endpoint
    local service_url
    if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
        local service_ip=$(kubectl get service "$service" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [[ -n "$service_ip" ]]; then
            service_url="http://$service_ip"
        else
            # Use port-forward for cluster-internal testing
            kubectl port-forward "service/$service" 8080:80 -n "$NAMESPACE" &
            local port_forward_pid=$!
            sleep 5
            service_url="http://localhost:8080"
        fi
    else
        log_warning "Service $service not found, skipping health check"
        return 0
    fi
    
    # Health check
    local health_endpoint="$service_url/health"
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" "$health_endpoint" || echo "000")
    
    # Clean up port-forward if used
    if [[ -n "${port_forward_pid:-}" ]]; then
        kill $port_forward_pid 2>/dev/null || true
    fi
    
    if [[ "$response_code" == "200" ]]; then
        log_success "$service health check passed"
        return 0
    else
        log_error "$service health check failed (HTTP $response_code)"
        return 1
    fi
}

# Function to configure ingress
configure_ingress() {
    log_info "Configuring ingress..."
    
    # Apply ingress configuration
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pyairtable-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: "istio"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - api.${DOMAIN_NAME}
    secretName: api-tls-secret
  rules:
  - host: api.${DOMAIN_NAME}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-gateway
            port:
              number: 80
EOF
    
    log_success "Ingress configured"
}

# Function to run smoke tests
run_smoke_tests() {
    log_info "Running smoke tests..."
    
    # Run the Python smoke test script
    if [[ -f "$PROJECT_ROOT/scripts/migration/production-smoke-tests.py" ]]; then
        cd "$PROJECT_ROOT"
        python3 scripts/migration/production-smoke-tests.py \
            --base-url "https://api.${DOMAIN_NAME}" \
            --api-key "${API_KEY}"
    else
        log_warning "Smoke test script not found, running basic health checks..."
        
        # Basic health checks for all services
        for service in "${CORE_SERVICES[@]}" "${PLATFORM_SERVICES[@]}" "${DOMAIN_SERVICES[@]}"; do
            validate_service_health "$service" || log_warning "$service health check failed"
        done
    fi
    
    log_success "Smoke tests completed"
}

# Function to setup monitoring
setup_monitoring() {
    log_info "Setting up monitoring..."
    
    # Deploy Prometheus and Grafana
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Deploy Prometheus
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --create-namespace \
        --values "$PROJECT_ROOT/monitoring/prometheus/values-$ENVIRONMENT.yaml" \
        --wait
    
    # Deploy custom dashboards
    kubectl apply -f "$PROJECT_ROOT/monitoring/grafana-dashboards.yaml"
    
    log_success "Monitoring setup completed"
}

# Function to configure autoscaling
configure_autoscaling() {
    log_info "Configuring autoscaling..."
    
    # Apply HPA configurations
    for service in "${CORE_SERVICES[@]}" "${PLATFORM_SERVICES[@]}" "${DOMAIN_SERVICES[@]}"; do
        cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${service}-hpa
  namespace: $NAMESPACE
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $service
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF
    done
    
    log_success "Autoscaling configured"
}

# Function to deploy complete stack
deploy_complete_stack() {
    log_info "Starting complete stack deployment..."
    
    # Deploy in phases
    deploy_service_group "Infrastructure" "${INFRASTRUCTURE_SERVICES[@]}"
    deploy_service_group "Core Services" "${CORE_SERVICES[@]}"
    deploy_service_group "Platform Services" "${PLATFORM_SERVICES[@]}"
    deploy_service_group "Domain Services" "${DOMAIN_SERVICES[@]}"
    deploy_service_group "Frontend Services" "${FRONTEND_SERVICES[@]}"
    deploy_service_group "Utility Services" "${UTILITY_SERVICES[@]}"
    
    # Configure ingress and networking
    configure_ingress
    
    # Setup monitoring
    setup_monitoring
    
    # Configure autoscaling
    configure_autoscaling
    
    # Run smoke tests
    run_smoke_tests
    
    log_success "Complete stack deployment finished!"
}

# Function to rollback deployment
rollback_deployment() {
    local rollback_version="${1:-}"
    
    log_info "Rolling back deployment..."
    
    if [[ -n "$rollback_version" ]]; then
        log_info "Rolling back to version: $rollback_version"
        
        # Rollback all services to previous version
        for service in "${CORE_SERVICES[@]}" "${PLATFORM_SERVICES[@]}" "${DOMAIN_SERVICES[@]}"; do
            if helm list -n "$NAMESPACE" | grep -q "$service"; then
                helm rollback "$service" 0 -n "$NAMESPACE"
            else
                kubectl set image "deployment/$service" "$service=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/$service:$rollback_version" -n "$NAMESPACE"
            fi
        done
    else
        log_info "Rolling back to previous revision..."
        
        # Rollback using Helm history
        for service in "${CORE_SERVICES[@]}" "${PLATFORM_SERVICES[@]}" "${DOMAIN_SERVICES[@]}"; do
            if helm list -n "$NAMESPACE" | grep -q "$service"; then
                helm rollback "$service" 0 -n "$NAMESPACE"
            fi
        done
    fi
    
    log_success "Rollback completed"
}

# Function to show deployment status
show_deployment_status() {
    log_info "Deployment Status Report"
    echo "========================"
    
    # Show namespace resources
    echo -e "\n${BLUE}Namespace: $NAMESPACE${NC}"
    kubectl get all -n "$NAMESPACE"
    
    # Show service health
    echo -e "\n${BLUE}Service Health Status:${NC}"
    for service in "${CORE_SERVICES[@]}" "${PLATFORM_SERVICES[@]}" "${DOMAIN_SERVICES[@]}"; do
        if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
            local status=$(kubectl get deployment "$service" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
            if [[ "$status" == "True" ]]; then
                echo -e "$service: ${GREEN}✅ Healthy${NC}"
            else
                echo -e "$service: ${RED}❌ Unhealthy${NC}"
            fi
        else
            echo -e "$service: ${YELLOW}⚠️  Not Found${NC}"
        fi
    done
    
    # Show ingress status
    echo -e "\n${BLUE}Ingress Status:${NC}"
    kubectl get ingress -n "$NAMESPACE"
}

# Main execution function
main() {
    local command="${1:-deploy}"
    
    case "$command" in
        "deploy")
            check_prerequisites
            create_namespace
            deploy_secrets
            build_and_push_images
            deploy_complete_stack
            show_deployment_status
            ;;
        "rollback")
            local version="${2:-}"
            rollback_deployment "$version"
            ;;
        "status")
            show_deployment_status
            ;;
        "smoke-test")
            run_smoke_tests
            ;;
        "build")
            build_and_push_images
            ;;
        *)
            echo "Usage: $0 {deploy|rollback|status|smoke-test|build} [version]"
            echo ""
            echo "Commands:"
            echo "  deploy      - Deploy complete PyAirtable stack"
            echo "  rollback    - Rollback deployment to previous version"
            echo "  status      - Show current deployment status"
            echo "  smoke-test  - Run smoke tests against deployment"
            echo "  build       - Build and push Docker images"
            echo ""
            echo "Environment Variables:"
            echo "  NAMESPACE     - Kubernetes namespace (default: pyairtable)"
            echo "  AWS_REGION    - AWS region (default: eu-central-1)"
            echo "  CLUSTER_NAME  - EKS cluster name (default: pyairtable-prod)"
            echo "  ENVIRONMENT   - Environment name (default: production)"
            echo "  BUILD_VERSION - Docker image version tag"
            echo "  DOMAIN_NAME   - Domain name for ingress"
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"