# AWS EKS Infrastructure for PyAirtable Platform
# Optimized for cost efficiency, scalability, and security

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
  
  backend "s3" {
    # Configure your S3 backend
    bucket = var.terraform_state_bucket
    key    = "pyairtable/eks/terraform.tfstate"
    region = var.aws_region
    
    dynamodb_table = var.terraform_lock_table
    encrypt        = true
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "PyAirtable"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
      CostCenter  = var.cost_center
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values for resource naming and configuration
locals {
  cluster_name = "${var.project_name}-${var.environment}-eks"
  
  # Use first 3 AZs for multi-AZ deployment
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
  
  # Cost optimization tags
  cost_tags = {
    "aws:cost-allocation:project" = var.project_name
    "aws:cost-allocation:env"     = var.environment
    "aws:cost-allocation:team"    = var.owner
  }
}

# Include all modules
module "vpc" {
  source = "./modules/vpc"
  
  project_name    = var.project_name
  environment     = var.environment
  aws_region      = var.aws_region
  vpc_cidr        = var.vpc_cidr
  azs             = local.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  
  # Enable VPC Flow Logs for security
  enable_flow_log                = true
  flow_log_destination_type      = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group = true
  
  # Enable DNS
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  # Cost optimization
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "production" # Single NAT for cost savings in non-prod
  
  tags = merge(local.common_tags, local.cost_tags)
}

module "security" {
  source = "./modules/security"
  
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
  
  tags = merge(local.common_tags, local.cost_tags)
}

module "iam" {
  source = "./modules/iam"
  
  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
  
  tags = merge(local.common_tags, local.cost_tags)
}

module "eks" {
  source = "./modules/eks"
  
  project_name                = var.project_name
  environment                 = var.environment
  cluster_name                = local.cluster_name
  cluster_version             = var.cluster_version
  
  vpc_id                      = module.vpc.vpc_id
  subnet_ids                  = module.vpc.private_subnets
  control_plane_subnet_ids    = module.vpc.private_subnets
  
  # Security groups
  cluster_security_group_id   = module.security.cluster_security_group_id
  node_security_group_id      = module.security.node_security_group_id
  
  # IAM roles
  cluster_service_role_arn    = module.iam.cluster_service_role_arn
  node_instance_profile_name  = module.iam.node_instance_profile_name
  
  # Node group configuration
  node_groups = var.node_groups
  
  # Spot instance configuration for cost optimization
  enable_spot_instances = var.enable_spot_instances
  spot_allocation_strategy = "diversified"
  
  # Enable ARM64 nodes for better price/performance
  enable_arm64_nodes = var.enable_arm64_nodes
  
  tags = merge(local.common_tags, local.cost_tags)
  
  depends_on = [module.vpc, module.security, module.iam]
}

module "storage" {
  source = "./modules/storage"
  
  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
  
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnets
  security_group_ids = [module.security.efs_security_group_id]
  
  # EBS CSI Driver
  enable_ebs_csi_driver = true
  
  # EFS Configuration
  enable_efs = var.enable_efs
  efs_performance_mode = var.efs_performance_mode
  efs_throughput_mode  = var.efs_throughput_mode
  
  tags = merge(local.common_tags, local.cost_tags)
  
  depends_on = [module.eks]
}

module "karpenter" {
  source = "./modules/karpenter"
  
  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
  
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  
  # Enable Karpenter for cost optimization
  enable_karpenter = var.enable_karpenter
  
  # Node pool configuration for cost optimization
  instance_types = var.karpenter_instance_types
  capacity_types = ["spot", "on-demand"]
  
  # Spot instance configuration
  spot_allocation_strategy = "price-capacity-optimized"
  
  tags = merge(local.common_tags, local.cost_tags)
  
  depends_on = [module.eks]
}

module "monitoring" {
  source = "./modules/monitoring"
  
  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
  
  # CloudWatch Container Insights
  enable_container_insights = var.enable_container_insights
  
  # Prometheus & Grafana
  enable_prometheus = var.enable_prometheus
  enable_grafana    = var.enable_grafana
  
  # Logging
  enable_fluent_bit = var.enable_fluent_bit
  
  tags = merge(local.common_tags, local.cost_tags)
  
  depends_on = [module.eks]
}

module "secrets" {
  source = "./modules/secrets"
  
  project_name = var.project_name
  environment  = var.environment
  
  # AWS Secrets Manager
  secrets = var.secrets_config
  
  # External Secrets Operator
  enable_external_secrets = var.enable_external_secrets
  
  tags = merge(local.common_tags, local.cost_tags)
  
  depends_on = [module.eks]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}