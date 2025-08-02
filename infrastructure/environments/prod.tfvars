# Production Environment Configuration
# High-performance, high-availability setup for Central Europe clients

project_name = "pyairtable"
environment  = "prod"
aws_region   = "eu-central-1"

# Network Configuration
vpc_cidr = "10.2.0.0/16"

# EKS Configuration - Production grade
eks_version = "1.28"
enable_spot_instances = false  # On-demand for stability
enable_spot_fleet = false

# Node Group Configurations - Production resources
go_services_node_config = {
  instance_types = ["c5.large", "c5.xlarge"]  # Compute optimized
  min_size       = 2
  max_size       = 10
  desired_size   = 3
  capacity_type  = "ON_DEMAND"
}

python_ai_node_config = {
  instance_types = ["r5.xlarge", "r5.2xlarge"]  # Memory optimized for AI
  min_size       = 2
  max_size       = 8
  desired_size   = 3
  capacity_type  = "ON_DEMAND"
}

general_services_node_config = {
  instance_types = ["m5.large", "m5.xlarge"]  # Balanced
  min_size       = 2
  max_size       = 6
  desired_size   = 3
  capacity_type  = "ON_DEMAND"
}

# Database Configuration - Production Aurora Serverless
aurora_serverless_config = {
  min_capacity = 1
  max_capacity = 16
}

# Resource Quotas - Production appropriate
resource_quotas = {
  cpu_requests    = "32"
  memory_requests = "64Gi"
  cpu_limits      = "64"
  memory_limits   = "128Gi"
  pods           = "100"
}

# Monitoring - Full monitoring for production
log_retention_days = 30
enable_detailed_monitoring = true

# CI/CD Configuration
github_owner = "reg-kris"
github_repo = "pyairtable-compose"
github_branch = "main"

# Cost Optimization - Conservative for production
cost_optimization_enabled = false  # Prioritize performance over cost
monthly_budget_limit = 2000

# Backup - Full retention for production
backup_retention_days = 30
enable_cross_region_backup = true

# Security - Maximum security for production
enable_pod_security_standards = true
enable_network_policies = true

# Lambda - Higher concurrency for production
lambda_reserved_concurrency = 50
lambda_provisioned_concurrency = 10  # Some warm instances

# Auto-scaling - Full featured for production
enable_cluster_autoscaler = true
enable_vertical_pod_autoscaler = true
enable_horizontal_pod_autoscaler = true