# Database Replication Module Variables

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Database Configuration
variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "pyairtable"
}

variable "database_username" {
  description = "Master username for the database"
  type        = string
  default     = "pyairtable_admin"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.4"
}

# Instance Configuration
variable "primary_instance_class" {
  description = "Instance class for primary database"
  type        = string
  default     = "db.r6g.xlarge"
}

variable "replica_instance_class" {
  description = "Instance class for read replicas"
  type        = string
  default     = "db.r6g.large"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 200
}

variable "max_allocated_storage" {
  description = "Maximum allocated storage in GB for autoscaling"
  type        = number
  default     = 2000
}

# Network Configuration
variable "security_group_ids" {
  description = "List of security group IDs for primary database"
  type        = list(string)
}

variable "db_subnet_group_name" {
  description = "DB subnet group name for primary database"
  type        = string
}

variable "primary_availability_zone" {
  description = "Availability zone for primary database (if not multi-AZ)"
  type        = string
  default     = ""
}

# High Availability Configuration
variable "multi_az" {
  description = "Enable Multi-AZ deployment for primary database"
  type        = bool
  default     = true
}

variable "replica_multi_az" {
  description = "Enable Multi-AZ deployment for read replicas"
  type        = bool
  default     = false
}

# Backup Configuration
variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 30
}

variable "backup_window" {
  description = "Daily time range for backups (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Weekly time range for maintenance (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# Monitoring Configuration
variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds"
  type        = number
  default     = 60
}

variable "monitoring_role_arn" {
  description = "IAM role ARN for enhanced monitoring"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Read Replica Configuration
variable "read_replica_regions" {
  description = "Map of regions and their configurations for read replicas"
  type = map(object({
    security_group_ids    = list(string)
    monitoring_role_arn  = string
  }))
  default = {}
}

# Security Configuration
variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

# Performance Configuration
variable "performance_insights_enabled" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Performance Insights retention period in days"
  type        = number
  default     = 7
}

# Replication Configuration
variable "max_wal_senders" {
  description = "Maximum number of WAL sender processes"
  type        = number
  default     = 10
}

variable "wal_keep_size" {
  description = "WAL keep size in MB"
  type        = number
  default     = 2048
}

variable "max_replication_slots" {
  description = "Maximum number of replication slots"
  type        = number
  default     = 10
}

variable "hot_standby_feedback" {
  description = "Enable hot standby feedback"
  type        = bool
  default     = true
}

variable "max_standby_streaming_delay" {
  description = "Maximum delay before canceling queries when WAL data is being received"
  type        = string
  default     = "30s"
}

variable "max_standby_archive_delay" {
  description = "Maximum delay before canceling queries when WAL data is being read from archive"
  type        = string
  default     = "30s"
}

# Connection Configuration
variable "max_connections" {
  description = "Maximum number of database connections"
  type        = number
  default     = 1000
}

variable "shared_buffers_ratio" {
  description = "Ratio of instance memory to allocate for shared buffers"
  type        = number
  default     = 0.25
}

variable "effective_cache_size_ratio" {
  description = "Ratio of instance memory to set as effective cache size"
  type        = number
  default     = 0.75
}

# Performance Tuning
variable "work_mem_kb" {
  description = "Work memory in KB"
  type        = number
  default     = 4096
}

variable "maintenance_work_mem_kb" {
  description = "Maintenance work memory in KB"
  type        = number
  default     = 2097152  # 2GB
}

variable "wal_buffers_kb" {
  description = "WAL buffers in KB"
  type        = number
  default     = 16384  # 16MB
}

variable "checkpoint_completion_target" {
  description = "Checkpoint completion target"
  type        = number
  default     = 0.9
}

variable "random_page_cost" {
  description = "Random page cost (optimized for SSD)"
  type        = number
  default     = 1.1
}

variable "effective_io_concurrency" {
  description = "Effective I/O concurrency (optimized for SSD)"
  type        = number
  default     = 200
}

# Logging Configuration
variable "log_statement" {
  description = "Log statement type"
  type        = string
  default     = "mod"
  validation {
    condition     = contains(["none", "ddl", "mod", "all"], var.log_statement)
    error_message = "Log statement must be none, ddl, mod, or all."
  }
}

variable "log_min_duration_statement" {
  description = "Log statements taking longer than this many milliseconds"
  type        = number
  default     = 1000
}

variable "log_checkpoints" {
  description = "Log checkpoints"
  type        = bool
  default     = true
}

variable "log_connections" {
  description = "Log connections"
  type        = bool
  default     = true
}

variable "log_disconnections" {
  description = "Log disconnections"
  type        = bool
  default     = true
}

variable "log_lock_waits" {
  description = "Log lock waits"
  type        = bool
  default     = true
}

# Alerting Configuration
variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
  default     = ""
}

# CPU and connection thresholds
variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarms"
  type        = number
  default     = 80
}

variable "connection_alarm_threshold" {
  description = "Connection count threshold for alarms"
  type        = number
  default     = 800
}

variable "replica_lag_threshold" {
  description = "Replica lag threshold in seconds for alarms"
  type        = number
  default     = 300
}

# Failover Configuration
variable "enable_automated_failover" {
  description = "Enable automated failover Lambda function"
  type        = bool
  default     = true
}

variable "failover_timeout" {
  description = "Timeout for failover operations in seconds"
  type        = number
  default     = 300
}

# Cost Optimization
variable "enable_storage_autoscaling" {
  description = "Enable storage autoscaling"
  type        = bool
  default     = true
}

variable "storage_autoscaling_threshold" {
  description = "Storage autoscaling threshold percentage"
  type        = number
  default     = 90
}

# Compliance and Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_data_encryption" {
  description = "Enable data encryption at rest"
  type        = bool
  default     = true
}

variable "enable_transit_encryption" {
  description = "Enable encryption in transit"
  type        = bool
  default     = true
}

# Disaster Recovery
variable "enable_cross_region_backup" {
  description = "Enable cross-region automated backups"
  type        = bool
  default     = true
}

variable "cross_region_backup_retention" {
  description = "Cross-region backup retention in days"
  type        = number
  default     = 30
}

# Advanced Configuration
variable "shared_preload_libraries" {
  description = "List of shared preload libraries"
  type        = list(string)
  default     = ["pg_stat_statements", "pg_hint_plan"]
}

variable "default_statistics_target" {
  description = "Default statistics target for query planner"
  type        = number
  default     = 100
}

variable "enable_pg_stat_statements" {
  description = "Enable pg_stat_statements extension"
  type        = bool
  default     = true
}

variable "enable_auto_explain" {
  description = "Enable auto_explain extension"
  type        = bool
  default     = false
}