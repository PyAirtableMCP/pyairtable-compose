#!/bin/bash

# Multi-Region PyAirtable Infrastructure Deployment Script
# This script deploys the complete multi-region infrastructure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="pyairtable"
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

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
    
    # Check if required tools are installed
    local required_tools=("terraform" "aws" "jq" "kubectl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    if [[ $(echo "$tf_version 1.5.0" | tr " " "\n" | sort -V | head -n1) != "1.5.0" ]]; then
        log_error "Terraform version must be >= 1.5.0 (current: $tf_version)"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check if terraform.tfvars exists
    if [[ ! -f "$SCRIPT_DIR/terraform.tfvars" ]]; then
        log_error "terraform.tfvars not found. Copy terraform.tfvars.example and customize it."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate AWS permissions
validate_aws_permissions() {
    log_info "Validating AWS permissions..."
    
    local required_permissions=(
        "iam:ListRoles"
        "ec2:DescribeVpcs"
        "rds:DescribeDBInstances"
        "elasticache:DescribeReplicationGroups"
        "eks:ListClusters"
        "s3:ListAllMyBuckets"
        "route53:ListHostedZones"
        "cloudfront:ListDistributions"
    )
    
    for permission in "${required_permissions[@]}"; do
        local service
        service=$(echo "$permission" | cut -d':' -f1)
        local action
        action=$(echo "$permission" | cut -d':' -f2)
        
        if ! aws "$service" "$action" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
            log_error "Missing permission: $permission"
            exit 1
        fi
    done
    
    log_success "AWS permissions validation passed"
}

# Function to initialize Terraform backend
init_terraform_backend() {
    log_info "Initializing Terraform backend..."
    
    cd "$SCRIPT_DIR"
    
    # Create S3 bucket for Terraform state if it doesn't exist
    local state_bucket="${PROJECT_NAME}-terraform-state-global"
    if ! aws s3 ls "s3://$state_bucket" &> /dev/null; then
        aws s3 mb "s3://$state_bucket" --region "$AWS_DEFAULT_REGION"
        aws s3api put-bucket-versioning \
            --bucket "$state_bucket" \
            --versioning-configuration Status=Enabled
        aws s3api put-bucket-encryption \
            --bucket "$state_bucket" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'
        log_success "Created Terraform state bucket: $state_bucket"
    fi
    
    # Create DynamoDB table for state locking if it doesn't exist
    local lock_table="${PROJECT_NAME}-terraform-state-lock-global"
    if ! aws dynamodb describe-table --table-name "$lock_table" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
        aws dynamodb create-table \
            --table-name "$lock_table" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "$AWS_DEFAULT_REGION"
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name "$lock_table" --region "$AWS_DEFAULT_REGION"
        log_success "Created Terraform state lock table: $lock_table"
    fi
    
    # Initialize Terraform
    terraform init \
        -backend-config="bucket=$state_bucket" \
        -backend-config="key=multi-region/terraform.tfstate" \
        -backend-config="region=$AWS_DEFAULT_REGION" \
        -backend-config="encrypt=true" \
        -backend-config="dynamodb_table=$lock_table"
    
    log_success "Terraform backend initialized"
}

# Function to validate Terraform configuration
validate_terraform() {
    log_info "Validating Terraform configuration..."
    
    cd "$SCRIPT_DIR"
    
    terraform validate
    terraform fmt -check=true -diff=true
    
    log_success "Terraform configuration validation passed"
}

# Function to plan deployment
plan_deployment() {
    log_info "Creating Terraform plan..."
    
    cd "$SCRIPT_DIR"
    
    terraform plan \
        -var-file="terraform.tfvars" \
        -out="tfplan" \
        -detailed-exitcode
    
    local exit_code=$?
    
    case $exit_code in
        0)
            log_info "No changes detected"
            return 0
            ;;
        1)
            log_error "Terraform plan failed"
            exit 1
            ;;
        2)
            log_info "Changes detected in plan"
            return 2
            ;;
    esac
}

# Function to apply deployment
apply_deployment() {
    log_info "Applying Terraform configuration..."
    
    cd "$SCRIPT_DIR"
    
    terraform apply \
        -var-file="terraform.tfvars" \
        -auto-approve \
        "tfplan"
    
    log_success "Terraform apply completed"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    cd "$SCRIPT_DIR"
    
    # Get outputs
    local outputs
    outputs=$(terraform output -json)
    
    # Verify CloudFront distribution
    local cloudfront_id
    cloudfront_id=$(echo "$outputs" | jq -r '.cloudfront_distribution_id.value')
    if [[ "$cloudfront_id" != "null" ]]; then
        log_success "CloudFront distribution created: $cloudfront_id"
    else
        log_error "CloudFront distribution not found"
        return 1
    fi
    
    # Verify regional endpoints
    local regions=("us_east" "eu_west" "ap_southeast")
    for region in "${regions[@]}"; do
        local alb_dns
        alb_dns=$(echo "$outputs" | jq -r ".${region}_region.value.alb_dns_name")
        if [[ "$alb_dns" != "null" ]]; then
            log_success "$region ALB created: $alb_dns"
        else
            log_error "$region ALB not found"
            return 1
        fi
    done
    
    # Verify databases
    for region in "${regions[@]}"; do
        local db_endpoint
        db_endpoint=$(echo "$outputs" | jq -r ".${region}_region.value.db_endpoint")
        if [[ "$db_endpoint" != "null" ]]; then
            log_success "$region database created: $db_endpoint"
        else
            log_error "$region database not found"
            return 1
        fi
    done
    
    log_success "Deployment verification completed"
}

