# Cost Optimization Features for PyAirtable EKS Infrastructure
# AWS Budgets, Cost Anomaly Detection, and Resource Optimization

# AWS Budget for cost monitoring
resource "aws_budgets_budget" "eks_monthly_budget" {
  name         = "${local.cluster_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.cost_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  time_period_start = "2024-01-01_00:00"
  
  cost_filters {
    tag = {
      "Project" = [var.project_name]
      "Environment" = [var.environment]
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.cost_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.cost_alert_emails
  }

  depends_on = [aws_sns_topic.cost_alerts]
}

# SNS Topic for cost alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "${local.name}-cost-alerts"
  
  tags = merge(local.common_tags, {
    Name = "${local.name}-cost-alerts"
  })
}

# SNS Topic subscriptions
resource "aws_sns_topic_subscription" "cost_alert_email" {
  count = length(var.cost_alert_emails)
  
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.cost_alert_emails[count.index]
}

# Cost Anomaly Detection
resource "aws_ce_anomaly_detector" "eks_anomaly_detector" {
  name        = "${local.cluster_name}-anomaly-detector"
  monitor_type = "DIMENSIONAL"

  specification = jsonencode({
    Dimensions = {
      Key = "SERVICE"
      Values = ["Amazon Elastic Container Service for Kubernetes", "Amazon Elastic Compute Cloud - Compute"]
    }
    MatchOptions = ["EQUALS"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-anomaly-detector"
  })
}

# Cost Anomaly Subscription
resource "aws_ce_anomaly_subscription" "eks_anomaly_subscription" {
  name      = "${local.cluster_name}-anomaly-subscription"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_detector.eks_anomaly_detector.arn
  ]
  
  subscriber {
    type    = "EMAIL"
    address = var.cost_alert_emails[0] # Primary email for anomaly alerts
  }

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = ["100"] # Alert for anomalies > $100
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-anomaly-subscription"
  })
}

# CloudWatch Cost Dashboard
resource "aws_cloudwatch_dashboard" "cost_dashboard" {
  dashboard_name = "${local.name}-cost-dashboard"

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
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", "ServiceName", "AmazonEKS"],
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", "ServiceName", "AmazonEC2"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "EKS and EC2 Estimated Charges"
          period  = 86400
          stat    = "Maximum"
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
            ["AWS/EKS", "cluster_node_count", "ClusterName", local.cluster_name],
            ["AWS/EKS", "cluster_running_pod_count", "ClusterName", local.cluster_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "EKS Resource Usage"
          period  = 300
        }
      }
    ]
  })
}

# Lambda function for cost optimization recommendations
resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.cost_optimizer_zip.output_path
  function_name    = "${local.name}-cost-optimizer"
  role            = aws_iam_role.cost_optimizer_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  
  source_code_hash = data.archive_file.cost_optimizer_zip.output_base64sha256

  environment {
    variables = {
      CLUSTER_NAME = local.cluster_name
      ENVIRONMENT  = var.environment
      SNS_TOPIC_ARN = aws_sns_topic.cost_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-cost-optimizer"
  })
}

# Lambda function code
data "archive_file" "cost_optimizer_zip" {
  type        = "zip"
  output_path = "/tmp/cost_optimizer.zip"
  
  source {
    content = templatefile("${path.module}/templates/cost_optimizer.py", {
      cluster_name = local.cluster_name
      environment  = var.environment
    })
    filename = "index.py"
  }
}

# IAM role for cost optimizer Lambda
resource "aws_iam_role" "cost_optimizer_lambda" {
  name = "${local.name}-cost-optimizer-lambda-role"

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

  tags = local.common_tags
}

# IAM policy for cost optimizer Lambda
resource "aws_iam_role_policy" "cost_optimizer_lambda_policy" {
  name = "${local.name}-cost-optimizer-lambda-policy"
  role = aws_iam_role.cost_optimizer_lambda.id

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
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeVolumes",
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_alerts.arn
      }
    ]
  })
}

