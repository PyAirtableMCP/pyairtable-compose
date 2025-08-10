# Production Environment Configuration for PyAirtable EKS Deployment
# Cost-optimized with high availability and security

# Project Configuration
project_name = "pyairtable"
environment  = "production"
owner        = "3vantage-team"
cost_center  = "engineering"

# AWS Configuration
aws_region = "us-west-2"
terraform_state_bucket = "pyairtable-terraform-state-prod"
terraform_lock_table   = "pyairtable-terraform-locks-prod"

# Network Configuration
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# EKS Configuration
cluster_version = "1.28"

# Node Groups - Production Configuration with Cost Optimization
node_groups = {
  # Primary workload nodes - 70% spot instances for cost savings
  primary = {
    instance_types = ["t3.medium", "t3a.medium", "t3.large"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 3
      max_size     = 15
      min_size     = 2
    }
    update_config = {
      max_unavailable_percentage = 25
    }
    disk_size = 50
    ami_type  = "AL2_x86_64"
    labels = {
      role = "primary"
      cost-optimization = "spot"
      workload = "general"
    }
    taints = []
  }
  
  # ARM64 nodes for better price/performance ratio
  arm64 = {
    instance_types = ["t4g.medium", "t4g.large", "m6g.medium"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 2
      max_size     = 8
      min_size     = 1
    }
    update_config = {
      max_unavailable_percentage = 25
    }
    disk_size = 50
    ami_type  = "AL2_ARM_64"
    labels = {
      role = "arm64"
      cost-optimization = "spot"
      architecture = "arm64"
      workload = "general"
    }
    taints = []
  }
  
  # Critical system components - On-demand for stability
  system = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    scaling_config = {
      desired_size = 2
      max_size     = 4
      min_size     = 2
    }
    update_config = {
      max_unavailable_percentage = 25
    }
    disk_size = 30
    ami_type  = "AL2_x86_64"
    labels = {
      role = "system"
      workload-type = "critical"
      node-type = "on-demand"
    }
    taints = [{
      key    = "system-critical"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
  }
}

# Cost Optimization Features
enable_spot_instances = true
enable_arm64_nodes    = true
enable_karpenter      = true

karpenter_instance_types = [
  "t3.small", "t3.medium", "t3.large", 
  "t3a.small", "t3a.medium", "t3a.large",
  "t4g.small", "t4g.medium", "t4g.large",
  "m5.large", "m5a.large", "m6g.large"
]

# Storage Configuration
enable_efs             = true
efs_performance_mode   = "generalPurpose"
efs_throughput_mode    = "bursting"

# Monitoring and Observability
enable_container_insights = true
enable_prometheus        = true
enable_grafana          = true
enable_fluent_bit       = true

# Security Configuration
enable_external_secrets = true

secrets_config = {
  "pyairtable/production/api" = {
    description = "Production API keys and tokens"
    secret_string = {
      airtable_token    = "CHANGE_ME_AIRTABLE_TOKEN"
      gemini_api_key    = "CHANGE_ME_GEMINI_API_KEY"
      api_key           = "CHANGE_ME_API_KEY"
      nextauth_secret   = "CHANGE_ME_NEXTAUTH_SECRET"
      jwt_secret        = "CHANGE_ME_JWT_SECRET"
    }
  }
  "pyairtable/production/database" = {
    description = "Production database credentials"
    secret_string = {
      postgres_password = "CHANGE_ME_POSTGRES_PASSWORD"
      redis_password    = "CHANGE_ME_REDIS_PASSWORD"
      postgres_user     = "pyairtable_prod"
      postgres_db       = "pyairtable_production"
    }
  }
  "pyairtable/production/config" = {
    description = "Production configuration values"
    secret_string = {
      cors_origins      = "https://pyairtable.com,https://www.pyairtable.com"
      environment       = "production"
      log_level         = "info"
      thinking_budget   = "20000"
    }
  }
}

# CI/CD Configuration
github_org   = "reg-kris"
github_repos = [
  "pyairtable-compose",
  "pyairtable-frontend", 
  "pyairtable-api-gateway",
  "llm-orchestrator-py",
  "mcp-server-py",
  "airtable-gateway-py"
]

# Cost Management
cost_budget_limit = 500  # $500/month budget limit
cost_alert_emails = [
  "admin@3vantage.com",
  "alerts@3vantage.com"
]

# Backup and Recovery
backup_retention_days    = 30
enable_automated_backups = true