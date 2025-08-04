# Regional Infrastructure Module
# This module deploys infrastructure for a single region

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

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name   = "${var.project_name}-${var.environment}-${var.region}-vpc"
    Region = var.region
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-igw"
  }
}

# Public Subnets (3 AZs for high availability)
resource "aws_subnet" "public" {
  count = min(length(var.availability_zones), 3)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-public-${count.index + 1}"
    Type = "Public"
    Tier = "Public"
  }
}

# Private Subnets (3 AZs for high availability)
resource "aws_subnet" "private" {
  count = min(length(var.availability_zones), 3)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-private-${count.index + 1}"
    Type = "Private"
    Tier = "Application"
  }
}

# Database Subnets (3 AZs for high availability)
resource "aws_subnet" "database" {
  count = min(length(var.availability_zones), 3)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-database-${count.index + 1}"
    Type = "Database"
    Tier = "Database"
  }
}

# NAT Gateways (One per AZ for HA)
resource "aws_eip" "nat" {
  count  = min(length(var.availability_zones), 3)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = min(length(var.availability_zones), 3)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-nat-gateway-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-public-rt"
  }
}

resource "aws_route_table" "private" {
  count = min(length(var.availability_zones), 3)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-database-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-alb-"
  vpc_id      = aws_vpc.main.id

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
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-ecs-tasks-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-ecs-tasks-sg"
  }
}

resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-database-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-database-sg"
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-redis-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-redis-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-${substr(var.region, -2, -1)}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = var.environment == "prod" ? true : false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-alb"
  }
}

# S3 bucket for ALB access logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project_name}-${var.environment}-${var.region}-alb-logs-${random_string.bucket_suffix.result}"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-alb-logs"
  }
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

data "aws_elb_service_account" "main" {}

# PostgreSQL RDS Instance
resource "aws_db_subnet_group" "main" {
  count = var.enable_rds ? 1 : 0

  name       = "${var.project_name}-${var.environment}-${var.region}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  count = var.enable_rds && var.is_primary_region ? 1 : 0

  identifier     = "${var.project_name}-${var.environment}-${var.region}-primary"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.db_instance_class
  
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 5
  storage_type         = "gp3"
  storage_encrypted    = true

  db_name  = "${var.project_name}_${var.environment}"
  username = "pyairtable_admin"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.main[0].name

  backup_retention_period = 30
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_monitoring.arn

  deletion_protection = var.environment == "prod" ? true : false
  skip_final_snapshot = var.environment == "prod" ? false : true

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-primary-db"
  }
}

# Read Replica for secondary regions
resource "aws_db_instance" "replica" {
  count = var.enable_rds && !var.is_primary_region && var.primary_db_identifier != "" ? 1 : 0

  identifier             = "${var.project_name}-${var.environment}-${var.region}-replica"
  replicate_source_db    = var.primary_db_identifier
  instance_class         = var.db_instance_class
  
  vpc_security_group_ids = [aws_security_group.database.id]

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_monitoring.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-replica-db"
  }
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-${var.region}-rds-monitoring-role"

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

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ElastiCache Redis Cluster
resource "aws_elasticache_subnet_group" "main" {
  count = var.enable_elasticache ? 1 : 0

  name       = "${var.project_name}-${var.environment}-${var.region}-cache-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-cache-subnet-group"
  }
}

resource "aws_elasticache_replication_group" "main" {
  count = var.enable_elasticache ? 1 : 0

  replication_group_id         = "${var.project_name}-${var.environment}-${substr(var.region, -2, -1)}"
  description                  = "Redis cluster for ${var.project_name} ${var.environment} in ${var.region}"
  
  node_type                   = var.redis_node_type
  port                        = 6379
  parameter_group_name        = "default.redis7"
  
  num_cache_clusters          = var.redis_num_cache_nodes
  automatic_failover_enabled  = var.redis_num_cache_nodes > 1
  multi_az_enabled           = var.redis_num_cache_nodes > 1
  
  subnet_group_name          = aws_elasticache_subnet_group.main[0].name
  security_group_ids         = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                = random_password.redis_auth_token.result

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis.name
    destination_type = "cloudwatch-logs"
    log_format      = "text"
    log_type        = "slow-log"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-redis"
  }
}

