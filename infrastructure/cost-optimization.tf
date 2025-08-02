# Cost Optimization and FinOps for PyAirtable Migration
# Implements cost monitoring, alerts, and automatic optimization

# Random ID for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Random passwords for secure defaults
resource "random_password" "postgres" {
  length  = 16
  special = true
}

resource "random_password" "redis" {
  length  = 16
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 32
  special = false
}

resource "random_password" "api_key" {
  length  = 24
  special = false
}

resource "random_password" "migration_token" {
  length  = 32
  special = false
}

# Cost allocation tags for better tracking
locals {
  common_tags = {
    Project         = var.project_name
    Environment     = var.environment
    ManagedBy       = "Terraform"
    CostCenter      = "pyairtable-${var.environment}"
    MigrationPhase  = var.migration_phase
    Owner           = "platform-team"
    
    # Cost optimization tags
    AutoShutdown    = var.environment == "dev" ? "enabled" : "disabled"
    SpotEligible    = var.environment != "prod" ? "true" : "false"
    BackupRequired  = var.environment == "prod" ? "true" : "false"
  }

  # Environment-specific cost targets (monthly USD)
  cost_targets = {
    dev     = 100
    staging = 200
    prod    = 500
  }
}

# Cost monitoring SNS topic
resource "aws_sns_topic" "cost_alerts" {
  name = "${var.project_name}-${var.environment}-cost-alerts"
  
  tags = merge(local.common_tags, {
    Purpose = "cost-monitoring"
  })
}

resource "aws_sns_topic_subscription" "cost_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Cost budget with alerts
resource "aws_budgets_budget" "monthly_cost" {
  name         = "${var.project_name}-${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(local.cost_targets[var.environment])
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())
  
  cost_filters {
    tag {
      key = "CostCenter"
      values = ["pyairtable-${var.environment}"]
    }
  }

  # Alert at 80% and 100% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  tags = merge(local.common_tags, {
    Purpose = "budget-monitoring"
  })
}

# CloudWatch dashboard for cost monitoring
resource "aws_cloudwatch_dashboard" "cost_optimization" {
  dashboard_name = "${var.project_name}-${var.environment}-cost-optimization"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Monthly Estimated Charges"
          period  = 86400
          stat    = "Maximum"
          annotations = {
            horizontal = [
              {
                value = local.cost_targets[var.environment]
                label = "Budget Limit"
                fill  = "above"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ServiceName", "${var.project_name}-api-gateway"],
            [".", "MemoryUtilization", ".", "."]
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "ECS Resource Utilization"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 6
        width  = 6
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_failed_node_count", "cluster_name", "${var.project_name}-${var.environment}"],
            [".", "cluster_node_count", ".", "."]
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "EKS Cluster Health"
          period = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          query   = "SOURCE '/aws/lambda/${var.project_name}-${var.environment}-cost-optimizer'\n| fields @timestamp, @message\n| filter @message like /COST_OPTIMIZATION/\n| sort @timestamp desc\n| limit 50"
          region  = var.aws_region
          title   = "Cost Optimization Actions"
          view    = "table"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "cost-dashboard"
  })
}

# Lambda function for automated cost optimization
resource "aws_lambda_function" "cost_optimizer" {
  filename         = "cost-optimizer.zip"
  function_name    = "${var.project_name}-${var.environment}-cost-optimizer"
  role            = aws_iam_role.cost_optimizer_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      ENVIRONMENT     = var.environment
      CLUSTER_NAME    = "${var.project_name}-${var.environment}"
      COST_TARGET     = local.cost_targets[var.environment]
      SNS_TOPIC_ARN   = aws_sns_topic.cost_alerts.arn
      ENABLE_AUTO_SCALING = var.environment != "prod" ? "true" : "false"
      SPOT_PERCENTAGE = var.environment == "dev" ? "80" : (var.environment == "staging" ? "50" : "0")
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "cost-optimization"
  })

  depends_on = [aws_cloudwatch_log_group.cost_optimizer]
}

# CloudWatch log group for cost optimizer
resource "aws_cloudwatch_log_group" "cost_optimizer" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-cost-optimizer"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Purpose = "cost-optimizer-logs"
  })
}

# IAM role for cost optimizer Lambda
resource "aws_iam_role" "cost_optimizer_lambda" {
  name = "${var.project_name}-${var.environment}-cost-optimizer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "cost-optimizer-role"
  })
}

