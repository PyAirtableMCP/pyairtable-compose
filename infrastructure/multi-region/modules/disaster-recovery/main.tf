# Disaster Recovery Module
# Automated failover procedures and disaster recovery orchestration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# SNS Topic for disaster recovery notifications
resource "aws_sns_topic" "disaster_recovery" {
  name         = "${var.project_name}-${var.environment}-disaster-recovery"
  display_name = "PyAirtable Disaster Recovery Notifications"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-disaster-recovery-topic"
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.disaster_recovery.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "slack" {
  count = var.slack_webhook_url != "" ? 1 : 0

  topic_arn = aws_sns_topic.disaster_recovery.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# DynamoDB table for disaster recovery state management
resource "aws_dynamodb_table" "disaster_recovery_state" {
  name           = "${var.project_name}-${var.environment}-dr-state"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "resource_type"
  range_key      = "resource_id"

  attribute {
    name = "resource_type"
    type = "S"
  }

  attribute {
    name = "resource_id"
    type = "S"
  }

  attribute {
    name = "region"
    type = "S"
  }

  global_secondary_index {
    name     = "region-index"
    hash_key = "region"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-state"
  })
}

# Lambda function for disaster recovery orchestration
resource "aws_lambda_function" "disaster_recovery_orchestrator" {
  filename         = data.archive_file.dr_orchestrator.output_path
  function_name    = "${var.project_name}-${var.environment}-dr-orchestrator"
  role            = aws_iam_role.dr_orchestrator.arn
  handler         = "orchestrator.handler"
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes
  memory_size     = 1024

  source_code_hash = data.archive_file.dr_orchestrator.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME                = var.project_name
      ENVIRONMENT                = var.environment
      DR_STATE_TABLE             = aws_dynamodb_table.disaster_recovery_state.name
      SNS_TOPIC_ARN              = aws_sns_topic.disaster_recovery.arn
      PRIMARY_REGION_RESOURCES   = jsonencode(var.primary_region_resources)
      EU_REGION_RESOURCES        = jsonencode(var.eu_region_resources)
      AP_REGION_RESOURCES        = jsonencode(var.ap_region_resources)
      FAILOVER_THRESHOLD_SECONDS = var.failover_threshold_seconds
      AUTO_FAILOVER_ENABLED      = var.auto_failover_enabled
      RTO_MINUTES                = var.rto_minutes
      RPO_MINUTES                = var.rpo_minutes
    }
  }

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [aws_security_group.dr_lambda.id]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-orchestrator"
  })
}

# Package the Lambda function
data "archive_file" "dr_orchestrator" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/disaster_recovery_orchestrator"
  output_path = "/tmp/disaster_recovery_orchestrator.zip"
}

# Security group for Lambda function
resource "aws_security_group" "dr_lambda" {
  name_prefix = "${var.project_name}-${var.environment}-dr-lambda-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-lambda-sg"
  })
}

# IAM role for disaster recovery orchestrator
resource "aws_iam_role" "dr_orchestrator" {
  name = "${var.project_name}-${var.environment}-dr-orchestrator-role"

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

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-orchestrator-role"
  })
}

# IAM policy for disaster recovery orchestrator
resource "aws_iam_policy" "dr_orchestrator" {
  name        = "${var.project_name}-${var.environment}-dr-orchestrator-policy"
  description = "Policy for disaster recovery orchestrator"

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
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.disaster_recovery_state.arn
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.disaster_recovery.arn
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:FailoverDBCluster",
          "rds:PromoteReadReplica",
          "rds:ModifyDBInstance",
          "rds:CreateDBInstanceReadReplica"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticache:DescribeReplicationGroups",
          "elasticache:DescribeCacheClusters",
          "elasticache:TestFailover",
          "elasticache:ModifyReplicationGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elbv2:DescribeLoadBalancers",
          "elbv2:DescribeTargetGroups",
          "elbv2:DescribeTargetHealth",
          "elbv2:ModifyTargetGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetChange",
          "route53:ListResourceRecordSets",
          "route53:GetHealthCheck"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:UpdateClusterConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:ListTasks",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:PutMetricData"
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
          "arn:aws:s3:::${var.project_name}-${var.environment}-*",
          "arn:aws:s3:::${var.project_name}-${var.environment}-*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dr_orchestrator" {
  role       = aws_iam_role.dr_orchestrator.name
  policy_arn = aws_iam_policy.dr_orchestrator.arn
}

# EventBridge rule for scheduled health checks
resource "aws_cloudwatch_event_rule" "dr_health_check" {
  name                = "${var.project_name}-${var.environment}-dr-health-check"
  description         = "Trigger disaster recovery health checks"
  schedule_expression = "rate(5 minutes)"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-health-check-rule"
  })
}