# CloudWatch Event Rule to trigger cost optimizer weekly
resource "aws_cloudwatch_event_rule" "cost_optimizer_schedule" {
  name                = "${local.name}-cost-optimizer-schedule"
  description         = "Trigger cost optimizer Lambda weekly"
  schedule_expression = "rate(7 days)"

  tags = merge(local.common_tags, {
    Name = "${local.name}-cost-optimizer-schedule"
  })
}

# CloudWatch Event Target
resource "aws_cloudwatch_event_target" "cost_optimizer_target" {
  rule      = aws_cloudwatch_event_rule.cost_optimizer_schedule.name
  target_id = "CostOptimizerTarget"
  arn       = aws_lambda_function.cost_optimizer.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "cost_optimizer_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_optimizer_schedule.arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "cost_optimizer_logs" {
  name              = "/aws/lambda/${local.name}-cost-optimizer"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "${local.name}-cost-optimizer-logs"
  })
}

# Trusted Advisor checks (available with Business/Enterprise support)
resource "aws_cloudwatch_metric_alarm" "trusted_advisor_cost_optimization" {
  count = var.enable_trusted_advisor_monitoring ? 1 : 0

  alarm_name          = "${local.name}-trusted-advisor-cost-optimization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "YellowResources"
  namespace           = "AWS/TrustedAdvisor"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "Trusted Advisor found cost optimization opportunities"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    CheckName = "Low Utilization Amazon EC2 Instances"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-trusted-advisor-cost-optimization"
  })
}

# Resource Groups for cost allocation
resource "aws_resourcegroups_group" "eks_resources" {
  name = "${local.name}-eks-resources"

  resource_query {
    query = jsonencode({
      ResourceTypeFilters = [
        "AWS::EKS::Cluster",
        "AWS::EC2::Instance",
        "AWS::AutoScaling::AutoScalingGroup",
        "AWS::ElasticLoadBalancingV2::LoadBalancer",
        "AWS::EFS::FileSystem",
        "AWS::EBS::Volume"
      ]
      TagFilters = [
        {
          Key = "Project"
          Values = [var.project_name]
        },
        {
          Key = "Environment"
          Values = [var.environment]
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-eks-resources"
  })
}

# Spot Fleet Request for additional cost optimization (if needed)
resource "aws_spot_fleet_request" "cost_optimization_fleet" {
  count = var.enable_additional_spot_fleet ? 1 : 0

  iam_fleet_role      = aws_iam_role.spot_fleet_role[0].arn
  allocation_strategy = "diversified"
  target_capacity     = var.spot_fleet_target_capacity
  valid_until         = timeadd(timestamp(), "8760h") # Valid for 1 year

  launch_specification {
    image_id             = data.aws_ami.eks_worker.id
    instance_type        = "t3.medium"
    key_name            = var.ec2_key_pair_name
    vpc_security_group_ids = [module.security.node_security_group_id]
    subnet_id           = module.vpc.private_subnets[0]
    
    user_data = base64encode(templatefile("${path.module}/templates/spot_fleet_userdata.sh", {
      cluster_name = local.cluster_name
    }))

    root_block_device {
      volume_type = "gp3"
      volume_size = 20
      encrypted   = true
    }
  }

  launch_specification {
    image_id             = data.aws_ami.eks_worker.id
    instance_type        = "t3a.medium"
    key_name            = var.ec2_key_pair_name
    vpc_security_group_ids = [module.security.node_security_group_id]
    subnet_id           = module.vpc.private_subnets[1]
    
    user_data = base64encode(templatefile("${path.module}/templates/spot_fleet_userdata.sh", {
      cluster_name = local.cluster_name
    }))

    root_block_device {
      volume_type = "gp3"
      volume_size = 20
      encrypted   = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-cost-optimization-spot-fleet"
  })
}

# IAM role for Spot Fleet
resource "aws_iam_role" "spot_fleet_role" {
  count = var.enable_additional_spot_fleet ? 1 : 0

  name = "${local.name}-spot-fleet-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "spot_fleet_policy" {
  count = var.enable_additional_spot_fleet ? 1 : 0

  role       = aws_iam_role.spot_fleet_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRequestRole"
}

# Data source for EKS worker AMI
data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.cluster_version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}