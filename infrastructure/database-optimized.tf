# Optimized Database Infrastructure for PyAirtable
# Cost-effective RDS Aurora Serverless v2 with intelligent scaling

# RDS Subnet Group
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-${var.environment}-postgres-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-postgres-subnet-group"
    Environment = var.environment
  }
}

# Security Group for RDS
resource "aws_security_group" "postgres" {
  name_prefix = "${var.project_name}-${var.environment}-postgres-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.pyairtable.vpc_config[0].cluster_security_group_id]
  }

  ingress {
    description     = "PostgreSQL from Lambda"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-postgres-sg"
  }
}

# RDS Aurora Serverless v2 Cluster (PostgreSQL)
resource "aws_rds_cluster" "postgres" {
  cluster_identifier      = "${var.project_name}-${var.environment}-postgres"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  engine_mode           = "provisioned"
  database_name         = var.postgres_db_name
  master_username       = var.postgres_username
  master_password       = var.postgres_password
  
  # Serverless v2 scaling configuration
  serverlessv2_scaling_configuration {
    max_capacity = var.environment == "prod" ? 16 : 4
    min_capacity = 0.5  # Very cost effective for low usage
  }

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  # Backup configuration
  backup_retention_period = var.environment == "prod" ? 30 : 7
  preferred_backup_window = "03:00-04:00"

  # Maintenance
  preferred_maintenance_window = "sun:04:00-sun:05:00"

  # Encryption
  storage_encrypted = true
  kms_key_id       = aws_kms_key.rds.arn

  # Performance monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]
  monitoring_interval            = 60
  monitoring_role_arn           = aws_iam_role.rds_monitoring.arn

  # Deletion protection
  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${var.project_name}-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Apply changes immediately in non-prod
  apply_immediately = var.environment != "prod"

  tags = {
    Name        = "${var.project_name}-postgres-cluster"
    Environment = var.environment
  }
}

# Aurora Serverless v2 Instance
resource "aws_rds_cluster_instance" "postgres" {
  identifier          = "${var.project_name}-${var.environment}-postgres-1"
  cluster_identifier  = aws_rds_cluster.postgres.id
  instance_class      = "db.serverless"
  engine             = aws_rds_cluster.postgres.engine
  engine_version     = aws_rds_cluster.postgres.engine_version

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn         = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "${var.project_name}-postgres-instance"
    Environment = var.environment
  }
}

# Read replica for read-heavy workloads (optional, only in prod)
resource "aws_rds_cluster_instance" "postgres_reader" {
  count = var.environment == "prod" ? 1 : 0
  
  identifier          = "${var.project_name}-${var.environment}-postgres-reader-1"
  cluster_identifier  = aws_rds_cluster.postgres.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.postgres.engine
  engine_version     = aws_rds_cluster.postgres.engine_version

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn         = aws_iam_role.rds_monitoring.arn

  tags = {
    Name        = "${var.project_name}-postgres-reader"
    Environment = var.environment
  }
}

# KMS Key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-rds-encryption"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds-encryption"
  target_key_id = aws_kms_key.rds.key_id
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
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

  tags = {
    Name = "${var.project_name}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ElastiCache Redis for session storage and caching
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-${var.environment}-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-redis-subnet-group"
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.project_name}-${var.environment}-redis-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from EKS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.pyairtable.vpc_config[0].cluster_security_group_id]
  }

  ingress {
    description     = "Redis from Lambda"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redis-sg"
  }
}

# ElastiCache Redis Replication Group
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id         = "${var.project_name}-${var.environment}-redis"
  description                  = "Redis cluster for PyAirtable"
  
  node_type                   = "cache.t3.micro"  # Cost-effective for development
  port                        = 6379
  parameter_group_name        = "default.redis7"
  
  num_cache_clusters          = 2
  automatic_failover_enabled  = true
  multi_az_enabled           = var.environment == "prod"
  
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                = var.redis_auth_token
  
  # Backup
  snapshot_retention_limit = var.environment == "prod" ? 7 : 1
  snapshot_window         = "03:00-05:00"
  
  # Maintenance
  maintenance_window = "sun:05:00-sun:07:00"
  
  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  tags = {
    Name        = "${var.project_name}-redis"
    Environment = var.environment
  }
}

# Database parameter store for connection strings
resource "aws_ssm_parameter" "db_connection_string" {
  name  = "/${var.project_name}/${var.environment}/database/connection-string"
  type  = "SecureString"
  value = "postgresql://${var.postgres_username}:${var.postgres_password}@${aws_rds_cluster.postgres.endpoint}:5432/${var.postgres_db_name}?sslmode=require"

  tags = {
    Name        = "${var.project_name}-db-connection"
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "db_read_connection_string" {
  count = var.environment == "prod" ? 1 : 0
  name  = "/${var.project_name}/${var.environment}/database/read-connection-string"
  type  = "SecureString"
  value = "postgresql://${var.postgres_username}:${var.postgres_password}@${aws_rds_cluster.postgres.reader_endpoint}:5432/${var.postgres_db_name}?sslmode=require"

  tags = {
    Name        = "${var.project_name}-db-read-connection"
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "redis_connection_string" {
  name  = "/${var.project_name}/${var.environment}/redis/connection-string"
  type  = "SecureString"
  value = "rediss://:${var.redis_auth_token}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"

  tags = {
    Name        = "${var.project_name}-redis-connection"
    Environment = var.environment
  }
}

# CloudWatch alarms for database monitoring
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-database-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.postgres.cluster_identifier
  }

  tags = {
    Name = "${var.project_name}-database-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.project_name}-${var.environment}-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.postgres.cluster_identifier
  }

  tags = {
    Name = "${var.project_name}-database-connections-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "${var.project_name}-${var.environment}-redis-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors Redis CPU utilization"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    CacheClusterId = "${aws_elasticache_replication_group.redis.replication_group_id}-001"
  }

  tags = {
    Name = "${var.project_name}-redis-cpu-alarm"
  }
}

# Outputs
output "postgres_cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = aws_rds_cluster.postgres.endpoint
  sensitive   = true
}

output "postgres_reader_endpoint" {
  description = "Aurora reader endpoint"
  value       = aws_rds_cluster.postgres.reader_endpoint
  sensitive   = true
}

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive   = true
}