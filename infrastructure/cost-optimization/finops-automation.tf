# FinOps Automation and Cost Optimization Framework
# Comprehensive cost management, optimization, and reporting

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Local variables for cost optimization
locals {
  # Environment-specific cost targets (monthly USD)
  cost_targets = {
    development = 500
    staging     = 1000
    production  = 5000
  }

  # Cost optimization tags
  cost_tags = {
    CostCenter     = "pyairtable-${var.environment}"
    Project        = var.project_name
    Environment    = var.environment
    AutoShutdown   = var.environment == "development" ? "enabled" : "disabled"
    SpotEligible   = var.environment != "production" ? "true" : "false"
    BackupRequired = var.environment == "production" ? "true" : "false"
    FinOpsManaged  = "true"
  }

  # Service cost allocations (percentage)
  service_cost_allocation = {
    compute      = 50
    database     = 25
    storage      = 10
    networking   = 10
    monitoring   = 5
  }
}

# Random ID for unique naming
resource "random_id" "finops_suffix" {
  byte_length = 4
}

# S3 Bucket for Cost and Usage Reports
resource "aws_s3_bucket" "cost_reports" {
  bucket = "${var.project_name}-${var.environment}-cost-reports-${random_id.finops_suffix.hex}"

  tags = merge(local.cost_tags, {
    Purpose = "cost-reporting"
  })
}

resource "aws_s3_bucket_versioning" "cost_reports" {
  bucket = aws_s3_bucket.cost_reports.id
  versioning_configuration {
    status = "Enabled"
  }
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
      days = 2555  # 7 years for compliance
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# Cost and Usage Report
resource "aws_cur_report_definition" "main" {
  report_name                = "${var.project_name}-${var.environment}-cur"
  time_unit                 = "HOURLY"
  format                    = "Parquet"
  compression               = "GZIP"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                 = aws_s3_bucket.cost_reports.bucket
  s3_prefix                 = "cost-and-usage-reports"
  s3_region                 = var.aws_region
  additional_artifacts      = ["REDSHIFT", "QUICKSIGHT", "ATHENA"]
  refresh_closed_reports    = true
  report_versioning         = "OVERWRITE_REPORT"

  tags = local.cost_tags
}

# SNS Topic for Cost Alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "${var.project_name}-${var.environment}-cost-alerts"

  tags = merge(local.cost_tags, {
    Purpose = "cost-alerting"
  })
}

resource "aws_sns_topic_subscription" "cost_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "cost_slack" {
  count     = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# Cost Budget with Multiple Alert Thresholds
resource "aws_budgets_budget" "monthly_budget" {
  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(local.cost_targets[var.environment])
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())
  time_period_end   = "2087-06-15_00:00"  # Far future date

  cost_filters {
    tag {
      key = "Project"
      values = [var.project_name]
    }
    tag {
      key = "Environment"
      values = [var.environment]
    }
  }

  # Alert at 50% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  # Alert at 80% of budget
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  # Alert at 100% forecasted
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  tags = merge(local.cost_tags, {
    Purpose = "budget-monitoring"
  })
}

# Service-specific budgets
resource "aws_budgets_budget" "service_budgets" {
  for_each = local.service_cost_allocation

  name         = "${var.project_name}-${var.environment}-${each.key}"
  budget_type  = "COST"
  limit_amount = tostring(local.cost_targets[var.environment] * each.value / 100)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filters {
    tag {
      key = "Project"
      values = [var.project_name]
    }
    tag {
      key = "Environment"
      values = [var.environment]
    }
    tag {
      key = "Service"
      values = [each.key]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }

  tags = merge(local.cost_tags, {
    Purpose = "service-budget-${each.key}"
  })
}

# Cost Anomaly Detection
resource "aws_ce_anomaly_detector" "main" {
  name         = "${var.project_name}-${var.environment}-anomaly-detector"
  monitor_type = "DIMENSIONAL"

  monitor_specification = jsonencode({
    Dimension = {
      Key           = "SERVICE"
      Values        = ["Amazon Elastic Compute Cloud - Compute", "Amazon Relational Database Service", "Amazon ElastiCache"]
      MatchOptions  = ["EQUALS"]
    }
    Tags = {
      Key           = "Project"
      Values        = [var.project_name]
      MatchOptions  = ["EQUALS"]
    }
  })

  tags = local.cost_tags
}

resource "aws_ce_anomaly_subscription" "main" {
  name      = "${var.project_name}-${var.environment}-anomaly-subscription"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_detector.main.arn
  ]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  dynamic "subscriber" {
    for_each = var.slack_webhook_url != "" ? [1] : []
    content {
      type    = "SNS"
      address = aws_sns_topic.cost_alerts.arn
    }
  }

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = ["100"]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  tags = local.cost_tags
}

