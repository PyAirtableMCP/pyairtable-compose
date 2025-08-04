# Disaster Recovery Configuration for PyAirtable
# Provides comprehensive DR capabilities including cross-region replication,
# automated failover, and recovery orchestration

# Local values for DR configuration
locals {
  dr_enabled = var.environment == "prod" && var.enable_cross_region_backup
  dr_region  = var.backup_destination_region
  
  dr_tags = merge(local.common_tags, {
    Purpose = "disaster-recovery"
    DRType  = "cross-region"
  })
}

# Cross-region provider for DR
provider "aws" {
  alias  = "dr"
  region = local.dr_region
  
  default_tags {
    tags = local.dr_tags
  }
}

# DR S3 bucket for database backups
resource "aws_s3_bucket" "dr_database_backups" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.dr
  
  bucket = "${local.project}-${local.environment}-dr-db-backups-${random_id.dr_bucket_suffix.hex}"
  
  tags = merge(local.dr_tags, {
    Name = "DR Database Backups"
  })
}

resource "random_id" "dr_bucket_suffix" {
  count       = local.dr_enabled ? 1 : 0
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "dr_database_backups" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.dr
  
  bucket = aws_s3_bucket.dr_database_backups[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "dr_database_backups" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.dr
  
  bucket = aws_s3_bucket.dr_database_backups[0].id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.dr_key[0].arn
        sse_algorithm     = "aws:kms"
      }
    }
  }
}

# DR KMS key
resource "aws_kms_key" "dr_key" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.dr
  
  description             = "KMS key for DR in ${local.dr_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  
  tags = merge(local.dr_tags, {
    Name = "${local.project}-${local.environment}-dr-kms"
  })
}

resource "aws_kms_alias" "dr_key" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.dr
  
  name          = "alias/${local.project}-${local.environment}-dr"
  target_key_id = aws_kms_key.dr_key[0].key_id
}

# Cross-region replication for RDS
resource "aws_db_snapshot" "manual_snapshot" {
  count = local.dr_enabled ? 1 : 0
  
  db_instance_identifier = module.rds.db_instance_identifier
  db_snapshot_identifier = "${local.project}-${local.environment}-manual-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = local.dr_tags
  
  lifecycle {
    ignore_changes = [db_snapshot_identifier]
  }
}

# Lambda function for automated DR orchestration
resource "aws_lambda_function" "dr_orchestrator" {
  count = local.dr_enabled ? 1 : 0
  
  filename         = "dr_orchestrator.zip"
  function_name    = "${local.project}-${local.environment}-dr-orchestrator"
  role            = aws_iam_role.dr_orchestrator[0].arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes
  
  environment {
    variables = {
      PRIMARY_REGION      = local.region
      DR_REGION          = local.dr_region
      RDS_INSTANCE_ID    = module.rds.db_instance_identifier
      CLUSTER_NAME       = local.cluster_name
      DR_BUCKET         = local.dr_enabled ? aws_s3_bucket.dr_database_backups[0].bucket : ""
      SNS_TOPIC_ARN     = aws_sns_topic.dr_alerts[0].arn
    }
  }
  
  tags = local.dr_tags
}

# Create the Lambda deployment package
data "archive_file" "dr_orchestrator" {
  count = local.dr_enabled ? 1 : 0
  
  type        = "zip"
  output_path = "dr_orchestrator.zip"
  
  source {
    content = templatefile("${path.module}/templates/dr_orchestrator.py", {
      primary_region = local.region
      dr_region     = local.dr_region
    })
    filename = "index.py"
  }
}

# IAM role for DR orchestrator
resource "aws_iam_role" "dr_orchestrator" {
  count = local.dr_enabled ? 1 : 0
  
  name_prefix = "${local.project}-${local.environment}-dr-orchestrator-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.dr_tags
}

