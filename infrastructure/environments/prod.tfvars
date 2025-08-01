# Production Environment Configuration

environment = "prod"
aws_region  = "us-east-1"

# VPC Configuration
vpc_cidr = "10.1.0.0/16"

# Domain and SSL (configure these for production)
domain_name     = "api.yourdomain.com"
certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERTIFICATE_ID"

# Service Configuration for Production
service_configs = {
  frontend = {
    port           = 3000
    cpu            = 512
    memory         = 1024
    desired_count  = 2
    health_check_path = "/api/health"
    priority       = 100
  }
  api-gateway = {
    port           = 8000
    cpu            = 1024
    memory         = 2048
    desired_count  = 3
    health_check_path = "/health"
    priority       = 200
  }
  llm-orchestrator = {
    port           = 8003
    cpu            = 2048
    memory         = 4096
    desired_count  = 2
    health_check_path = "/health"
    priority       = 300
  }
  mcp-server = {
    port           = 8001
    cpu            = 1024
    memory         = 2048
    desired_count  = 2
    health_check_path = "/health"
    priority       = 400
  }
  airtable-gateway = {
    port           = 8002
    cpu            = 512
    memory         = 1024
    desired_count  = 2
    health_check_path = "/health"
    priority       = 500
  }
  platform-services = {
    port           = 8007
    cpu            = 1024
    memory         = 2048
    desired_count  = 2
    health_check_path = "/health"
    priority       = 600
  }
  automation-services = {
    port           = 8006
    cpu            = 1024
    memory         = 2048
    desired_count  = 2
    health_check_path = "/health"
    priority       = 700
  }
}

# Environment-specific settings
environment_configs = {
  prod = {
    min_capacity = 2
    max_capacity = 10
    enable_autoscaling = true
    enable_deletion_protection = true
  }
}

# Database Configuration
enable_rds           = true
db_instance_class    = "db.t3.small"
db_allocated_storage = 100

# Redis Configuration
enable_elasticache     = true
redis_node_type        = "cache.t3.small"
redis_num_cache_nodes  = 1

# Logging
log_retention_days = 30