# Storage Module Outputs

# EFS Outputs
output "efs_file_system_id" {
  description = "EFS file system ID"
  value       = var.enable_efs ? aws_efs_file_system.main[0].id : null
}

output "efs_file_system_arn" {
  description = "EFS file system ARN"
  value       = var.enable_efs ? aws_efs_file_system.main[0].arn : null
}

output "efs_dns_name" {
  description = "EFS DNS name"
  value       = var.enable_efs ? aws_efs_file_system.main[0].dns_name : null
}

output "efs_mount_target_ids" {
  description = "List of EFS mount target IDs"
  value       = var.enable_efs ? aws_efs_mount_target.main[*].id : []
}

output "efs_access_point_application_data_id" {
  description = "EFS access point ID for application data"
  value       = var.enable_efs ? aws_efs_access_point.application_data[0].id : null
}

output "efs_access_point_shared_storage_id" {
  description = "EFS access point ID for shared storage"
  value       = var.enable_efs ? aws_efs_access_point.shared_storage[0].id : null
}

# Storage Classes
output "storage_class_gp3_name" {
  description = "Name of the GP3 storage class"
  value       = var.enable_ebs_csi_driver ? kubernetes_storage_class.gp3[0].metadata[0].name : null
}

output "storage_class_gp3_retain_name" {
  description = "Name of the GP3 retain storage class"
  value       = var.enable_ebs_csi_driver ? kubernetes_storage_class.gp3_retain[0].metadata[0].name : null
}

output "storage_class_efs_name" {
  description = "Name of the EFS storage class"
  value       = var.enable_efs ? kubernetes_storage_class.efs[0].metadata[0].name : null
}

# Backup Resources
output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = var.enable_automated_backups ? aws_backup_vault.main[0].name : null
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = var.enable_automated_backups ? aws_backup_vault.main[0].arn : null
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = var.enable_automated_backups ? aws_backup_plan.main[0].id : null
}

output "backup_plan_arn" {
  description = "ARN of the AWS Backup plan"
  value       = var.enable_automated_backups ? aws_backup_plan.main[0].arn : null
}

# KMS Keys
output "efs_kms_key_id" {
  description = "KMS key ID for EFS encryption"
  value       = var.enable_efs ? aws_kms_key.efs[0].key_id : null
}

output "efs_kms_key_arn" {
  description = "KMS key ARN for EFS encryption"
  value       = var.enable_efs ? aws_kms_key.efs[0].arn : null
}

output "backup_kms_key_id" {
  description = "KMS key ID for backup encryption"
  value       = var.enable_automated_backups ? aws_kms_key.backup[0].key_id : null
}

output "backup_kms_key_arn" {
  description = "KMS key ARN for backup encryption"
  value       = var.enable_automated_backups ? aws_kms_key.backup[0].arn : null
}

# IAM Roles
output "backup_role_arn" {
  description = "ARN of the backup IAM role"
  value       = var.enable_automated_backups ? aws_iam_role.backup[0].arn : null
}

output "dlm_role_arn" {
  description = "ARN of the Data Lifecycle Manager IAM role"
  value       = var.enable_automated_backups ? aws_iam_role.dlm[0].arn : null
}

# Manual Snapshots
output "manual_snapshot_ids" {
  description = "List of manual EBS snapshot IDs"
  value       = aws_ebs_snapshot.manual_snapshot[*].id
}

# DLM Policy
output "dlm_lifecycle_policy_id" {
  description = "ID of the Data Lifecycle Manager policy"
  value       = var.enable_automated_backups ? aws_dlm_lifecycle_policy.ebs_snapshots[0].id : null
}

# CloudWatch Alarms
output "efs_burst_credit_alarm_name" {
  description = "Name of the EFS burst credit balance alarm"
  value       = var.enable_efs ? aws_cloudwatch_metric_alarm.efs_burst_credit_balance[0].alarm_name : null
}

# Summary output for easy reference
output "storage_summary" {
  description = "Summary of storage resources created"
  value = {
    efs_enabled           = var.enable_efs
    ebs_csi_driver_enabled = var.enable_ebs_csi_driver
    automated_backups_enabled = var.enable_automated_backups
    efs_file_system_id    = var.enable_efs ? aws_efs_file_system.main[0].id : null
    storage_classes = {
      gp3        = var.enable_ebs_csi_driver ? kubernetes_storage_class.gp3[0].metadata[0].name : null
      gp3_retain = var.enable_ebs_csi_driver ? kubernetes_storage_class.gp3_retain[0].metadata[0].name : null
      efs        = var.enable_efs ? kubernetes_storage_class.efs[0].metadata[0].name : null
    }
    backup = {
      vault_name = var.enable_automated_backups ? aws_backup_vault.main[0].name : null
      plan_id    = var.enable_automated_backups ? aws_backup_plan.main[0].id : null
    }
  }
}