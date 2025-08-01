# Development Environment - Cost Optimized

environment = "dev"
aws_region  = "us-east-1"

# Networking
vpc_cidr = "10.0.0.0/16"

# Database - Minimal for dev
db_instance_class    = "db.t3.micro"
db_allocated_storage = 20

# Redis - Minimal for dev
redis_node_type = "cache.t3.micro"

# Services - Lower resources for dev
services = {
  frontend = {
    port              = 3000
    cpu               = 256
    memory            = 512
    desired_count     = 1
    health_check_path = "/api/health"
  }
  api-gateway = {
    port              = 8000
    cpu               = 256
    memory            = 512
    desired_count     = 1
    health_check_path = "/health"
  }
  llm-orchestrator = {
    port              = 8003
    cpu               = 512
    memory            = 1024
    desired_count     = 1
    health_check_path = "/health"
  }
  mcp-server = {
    port              = 8001
    cpu               = 256
    memory            = 512
    desired_count     = 1
    health_check_path = "/health"
  }
  airtable-gateway = {
    port              = 8002
    cpu               = 256
    memory            = 512
    desired_count     = 1
    health_check_path = "/health"
  }
  platform-services = {
    port              = 8007
    cpu               = 256
    memory            = 512
    desired_count     = 1
    health_check_path = "/health"
  }
  automation-services = {
    port              = 8006
    cpu               = 256
    memory            = 512
    desired_count     = 1
    health_check_path = "/health"
  }
}

# No SSL/domain for dev
certificate_arn = ""
domain_name     = ""

# Optional alerting
alert_email = "dev-team@yourcompany.com"

# Tags
tags = {
  Owner       = "dev-team"
  CostCenter  = "engineering"
  Purpose     = "development"
}