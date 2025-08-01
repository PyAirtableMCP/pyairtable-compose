# Bootstrap Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pyairtable"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "workspaces" {
  description = "List of Terraform workspaces to create backend configs for"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "enable_state_notifications" {
  description = "Enable S3 bucket notifications for state changes"
  type        = bool
  default     = false
}

variable "enable_state_audit_trail" {
  description = "Enable CloudTrail for state bucket access logging"
  type        = bool
  default     = true
}

variable "enable_state_monitoring" {
  description = "Enable CloudWatch monitoring for state management resources"
  type        = bool
  default     = true
}

variable "state_bucket_size_alarm_threshold" {
  description = "Threshold for state bucket size alarm (bytes)"
  type        = number
  default     = 104857600 # 100MB
}