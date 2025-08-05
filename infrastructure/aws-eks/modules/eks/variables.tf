# EKS Module Variables

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

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "ID of the VPC where to create security group"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "List of subnet IDs for the EKS control plane"
  type        = list(string)
  default     = []
}

variable "cluster_security_group_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group ID for the EKS nodes"
  type        = string
}

variable "node_security_group_ids" {
  description = "List of security group IDs for the EKS nodes"
  type        = list(string)
  default     = []
}

variable "cluster_service_role_arn" {
  description = "ARN of the EKS cluster service role"
  type        = string
}

variable "node_instance_role_arn" {
  description = "ARN of the EKS node instance role"
  type        = string
}

variable "vpc_cni_irsa_role_arn" {
  description = "ARN of the VPC CNI IRSA role"
  type        = string
  default     = null
}

variable "ebs_csi_irsa_role_arn" {
  description = "ARN of the EBS CSI IRSA role"
  type        = string
  default     = null
}

variable "efs_csi_irsa_role_arn" {
  description = "ARN of the EFS CSI IRSA role"
  type        = string
  default     = null
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Node Groups Configuration
variable "node_groups" {
  description = "Map of EKS node group configurations"
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
  default = {}
}

variable "node_groups_defaults" {
  description = "Default configuration for EKS node groups"
  type = object({
    ec2_ssh_key = string
  })
  default = {
    ec2_ssh_key = null
  }
}

# Spot Instance Configuration
variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "spot_allocation_strategy" {
  description = "Strategy for spot instance allocation"
  type        = string
  default     = "diversified"
  
  validation {
    condition     = contains(["lowest-price", "diversified", "capacity-optimized"], var.spot_allocation_strategy)
    error_message = "Spot allocation strategy must be one of: lowest-price, diversified, capacity-optimized."
  }
}

# ARM64 Configuration
variable "enable_arm64_nodes" {
  description = "Enable ARM64 nodes for better price/performance"
  type        = bool
  default     = true
}

# Add-on Versions
variable "addon_versions" {
  description = "Map of EKS add-on versions"
  type = object({
    vpc_cni        = string
    coredns        = string
    kube_proxy     = string
    ebs_csi_driver = string
    efs_csi_driver = string
  })
  default = {
    vpc_cni        = "v1.15.1-eksbuild.1"
    coredns        = "v1.10.1-eksbuild.2"
    kube_proxy     = "v1.28.1-eksbuild.1"
    ebs_csi_driver = "v1.24.0-eksbuild.1"
    efs_csi_driver = "v1.7.0-eksbuild.1"
  }
}

# CSI Drivers
variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI driver"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Enable EFS CSI driver"
  type        = bool
  default     = true
}

# Cluster Autoscaler
variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

# Bootstrap and Kubelet Configuration
variable "bootstrap_arguments" {
  description = "Additional arguments for the EKS bootstrap script"
  type        = string
  default     = ""
}

variable "kubelet_extra_args" {
  description = "Additional arguments for kubelet"
  type        = string
  default     = "--node-labels=node.kubernetes.io/lifecycle=normal"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}