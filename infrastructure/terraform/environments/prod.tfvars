# Production Environment - Performance & Reliability

environment = "prod"
aws_region  = "us-east-1"

# Networking
vpc_cidr = "10.1.0.0/16"

# Database - Production sized
db_instance_class    = "db.t3.small"
db_allocated_storage = 100

# Redis - Production sized
redis_node_type = "cache.t3.small"

# Services - Production resources and scaling
services = {
  frontend = {
    port              = 3000
    cpu               = 512
    memory            = 1024
    desired_count     = 2
    health_check_path = "/api/health"
  }
  api-gateway = {
    port              = 8000
    cpu               = 1024
    memory            = 2048
    desired_count     = 2
    health_check_path = "/health"
  }
  llm-orchestrator = {
    port              = 8003
    cpu               = 2048
    memory            = 4096
    desired_count     = 2
    health_check_path = "/health"
  }
  mcp-server = {
    port              = 8001
    cpu               = 512
    memory            = 1024
    desired_count     = 2
    health_check_path = "/health"
  }
  airtable-gateway = {
    port              = 8002
    cpu               = 512
    memory            = 1024
    desired_count     = 2
    health_check_path = "/health"
  }
  platform-services = {
    port              = 8007
    cpu               = 1024
    memory            = 2048
    desired_count     = 2
    health_check_path = "/health"
  }
  automation-services = {
    port              = 8006
    cpu               = 1024
    memory            = 2048
    desired_count     = 2
    health_check_path = "/health"
  }
}

# SSL and domain (configure these)
certificate_arn = "arn:aws:acm:us-east-1:YOUR_ACCOUNT:certificate/YOUR_CERT_ID"
domain_name     = "api.yourdomain.com"

# Production alerting
alert_email = "ops-team@yourcompany.com"

# Tags
tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Purpose     = "production"
  Backup      = "required"
}