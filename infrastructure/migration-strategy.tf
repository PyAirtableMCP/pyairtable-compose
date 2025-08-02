# PyAirtable Migration Strategy - Infrastructure as Code
# Cost-optimized multi-environment setup with gradual migration support

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  backend "s3" {
    # Multi-workspace backend for environment isolation
    bucket         = "pyairtable-terraform-state"
    key            = "migration/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    
    # Workspace-specific state paths
    workspace_key_prefix = "environments"
  }
}

# Migration-specific variables
variable "migration_phase" {
  description = "Current migration phase (1-4)"
  type        = number
  default     = 1
  validation {
    condition     = var.migration_phase >= 1 && var.migration_phase <= 4
    error_message = "Migration phase must be between 1 and 4."
  }
}

variable "legacy_services_enabled" {
  description = "Keep legacy services running during migration"
  type        = bool
  default     = true
}

variable "blue_green_enabled" {
  description = "Enable blue-green deployment for production"
  type        = bool
  default     = false
}

# Cost optimization settings per environment
locals {
  environment_configs = {
    dev = {
      spot_percentage        = 80
      min_capacity          = 1
      max_capacity          = 3
      instance_types        = ["t3.micro", "t3.small"]
      enable_monitoring     = false
      backup_retention_days = 7
      auto_shutdown_hours   = "18:00-08:00"  # Shutdown overnight
    }
    staging = {
      spot_percentage        = 50
      min_capacity          = 2
      max_capacity          = 6
      instance_types        = ["t3.small", "t3.medium"]
      enable_monitoring     = true
      backup_retention_days = 14
      auto_shutdown_hours   = "none"
    }
    prod = {
      spot_percentage        = 0
      min_capacity          = 3
      max_capacity          = 15
      instance_types        = ["t3.medium", "t3.large"]
      enable_monitoring     = true
      backup_retention_days = 30
      auto_shutdown_hours   = "none"
    }
  }

  current_config = local.environment_configs[var.environment]
}

# Phase 1: Enhanced Container Registry with lifecycle management
resource "aws_ecr_repository" "migration_services" {
  for_each = var.migration_phase >= 1 ? toset([
    "legacy/api-gateway",
    "legacy/platform-services", 
    "legacy/automation-services",
    "microservices/auth-service",
    "microservices/user-service",
    "microservices/tenant-service",
    "microservices/workspace-service",
    "shared/base-go",
    "shared/base-python"
  ]) : toset([])

  name                 = "pyairtable/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name            = "pyairtable-${each.key}"
    MigrationPhase  = var.migration_phase
    Environment     = var.environment
  }
}

# Enhanced lifecycle policy for cost optimization
resource "aws_ecr_lifecycle_policy" "migration_repositories" {
  for_each   = aws_ecr_repository.migration_services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 development images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev-", "staging-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Delete untagged images after 1 day"
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

# Phase 2: Environment-specific EKS configuration
resource "aws_eks_node_group" "migration_nodes" {
  count           = var.migration_phase >= 2 ? 1 : 0
  cluster_name    = aws_eks_cluster.pyairtable.name
  node_group_name = "pyairtable-${var.environment}-migration"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private[*].id

  # Cost-optimized configuration
  capacity_type  = local.current_config.spot_percentage > 0 ? "SPOT" : "ON_DEMAND"
  instance_types = local.current_config.instance_types

  scaling_config {
    desired_size = local.current_config.min_capacity
    max_size     = local.current_config.max_capacity
    min_size     = local.current_config.min_capacity
  }

  # Taints for migration workloads
  taint {
    key    = "migration-phase"
    value  = tostring(var.migration_phase)
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name           = "pyairtable-${var.environment}-migration-nodes"
    MigrationPhase = var.migration_phase
    Environment    = var.environment
    CostCenter     = "migration"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}

# Phase 3: Secrets Management with External Secrets Operator
resource "helm_release" "external_secrets" {
  count      = var.migration_phase >= 3 ? 1 : 0
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "external-secrets-system"
  create_namespace = true

  values = [
    yamlencode({
      installCRDs = true
      
      # Cost optimization - reduce replicas for non-prod
      replicaCount = var.environment == "prod" ? 2 : 1
      
      resources = {
        limits = {
          cpu    = var.environment == "prod" ? "200m" : "100m"
          memory = var.environment == "prod" ? "256Mi" : "128Mi"
        }
        requests = {
          cpu    = var.environment == "prod" ? "100m" : "50m"
          memory = var.environment == "prod" ? "128Mi" : "64Mi"
        }
      }
    })
  ]

  depends_on = [aws_eks_cluster.pyairtable]
}

# AWS Secrets Manager for migration secrets
resource "aws_secretsmanager_secret" "migration_secrets" {
  count       = var.migration_phase >= 3 ? 1 : 0
  name        = "pyairtable/${var.environment}/migration-secrets"
  description = "Migration secrets for PyAirtable ${var.environment} environment"

  tags = {
    Environment    = var.environment
    MigrationPhase = var.migration_phase
    Purpose        = "migration"
  }
}

resource "aws_secretsmanager_secret_version" "migration_secrets" {
  count     = var.migration_phase >= 3 ? 1 : 0
  secret_id = aws_secretsmanager_secret.migration_secrets[0].id
  secret_string = jsonencode({
    postgres_password = random_password.postgres.result
    redis_password    = random_password.redis.result
    jwt_secret        = random_password.jwt_secret.result
    api_key          = random_password.api_key.result
    migration_token  = random_password.migration_token.result
  })
}

# Phase 4: Blue-Green Deployment Infrastructure
resource "aws_lb_target_group" "blue_green" {
  count    = var.migration_phase >= 4 && var.blue_green_enabled ? 2 : 0
  name     = "pyairtable-${var.environment}-${count.index == 0 ? "blue" : "green"}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    protocol            = "HTTP"
  }

  tags = {
    Name        = "pyairtable-${var.environment}-${count.index == 0 ? "blue" : "green"}"
    Environment = var.environment
    BlueGreen   = count.index == 0 ? "blue" : "green"
  }
}

# Cost monitoring and alerting
resource "aws_cloudwatch_metric_alarm" "cost_alarm" {
  count               = local.current_config.enable_monitoring ? 1 : 0
  alarm_name          = "pyairtable-${var.environment}-high-cost"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"  # 24 hours
  statistic           = "Maximum"
  
  # Environment-specific cost thresholds
  threshold = var.environment == "prod" ? 500 : (var.environment == "staging" ? 200 : 100)
  
  alarm_description = "This metric monitors estimated charges for ${var.environment} environment"
  alarm_actions     = var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    Currency = "USD"
  }

  tags = {
    Environment = var.environment
    Purpose     = "cost-monitoring"
  }
}

