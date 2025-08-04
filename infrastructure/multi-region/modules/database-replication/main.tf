# Database Replication Module
# PostgreSQL multi-region setup with streaming replication and conflict resolution

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}

# Parameter Group for PostgreSQL with optimized settings for replication
resource "aws_db_parameter_group" "postgres_replication" {
  name_prefix = "${var.project_name}-${var.environment}-postgres-replication-"
  family      = "postgres15"
  description = "Parameter group for PostgreSQL replication"

  # Replication settings
  parameter {
    name  = "wal_level"
    value = "replica"
  }

  parameter {
    name  = "max_wal_senders"
    value = "10"
  }

  parameter {
    name  = "wal_keep_size"
    value = "2048"  # MB
  }

  parameter {
    name  = "max_replication_slots"
    value = "10"
  }

  # Performance optimizations
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pg_hint_plan"
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "2097152"  # 2GB in KB
  }

  parameter {
    name  = "checkpoint_completion_target"
    value = "0.9"
  }

  parameter {
    name  = "wal_buffers"
    value = "16384"  # 16MB in KB
  }

  parameter {
    name  = "default_statistics_target"
    value = "100"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"  # Optimized for SSD
  }

  parameter {
    name  = "effective_io_concurrency"
    value = "200"  # Optimized for SSD
  }

  # Connection settings
  parameter {
    name  = "max_connections"
    value = "1000"
  }

  parameter {
    name  = "work_mem"
    value = "4096"  # 4MB in KB
  }

  # Logging settings
  parameter {
    name  = "log_statement"
    value = "mod"  # Log all DDL statements
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking longer than 1 second
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

  # Conflict resolution settings
  parameter {
    name  = "hot_standby"
    value = "1"  # Enable read queries on standby
  }

  parameter {
    name  = "max_standby_streaming_delay"
    value = "30s"
  }

  parameter {
    name  = "hot_standby_feedback"
    value = "1"  # Reduce conflicts between primary and standby
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres-replication-params"
  }
}

# Option Group for PostgreSQL extensions
resource "aws_db_option_group" "postgres_replication" {
  name                     = "${var.project_name}-${var.environment}-postgres-replication-options"
  option_group_description = "Option group for PostgreSQL replication"
  engine_name              = "postgres"
  major_engine_version     = "15"

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres-replication-options"
  }
}

# Primary Database Instance
resource "aws_db_instance" "primary" {
  identifier = "${var.project_name}-${var.environment}-primary"

  # Engine configuration
  engine              = "postgres"
  engine_version      = var.postgres_version
  instance_class      = var.primary_instance_class
  allocated_storage   = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type        = "gp3"
  storage_encrypted   = true
  kms_key_id         = aws_kms_key.database.arn

  # Database configuration
  db_name  = var.database_name
  username = var.database_username
  password = random_password.master_password.result
  port     = 5432

  # Network and security
  vpc_security_group_ids = var.security_group_ids
  db_subnet_group_name   = var.db_subnet_group_name
  publicly_accessible    = false

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.postgres_replication.name
  option_group_name    = aws_db_option_group.postgres_replication.name

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  auto_minor_version_upgrade = false

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id      = aws_kms_key.database.arn
  performance_insights_retention_period = 7

  # Enhanced monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_role_arn

  # High availability
  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : var.primary_availability_zone

  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.project_name}-${var.environment}-primary-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Replication
  backup_retention_period = var.backup_retention_period

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-primary-db"
    Role = "primary"
  })

  depends_on = [
    aws_db_parameter_group.postgres_replication,
    aws_db_option_group.postgres_replication
  ]
}

# Cross-region read replicas
resource "aws_db_instance" "read_replica" {
  for_each = var.read_replica_regions

  identifier = "${var.project_name}-${var.environment}-replica-${each.key}"

  # Source database
  replicate_source_db = aws_db_instance.primary.identifier

  # Instance configuration
  instance_class        = var.replica_instance_class
  publicly_accessible   = false
  auto_minor_version_upgrade = false

  # Network configuration (will be in the replica region)
  vpc_security_group_ids = each.value.security_group_ids
  
  # Parameter group for replica
  parameter_group_name = aws_db_parameter_group.postgres_replica[each.key].name

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_kms_key_id      = aws_kms_key.replica_database[each.key].arn
  performance_insights_retention_period = 7

  # Enhanced monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = each.value.monitoring_role_arn

  # High availability for replica
  multi_az = var.replica_multi_az

  # Logging
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = !var.deletion_protection
  final_snapshot_identifier = var.deletion_protection ? "${var.project_name}-${var.environment}-replica-${each.key}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-replica-${each.key}-db"
    Role = "replica"
    Region = each.key
  })

  depends_on = [
    aws_db_instance.primary,
    aws_db_parameter_group.postgres_replica
  ]
}