# Lambda Function for Cost Optimization
resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.cost_optimizer_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-cost-optimizer"
  role            = aws_iam_role.cost_optimizer_lambda.arn
  handler         = "cost_optimizer.lambda_handler"
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes
  memory_size     = 512

  environment {
    variables = {
      ENVIRONMENT           = var.environment
      PROJECT_NAME         = var.project_name
      COST_TARGET          = local.cost_targets[var.environment]
      SNS_TOPIC_ARN        = aws_sns_topic.cost_alerts.arn
      ENABLE_AUTO_SCALING  = var.environment != "production" ? "true" : "false"
      SPOT_PERCENTAGE      = var.environment == "development" ? "80" : (var.environment == "staging" ? "50" : "20")
      S3_BUCKET           = aws_s3_bucket.cost_reports.bucket
      SLACK_WEBHOOK_URL   = var.slack_webhook_url
    }
  }

  tags = merge(local.cost_tags, {
    Purpose = "cost-optimization"
  })

  depends_on = [aws_cloudwatch_log_group.cost_optimizer]
}

# Create the Cost Optimizer Lambda deployment package
data "archive_file" "cost_optimizer_zip" {
  type        = "zip"
  output_path = "/tmp/cost_optimizer.zip"
  source {
    content = file("${path.module}/lambda/cost_optimizer.py")
    filename = "cost_optimizer.py"
  }
  source {
    content = file("${path.module}/lambda/requirements.txt")
    filename = "requirements.txt"
  }
}

# CloudWatch Log Group for Cost Optimizer
resource "aws_cloudwatch_log_group" "cost_optimizer" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-cost-optimizer"
  retention_in_days = 30

  tags = merge(local.cost_tags, {
    Purpose = "cost-optimizer-logs"
  })
}

# IAM Role for Cost Optimizer Lambda
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

  tags = merge(local.cost_tags, {
    Purpose = "cost-optimizer-role"
  })
}

# IAM Policy for Cost Optimizer
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
          "ce:GetCostCategories",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization",
          "ce:GetSavingsPlansUtilization",
          "ce:GetSavingsPlansUtilizationDetails",
          "ce:ListCostCategoryDefinitions",
          "budgets:ViewBudget",
          "budgets:DescribeBudgets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateNodegroupVersion"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:DescribeClusters",
          "ecs:ListServices",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:ModifyDBInstance",
          "rds:StopDBInstance",
          "rds:StartDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:ModifyInstanceAttribute",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeReservedInstances",
          "ec2:DescribeReservedInstancesOfferings"
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
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.cost_reports.arn,
          "${aws_s3_bucket.cost_reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "pricing:GetProducts"
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

# CloudWatch Event Rules for Cost Optimization
resource "aws_cloudwatch_event_rule" "daily_cost_check" {
  name                = "${var.project_name}-${var.environment}-daily-cost-check"
  description         = "Trigger daily cost optimization analysis"
  schedule_expression = "cron(0 9 * * ? *)"  # 9 AM UTC daily

  tags = merge(local.cost_tags, {
    Purpose = "cost-monitoring"
  })
}

resource "aws_cloudwatch_event_target" "cost_optimizer_daily" {
  rule      = aws_cloudwatch_event_rule.daily_cost_check.name
  target_id = "CostOptimizerDailyTarget"
  arn       = aws_lambda_function.cost_optimizer.arn

  input = jsonencode({
    action = "daily_analysis"
    include_recommendations = true
  })
}

resource "aws_lambda_permission" "allow_cloudwatch_daily" {
  statement_id  = "AllowDailyExecution"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_check.arn
}

# Weekly Cost Report
resource "aws_cloudwatch_event_rule" "weekly_cost_report" {
  name                = "${var.project_name}-${var.environment}-weekly-cost-report"
  description         = "Generate weekly cost report"
  schedule_expression = "cron(0 10 ? * MON *)"  # 10 AM UTC every Monday

  tags = merge(local.cost_tags, {
    Purpose = "cost-reporting"
  })
}

resource "aws_cloudwatch_event_target" "cost_optimizer_weekly" {
  rule      = aws_cloudwatch_event_rule.weekly_cost_report.name
  target_id = "CostOptimizerWeeklyTarget"
  arn       = aws_lambda_function.cost_optimizer.arn

  input = jsonencode({
    action = "weekly_report"
    include_trends = true
    include_forecasts = true
  })
}

resource "aws_lambda_permission" "allow_cloudwatch_weekly" {
  statement_id  = "AllowWeeklyExecution"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_cost_report.arn
}

# Auto-shutdown for development environment
resource "aws_cloudwatch_event_rule" "auto_shutdown" {
  count = var.environment == "development" ? 1 : 0

  name                = "${var.project_name}-${var.environment}-auto-shutdown"
  description         = "Auto shutdown development resources"
  schedule_expression = "cron(0 22 * * ? *)"  # 10 PM UTC daily

  tags = merge(local.cost_tags, {
    Purpose = "auto-shutdown"
  })
}

