# Karpenter Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC Identity Provider"
  type        = string
}

# Karpenter Configuration
variable "enable_karpenter" {
  description = "Enable Karpenter for advanced auto-scaling"
  type        = bool
  default     = true
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "0.32.1"
}

# Instance Configuration
variable "instance_types" {
  description = "List of instance types for Karpenter nodes"
  type        = list(string)
  default = [
    "t3.small", "t3.medium", "t3.large",
    "t3a.small", "t3a.medium", "t3a.large",
    "t4g.small", "t4g.medium", "t4g.large",
    "m5.large", "m5.xlarge",
    "m5a.large", "m5a.xlarge",
    "m6i.large", "m6i.xlarge",
    "c5.large", "c5.xlarge",
    "c5a.large", "c5a.xlarge",
    "c6i.large", "c6i.xlarge"
  ]
}

variable "capacity_types" {
  description = "List of capacity types (spot, on-demand)"
  type        = list(string)
  default     = ["spot", "on-demand"]
}

variable "supported_architectures" {
  description = "List of supported architectures"
  type        = list(string)
  default     = ["amd64", "arm64"]
}

# Scaling Limits
variable "max_cpu_limit" {
  description = "Maximum CPU limit for all Karpenter nodes"
  type        = string
  default     = "1000"
}

variable "max_memory_limit" {
  description = "Maximum memory limit for all Karpenter nodes"
  type        = string
  default     = "1000Gi"
}

# Node Configuration
variable "node_volume_size" {
  description = "EBS volume size for Karpenter nodes (GB)"
  type        = number
  default     = 20
}

# TTL Settings for Cost Optimization
variable "ttl_seconds_after_empty" {
  description = "Seconds to wait before terminating empty nodes"
  type        = number
  default     = 30
}

variable "ttl_seconds_until_expired" {
  description = "Seconds to wait before expiring nodes"
  type        = number
  default     = 2592000 # 30 days
}

# Spot Instance Configuration
variable "spot_allocation_strategy" {
  description = "Strategy for spot instance allocation"
  type        = string
  default     = "price-capacity-optimized"
  
  validation {
    condition = contains([
      "lowest-price", 
      "diversified", 
      "capacity-optimized", 
      "capacity-optimized-prioritized",
      "price-capacity-optimized"
    ], var.spot_allocation_strategy)
    error_message = "Spot allocation strategy must be valid."
  }
}

variable "enable_spot_taints" {
  description = "Enable taints on spot instances"
  type        = bool
  default     = false
}

# Additional Provisioners
variable "enable_burstable_provisioner" {
  description = "Enable dedicated provisioner for burstable instances"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}