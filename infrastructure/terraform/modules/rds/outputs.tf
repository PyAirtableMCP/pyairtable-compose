# RDS Module Outputs

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "db_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "db_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "db_instance_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

output "db_instance_username" {
  description = "RDS master username"
  value       = aws_db_instance.main.username
  sensitive   = true
}

output "db_instance_availability_zone" {
  description = "RDS instance availability zone"
  value       = aws_db_instance.main.availability_zone
}

output "db_instance_multi_az" {
  description = "RDS Multi-AZ deployment status"
  value       = aws_db_instance.main.multi_az
}

output "db_instance_storage_encrypted" {
  description = "RDS storage encryption status"
  value       = aws_db_instance.main.storage_encrypted
}

output "db_instance_kms_key_id" {
  description = "RDS KMS key ID"
  value       = aws_db_instance.main.kms_key_id
}

# Read Replica
output "read_replica_identifier" {
  description = "Read replica identifier"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].identifier : null
}

output "read_replica_endpoint" {
  description = "Read replica endpoint"
  value       = var.create_read_replica ? aws_db_instance.read_replica[0].endpoint : null
  sensitive   = true
}

# Subnet Group
output "db_subnet_group_id" {
  description = "Database subnet group ID"
  value       = aws_db_subnet_group.main.id
}

output "db_subnet_group_name" {
  description = "Database subnet group name"
  value       = aws_db_subnet_group.main.name
}

# Parameter Group
output "db_parameter_group_id" {
  description = "Database parameter group ID"
  value       = aws_db_parameter_group.main.id
}

output "db_parameter_group_name" {
  description = "Database parameter group name"
  value       = aws_db_parameter_group.main.name
}

# Option Group
output "db_option_group_name" {
  description = "Database option group name"
  value       = var.create_option_group ? aws_db_option_group.main[0].name : null
}

# Secrets Manager
output "db_password_secret_id" {
  description = "Database password secret ID"
  value       = aws_secretsmanager_secret.db_password.id
}

output "db_password_secret_arn" {
  description = "Database password secret ARN"
  value       = aws_secretsmanager_secret.db_password.arn
}

# SSM Parameters
output "database_url_parameter" {
  description = "Database URL SSM parameter name"
  value       = aws_ssm_parameter.database_url.name
}

output "database_host_parameter" {
  description = "Database host SSM parameter name"
  value       = aws_ssm_parameter.database_host.name
}

output "database_port_parameter" {
  description = "Database port SSM parameter name"
  value       = aws_ssm_parameter.database_port.name
}

output "database_name_parameter" {
  description = "Database name SSM parameter name"
  value       = aws_ssm_parameter.database_name.name
}

# Enhanced Monitoring
output "enhanced_monitoring_role_arn" {
  description = "Enhanced monitoring IAM role ARN"
  value       = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
}

# CloudWatch Log Groups
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for database logs"
  value       = { for k, v in aws_cloudwatch_log_group.postgresql : k => v.name }
}

# Manual Snapshot
output "manual_snapshot_id" {
  description = "Manual snapshot ID"
  value       = var.create_manual_snapshot ? aws_db_snapshot.manual_snapshot[0].id : null
}

# Connection Information (for applications)
output "connection_info" {
  description = "Database connection information"
  value = {
    host     = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    database = aws_db_instance.main.db_name
    username = aws_db_instance.main.username
  }
  sensitive = true
}