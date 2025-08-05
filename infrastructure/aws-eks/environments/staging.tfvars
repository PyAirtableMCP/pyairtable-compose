# Staging Environment Configuration
# Production-like configuration with cost optimizations

# Project Configuration
project_name = "pyairtable"
environment  = "staging"
owner        = "platform-team"
cost_center  = "engineering"

# AWS Configuration
aws_region = "us-west-2"

# Backend Configuration
terraform_state_bucket = "pyairtable-terraform-state-staging"
terraform_lock_table   = "pyairtable-terraform-locks-staging"

# Network Configuration
vpc_cidr        = "10.1.0.0/16"
public_subnets  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnets = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

# EKS Configuration
cluster_version = "1.28"

# Node Groups - Balanced between cost and reliability
node_groups = {
  # Primary node group with mixed capacity
  primary = {
    instance_types = ["t3.large", "t3a.large", "m5.large"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 3
      max_size     = 15
      min_size     = 2
    }
    update_config = {
      max_unavailable_percentage = 25
    }
    disk_size = 30
    ami_type  = "AL2_x86_64"
    labels = {
      role = "primary"
      cost-optimization = "spot"
      environment = "staging"
    }
    taints = []
  }
  
  # On-demand node group for critical workloads
  critical = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    scaling_config = {
      desired_size = 2
      max_size     = 5
      min_size     = 1
    }
    update_config = {
      max_unavailable_percentage = 25
    }
    disk_size = 30
    ami_type  = "AL2_x86_64"
    labels = {
      role = "critical"
      workload-type = "system"
      environment = "staging"
    }
    taints = []
  }
  
  # ARM64 node group
  arm64 = {
    instance_types = ["t4g.large", "m6g.large"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 1
      max_size     = 5
      min_size     = 0
    }
    update_config = {
      max_unavailable_percentage = 25
    }
    disk_size = 30
    ami_type  = "AL2_ARM_64"
    labels = {
      role = "arm64"
      cost-optimization = "spot"
      architecture = "arm64"
      environment = "staging"
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
  "t3.medium", "t3.large", "t3a.medium", "t3a.large",
  "t4g.medium", "t4g.large", "m5.large", "m5a.large",
  "c5.large", "c5a.large"
]

# Storage Configuration
enable_efs = true
efs_performance_mode = "generalPurpose"
efs_throughput_mode  = "bursting"

# Monitoring Configuration - Full monitoring stack
enable_container_insights = true
enable_prometheus = true
enable_grafana    = true
enable_fluent_bit = true
enable_loki       = true
enable_tempo      = false # Can be enabled for tracing if needed

# Secrets Management
enable_external_secrets = true

# Staging-specific secrets
secrets_config = {
  "database" = {
    description = "Database credentials for staging"
    secret_string = {
      host     = "staging-postgres.internal"
      port     = "5432"
      dbname   = "pyairtable_staging"
      username = "postgres"
      # passwords will be generated automatically
    }
  }
  "api-keys" = {
    description = "API keys for staging services"
    secret_string = {
      airtable_api_key = "staging_placeholder"
      openai_api_key   = "staging_placeholder"
      stripe_api_key   = "staging_placeholder"
    }
  }
  "auth" = {
    description = "Authentication secrets for staging"
    secret_string = {
      # jwt_secret will be generated automatically
      oauth_client_id     = "staging_oauth_client_id"
      oauth_client_secret = "staging_oauth_client_secret"
    }
  }
}

# Cost Budget
cost_budget_limit = 300 # $300/month for staging environment
cost_alert_emails = ["platform-team@pyairtable.com"]

# GitHub Configuration
github_org = "pyairtable"
github_repos = ["pyairtable-compose", "pyairtable-frontend", "pyairtable-api"]

# Backup Configuration
backup_retention_days = 14
enable_automated_backups = true