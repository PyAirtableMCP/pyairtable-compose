# Enhanced Variables for PyAirtable Infrastructure
# Comprehensive configuration for multi-environment deployment

# Basic Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "owner_email" {
  description = "Email of the infrastructure owner"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# Multi-region Configuration
variable "multi_region_enabled" {
  description = "Enable multi-region deployment"
  type        = bool
  default     = false
}

variable "regions" {
  description = "List of AWS regions for multi-region deployment"
  type        = list(string)
  default     = ["us-west-2", "us-east-1"]
}

# Network Configuration
variable "vpc_cidrs" {
  description = "VPC CIDR blocks for each environment"
  type        = map(string)
  default = {
    dev     = "10.0.0.0/16"
    staging = "10.1.0.0/16"
    prod    = "10.2.0.0/16"
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks for each environment"
  type        = map(list(string))
  default = {
    dev     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
    staging = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
    prod    = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks for each environment"
  type        = map(list(string))
  default = {
    dev     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
    staging = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]
    prod    = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
  }
}

variable "database_subnet_cidrs" {
  description = "Database subnet CIDR blocks for each environment"
  type        = map(list(string))
  default = {
    dev     = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
    staging = ["10.1.201.0/24", "10.1.202.0/24", "10.1.203.0/24"]
    prod    = ["10.2.201.0/24", "10.2.202.0/24", "10.2.203.0/24"]
  }
}

# Kubernetes Configuration
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "eks_node_groups" {
  description = "EKS node group configurations for each environment"
  type = map(map(object({
    instance_types = list(string)
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
    update_config = object({
      max_unavailable_percentage = number
    })
    capacity_type = string
    disk_size     = number
    ami_type      = string
    labels        = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  })))
  default = {
    dev = {
      main = {
        instance_types = ["t3.medium"]
        scaling_config = {
          desired_size = 2
          max_size     = 4
          min_size     = 1
        }
        update_config = {
          max_unavailable_percentage = 25
        }
        capacity_type = "SPOT"
        disk_size     = 50
        ami_type      = "AL2_x86_64"
        labels = {
          Environment = "dev"
          NodeGroup   = "main"
        }
        taints = []
      }
    }
    staging = {
      main = {
        instance_types = ["t3.large"]
        scaling_config = {
          desired_size = 3
          max_size     = 6
          min_size     = 2
        }
        update_config = {
          max_unavailable_percentage = 25
        }
        capacity_type = "ON_DEMAND"
        disk_size     = 100
        ami_type      = "AL2_x86_64"
        labels = {
          Environment = "staging"
          NodeGroup   = "main"
        }
        taints = []
      }
    }
    prod = {
      main = {
        instance_types = ["m5.large"]
        scaling_config = {
          desired_size = 3
          max_size     = 10
          min_size     = 3
        }
        update_config = {
          max_unavailable_percentage = 25
        }
        capacity_type = "ON_DEMAND"
        disk_size     = 100
        ami_type      = "AL2_x86_64"
        labels = {
          Environment = "prod"
          NodeGroup   = "main"
        }
        taints = []
      }
      compute = {
        instance_types = ["c5.xlarge"]
        scaling_config = {
          desired_size = 2
          max_size     = 8
          min_size     = 0
        }
        update_config = {
          max_unavailable_percentage = 25
        }
        capacity_type = "SPOT"
        disk_size     = 100
        ami_type      = "AL2_x86_64"
        labels = {
          Environment = "prod"
          NodeGroup   = "compute"
          WorkloadType = "compute-intensive"
        }
        taints = [{
          key    = "workload-type"
          value  = "compute-intensive"
          effect = "NO_SCHEDULE"
        }]
      }
    }
  }
}

# Database Configuration
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.4"
}

variable "postgres_family" {
  description = "PostgreSQL parameter group family"
  type        = string
  default     = "postgres15"
}

variable "postgres_major_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "15"
}

variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "pyairtable"
}

variable "database_username" {
  description = "Database master username"
  type        = string
  default     = "postgres"
}

variable "rds_instance_classes" {
  description = "RDS instance classes for each environment"
  type        = map(string)
  default = {
    dev     = "db.t3.micro"
    staging = "db.t3.small"
    prod    = "db.r6g.large"
  }
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage for each environment"
  type        = map(number)
  default = {
    dev     = 20
    staging = 50
    prod    = 100
  }
}

variable "rds_max_allocated_storage" {
  description = "RDS max allocated storage for each environment"
  type        = map(number)
  default = {
    dev     = 100
    staging = 200
    prod    = 1000
  }
}

variable "rds_backup_retention" {
  description = "RDS backup retention period for each environment"
  type        = map(number)
  default = {
    dev     = 7
    staging = 7
    prod    = 30
  }
}

variable "rds_backup_window" {
  description = "RDS backup window for each environment"
  type        = map(string)
  default = {
    dev     = "03:00-04:00"
    staging = "03:00-04:00"
    prod    = "03:00-04:00"
  }
}

variable "rds_maintenance_window" {
  description = "RDS maintenance window for each environment"
  type        = map(string)
  default = {
    dev     = "sun:04:00-sun:05:00"
    staging = "sun:04:00-sun:05:00"
    prod    = "sun:04:00-sun:05:00"
  }
}

variable "postgres_parameters" {
  description = "PostgreSQL parameters"
  type = list(object({
    name  = string
    value = string
  }))
  default = [
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    },
    {
      name  = "log_statement"
      value = "all"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    },
    {
      name  = "max_connections"
      value = "200"
    }
  ]
}

