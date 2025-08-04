# Multi-Region Infrastructure for PyAirtable
# Terraform configuration for global deployment across US-East, EU-West, and AP-Southeast

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "pyairtable-terraform-state-global"
    key            = "multi-region/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-global"
  }
}

# Primary Region - US East
provider "aws" {
  alias  = "us_east"
  region = "us-east-1"
  
  default_tags {
    tags = {
      Project      = "PyAirtable"
      Environment  = var.environment
      ManagedBy    = "Terraform"
      Region       = "us-east-1"
      RegionType   = "primary"
    }
  }
}

# Secondary Region - EU West
provider "aws" {
  alias  = "eu_west"
  region = "eu-west-1"
  
  default_tags {
    tags = {
      Project      = "PyAirtable"
      Environment  = var.environment
      ManagedBy    = "Terraform"
      Region       = "eu-west-1"
      RegionType   = "secondary"
    }
  }
}

# Secondary Region - AP Southeast
provider "aws" {
  alias  = "ap_southeast"
  region = "ap-southeast-1"
  
  default_tags {
    tags = {
      Project      = "PyAirtable"
      Environment  = var.environment
      ManagedBy    = "Terraform"
      Region       = "ap-southeast-1"
      RegionType   = "secondary"
    }
  }
}

# Data sources for each region
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "us_east" {
  provider = aws.us_east
  state    = "available"
}

data "aws_availability_zones" "eu_west" {
  provider = aws.eu_west
  state    = "available"
}

data "aws_availability_zones" "ap_southeast" {
  provider = aws.ap_southeast
  state    = "available"
}

# Global resources
resource "aws_route53_zone" "main" {
  provider = aws.us_east
  name     = var.domain_name

  tags = {
    Name = "${var.project_name}-${var.environment}-zone"
  }
}

# US East Region Infrastructure
module "us_east_region" {
  source = "./modules/regional-infrastructure"
  
  providers = {
    aws = aws.us_east
  }

  region                = "us-east-1"
  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = data.aws_availability_zones.us_east.names
  is_primary_region    = true
  
  # Service configurations
  services             = var.services
  service_configs      = var.service_configs
  environment_configs  = var.environment_configs
  
  # Database configuration
  enable_rds          = var.enable_rds
  db_instance_class   = var.db_instance_class_primary
  db_allocated_storage = var.db_allocated_storage
  
  # Redis configuration
  enable_elasticache     = var.enable_elasticache
  redis_node_type       = var.redis_node_type
  redis_num_cache_nodes = var.redis_num_cache_nodes
  
  # Cross-region replication
  cross_region_backup_bucket = aws_s3_bucket.cross_region_backup.id
  
  # Route53 zone
  route53_zone_id = aws_route53_zone.main.zone_id
  domain_name     = var.domain_name
}

# EU West Region Infrastructure
module "eu_west_region" {
  source = "./modules/regional-infrastructure"
  
  providers = {
    aws = aws.eu_west
  }

  region                = "eu-west-1"
  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = "10.1.0.0/16"
  availability_zones   = data.aws_availability_zones.eu_west.names
  is_primary_region    = false
  
  # Service configurations
  services             = var.services
  service_configs      = var.service_configs
  environment_configs  = var.environment_configs
  
  # Database configuration (read replica)
  enable_rds          = var.enable_rds
  db_instance_class   = var.db_instance_class_secondary
  db_allocated_storage = var.db_allocated_storage
  primary_db_identifier = module.us_east_region.db_instance_identifier
  
  # Redis configuration
  enable_elasticache     = var.enable_elasticache
  redis_node_type       = var.redis_node_type
  redis_num_cache_nodes = var.redis_num_cache_nodes
  
  # Cross-region replication
  cross_region_backup_bucket = aws_s3_bucket.cross_region_backup.id
  
  # Route53 zone
  route53_zone_id = aws_route53_zone.main.zone_id
  domain_name     = var.domain_name
  
  # GDPR compliance
  gdpr_compliant = true
  data_residency_region = "eu-west-1"
}

# AP Southeast Region Infrastructure  
module "ap_southeast_region" {
  source = "./modules/regional-infrastructure"
  
  providers = {
    aws = aws.ap_southeast
  }

  region                = "ap-southeast-1"
  environment          = var.environment
  project_name         = var.project_name
  vpc_cidr             = "10.2.0.0/16"
  availability_zones   = data.aws_availability_zones.ap_southeast.names
  is_primary_region    = false
  
  # Service configurations
  services             = var.services
  service_configs      = var.service_configs
  environment_configs  = var.environment_configs
  
  # Database configuration (read replica)
  enable_rds          = var.enable_rds
  db_instance_class   = var.db_instance_class_secondary
  db_allocated_storage = var.db_allocated_storage
  primary_db_identifier = module.us_east_region.db_instance_identifier
  
  # Redis configuration
  enable_elasticache     = var.enable_elasticache
  redis_node_type       = var.redis_node_type
  redis_num_cache_nodes = var.redis_num_cache_nodes
  
  # Cross-region replication
  cross_region_backup_bucket = aws_s3_bucket.cross_region_backup.id
  
