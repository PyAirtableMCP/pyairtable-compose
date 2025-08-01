# Development Environment Configuration
# Cost-optimized settings for development and testing

# Basic Configuration
project_name = "pyairtable"
environment  = "dev"
aws_region   = "us-east-1"
owner        = "dev-team"
cost_center  = "engineering"

# Network Configuration - Smaller CIDR for dev
vpc_cidr                = "10.0.0.0/16"
max_azs                 = 2  # Fewer AZs for cost savings
enable_nat_gateway      = true
single_nat_gateway      = true  # Single NAT gateway for cost savings
enable_database_subnets = true
enable_flow_logs        = false  # Disabled for cost savings
enable_s3_endpoint      = true
enable_ecr_endpoints    = true

# Security Configuration - Relaxed for dev
allowed_cidr_blocks = ["0.0.0.0/0"]
allowed_countries   = ["US", "CA", "GB", "DE", "FR", "JP", "AU"]
waf_rate_limit      = 5000  # Higher limit for testing
enable_guardduty    = false  # Disabled for cost savings
enable_security_hub = false  # Disabled for cost savings
enable_config       = false  # Disabled for cost savings

# Domain and SSL - Not configured for dev
domain_name     = ""
certificate_arn = ""
route53_zone_id = ""

# Database Configuration - Cost optimized
enable_rds                    = true
database_name                 = "pyairtable_dev"
master_username              = "app_user"
db_instance_class            = "db.t3.micro"
db_allocated_storage         = 20
db_max_allocated_storage     = 100
db_storage_type              = "gp3"
db_multi_az                  = false  # Single AZ for cost savings
db_backup_retention_period   = 1
db_backup_window            = "03:00-04:00"
db_maintenance_window       = "sun:04:00-sun:05:00"
db_skip_final_snapshot      = true
db_monitoring_interval      = 0  # Disabled for cost savings
db_performance_insights_enabled = false  # Disabled for cost savings
db_enabled_cloudwatch_logs_exports = ["postgresql"]
db_create_read_replica      = false  # No read replica in dev

# Redis Configuration - Minimal for dev
enable_elasticache             = true
redis_node_type               = "cache.t3.micro"
redis_num_cache_nodes         = 1
redis_engine_version          = "7.0"
redis_port                    = 6379
redis_auth_token_enabled      = false  # Simplified for dev
redis_transit_encryption_enabled = false  # Simplified for dev
redis_at_rest_encryption_enabled = true
redis_snapshot_retention_limit = 1
redis_snapshot_window         = "05:00-06:00"
redis_maintenance_window      = "sun:06:00-sun:07:00"
redis_automatic_failover_enabled = false

# ECS Configuration - Cost optimized with Spot instances
ecs_capacity_providers = ["FARGATE", "FARGATE_SPOT"]
ecs_default_capacity_provider_strategy = [
  {
    capacity_provider = "FARGATE_SPOT"
    weight           = 80
    base             = 0
  },
  {
    capacity_provider = "FARGATE"
    weight           = 20
    base             = 1
  }
]
ecs_service_capacity_provider_strategy = [
  {
    capacity_provider = "FARGATE_SPOT"
    weight           = 100
    base             = 0
  }
]
ecs_enable_container_insights = false  # Disabled for cost savings
ecs_enable_execute_command    = true   # Enabled for debugging
ecs_enable_autoscaling       = false   # Disabled in dev
ecs_deployment_maximum_percent = 200
ecs_deployment_minimum_healthy_percent = 0  # Allow stopping all tasks
ecs_enable_deployment_circuit_breaker = true
ecs_enable_deployment_rollback = false
ecs_deployment_controller_type = "ECS"
ecs_readonly_root_filesystem  = false  # Disabled for easier development
ecs_container_user           = "root"   # Root user for easier development
ecs_cpu_alarm_threshold      = 90
ecs_memory_alarm_threshold   = 90

# Service Configuration - Minimal resources for dev
service_configs = {
  frontend = {
    port              = 3000
    cpu               = 256
    memory            = 512
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/api/health"
    priority          = 100
  }
  api-gateway = {
    port              = 8000
    cpu               = 512
    memory            = 1024
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 3
    health_check_path = "/health"
    priority          = 200
  }
  llm-orchestrator = {
    port              = 8003
    cpu               = 1024
    memory            = 2048
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    priority          = 300
  }
  mcp-server = {
    port              = 8001
    cpu               = 256
    memory            = 512
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    priority          = 400
  }
  airtable-gateway = {
    port              = 8002
    cpu               = 256
    memory            = 512
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    priority          = 500
  }
  platform-services = {
    port              = 8007
    cpu               = 512
    memory            = 1024
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    priority          = 600
  }
  automation-services = {
    port              = 8006
    cpu               = 512
    memory            = 1024
    desired_count     = 1
    min_capacity      = 1
    max_capacity      = 2
    health_check_path = "/health"
    priority          = 700
  }
}

# Load Balancer Configuration
alb_enable_cross_zone_load_balancing = false  # Cost savings
alb_idle_timeout                    = 60
alb_enable_http2                    = true

# Monitoring and Alerting - Minimal for dev
log_retention_days              = 7   # Short retention for cost savings
alert_email                    = "dev-alerts@yourdomain.com"
slack_webhook_url              = ""   # Optional for dev
enable_enhanced_monitoring     = false
enable_custom_metrics          = false
enable_application_insights    = false

# Cost Management
enable_cost_management         = true
monthly_budget_limit          = 200   # Lower budget for dev
budget_alert_threshold_percent = [80, 100]
enable_resource_scheduling    = true  # Schedule resources to save costs
schedule_stop_time            = "18:00"  # Stop at 6 PM
schedule_start_time           = "08:00"  # Start at 8 AM
scheduled_services            = ["frontend", "api-gateway"]  # Only schedule non-critical services
enable_spot_instances         = true   # Use Spot instances for savings

# Backup and Disaster Recovery - Minimal
enable_backup                     = false  # Disabled for dev
backup_retention_days            = 7
enable_cross_region_backup       = false

# S3 Configuration
create_s3_bucket = true
s3_bucket_name   = ""  # Auto-generated name

# Service Environment Variables (non-sensitive)
service_environment_variables = {
  api-gateway = [
    {
      name  = "MAX_WORKERS"
      value = "2"
    },
    {
      name  = "RATE_LIMIT_REQUESTS"
      value = "10000"
    }
  ]
  llm-orchestrator = [
    {
      name  = "MAX_CONCURRENT_REQUESTS"
      value = "10"
    }
  ]
  frontend = [
    {
      name  = "NODE_ENV"
      value = "development"
    }
  ]
}

# Service Secrets (references to SSM parameters)
service_secrets = {
  api-gateway = [
    {
      name      = "OPENAI_API_KEY"
      valueFrom = "/pyairtable/dev/openai-api-key"
    },
    {
      name      = "JWT_SECRET"
      valueFrom = "/pyairtable/dev/jwt-secret"
    }
  ]
  airtable-gateway = [
    {
      name      = "AIRTABLE_API_KEY"
      valueFrom = "/pyairtable/dev/airtable-api-key"
    }
  ]
}

# Image tag - typically set via CI/CD
image_tag = "dev"