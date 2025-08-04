# Multi-Region Architecture for PyAirtable
# Active-Passive deployment with event replication and disaster recovery

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ==============================================================================
# PROVIDER CONFIGURATION FOR MULTI-REGION
# ==============================================================================

# Primary region provider (us-east-1)
provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Region      = "primary"
    }
  }
}

# Secondary region provider (us-west-2) for DR
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Region      = "secondary"
    }
  }
}

# ==============================================================================
# GLOBAL INFRASTRUCTURE
# ==============================================================================

# Route 53 Hosted Zone
resource "aws_route53_zone" "primary" {
  provider = aws.primary
  name     = var.domain_name

  tags = {
    Name = "${var.project_name}-zone"
  }
}

# Route 53 Health Checks
resource "aws_route53_health_check" "primary_region" {
  provider                            = aws.primary
  fqdn                               = "api.${var.domain_name}"
  port                               = 443
  type                               = "HTTPS"
  resource_path                      = "/health"
  failure_threshold                  = "3"
  request_interval                   = "30"
  cloudwatch_alarm_region           = var.primary_region
  cloudwatch_alarm_name             = "${var.project_name}-primary-health"
  insufficient_data_health_status    = "Failure"

  tags = {
    Name = "${var.project_name}-primary-health-check"
  }
}

resource "aws_route53_health_check" "secondary_region" {
  provider                            = aws.primary
  fqdn                               = "api-dr.${var.domain_name}"
  port                               = 443
  type                               = "HTTPS"
  resource_path                      = "/health"
  failure_threshold                  = "3"
  request_interval                   = "30"
  cloudwatch_alarm_region           = var.secondary_region
  cloudwatch_alarm_name             = "${var.project_name}-secondary-health"
  insufficient_data_health_status    = "Failure"

  tags = {
    Name = "${var.project_name}-secondary-health-check"
  }
}

# Route 53 DNS Records with Failover
resource "aws_route53_record" "api_primary" {
  provider = aws.primary
  zone_id  = aws_route53_zone.primary.zone_id
  name     = "api.${var.domain_name}"
  type     = "A"

  set_identifier = "primary"
  
  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary_region.id

  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api_secondary" {
  provider = aws.primary
  zone_id  = aws_route53_zone.primary.zone_id
  name     = "api.${var.domain_name}"
  type     = "A"

  set_identifier = "secondary"
  
  failover_routing_policy {
    type = "SECONDARY"
  }

  health_check_id = aws_route53_health_check.secondary_region.id

  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
}

# ==============================================================================
# PRIMARY REGION INFRASTRUCTURE
# ==============================================================================

# VPC in Primary Region
resource "aws_vpc" "primary" {
  provider             = aws.primary
  cidr_block           = var.primary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-vpc"
  }
}

# Internet Gateway - Primary
resource "aws_internet_gateway" "primary" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary.id

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-igw"
  }
}

# Subnets - Primary Region
resource "aws_subnet" "primary_public" {
  provider  = aws.primary
  count     = 3
  vpc_id    = aws_vpc.primary.id
  cidr_block = cidrsubnet(var.primary_vpc_cidr, 8, count.index)
  
  availability_zone       = data.aws_availability_zones.primary.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-public-${count.index + 1}"
    Type = "Public"
  }
}

resource "aws_subnet" "primary_private" {
  provider  = aws.primary
  count     = 3
  vpc_id    = aws_vpc.primary.id
  cidr_block = cidrsubnet(var.primary_vpc_cidr, 8, count.index + 3)
  
  availability_zone = data.aws_availability_zones.primary.names[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-private-${count.index + 1}"
    Type = "Private"
  }
}

# NAT Gateways - Primary
resource "aws_eip" "primary_nat" {
  provider = aws.primary
  count    = 3
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.primary]
}

resource "aws_nat_gateway" "primary" {
  provider      = aws.primary
  count         = 3
  allocation_id = aws_eip.primary_nat[count.index].id
  subnet_id     = aws_subnet.primary_public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-nat-gateway-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.primary]
}

# Route Tables - Primary
resource "aws_route_table" "primary_public" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-public-rt"
  }
}

resource "aws_route_table" "primary_private" {
  provider = aws.primary
  count    = 3
  vpc_id   = aws_vpc.primary.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.primary[count.index].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-private-rt-${count.index + 1}"
  }
}

# Route Table Associations - Primary
resource "aws_route_table_association" "primary_public" {
  provider       = aws.primary
  count          = 3
  subnet_id      = aws_subnet.primary_public[count.index].id
  route_table_id = aws_route_table.primary_public.id
}

