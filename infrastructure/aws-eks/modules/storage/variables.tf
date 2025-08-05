# Storage Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for EFS"
  type        = list(string)
}

# EBS CSI Driver Configuration
variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI driver"
  type        = bool
  default     = true
}

# EFS Configuration
variable "enable_efs" {
  description = "Enable EFS for shared storage"
  type        = bool
  default     = true
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
  
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be either generalPurpose or maxIO."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
  
  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either bursting or provisioned."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only used if throughput_mode is provisioned)"
  type        = number
  default     = 100
}

variable "efs_transition_to_ia" {
  description = "EFS transition to Infrequent Access storage class"
  type        = string
  default     = "AFTER_30_DAYS"
  
  validation {
    condition = contains([
      "AFTER_7_DAYS", 
      "AFTER_14_DAYS", 
      "AFTER_30_DAYS", 
      "AFTER_60_DAYS", 
      "AFTER_90_DAYS"
    ], var.efs_transition_to_ia)
    error_message = "EFS transition to IA must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

variable "efs_transition_to_primary_storage_class" {
  description = "EFS transition back to primary storage class"
  type        = string
  default     = "AFTER_1_ACCESS"
  
  validation {
    condition = contains([
      "AFTER_1_ACCESS"
    ], var.efs_transition_to_primary_storage_class)
    error_message = "EFS transition to primary storage class must be AFTER_1_ACCESS."
  }
}

# Backup Configuration
variable "enable_automated_backups" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "manual_snapshot_volume_ids" {
  description = "List of EBS volume IDs to create manual snapshots"
  type        = list(string)
  default     = []
}

# Monitoring Configuration
variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}