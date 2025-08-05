# IAM Module Outputs

# Cluster Service Role
output "cluster_service_role_arn" {
  description = "ARN of the EKS cluster service role"
  value       = aws_iam_role.cluster_service_role.arn
}

output "cluster_service_role_name" {
  description = "Name of the EKS cluster service role"
  value       = aws_iam_role.cluster_service_role.name
}

# Node Instance Role
output "node_instance_role_arn" {
  description = "ARN of the EKS node instance role"
  value       = aws_iam_role.node_instance_role.arn
}

output "node_instance_role_name" {
  description = "Name of the EKS node instance role"
  value       = aws_iam_role.node_instance_role.name
}

output "node_instance_profile_name" {
  description = "Name of the EKS node instance profile"
  value       = aws_iam_instance_profile.node_instance_profile.name
}

output "node_instance_profile_arn" {
  description = "ARN of the EKS node instance profile"
  value       = aws_iam_instance_profile.node_instance_profile.arn
}

# IRSA Roles
output "vpc_cni_irsa_role_arn" {
  description = "ARN of the VPC CNI IRSA role"
  value       = aws_iam_role.vpc_cni_irsa.arn
}

output "ebs_csi_irsa_role_arn" {
  description = "ARN of the EBS CSI IRSA role"
  value       = aws_iam_role.ebs_csi_irsa.arn
}

output "efs_csi_irsa_role_arn" {
  description = "ARN of the EFS CSI IRSA role"
  value       = aws_iam_role.efs_csi_irsa.arn
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role"
  value       = aws_iam_role.cluster_autoscaler_irsa.arn
}

output "load_balancer_controller_irsa_role_arn" {
  description = "ARN of the Load Balancer Controller IRSA role"
  value       = aws_iam_role.load_balancer_controller_irsa.arn
}

output "external_secrets_irsa_role_arn" {
  description = "ARN of the External Secrets IRSA role"
  value       = aws_iam_role.external_secrets_irsa.arn
}

output "cloudwatch_agent_irsa_role_arn" {
  description = "ARN of the CloudWatch Agent IRSA role"
  value       = aws_iam_role.cloudwatch_agent_irsa.arn
}

# All IRSA roles for convenience
output "irsa_roles" {
  description = "Map of all IRSA role ARNs"
  value = {
    vpc_cni                 = aws_iam_role.vpc_cni_irsa.arn
    ebs_csi                = aws_iam_role.ebs_csi_irsa.arn
    efs_csi                = aws_iam_role.efs_csi_irsa.arn
    cluster_autoscaler     = aws_iam_role.cluster_autoscaler_irsa.arn
    load_balancer_controller = aws_iam_role.load_balancer_controller_irsa.arn
    external_secrets       = aws_iam_role.external_secrets_irsa.arn
    cloudwatch_agent       = aws_iam_role.cloudwatch_agent_irsa.arn
  }
}