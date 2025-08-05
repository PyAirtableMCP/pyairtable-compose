# Production Environment Configuration
# High availability, security, and performance optimized

# Project Configuration
project_name = "pyairtable"
environment  = "production"
owner        = "platform-team"
cost_center  = "production"

# AWS Configuration
aws_region = "us-west-2"

# Backend Configuration
terraform_state_bucket = "pyairtable-terraform-state-prod"
terraform_lock_table   = "pyairtable-terraform-locks-prod"

# Network Configuration - Larger address space for production
vpc_cidr        = "10.2.0.0/16"
public_subnets  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
private_subnets = ["10.2.11.0/24", "10.2.12.0/24", "10.2.13.0/24"]

# EKS Configuration
cluster_version = "1.28"

# Node Groups - High availability and performance
node_groups = {
  # Primary production node group - mixed spot and on-demand
  primary = {
    instance_types = ["m5.large", "m5.xlarge", "m5a.large", "m5a.xlarge"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 5
      max_size     = 25
      min_size     = 3
    }
    update_config = {
      max_unavailable_percentage = 20 # Conservative for production
    }
    disk_size = 50
    ami_type  = "AL2_x86_64"
    labels = {
      role = "primary"
      cost-optimization = "spot"
      environment = "production"
    }
    taints = []
  }
  
  # Critical on-demand node group for system components
  critical = {
    instance_types = ["m5.large"]
    capacity_type  = "ON_DEMAND"
    scaling_config = {
      desired_size = 3
      max_size     = 8
      min_size     = 2
    }
    update_config = {
      max_unavailable_percentage = 20
    }
    disk_size = 50
    ami_type  = "AL2_x86_64"
    labels = {
      role = "critical"
      workload-type = "system"
      environment = "production"
    }
    taints = []
  }
  
  # Compute-optimized nodes for CPU-intensive workloads
  compute = {
    instance_types = ["c5.large", "c5.xlarge", "c5a.large", "c5a.xlarge"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 2
      max_size     = 10
      min_size     = 0
    }
    update_config = {
      max_unavailable_percentage = 20
    }
    disk_size = 50
    ami_type  = "AL2_x86_64"
    labels = {
      role = "compute"
      workload-type = "cpu-intensive"
      cost-optimization = "spot"
      environment = "production"
    }
    taints = [
      {
        key    = "workload-type"
        value  = "cpu-intensive"
        effect = "NoSchedule"
      }
    ]
  }
  
  # ARM64 nodes for cost optimization
  arm64 = {
    instance_types = ["m6g.large", "m6g.xlarge", "c6g.large", "c6g.xlarge"]
    capacity_type  = "SPOT"
    scaling_config = {
      desired_size = 2
      max_size     = 10
      min_size     = 0
    }
    update_config = {
      max_unavailable_percentage = 20
    }
    disk_size = 50
    ami_type  = "AL2_ARM_64"
    labels = {
      role = "arm64"
      cost-optimization = "spot"
      architecture = "arm64"
      environment = "production"
    }
    taints = []
  }
}

# Cost Optimization Features
enable_spot_instances = true
enable_arm64_nodes    = true
enable_karpenter      = true

# Karpenter Configuration - Extensive instance type coverage
karpenter_instance_types = [
  # General purpose
  "t3.medium", "t3.large", "t3.xlarge",
  "t3a.medium", "t3a.large", "t3a.xlarge",
  "t4g.medium", "t4g.large", "t4g.xlarge",
  "m5.large", "m5.xlarge", "m5.2xlarge",
  "m5a.large", "m5a.xlarge", "m5a.2xlarge",
  "m6i.large", "m6i.xlarge", "m6i.2xlarge",
  "m6g.large", "m6g.xlarge", "m6g.2xlarge",
  # Compute optimized
  "c5.large", "c5.xlarge", "c5.2xlarge",
  "c5a.large", "c5a.xlarge", "c5a.2xlarge",
  "c6i.large", "c6i.xlarge", "c6i.2xlarge",
  "c6g.large", "c6g.xlarge", "c6g.2xlarge",
  # Memory optimized
  "r5.large", "r5.xlarge",
  "r5a.large", "r5a.xlarge",
  "r6g.large", "r6g.xlarge"
]

# Storage Configuration - High performance
enable_efs = true
efs_performance_mode = "generalPurpose"
efs_throughput_mode  = "bursting"

# Monitoring Configuration - Full observability stack
enable_container_insights = true
enable_prometheus = true
enable_grafana    = true
enable_fluent_bit = true
enable_loki       = true
enable_tempo      = true # Full tracing in production

# Secrets Management
enable_external_secrets = true

# Production secrets configuration
secrets_config = {
  "database" = {
    description = "Database credentials for production"
    secret_string = {
      host     = "prod-postgres.internal"
      port     = "5432"
      dbname   = "pyairtable_prod"
      username = "postgres"
      # passwords will be generated automatically
    }
    rotation_days = 90 # Automatic rotation every 90 days
  }
  "api-keys" = {
    description = "API keys for production services"
    secret_string = {
      airtable_api_key = "prod_placeholder"
      openai_api_key   = "prod_placeholder"
      stripe_api_key   = "prod_placeholder"
    }
  }
  "auth" = {
    description = "Authentication secrets for production"
    secret_string = {
      # jwt_secret will be generated automatically
      oauth_client_id     = "prod_oauth_client_id"
      oauth_client_secret = "prod_oauth_client_secret"
    }
    rotation_days = 60 # More frequent rotation for auth secrets
  }
  "ssl-certificates" = {
    description = "SSL certificates and keys"
    secret_string = {
      tls_cert = "prod_tls_cert_placeholder"
      tls_key  = "prod_tls_key_placeholder"
    }
  }
}

# Cost Budget - Higher for production
cost_budget_limit = 1000 # $1000/month for production
cost_alert_emails = [
  "platform-team@pyairtable.com",
  "finance@pyairtable.com",
  "alerts@pyairtable.com"
]

# GitHub Configuration
github_org = "pyairtable"
github_repos = [
  "pyairtable-compose",
  "pyairtable-frontend", 
  "pyairtable-api",
  "pyairtable-mobile",
  "pyairtable-docs"
]

# Backup Configuration - Comprehensive backup strategy
backup_retention_days = 90
enable_automated_backups = true