resource "aws_route_table_association" "primary_private" {
  provider       = aws.primary
  count          = 3
  subnet_id      = aws_subnet.primary_private[count.index].id
  route_table_id = aws_route_table.primary_private[count.index].id
}

# Load Balancer - Primary
resource "aws_lb" "primary" {
  provider           = aws.primary
  name               = "${var.project_name}-${var.environment}-primary-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.primary_alb.id]
  subnets            = aws_subnet.primary_public[*].id

  enable_deletion_protection = var.environment == "prod"

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-alb"
  }
}

# Security Group for Primary ALB
resource "aws_security_group" "primary_alb" {
  provider    = aws.primary
  name_prefix = "${var.project_name}-${var.environment}-primary-alb-"
  vpc_id      = aws_vpc.primary.id

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
    Name = "${var.project_name}-${var.environment}-primary-alb-sg"
  }
}

# ==============================================================================
# SECONDARY REGION INFRASTRUCTURE (DR)
# ==============================================================================

# VPC in Secondary Region
resource "aws_vpc" "secondary" {
  provider             = aws.secondary
  cidr_block           = var.secondary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-vpc"
  }
}

# Internet Gateway - Secondary
resource "aws_internet_gateway" "secondary" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary.id

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-igw"
  }
}

# Subnets - Secondary Region
resource "aws_subnet" "secondary_public" {
  provider  = aws.secondary
  count     = 3
  vpc_id    = aws_vpc.secondary.id
  cidr_block = cidrsubnet(var.secondary_vpc_cidr, 8, count.index)
  
  availability_zone       = data.aws_availability_zones.secondary.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-public-${count.index + 1}"
    Type = "Public"
  }
}

resource "aws_subnet" "secondary_private" {
  provider  = aws.secondary
  count     = 3
  vpc_id    = aws_vpc.secondary.id
  cidr_block = cidrsubnet(var.secondary_vpc_cidr, 8, count.index + 3)
  
  availability_zone = data.aws_availability_zones.secondary.names[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-private-${count.index + 1}"
    Type = "Private"
  }
}

# NAT Gateways - Secondary
resource "aws_eip" "secondary_nat" {
  provider = aws.secondary
  count    = 3
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.secondary]
}

resource "aws_nat_gateway" "secondary" {
  provider      = aws.secondary
  count         = 3
  allocation_id = aws_eip.secondary_nat[count.index].id
  subnet_id     = aws_subnet.secondary_public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-nat-gateway-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.secondary]
}

# Route Tables - Secondary
resource "aws_route_table" "secondary_public" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-public-rt"
  }
}

resource "aws_route_table" "secondary_private" {
  provider = aws.secondary
  count    = 3
  vpc_id   = aws_vpc.secondary.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.secondary[count.index].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-private-rt-${count.index + 1}"
  }
}

# Route Table Associations - Secondary
resource "aws_route_table_association" "secondary_public" {
  provider       = aws.secondary
  count          = 3
  subnet_id      = aws_subnet.secondary_public[count.index].id
  route_table_id = aws_route_table.secondary_public.id
}

resource "aws_route_table_association" "secondary_private" {
  provider       = aws.secondary
  count          = 3
  subnet_id      = aws_subnet.secondary_private[count.index].id
  route_table_id = aws_route_table.secondary_private[count.index].id
}

# Load Balancer - Secondary
resource "aws_lb" "secondary" {
  provider           = aws.secondary
  name               = "${var.project_name}-${var.environment}-secondary-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.secondary_alb.id]
  subnets            = aws_subnet.secondary_public[*].id

  enable_deletion_protection = var.environment == "prod"

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-alb"
  }
}

# Security Group for Secondary ALB
resource "aws_security_group" "secondary_alb" {
  provider    = aws.secondary
  name_prefix = "${var.project_name}-${var.environment}-secondary-alb-"
  vpc_id      = aws_vpc.secondary.id

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
    Name = "${var.project_name}-${var.environment}-secondary-alb-sg"
  }
}

# ==============================================================================
# DATABASE WITH CROSS-REGION REPLICATION
# ==============================================================================

