# Infrastructure Outputs

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

# Load Balancer Outputs
output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.main.arn
}

output "load_balancer_zone_id" {
  description = "The canonical hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

# ECS Outputs
output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

# ECR Outputs
output "ecr_repository_urls" {
  description = "URLs of the ECR repositories"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

# Service Outputs
output "service_urls" {
  description = "URLs for each service"
  value = {
    for service, config in var.service_configs :
    service => service == "frontend" ? 
      "http://${aws_lb.main.dns_name}" : 
      "http://${aws_lb.main.dns_name}/${service}"
  }
}

output "service_discovery_namespace" {
  description = "Service discovery namespace"
  value       = aws_service_discovery_private_dns_namespace.main.name
}

# Database Outputs
output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = var.enable_rds ? aws_db_instance.main[0].endpoint : null
  sensitive   = true
}

output "database_port" {
  description = "RDS instance port"
  value       = var.enable_rds ? aws_db_instance.main[0].port : null
}

output "database_name" {
  description = "RDS database name"
  value       = var.enable_rds ? aws_db_instance.main[0].db_name : null
}

# Redis Outputs
output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = var.enable_elasticache ? aws_elasticache_cluster.main[0].cluster_address : null
  sensitive   = true
}

output "redis_port" {
  description = "ElastiCache Redis port"
  value       = var.enable_elasticache ? aws_elasticache_cluster.main[0].port : null
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ID of the ECS tasks security group"
  value       = aws_security_group.ecs_tasks.id
}

# IAM Role Outputs
output "ecs_task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task_role.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.ecs.name
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# Application URLs
output "application_urls" {
  description = "Application access URLs"
  value = {
    frontend           = "http://${aws_lb.main.dns_name}"
    api_gateway       = "http://${aws_lb.main.dns_name}/api-gateway"
    llm_orchestrator  = "http://${aws_lb.main.dns_name}/llm-orchestrator" 
    mcp_server        = "http://${aws_lb.main.dns_name}/mcp-server"
    airtable_gateway  = "http://${aws_lb.main.dns_name}/airtable-gateway"
    platform_services = "http://${aws_lb.main.dns_name}/platform-services"
    automation_services = "http://${aws_lb.main.dns_name}/automation-services"
  }
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information"
  value = {
    cluster_name     = aws_ecs_cluster.main.name
    environment      = var.environment
    region          = var.aws_region
    load_balancer   = aws_lb.main.dns_name
    services_count  = length(var.services)
  }
}