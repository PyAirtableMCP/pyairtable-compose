# ECS Services Configuration
# Individual service definitions for each microservice

# Target Groups for ALB
resource "aws_lb_target_group" "services" {
  for_each = var.service_configs

  name     = "${var.project_name}-${var.environment}-${each.key}-tg"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  # Default action - return 404
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Service not found"
      status_code  = "404"
    }
  }
}

# HTTPS Listener (if certificate is provided)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn

  # Default action - return 404
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Service not found"
      status_code  = "404"
    }
  }
}

# ALB Listener Rules
resource "aws_lb_listener_rule" "services" {
  for_each = var.service_configs

  listener_arn = aws_lb_listener.main.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services[each.key].arn
  }

  condition {
    path_pattern {
      values = each.key == "frontend" ? ["/*"] : ["/${each.key}/*", "/${each.key}"]
    }
  }

  depends_on = [aws_lb_target_group.services]
}

# HTTPS Listener Rules (if certificate is provided)
resource "aws_lb_listener_rule" "services_https" {
  for_each = var.certificate_arn != "" ? var.service_configs : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services[each.key].arn
  }

  condition {
    path_pattern {
      values = each.key == "frontend" ? ["/*"] : ["/${each.key}/*", "/${each.key}"]
    }
  }

  depends_on = [aws_lb_target_group.services]
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "services" {
  for_each = var.service_configs

  family                   = "${var.project_name}-${each.key}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = each.key
      image = "${aws_ecr_repository.services[each.key].repository_url}:latest"
      
      portMappings = [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ]

      # Environment variables (customize per service)
      environment = concat(
        [
          {
            name  = "ENVIRONMENT"
            value = var.environment
          },
          {
            name  = "LOG_LEVEL"
            value = var.environment == "prod" ? "INFO" : "DEBUG"
          }
        ],
        # Service-specific environment variables
        each.key == "api-gateway" ? [
          {
            name  = "AIRTABLE_GATEWAY_URL"
            value = "http://${aws_lb.main.dns_name}/airtable-gateway"
          },
          {
            name  = "MCP_SERVER_URL"
            value = "http://${aws_lb.main.dns_name}/mcp-server"
          },
          {
            name  = "LLM_ORCHESTRATOR_URL"
            value = "http://${aws_lb.main.dns_name}/llm-orchestrator"
          },
          {
            name  = "PLATFORM_SERVICES_URL"
            value = "http://${aws_lb.main.dns_name}/platform-services"
          },
          {
            name  = "AUTOMATION_SERVICES_URL"
            value = "http://${aws_lb.main.dns_name}/automation-services"
          }
        ] : each.key == "frontend" ? [
          {
            name  = "NEXT_PUBLIC_API_URL"
            value = "http://${aws_lb.main.dns_name}"
          },
          {
            name  = "NEXT_PUBLIC_API_GATEWAY_URL"
            value = "http://${aws_lb.main.dns_name}/api-gateway"
          }
        ] : []
      )

      # Secrets (stored in AWS Systems Manager Parameter Store)
      secrets = [
        {
          name      = "API_KEY"
          valueFrom = "/pyairtable/${var.environment}/api-key"
        },
        {
          name      = "DATABASE_URL"
          valueFrom = "/pyairtable/${var.environment}/database-url"
        },
        {
          name      = "REDIS_URL"
          valueFrom = "/pyairtable/${var.environment}/redis-url"
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
          each.key == "frontend" ? 
            "curl -f http://localhost:${each.value.port}/api/health || exit 1" :
            "curl -f http://localhost:${each.value.port}/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}"
  }
}

# ECS Services
resource "aws_ecs_service" "services" {
  for_each = var.service_configs

  name            = "${var.project_name}-${each.key}-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = var.environment_configs[var.environment].min_capacity

  capacity_provider_strategy {
    capacity_provider = var.environment == "prod" ? "FARGATE" : "FARGATE_SPOT"
    weight            = var.environment == "prod" ? 100 : 50
    base              = var.environment == "prod" ? 1 : 0
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = var.environment == "prod" ? 0 : 50
    base              = var.environment == "prod" ? 0 : 1
  }

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = aws_subnet.private[*].id
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

  # Blue-green deployment with CodeDeploy
  deployment_controller {
    type = "ECS"
  }

  # Enable service discovery
  service_registries {
    registry_arn = aws_service_discovery_service.services[each.key].arn
  }

  enable_execute_command = var.environment != "prod"

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}"
  }

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role_policy_attachment.ecs_task_execution_role,
    aws_iam_role_policy_attachment.ecs_task_policy
  ]
}

# Service Discovery
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project_name}-${var.environment}.local"
  description = "Service discovery namespace for ${var.project_name}"
  vpc         = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-namespace"
  }
}

resource "aws_service_discovery_service" "services" {
  for_each = var.service_configs

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

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}-discovery"
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "services" {
  for_each = var.environment_configs[var.environment].enable_autoscaling ? var.service_configs : {}

  max_capacity       = var.environment_configs[var.environment].max_capacity
  min_capacity       = var.environment_configs[var.environment].min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}-autoscaling"
  }
}

resource "aws_appautoscaling_policy" "cpu_scaling" {
  for_each = var.environment_configs[var.environment].enable_autoscaling ? var.service_configs : {}

  name               = "${var.project_name}-${each.key}-${var.environment}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

resource "aws_appautoscaling_policy" "memory_scaling" {
  for_each = var.environment_configs[var.environment].enable_autoscaling ? var.service_configs : {}

  name               = "${var.project_name}-${each.key}-${var.environment}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}