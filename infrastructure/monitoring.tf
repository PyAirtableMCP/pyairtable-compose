# Monitoring and Alerting Infrastructure
# CloudWatch dashboards, alarms, and notification setup

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name = "${var.project_name}-${var.environment}-alerts"
  }
}

# SNS Topic Subscription (Email)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# SNS Topic Subscription (Slack - if webhook provided)
resource "aws_sns_topic_subscription" "slack_alerts" {
  count     = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ECS Service Overview
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            for service in var.services : [
              "AWS/ECS", "CPUUtilization", "ServiceName", "pyairtable-${service}-${var.environment}", "ClusterName", "${var.project_name}-${var.environment}"
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ECS Service CPU Utilization"
          period  = 300
        }
      },

      # Memory utilization
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            for service in var.services : [
              "AWS/ECS", "MemoryUtilization", "ServiceName", "pyairtable-${service}-${var.environment}", "ClusterName", "${var.project_name}-${var.environment}"
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ECS Service Memory Utilization"
          period  = 300
        }
      },

      # Running tasks count
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            for service in var.services : [
              "AWS/ECS", "RunningTaskCount", "ServiceName", "pyairtable-${service}-${var.environment}", "ClusterName", "${var.project_name}-${var.environment}"
            ]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ECS Running Tasks"
          period  = 300
        }
      },

      # ALB Request Count
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ALB Request Count"
          period  = 300
        }
      },

      # ALB Response Time
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ALB Response Time"
          period  = 300
        }
      },

      # ALB Error Rates
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_4XX_Count", "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.main.arn_suffix]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ALB Error Rates"
          period  = 300
        }
      },

      # Database metrics (if RDS enabled)
      {
        type   = var.enable_rds ? "metric" : "text"
        x      = 0
        y      = 18
        width  = 12
        height = 6

        properties = var.enable_rds ? {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${var.project_name}-${var.environment}-db"],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${var.project_name}-${var.environment}-db"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "RDS Metrics"
          period  = 300
        } : {
          markdown = "## RDS Disabled\n\nRDS monitoring not available as RDS is disabled for this environment."
        }
      },

      # ElastiCache metrics (if enabled)
      {
        type   = var.enable_elasticache ? "metric" : "text"
        x      = 12
        y      = 18
        width  = 12
        height = 6

        properties = var.enable_elasticache ? {
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", "${var.project_name}-${var.environment}-redis"],
            ["AWS/ElastiCache", "CacheHitRate", "CacheClusterId", "${var.project_name}-${var.environment}-redis"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "ElastiCache Metrics"
          period  = 300
        } : {
          markdown = "## ElastiCache Disabled\n\nElastiCache monitoring not available as Redis is disabled for this environment."
        }
      }
    ]
  })
}

# CloudWatch Alarms

# ECS Service CPU Alarms
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  for_each = var.service_configs

  alarm_name          = "${var.project_name}-${each.key}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ${each.key} cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = "pyairtable-${each.key}-${var.environment}"
    ClusterName = "${var.project_name}-${var.environment}"
  }

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}-cpu-alarm"
  }
}

# ECS Service Memory Alarms
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  for_each = var.service_configs

  alarm_name          = "${var.project_name}-${each.key}-${var.environment}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "This metric monitors ${each.key} memory utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = "pyairtable-${each.key}-${var.environment}"
    ClusterName = "${var.project_name}-${var.environment}"
  }

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}-memory-alarm"
  }
}

# ECS Service Task Count Alarms (for production)
resource "aws_cloudwatch_metric_alarm" "ecs_task_count_low" {
  for_each = var.environment == "prod" ? var.service_configs : {}

  alarm_name          = "${var.project_name}-${each.key}-${var.environment}-task-count-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ${each.key} running task count"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    ServiceName = "pyairtable-${each.key}-${var.environment}"
    ClusterName = "${var.project_name}-${var.environment}"
  }

  tags = {
    Name = "${var.project_name}-${each.key}-${var.environment}-task-count-alarm"
  }
}

# ALB Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "alb_response_time_high" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-response-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.environment == "prod" ? "1" : "2"
  alarm_description   = "This metric monitors ALB response time"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-response-time-alarm"
  }
}

# ALB Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "alb_error_rate_high" {
  alarm_name          = "${var.project_name}-${var.environment}-alb-error-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors ALB 5XX error count"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-error-rate-alarm"
  }
}

# Database Alarms (if RDS enabled)
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.enable_rds ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = "${var.project_name}-${var.environment}-db"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-cpu-alarm"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  count = var.enable_rds ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric monitors RDS connection count"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = "${var.project_name}-${var.environment}-db"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-connections-alarm"
  }
}

# ElastiCache Alarms (if enabled)
resource "aws_cloudwatch_metric_alarm" "elasticache_cpu_high" {
  count = var.enable_elasticache ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-elasticache-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ElastiCache CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  dimensions = {
    CacheClusterId = "${var.project_name}-${var.environment}-redis"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-elasticache-cpu-alarm"
  }
}