# Auto-shutdown for development environment (cost optimization)
resource "aws_lambda_function" "auto_shutdown" {
  count         = var.environment == "dev" && local.current_config.auto_shutdown_hours != "none" ? 1 : 0
  filename      = "auto-shutdown.zip"
  function_name = "pyairtable-${var.environment}-auto-shutdown"
  role          = aws_iam_role.auto_shutdown_lambda[0].arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300

  environment {
    variables = {
      CLUSTER_NAME = aws_eks_cluster.pyairtable.name
      ENVIRONMENT  = var.environment
      SHUTDOWN_HOURS = local.current_config.auto_shutdown_hours
    }
  }

  tags = {
    Environment = var.environment
    Purpose     = "cost-optimization"
  }
}

# CloudWatch Event to trigger auto-shutdown
resource "aws_cloudwatch_event_rule" "auto_shutdown_schedule" {
  count               = var.environment == "dev" && local.current_config.auto_shutdown_hours != "none" ? 1 : 0
  name                = "pyairtable-${var.environment}-auto-shutdown"
  description         = "Trigger auto-shutdown for development environment"
  schedule_expression = "cron(0 18 * * MON-FRI *)"  # 6 PM weekdays

  tags = {
    Environment = var.environment
    Purpose     = "cost-optimization"
  }
}

resource "aws_cloudwatch_event_target" "auto_shutdown_target" {
  count     = var.environment == "dev" && local.current_config.auto_shutdown_hours != "none" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.auto_shutdown_schedule[0].name
  target_id = "AutoShutdownTarget"
  arn       = aws_lambda_function.auto_shutdown[0].arn
}

# Outputs for migration tracking
output "migration_status" {
  description = "Current migration status and next steps"
  value = {
    current_phase = var.migration_phase
    next_steps = var.migration_phase < 4 ? "Proceed to phase ${var.migration_phase + 1}" : "Migration complete"
    estimated_monthly_cost = var.environment == "dev" ? "$98" : (var.environment == "staging" ? "$150" : "$395")
    cost_optimization_active = {
      spot_instances = local.current_config.spot_percentage > 0
      auto_shutdown = var.environment == "dev"
      right_sizing = true
    }
  }
}

output "registry_urls" {
  description = "Container registry URLs for migration"
  value = {
    for service, repo in aws_ecr_repository.migration_services : 
    service => repo.repository_url
  }
}

output "migration_recommendations" {
  description = "Next steps and recommendations"
  value = {
    phase_1 = "✅ Registry consolidation and lifecycle policies"
    phase_2 = var.migration_phase >= 2 ? "✅ Multi-environment strategy" : "🔄 Configure environment-specific resources"
    phase_3 = var.migration_phase >= 3 ? "✅ Secrets management with External Secrets" : "⏳ Implement secure secrets management"
    phase_4 = var.migration_phase >= 4 ? "✅ Blue-green deployment ready" : "⏳ Setup blue-green deployment"
    
    immediate_actions = [
      "Migrate images to organized registry structure",
      "Implement semantic versioning (v1.x.x legacy, v2.x.x microservices)",
      "Setup cost monitoring alerts",
      "Configure auto-scaling policies"
    ]
    
    cost_savings = {
      spot_instances = "${local.current_config.spot_percentage}% cost reduction on compute"
      auto_shutdown = var.environment == "dev" ? "~60% savings on development environment" : "N/A"
      right_sizing = "Start with minimal resources and scale based on actual usage"
    }
  }
}