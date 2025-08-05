# AWS EKS Infrastructure Variables
# Cost-optimized configuration for PyAirtable Platform

# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pyairtable"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "owner" {
  description = "Owner of the infrastructure"
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
  default     = "pyairtable-terraform-state"
}

variable "terraform_lock_table" {
  description = "DynamoDB table for Terraform state locking"
  type        = string
  default     = "pyairtable-terraform-locks"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# EKS Configuration
variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

# Node Groups Configuration - Cost Optimized
variable "node_groups" {
  description = "EKS node groups configuration"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
    update_config = object({
      max_unavailable_percentage = number
    })
    disk_size = number
    ami_type  = string
    labels    = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
  
  default = {
    # Primary node group with mixed instances for cost optimization
    primary = {
      instance_types = ["t3.medium", "t3a.medium", "t2.medium"]
      capacity_type  = "SPOT"
      scaling_config = {
        desired_size = 2
        max_size     = 10
        min_size     = 1
      }
      update_config = {
        max_unavailable_percentage = 25
      }
      disk_size = 20
      ami_type  = "AL2_x86_64"
      labels = {
        role = "primary"
        cost-optimization = "spot"
      }
      taints = []
    }
    
    # ARM64 node group for better price/performance
    arm64 = {
      instance_types = ["t4g.medium", "t4g.large"]
      capacity_type  = "SPOT"
      scaling_config = {
        desired_size = 1
        max_size     = 5
        min_size     = 0
      }
      update_config = {
        max_unavailable_percentage = 25
      }
      disk_size = 20
      ami_type  = "AL2_ARM_64"
      labels = {
        role = "arm64"
        cost-optimization = "spot"
        architecture = "arm64"
      }
      taints = []
    }
    
    # On-demand node group for critical workloads
    critical = {
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"
      scaling_config = {
        desired_size = 1
        max_size     = 3
        min_size     = 1
      }
      update_config = {
        max_unavailable_percentage = 25
      }
      disk_size = 20
      ami_type  = "AL2_x86_64"
      labels = {
        role = "critical"
        workload-type = "system"
      }
      taints = []
    }
  }
}

# Cost Optimization Features
variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "enable_arm64_nodes" {
  description = "Enable ARM64 nodes for better price/performance"
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Enable Karpenter for advanced auto-scaling"
  type        = bool
  default     = true
}

variable "karpenter_instance_types" {
  description = "Instance types for Karpenter nodes"
  type        = list(string)
  default     = ["t3.small", "t3.medium", "t3a.small", "t3a.medium", "t4g.small", "t4g.medium"]
}

# Storage Configuration
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

# Monitoring Configuration
variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "enable_fluent_bit" {
  description = "Enable Fluent Bit for log forwarding"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_external_secrets" {
  description = "Enable External Secrets Operator"
  type        = bool
  default     = true
}

variable "secrets_config" {
  description = "Configuration for secrets management"
  type = map(object({
    description = string
    secret_string = map(string)
  }))
  default = {
    "pyairtable/api/keys" = {
      description = "API keys for PyAirtable services"
      secret_string = {
        airtable_api_key = "placeholder"
        openai_api_key   = "placeholder"
      }
    }
    "pyairtable/database" = {
      description = "Database credentials"
      secret_string = {
        postgres_password = "placeholder"
        redis_password    = "placeholder"
      }
    }
  }
}

# CI/CD Configuration
variable "github_org" {
  description = "GitHub organization for CI/CD"
  type        = string
  default     = "pyairtable"
}

variable "github_repos" {
  description = "GitHub repositories for CI/CD access"
  type        = list(string)
  default     = ["pyairtable-compose", "pyairtable-frontend", "pyairtable-api"]
}

# Cost Monitoring
variable "cost_budget_limit" {
  description = "Monthly cost budget limit in USD"
  type        = number
  default     = 200
}

variable "cost_alert_emails" {
  description = "Email addresses for cost alerts"
  type        = list(string)
  default     = ["admin@pyairtable.com"]
}

# Backup Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "enable_automated_backups" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}