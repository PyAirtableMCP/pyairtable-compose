# Enhanced Terraform Configuration for PyAirtable
# Provides comprehensive infrastructure automation with state management,
# cost tracking, disaster recovery, and multi-region support

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
      version = "~> 3.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  
  # S3 backend for state management with locking
  backend "s3" {
    bucket         = "pyairtable-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "pyairtable-terraform-locks"
    
    # Versioning and backup
    versioning = true
  }
}

# Local values for common configurations
locals {
  environment = var.environment
  project     = "pyairtable"
  region      = var.aws_region
  
  # Cost allocation tags
  common_tags = {
    Project      = local.project
    Environment  = local.environment
    ManagedBy    = "terraform"
    Owner        = var.owner_email
    CostCenter   = var.cost_center
    CreatedBy    = "terraform"
    CreatedAt    = timestamp()
  }
  
  # Multi-region configuration
  regions = var.multi_region_enabled ? var.regions : [local.region]
  
  # Availability zones
  azs = data.aws_availability_zones.available.names
  
  # CIDR blocks for VPC
  vpc_cidr = var.vpc_cidrs[local.environment]
  
  # Kubernetes cluster configuration
  cluster_name = "${local.project}-${local.environment}-cluster"
  
  # Domain configuration
  domain_name = var.domain_names[local.environment]
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Random password for databases
resource "random_password" "master_password" {
  length  = 32
  special = true
}

# KMS key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${local.project} ${local.environment}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-kms"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.project}-${local.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  name               = "${local.project}-${local.environment}"
  cidr               = local.vpc_cidr
  azs                = slice(local.azs, 0, 3)
  private_subnets    = var.private_subnet_cidrs[local.environment]
  public_subnets     = var.public_subnet_cidrs[local.environment]
  database_subnets   = var.database_subnet_cidrs[local.environment]
  
  enable_nat_gateway     = true
  enable_vpn_gateway     = var.environment == "prod"
  enable_flow_log        = true
  create_flow_log_s3_iam_role = true
  flow_log_destination_type    = "s3"
  flow_log_destination_arn     = aws_s3_bucket.vpc_flow_logs.arn
  
  # DNS settings
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = local.common_tags
}

# S3 bucket for VPC flow logs
resource "aws_s3_bucket" "vpc_flow_logs" {
  bucket = "${local.project}-${local.environment}-vpc-flow-logs-${random_id.bucket_suffix.hex}"
  
  tags = merge(local.common_tags, {
    Name = "VPC Flow Logs"
  })
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.main.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# EKS Cluster Module
module "eks" {
  source = "./modules/eks"
  
  cluster_name                    = local.cluster_name
  cluster_version                 = var.kubernetes_version
  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  control_plane_subnet_ids       = module.vpc.public_subnets
  
  # Encryption
  cluster_encryption_config = [{
    provider_key_arn = aws_kms_key.main.arn
    resources        = ["secrets"]
  }]
  
  # Logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.environment == "prod" ? 90 : 7
  
  # Node groups
  node_groups = var.eks_node_groups[local.environment]
  
  # IRSA (IAM Roles for Service Accounts)
  enable_irsa = true
  
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
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }
  
  tags = local.common_tags
}

# EBS CSI Driver IRSA
module "ebs_csi_irsa_role" {
  source = "./modules/iam-role-for-service-accounts"
  
  role_name = "${local.cluster_name}-ebs-csi"
  
  attach_ebs_csi_policy = true
  
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  
  tags = local.common_tags
}

# RDS Module
module "rds" {
  source = "./modules/rds"
  
  identifier = "${local.project}-${local.environment}"
  
  # Engine configuration
  engine               = "postgres"
  engine_version       = var.postgres_version
  family               = var.postgres_family
  major_engine_version = var.postgres_major_version
  instance_class       = var.rds_instance_classes[local.environment]
  
  allocated_storage     = var.rds_allocated_storage[local.environment]
  max_allocated_storage = var.rds_max_allocated_storage[local.environment]
  
  # Network
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [aws_security_group.rds.id]
  
  # Database configuration
  db_name  = var.database_name
  username = var.database_username
  password = random_password.master_password.result
  port     = 5432
  
  # Maintenance
  maintenance_window              = var.rds_maintenance_window[local.environment]
  backup_window                  = var.rds_backup_window[local.environment]
  backup_retention_period        = var.rds_backup_retention[local.environment]
  copy_tags_to_snapshot          = true
  delete_automated_backups       = var.environment != "prod"
  deletion_protection            = var.environment == "prod"
  
  # Performance and monitoring
  monitoring_interval          = var.environment == "prod" ? 60 : 0
  monitoring_role_arn         = var.environment == "prod" ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # Multi-AZ for production
  multi_az = var.environment == "prod"
  
  # Encryption
  storage_encrypted = true
  kms_key_id       = aws_kms_key.main.arn
  