# Custom Application Metrics

# CloudWatch Log Group for Custom Metrics
resource "aws_cloudwatch_log_group" "custom_metrics" {
  name              = "/aws/lambda/${var.project_name}-${var.environment}-custom-metrics"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-custom-metrics-logs"
  }
}

# Lambda function for custom metrics collection
resource "aws_lambda_function" "custom_metrics" {
  filename         = "custom_metrics.zip"
  function_name    = "${var.project_name}-${var.environment}-custom-metrics"
  role            = aws_iam_role.lambda_metrics_role.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT_NAME = var.project_name
      CLUSTER_NAME = aws_ecs_cluster.main.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_metrics_policy,
    aws_cloudwatch_log_group.custom_metrics,
    data.archive_file.custom_metrics_zip
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-custom-metrics"
  }
}

# Create the Lambda deployment package
data "archive_file" "custom_metrics_zip" {
  type        = "zip"
  output_path = "custom_metrics.zip"
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime

def handler(event, context):
    cloudwatch = boto3.client('cloudwatch')
    ecs = boto3.client('ecs')
    
    cluster_name = os.environ['CLUSTER_NAME']
    project_name = os.environ['PROJECT_NAME']
    environment = os.environ['ENVIRONMENT']
    
    try:
        # Get ECS services
        services = ecs.list_services(cluster=cluster_name)
        
        for service_arn in services['serviceArns']:
            service_name = service_arn.split('/')[-1]
            
            # Get service details
            service_details = ecs.describe_services(
                cluster=cluster_name,
                services=[service_arn]
            )
            
            service = service_details['services'][0]
            
            # Custom metrics
            running_count = service['runningCount']
            desired_count = service['desiredCount']
            pending_count = service['pendingCount']
            
            # Health ratio
            health_ratio = (running_count / desired_count * 100) if desired_count > 0 else 0
            
            # Send custom metrics
            cloudwatch.put_metric_data(
                Namespace=f'{project_name}/{environment}/Custom',
                MetricData=[
                    {
                        'MetricName': 'ServiceHealthRatio',
                        'Dimensions': [
                            {
                                'Name': 'ServiceName',
                                'Value': service_name
                            },
                            {
                                'Name': 'Environment',
                                'Value': environment
                            }
                        ],
                        'Value': health_ratio,
                        'Unit': 'Percent',
                        'Timestamp': datetime.utcnow()
                    },
                    {
                        'MetricName': 'PendingTaskCount',
                        'Dimensions': [
                            {
                                'Name': 'ServiceName',
                                'Value': service_name
                            },
                            {
                                'Name': 'Environment',
                                'Value': environment
                            }
                        ],
                        'Value': pending_count,
                        'Unit': 'Count',
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Custom metrics published successfully')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_metrics_role" {
  name = "${var.project_name}-${var.environment}-lambda-metrics-role"

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
}

# IAM policy for Lambda
resource "aws_iam_policy" "lambda_metrics_policy" {
  name        = "${var.project_name}-${var.environment}-lambda-metrics-policy"
  description = "Policy for custom metrics Lambda function"

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:ListServices",
          "ecs:DescribeServices",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_metrics_policy" {
  role       = aws_iam_role.lambda_metrics_role.name
  policy_arn = aws_iam_policy.lambda_metrics_policy.arn
}

# Schedule the Lambda function to run every 5 minutes
resource "aws_cloudwatch_event_rule" "custom_metrics_schedule" {
  name                = "${var.project_name}-${var.environment}-custom-metrics-schedule"
  description         = "Trigger custom metrics collection"
  schedule_expression = "rate(5 minutes)"

  tags = {
    Name = "${var.project_name}-${var.environment}-custom-metrics-schedule"
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.custom_metrics_schedule.name
  target_id = "CustomMetricsLambdaTarget"
  arn       = aws_lambda_function.custom_metrics.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custom_metrics.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custom_metrics_schedule.arn
}

# Application Insights (for advanced monitoring in production)
resource "aws_applicationinsights_application" "main" {
  count = var.environment == "prod" ? 1 : 0

  resource_group_name                = aws_resourcegroups_group.main[0].name
  auto_config_enabled               = true
  auto_create                       = true
  cwe_monitor_enabled              = true
  ops_center_enabled               = true
  ops_item_sns_topic_arn           = aws_sns_topic.alerts.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-app-insights"
  }
}

# Resource group for Application Insights
resource "aws_resourcegroups_group" "main" {
  count = var.environment == "prod" ? 1 : 0

  name = "${var.project_name}-${var.environment}-resources"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = [
        "AWS::ECS::Service",
        "AWS::ECS::Cluster",
        "AWS::ElasticLoadBalancingV2::LoadBalancer",
        "AWS::RDS::DBInstance",
        "AWS::ElastiCache::CacheCluster"
      ]
      TagFilters = [
        {
          Key    = "Project"
          Values = [var.project_name]
        },
        {
          Key    = "Environment"
          Values = [var.environment]
        }
      ]
    })
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-resource-group"
  }
}