resource "aws_iam_role_policy" "dr_orchestrator" {
  count = local.dr_enabled ? 1 : 0
  
  name_prefix = "${local.project}-${local.environment}-dr-orchestrator-"
  role        = aws_iam_role.dr_orchestrator[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstanceReadReplica",
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots",
          "rds:CreateDBSnapshot",
          "rds:CopyDBSnapshot",
          "rds:RestoreDBInstanceFromDBSnapshot",
          "rds:PromoteReadReplica",
          "rds:ModifyDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:UpdateClusterConfig",
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.dr_enabled ? aws_s3_bucket.dr_database_backups[0].arn : "",
          local.dr_enabled ? "${aws_s3_bucket.dr_database_backups[0].arn}/*" : ""
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = local.dr_enabled ? aws_sns_topic.dr_alerts[0].arn : ""
      },
      {
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch event rule for scheduled DR testing
resource "aws_cloudwatch_event_rule" "dr_test" {
  count = local.dr_enabled ? 1 : 0
  
  name                = "${local.project}-${local.environment}-dr-test"
  description         = "Trigger DR testing"
  schedule_expression = "cron(0 2 * * SUN *)"  # Weekly on Sunday at 2 AM
  
  tags = local.dr_tags
}

resource "aws_cloudwatch_event_target" "dr_test" {
  count = local.dr_enabled ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.dr_test[0].name
  target_id = "DrTestTarget"
  arn       = aws_lambda_function.dr_orchestrator[0].arn
  
  input = jsonencode({
    action = "test"
    dry_run = true
  })
}

resource "aws_lambda_permission" "allow_cloudwatch_dr_test" {
  count = local.dr_enabled ? 1 : 0
  
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_orchestrator[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dr_test[0].arn
}

# SNS topic for DR alerts
resource "aws_sns_topic" "dr_alerts" {
  count = local.dr_enabled ? 1 : 0
  
  name         = "${local.project}-${local.environment}-dr-alerts"
  display_name = "PyAirtable DR Alerts"
  
  kms_master_key_id = aws_kms_key.main.id
  
  tags = local.dr_tags
}

# CloudWatch alarms for DR monitoring
resource "aws_cloudwatch_metric_alarm" "rds_replica_lag" {
  count = local.dr_enabled ? 1 : 0
  
  alarm_name          = "${local.project}-${local.environment}-rds-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "300"  # 5 minutes
  alarm_description   = "This metric monitors RDS replica lag"
  alarm_actions       = [aws_sns_topic.dr_alerts[0].arn]
  
  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }
  
  tags = local.dr_tags
}

# Cross-region VPC for DR (simplified)
module "dr_vpc" {
  count = local.dr_enabled ? 1 : 0
  
  source = "./modules/vpc"
  
  providers = {
    aws = aws.dr
  }
  
  name               = "${local.project}-${local.environment}-dr"
  cidr               = "10.100.0.0/16"  # Different CIDR for DR region
  azs                = slice(data.aws_availability_zones.dr[0].names, 0, 2)
  private_subnets    = ["10.100.1.0/24", "10.100.2.0/24"]
  public_subnets     = ["10.100.101.0/24", "10.100.102.0/24"]
  database_subnets   = ["10.100.201.0/24", "10.100.202.0/24"]
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_flow_log    = true
  
  tags = local.dr_tags
}

data "aws_availability_zones" "dr" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.dr
  state    = "available"
}

# DR RDS instance (standby)
resource "aws_db_instance" "dr_standby" {
  count = local.dr_enabled ? 1 : 0
  
  provider = aws.dr
  
  identifier     = "${local.project}-${local.environment}-dr"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.rds_instance_classes[local.environment]
  
  allocated_storage = var.rds_allocated_storage[local.environment]
  storage_encrypted = true
  kms_key_id       = aws_kms_key.dr_key[0].arn
  
  db_name  = var.database_name
  username = var.database_username
  password = random_password.master_password.result
  
  db_subnet_group_name   = aws_db_subnet_group.dr[0].name
  vpc_security_group_ids = [aws_security_group.dr_rds[0].id]
  
  backup_retention_period = var.rds_backup_retention[local.environment]
  backup_window          = var.rds_backup_window[local.environment]
  maintenance_window     = var.rds_maintenance_window[local.environment]
  
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.project}-${local.environment}-dr-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  # This instance starts as a snapshot restore
  snapshot_identifier = aws_db_snapshot.manual_snapshot[0].id
  
  tags = merge(local.dr_tags, {
    Name = "${local.project}-${local.environment}-dr-db"
  })
  
  lifecycle {
    ignore_changes = [
      snapshot_identifier,
      final_snapshot_identifier
    ]
  }
}

