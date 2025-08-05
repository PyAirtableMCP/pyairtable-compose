# LGTM Stack Terraform Variables
# Configuration variables for PyAirtable observability infrastructure

# General Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "pyairtable-lgtm"
}

# Networking Configuration
variable "create_vpc" {
  description = "Whether to create a new VPC or use existing one"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "existing_vpc_id" {
  description = "ID of existing VPC (if create_vpc is false)"
  type        = string
  default     = ""
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs (if create_vpc is false)"
  type        = list(string)
  default     = []
}

# EKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "node_instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["m5.large"]
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in EKS node group"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in EKS node group"
  type        = number
  default     = 10
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in EKS node group"
  type        = number
  default     = 3
}

# Storage Configuration
variable "use_s3_storage" {
  description = "Use S3 for object storage instead of MinIO"
  type        = bool
  default     = false
}

variable "minio_root_user" {
  description = "MinIO root user (only used if use_s3_storage is false)"
  type        = string
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_root_password" {
  description = "MinIO root password (only used if use_s3_storage is false)"
  type        = string
  default     = "minioadmin123"
  sensitive   = true
}

# Grafana Configuration
variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin123"
  sensitive   = true
}

# Resource Limits (Environment-specific defaults will be applied)
variable "custom_resource_limits" {
  description = "Custom resource limits override"
  type = object({
    loki_memory    = optional(string)
    loki_cpu       = optional(string)
    tempo_memory   = optional(string)
    tempo_cpu      = optional(string)
    mimir_memory   = optional(string)
    mimir_cpu      = optional(string)
    grafana_memory = optional(string)
    grafana_cpu    = optional(string)
  })
  default = {}
}

# Retention Policies
variable "custom_retention_days" {
  description = "Custom retention days override"
  type = object({
    loki_retention_days  = optional(number)
    tempo_retention_days = optional(number)
    mimir_retention_days = optional(number)
  })
  default = {}
}

# Cost Optimization Settings
variable "enable_cost_optimization" {
  description = "Enable aggressive cost optimization settings"
  type        = bool
  default     = true
}

variable "sampling_rate" {
  description = "Trace sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.15
  
  validation {
    condition     = var.sampling_rate >= 0.0 && var.sampling_rate <= 1.0
    error_message = "Sampling rate must be between 0.0 and 1.0."
  }
}

variable "log_level_filter" {
  description = "Minimum log level to collect (DEBUG, INFO, WARN, ERROR)"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.log_level_filter)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

# Security Configuration
variable "enable_network_policies" {
  description = "Enable Kubernetes network policies for security"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access monitoring services"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

# High Availability Configuration
variable "enable_multi_zone" {
  description = "Enable multi-zone deployment for high availability"
  type        = bool
  default     = false
}

variable "replica_count" {
  description = "Number of replicas for each component (only if enable_multi_zone is true)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 5
    error_message = "Replica count must be between 1 and 5."
  }
}

# Monitoring and Alerting
variable "enable_prometheus_operator" {
  description = "Install Prometheus Operator for advanced monitoring"
  type        = bool
  default     = false
}

variable "alert_webhook_url" {
  description = "Webhook URL for alert notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

# Backup and Disaster Recovery
variable "enable_backups" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

# Performance Tuning
variable "enable_performance_tuning" {
  description = "Enable performance optimization settings"
  type        = bool
  default     = true
}

variable "cache_size_mb" {
  description = "Cache size in MB for each component"
  type        = number
  default     = 512
}

variable "max_concurrent_queries" {
  description = "Maximum concurrent queries per component"
  type        = number
  default     = 32
}

# Development/Testing Configuration
variable "enable_debug_mode" {
  description = "Enable debug mode (not for production)"
  type        = bool
  default     = false
}

variable "expose_services_externally" {
  description = "Expose services via LoadBalancer (for development)"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}