# Production Environment Configuration
# Enhanced production-ready settings with security hardening

# Basic Configuration
project_name = "pyairtable"
environment  = "prod"
aws_region   = "us-east-1"
owner        = "platform-team"
cost_center  = "engineering"

# Network Configuration - Separate CIDR for prod
vpc_cidr                = "10.1.0.0/16"
max_azs                 = 3
enable_nat_gateway      = true
single_nat_gateway      = false  # Multiple NAT gateways for HA
enable_database_subnets = true
enable_flow_logs        = true
flow_log_retention_days = 90
enable_s3_endpoint      = true
enable_ecr_endpoints    = true

# Security Configuration
allowed_cidr_blocks = ["0.0.0.0/0"]  # Restricted by WAF and security groups
allowed_countries   = ["US", "CA", "GB", "DE", "FR", "JP", "AU"]
blocked_countries   = []  # Can add countries to block if needed
waf_rate_limit      = 2000
enable_guardduty    = true
enable_security_hub = true
enable_config       = true

# Domain and SSL
domain_name     = "api.yourdomain.com"
certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT_ID:certificate/CERTIFICATE_ID"
route53_zone_id = "Z1D633PJN98FT9"

# Database Configuration - Production hardened
enable_rds                    = true
database_name                 = "pyairtable_prod"
master_username              = "app_admin"
db_instance_class            = "db.r6g.large"
db_allocated_storage         = 200
db_max_allocated_storage     = 1000
db_storage_type              = "gp3"
db_multi_az                  = true
db_backup_retention_period   = 30
db_backup_window            = "03:00-04:00"
db_maintenance_window       = "sun:04:00-sun:05:00"
db_skip_final_snapshot      = false
db_monitoring_interval      = 60
db_performance_insights_enabled = true
db_performance_insights_retention_period = 731
db_enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
db_create_read_replica      = true
db_read_replica_instance_class = "db.r6g.large"

# Redis Configuration - Production hardened
enable_elasticache             = true
redis_node_type               = "cache.r6g.large"
redis_num_cache_nodes         = 3
redis_engine_version          = "7.0"
redis_port                    = 6379
redis_auth_token_enabled      = true
redis_transit_encryption_enabled = true
redis_at_rest_encryption_enabled = true
redis_snapshot_retention_limit = 7
redis_snapshot_window         = "05:00-06:00"
redis_maintenance_window      = "sun:06:00-sun:07:00"
redis_automatic_failover_enabled = true

# ECS Configuration - Production optimized
ecs_capacity_providers = ["FARGATE"]
ecs_default_capacity_provider_strategy = [
  {
    capacity_provider = "FARGATE"
    weight           = 100
    base             = 2
  }
]
ecs_service_capacity_provider_strategy = [
  {
    capacity_provider = "FARGATE"
    weight           = 100
    base             = 1
  }
]
ecs_enable_container_insights = true
ecs_enable_execute_command    = false  # Disabled in prod for security
ecs_enable_autoscaling       = true
ecs_cpu_target_value         = 60.0
ecs_memory_target_value      = 70.0
ecs_scale_in_cooldown        = 300
ecs_scale_out_cooldown       = 300
ecs_deployment_maximum_percent = 200
ecs_deployment_minimum_healthy_percent = 50
ecs_enable_deployment_circuit_breaker = true
ecs_enable_deployment_rollback = true
ecs_deployment_controller_type = "ECS"
ecs_readonly_root_filesystem  = true
ecs_container_user           = "1001:1001"  # Non-root user
ecs_cpu_alarm_threshold      = 80
ecs_memory_alarm_threshold   = 85

