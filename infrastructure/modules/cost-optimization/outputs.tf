# Outputs for Cost Optimization Module
# Task: cost-1 - Create Terraform cost-optimization module with Spot instance integration

output "capacity_provider_name" {
  description = "Name of the Fargate Spot capacity provider"
  value       = aws_ecs_capacity_provider.fargate_spot.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group for spot instances"
  value       = aws_autoscaling_group.ecs_spot.arn
}

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group for spot instances"
  value       = aws_autoscaling_group.ecs_spot.name
}

output "launch_template_id" {
  description = "ID of the launch template for spot instances"
  value       = aws_launch_template.ecs_spot.id
}

output "security_group_id" {
  description = "Security group ID for spot instances"
  value       = aws_security_group.ecs_spot.id
}

output "iam_role_arn" {
  description = "IAM role ARN for spot instances"
  value       = aws_iam_role.ecs_spot.arn
}

output "iam_instance_profile_name" {
  description = "IAM instance profile name for spot instances"
  value       = aws_iam_instance_profile.ecs_spot.name
}

output "cost_alerts_topic_arn" {
  description = "SNS topic ARN for cost alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "cost_optimizer_function_name" {
  description = "Lambda function name for cost optimization"
  value       = aws_lambda_function.cost_optimizer.function_name
}

output "cost_optimizer_function_arn" {
  description = "Lambda function ARN for cost optimization"
  value       = aws_lambda_function.cost_optimizer.arn
}

output "cost_category_arn" {
  description = "Cost category ARN for service cost allocation"
  value       = aws_ce_cost_category.service_costs.arn
}

output "daily_cost_alarm_name" {
  description = "CloudWatch alarm name for daily cost monitoring"
  value       = aws_cloudwatch_metric_alarm.daily_cost_alert.alarm_name
}

output "scheduled_scaling_policies" {
  description = "Scheduled scaling policy names"
  value = {
    night_scale_down = var.enable_night_scaling ? aws_autoscaling_schedule.scale_down_night[0].scheduled_action_name : null
    morning_scale_up = var.enable_night_scaling ? aws_autoscaling_schedule.scale_up_morning[0].scheduled_action_name : null
  }
}

output "cost_optimization_schedule_rule" {
  description = "CloudWatch event rule for cost optimization schedule"
  value       = aws_cloudwatch_event_rule.cost_optimization_schedule.name
}

output "reserved_cache_node_id" {
  description = "Reserved cache node ID (if enabled)"
  value       = var.enable_redis_reserved ? aws_elasticache_reserved_cache_node.redis_reserved[0].reserved_cache_node_id : null
}

# Cost estimation outputs
output "estimated_monthly_savings" {
  description = "Estimated monthly savings from spot instances"
  value = {
    spot_savings_percentage = var.on_demand_percentage < 50 ? (100 - var.on_demand_percentage) * 0.6 : 0
    night_scaling_savings   = var.enable_night_scaling ? var.night_scale_down_percentage * 0.4 : 0
    total_estimated_savings = "30-50% based on workload patterns"
  }
}

output "cost_monitoring_dashboard_url" {
  description = "URL to AWS Cost Explorer dashboard (manual setup required)"
  value       = "https://console.aws.amazon.com/cost-management/home#/dashboard"
}

output "spot_instance_configuration" {
  description = "Spot instance configuration summary"
  value = {
    spot_percentage         = 100 - var.on_demand_percentage
    max_spot_price         = var.spot_max_price
    diversification_pools  = 4
    allocation_strategy    = "diversified"
    interruption_handling  = "enabled"
  }
}

output "cost_optimization_metrics" {
  description = "Key metrics for cost optimization monitoring"
  value = {
    daily_cost_threshold    = var.daily_cost_threshold
    optimization_frequency  = var.cost_optimization_schedule
    night_scaling_enabled   = var.enable_night_scaling
    reserved_capacity       = var.enable_redis_reserved
  }
}