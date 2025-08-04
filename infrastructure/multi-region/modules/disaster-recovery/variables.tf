# Disaster Recovery Module Variables

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Network Configuration
variable "vpc_id" {
  description = "VPC ID for Lambda functions"
  type        = string
}

variable "lambda_subnet_ids" {
  description = "Subnet IDs for Lambda functions"
  type        = list(string)
}

# Regional Resources Configuration
variable "primary_region_resources" {
  description = "Primary region resources for disaster recovery"
  type = object({
    vpc_id                = string
    private_subnet_ids    = list(string)
    database_subnet_ids   = list(string)
    db_instance_id       = string
    redis_cluster_id     = string
    eks_cluster_name     = string
    alb_arn             = string
    region              = string
    is_primary          = bool
  })
}

variable "eu_region_resources" {
  description = "EU region resources for disaster recovery"
  type = object({
    vpc_id                = string
    private_subnet_ids    = list(string)
    database_subnet_ids   = list(string)
    db_instance_id       = string
    redis_cluster_id     = string
    eks_cluster_name     = string
    alb_arn             = string
    region              = string
    is_primary          = bool
  })
}

variable "ap_region_resources" {
  description = "AP region resources for disaster recovery"
  type = object({
    vpc_id                = string
    private_subnet_ids    = list(string)
    database_subnet_ids   = list(string)
    db_instance_id       = string
    redis_cluster_id     = string
    eks_cluster_name     = string
    alb_arn             = string
    region              = string
    is_primary          = bool
  })
}

# Health Check Configuration
variable "primary_region_health_check_id" {
  description = "Route53 health check ID for primary region"
  type        = string
}

variable "eu_region_health_check_id" {
  description = "Route53 health check ID for EU region"
  type        = string
}

variable "ap_region_health_check_id" {
  description = "Route53 health check ID for AP region"
  type        = string
}

# Failover Configuration
variable "failover_threshold_seconds" {
  description = "Threshold in seconds before triggering failover"
  type        = number
  default     = 300
}

variable "auto_failover_enabled" {
  description = "Enable automatic failover"
  type        = bool
  default     = false
}

variable "rto_minutes" {
  description = "Recovery Time Objective in minutes"
  type        = number
  default     = 30
}

variable "rpo_minutes" {
  description = "Recovery Point Objective in minutes"
  type        = number
  default     = 15
}

# Notification Configuration
variable "notification_emails" {
  description = "List of email addresses for disaster recovery notifications"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pagerduty_integration_key" {
  description = "PagerDuty integration key for critical alerts"
  type        = string
  default     = ""
  sensitive   = true
}

# Monitoring Configuration
variable "health_check_interval_minutes" {
  description = "Interval in minutes for automated health checks"
  type        = number
  default     = 5
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Failover Strategy Configuration
variable "database_failover_strategy" {
  description = "Database failover strategy"
  type        = string
  default     = "promote_replica"
  validation {
    condition     = contains(["promote_replica", "point_in_time_recovery", "manual"], var.database_failover_strategy)
    error_message = "Database failover strategy must be promote_replica, point_in_time_recovery, or manual."
  }
}

variable "dns_failover_strategy" {
  description = "DNS failover strategy"
  type        = string
  default     = "weighted_routing"
  validation {
    condition     = contains(["weighted_routing", "health_check", "manual"], var.dns_failover_strategy)
    error_message = "DNS failover strategy must be weighted_routing, health_check, or manual."
  }
}

variable "service_failover_strategy" {
  description = "Service failover strategy"
  type        = string
  default     = "auto_scaling"
  validation {
    condition     = contains(["auto_scaling", "blue_green", "canary", "manual"], var.service_failover_strategy)
    error_message = "Service failover strategy must be auto_scaling, blue_green, canary, or manual."
  }
}

# Validation Configuration
variable "post_failover_validation_enabled" {
  description = "Enable post-failover validation"
  type        = bool
  default     = true
}

variable "validation_timeout_minutes" {
  description = "Timeout for post-failover validation in minutes"
  type        = number
  default     = 10
}

variable "validation_endpoints" {
  description = "List of endpoints to validate after failover"
  type        = list(string)
  default     = ["/health", "/api/health", "/status"]
}

# Rollback Configuration
variable "enable_automatic_rollback" {
  description = "Enable automatic rollback on validation failure"
  type        = bool
  default     = false
}

variable "rollback_timeout_minutes" {
  description = "Timeout for rollback operations in minutes"
  type        = number
  default     = 15
}

# Compliance and Reporting
variable "enable_audit_logging" {
  description = "Enable audit logging for all disaster recovery actions"
  type        = bool
  default     = true
}

variable "compliance_framework" {
  description = "Compliance framework requirements"
  type        = list(string)
  default     = ["SOC2", "ISO27001"]
}

variable "incident_response_team" {
  description = "Incident response team contact information"
  type = list(object({
    name         = string
    email        = string
    phone        = string
    role         = string
    primary      = bool
  }))
  default = []
}

# Cost Optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization during disaster recovery"
  type        = bool
  default     = true
}

variable "scale_down_delay_minutes" {
  description = "Delay in minutes before scaling down resources after recovery"
  type        = number
  default     = 60
}

# Testing Configuration
variable "enable_disaster_recovery_testing" {
  description = "Enable periodic disaster recovery testing"
  type        = bool
  default     = true
}

variable "dr_test_schedule" {
  description = "Cron expression for disaster recovery testing schedule"
  type        = string
  default     = "cron(0 2 ? * SUN *)"  # Every Sunday at 2 AM
}

variable "test_environment_suffix" {
  description = "Suffix for test environment resources"
  type        = string
  default     = "dr-test"
}

# Security Configuration
variable "enable_cross_region_encryption" {
  description = "Enable encryption for cross-region communications"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = ""
}

# Advanced Configuration
variable "max_concurrent_failovers" {
  description = "Maximum number of concurrent failover operations"
  type        = number
  default     = 1
}

variable "failover_priority_order" {
  description = "Priority order for resource failover"
  type        = list(string)
  default     = ["database", "cache", "services", "dns"]
}

variable "enable_chaos_engineering" {
  description = "Enable chaos engineering tests"
  type        = bool
  default     = false
}

variable "chaos_test_schedule" {
  description = "Schedule for chaos engineering tests"
  type        = string
  default     = "cron(0 3 ? * MON *)"  # Every Monday at 3 AM
}

# Integration Configuration
variable "integration_webhooks" {
  description = "External webhook URLs for disaster recovery notifications"
  type = list(object({
    name = string
    url  = string
    type = string  # slack, teams, custom
  }))
  default = []
}

variable "external_monitoring_systems" {
  description = "External monitoring systems to integrate with"
  type = list(object({
    name = string
    type = string  # datadog, newrelic, splunk
    api_endpoint = string
    api_key = string
  }))
  default = []
  sensitive = true
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Lambda Configuration
variable "lambda_timeout_seconds" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900
}

variable "lambda_memory_mb" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 1024
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions"
  type        = number
  default     = 10
}