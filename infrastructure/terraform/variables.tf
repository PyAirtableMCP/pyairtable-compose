# Simplified Variables for 2-Person Team
# Focus on essential configuration with sensible defaults

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pyairtable"
}

variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod (keep it simple)."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

# Service configurations with environment-specific defaults
variable "services" {
  description = "Service configurations"
  type = map(object({
    port            = number
    cpu             = number
    memory          = number
    desired_count   = number
    health_check_path = string
  }))
  default = {
    frontend = {
      port            = 3000
      cpu             = 256
      memory          = 512
      desired_count   = 1
      health_check_path = "/api/health"
    }
    api-gateway = {
      port            = 8000
      cpu             = 512
      memory          = 1024
      desired_count   = 1
      health_check_path = "/health"
    }
    llm-orchestrator = {
      port            = 8003
      cpu             = 1024
      memory          = 2048
      desired_count   = 1
      health_check_path = "/health"
    }
    mcp-server = {
      port            = 8001
      cpu             = 256
      memory          = 512
      desired_count   = 1
      health_check_path = "/health"
    }
    airtable-gateway = {
      port            = 8002
      cpu             = 256
      memory          = 512
      desired_count   = 1
      health_check_path = "/health"
    }
    platform-services = {
      port            = 8007
      cpu             = 512
      memory          = 1024
      desired_count   = 1
      health_check_path = "/health"
    }
    automation-services = {
      port            = 8006
      cpu             = 512
      memory          = 1024
      desired_count   = 1
      health_check_path = "/health"
    }
  }
}

# Database settings
variable "db_instance_class" {
  description = "Database instance class"
  type        = string
  default     = "db.t3.micro"  # Will be overridden in prod
}

variable "db_allocated_storage" {
  description = "Database storage in GB"
  type        = number
  default     = 20  # Will be overridden in prod
}

# Redis settings
variable "redis_node_type" {
  description = "Redis node type"
  type        = string
  default     = "cache.t3.micro"  # Will be overridden in prod
}

# SSL certificate (optional)
variable "certificate_arn" {
  description = "SSL certificate ARN (optional)"
  type        = string
  default     = ""
}

# Domain name (optional)
variable "domain_name" {
  description = "Domain name (optional)"
  type        = string
  default     = ""
}

# Alert email
variable "alert_email" {
  description = "Email for alerts"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}