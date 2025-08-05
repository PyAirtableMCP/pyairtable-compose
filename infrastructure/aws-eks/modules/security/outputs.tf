# Security Module Outputs

output "cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.node.id
}

output "alb_security_group_id" {
  description = "Security group ID for Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "database_security_group_id" {
  description = "Security group ID for database access"
  value       = aws_security_group.database.id
}

output "efs_security_group_id" {
  description = "Security group ID for EFS access"
  value       = aws_security_group.efs.id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS database"
  value       = aws_security_group.rds.id
}

output "elasticache_security_group_id" {
  description = "Security group ID for ElastiCache"
  value       = aws_security_group.elasticache.id
}

output "bastion_security_group_id" {
  description = "Security group ID for bastion host"
  value       = var.enable_bastion ? aws_security_group.bastion[0].id : null
}

output "private_network_acl_id" {
  description = "Network ACL ID for private subnets"
  value       = aws_network_acl.private.id
}

# Security group IDs map for easy reference
output "security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    cluster      = aws_security_group.cluster.id
    node         = aws_security_group.node.id
    alb          = aws_security_group.alb.id
    database     = aws_security_group.database.id
    efs          = aws_security_group.efs.id
    rds          = aws_security_group.rds.id
    elasticache  = aws_security_group.elasticache.id
    bastion      = var.enable_bastion ? aws_security_group.bastion[0].id : null
  }
}