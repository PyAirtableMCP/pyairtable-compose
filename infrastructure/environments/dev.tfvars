# Development Environment Configuration

environment = "dev"
aws_region  = "us-east-1"

# VPC Configuration
vpc_cidr = "10.0.0.0/16"

# Domain and SSL (optional for dev)
domain_name     = ""
certificate_arn = ""

# Service Configuration Overrides for Dev
service_configs = {
  frontend = {
    port           = 3000
    cpu            = 256
    memory         = 512
    desired_count  = 1
    health_check_path = "/api/health"
    priority       = 100
  }
  api-gateway = {
    port           = 8000
    cpu            = 256
    memory         = 512
    desired_count  = 1
    health_check_path = "/health"
    priority       = 200
  }
  llm-orchestrator = {
    port           = 8003
    cpu            = 512
    memory         = 1024
    desired_count  = 1
    health_check_path = "/health"
    priority       = 300
  }
  mcp-server = {
    port           = 8001
    cpu            = 256
    memory         = 512
    desired_count  = 1
    health_check_path = "/health"
    priority       = 400
  }
  airtable-gateway = {
    port           = 8002
    cpu            = 256
    memory         = 512
    desired_count  = 1
    health_check_path = "/health"
    priority       = 500
  }
  platform-services = {
    port           = 8007
    cpu            = 256
    memory         = 512
    desired_count  = 1
    health_check_path = "/health"
    priority       = 600
  }
  automation-services = {
    port           = 8006
    cpu            = 256
    memory         = 512
    desired_count  = 1
    health_check_path = "/health"
    priority       = 700
  }
}

# Environment-specific settings
environment_configs = {
  dev = {
    min_capacity = 1
    max_capacity = 2
    enable_autoscaling = false
    enable_deletion_protection = false
  }
}

# Database Configuration
enable_rds           = true
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20

# Redis Configuration  
enable_elasticache     = true
redis_node_type        = "cache.t3.micro"
redis_num_cache_nodes  = 1

# Logging
log_retention_days = 7