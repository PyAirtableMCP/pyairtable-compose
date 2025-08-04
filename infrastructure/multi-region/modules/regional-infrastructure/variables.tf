# Regional Infrastructure Module Variables

variable "region" {
  description = "AWS region for this infrastructure"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "is_primary_region" {
  description = "Whether this is the primary region"
  type        = bool
  default     = false
}

variable "services" {
  description = "List of microservices to deploy"
  type        = list(string)
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
}

variable "environment_configs" {
  description = "Environment-specific configurations"
  type = map(object({
    min_capacity = number
    max_capacity = number
    enable_autoscaling = bool
    enable_deletion_protection = bool
  }))
}

# Database Configuration
variable "enable_rds" {
  description = "Enable RDS PostgreSQL database"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "primary_db_identifier" {
  description = "Primary database identifier for creating read replicas"
  type        = string
  default     = ""
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

# Cross-region Configuration
variable "cross_region_backup_bucket" {
  description = "S3 bucket for cross-region backups"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# Compliance Configuration
variable "gdpr_compliant" {
  description = "Enable GDPR compliance features"
  type        = bool
  default     = false
}

variable "data_residency_region" {
  description = "Data residency region for compliance"
  type        = string
  default     = ""
}

# SSL/TLS Configuration
variable "certificate_arn" {
  description = "ARN of SSL certificate"
  type        = string
  default     = ""
}

# Monitoring Configuration
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

# Cost Optimization
variable "enable_spot_instances" {
  description = "Enable Spot instances for non-critical workloads"
  type        = bool
  default     = false
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

# Kubernetes Configuration
variable "enable_eks" {
  description = "Enable Amazon EKS cluster"
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