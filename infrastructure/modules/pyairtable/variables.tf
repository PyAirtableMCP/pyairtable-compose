# Variables for PyAirtable Infrastructure Module

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pyairtable"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN for ALB"
  type        = string
  default     = ""
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0."
  }
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
  
  validation {
    condition = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address or empty string."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Application secrets
variable "jwt_secret" {
  description = "JWT secret for authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "api_key" {
  description = "Internal API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "airtable_token" {
  description = "Airtable API token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gemini_api_key" {
  description = "Google Gemini API key"
  type        = string
  sensitive   = true
  default     = ""
}

# Feature flags
variable "enable_monitoring" {
  description = "Enable comprehensive monitoring stack"
  type        = bool
  default     = true
}

variable "enable_service_mesh" {
  description = "Enable Istio service mesh"
  type        = bool
  default     = true
}

variable "enable_autoscaling" {
  description = "Enable advanced autoscaling"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable automated backup"
  type        = bool
  default     = true
}

variable "enable_dr" {
  description = "Enable disaster recovery"
  type        = bool
  default     = false
}

# Multi-region configuration
variable "dr_region" {
  description = "Disaster recovery region"
  type        = string
  default     = "us-west-2"
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication"
  type        = bool
  default     = false
}

# Cost optimization
variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "spot_instance_percentage" {
  description = "Percentage of spot instances to use"
  type        = number
  default     = 50
  
  validation {
    condition     = var.spot_instance_percentage >= 0 && var.spot_instance_percentage <= 100
    error_message = "Spot instance percentage must be between 0 and 100."
  }
}

variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling for cost optimization"
  type        = bool
  default     = true
}

# Security
variable "enable_waf" {
  description = "Enable AWS WAF"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable AWS GuardDuty"
  type        = bool
  default     = true
}

variable "enable_security_hub" {
  description = "Enable AWS Security Hub"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Compliance
variable "enable_compliance_scanning" {
  description = "Enable compliance scanning"
  type        = bool
  default     = false
}

variable "compliance_framework" {
  description = "Compliance framework to adhere to"
  type        = string
  default     = "cis"
  
  validation {
    condition = contains(["cis", "pci", "hipaa", "soc2"], var.compliance_framework)
    error_message = "Compliance framework must be one of: cis, pci, hipaa, soc2."
  }
}

# Networking
variable "enable_private_endpoints" {
  description = "Enable VPC endpoints for AWS services"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

# Database configuration
variable "database_config" {
  description = "Database configuration override"
  type = object({
    instance_class        = optional(string)
    allocated_storage     = optional(number)
    max_allocated_storage = optional(number)
    backup_retention_days = optional(number)
    multi_az             = optional(bool)
    storage_encrypted    = optional(bool)
    deletion_protection  = optional(bool)
  })
  default = {}
}

# Cache configuration
variable "cache_config" {
  description = "Cache configuration override"
  type = object({
    node_type                   = optional(string)
    num_cache_nodes            = optional(number)
    engine_version             = optional(string)
    snapshot_retention_limit   = optional(number)
    auth_token_enabled         = optional(bool)
    at_rest_encryption_enabled = optional(bool)
    transit_encryption_enabled = optional(bool)
  })
  default = {}
}

# Service-specific configurations
variable "service_configs" {
  description = "Service-specific resource configurations"
  type = map(object({
    cpu_request    = optional(string, "100m")
    cpu_limit      = optional(string, "500m")
    memory_request = optional(string, "128Mi")
    memory_limit   = optional(string, "512Mi")
    replicas       = optional(number, 1)
    priority_class = optional(string, "pyairtable-normal")
    node_selector  = optional(map(string), {})
    tolerations    = optional(list(object({
      key      = string
      operator = string
      value    = optional(string)
      effect   = string
    })), [])
  }))
  default = {}
}

# Observability configuration
variable "observability_config" {
  description = "Observability stack configuration"
  type = object({
    prometheus_retention_days = optional(number, 15)
    grafana_admin_password   = optional(string, "admin")
    jaeger_enabled           = optional(bool, true)
    elasticsearch_enabled    = optional(bool, false)
    log_level               = optional(string, "info")
  })
  default = {}
}

# Auto-scaling configuration
variable "autoscaling_config" {
  description = "Auto-scaling configuration"
  type = object({
    enable_hpa                = optional(bool, true)
    enable_vpa                = optional(bool, true)
    enable_cluster_autoscaler = optional(bool, true)
    enable_keda               = optional(bool, true)
    target_cpu_utilization    = optional(number, 70)
    target_memory_utilization = optional(number, 80)
  })
  default = {}
}

# Migration settings
variable "migration_config" {
  description = "Migration-specific configuration"
  type = object({
    source_environment = optional(string, "")
    migration_window   = optional(string, "")
    rollback_enabled   = optional(bool, true)
    data_sync_enabled  = optional(bool, false)
  })
  default = {}
}