resource "aws_db_subnet_group" "dr" {
  count = local.dr_enabled ? 1 : 0
  
  provider = aws.dr
  
  name       = "${local.project}-${local.environment}-dr"
  subnet_ids = module.dr_vpc[0].database_subnets
  
  tags = local.dr_tags
}

resource "aws_security_group" "dr_rds" {
  count = local.dr_enabled ? 1 : 0
  
  provider = aws.dr
  
  name_prefix = "${local.project}-${local.environment}-dr-rds-"
  vpc_id      = module.dr_vpc[0].vpc_id
  description = "Security group for DR RDS"
  
  ingress {
    description = "PostgreSQL from DR VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.dr_vpc[0].vpc_cidr_block]
  }
  
  tags = merge(local.dr_tags, {
    Name = "${local.project}-${local.environment}-dr-rds-sg"
  })
}

# Route53 health check for primary region
resource "aws_route53_health_check" "primary" {
  count = local.dr_enabled ? 1 : 0
  
  fqdn                            = local.domain_name
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/health"
  failure_threshold               = "3"
  request_interval                = "30"
  cloudwatch_alarm_region         = local.region
  cloudwatch_alarm_name           = "${local.project}-${local.environment}-primary-health"
  insufficient_data_health_status = "Failure"
  
  tags = merge(local.dr_tags, {
    Name = "Primary Region Health Check"
  })
}

# CloudWatch alarm for primary region failure
resource "aws_cloudwatch_metric_alarm" "primary_failure" {
  count = local.dr_enabled ? 1 : 0
  
  alarm_name          = "${local.project}-${local.environment}-primary-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Primary region health check failure"
  alarm_actions       = [aws_sns_topic.dr_alerts[0].arn]
  
  dimensions = {
    HealthCheckId = aws_route53_health_check.primary[0].id
  }
  
  tags = local.dr_tags
}

# Route53 failover records
resource "aws_route53_record" "primary" {
  count = local.dr_enabled && var.create_hosted_zone ? 1 : 0
  
  zone_id = aws_route53_zone.main[0].zone_id
  name    = local.domain_name
  type    = "A"
  
  set_identifier = "primary"
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary[0].id
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count = local.dr_enabled && var.create_hosted_zone ? 1 : 0
  
  provider = aws.dr
  
  zone_id = aws_route53_zone.main[0].zone_id
  name    = local.domain_name
  type    = "A"
  
  set_identifier = "secondary"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  alias {
    name                   = aws_lb.dr[0].dns_name
    zone_id                = aws_lb.dr[0].zone_id
    evaluate_target_health = true
  }
}

# DR Load Balancer (minimal setup)
resource "aws_lb" "dr" {
  count = local.dr_enabled ? 1 : 0
  
  provider = aws.dr
  
  name               = "${local.project}-${local.environment}-dr-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.dr_alb[0].id]
  subnets           = module.dr_vpc[0].public_subnets
  
  enable_deletion_protection = false
  
  tags = merge(local.dr_tags, {
    Name = "${local.project}-${local.environment}-dr-alb"
  })
}

resource "aws_security_group" "dr_alb" {
  count = local.dr_enabled ? 1 : 0
  
  provider = aws.dr
  
  name_prefix = "${local.project}-${local.environment}-dr-alb-"
  vpc_id      = module.dr_vpc[0].vpc_id
  description = "Security group for DR ALB"
  
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
  
  tags = merge(local.dr_tags, {
    Name = "${local.project}-${local.environment}-dr-alb-sg"
  })
}