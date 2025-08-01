# Enhanced Production-Ready Infrastructure
# Modular Terraform configuration for PyAirtable microservices

terraform {
  required_version = ">= 1.5"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # Backend configuration - will be provided via backend-config.hcl
  backend "s3" {
    # Configuration provided via backend-config.hcl file
  }
}

# Provider configuration with default tags
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project            = var.project_name
      Environment        = var.environment
      ManagedBy         = "terraform"
      Owner             = var.owner
      CostCenter        = var.cost_center
      Workspace         = terraform.workspace
      LastModified      = timestamp()
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values for computed configurations
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = {
    Project            = var.project_name
    Environment        = var.environment
    ManagedBy         = "terraform"
    Owner             = var.owner
    CostCenter        = var.cost_center
    Workspace         = terraform.workspace
  }

  # Service configuration with environment-specific overrides
  services = {
    for service_name, service_config in var.service_configs : service_name => merge(
      service_config,
      lookup(var.environment_specific_service_configs, service_name, {})
    )
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  name_prefix                = local.name_prefix
  environment               = var.environment
  vpc_cidr                 = var.vpc_cidr
  max_azs                  = var.max_azs
  enable_nat_gateway       = var.enable_nat_gateway
  single_nat_gateway       = var.single_nat_gateway
  enable_database_subnets  = var.enable_database_subnets
  enable_flow_logs         = var.enable_flow_logs
  flow_log_retention_days  = var.flow_log_retention_days
  enable_s3_endpoint       = var.enable_s3_endpoint
  enable_ecr_endpoints     = var.enable_ecr_endpoints
  common_tags              = local.common_tags
}

# Security Module
module "security" {
  source = "./modules/security"

  name_prefix           = local.name_prefix
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  s3_bucket_name       = var.s3_bucket_name
  allowed_cidr_blocks  = var.allowed_cidr_blocks
  allowed_countries    = var.allowed_countries
  blocked_countries    = var.blocked_countries
  waf_rate_limit       = var.waf_rate_limit
  enable_guardduty     = var.enable_guardduty
  enable_security_hub  = var.enable_security_hub
  enable_config        = var.enable_config
  config_s3_bucket_name = var.config_s3_bucket_name
  common_tags          = local.common_tags
}

# RDS Module
module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "./modules/rds"

  name_prefix                        = local.name_prefix
  environment                       = var.environment
  database_subnet_ids               = module.vpc.database_subnet_ids
  security_group_id                 = module.security.database_security_group_id
  kms_key_id                       = module.security.kms_key_arn
  database_name                    = var.database_name
  master_username                  = var.master_username
  instance_class                   = var.db_instance_class
  allocated_storage                = var.db_allocated_storage
  max_allocated_storage            = var.db_max_allocated_storage
  storage_type                     = var.db_storage_type
  multi_az                         = var.db_multi_az
  backup_retention_period          = var.db_backup_retention_period
  backup_window                    = var.db_backup_window
  maintenance_window               = var.db_maintenance_window
  skip_final_snapshot              = var.db_skip_final_snapshot
  deletion_protection              = var.environment == "prod" ? true : false
  monitoring_interval              = var.db_monitoring_interval
  performance_insights_enabled     = var.db_performance_insights_enabled
  performance_insights_retention_period = var.db_performance_insights_retention_period
  enabled_cloudwatch_logs_exports  = var.db_enabled_cloudwatch_logs_exports
  log_retention_days               = var.log_retention_days
  create_read_replica              = var.db_create_read_replica
  read_replica_instance_class      = var.db_read_replica_instance_class
  alarm_actions                    = [module.monitoring.sns_topic_arn]
  common_tags                      = local.common_tags
}

# ElastiCache Module
module "elasticache" {
  count  = var.enable_elasticache ? 1 : 0
  source = "./modules/elasticache"

  name_prefix         = local.name_prefix
  environment        = var.environment
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_id  = module.security.cache_security_group_id
  kms_key_id        = module.security.kms_key_arn
  node_type         = var.redis_node_type
  num_cache_nodes   = var.redis_num_cache_nodes
  engine_version    = var.redis_engine_version
  port              = var.redis_port
  parameter_group_name = var.redis_parameter_group_name
  auth_token_enabled = var.redis_auth_token_enabled
  transit_encryption_enabled = var.redis_transit_encryption_enabled
  at_rest_encryption_enabled = var.redis_at_rest_encryption_enabled
  snapshot_retention_limit = var.redis_snapshot_retention_limit
  snapshot_window = var.redis_snapshot_window
  maintenance_window = var.redis_maintenance_window
  automatic_failover_enabled = var.redis_automatic_failover_enabled
  alarm_actions = [module.monitoring.sns_topic_arn]
  common_tags = local.common_tags
}

# Application Load Balancer Module
module "alb" {
  source = "./modules/alb"

  name_prefix            = local.name_prefix
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  security_group_id     = module.security.alb_security_group_id
  certificate_arn       = var.certificate_arn
  domain_name           = var.domain_name
  waf_web_acl_arn       = module.security.waf_web_acl_arn
  services              = local.services
  enable_deletion_protection = var.environment == "prod" ? true : false
  enable_cross_zone_load_balancing = var.alb_enable_cross_zone_load_balancing
  idle_timeout          = var.alb_idle_timeout
  enable_http2          = var.alb_enable_http2
  alarm_actions         = [module.monitoring.sns_topic_arn]
  common_tags           = local.common_tags
}