# Primary RDS Instance
resource "aws_db_instance" "primary" {
  provider = aws.primary
  
  identifier     = "${var.project_name}-${var.environment}-primary"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.environment == "prod" ? "db.r6g.xlarge" : "db.t3.medium"

  allocated_storage     = var.environment == "prod" ? 500 : 100
  max_allocated_storage = var.environment == "prod" ? 1000 : 200
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  vpc_security_group_ids = [aws_security_group.primary_rds.id]
  db_subnet_group_name   = aws_db_subnet_group.primary.name

  # Backup and maintenance
  backup_retention_period = var.environment == "prod" ? 30 : 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  # High availability for production
  multi_az = var.environment == "prod"

  # Enhanced monitoring
  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring.arn

  # Cross-region automated backups
  backup_target = "region"

  # Deletion protection
  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-db"
  }
}

# Read Replica in Secondary Region
resource "aws_db_instance" "secondary_replica" {
  provider = aws.secondary
  
  identifier                = "${var.project_name}-${var.environment}-secondary-replica"
  replicate_source_db       = aws_db_instance.primary.arn
  instance_class            = var.environment == "prod" ? "db.r6g.large" : "db.t3.small"
  
  vpc_security_group_ids = [aws_security_group.secondary_rds.id]
  
  # Enhanced monitoring
  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.secondary_rds_enhanced_monitoring.arn

  skip_final_snapshot = true
  
  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-replica"
  }
}

# DB Subnet Groups
resource "aws_db_subnet_group" "primary" {
  provider   = aws.primary
  name       = "${var.project_name}-${var.environment}-primary-db-subnet-group"
  subnet_ids = aws_subnet.primary_private[*].id

  tags = {
    Name = "${var.project_name}-primary-db-subnet-group"
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${var.project_name}-${var.environment}-secondary-db-subnet-group"
  subnet_ids = aws_subnet.secondary_private[*].id

  tags = {
    Name = "${var.project_name}-secondary-db-subnet-group"
  }
}

# Security Groups for RDS
resource "aws_security_group" "primary_rds" {
  provider    = aws.primary
  name_prefix = "${var.project_name}-${var.environment}-primary-rds-"
  vpc_id      = aws_vpc.primary.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.primary.cidr_block]
  }

  # Allow cross-region replication
  ingress {
    description = "PostgreSQL from secondary region"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-rds-sg"
  }
}

resource "aws_security_group" "secondary_rds" {
  provider    = aws.secondary
  name_prefix = "${var.project_name}-${var.environment}-secondary-rds-"
  vpc_id      = aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.secondary.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-rds-sg"
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  provider = aws.primary
  name     = "${var.project_name}-${var.environment}-rds-enhanced-monitoring"

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
  provider   = aws.primary
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_iam_role" "secondary_rds_enhanced_monitoring" {
  provider = aws.secondary
  name     = "${var.project_name}-${var.environment}-secondary-rds-enhanced-monitoring"

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

resource "aws_iam_role_policy_attachment" "secondary_rds_enhanced_monitoring" {
  provider   = aws.secondary
  role       = aws_iam_role.secondary_rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ==============================================================================
# KAFKA CROSS-REGION REPLICATION
# ==============================================================================

# Primary MSK Cluster
resource "aws_msk_cluster" "primary" {
  provider                   = aws.primary
  cluster_name               = "${var.project_name}-${var.environment}-primary-kafka"
  kafka_version              = "3.5.1"
  number_of_broker_nodes     = var.environment == "prod" ? 6 : 3

  broker_node_group_info {
    instance_type   = var.environment == "prod" ? "kafka.m5.xlarge" : "kafka.m5.large"
    ebs_volume_size = var.environment == "prod" ? 1000 : 500
    client_subnets  = aws_subnet.primary_private[*].id
    security_groups = [aws_security_group.primary_kafka.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-kafka"
  }
}

# Secondary MSK Cluster for DR
resource "aws_msk_cluster" "secondary" {
  provider                   = aws.secondary
  cluster_name               = "${var.project_name}-${var.environment}-secondary-kafka"
  kafka_version              = "3.5.1"
  number_of_broker_nodes     = var.environment == "prod" ? 3 : 2

  broker_node_group_info {
    instance_type   = var.environment == "prod" ? "kafka.m5.large" : "kafka.m5.medium"
    ebs_volume_size = var.environment == "prod" ? 500 : 250
    client_subnets  = aws_subnet.secondary_private[*].id
    security_groups = [aws_security_group.secondary_kafka.id]
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-kafka"
  }
}

# Security Groups for Kafka
resource "aws_security_group" "primary_kafka" {
  provider    = aws.primary
  name_prefix = "${var.project_name}-${var.environment}-primary-kafka-"
  vpc_id      = aws_vpc.primary.id

  ingress {
    description = "Kafka broker communication"
    from_port   = 9092
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.primary.cidr_block]
  }

  # Allow cross-region replication
  ingress {
    description = "Kafka cross-region replication"
    from_port   = 9092
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  ingress {
    description = "ZooKeeper communication"
    from_port   = 2181
    to_port     = 2188
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.primary.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-kafka-sg"
  }
}

resource "aws_security_group" "secondary_kafka" {
  provider    = aws.secondary
  name_prefix = "${var.project_name}-${var.environment}-secondary-kafka-"
  vpc_id      = aws_vpc.secondary.id

  ingress {
    description = "Kafka broker communication"
    from_port   = 9092
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.secondary.cidr_block]
  }

  ingress {
    description = "ZooKeeper communication"
    from_port   = 2181
    to_port     = 2188
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.secondary.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-kafka-sg"
  }
}

# ==============================================================================
# VPC PEERING FOR CROSS-REGION COMMUNICATION
# ==============================================================================

# VPC Peering Connection
resource "aws_vpc_peering_connection" "primary_to_secondary" {
  provider    = aws.primary
  vpc_id      = aws_vpc.primary.id
  peer_vpc_id = aws_vpc.secondary.id
  peer_region = var.secondary_region
  auto_accept = false

  tags = {
    Name = "${var.project_name}-${var.environment}-primary-to-secondary-peering"
  }
}

# Accept the peering connection in the secondary region
resource "aws_vpc_peering_connection_accepter" "secondary" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
  auto_accept               = true

  tags = {
    Name = "${var.project_name}-${var.environment}-secondary-peering-accepter"
  }
}

# Route table entries for VPC peering
resource "aws_route" "primary_to_secondary" {
  provider                  = aws.primary
  count                     = 3
  route_table_id            = aws_route_table.primary_private[count.index].id
  destination_cidr_block    = var.secondary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
}

resource "aws_route" "secondary_to_primary" {
  provider                  = aws.secondary
  count                     = 3
  route_table_id            = aws_route_table.secondary_private[count.index].id
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
}

# ==============================================================================
# S3 CROSS-REGION REPLICATION
# ==============================================================================

# S3 Bucket in Primary Region
resource "aws_s3_bucket" "primary" {
  provider = aws.primary
  bucket   = "${var.project_name}-${var.environment}-primary-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-primary-bucket"
  }
}

