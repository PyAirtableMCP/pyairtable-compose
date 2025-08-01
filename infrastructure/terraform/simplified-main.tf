# PyAirtable Infrastructure - Simplified but Maintainable
# Modular approach designed for a 2-person team

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

  # Simple S3 backend - create bucket manually first
  backend "s3" {}  # Will be configured via terraform init -backend-config
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Local values
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Environment-specific overrides
  environment_config = {
    dev = {
      multi_az              = false
      backup_retention      = 1
      enable_monitoring     = false
      instance_count        = 1
      use_spot             = true
    }
    prod = {
      multi_az              = true
      backup_retention      = 7
      enable_monitoring     = true
      instance_count        = 2
      use_spot             = false
    }
  }
  
  config = local.environment_config[var.environment]
}

# VPC Module - Keep the good structure we built
module "vpc" {
  source = "./modules/vpc"

  name_prefix                = local.name_prefix
  environment               = var.environment
  vpc_cidr                 = var.vpc_cidr
  max_azs                  = 2  # Keep it simple with 2 AZs
  enable_nat_gateway       = true
  single_nat_gateway       = var.environment == "dev" ? true : false  # Save cost in dev
  enable_database_subnets  = true
  enable_flow_logs         = var.environment == "prod" ? true : false  # Only in prod
  enable_s3_endpoint       = true
  enable_ecr_endpoints     = true
  common_tags              = var.tags
}

# Security Module - Simplified but secure
module "security" {
  source = "./modules/security"

  name_prefix           = local.name_prefix
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  allowed_cidr_blocks  = ["0.0.0.0/0"]  # Rely on ALB and security groups
  waf_rate_limit       = 2000
  enable_guardduty     = var.environment == "prod" ? true : false
  enable_security_hub  = false  # Keep it simple
  enable_config        = false  # Keep it simple
  common_tags          = var.tags
}

# RDS Module - Essential database setup
module "rds" {
  source = "./modules/rds"

  name_prefix                        = local.name_prefix
  environment                       = var.environment
  database_subnet_ids               = module.vpc.database_subnet_ids
  security_group_id                 = module.security.database_security_group_id
  kms_key_id                       = module.security.kms_key_arn
  database_name                    = "pyairtable"
  master_username                  = "app_user"
  instance_class                   = var.db_instance_class
  allocated_storage                = var.db_allocated_storage
  multi_az                         = local.config.multi_az
  backup_retention_period          = local.config.backup_retention
  skip_final_snapshot              = var.environment != "prod"
  deletion_protection              = var.environment == "prod"
  monitoring_interval              = local.config.enable_monitoring ? 60 : 0
  performance_insights_enabled     = local.config.enable_monitoring
  create_read_replica              = var.environment == "prod"
  alarm_actions                    = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []
  common_tags                      = var.tags
}

# ElastiCache - Simple Redis setup
resource "aws_elasticache_subnet_group" "main" {
  name       = local.name_prefix
  subnet_ids = module.vpc.private_subnet_ids
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = local.name_prefix
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [module.security.cache_security_group_id]

  tags = var.tags
}

# Store Redis connection info
resource "aws_ssm_parameter" "redis_url" {
  name  = "/${var.project_name}/${var.environment}/redis-url"
  type  = "SecureString"
  value = "redis://${aws_elasticache_cluster.main.cluster_address}:${aws_elasticache_cluster.main.port}"
  key_id = module.security.kms_key_id

  tags = var.tags
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [module.security.alb_security_group_id]
  subnets            = module.vpc.public_subnet_ids

  enable_deletion_protection = var.environment == "prod"

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = module.security.waf_web_acl_arn
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = var.certificate_arn != "" ? "443" : "80"
  protocol          = var.certificate_arn != "" ? "HTTPS" : "HTTP"
  certificate_arn   = var.certificate_arn != "" ? var.certificate_arn : null

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "PyAirtable API"
      status_code  = "200"
    }
  }
}

# Redirect HTTP to HTTPS if we have SSL
resource "aws_lb_listener" "redirect" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Target Groups and Listener Rules
resource "aws_lb_target_group" "services" {
  for_each = var.services

  name     = "${local.name_prefix}-${each.key}"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "services" {
  for_each = var.services

  listener_arn = aws_lb_listener.main.arn
  priority     = 100 + index(keys(var.services), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services[each.key].arn
  }

  condition {
    path_pattern {
      values = each.key == "frontend" ? ["/*"] : ["/${each.key}/*", "/${each.key}"]
    }
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = local.config.enable_monitoring ? "enabled" : "disabled"
  }

  tags = var.tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.environment == "prod" ? 30 : 7
  kms_key_id        = module.security.kms_key_arn

  tags = var.tags
}

# ECR Repositories
resource "aws_ecr_repository" "services" {
  for_each = var.services

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = module.security.kms_key_arn
  }

  tags = var.tags
}

# ECR Lifecycle Policy (keep it simple)
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "services" {
  for_each = var.services

  family                   = "${local.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = module.security.ecs_task_execution_role_arn
  task_role_arn           = module.security.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name  = each.key
      image = "${aws_ecr_repository.services[each.key].repository_url}:latest"
      
      essential = true

      portMappings = [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "SERVICE_NAME"
          value = each.key
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = module.rds.database_url_parameter
        },
        {
          name      = "REDIS_URL"
          valueFrom = aws_ssm_parameter.redis_url.name
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${each.value.port}${each.value.health_check_path} || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = var.tags
}

# ECS Services
resource "aws_ecs_service" "services" {
  for_each = var.services

  name            = "${local.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = each.value.desired_count

  # Use Spot for dev, Fargate for prod
  capacity_provider_strategy {
    capacity_provider = local.config.use_spot ? "FARGATE_SPOT" : "FARGATE"
    weight           = 100
  }

  network_configuration {
    security_groups  = [module.security.ecs_tasks_security_group_id]
    subnets          = module.vpc.private_subnet_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.services[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 50
    
    deployment_circuit_breaker {
      enable   = true
      rollback = true
    }
  }

  tags = var.tags

  depends_on = [aws_lb_listener.main]
}

# Simple alerting (optional)
resource "aws_sns_topic" "alerts" {
  count = var.alert_email != "" ? 1 : 0
  name  = "${local.name_prefix}-alerts"
  
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Basic CloudWatch alarms for production
resource "aws_cloudwatch_metric_alarm" "alb_error_rate" {
  count = var.environment == "prod" && var.alert_email != "" ? 1 : 0

  alarm_name          = "${local.name_prefix}-alb-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "ALB 5XX error count is too high"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = var.tags
}

# Route53 record (if domain provided)
data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "main" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}