resource "aws_cloudwatch_event_target" "dr_health_check" {
  rule      = aws_cloudwatch_event_rule.dr_health_check.name
  target_id = "disaster-recovery-orchestrator"
  arn       = aws_lambda_function.disaster_recovery_orchestrator.arn

  input = jsonencode({
    action = "health_check"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_dr_health_check" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disaster_recovery_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dr_health_check.arn
}

# EventBridge rule for manual failover trigger
resource "aws_cloudwatch_event_rule" "manual_failover" {
  name        = "${var.project_name}-${var.environment}-manual-failover"
  description = "Manual failover trigger"
  event_pattern = jsonencode({
    source      = ["custom.disaster-recovery"]
    detail-type = ["Manual Failover Request"]
    detail = {
      project = [var.project_name]
      environment = [var.environment]
    }
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-manual-failover-rule"
  })
}

resource "aws_cloudwatch_event_target" "manual_failover" {
  rule      = aws_cloudwatch_event_rule.manual_failover.name
  target_id = "manual-failover-orchestrator"
  arn       = aws_lambda_function.disaster_recovery_orchestrator.arn

  input_transformer {
    input_paths = {
      action      = "$.detail.action"
      target_region = "$.detail.target_region"
      reason      = "$.detail.reason"
    }
    input_template = jsonencode({
      action        = "<action>"
      target_region = "<target_region>"
      reason        = "<reason>"
      manual        = true
    })
  }
}

resource "aws_lambda_permission" "allow_eventbridge_manual_failover" {
  statement_id  = "AllowExecutionFromEventBridgeManualFailover"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disaster_recovery_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.manual_failover.arn
}

# CloudWatch Alarms for disaster recovery triggers
resource "aws_cloudwatch_metric_alarm" "primary_region_health" {
  alarm_name          = "${var.project_name}-${var.environment}-primary-region-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Primary region health check failed"
  treat_missing_data  = "breaching"

  alarm_actions = [
    aws_sns_topic.disaster_recovery.arn,
    aws_lambda_function.disaster_recovery_orchestrator.arn
  ]

  dimensions = {
    HealthCheckId = var.primary_region_health_check_id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-primary-region-health-alarm"
  })
}

resource "aws_lambda_permission" "allow_cloudwatch_alarm" {
  statement_id  = "AllowExecutionFromCloudWatchAlarm"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disaster_recovery_orchestrator.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.primary_region_health.arn
}

# S3 bucket for disaster recovery artifacts and runbooks
resource "aws_s3_bucket" "disaster_recovery_artifacts" {
  bucket = "${var.project_name}-${var.environment}-dr-artifacts-${random_string.bucket_suffix.result}"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-artifacts"
  })
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_versioning" "disaster_recovery_artifacts" {
  bucket = aws_s3_bucket.disaster_recovery_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "disaster_recovery_artifacts" {
  bucket = aws_s3_bucket.disaster_recovery_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload disaster recovery runbooks
resource "aws_s3_object" "failover_runbook" {
  bucket = aws_s3_bucket.disaster_recovery_artifacts.bucket
  key    = "runbooks/failover_procedures.md"
  source = "${path.module}/runbooks/failover_procedures.md"
  etag   = filemd5("${path.module}/runbooks/failover_procedures.md")

  tags = merge(var.tags, {
    Name = "failover-runbook"
  })
}

resource "aws_s3_object" "recovery_checklist" {
  bucket = aws_s3_bucket.disaster_recovery_artifacts.bucket
  key    = "runbooks/recovery_checklist.md"
  source = "${path.module}/runbooks/recovery_checklist.md"
  etag   = filemd5("${path.module}/runbooks/recovery_checklist.md")

  tags = merge(var.tags, {
    Name = "recovery-checklist"
  })
}

# CloudWatch Dashboard for disaster recovery monitoring
resource "aws_cloudwatch_dashboard" "disaster_recovery" {
  dashboard_name = "${var.project_name}-${var.environment}-disaster-recovery"

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
            ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", var.primary_region_health_check_id],
            [".", ".", ".", var.eu_region_health_check_id],
            [".", ".", ".", var.ap_region_health_check_id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Regional Health Check Status"
          period  = 300
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
            ["AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", var.eu_region_resources.db_instance_id],
            [".", ".", ".", var.ap_region_resources.db_instance_id]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Database Replica Lag"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '/aws/lambda/${aws_lambda_function.disaster_recovery_orchestrator.function_name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Disaster Recovery Orchestrator Logs"
        }
      }
    ]
  })
}