# Function to setup kubectl contexts
setup_kubectl_contexts() {
    log_info "Setting up kubectl contexts for EKS clusters..."
    
    cd "$SCRIPT_DIR"
    
    local outputs
    outputs=$(terraform output -json)
    
    local regions=("us_east" "eu_west" "ap_southeast")
    local aws_regions=("us-east-1" "eu-west-1" "ap-southeast-1")
    
    for i in "${!regions[@]}"; do
        local region="${regions[$i]}"
        local aws_region="${aws_regions[$i]}"
        local cluster_name
        cluster_name=$(echo "$outputs" | jq -r ".kubernetes_clusters.value.${region}.cluster_name")
        
        if [[ "$cluster_name" != "null" ]]; then
            aws eks update-kubeconfig \
                --region "$aws_region" \
                --name "$cluster_name" \
                --alias "${PROJECT_NAME}-${ENVIRONMENT}-${region}"
            log_success "kubectl context configured for $region: ${PROJECT_NAME}-${ENVIRONMENT}-${region}"
        fi
    done
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===================="
    
    cd "$SCRIPT_DIR"
    
    local outputs
    outputs=$(terraform output -json)
    
    echo -e "\n${GREEN}Global Endpoints:${NC}"
    echo "Primary Domain: $(echo "$outputs" | jq -r '.domain_name.value')"
    echo "CloudFront: $(echo "$outputs" | jq -r '.cloudfront_domain_name.value')"
    echo "API Domain: api.$(echo "$outputs" | jq -r '.domain_name.value')"
    
    echo -e "\n${GREEN}Regional Infrastructure:${NC}"
    local regions=("us_east" "eu_west" "ap_southeast")
    local region_names=("US East" "EU West" "AP Southeast")
    
    for i in "${!regions[@]}"; do
        local region="${regions[$i]}"
        local region_name="${region_names[$i]}"
        echo -e "\n$region_name:"
        echo "  ALB: $(echo "$outputs" | jq -r ".${region}_region.value.alb_dns_name")"
        echo "  Database: $(echo "$outputs" | jq -r ".${region}_region.value.db_endpoint")"
        echo "  Redis: $(echo "$outputs" | jq -r ".${region}_region.value.redis_endpoint")"
        echo "  EKS: $(echo "$outputs" | jq -r ".kubernetes_clusters.value.${region}.cluster_name")"
    done
    
    echo -e "\n${GREEN}Security Features:${NC}"
    echo "WAF Enabled: $(echo "$outputs" | jq -r '.security_features.value.waf_enabled')"
    echo "Encryption at Rest: $(echo "$outputs" | jq -r '.security_features.value.encryption_at_rest')"
    echo "Encryption in Transit: $(echo "$outputs" | jq -r '.security_features.value.encryption_in_transit')"
    
    echo -e "\n${GREEN}Disaster Recovery:${NC}"
    echo "Auto Failover: $(echo "$outputs" | jq -r '.disaster_recovery.value.auto_failover_enabled')"
    echo "RTO: $(echo "$outputs" | jq -r '.disaster_recovery.value.rto_minutes') minutes"
    echo "RPO: $(echo "$outputs" | jq -r '.disaster_recovery.value.rpo_minutes') minutes"
    
    echo -e "\n${GREEN}Cost Optimization:${NC}"
    echo "Auto Scaling: $(echo "$outputs" | jq -r '.cost_optimization.value.auto_scaling_enabled')"
    echo "Spot Instances: $(echo "$outputs" | jq -r '.cost_optimization.value.spot_instances_enabled')"
    echo "Monthly Budget: $$(echo "$outputs" | jq -r '.cost_optimization.value.monthly_budget_limit')"
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. Update DNS records to point to CloudFront distribution"
    echo "2. Configure SSL certificates if not already done"
    echo "3. Set up monitoring alerts and dashboards"
    echo "4. Test disaster recovery procedures"
    echo "5. Deploy application services to EKS clusters"
    
    echo -e "\n${BLUE}kubectl Contexts:${NC}"
    kubectl config get-contexts | grep "${PROJECT_NAME}-${ENVIRONMENT}" || true
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Check the logs above for details"
        log_info "Run 'terraform destroy' to clean up partial deployment if needed"
    fi
}

# Main deployment function
main() {
    log_info "Starting multi-region PyAirtable infrastructure deployment"
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_DEFAULT_REGION"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Run deployment steps
    check_prerequisites
    validate_aws_permissions
    init_terraform_backend
    validate_terraform
    
    # Plan deployment
    if plan_deployment; then
        local plan_exit_code=$?
        if [[ $plan_exit_code -eq 0 ]]; then
            log_info "No changes to apply"
            return 0
        fi
    fi
    
    # Confirm deployment
    if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
        echo -e "\n${YELLOW}Review the plan above and confirm deployment.${NC}"
        read -p "Do you want to proceed with the deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Apply deployment
    apply_deployment
    verify_deployment
    setup_kubectl_contexts
    display_summary
    
    log_success "Multi-region infrastructure deployment completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --environment|-e)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --region|-r)
            AWS_DEFAULT_REGION="$2"
            shift 2
            ;;
        --auto-approve|-y)
            export AUTO_APPROVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -e, --environment    Environment name (default: prod)"
            echo "  -r, --region        AWS region (default: us-east-1)"
            echo "  -y, --auto-approve  Auto approve deployment"
            echo "  -h, --help          Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  ENVIRONMENT         Environment name"
            echo "  AWS_DEFAULT_REGION  AWS region"
            echo "  AUTO_APPROVE        Auto approve deployment (true/false)"
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