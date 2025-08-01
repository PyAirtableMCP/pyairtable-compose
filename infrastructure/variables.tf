# Infrastructure Variables

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

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

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

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

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ARN of SSL certificate"
  type        = string
  default     = ""
}

# Service-specific configurations
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

# Environment-specific overrides
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

# Database configuration
variable "enable_rds" {
  description = "Enable RDS PostgreSQL database"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

# Redis configuration
variable "enable_elasticache" {
  description = "Enable ElastiCache Redis"
  type        = bool
  default     = true
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes"
  type        = number
  default     = 1
}

# Monitoring and alerting
variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for alerts"
  type        = string
  default     = ""
}