# Parameter groups for replicas (region-specific optimizations)
resource "aws_db_parameter_group" "postgres_replica" {
  for_each = var.read_replica_regions

  name_prefix = "${var.project_name}-${var.environment}-postgres-replica-${each.key}-"
  family      = "postgres15"
  description = "Parameter group for PostgreSQL replica in ${each.key}"

  # Replica-specific settings
  parameter {
    name  = "hot_standby"
    value = "1"
  }

  parameter {
    name  = "max_standby_streaming_delay"
    value = "30s"
  }

  parameter {
    name  = "max_standby_archive_delay"
    value = "30s"
  }

  parameter {
    name  = "hot_standby_feedback"
    value = "1"
  }

  # Performance optimizations for read workloads
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4}"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
  }

  parameter {
    name  = "effective_io_concurrency"
    value = "200"
  }

  parameter {
    name  = "work_mem"
    value = "8192"  # 8MB for read queries
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "2097152"  # 2GB
  }

  # Connection settings optimized for read workloads
  parameter {
    name  = "max_connections"
    value = "1000"
  }

  # Logging settings
  parameter {
    name  = "log_min_duration_statement"
    value = "5000"  # Log slow queries (5 seconds)
  }

  parameter {
    name  = "log_statement"
    value = "none"  # Reduce logging on replicas
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-postgres-replica-${each.key}-params"
    Region = each.key
  })
}

# KMS Key for primary database encryption
resource "aws_kms_key" "database" {
  description             = "KMS key for ${var.project_name} ${var.environment} primary database encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database-key"
  })
}

resource "aws_kms_alias" "database" {
  name          = "alias/${var.project_name}-${var.environment}-database"
  target_key_id = aws_kms_key.database.key_id
}

# KMS Keys for replica databases (one per region)
resource "aws_kms_key" "replica_database" {
  for_each = var.read_replica_regions

  description             = "KMS key for ${var.project_name} ${var.environment} replica database encryption in ${each.key}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-replica-${each.key}-database-key"
    Region = each.key
  })
}

resource "aws_kms_alias" "replica_database" {
  for_each = var.read_replica_regions

  name          = "alias/${var.project_name}-${var.environment}-replica-${each.key}-database"
  target_key_id = aws_kms_key.replica_database[each.key].key_id
}

# Random password for master database
resource "random_password" "master_password" {
  length      = 32
  special     = true
  min_special = 2
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

# Secrets Manager secret for database credentials
resource "aws_secretsmanager_secret" "database_credentials" {
  name        = "${var.project_name}/${var.environment}/database/master"
  description = "Master database credentials for ${var.project_name}"
  kms_key_id  = aws_kms_key.database.arn

  replica {
    region     = "eu-west-1"
    kms_key_id = aws_kms_key.replica_database["eu-west-1"].arn
  }

  replica {
    region     = "ap-southeast-1"
    kms_key_id = aws_kms_key.replica_database["ap-southeast-1"].arn
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database-secret"
  })
}

resource "aws_secretsmanager_secret_version" "database_credentials" {
  secret_id = aws_secretsmanager_secret.database_credentials.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.primary.endpoint
    port     = aws_db_instance.primary.port
    dbname   = aws_db_instance.primary.db_name
    username = aws_db_instance.primary.username
    password = random_password.master_password.result
  })
}

# Secrets for read replicas
resource "aws_secretsmanager_secret" "replica_credentials" {
  for_each = var.read_replica_regions

  name        = "${var.project_name}/${var.environment}/database/replica-${each.key}"
  description = "Read replica database credentials for ${var.project_name} in ${each.key}"
  kms_key_id  = aws_kms_key.replica_database[each.key].arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-replica-${each.key}-secret"
    Region = each.key
  })
}