# S3 Bucket in Secondary Region
resource "aws_s3_bucket" "secondary" {
  provider = aws.secondary
  bucket   = "${var.project_name}-${var.environment}-secondary-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-secondary-bucket"
  }
}

# Enable versioning for replication
resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "secondary" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.secondary.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Cross-region replication configuration
resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider   = aws.primary
  role       = aws_iam_role.s3_replication.arn
  bucket     = aws_s3_bucket.primary.id
  depends_on = [aws_s3_bucket_versioning.primary]

  rule {
    id     = "replicate-to-secondary"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.secondary.arn
      storage_class = "STANDARD_IA"
    }
  }
}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication" {
  provider = aws.primary
  name     = "${var.project_name}-${var.environment}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "s3_replication" {
  provider = aws.primary
  name     = "${var.project_name}-${var.environment}-s3-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.primary.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.primary.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.secondary.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_replication" {
  provider   = aws.primary
  role       = aws_iam_role.s3_replication.name
  policy_arn = aws_iam_policy.s3_replication.arn
}

# ==============================================================================
# DISASTER RECOVERY AUTOMATION
# ==============================================================================

# Lambda function for DR orchestration
resource "aws_lambda_function" "dr_orchestrator" {
  provider         = aws.primary
  filename         = "dr_orchestrator.zip"
  function_name    = "${var.project_name}-${var.environment}-dr-orchestrator"
  role            = aws_iam_role.dr_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 900

  environment {
    variables = {
      PRIMARY_REGION   = var.primary_region
      SECONDARY_REGION = var.secondary_region
      CLUSTER_NAME     = "${var.project_name}-${var.environment}"
      RDS_IDENTIFIER   = aws_db_instance.primary.identifier
    }
  }

  tags = {
    Name = "${var.project_name}-dr-orchestrator"
  }
}

# IAM role for DR Lambda
resource "aws_iam_role" "dr_lambda" {
  provider = aws.primary
  name     = "${var.project_name}-${var.environment}-dr-lambda-role"

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
}

resource "aws_iam_policy" "dr_lambda" {
  provider = aws.primary
  name     = "${var.project_name}-${var.environment}-dr-lambda-policy"

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
          "rds:PromoteReadReplica",
          "rds:CreateDBSnapshot",
          "rds:DescribeDBSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:UpdateClusterConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHealthCheck",
          "route53:UpdateHealthCheck"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dr_lambda" {
  provider   = aws.primary
  role       = aws_iam_role.dr_lambda.name
  policy_arn = aws_iam_policy.dr_lambda.arn
}

