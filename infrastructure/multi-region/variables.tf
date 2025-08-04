# Multi-Region Infrastructure Variables

variable "environment" {
  description = "Environment name"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "pyairtable"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# Regional Configuration
variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_regions" {
  description = "List of secondary AWS regions"
  type        = list(string)
  default     = ["eu-west-1", "ap-southeast-1"]
}

# Service Configuration
variable "services" {
  description = "List of microservices to deploy"
  type        = list(string)
  default = [
    "frontend",
    "api-gateway", 
    "llm-orchestrator",
    "mcp-server",
    "airtable-gateway",
    "platform-services",
    "automation-services"
  ]
}

variable "service_configs" {
  description = "Configuration for each service"
  type = map(object({
    port           = number
    cpu            = number
    memory         = number
    desired_count  = number
    health_check_path = string
    priority       = number
  }))
  
  default = {
    frontend = {
      port           = 3000
      cpu            = 256
      memory         = 512
      desired_count  = 2
      health_check_path = "/api/health"
      priority       = 100
    }
    api-gateway = {
      port           = 8000
      cpu            = 512
      memory         = 1024
      desired_count  = 2
      health_check_path = "/health"
      priority       = 200
    }
    llm-orchestrator = {
      port           = 8003
      cpu            = 1024
      memory         = 2048
      desired_count  = 2
      health_check_path = "/health"
      priority       = 300
    }
    mcp-server = {
      port           = 8001
      cpu            = 512
      memory         = 1024
      desired_count  = 2
      health_check_path = "/health"
      priority       = 400
    }
    airtable-gateway = {
      port           = 8002
      cpu            = 256
      memory         = 512
      desired_count  = 2
      health_check_path = "/health"
      priority       = 500
    }
    platform-services = {
      port           = 8007
      cpu            = 512
      memory         = 1024
      desired_count  = 2
      health_check_path = "/health"
      priority       = 600
    }
    automation-services = {
      port           = 8006
      cpu            = 512
      memory         = 1024
      desired_count  = 2
      health_check_path = "/health"
      priority       = 700
    }
  }
}

# Environment-specific configurations
variable "environment_configs" {
  description = "Environment-specific configurations"
  type = map(object({
    min_capacity = number
    max_capacity = number
    enable_autoscaling = bool
    enable_deletion_protection = bool
  }))
  
  default = {
    dev = {
      min_capacity = 1
      max_capacity = 2
      enable_autoscaling = false
      enable_deletion_protection = false
    }
    staging = {
      min_capacity = 1
      max_capacity = 4
      enable_autoscaling = true
      enable_deletion_protection = false
    }
    prod = {
      min_capacity = 2
      max_capacity = 10
      enable_autoscaling = true
      enable_deletion_protection = true
    }
  }
}

# Database Configuration
variable "enable_rds" {
  description = "Enable RDS PostgreSQL database"
  type        = bool
  default     = true
}

variable "db_instance_class_primary" {
  description = "RDS instance class for primary region"
  type        = string
  default     = "db.r6g.large"
}

variable "db_instance_class_secondary" {
  description = "RDS instance class for secondary regions"
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "RDS maximum allocated storage in GB for autoscaling"
  type        = number
  default     = 1000
}

variable "backup_retention_period" {
  description = "Database backup retention period in days"
  type        = number
  default     = 30
}

variable "backup_window" {
  description = "Database backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Database maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

# Redis Configuration
variable "enable_elasticache" {
  description = "Enable ElastiCache Redis"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.r6g.large"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 3
}

variable "redis_parameter_group_name" {
  description = "Redis parameter group"
  type        = string
  default     = "default.redis7"
}

# Kafka Configuration
variable "enable_msk" {
  description = "Enable Amazon MSK (Managed Streaming for Kafka)"
  type        = bool
  default     = true
}

variable "kafka_instance_type" {
  description = "Kafka broker instance type"
  type        = string
  default     = "kafka.m5.large"
}

variable "kafka_ebs_volume_size" {
  description = "EBS volume size for Kafka brokers in GB"
  type        = number
  default     = 100
}

variable "kafka_version" {
  description = "Kafka version"
  type        = string
  default     = "2.8.1"
}

# CloudFront and CDN Configuration
variable "enable_cloudfront" {
  description = "Enable CloudFront CDN"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_All"
  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "cloudfront_minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version"
  type        = string
  default     = "TLSv1.2_2021"
}

# SSL/TLS Configuration
variable "certificate_arn" {
  description = "ARN of SSL certificate for primary domain"
  type        = string
  default     = ""
}

variable "certificate_arn_eu" {
  description = "ARN of SSL certificate for EU region"
  type        = string
  default     = ""
}

variable "certificate_arn_ap" {
  description = "ARN of SSL certificate for AP region"
  type        = string
  default     = ""
}

# Monitoring and Alerting
variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# Disaster Recovery Configuration
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

variable "rpo_minutes" {
  description = "Recovery Point Objective in minutes"
  type        = number
  default     = 15
}

variable "rto_minutes" {
  description = "Recovery Time Objective in minutes"
  type        = number
  default     = 30
}

# Security Configuration
variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all services"
  type        = bool
  default     = true
}

variable "enable_encryption_in_transit" {
  description = "Enable encryption in transit for all services"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "Enable AWS WAF"
  type        = bool
  default     = true
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable Spot instances for non-critical workloads"
  type        = bool
  default     = false
}

variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 5000
}

# Compliance and Data Residency
variable "enable_gdpr_compliance" {
  description = "Enable GDPR compliance features"
  type        = bool
  default     = true
}

variable "data_classification_tags" {
  description = "Data classification tags for compliance"
  type        = map(string)
  default = {
    "DataClassification" = "Internal"
    "DataRetention"     = "7years"
    "ComplianceFramework" = "GDPR,SOC2"
  }
}

# Performance Configuration
variable "enable_auto_scaling" {
  description = "Enable auto scaling for all services"
  type        = bool
  default     = true
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for auto scaling"
  type        = number
  default     = 70
}

variable "target_memory_utilization" {
  description = "Target memory utilization for auto scaling"
  type        = number
  default     = 80
}

# Network Configuration
variable "enable_transit_gateway" {
  description = "Enable AWS Transit Gateway for inter-region connectivity"
  type        = bool
  default     = true
}

variable "enable_private_link" {
  description = "Enable VPC endpoints via PrivateLink"
  type        = bool
  default     = true
}

# Kubernetes Configuration
variable "enable_eks" {
  description = "Enable Amazon EKS clusters"
  type        = bool
  default     = true
}

variable "eks_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.28"
}

variable "eks_node_group_instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge"]
}

variable "eks_node_group_scaling_config" {
  description = "Scaling configuration for EKS node groups"
  type = object({
    desired_size = number
    max_size     = number
    min_size     = number
  })
  default = {
    desired_size = 3
    max_size     = 10
    min_size     = 1
  }
}