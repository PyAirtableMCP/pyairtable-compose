# Simplified Outputs - What you actually need

# Application URLs
output "application_url" {
  description = "Main application URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_lb.main.dns_name}"
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "service_urls" {
  description = "Individual service URLs"
  value = {
    for service, config in var.services :
    service => service == "frontend" ? 
      (var.domain_name != "" ? "https://${var.domain_name}" : "http://${aws_lb.main.dns_name}") : 
      (var.domain_name != "" ? "https://${var.domain_name}/${service}" : "http://${aws_lb.main.dns_name}/${service}")
  }
}

# Infrastructure details
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

# Container registries
output "ecr_repositories" {
  description = "ECR repository URLs for pushing images"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

# Database info (sensitive)
output "database_endpoint" {
  description = "Database endpoint"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = "${aws_elasticache_cluster.main.cluster_address}:${aws_elasticache_cluster.main.port}"
  sensitive   = true
}

# For deployment scripts
output "deployment_info" {
  description = "Information needed for deployment scripts"
  value = {
    cluster_name     = aws_ecs_cluster.main.name
    service_names    = { for k, v in aws_ecs_service.services : k => v.name }
    repository_urls  = { for k, v in aws_ecr_repository.services : k => v.repository_url }
    environment      = var.environment
    region          = var.aws_region
  }
}