# Redis Configuration
variable "redis_node_types" {
  description = "Redis node types for each environment"
  type        = map(string)
  default = {
    dev     = "cache.t3.micro"
    staging = "cache.t3.small"
    prod    = "cache.r6g.large"
  }
}

variable "redis_num_cache_nodes" {
  description = "Number of Redis cache nodes for each environment"
  type        = map(number)
  default = {
    dev     = 1
    staging = 2
    prod    = 3
  }
}

# Domain Configuration
variable "domain_names" {
  description = "Domain names for each environment"
  type        = map(string)
  default = {
    dev     = "dev.pyairtable.com"
    staging = "staging.pyairtable.com"
    prod    = "pyairtable.com"
  }
}

variable "create_hosted_zone" {
  description = "Create Route53 hosted zone"
  type        = bool
  default     = true
}

# Monitoring and Logging
variable "log_retention_days" {
  description = "CloudWatch log retention days for each environment"
  type        = map(number)
  default = {
    dev     = 7
    staging = 30
    prod    = 90
  }
}

variable "cost_alert_threshold" {
  description = "Cost alert threshold in USD"
  type        = number
  default     = 1000
}

# Backup Configuration
variable "enable_backup" {
  description = "Enable AWS Backup"
  type        = bool
  default     = true
}

variable "backup_plans" {
  description = "Backup plans for each environment"
  type = map(object({
    name = string
    rules = list(object({
      rule_name         = string
      target_vault_name = string
      schedule          = string
      lifecycle = object({
        cold_storage_after = number
        delete_after      = number
      })
      recovery_point_tags = map(string)
    }))
  }))
  default = {
    dev = {
      name = "dev-backup-plan"
      rules = [{
        rule_name         = "daily-backup"
        target_vault_name = "dev-backup-vault"
        schedule          = "cron(0 5 ? * * *)"
        lifecycle = {
          cold_storage_after = 30
          delete_after      = 120
        }
        recovery_point_tags = {
          Environment = "dev"
        }
      }]
    }
    staging = {
      name = "staging-backup-plan"
      rules = [{
        rule_name         = "daily-backup"
        target_vault_name = "staging-backup-vault"
        schedule          = "cron(0 5 ? * * *)"
        lifecycle = {
          cold_storage_after = 30
          delete_after      = 180
        }
        recovery_point_tags = {
          Environment = "staging"
        }
      }]
    }
    prod = {
      name = "prod-backup-plan"
      rules = [
        {
          rule_name         = "daily-backup"
          target_vault_name = "prod-backup-vault"
          schedule          = "cron(0 5 ? * * *)"
          lifecycle = {
            cold_storage_after = 30
            delete_after      = 365
          }
          recovery_point_tags = {
            Environment = "prod"
            BackupType  = "daily"
          }
        },
        {
          rule_name         = "weekly-backup"
          target_vault_name = "prod-backup-vault"
          schedule          = "cron(0 6 ? * SUN *)"
          lifecycle = {
            cold_storage_after = 90
            delete_after      = 2555  # 7 years
          }
          recovery_point_tags = {
            Environment = "prod"
            BackupType  = "weekly"
          }
        }
      ]
    }
  }
}

# Disaster Recovery Configuration
variable "enable_cross_region_backup" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = false
}

variable "backup_destination_region" {
  description = "Destination region for backup replication"
  type        = string
  default     = "us-east-1"
}

# Feature Flags
variable "enable_waf" {
  description = "Enable AWS WAF"
  type        = bool
  default     = true
}

variable "enable_shield" {
  description = "Enable AWS Shield Advanced"
  type        = bool
  default     = false
}

variable "enable_guard_duty" {
  description = "Enable AWS GuardDuty"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail"
  type        = bool
  default     = true
}

# Security Configuration
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access resources"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Restrict this in production
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = true
}

# Auto Scaling Configuration
variable "enable_cluster_autoscaler" {
  description = "Enable EKS cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaler" {
  description = "Enable vertical pod autoscaler"
  type        = bool
  default     = true
}

# Service Mesh Configuration
variable "enable_istio" {
  description = "Enable Istio service mesh"
  type        = bool
  default     = false
}

variable "enable_linkerd" {
  description = "Enable Linkerd service mesh"
  type        = bool
  default     = false
}

# Observability Configuration
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

variable "enable_jaeger" {
  description = "Enable Jaeger tracing"
  type        = bool
  default     = false
}

variable "enable_elastic_stack" {
  description = "Enable Elastic Stack (ELK)"
  type        = bool
  default     = false
}

# Performance Configuration
variable "enable_performance_monitoring" {
  description = "Enable performance monitoring"
  type        = bool
  default     = true
}

variable "enable_x_ray" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = false
}

# Cost Optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "enable_spot_instances" {
  description = "Enable spot instances where appropriate"
  type        = bool
  default     = true
}

variable "enable_savings_plans" {
  description = "Enable AWS Savings Plans recommendations"
  type        = bool
  default     = false
}

# Compliance and Governance
variable "enable_compliance_monitoring" {
  description = "Enable compliance monitoring"
  type        = bool
  default     = true
}

variable "compliance_standards" {
  description = "Compliance standards to monitor"
  type        = list(string)
  default     = ["SOC2", "PCI-DSS", "GDPR"]
}

# Data Classification
variable "data_classification" {
  description = "Data classification level"
  type        = string
  default     = "internal"
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be public, internal, confidential, or restricted."
  }
}