#!/bin/bash

# PyAirtable Production EKS Deployment Script
# Comprehensive deployment automation for AWS EKS production environment

set -euo pipefail

# Configuration
PROJECT_NAME="pyairtable"
ENVIRONMENT="production"
AWS_REGION="us-west-2"
CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eks"
TERRAFORM_DIR="infrastructure/aws-eks"
K8S_DIR="k8s/production"

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Check logs above for details"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Check required tools
    local required_tools=("aws" "kubectl" "terraform" "helm")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool '$tool' is not installed"
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured"
    fi
    
    # Check if user has necessary permissions
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "Deploying to AWS account: $account_id"
    
    # Verify Terraform state bucket exists
    local state_bucket="${PROJECT_NAME}-terraform-state-prod"
    if ! aws s3 ls "s3://$state_bucket" &> /dev/null; then
        log_warning "Terraform state bucket does not exist. Creating..."
        aws s3 mb "s3://$state_bucket" --region "$AWS_REGION"
        aws s3api put-bucket-versioning --bucket "$state_bucket" --versioning-configuration Status=Enabled
        aws s3api put-bucket-encryption --bucket "$state_bucket" --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    fi
    
    # Verify DynamoDB lock table exists
    local lock_table="${PROJECT_NAME}-terraform-locks-prod"
    if ! aws dynamodb describe-table --table-name "$lock_table" &> /dev/null; then
        log_warning "Terraform lock table does not exist. Creating..."
        aws dynamodb create-table \
            --table-name "$lock_table" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "$AWS_REGION"
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$lock_table" --region "$AWS_REGION"
    fi
    
    log_success "Pre-flight checks completed"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    log_info "Planning infrastructure deployment..."
    terraform plan -var-file="terraform.tfvars" -out=tfplan
    
    # Apply deployment
    log_info "Applying infrastructure deployment..."
    terraform apply tfplan
    
    # Output important values
    log_info "Infrastructure deployment completed. Getting outputs..."
    local cluster_endpoint=$(terraform output -raw cluster_endpoint 2>/dev/null || echo "")
    local cluster_arn=$(terraform output -raw cluster_arn 2>/dev/null || echo "")
    
    if [ -n "$cluster_endpoint" ] && [ -n "$cluster_arn" ]; then
        log_success "EKS cluster created successfully"
        log_info "Cluster endpoint: $cluster_endpoint"
        log_info "Cluster ARN: $cluster_arn"
    else
        error_exit "Failed to retrieve cluster information"
    fi
    
    cd - > /dev/null
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl for EKS cluster..."
    
    # Update kubeconfig
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
    
    # Test cluster connectivity
    if kubectl cluster-info &> /dev/null; then
        log_success "Successfully connected to EKS cluster"
        kubectl get nodes
    else
        error_exit "Failed to connect to EKS cluster"
    fi
}

# Install necessary Kubernetes addons
install_addons() {
    log_info "Installing Kubernetes addons..."
    
    # Install AWS Load Balancer Controller
    log_info "Installing AWS Load Balancer Controller..."
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    if ! helm list -n kube-system | grep -q aws-load-balancer-controller; then
        helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="$CLUSTER_NAME" \
            --set serviceAccount.create=false \
            --set serviceAccount.name=aws-load-balancer-controller \
            --set region="$AWS_REGION" \
            --set vpcId=$(terraform -chdir="$TERRAFORM_DIR" output -raw vpc_id)
    fi
    
    # Install External Secrets Operator
    log_info "Installing External Secrets Operator..."
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    
    if ! helm list -n external-secrets-system | grep -q external-secrets; then
        kubectl create namespace external-secrets-system --dry-run=client -o yaml | kubectl apply -f -
        helm install external-secrets external-secrets/external-secrets \
            -n external-secrets-system \
            --create-namespace \
            --set installCRDs=true
    fi
    
    # Install Metrics Server (if not already installed)
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log_info "Installing Metrics Server..."
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    fi
    
    # Install Vertical Pod Autoscaler
    if ! kubectl get deployment vpa-recommender -n kube-system &> /dev/null; then
        log_info "Installing Vertical Pod Autoscaler..."
        git clone https://github.com/kubernetes/autoscaler.git /tmp/autoscaler || true
        cd /tmp/autoscaler/vertical-pod-autoscaler/
        ./hack/vpa-install.sh
        cd - > /dev/null
        rm -rf /tmp/autoscaler
    fi
    
    log_success "Kubernetes addons installed successfully"
}

# Create necessary namespaces
create_namespaces() {
    log_info "Creating Kubernetes namespaces..."
    
    local namespaces=("amazon-cloudwatch" "monitoring")
    for ns in "${namespaces[@]}"; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    done
    
    log_success "Namespaces created successfully"
}