resource "aws_cloudwatch_event_target" "auto_shutdown" {
  count = var.environment == "development" ? 1 : 0

  rule      = aws_cloudwatch_event_rule.auto_shutdown[0].name
  target_id = "AutoShutdownTarget"
  arn       = aws_lambda_function.cost_optimizer.arn

  input = jsonencode({
    action = "auto_shutdown"
    services = ["eks", "rds", "elasticache"]
  })
}

resource "aws_lambda_permission" "allow_auto_shutdown" {
  count = var.environment == "development" ? 1 : 0

  statement_id  = "AllowAutoShutdown"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_shutdown[0].arn
}

# CloudWatch Dashboard for Cost Monitoring
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
                label = "Budget Limit ($${local.cost_targets[var.environment]})"
                fill  = "above"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_count", "cluster_name", "${var.project_name}-${var.environment}"],
            ["AWS/EKS", "cluster_failed_node_count", "cluster_name", "${var.project_name}-${var.environment}"]
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "EKS Cluster Nodes (Cost Driver)"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${var.project_name}-${var.environment}-db"],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${var.project_name}-${var.environment}-db"]
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "Database Utilization (Right-sizing Opportunity)"
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "${var.project_name}-${var.environment}-redis"],
            ["AWS/ElastiCache", "CacheHitRate", "CacheClusterId", "${var.project_name}-${var.environment}-redis"]
          ]
          view   = "timeSeries"
          region = var.aws_region
          title  = "Cache Performance vs Cost"
          period = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          query = "SOURCE '/aws/lambda/${var.project_name}-${var.environment}-cost-optimizer'\n| fields @timestamp, @message\n| filter @message like /COST_OPTIMIZATION/\n| sort @timestamp desc\n| limit 50"
          region = var.aws_region
          title  = "Cost Optimization Actions"
          view   = "table"
        }
      }
    ]
  })

  tags = merge(local.cost_tags, {
    Purpose = "cost-dashboard"
  })
}

# CloudWatch Custom Metrics for Cost Tracking
resource "aws_cloudwatch_metric_alarm" "cost_spike_alert" {
  alarm_name          = "${var.project_name}-${var.environment}-cost-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  datapoints_to_alarm = "2"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"  # 24 hours
  statistic           = "Maximum"
  threshold           = local.cost_targets[var.environment] * 1.2  # 20% over budget
  alarm_description   = "Daily cost spike detected - exceeding budget by 20%"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    Currency = "USD"
  }

  tags = merge(local.cost_tags, {
    Purpose = "cost-spike-alert"
  })
}

# Data sources
data "aws_caller_identity" "current" {}

# Outputs for cost optimization summary
output "cost_optimization_summary" {
  description = "Cost optimization features and estimated savings"
  value = {
    monthly_budget = local.cost_targets[var.environment]
    dashboard_url  = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization.dashboard_name}"
    cost_reports_bucket = aws_s3_bucket.cost_reports.bucket
    
    estimated_savings = {
      spot_instances = var.environment == "development" ? "~70%" : (var.environment == "staging" ? "~50%" : "~20%")
      auto_shutdown  = var.environment == "development" ? "~40%" : "N/A"
      right_sizing   = "15-25% through automated optimization"
      reserved_instances = "30-60% for baseline workloads"
    }
    
    optimization_features = {
      budget_alerts        = "Multi-threshold alerts (50%, 80%, 100%)"
      anomaly_detection   = "AI-powered cost anomaly detection"
      daily_optimization  = "Automated daily cost analysis"
      weekly_reporting    = "Comprehensive weekly cost reports"
      auto_shutdown       = var.environment == "development" ? "Enabled (10 PM UTC)" : "Disabled"
      spot_instances      = var.environment != "production" ? "Enabled" : "Limited to non-critical"
      service_budgets     = "Individual budgets per service category"
    }
    
    cost_allocation = local.service_cost_allocation
    
    lambda_functions = {
      cost_optimizer = aws_lambda_function.cost_optimizer.function_name
    }
  }
}

output "finops_monitoring_endpoints" {
  description = "FinOps monitoring and alerting endpoints"
  value = {
    sns_topic_arn     = aws_sns_topic.cost_alerts.arn
    dashboard_name    = aws_cloudwatch_dashboard.cost_optimization.dashboard_name
    budget_names      = merge(
      { "main" = aws_budgets_budget.monthly_budget.name },
      { for k, v in aws_budgets_budget.service_budgets : k => v.name }
    )
    cost_reports_bucket = aws_s3_bucket.cost_reports.bucket
    cur_report_name     = aws_cur_report_definition.main.report_name
  }
}