resource "aws_secretsmanager_secret_version" "replica_credentials" {
  for_each = var.read_replica_regions

  secret_id = aws_secretsmanager_secret.replica_credentials[each.key].id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.read_replica[each.key].endpoint
    port     = aws_db_instance.read_replica[each.key].port
    dbname   = aws_db_instance.primary.db_name
    username = aws_db_instance.primary.username
    password = random_password.master_password.result
    replica  = true
    region   = each.key
  })

  depends_on = [aws_db_instance.read_replica]
}

# CloudWatch Log Groups for database logs
resource "aws_cloudwatch_log_group" "database_logs" {
  name              = "/aws/rds/instance/${aws_db_instance.primary.identifier}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id       = aws_kms_key.database.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-primary-db-logs"
  })
}

resource "aws_cloudwatch_log_group" "replica_logs" {
  for_each = var.read_replica_regions

  name              = "/aws/rds/instance/${aws_db_instance.read_replica[each.key].identifier}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id       = aws_kms_key.replica_database[each.key].arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-replica-${each.key}-db-logs"
    Region = each.key
  })
}

# CloudWatch Alarms for database monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-primary-db-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors primary database CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-primary-db-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-primary-db-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "800"
  alarm_description   = "This metric monitors primary database connections"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.primary.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-primary-db-connections-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  for_each = var.read_replica_regions

  alarm_name          = "${var.project_name}-${var.environment}-replica-${each.key}-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "300"  # 5 minutes
  alarm_description   = "This metric monitors replica lag for ${each.key}"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.read_replica[each.key].id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-replica-${each.key}-lag-alarm"
    Region = each.key
  })
}

# Database migration scripts for conflict resolution
resource "aws_s3_bucket" "database_scripts" {
  bucket = "${var.project_name}-${var.environment}-database-scripts-${random_string.scripts_bucket_suffix.result}"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database-scripts"
  })
}

resource "random_string" "scripts_bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "database_scripts" {
  bucket = aws_s3_bucket.database_scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "database_scripts" {
  bucket = aws_s3_bucket.database_scripts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.database.arn
    }
  }
}

# Upload conflict resolution scripts
resource "aws_s3_object" "conflict_resolution_script" {
  bucket = aws_s3_bucket.database_scripts.bucket
  key    = "scripts/conflict_resolution.sql"
  source = "${path.module}/scripts/conflict_resolution.sql"
  etag   = filemd5("${path.module}/scripts/conflict_resolution.sql")

  tags = merge(var.tags, {
    Name = "conflict-resolution-script"
  })
}

resource "aws_s3_object" "monitoring_script" {
  bucket = aws_s3_bucket.database_scripts.bucket
  key    = "scripts/monitoring.sql"
  source = "${path.module}/scripts/monitoring.sql"
  etag   = filemd5("${path.module}/scripts/monitoring.sql")

  tags = merge(var.tags, {
    Name = "monitoring-script"
  })
}

# Lambda function for automated failover
resource "aws_lambda_function" "database_failover" {
  filename         = "${path.module}/lambda/database_failover.zip"
  function_name    = "${var.project_name}-${var.environment}-database-failover"
  role            = aws_iam_role.lambda_failover.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300

  environment {
    variables = {
      PRIMARY_DB_IDENTIFIER = aws_db_instance.primary.identifier
      REPLICA_IDENTIFIERS   = jsonencode([for k, v in aws_db_instance.read_replica : v.identifier])
      SNS_TOPIC_ARN        = var.sns_topic_arn
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database-failover-lambda"
  })
}

# IAM role for Lambda failover function
resource "aws_iam_role" "lambda_failover" {
  name = "${var.project_name}-${var.environment}-database-failover-lambda-role"

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

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-database-failover-lambda-role"
  })
}

resource "aws_iam_role_policy" "lambda_failover" {
  name = "${var.project_name}-${var.environment}-database-failover-policy"
  role = aws_iam_role.lambda_failover.id

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
          "rds:DescribeDBInstances",
          "rds:FailoverDBCluster",
          "rds:PromoteReadReplica",
          "rds:ModifyDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = "*"
      }
    ]
  })
}