# ECS Module
module "ecs" {
  source = "./modules/ecs"

  name_prefix                  = local.name_prefix
  environment                 = var.environment
  vpc_id                      = module.vpc.vpc_id
  private_subnet_ids          = module.vpc.private_subnet_ids
  ecs_security_group_id       = module.security.ecs_tasks_security_group_id
  task_execution_role_arn     = module.security.ecs_task_execution_role_arn
  task_role_arn              = module.security.ecs_task_role_arn
  kms_key_id                 = module.security.kms_key_arn
  services                   = local.services
  target_group_arns          = module.alb.target_group_arns
  capacity_providers         = var.ecs_capacity_providers
  default_capacity_provider_strategy = var.ecs_default_capacity_provider_strategy
  service_capacity_provider_strategy = var.ecs_service_capacity_provider_strategy
  enable_container_insights  = var.ecs_enable_container_insights
  enable_execute_command     = var.ecs_enable_execute_command
  log_retention_days         = var.log_retention_days
  image_tag                  = var.image_tag
  redis_enabled              = var.enable_elasticache
  service_environment_variables = var.service_environment_variables
  service_secrets            = var.service_secrets
  enable_autoscaling         = var.ecs_enable_autoscaling
  cpu_target_value          = var.ecs_cpu_target_value
  memory_target_value       = var.ecs_memory_target_value
  scale_in_cooldown         = var.ecs_scale_in_cooldown
  scale_out_cooldown        = var.ecs_scale_out_cooldown
  deployment_maximum_percent = var.ecs_deployment_maximum_percent
  deployment_minimum_healthy_percent = var.ecs_deployment_minimum_healthy_percent
  enable_deployment_circuit_breaker = var.ecs_enable_deployment_circuit_breaker
  enable_deployment_rollback = var.ecs_enable_deployment_rollback
  deployment_controller_type = var.ecs_deployment_controller_type
  readonly_root_filesystem   = var.ecs_readonly_root_filesystem
  container_user            = var.ecs_container_user
  cpu_alarm_threshold       = var.ecs_cpu_alarm_threshold
  memory_alarm_threshold    = var.ecs_memory_alarm_threshold
  alarm_actions             = [module.monitoring.sns_topic_arn]
  common_tags               = local.common_tags
}

# Monitoring and Alerting Module
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix              = local.name_prefix
  environment             = var.environment
  cluster_name            = module.ecs.cluster_name
  services                = keys(local.services)
  load_balancer_arn_suffix = module.alb.load_balancer_arn_suffix
  target_group_arn_suffixes = module.alb.target_group_arn_suffixes
  database_identifier     = var.enable_rds ? module.rds[0].db_instance_identifier : null
  redis_cluster_id        = var.enable_elasticache ? module.elasticache[0].cluster_id : null
  kms_key_id             = module.security.kms_key_arn
  log_retention_days     = var.log_retention_days
  alert_email            = var.alert_email
  slack_webhook_url      = var.slack_webhook_url
  enable_enhanced_monitoring = var.enable_enhanced_monitoring
  enable_custom_metrics  = var.enable_custom_metrics
  enable_application_insights = var.environment == "prod" && var.enable_application_insights
  common_tags            = local.common_tags
}

# Cost Management Module
module "cost_management" {
  count  = var.enable_cost_management ? 1 : 0
  source = "./modules/cost-management"

  name_prefix          = local.name_prefix
  environment         = var.environment
  monthly_budget_limit = var.monthly_budget_limit
  budget_alert_threshold_percent = var.budget_alert_threshold_percent
  alert_email         = var.alert_email
  enable_resource_scheduling = var.enable_resource_scheduling
  schedule_stop_time  = var.schedule_stop_time
  schedule_start_time = var.schedule_start_time
  scheduled_services  = var.scheduled_services
  enable_spot_instances = var.enable_spot_instances
  common_tags         = local.common_tags
}

# Backup and Disaster Recovery Module
module "backup" {
  count  = var.enable_backup ? 1 : 0
  source = "./modules/backup"

  name_prefix             = local.name_prefix
  environment            = var.environment
  kms_key_id            = module.security.kms_key_arn
  backup_vault_name     = "${local.name_prefix}-backup-vault"
  backup_plan_name      = "${local.name_prefix}-backup-plan"
  backup_retention_days = var.backup_retention_days
  backup_schedule       = var.backup_schedule
  backup_start_window   = var.backup_start_window
  backup_completion_window = var.backup_completion_window
  enable_cross_region_backup = var.enable_cross_region_backup
  cross_region_backup_destination = var.cross_region_backup_destination
  
  # Resources to backup
  rds_db_instance_arn = var.enable_rds ? module.rds[0].db_instance_arn : null
  efs_file_system_arns = var.efs_file_system_arns
  
  common_tags = local.common_tags
}

# S3 Bucket for Application Data
resource "aws_s3_bucket" "app_data" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-app-data-${random_id.bucket_suffix[0].hex}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-data"
  })
}

resource "random_id" "bucket_suffix" {
  count       = var.create_s3_bucket && var.s3_bucket_name == "" ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "app_data" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.app_data[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.app_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = module.security.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "app_data" {
  count  = var.create_s3_bucket ? 1 : 0
  bucket = aws_s3_bucket.app_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Route53 (if domain is provided)
resource "aws_route53_record" "app" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.load_balancer_dns_name
    zone_id                = module.alb.load_balancer_zone_id
    evaluate_target_health = true
  }
}