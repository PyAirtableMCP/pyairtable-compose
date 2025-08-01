# Database Infrastructure
# RDS PostgreSQL and ElastiCache Redis

# Database Subnet Group
resource "aws_db_subnet_group" "main" {
  count = var.enable_rds ? 1 : 0

  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# Database Security Group
resource "aws_security_group" "rds" {
  count = var.enable_rds ? 1 : 0

  name_prefix = "${var.project_name}-${var.environment}-rds-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  count = var.enable_rds ? 1 : 0

  identifier = "${var.project_name}-${var.environment}-db"

  # Engine
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.db_instance_class

  # Storage
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database
  db_name  = "pyairtable"
  username = "pyairtable_user"
  password = random_password.db_password[0].result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main[0].name
  vpc_security_group_ids = [aws_security_group.rds[0].id]
  publicly_accessible    = false

  # Backup
  backup_window           = "03:00-04:00"
  backup_retention_period = var.environment == "prod" ? 7 : 1
  maintenance_window      = "sun:04:00-sun:05:00"

  # Monitoring
  monitoring_interval = var.environment == "prod" ? 60 : 0
  monitoring_role_arn = var.environment == "prod" ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  # Performance Insights
  performance_insights_enabled = var.environment == "prod"

  # Deletion protection
  deletion_protection = var.environment_configs[var.environment].enable_deletion_protection
  skip_final_snapshot = var.environment != "prod"

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
  }
}

# Random password for database
resource "random_password" "db_password" {
  count = var.enable_rds ? 1 : 0

  length  = 16
  special = true
}

# Store database password in Systems Manager Parameter Store
resource "aws_ssm_parameter" "db_password" {
  count = var.enable_rds ? 1 : 0

  name  = "/pyairtable/${var.environment}/db-password"
  type  = "SecureString"
  value = random_password.db_password[0].result

  tags = {
    Name = "${var.project_name}-${var.environment}-db-password"
  }
}

# Store database URL in Systems Manager Parameter Store
resource "aws_ssm_parameter" "database_url" {
  count = var.enable_rds ? 1 : 0

  name  = "/pyairtable/${var.environment}/database-url"
  type  = "SecureString"
  value = "postgresql://${aws_db_instance.main[0].username}:${random_password.db_password[0].result}@${aws_db_instance.main[0].endpoint}/${aws_db_instance.main[0].db_name}"

  tags = {
    Name = "${var.project_name}-${var.environment}-database-url"
  }
}

# RDS Enhanced Monitoring Role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.enable_rds && var.environment == "prod" ? 1 : 0

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
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.enable_rds && var.environment == "prod" ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  count = var.enable_elasticache ? 1 : 0

  name       = "${var.project_name}-${var.environment}-cache-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-subnet"
  }
}

# ElastiCache Security Group
resource "aws_security_group" "elasticache" {
  count = var.enable_elasticache ? 1 : 0

  name_prefix = "${var.project_name}-${var.environment}-cache-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from ECS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cache-sg"
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_cluster" "main" {
  count = var.enable_elasticache ? 1 : 0

  cluster_id           = "${var.project_name}-${var.environment}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_cache_nodes
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main[0].name
  security_group_ids   = [aws_security_group.elasticache[0].id]

  tags = {
    Name = "${var.project_name}-${var.environment}-redis"
  }
}

# Random password for Redis
resource "random_password" "redis_password" {
  count = var.enable_elasticache ? 1 : 0

  length  = 16
  special = false
}

# Store Redis URL in Systems Manager Parameter Store
resource "aws_ssm_parameter" "redis_url" {
  count = var.enable_elasticache ? 1 : 0

  name  = "/pyairtable/${var.environment}/redis-url"
  type  = "SecureString"
  value = "redis://${aws_elasticache_cluster.main[0].cluster_address}:${aws_elasticache_cluster.main[0].port}"

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-url"
  }
}

# Store Redis password in Systems Manager Parameter Store
resource "aws_ssm_parameter" "redis_password" {
  count = var.enable_elasticache ? 1 : 0

  name  = "/pyairtable/${var.environment}/redis-password"
  type  = "SecureString"
  value = random_password.redis_password[0].result

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-password"
  }
}