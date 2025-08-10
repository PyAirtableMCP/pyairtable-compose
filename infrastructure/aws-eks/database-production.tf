# Production Database Infrastructure for PyAirtable EKS
# RDS PostgreSQL with Multi-AZ, automated backups, and connection pooling

# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

# Database Security Group
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from EKS nodes"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [module.security.node_security_group_id]
  }

  ingress {
    description = "PostgreSQL from PgBouncer"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.pgbouncer.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  })
}

# PgBouncer Security Group for connection pooling
resource "aws_security_group" "pgbouncer" {
  name_prefix = "${var.project_name}-${var.environment}-pgbouncer-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PgBouncer from EKS"
    from_port   = 6432
    to_port     = 6432
    protocol    = "tcp"
    security_groups = [module.security.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-pgbouncer-sg"
  })
}

# Database password
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# RDS PostgreSQL Instance - Production Configuration
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db"

  # Engine Configuration
  engine              = "postgres"
  engine_version      = "15.4"
  instance_class      = var.environment == "production" ? "db.r6g.large" : "db.t3.medium"
  
  # Storage Configuration - Production optimized
  allocated_storage     = var.environment == "production" ? 100 : 20
  max_allocated_storage = var.environment == "production" ? 1000 : 100
  storage_type          = var.environment == "production" ? "gp3" : "gp2"
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.rds.arn

  # Database Configuration
  db_name  = "pyairtable_production"
  username = "pyairtable"
  password = random_password.db_password.result

  # Network Configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # High Availability - Multi-AZ for production
  multi_az = var.environment == "production"

  # Backup Configuration - Production grade
  backup_window           = "03:00-04:00"
  backup_retention_period = var.environment == "production" ? 30 : 7
  maintenance_window      = "sun:04:00-sun:05:00"
  
  # Point-in-time recovery
  copy_tags_to_snapshot = true
  final_snapshot_identifier = "${var.project_name}-${var.environment}-db-final-snapshot"

  # Monitoring Configuration
  monitoring_interval                   = var.environment == "production" ? 60 : 0
  monitoring_role_arn                  = var.environment == "production" ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  performance_insights_enabled         = var.environment == "production"
  performance_insights_retention_period = var.environment == "production" ? 7 : 0

  # Security
  deletion_protection = var.environment == "production"
  skip_final_snapshot = var.environment != "production"

  # Parameter group for performance tuning
  parameter_group_name = aws_db_parameter_group.main.name

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-database"
    Backup = "required"
    MonitoringLevel = var.environment == "production" ? "enhanced" : "basic"
  })

  depends_on = [aws_kms_key.rds]
}

# Database Parameter Group for Performance Optimization
resource "aws_db_parameter_group" "main" {
  family = "postgres15"
  name   = "${var.project_name}-${var.environment}-postgres15"

  # Performance optimizations for PyAirtable workload
  parameter {
    name  = "shared_buffers"
    value = var.environment == "production" ? "2GB" : "256MB"
  }

  parameter {
    name  = "effective_cache_size"
    value = var.environment == "production" ? "6GB" : "1GB"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = var.environment == "production" ? "512MB" : "128MB"
  }

  parameter {
    name  = "checkpoint_completion_target"
    value = "0.9"
  }

  parameter {
    name  = "wal_buffers"
    value = "16MB"
  }

  parameter {
    name  = "default_statistics_target"
    value = "100"
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
    value = var.environment == "production" ? "64MB" : "16MB"
  }

  parameter {
    name  = "max_connections"
    value = var.environment == "production" ? "200" : "100"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-params"
  })
}

# KMS Key for RDS Encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-rds-kms"
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# RDS Enhanced Monitoring Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.environment == "production" ? 1 : 0

  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.environment == "production" ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ElastiCache Redis for Session Storage and Caching
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-cache-subnet"
  subnet_ids = module.vpc.private_subnets

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-cache-subnet"
  })
}

resource "aws_security_group" "elasticache" {
  name_prefix = "${var.project_name}-${var.environment}-cache-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Redis from EKS"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [module.security.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-cache-sg"
  })
}

# Redis password
resource "random_password" "redis_password" {
  length  = 32
  special = false
}

# ElastiCache Redis Replication Group for High Availability
resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.project_name}-${var.environment}-redis"
  description                = "Redis cluster for PyAirtable"
  
  # Node configuration
  node_type                  = var.environment == "production" ? "cache.r6g.large" : "cache.t3.micro"
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  # Cluster configuration
  num_cache_clusters         = var.environment == "production" ? 2 : 1
  automatic_failover_enabled = var.environment == "production"
  multi_az_enabled          = var.environment == "production"
  
  # Network configuration
  subnet_group_name = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]
  
  # Security
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_password.result
  
  # Maintenance
  maintenance_window         = "sun:05:00-sun:06:00"
  snapshot_retention_limit   = var.environment == "production" ? 7 : 1
  snapshot_window           = "06:00-07:00"
  
  # Auto backup
  final_snapshot_identifier = "${var.project_name}-${var.environment}-redis-final-snapshot"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-redis"
  })
}

# AWS Secrets Manager for Database Credentials
resource "aws_secretsmanager_secret" "database" {
  name                    = "${var.project_name}/${var.environment}/database"
  description             = "Database credentials for PyAirtable"
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-secret"
  })
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
    database_url = "postgresql://${aws_db_instance.main.username}:${random_password.db_password.result}@${aws_db_instance.main.endpoint}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
    # Connection pooling URL (through PgBouncer)
    pooled_url = "postgresql://${aws_db_instance.main.username}:${random_password.db_password.result}@pgbouncer.${var.project_name}.local:6432/${aws_db_instance.main.db_name}"
  })
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${var.project_name}/${var.environment}/redis"
  description             = "Redis credentials for PyAirtable"
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-redis-secret"
  })
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({
    host      = aws_elasticache_replication_group.main.primary_endpoint_address
    port      = aws_elasticache_replication_group.main.port
    password  = random_password.redis_password.result
    redis_url = "redis://:${random_password.redis_password.result}@${aws_elasticache_replication_group.main.primary_endpoint_address}:${aws_elasticache_replication_group.main.port}"
    # SSL/TLS URL for production
    redis_tls_url = "rediss://:${random_password.redis_password.result}@${aws_elasticache_replication_group.main.primary_endpoint_address}:${aws_elasticache_replication_group.main.port}"
  })
}

# CloudWatch Alarms for Database Monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-db-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors db cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-db-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "120"
  statistic           = "Average"
  threshold           = var.environment == "production" ? "160" : "80"
  alarm_description   = "This metric monitors db connection count"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = local.common_tags
}

# SNS Topic for Database Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-db-alerts"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-alerts"
  })
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count     = length(var.cost_alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.cost_alert_emails[count.index]
}

# Outputs for Kubernetes configuration
output "database_secret_arn" {
  description = "ARN of the database secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.database.arn
}

output "redis_secret_arn" {
  description = "ARN of the Redis secret in AWS Secrets Manager"
  value       = aws_secretsmanager_secret.redis.arn
}

output "database_endpoint" {
  description = "Database endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
}