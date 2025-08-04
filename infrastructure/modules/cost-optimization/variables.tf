# Variables for Cost Optimization Module
# Task: cost-1 - Create Terraform cost-optimization module with Spot instance integration

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "target_group_arns" {
  description = "Target group ARNs for load balancer"
  type        = list(string)
  default     = []
}

# Spot Instance Configuration
variable "spot_target_capacity" {
  description = "Target capacity for spot instances"
  type        = number
  default     = 100
}

variable "min_spot_instances" {
  description = "Minimum number of spot instances"
  type        = number
  default     = 0
}

variable "max_spot_instances" {
  description = "Maximum number of spot instances"
  type        = number
  default     = 10
}

variable "desired_spot_instances" {
  description = "Desired number of spot instances"
  type        = number
  default     = 2
}

variable "on_demand_base_capacity" {
  description = "Base on-demand capacity"
  type        = number
  default     = 1
}

variable "on_demand_percentage" {
  description = "Percentage of on-demand instances above base capacity"
  type        = number
  default     = 30 # 70% spot, 30% on-demand
}

variable "spot_max_price" {
  description = "Maximum price for spot instances"
  type        = string
  default     = "0.05" # $0.05 per hour
}

# Scheduled Scaling Configuration
variable "enable_night_scaling" {
  description = "Enable night-time scaling for cost reduction"
  type        = bool
  default     = true
}

variable "night_scale_down_percentage" {
  description = "Percentage to scale down during night hours"
  type        = number
  default     = 50
}

variable "night_min_size" {
  description = "Minimum instances during night hours"
  type        = number
  default     = 1
}

variable "night_max_size" {
  description = "Maximum instances during night hours"
  type        = number
  default     = 3
}

variable "night_desired_capacity" {
  description = "Desired capacity during night hours"
  type        = number
  default     = 1
}

variable "night_scale_down_cron" {
  description = "Cron expression for night scale down (UTC)"
  type        = string
  default     = "0 22 * * *" # 10 PM UTC
}

variable "morning_scale_up_cron" {
  description = "Cron expression for morning scale up (UTC)"
  type        = string
  default     = "0 6 * * *" # 6 AM UTC
}

# Cost Monitoring Configuration
variable "daily_cost_threshold" {
  description = "Daily cost threshold for alerts (USD)"
  type        = number
  default     = 100
}

variable "alert_email" {
  description = "Email address for cost alerts"
  type        = string
  default     = ""
}

variable "cost_optimization_schedule" {
  description = "Schedule for cost optimization checks"
  type        = string
  default     = "rate(4 hours)" # Every 4 hours
}

# Reserved Capacity Configuration
variable "enable_redis_reserved" {
  description = "Enable Redis reserved capacity"
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "Redis node type for reserved capacity"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_reserved_nodes" {
  description = "Number of Redis reserved nodes"
  type        = number
  default     = 1
}

variable "reserved_duration" {
  description = "Reserved capacity duration"
  type        = string
  default     = "31536000" # 1 year in seconds
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Module    = "cost-optimization"
  }
}

# Cost Allocation Tags
variable "cost_allocation_tags" {
  description = "Cost allocation tags for billing"
  type        = map(string)
  default = {
    Team        = "3vantage"
    Service     = "pyairtable"
    CostCenter  = "engineering"
    Environment = "production"
  }
}