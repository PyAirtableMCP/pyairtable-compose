# Karpenter Module Outputs

# Karpenter Controller
output "karpenter_controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_controller[0].arn : null
}

output "karpenter_controller_role_name" {
  description = "Name of the Karpenter controller IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_controller[0].name : null
}

# Karpenter Node Instance Role
output "karpenter_node_instance_role_arn" {
  description = "ARN of the Karpenter node instance IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_node_instance_role[0].arn : null
}

output "karpenter_node_instance_role_name" {
  description = "Name of the Karpenter node instance IAM role"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_node_instance_role[0].name : null
}

output "karpenter_instance_profile_name" {
  description = "Name of the Karpenter instance profile"
  value       = var.enable_karpenter ? aws_iam_instance_profile.karpenter[0].name : null
}

output "karpenter_instance_profile_arn" {
  description = "ARN of the Karpenter instance profile"
  value       = var.enable_karpenter ? aws_iam_instance_profile.karpenter[0].arn : null
}

# SQS Queue
output "karpenter_sqs_queue_name" {
  description = "Name of the Karpenter SQS queue"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter[0].name : null
}

output "karpenter_sqs_queue_arn" {
  description = "ARN of the Karpenter SQS queue"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter[0].arn : null
}

output "karpenter_sqs_queue_url" {
  description = "URL of the Karpenter SQS queue"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter[0].url : null
}

# EventBridge Rules
output "spot_interruption_rule_name" {
  description = "Name of the spot interruption EventBridge rule"
  value       = var.enable_karpenter ? aws_cloudwatch_event_rule.karpenter_spot_interruption[0].name : null
}

output "instance_state_change_rule_name" {
  description = "Name of the instance state change EventBridge rule"
  value       = var.enable_karpenter ? aws_cloudwatch_event_rule.karpenter_instance_state_change[0].name : null
}

# Kubernetes Resources
output "karpenter_namespace" {
  description = "Karpenter namespace name"
  value       = var.enable_karpenter ? kubernetes_namespace.karpenter[0].metadata[0].name : null
}

output "karpenter_helm_release_name" {
  description = "Karpenter Helm release name"
  value       = var.enable_karpenter ? helm_release.karpenter[0].name : null
}

output "karpenter_helm_release_version" {
  description = "Karpenter Helm release version"
  value       = var.enable_karpenter ? helm_release.karpenter[0].version : null
}

# Provisioners
output "general_provisioner_name" {
  description = "Name of the general purpose Karpenter provisioner"
  value       = var.enable_karpenter ? kubernetes_manifest.karpenter_provisioner_general[0].manifest.metadata.name : null
}

output "burstable_provisioner_name" {
  description = "Name of the burstable Karpenter provisioner"
  value       = var.enable_karpenter && var.enable_burstable_provisioner ? kubernetes_manifest.karpenter_provisioner_burstable[0].manifest.metadata.name : null
}

# Node Classes
output "general_node_class_name" {
  description = "Name of the general purpose EC2NodeClass"
  value       = var.enable_karpenter ? kubernetes_manifest.karpenter_node_pool_general[0].manifest.metadata.name : null
}

output "burstable_node_class_name" {
  description = "Name of the burstable EC2NodeClass"
  value       = var.enable_karpenter && var.enable_burstable_provisioner ? kubernetes_manifest.karpenter_node_pool_burstable[0].manifest.metadata.name : null
}

# Configuration Summary
output "karpenter_summary" {
  description = "Summary of Karpenter configuration"
  value = var.enable_karpenter ? {
    enabled                    = true
    chart_version             = var.karpenter_chart_version
    controller_role_arn       = aws_iam_role.karpenter_controller[0].arn
    node_instance_profile     = aws_iam_instance_profile.karpenter[0].name
    sqs_queue_name           = aws_sqs_queue.karpenter[0].name
    supported_instance_types  = var.instance_types
    capacity_types           = var.capacity_types
    spot_allocation_strategy = var.spot_allocation_strategy
    burstable_provisioner_enabled = var.enable_burstable_provisioner
    ttl_after_empty          = var.ttl_seconds_after_empty
    ttl_until_expired        = var.ttl_seconds_until_expired
    max_cpu_limit            = var.max_cpu_limit
    max_memory_limit         = var.max_memory_limit
  } : {
    enabled = false
  }
}