# CloudWatch alarm for triggering DR
resource "aws_cloudwatch_metric_alarm" "primary_region_failure" {
  provider            = aws.primary
  alarm_name          = "${var.project_name}-${var.environment}-primary-region-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors primary region health"
  alarm_actions       = [aws_lambda_function.dr_orchestrator.arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary_region.id
  }

  tags = {
    Name = "${var.project_name}-primary-region-failure-alarm"
  }
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

data "aws_caller_identity" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ==============================================================================
# VARIABLES
# ==============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pyairtable"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for DR"
  type        = string
  default     = "us-west-2"
}

variable "primary_vpc_cidr" {
  description = "CIDR block for primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for secondary VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "pyairtable.com"
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "pyairtable"
}

variable "database_username" {
  description = "Database username"
  type        = string
  default     = "admin"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "multi_region_infrastructure" {
  description = "Multi-region infrastructure details"
  value = {
    primary_region = {
      vpc_id         = aws_vpc.primary.id
      vpc_cidr       = aws_vpc.primary.cidr_block
      public_subnets = aws_subnet.primary_public[*].id
      private_subnets = aws_subnet.primary_private[*].id
      alb_dns        = aws_lb.primary.dns_name
      rds_endpoint   = aws_db_instance.primary.endpoint
      kafka_endpoint = aws_msk_cluster.primary.bootstrap_brokers
    }
    
    secondary_region = {
      vpc_id         = aws_vpc.secondary.id
      vpc_cidr       = aws_vpc.secondary.cidr_block
      public_subnets = aws_subnet.secondary_public[*].id
      private_subnets = aws_subnet.secondary_private[*].id
      alb_dns        = aws_lb.secondary.dns_name
      rds_endpoint   = aws_db_instance.secondary_replica.endpoint
      kafka_endpoint = aws_msk_cluster.secondary.bootstrap_brokers
    }
    
    global = {
      domain_name     = var.domain_name
      hosted_zone_id  = aws_route53_zone.primary.zone_id
      s3_primary      = aws_s3_bucket.primary.bucket
      s3_secondary    = aws_s3_bucket.secondary.bucket
    }
  }
  sensitive = false
}

output "disaster_recovery" {
  description = "Disaster recovery configuration"
  value = {
    dr_lambda_function = aws_lambda_function.dr_orchestrator.function_name
    health_checks = {
      primary   = aws_route53_health_check.primary_region.id
      secondary = aws_route53_health_check.secondary_region.id
    }
    failover_alarm = aws_cloudwatch_metric_alarm.primary_region_failure.alarm_name
  }
}

output "cost_estimation" {
  description = "Monthly cost estimation for multi-region setup (USD)"
  value = {
    primary_region = {
      vpc_nat_gateways = "135"     # 3 NAT gateways * $45/month
      alb             = "22"       # Application Load Balancer
      rds_primary     = var.environment == "prod" ? "720" : "180"  # RDS instance
      msk_cluster     = var.environment == "prod" ? "782" : "262"  # Kafka cluster
      s3_storage      = "25"       # S3 storage and requests
      data_transfer   = "100"      # Cross-region transfer
      total           = var.environment == "prod" ? "1784" : "724"
    }
    
    secondary_region = {
      vpc_nat_gateways = "135"     # 3 NAT gateways * $45/month
      alb             = "22"       # Application Load Balancer
      rds_replica     = var.environment == "prod" ? "360" : "90"   # Read replica
      msk_cluster     = var.environment == "prod" ? "391" : "131"  # Smaller Kafka cluster
      s3_storage      = "15"       # S3 storage (replicated data)
      lambda_dr       = "5"        # DR orchestration Lambda
      route53         = "5"        # Health checks and DNS
      total           = var.environment == "prod" ? "933" : "398"
    }
    
    global_services = {
      route53_zone        = "0.50"     # Hosted zone
      route53_queries     = "20"       # DNS queries
      cloudwatch_alarms   = "2"        # Health check alarms
      vpc_peering         = "0"        # No additional cost
      total              = "22.50"
    }
    
    total_monthly = var.environment == "prod" ? "2739.50" : "1144.50"
    
    cost_breakdown = {
      networking      = "17%"
      databases       = "39%"
      compute_kafka   = "36%"
      storage         = "4%"
      monitoring      = "2%"
      dns_failover    = "2%"
    }
  }
}