resource "random_password" "redis_auth_token" {
  length  = 32
  special = false
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/elasticache/${var.project_name}-${var.environment}-${var.region}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-redis-logs"
  }
}

# EKS Cluster for container orchestration
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-eks-cluster-"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-eks-cluster-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-${var.region}-eks-nodes-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic from cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "HTTPS from cluster"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-eks-nodes-sg"
  }
}

# EKS service role
resource "aws_iam_role" "eks_service_role" {
  name = "${var.project_name}-${var.environment}-${var.region}-eks-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_service_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-${var.region}"
  role_arn = aws_iam_role.eks_service_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-eks"
  }
}

resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key for ${var.project_name}-${var.environment}-${var.region}"
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-eks-key"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-${var.environment}-${var.region}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.project_name}-${var.environment}-${var.region}/cluster"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-eks-logs"
  }
}

# EKS Node Group
resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-${var.environment}-${var.region}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-${var.region}-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  capacity_type  = "ON_DEMAND"
  instance_types = ["m5.large", "m5.xlarge"]

  scaling_config {
    desired_size = var.environment == "prod" ? 3 : 2
    max_size     = var.environment == "prod" ? 10 : 4
    min_size     = var.environment == "prod" ? 2 : 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-node-group"
  }
}

# CloudWatch Log Groups for services
resource "aws_cloudwatch_log_group" "services" {
  for_each = toset(var.services)

  name              = "/ecs/${var.project_name}-${var.environment}-${var.region}-${each.key}"
  retention_in_days = 30

  tags = {
    Name    = "${var.project_name}-${var.environment}-${var.region}-${each.key}-logs"
    Service = each.key
  }
}

# Secrets Manager for storing sensitive data
resource "aws_secretsmanager_secret" "database" {
  count = var.enable_rds ? 1 : 0

  name        = "${var.project_name}/${var.environment}/${var.region}/database"
  description = "Database credentials for ${var.project_name}"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-database-secret"
  }
}

resource "aws_secretsmanager_secret_version" "database" {
  count = var.enable_rds ? 1 : 0

  secret_id = aws_secretsmanager_secret.database[0].id
  secret_string = jsonencode({
    username = "pyairtable_admin"
    password = random_password.db_password.result
    host     = var.is_primary_region ? aws_db_instance.main[0].endpoint : aws_db_instance.replica[0].endpoint
    port     = 5432
    dbname   = "${var.project_name}_${var.environment}"
  })
}

resource "aws_secretsmanager_secret" "redis" {
  count = var.enable_elasticache ? 1 : 0

  name        = "${var.project_name}/${var.environment}/${var.region}/redis"
  description = "Redis credentials for ${var.project_name}"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-redis-secret"
  }
}

resource "aws_secretsmanager_secret_version" "redis" {
  count = var.enable_elasticache ? 1 : 0

  secret_id = aws_secretsmanager_secret.redis[0].id
  secret_string = jsonencode({
    host     = aws_elasticache_replication_group.main[0].configuration_endpoint_address
    port     = 6379
    auth_token = random_password.redis_auth_token.result
  })
}

# Route53 health check for this region
resource "aws_route53_health_check" "main" {
  fqdn                            = "${var.region}.${var.domain_name}"
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/health"
  failure_threshold               = "3"
  request_interval                = "30"

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-health-check"
  }
}

# CloudWatch alarms for health monitoring
resource "aws_cloudwatch_metric_alarm" "health_check" {
  alarm_name          = "${var.project_name}-${var.environment}-${var.region}-health-check-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric monitors health check status"
  alarm_actions       = []

  dimensions = {
    HealthCheckId = aws_route53_health_check.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${var.region}-health-alarm"
  }
}