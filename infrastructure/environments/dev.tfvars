# Development Environment Configuration
# Production-like setup with cost optimizations for testing

project_name = "pyairtable"
environment  = "dev"
aws_region   = "eu-central-1"

# Network Configuration
vpc_cidr = "10.1.0.0/16"

# EKS Configuration - Balanced for development testing
eks_version = "1.28"
enable_spot_instances = true
enable_spot_fleet = false

# Node Group Configurations - Balanced resources
go_services_node_config = {
  instance_types = ["t3.medium", "t3.large"]
  min_size       = 1
  max_size       = 4
  desired_size   = 2
  capacity_type  = "SPOT"
}

python_ai_node_config = {
  instance_types = ["r5.large", "r5.xlarge"]
  min_size       = 1
  max_size       = 3
  desired_size   = 2
  capacity_type  = "SPOT"
}

general_services_node_config = {
  instance_types = ["t3.medium", "t3.large"]
  min_size       = 1
  max_size       = 3
  desired_size   = 2
  capacity_type  = "SPOT"  # Cost optimization
}

# Database Configuration - Development tier Aurora Serverless
aurora_serverless_config = {
  min_capacity = 0.5
  max_capacity = 4
}

# Resource Quotas - Development appropriate
resource_quotas = {
  cpu_requests    = "8"
  memory_requests = "16Gi"
  cpu_limits      = "16"
  memory_limits   = "32Gi"
  pods           = "25"
}

# Monitoring - Standard for development
log_retention_days = 14
enable_detailed_monitoring = false

# CI/CD Configuration
github_owner = "reg-kris"
github_repo = "pyairtable-compose"
github_branch = "develop"

# Cost Optimization - Enabled for development
cost_optimization_enabled = true
monthly_budget_limit = 400

# Backup - Short retention for development
backup_retention_days = 7
enable_cross_region_backup = false

# Security - Full security for realistic testing
enable_pod_security_standards = true
enable_network_policies = true

# Lambda - Standard concurrency
lambda_reserved_concurrency = 10
lambda_provisioned_concurrency = 0

# Auto-scaling - Full featured for testing
enable_cluster_autoscaler = true
enable_vertical_pod_autoscaler = true
enable_horizontal_pod_autoscaler = true