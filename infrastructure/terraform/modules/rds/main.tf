# RDS Module - Enhanced with backup, disaster recovery, and security
# PostgreSQL with Multi-AZ, automated backups, and monitoring

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
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random password for database
resource "random_password" "master_password" {
  length  = 32
  special = true
  # Exclude characters that might cause issues
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store master password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.name_prefix}-db-master-password"
  description             = "Master password for ${var.name_prefix} RDS instance"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0
  kms_key_id              = var.kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-master-password"
  })
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.master_password.result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# Database subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-subnet-group"
  })
}

# Parameter group for PostgreSQL optimization
resource "aws_db_parameter_group" "main" {
  family = "postgres15"
  name   = "${var.name_prefix}-db-params"

  # Production-optimized parameters
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  parameter {
    name  = "log_statement"
    value = var.environment == "prod" ? "mod" : "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = var.environment == "prod" ? "1000" : "0"
  }

  parameter {
    name  = "log_checkpoints"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  dynamic "parameter" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      name  = "max_connections"
      value = "200"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-params"
  })
}

# Option group (if needed for PostgreSQL extensions)
resource "aws_db_option_group" "main" {
  count = var.create_option_group ? 1 : 0

  name                     = "${var.name_prefix}-db-options"
  option_group_description = "Option group for ${var.name_prefix}"
  engine_name              = "postgres"
  major_engine_version     = "15"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-options"
  })
}

# RDS instance
resource "aws_db_instance" "main" {
  # Engine and version
  engine              = "postgres"
  engine_version      = var.engine_version
  instance_class      = var.instance_class
  allocated_storage   = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type        = var.storage_type
  storage_encrypted   = true
  kms_key_id         = var.kms_key_id

  # Database configuration
  identifier = "${var.name_prefix}-db"
  db_name    = var.database_name
  username   = var.master_username
  manage_master_user_password = true
  master_user_secret_kms_key_id = var.kms_key_id

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  port                   = var.database_port

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = var.create_option_group ? aws_db_option_group.main[0].name : null

  # High availability and disaster recovery
  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : var.availability_zone
  
  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  copy_tags_to_snapshot  = true
  delete_automated_backups = false
  skip_final_snapshot    = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name_prefix}-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Maintenance
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately         = var.apply_immediately

  # Monitoring and performance
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
  performance_insights_enabled = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id = var.performance_insights_enabled ? var.kms_key_id : null

  # Logging
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  # Security
  deletion_protection = var.deletion_protection
  
  # Restore from snapshot if specified
  snapshot_identifier = var.snapshot_identifier

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db"
  })

  lifecycle {
    ignore_changes = [
      password,
      snapshot_identifier,
    ]
  }

  depends_on = [
    aws_db_subnet_group.main,
    aws_db_parameter_group.main
  ]
}

# Read replica (for production)
resource "aws_db_instance" "read_replica" {
  count = var.create_read_replica ? 1 : 0

  identifier                = "${var.name_prefix}-db-read-replica"
  replicate_source_db       = aws_db_instance.main.identifier
  instance_class           = var.read_replica_instance_class
  publicly_accessible     = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  
  # Monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
  performance_insights_enabled = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null
  performance_insights_kms_key_id = var.performance_insights_enabled ? var.kms_key_id : null

  skip_final_snapshot = true
  deletion_protection = var.deletion_protection

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-read-replica"
    Role = "ReadReplica"
  })
}

# Enhanced monitoring role
resource "aws_iam_role" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name = "${var.name_prefix}-rds-enhanced-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-rds-enhanced-monitoring-role"
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Log Groups for RDS logs
resource "aws_cloudwatch_log_group" "postgresql" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${var.name_prefix}-db/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-${each.value}-logs"
  })
}

# Database connection information in SSM Parameter Store
resource "aws_ssm_parameter" "database_url" {
  name  = "/${var.name_prefix}/${var.environment}/database-url"
  type  = "SecureString"
  value = "postgresql://${aws_db_instance.main.username}:${random_password.master_password.result}@${aws_db_instance.main.endpoint}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
  key_id = var.kms_key_id

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-database-url"
  })

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "database_host" {
  name  = "/${var.name_prefix}/${var.environment}/database-host"
  type  = "String"
  value = aws_db_instance.main.endpoint

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-database-host"
  })
}

resource "aws_ssm_parameter" "database_port" {
  name  = "/${var.name_prefix}/${var.environment}/database-port"
  type  = "String"
  value = tostring(aws_db_instance.main.port)

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-database-port"
  })
}

resource "aws_ssm_parameter" "database_name" {
  name  = "/${var.name_prefix}/${var.environment}/database-name"
  type  = "String"
  value = aws_db_instance.main.db_name

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-database-name"
  })
}

resource "aws_ssm_parameter" "read_replica_endpoint" {
  count = var.create_read_replica ? 1 : 0

  name  = "/${var.name_prefix}/${var.environment}/database-read-replica-endpoint"
  type  = "String"
  value = aws_db_instance.read_replica[0].endpoint

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-database-read-replica-endpoint"
  })
}

# Automated backup to S3 (additional backup beyond RDS automated backups)
resource "aws_db_snapshot" "manual_snapshot" {
  count = var.create_manual_snapshot ? 1 : 0

  db_instance_identifier = aws_db_instance.main.identifier
  db_snapshot_identifier = "${var.name_prefix}-manual-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-manual-snapshot"
    Type = "Manual"
  })
}

# CloudWatch alarms for database monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.name_prefix}-db-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_actions
  ok_actions         = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.name_prefix}-db-connection-count"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.connection_alarm_threshold
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = var.alarm_actions
  ok_actions         = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-connections-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "database_free_storage" {
  alarm_name          = "${var.name_prefix}-db-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.free_storage_alarm_threshold * 1024 * 1024 * 1024 # Convert GB to bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = var.alarm_actions
  ok_actions         = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  tags = merge(var.common_tags, {
    Name = "${var.name_prefix}-db-free-storage-alarm"
  })
}