  # Route53 zone
  route53_zone_id = aws_route53_zone.main.zone_id
  domain_name     = var.domain_name
}

# Global Cross-Region Resources
resource "aws_s3_bucket" "cross_region_backup" {
  provider = aws.us_east
  bucket   = "${var.project_name}-${var.environment}-cross-region-backup"

  tags = {
    Name = "${var.project_name}-${var.environment}-cross-region-backup"
  }
}

resource "aws_s3_bucket_versioning" "cross_region_backup" {
  provider = aws.us_east
  bucket   = aws_s3_bucket.cross_region_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cross_region_backup" {
  provider = aws.us_east
  bucket   = aws_s3_bucket.cross_region_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Cross-Region Replication for S3
resource "aws_s3_bucket_replication_configuration" "cross_region_backup" {
  provider   = aws.us_east
  depends_on = [aws_s3_bucket_versioning.cross_region_backup]

  role   = aws_iam_role.s3_replication.arn
  bucket = aws_s3_bucket.cross_region_backup.id

  rule {
    id     = "replicate-to-eu"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.eu_backup.arn
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "replicate-to-ap"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.ap_backup.arn
      storage_class = "STANDARD_IA"
    }
  }
}

# EU backup bucket
resource "aws_s3_bucket" "eu_backup" {
  provider = aws.eu_west
  bucket   = "${var.project_name}-${var.environment}-eu-backup"

  tags = {
    Name = "${var.project_name}-${var.environment}-eu-backup"
  }
}

resource "aws_s3_bucket_versioning" "eu_backup" {
  provider = aws.eu_west
  bucket   = aws_s3_bucket.eu_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AP backup bucket
resource "aws_s3_bucket" "ap_backup" {
  provider = aws.ap_southeast
  bucket   = "${var.project_name}-${var.environment}-ap-backup"

  tags = {
    Name = "${var.project_name}-${var.environment}-ap-backup"
  }
}

resource "aws_s3_bucket_versioning" "ap_backup" {
  provider = aws.ap_southeast
  bucket   = aws_s3_bucket.ap_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication" {
  provider = aws.us_east
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
  provider = aws.us_east
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
        Resource = "${aws_s3_bucket.cross_region_backup.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.cross_region_backup.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = [
          "${aws_s3_bucket.eu_backup.arn}/*",
          "${aws_s3_bucket.ap_backup.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_replication" {
  provider   = aws.us_east
  role       = aws_iam_role.s3_replication.name
  policy_arn = aws_iam_policy.s3_replication.arn
}

# VPC Peering for cross-region communication
resource "aws_vpc_peering_connection" "us_to_eu" {
  provider    = aws.us_east
  vpc_id      = module.us_east_region.vpc_id
  peer_vpc_id = module.eu_west_region.vpc_id
  peer_region = "eu-west-1"
  auto_accept = false

  tags = {
    Name = "${var.project_name}-${var.environment}-us-to-eu-peering"
  }
}

resource "aws_vpc_peering_connection_accepter" "us_to_eu" {
  provider                  = aws.eu_west
  vpc_peering_connection_id = aws_vpc_peering_connection.us_to_eu.id
  auto_accept               = true

  tags = {
    Name = "${var.project_name}-${var.environment}-us-to-eu-peering-accepter"
  }
}

resource "aws_vpc_peering_connection" "us_to_ap" {
  provider    = aws.us_east
  vpc_id      = module.us_east_region.vpc_id
  peer_vpc_id = module.ap_southeast_region.vpc_id
  peer_region = "ap-southeast-1"
  auto_accept = false

  tags = {
    Name = "${var.project_name}-${var.environment}-us-to-ap-peering"
  }
}

resource "aws_vpc_peering_connection_accepter" "us_to_ap" {
  provider                  = aws.ap_southeast
  vpc_peering_connection_id = aws_vpc_peering_connection.us_to_ap.id
  auto_accept               = true

  tags = {
    Name = "${var.project_name}-${var.environment}-us-to-ap-peering-accepter"
  }
}

# Cross-region monitoring and alerting
module "global_monitoring" {
  source = "./modules/global-monitoring"
  
  providers = {
    aws = aws.us_east
  }
  
  project_name = var.project_name
  environment  = var.environment
  
  # Regional monitoring endpoints
  us_east_endpoints     = module.us_east_region.monitoring_endpoints
  eu_west_endpoints     = module.eu_west_region.monitoring_endpoints
  ap_southeast_endpoints = module.ap_southeast_region.monitoring_endpoints
  
  # Alert configuration
  alert_email           = var.alert_email
  slack_webhook_url     = var.slack_webhook_url
}

# Disaster Recovery Automation
module "disaster_recovery" {
  source = "./modules/disaster-recovery"
  
  providers = {
    aws = aws.us_east
  }
  
  project_name = var.project_name
  environment  = var.environment
  
  # Regional resources
  primary_region_resources   = module.us_east_region.disaster_recovery_resources
  eu_region_resources       = module.eu_west_region.disaster_recovery_resources
  ap_region_resources       = module.ap_southeast_region.disaster_recovery_resources
  
  # Failover configuration
  failover_threshold_seconds = var.failover_threshold_seconds
  auto_failover_enabled     = var.auto_failover_enabled
}