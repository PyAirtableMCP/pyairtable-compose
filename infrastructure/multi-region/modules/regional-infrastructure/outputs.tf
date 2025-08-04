# Regional Infrastructure Module Outputs

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs of the database subnets"
  value       = aws_subnet.database[*].id
}

# Load Balancer Outputs
output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "alb_security_group_id" {
  description = "Security group ID for the ALB"
  value       = aws_security_group.alb.id
}

# Database Outputs
output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = var.is_primary_region && var.enable_rds ? aws_db_instance.main[0].identifier : (var.enable_rds ? aws_db_instance.replica[0].identifier : "")
}

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = var.is_primary_region && var.enable_rds ? aws_db_instance.main[0].endpoint : (var.enable_rds ? aws_db_instance.replica[0].endpoint : "")
}

output "db_port" {
  description = "RDS instance port"
  value       = var.enable_rds ? 5432 : null
}

output "db_security_group_id" {
  description = "Security group ID for the database"
  value       = aws_security_group.database.id
}

output "database_secret_arn" {
  description = "ARN of the database secrets"
  value       = var.enable_rds ? aws_secretsmanager_secret.database[0].arn : ""
}

# Redis Outputs
output "redis_endpoint" {
  description = "Redis cluster endpoint"
  value       = var.enable_elasticache ? aws_elasticache_replication_group.main[0].configuration_endpoint_address : ""
}

output "redis_port" {
  description = "Redis cluster port"
  value       = var.enable_elasticache ? 6379 : null
}

output "redis_security_group_id" {
  description = "Security group ID for Redis"
  value       = aws_security_group.redis.id
}

output "redis_secret_arn" {
  description = "ARN of the Redis secrets"
  value       = var.enable_elasticache ? aws_secretsmanager_secret.redis[0].arn : ""
}

# EKS Outputs
output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "EKS cluster version"
  value       = aws_eks_cluster.main.version
}

output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

# Security Groups
output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

# CloudWatch Outputs
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for services"
  value = {
    for service, log_group in aws_cloudwatch_log_group.services : service => {
      name = log_group.name
      arn  = log_group.arn
    }
  }
}

# Route53 Health Check
output "health_check_id" {
  description = "Route53 health check ID"
  value       = aws_route53_health_check.main.id
}

# Regional Monitoring Endpoints
output "monitoring_endpoints" {
  description = "Monitoring endpoints for this region"
  value = {
    health_check_id = aws_route53_health_check.main.id
    alb_dns_name   = aws_lb.main.dns_name
    region         = var.region
    primary        = var.is_primary_region
  }
}

# Disaster Recovery Resources
output "disaster_recovery_resources" {
  description = "Resources needed for disaster recovery"
  value = {
    vpc_id                = aws_vpc.main.id
    private_subnet_ids    = aws_subnet.private[*].id
    database_subnet_ids   = aws_subnet.database[*].id
    db_instance_id       = var.is_primary_region && var.enable_rds ? aws_db_instance.main[0].identifier : (var.enable_rds ? aws_db_instance.replica[0].identifier : "")
    redis_cluster_id     = var.enable_elasticache ? aws_elasticache_replication_group.main[0].id : ""
    eks_cluster_name     = aws_eks_cluster.main.name
    alb_arn             = aws_lb.main.arn
    region              = var.region
    is_primary          = var.is_primary_region
  }
}

# Cost Tracking Tags
output "cost_allocation_tags" {
  description = "Cost allocation tags for this region's resources"
  value = {
    Project     = var.project_name
    Environment = var.environment
    Region      = var.region
    RegionType  = var.is_primary_region ? "primary" : "secondary"
  }
}

# Network Configuration
output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

# S3 Outputs
output "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
}

# KMS Key Outputs
output "eks_kms_key_arn" {
  description = "ARN of the KMS key used for EKS encryption"
  value       = aws_kms_key.eks.arn
}

output "eks_kms_key_id" {
  description = "ID of the KMS key used for EKS encryption"
  value       = aws_kms_key.eks.id
}