# Service Configuration - Production scaling
service_configs = {
  frontend = {
    port              = 3000
    cpu               = 1024
    memory            = 2048
    desired_count     = 3
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/api/health"
    priority          = 100
  }
  api-gateway = {
    port              = 8000
    cpu               = 2048
    memory            = 4096
    desired_count     = 5
    min_capacity      = 3
    max_capacity      = 20
    health_check_path = "/health"
    priority          = 200
  }
  llm-orchestrator = {
    port              = 8003
    cpu               = 4096
    memory            = 8192
    desired_count     = 3
    min_capacity      = 2
    max_capacity      = 15
    health_check_path = "/health"
    priority          = 300
  }
  mcp-server = {
    port              = 8001
    cpu               = 1024
    memory            = 2048
    desired_count     = 3
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    priority          = 400
  }
  airtable-gateway = {
    port              = 8002
    cpu               = 1024
    memory            = 2048
    desired_count     = 3
    min_capacity      = 2
    max_capacity      = 10
    health_check_path = "/health"
    priority          = 500
  }
  platform-services = {
    port              = 8007
    cpu               = 2048
    memory            = 4096
    desired_count     = 3
    min_capacity      = 2
    max_capacity      = 12
    health_check_path = "/health"
    priority          = 600
  }
  automation-services = {
    port              = 8006
    cpu               = 2048
    memory            = 4096
    desired_count     = 2
    min_capacity      = 1
    max_capacity      = 8
    health_check_path = "/health"
    priority          = 700
  }
}

# Load Balancer Configuration
alb_enable_cross_zone_load_balancing = true
alb_idle_timeout                    = 60
alb_enable_http2                    = true

# Monitoring and Alerting
log_retention_days              = 90
alert_email                    = "alerts@yourdomain.com"
slack_webhook_url              = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
enable_enhanced_monitoring     = true
enable_custom_metrics          = true
enable_application_insights    = true

# Cost Management
enable_cost_management         = true
monthly_budget_limit          = 5000
budget_alert_threshold_percent = [50, 80, 100]
enable_resource_scheduling    = false  # Don't schedule prod resources
enable_spot_instances         = false  # Use only on-demand in prod

# Backup and Disaster Recovery
enable_backup                     = true
backup_retention_days            = 90
backup_schedule                  = "cron(0 2 * * ? *)"  # Daily at 2 AM
backup_start_window              = "02:00"
backup_completion_window         = "04:00"
enable_cross_region_backup       = true
cross_region_backup_destination  = "us-west-2"

# S3 Configuration
create_s3_bucket = true
s3_bucket_name   = "pyairtable-prod-app-data"

# Service Environment Variables (non-sensitive)
service_environment_variables = {
  api-gateway = [
    {
      name  = "MAX_WORKERS"
      value = "8"
    },
    {
      name  = "RATE_LIMIT_REQUESTS"
      value = "1000"
    },
    {
      name  = "RATE_LIMIT_WINDOW"
      value = "3600"
    }
  ]
  llm-orchestrator = [
    {
      name  = "MAX_CONCURRENT_REQUESTS"
      value = "50"
    },
    {
      name  = "MODEL_TIMEOUT"
      value = "300"
    }
  ]
  frontend = [
    {
      name  = "NODE_ENV"
      value = "production"
    },
    {
      name  = "NEXT_TELEMETRY_DISABLED"
      value = "1"
    }
  ]
}

# Service Secrets (references to SSM parameters)
service_secrets = {
  api-gateway = [
    {
      name      = "OPENAI_API_KEY"
      valueFrom = "/pyairtable/prod/openai-api-key"
    },
    {
      name      = "JWT_SECRET"
      valueFrom = "/pyairtable/prod/jwt-secret"
    }
  ]
  airtable-gateway = [
    {
      name      = "AIRTABLE_API_KEY"
      valueFrom = "/pyairtable/prod/airtable-api-key"
    }
  ]
  llm-orchestrator = [
    {
      name      = "ANTHROPIC_API_KEY"
      valueFrom = "/pyairtable/prod/anthropic-api-key"
    }
  ]
}

# Image tag - typically set via CI/CD
image_tag = "latest"