  # Parameter group
  create_db_parameter_group = true
  parameter_group_name      = "${local.project}-${local.environment}-postgres"
  parameters = var.postgres_parameters
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-db"
  })
}

# RDS Enhanced Monitoring Role (for production)
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.environment == "prod" ? 1 : 0
  
  name_prefix        = "rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring.json
  
  tags = local.common_tags
}

data "aws_iam_policy_document" "rds_enhanced_monitoring" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]
    
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.environment == "prod" ? 1 : 0
  
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ElastiCache Redis Module
module "redis" {
  source = "./modules/redis"
  
  cluster_id           = "${local.project}-${local.environment}"
  description          = "${local.project} ${local.environment} Redis cluster"
  node_type           = var.redis_node_types[local.environment]
  port                = 6379
  parameter_group_name = "default.redis7"
  
  num_cache_clusters  = var.redis_num_cache_nodes[local.environment]
  
  # Network
  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth_token.result
  kms_key_id                = aws_kms_key.main.arn
  
  # Backup (for production)
  snapshot_retention_limit = var.environment == "prod" ? 7 : 0
  snapshot_window         = var.environment == "prod" ? "03:00-04:00" : null
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-redis"
  })
}

resource "random_password" "redis_auth_token" {
  length  = 64
  special = false
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.project}-${local.environment}-redis"
  subnet_ids = module.vpc.private_subnets
  
  tags = local.common_tags
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.project}-${local.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = module.vpc.public_subnets
  
  enable_deletion_protection = var.environment == "prod"
  
  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-alb"
  })
}

# S3 bucket for ALB access logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${local.project}-${local.environment}-alb-logs-${random_id.alb_bucket_suffix.hex}"
  
  tags = merge(local.common_tags, {
    Name = "ALB Access Logs"
  })
}

resource "random_id" "alb_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
    
    actions = ["s3:PutObject"]
    
    resources = [
      "${aws_s3_bucket.alb_logs.arn}/*",
    ]
  }
}

# Route53 Hosted Zone
resource "aws_route53_zone" "main" {
  count = var.create_hosted_zone ? 1 : 0
  
  name = local.domain_name
  
  tags = merge(local.common_tags, {
    Name = local.domain_name
  })
}

# ACM Certificate
resource "aws_acm_certificate" "main" {
  domain_name       = local.domain_name
  validation_method = "DNS"
  
  subject_alternative_names = [
    "*.${local.domain_name}"
  ]
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = merge(local.common_tags, {
    Name = local.domain_name
  })
}

resource "aws_acm_certificate_validation" "main" {
  count = var.create_hosted_zone ? 1 : 0
  
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.create_hosted_zone ? {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main[0].zone_id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${local.project}-${local.environment}-alb-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for ALB"
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-alb-sg"
  })
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.project}-${local.environment}-rds-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for RDS"
  
  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-rds-sg"
  })
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.project}-${local.environment}-redis-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for Redis"
  
  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.project}-${local.environment}-redis-sg"
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${local.cluster_name}/application"
  retention_in_days = var.log_retention_days[local.environment]
  kms_key_id       = aws_kms_key.main.arn
  
  tags = local.common_tags
}

# Parameter Store for secrets
resource "aws_ssm_parameter" "database_password" {
  name  = "/${local.project}/${local.environment}/database/password"
  type  = "SecureString"
  value = random_password.master_password.result
  key_id = aws_kms_key.main.arn
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "redis_auth_token" {
  name  = "/${local.project}/${local.environment}/redis/auth_token"
  type  = "SecureString"
  value = random_password.redis_auth_token.result
  key_id = aws_kms_key.main.arn
  
  tags = local.common_tags
}

# CloudWatch Alarms for cost monitoring
resource "aws_cloudwatch_metric_alarm" "high_cost" {
  count = var.environment == "prod" ? 1 : 0
  
  alarm_name          = "${local.project}-${local.environment}-high-cost"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.cost_alert_threshold
  alarm_description   = "This metric monitors AWS estimated charges"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    Currency = "USD"
  }
  
  tags = local.common_tags
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name         = "${local.project}-${local.environment}-alerts"
  display_name = "PyAirtable Alerts"
  
  kms_master_key_id = aws_kms_key.main.id
  
  tags = local.common_tags
}

# Backup configuration
module "backup" {
  source = "./modules/backup"
  count  = var.enable_backup ? 1 : 0
  
  backup_vault_name = "${local.project}-${local.environment}-backup-vault"
  kms_key_arn      = aws_kms_key.main.arn
  
  # Backup plans
  backup_plans = var.backup_plans[local.environment]
  
  # Resources to backup
  backup_resources = [
    module.rds.db_instance_arn,
    aws_s3_bucket.alb_logs.arn,
    aws_s3_bucket.vpc_flow_logs.arn,
  ]
  
  tags = local.common_tags
}