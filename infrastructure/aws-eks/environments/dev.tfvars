# Development Environment Configuration
# Optimized for cost and development workflows

# Project Configuration
project_name = "pyairtable"
environment  = "dev"
owner        = "platform-team"
cost_center  = "engineering"

# AWS Configuration
aws_region = "us-west-2"

# Backend Configuration
terraform_state_bucket = "pyairtable-terraform-state-dev"
terraform_lock_table   = "pyairtable-terraform-locks-dev"

# Network Configuration
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# EKS Configuration
cluster_version = "1.28"

# Node Groups - Cost Optimized for Development
node_groups = {
  # Primary development node group - mostly spot instances
  primary = {
    instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 2
      max_size     = 8
      min_size     = 1
    }
    update_config = {
      max_unavailable_percentage = 50 # Faster updates in dev
    }
    disk_size = 20
    ami_type  = "AL2_x86_64"
    labels = {
      role = "primary"
      cost-optimization = "spot"
      environment = "dev"
    }
    taints = []
  }
  
  # ARM64 node group for testing ARM workloads
  arm64 = {
    instance_types = ["t4g.medium"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 1
      max_size     = 3
      min_size     = 0
    }
    update_config = {
      max_unavailable_percentage = 50
    }
    disk_size = 20
    ami_type  = "AL2_ARM_64"
    labels = {
      role = "arm64"
      cost-optimization = "spot"
      architecture = "arm64"
      environment = "dev"
    }
    taints = []
  }
}

# Cost Optimization Features
enable_spot_instances = true
enable_arm64_nodes    = true
enable_karpenter      = true

# Karpenter Configuration
karpenter_instance_types = [
  "t3.small", "t3.medium", "t3a.small", "t3a.medium",
  "t4g.small", "t4g.medium"
]

# Storage Configuration - Minimal for development
enable_efs = true
efs_performance_mode = "generalPurpose"
efs_throughput_mode  = "bursting"

# Monitoring Configuration - Basic monitoring
enable_container_insights = true
enable_prometheus = true
enable_grafana    = true
enable_fluent_bit = true
enable_loki       = false # Disabled for cost savings in dev
enable_tempo      = false # Disabled for cost savings in dev

# Secrets Management
enable_external_secrets = true

# Development-specific secrets
secrets_config = {
  "database" = {
    description = "Database credentials for development"
    secret_string = {
      host     = "dev-postgres.internal"
      port     = "5432"
      dbname   = "pyairtable_dev"
      username = "postgres"
      # passwords will be generated automatically
    }
  }
  "api-keys" = {
    description = "API keys for development services"
    secret_string = {
      airtable_api_key = "dev_placeholder"
      openai_api_key   = "dev_placeholder"
      stripe_api_key   = "dev_placeholder"
    }
  }
}

# Cost Budget
cost_budget_limit = 100 # $100/month for dev environment
cost_alert_emails = ["dev-team@pyairtable.com"]

# GitHub Configuration
github_org = "pyairtable"
github_repos = ["pyairtable-compose", "pyairtable-frontend"]

# Backup Configuration - Minimal retention for dev
backup_retention_days = 7
enable_automated_backups = false # Disabled for cost savings