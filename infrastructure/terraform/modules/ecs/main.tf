# ECS Module - Enhanced with security, autoscaling, and service discovery
# Fargate cluster with comprehensive service management

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ECS Cluster with container insights
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_id
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-cluster"
  })
}

# Capacity providers for cost optimization
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = var.capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      base              = default_capacity_provider_strategy.value.base
      weight            = default_capacity_provider_strategy.value.weight
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
    }
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ecs-logs"
  })
}

resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "/ecs/${var.name_prefix}/exec"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-ecs-exec-logs"
  })
}

# Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.name_prefix}.local"
  description = "Service discovery namespace for ${var.name_prefix}"
  vpc         = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-service-discovery"
  })
}

resource "aws_service_discovery_service" "services" {
  for_each = var.services

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_grace_period_seconds = 60

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-discovery"
  })
}

# ECR Repositories
resource "aws_ecr_repository" "services" {
  for_each = var.services

  name                 = "${var.name_prefix}-${each.key}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = var.kms_key_id
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-ecr"
  })
}

# ECR Lifecycle Policies
resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_max_image_count} production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "prod", "release"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.ecr_max_dev_image_count} development images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev", "feature", "staging"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_max_dev_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Task Definitions
resource "aws_ecs_task_definition" "services" {
  for_each = var.services

  family                   = "${var.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn           = var.task_role_arn

  container_definitions = jsonencode([
    {
      name  = each.key
      image = "${aws_ecr_repository.services[each.key].repository_url}:${var.image_tag}"
      
      essential = true

      portMappings = [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ]

      # Environment variables
      environment = concat(
        [
          {
            name  = "ENVIRONMENT"
            value = var.environment
          },
          {
            name  = "SERVICE_NAME"
            value = each.key
          },
          {
            name  = "LOG_LEVEL"
            value = var.environment == "prod" ? "INFO" : "DEBUG"
          },
          {
            name  = "AWS_REGION"
            value = data.aws_region.current.name
          }
        ],
        lookup(var.service_environment_variables, each.key, [])
      )

      # Secrets from SSM Parameter Store and Secrets Manager
      secrets = concat(
        [
          {
            name      = "DATABASE_URL"
            valueFrom = "/${var.name_prefix}/${var.environment}/database-url"
          }
        ],
        var.redis_enabled ? [
          {
            name      = "REDIS_URL"
            valueFrom = "/${var.name_prefix}/${var.environment}/redis-url"
          }
        ] : [],
        lookup(var.service_secrets, each.key, [])
      )

      # Logging configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = each.key
        }
      }

      # Health check
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

      # Resource limits and reservations
      ulimits = [
        {
          name      = "nofile"
          softLimit = 65536
          hardLimit = 65536
        }
      ]

      # Security
      readonlyRootFilesystem = var.readonly_root_filesystem
      user                  = var.container_user

      # Stop timeout
      stopTimeout = 30
    }
  ])

  # Placement constraints (if any)
  dynamic "placement_constraints" {
    for_each = var.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression
    }
  }

  # Volume configuration (if needed)
  dynamic "volume" {
    for_each = var.efs_volumes
    content {
      name = volume.value.name

      efs_volume_configuration {
        file_system_id          = volume.value.file_system_id
        root_directory          = volume.value.root_directory
        transit_encryption      = "ENABLED"
        transit_encryption_port = 2049
        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = "ENABLED"
        }
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-task"
  })
}

# ECS Services
resource "aws_ecs_service" "services" {
  for_each = var.services

  name            = "${var.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = null # Using capacity provider strategy instead

  # Capacity provider strategy
  dynamic "capacity_provider_strategy" {
    for_each = var.service_capacity_provider_strategy
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight           = capacity_provider_strategy.value.weight
      base             = capacity_provider_strategy.value.base
    }
  }

  # Network configuration
  network_configuration {
    security_groups  = [var.ecs_security_group_id]
    subnets          = var.private_subnet_ids
    assign_public_ip = false
  }

  # Load balancer configuration
  dynamic "load_balancer" {
    for_each = var.target_group_arns != null ? [1] : []
    content {
      target_group_arn = var.target_group_arns[each.key]
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  # Service discovery
  service_registries {
    registry_arn = aws_service_discovery_service.services[each.key].arn
  }

  # Deployment configuration
  deployment_configuration {
    maximum_percent         = var.deployment_maximum_percent
    minimum_healthy_percent = var.deployment_minimum_healthy_percent
    
    deployment_circuit_breaker {
      enable   = var.enable_deployment_circuit_breaker
      rollback = var.enable_deployment_rollback
    }
  }

  # Blue-green deployment with CodeDeploy (if enabled)
  deployment_controller {
    type = var.deployment_controller_type
  }

  # Enable ECS Exec for debugging (non-prod environments)
  enable_execute_command = var.environment != "prod" && var.enable_execute_command

  # Propagate tags
  propagate_tags = "SERVICE"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-service"
  })

  depends_on = [
    aws_ecs_task_definition.services
  ]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "services" {
  for_each = var.enable_autoscaling ? var.services : {}

  max_capacity       = each.value.max_capacity
  min_capacity       = each.value.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-autoscaling"
  })
}

# CPU-based autoscaling policy
resource "aws_appautoscaling_policy" "cpu_scaling" {
  for_each = var.enable_autoscaling ? var.services : {}

  name               = "${var.name_prefix}-${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Memory-based autoscaling policy
resource "aws_appautoscaling_policy" "memory_scaling" {
  for_each = var.enable_autoscaling ? var.services : {}

  name               = "${var.name_prefix}-${each.key}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Custom metric scaling (ALB request count per target)
resource "aws_appautoscaling_policy" "request_count_scaling" {
  for_each = var.enable_autoscaling && var.enable_alb_request_scaling ? var.services : {}

  name               = "${var.name_prefix}-${each.key}-request-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label        = var.alb_target_group_labels[each.key]
    }

    target_value       = var.request_count_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# CloudWatch Alarms for service monitoring
resource "aws_cloudwatch_metric_alarm" "service_cpu_high" {
  for_each = var.services

  alarm_name          = "${var.name_prefix}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors ${each.key} CPU utilization"
  alarm_actions       = var.alarm_actions
  ok_actions         = var.alarm_actions

  dimensions = {
    ServiceName = aws_ecs_service.services[each.key].name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "service_memory_high" {
  for_each = var.services

  alarm_name          = "${var.name_prefix}-${each.key}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "This metric monitors ${each.key} memory utilization"
  alarm_actions       = var.alarm_actions
  ok_actions         = var.alarm_actions

  dimensions = {
    ServiceName = aws_ecs_service.services[each.key].name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-memory-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "service_task_count_low" {
  for_each = var.environment == "prod" ? var.services : {}

  alarm_name          = "${var.name_prefix}-${each.key}-task-count-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "This metric monitors ${each.key} running task count"
  alarm_actions       = var.alarm_actions
  ok_actions         = var.alarm_actions
  treat_missing_data  = "breaching"

  dimensions = {
    ServiceName = aws_ecs_service.services[each.key].name
    ClusterName = aws_ecs_cluster.main.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-${each.key}-task-count-alarm"
  })
}