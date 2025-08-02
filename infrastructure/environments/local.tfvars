# Local Development Environment Configuration
# Optimized for development with minimal resources and cost

project_name = "pyairtable"
environment  = "dev"
aws_region   = "eu-central-1"

# Network Configuration
vpc_cidr = "10.0.0.0/16"

# EKS Configuration - Minimal for local development
eks_version = "1.28"
enable_spot_instances = true
enable_spot_fleet = false

# Node Group Configurations - Minimal resources
go_services_node_config = {
  instance_types = ["t3.small", "t3.medium"]
  min_size       = 1
  max_size       = 2
  desired_size   = 1
  capacity_type  = "SPOT"
}

python_ai_node_config = {
  instance_types = ["t3.medium", "t3.large"]
  min_size       = 1
  max_size       = 2
  desired_size   = 1
  capacity_type  = "SPOT"
}

general_services_node_config = {
  instance_types = ["t3.small", "t3.medium"]  
  min_size       = 1
  max_size       = 2
  desired_size   = 1
  capacity_type  = "SPOT"
}

# Database Configuration - Minimal Aurora Serverless
aurora_serverless_config = {
  min_capacity = 0.5
  max_capacity = 1
}

# Resource Quotas - Limited for local development
resource_quotas = {
  cpu_requests    = "4"
  memory_requests = "8Gi"
  cpu_limits      = "8"
  memory_limits   = "16Gi"
  pods           = "15"
}

# Monitoring - Minimal logging
log_retention_days = 7
enable_detailed_monitoring = false

# CI/CD - Simplified
github_owner = "reg-kris"
github_repo = "pyairtable-compose"
github_branch = "develop"

# Cost Optimization - Aggressive for local
cost_optimization_enabled = true
monthly_budget_limit = 200

# Backup - Minimal for local
backup_retention_days = 3
enable_cross_region_backup = false

# Security - Basic for local
enable_pod_security_standards = true
enable_network_policies = false  # Simplified for local development

# Lambda - Reduced concurrency
lambda_reserved_concurrency = 5
lambda_provisioned_concurrency = 0

# Auto-scaling - Basic
enable_cluster_autoscaler = true
enable_vertical_pod_autoscaler = false  # Not needed for local
enable_horizontal_pod_autoscaler = true