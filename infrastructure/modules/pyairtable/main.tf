# Enhanced PyAirtable Infrastructure Module
# Multi-environment support with cost optimization and security

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Local variables for environment-specific configurations
locals {
  # Environment-specific settings
  environment_config = {
    development = {
      instance_types          = ["t3.medium", "t3.large"]
      min_size               = 1
      max_size               = 5
      desired_capacity       = 2
      spot_percentage        = 80
      enable_detailed_monitoring = false
      backup_retention_days  = 7
      log_retention_days     = 30
      enable_deletion_protection = false
      db_instance_class      = "db.t3.medium"
      redis_node_type        = "cache.t3.micro"
      enable_multi_az        = false
    }
    staging = {
      instance_types          = ["t3.large", "m5.large"]
      min_size               = 2
      max_size               = 10
      desired_capacity       = 3
      spot_percentage        = 60
      enable_detailed_monitoring = true
      backup_retention_days  = 14
      log_retention_days     = 60
      enable_deletion_protection = false
      db_instance_class      = "db.r6g.large"
      redis_node_type        = "cache.r6g.large"
      enable_multi_az        = true
    }
    production = {
      instance_types          = ["m5.large", "c5.large", "r5.large"]
      min_size               = 3
      max_size               = 20
      desired_capacity       = 5
      spot_percentage        = 20
      enable_detailed_monitoring = true
      backup_retention_days  = 30
      log_retention_days     = 365
      enable_deletion_protection = true
      db_instance_class      = "db.r6g.2xlarge"
      redis_node_type        = "cache.r6g.xlarge"
      enable_multi_az        = true
    }
  }

  # Get configuration for current environment
  config = local.environment_config[var.environment]

  # Common tags for all resources
  common_tags = merge(var.additional_tags, {
    Project         = var.project_name
    Environment     = var.environment
    ManagedBy       = "Terraform"
    Region          = var.aws_region
    CostCenter      = "pyairtable-${var.environment}"
    Owner           = "platform-team"
    
    # Cost optimization tags
    AutoShutdown    = var.environment == "development" ? "enabled" : "disabled"
    SpotEligible    = local.config.spot_percentage > 0 ? "true" : "false"
    BackupRequired  = var.environment == "production" ? "true" : "false"
    MonitoringLevel = local.config.enable_detailed_monitoring ? "detailed" : "basic"
  })

  # Service configurations
  service_configs = {
    api_gateway = {
      cpu_request = var.environment == "production" ? "200m" : "100m"
      cpu_limit   = var.environment == "production" ? "1000m" : "500m"
      memory_request = var.environment == "production" ? "256Mi" : "128Mi"
      memory_limit   = var.environment == "production" ? "1Gi" : "512Mi"
      replicas    = var.environment == "production" ? 3 : 2
      priority_class = "pyairtable-critical"
    }
    auth_service = {
      cpu_request = "100m"
      cpu_limit   = "500m"
      memory_request = "128Mi"
      memory_limit   = "512Mi"
      replicas    = var.environment == "production" ? 2 : 1
      priority_class = "pyairtable-critical"
    }
    platform_services = {
      cpu_request = var.environment == "production" ? "200m" : "100m"
      cpu_limit   = var.environment == "production" ? "1000m" : "500m"
      memory_request = var.environment == "production" ? "512Mi" : "256Mi"
      memory_limit   = var.environment == "production" ? "2Gi" : "1Gi"
      replicas    = var.environment == "production" ? 2 : 1
      priority_class = "pyairtable-normal"
    }
    automation_services = {
      cpu_request = "100m"
      cpu_limit   = "500m"
      memory_request = "256Mi"
      memory_limit   = "1Gi"
      replicas    = var.environment == "production" ? 2 : 1
      priority_class = "pyairtable-normal"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Random resources for unique naming
resource "random_id" "cluster_suffix" {
  byte_length = 4
}

resource "random_password" "postgres_password" {
  length  = 32
  special = true
}

resource "random_password" "redis_password" {
  length  = 32
  special = false
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  
  vpc_cidr = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  
  enable_nat_gateway = true
  enable_vpn_gateway = var.environment == "production"
  enable_flow_logs   = var.enable_flow_logs
  
  tags = local.common_tags
}

# EKS Cluster
module "eks" {
  source = "./modules/eks"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  cluster_version = var.kubernetes_version
  
  # Node group configuration
  node_groups = {
    main = {
      name           = "main-${var.environment}"
      instance_types = local.config.instance_types
      min_size       = local.config.min_size
      max_size       = local.config.max_size
      desired_size   = local.config.desired_capacity
      
      # Cost optimization
      capacity_type = var.environment == "production" ? "ON_DEMAND" : "SPOT"
      
      # Taints for spot instances
      taints = var.environment != "production" ? [
        {
          key    = "spot-instance"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      ] : []
    }
    
    # Dedicated node group for critical services in production
    critical = var.environment == "production" ? {
      name           = "critical-${var.environment}"
      instance_types = ["m5.large", "c5.large"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      capacity_type  = "ON_DEMAND"
      
      labels = {
        node-type = "critical"
        workload  = "system"
      }
      
      taints = [
        {
          key    = "dedicated"
          value  = "critical"
          effect = "NO_SCHEDULE"
        }
      ]
    } : {}
  }
  
  # Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }
  
  tags = local.common_tags
}

# RDS Database
module "database" {
  source = "./modules/rds"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  # Database configuration
  engine         = "postgres"
  engine_version = "16.1"
  instance_class = local.config.db_instance_class
  
  allocated_storage     = var.environment == "production" ? 100 : 20
  max_allocated_storage = var.environment == "production" ? 1000 : 100
  
  db_name  = "pyairtable"
  username = "pyairtable_admin"
  password = random_password.postgres_password.result
  
  # High availability
  multi_az               = local.config.enable_multi_az
  backup_retention_period = local.config.backup_retention_days
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Security
  storage_encrypted = true
  deletion_protection = local.config.enable_deletion_protection
  
  # Performance Insights
  performance_insights_enabled = var.environment == "production"
  
  # Enhanced monitoring
  monitoring_interval = local.config.enable_detailed_monitoring ? 60 : 0
  
  tags = local.common_tags
}

# ElastiCache Redis Cluster
module "redis" {
  source = "./modules/elasticache"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  # Redis configuration
  node_type = local.config.redis_node_type
  num_cache_nodes = var.environment == "production" ? 3 : 1
  
  engine_version = "7.0"
  port           = 6379
  
  # Security
  auth_token = random_password.redis_password.result
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  # Backup
  snapshot_retention_limit = local.config.backup_retention_days
  snapshot_window         = "03:30-05:30"
  
  tags = local.common_tags
}

# Application Load Balancer
module "alb" {
  source = "./modules/alb"
  
  project_name = var.project_name
  environment  = var.environment
  
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids
  
  # Security groups
  security_group_ids = [module.eks.cluster_security_group_id]
  
  # SSL/TLS
  enable_https = true
  certificate_arn = var.ssl_certificate_arn
  
  # Access logging
  enable_access_logs = true
  
  tags = local.common_tags
}

# S3 Buckets for various purposes
module "s3_buckets" {
  source = "./modules/s3"
  
  project_name = var.project_name
  environment  = var.environment
  
  buckets = {
    # Application files and uploads
    uploads = {
      versioning_enabled = true
      lifecycle_rules = [
        {
          id     = "delete_old_versions"
          status = "Enabled"
          noncurrent_version_expiration = {
            days = 90
          }
        }
      ]
    }
    
    # Backup storage
    backups = {
      versioning_enabled = true
      lifecycle_rules = [
        {
          id     = "transition_to_ia"
          status = "Enabled"
          transition = {
            days          = 30
            storage_class = "STANDARD_IA"
          }
        },
        {
          id     = "transition_to_glacier"
          status = "Enabled"
          transition = {
            days          = 90
            storage_class = "GLACIER"
          }
        }
      ]
    }
    
    # Static assets and CDN
    assets = {
      versioning_enabled = false
      website_enabled    = true
      cors_rules = [
        {
          allowed_headers = ["*"]
          allowed_methods = ["GET", "HEAD"]
          allowed_origins = ["https://*.pyairtable.com"]
          expose_headers  = ["ETag"]
          max_age_seconds = 3000
        }
      ]
    }
  }
  
  tags = local.common_tags
}

# Secrets Manager
module "secrets" {
  source = "./modules/secrets"
  
  project_name = var.project_name
  environment  = var.environment
  
  secrets = {
    database = {
      description = "Database credentials"
      secret_string = jsonencode({
        username = "pyairtable_admin"
        password = random_password.postgres_password.result
        host     = module.database.endpoint
        port     = 5432
        database = "pyairtable"
      })
    }
    
    redis = {
      description = "Redis credentials"
      secret_string = jsonencode({
        host     = module.redis.primary_endpoint
        port     = 6379
        auth_token = random_password.redis_password.result
      })
    }
    
    application = {
      description = "Application secrets"
      secret_string = jsonencode({
        jwt_secret = var.jwt_secret
        api_key    = var.api_key
        airtable_token = var.airtable_token
        gemini_api_key = var.gemini_api_key
      })
    }
  }
  
  tags = local.common_tags
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application_logs" {
  for_each = toset([
    "api-gateway",
    "auth-service", 
    "platform-services",
    "automation-services"
  ])
  
  name              = "/aws/eks/${var.project_name}-${var.environment}/${each.key}"
  retention_in_days = local.config.log_retention_days
  
  tags = merge(local.common_tags, {
    Service = each.key
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-overview"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_count", "cluster_name", module.eks.cluster_name],
            ["AWS/EKS", "cluster_failed_node_count", "cluster_name", module.eks.cluster_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "EKS Cluster Health"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", module.database.db_instance_id],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", module.database.db_instance_id]
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "Database Metrics"
          period = 300
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Cost budgets
resource "aws_budgets_budget" "monthly_budget" {
  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filters {
    tag {
      key = "Project"
      values = [var.project_name]
    }
    tag {
      key = "Environment"
      values = [var.environment]
    }
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
  
  tags = local.common_tags
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EKS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EKS node CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    ClusterName = module.eks.cluster_name
  }
  
  tags = local.common_tags
}

# IAM roles for service accounts (IRSA)
module "irsa_roles" {
  source = "./modules/irsa"
  
  project_name = var.project_name
  environment  = var.environment
  
  cluster_name = module.eks.cluster_name
  oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  
  service_accounts = {
    api_gateway = {
      namespace = "pyairtable"
      policies = [
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      ]
    }
    
    platform_services = {
      namespace = "pyairtable"
      policies = [
        "arn:aws:iam::aws:policy/AmazonS3FullAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      ]
    }
    
    automation_services = {
      namespace = "pyairtable"
      policies = [
        "arn:aws:iam::aws:policy/AmazonS3FullAccess",
        "arn:aws:iam::aws:policy/AmazonSESFullAccess"
      ]
    }
  }
  
  tags = local.common_tags
}