# Custom metric for disaster recovery status
resource "aws_cloudwatch_log_metric_filter" "dr_status" {
  name           = "${var.project_name}-${var.environment}-dr-status"
  log_group_name = "/aws/lambda/${aws_lambda_function.disaster_recovery_orchestrator.function_name}"
  pattern        = "[timestamp, request_id, level=\"INFO\", message=\"DR_STATUS\", status, ...]"

  metric_transformation {
    name      = "DisasterRecoveryStatus"
    namespace = "Custom/DisasterRecovery"
    value     = "$status"
  }
}

# Step Function for complex disaster recovery workflows
resource "aws_sfn_state_machine" "disaster_recovery_workflow" {
  name     = "${var.project_name}-${var.environment}-dr-workflow"
  role_arn = aws_iam_role.step_function_dr.arn

  definition = jsonencode({
    Comment = "Disaster Recovery Workflow"
    StartAt = "AssessFailure"
    States = {
      AssessFailure = {
        Type = "Task"
        Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
        Parameters = {
          action = "assess_failure"
          "Input.$" = "$"
        }
        Next = "DetermineFailoverStrategy"
        Retry = [
          {
            ErrorEquals = ["States.ALL"]
            IntervalSeconds = 5
            MaxAttempts = 3
            BackoffRate = 2.0
          }
        ]
      }
      DetermineFailoverStrategy = {
        Type = "Choice"
        Choices = [
          {
            Variable = "$.failover_required"
            BooleanEquals = true
            Next = "ExecuteFailover"
          }
        ]
        Default = "MonitorAndAlert"
      }
      ExecuteFailover = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "FailoverDatabase"
            States = {
              FailoverDatabase = {
                Type = "Task"
                Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
                Parameters = {
                  action = "failover_database"
                  "Input.$" = "$"
                }
                End = true
              }
            }
          },
          {
            StartAt = "UpdateDNS"
            States = {
              UpdateDNS = {
                Type = "Task"
                Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
                Parameters = {
                  action = "update_dns"
                  "Input.$" = "$"
                }
                End = true
              }
            }
          },
          {
            StartAt = "ScaleServices"
            States = {
              ScaleServices = {
                Type = "Task"
                Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
                Parameters = {
                  action = "scale_services"
                  "Input.$" = "$"
                }
                End = true
              }
            }
          }
        ]
        Next = "ValidateFailover"
      }
      ValidateFailover = {
        Type = "Task"
        Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
        Parameters = {
          action = "validate_failover"
          "Input.$" = "$"
        }
        Next = "NotifyStakeholders"
      }
      MonitorAndAlert = {
        Type = "Task"
        Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
        Parameters = {
          action = "monitor_and_alert"
          "Input.$" = "$"
        }
        End = true
      }
      NotifyStakeholders = {
        Type = "Task"
        Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
        Parameters = {
          action = "notify_stakeholders"
          "Input.$" = "$"
        }
        End = true
      }
    }
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-dr-workflow"
  })
}

# IAM role for Step Function
resource "aws_iam_role" "step_function_dr" {
  name = "${var.project_name}-${var.environment}-step-function-dr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-step-function-dr-role"
  })
}

resource "aws_iam_policy" "step_function_dr" {
  name        = "${var.project_name}-${var.environment}-step-function-dr-policy"
  description = "Policy for disaster recovery Step Function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.disaster_recovery_orchestrator.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_function_dr" {
  role       = aws_iam_role.step_function_dr.name
  policy_arn = aws_iam_policy.step_function_dr.arn
}