# Deploy applications
deploy_applications() {
    log_info "Deploying PyAirtable applications..."
    
    # Deploy in order
    local manifests=(
        "00-namespace.yaml"
        "01-external-secrets.yaml"  
        "02-api-gateway.yaml"
        "03-llm-orchestrator.yaml"
        "04-mcp-server.yaml"
        "05-airtable-gateway.yaml"
        "06-platform-services.yaml"
        "07-automation-services.yaml"
        "08-saga-orchestrator.yaml"
        "09-frontend.yaml"
        "10-ingress-alb.yaml"
        "11-storage-config.yaml"
    )
    
    for manifest in "${manifests[@]}"; do
        log_info "Applying $manifest..."
        kubectl apply -f "$K8S_DIR/$manifest"
        
        # Wait a bit between deployments
        sleep 5
    done
    
    log_success "Applications deployed successfully"
}

# Deploy monitoring stack
deploy_monitoring() {
    log_info "Deploying monitoring stack..."
    
    # Deploy LGTM stack
    kubectl apply -f "$K8S_DIR/12-monitoring-lgtm.yaml"
    
    # Deploy CloudWatch integration
    kubectl apply -f "$K8S_DIR/13-cloudwatch-integration.yaml"
    
    # Wait for monitoring pods to be ready
    log_info "Waiting for monitoring stack to be ready..."
    kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
    kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=300s
    
    log_success "Monitoring stack deployed successfully"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if all pods are running
    log_info "Checking pod status..."
    kubectl get pods -n pyairtable-production
    
    # Check services
    log_info "Checking services..."
    kubectl get services -n pyairtable-production
    
    # Check ingresses
    log_info "Checking ingresses..."
    kubectl get ingress -n pyairtable-production
    
    # Health check endpoints
    log_info "Performing health checks..."
    local services=("api-gateway:8000" "llm-orchestrator:8003" "mcp-server:8001" "airtable-gateway:8002" "platform-services:8007" "automation-services:8006" "saga-orchestrator:8008" "frontend:3000")
    
    for service in "${services[@]}"; do
        local service_name=$(echo "$service" | cut -d: -f1)
        local port=$(echo "$service" | cut -d: -f2)
        
        log_info "Health checking $service_name..."
        if kubectl exec -n pyairtable-production deployment/"$service_name" -- curl -f "http://localhost:$port/health" &> /dev/null; then
            log_success "$service_name health check passed"
        else
            log_warning "$service_name health check failed - this may be normal during initial startup"
        fi
    done
    
    # Check HPA status
    log_info "Checking Horizontal Pod Autoscaler status..."
    kubectl get hpa -n pyairtable-production
    
    # Check persistent volumes
    log_info "Checking persistent volumes..."
    kubectl get pv
    kubectl get pvc -n pyairtable-production
    
    log_success "Deployment validation completed"
}

# Get deployment information
get_deployment_info() {
    log_info "Getting deployment information..."
    
    # Get Load Balancer URLs
    log_info "Load Balancer information:"
    kubectl get ingress -n pyairtable-production -o wide
    
    # Get Grafana URL
    local grafana_url=$(kubectl get service grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -n "$grafana_url" ]; then
        log_info "Grafana dashboard: http://$grafana_url:3000"
        log_info "Default Grafana credentials: admin/admin123"
    fi
    
    # Get important endpoints
    log_info "Important endpoints will be available at:"
    log_info "- Frontend: https://pyairtable.com"
    log_info "- API: https://api.pyairtable.com"
    log_info "- Grafana: http://$grafana_url:3000"
    
    # Cost estimation
    log_info "Estimated monthly cost:"
    log_info "- EKS Cluster: ~$73/month"
    log_info "- EC2 Instances (mixed): ~$150-300/month"
    log_info "- RDS PostgreSQL: ~$50-100/month"
    log_info "- ElastiCache Redis: ~$25-50/month"
    log_info "- Load Balancers: ~$25/month"
    log_info "- Data Transfer: ~$10-50/month"
    log_info "Total estimated: ~$333-598/month"
    
    log_success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log_info "Starting PyAirtable production deployment to AWS EKS..."
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Environment: $ENVIRONMENT"
    
    # Ask for confirmation
    echo -e "${YELLOW}This will deploy PyAirtable to production. Are you sure? (y/N)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment steps
    preflight_checks
    deploy_infrastructure
    configure_kubectl
    create_namespaces
    install_addons
    deploy_applications
    deploy_monitoring
    validate_deployment
    get_deployment_info
    
    log_success "PyAirtable production deployment completed successfully!"
    log_info "Please update your DNS records to point to the Load Balancer endpoints"
    log_info "Remember to update secrets in AWS Secrets Manager with real values"
}

# Run main function
main "$@"