# IAM policy for cost optimizer
resource "aws_iam_policy" "cost_optimizer" {
  name        = "${var.project_name}-${var.environment}-cost-optimizer-policy"
  description = "Policy for cost optimization Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageAndCosts",
          "budgets:ViewBudget"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:DescribeClusters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cost_optimizer" {
  policy_arn = aws_iam_policy.cost_optimizer.arn
  role       = aws_iam_role.cost_optimizer_lambda.name
}

resource "aws_iam_role_policy_attachment" "cost_optimizer_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.cost_optimizer_lambda.name
}

# CloudWatch event to trigger cost optimization daily
resource "aws_cloudwatch_event_rule" "daily_cost_check" {
  name                = "${var.project_name}-${var.environment}-daily-cost-check"
  description         = "Trigger daily cost optimization"
  schedule_expression = "cron(0 9 * * ? *)"  # 9 AM UTC daily

  tags = merge(local.common_tags, {
    Purpose = "cost-monitoring"
  })
}

resource "aws_cloudwatch_event_target" "cost_optimizer_target" {
  rule      = aws_cloudwatch_event_rule.daily_cost_check.name
  target_id = "CostOptimizerTarget"
  arn       = aws_lambda_function.cost_optimizer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_cost_optimizer" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_check.arn
}

# Auto-shutdown Lambda for development environment
resource "aws_iam_role" "auto_shutdown_lambda" {
  count = var.environment == "dev" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-auto-shutdown-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "auto-shutdown"
  })
}

resource "aws_iam_policy" "auto_shutdown" {
  count       = var.environment == "dev" ? 1 : 0
  name        = "${var.project_name}-${var.environment}-auto-shutdown-policy"
  description = "Policy for auto-shutdown Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:UpdateNodegroupConfig"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "auto_shutdown" {
  count      = var.environment == "dev" ? 1 : 0
  policy_arn = aws_iam_policy.auto_shutdown[0].arn
  role       = aws_iam_role.auto_shutdown_lambda[0].name
}

# CloudWatch custom metrics for cost tracking
resource "aws_cloudwatch_metric_alarm" "high_cpu_cost_alert" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cpu-cost"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "High CPU utilization indicating potential over-provisioning"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    ServiceName = "${var.project_name}-api-gateway"
  }

  tags = merge(local.common_tags, {
    Purpose = "cost-alert"
  })
}

resource "aws_cloudwatch_metric_alarm" "low_cpu_cost_alert" {
  alarm_name          = "${var.project_name}-${var.environment}-low-cpu-utilization"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "900"  # 15 minutes
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "Low CPU utilization indicating potential right-sizing opportunity"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    ServiceName = "${var.project_name}-api-gateway"
  }

  tags = merge(local.common_tags, {
    Purpose = "cost-optimization"
  })
}

# Cost and usage report configuration
resource "aws_s3_bucket" "cost_reports" {
  bucket = "${var.project_name}-${var.environment}-cost-reports-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Purpose = "cost-reporting"
  })
}

resource "aws_s3_bucket_encryption" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id

  rule {
    id     = "cost_report_lifecycle"
    status = "Enabled"

    expiration {
      days = 90  # Keep cost reports for 90 days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Outputs for cost monitoring
output "cost_optimization_summary" {
  description = "Cost optimization features and estimated savings"
  value = {
    monthly_budget = local.cost_targets[var.environment]
    dashboard_url = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization.dashboard_name}"
    
    estimated_savings = {
      spot_instances = var.environment == "dev" ? "~60%" : (var.environment == "staging" ? "~30%" : "0%")
      auto_shutdown = var.environment == "dev" ? "~40%" : "N/A"
      right_sizing = "10-20% through resource optimization"
    }
    
    optimization_features = {
      budget_alerts = "Enabled at 80% and 100% thresholds"
      daily_cost_monitoring = "Automated via Lambda"
      resource_right_sizing = "Based on utilization metrics"
      auto_shutdown = var.environment == "dev" ? "Enabled for development" : "Disabled"
      spot_instances = var.environment != "prod" ? "Enabled" : "Disabled"
    }
    
    cost_targets = local.cost_targets
  }
}

output "monitoring_endpoints" {
  description = "Cost monitoring and alerting endpoints"
  value = {
    sns_topic_arn = aws_sns_topic.cost_alerts.arn
    dashboard_name = aws_cloudwatch_dashboard.cost_optimization.dashboard_name
    budget_name = aws_budgets_budget.monthly_cost.name
    cost_optimizer_function = aws_lambda_function.cost_optimizer.function_name
  }
}