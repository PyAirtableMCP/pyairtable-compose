# EKS Module Outputs

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster"
  value       = aws_eks_cluster.main.status
}

output "cluster_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Identity Provider if enabled"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of cloudwatch log group created"
  value       = aws_cloudwatch_log_group.eks.name
}

output "cloudwatch_log_group_arn" {
  description = "Arn of cloudwatch log group created"
  value       = aws_cloudwatch_log_group.eks.arn
}

# Node groups outputs
output "node_groups" {
  description = "Map of attribute maps for all EKS node groups created"
  value = {
    for k, v in aws_eks_node_group.main : k => {
      arn           = v.arn
      status        = v.status
      capacity_type = v.capacity_type
      instance_types = v.instance_types
      ami_type      = v.ami_type
      node_group_name = v.node_group_name
      scaling_config = v.scaling_config
      remote_access = v.remote_access
      labels        = v.labels
      taints        = v.taint
    }
  }
}

output "node_group_arns" {
  description = "List of the EKS node group ARNs"
  value       = [for ng in aws_eks_node_group.main : ng.arn]
}

output "node_group_names" {
  description = "List of the EKS node group names"
  value       = [for ng in aws_eks_node_group.main : ng.node_group_name]
}

output "node_group_statuses" {
  description = "Status of the EKS node groups"
  value       = {for k, v in aws_eks_node_group.main : k => v.status}
}

# Launch templates
output "launch_template_ids" {
  description = "Map of launch template IDs"
  value       = {for k, v in aws_launch_template.node_group : k => v.id}
}

output "launch_template_arns" {
  description = "Map of launch template ARNs"
  value       = {for k, v in aws_launch_template.node_group : k => v.arn}
}

output "launch_template_latest_versions" {
  description = "Map of launch template latest versions"
  value       = {for k, v in aws_launch_template.node_group : k => v.latest_version}
}

# KMS keys
output "kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the EKS encryption key"
  value       = aws_kms_key.eks.arn
}

output "kms_key_id" {
  description = "The globally unique identifier for the EKS encryption key"
  value       = aws_kms_key.eks.key_id
}

output "ebs_kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the EBS encryption key"
  value       = aws_kms_key.ebs.arn
}

output "ebs_kms_key_id" {
  description = "The globally unique identifier for the EBS encryption key"
  value       = aws_kms_key.ebs.key_id
}

# Add-ons
output "addons" {
  description = "Map of attribute maps for all EKS add-ons enabled"
  value = {
    vpc_cni = try({
      arn               = aws_eks_addon.vpc_cni.arn
      status            = aws_eks_addon.vpc_cni.status
      addon_version     = aws_eks_addon.vpc_cni.addon_version
      resolve_conflicts = aws_eks_addon.vpc_cni.resolve_conflicts
    }, null)
    
    coredns = try({
      arn               = aws_eks_addon.coredns.arn
      status            = aws_eks_addon.coredns.status
      addon_version     = aws_eks_addon.coredns.addon_version
      resolve_conflicts = aws_eks_addon.coredns.resolve_conflicts
    }, null)
    
    kube_proxy = try({
      arn               = aws_eks_addon.kube_proxy.arn
      status            = aws_eks_addon.kube_proxy.status
      addon_version     = aws_eks_addon.kube_proxy.addon_version
      resolve_conflicts = aws_eks_addon.kube_proxy.resolve_conflicts
    }, null)
    
    ebs_csi_driver = try({
      arn               = aws_eks_addon.ebs_csi_driver[0].arn
      status            = aws_eks_addon.ebs_csi_driver[0].status
      addon_version     = aws_eks_addon.ebs_csi_driver[0].addon_version
      resolve_conflicts = aws_eks_addon.ebs_csi_driver[0].resolve_conflicts
    }, null)
    
    efs_csi_driver = try({
      arn               = aws_eks_addon.efs_csi_driver[0].arn
      status            = aws_eks_addon.efs_csi_driver[0].status
      addon_version     = aws_eks_addon.efs_csi_driver[0].addon_version
      resolve_conflicts = aws_eks_addon.efs_csi_driver[0].resolve_conflicts
    }, null)
  }
}