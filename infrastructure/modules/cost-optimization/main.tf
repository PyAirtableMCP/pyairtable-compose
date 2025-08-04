# Cost Optimization Module for PyAirtable Platform
# Task: cost-1 - Create Terraform cost-optimization module with Spot instance integration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Spot Instance Integration for ECS
resource "aws_ecs_capacity_provider" "fargate_spot" {
  name = "${var.project_name}-${var.environment}-fargate-spot"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.ecs_spot.arn
    
    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity          = var.spot_target_capacity
    }
    
    managed_termination_protection = "DISABLED"
  }

  tags = var.tags
}

# Auto Scaling Group for Spot Instances
resource "aws_autoscaling_group" "ecs_spot" {
  name                = "${var.project_name}-${var.environment}-ecs-spot-asg"
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = var.target_group_arns
  health_check_type   = "ELB"
  
  min_size         = var.min_spot_instances
  max_size         = var.max_spot_instances
  desired_capacity = var.desired_spot_instances

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.ecs_spot.id
        version           = "$Latest"
      }
      
      override {
        instance_type     = "t3.medium"
        weighted_capacity = "1"
      }
      
      override {
        instance_type     = "t3.large"
        weighted_capacity = "2"
      }
    }
    
    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      spot_allocation_strategy                 = "diversified"
      spot_instance_pools                     = 4
      spot_max_price                          = var.spot_max_price
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-ecs-spot"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Launch Template for Spot Instances
resource "aws_launch_template" "ecs_spot" {
  name_prefix   = "${var.project_name}-${var.environment}-ecs-spot-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = "t3.medium"

  vpc_security_group_ids = [aws_security_group.ecs_spot.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_spot.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name = var.cluster_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.project_name}-${var.environment}-ecs-spot"
      Type = "spot"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Optimized AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

# Security Group for Spot Instances
resource "aws_security_group" "ecs_spot" {
  name_prefix = "${var.project_name}-${var.environment}-ecs-spot-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-ecs-spot-sg"
  })
}

# IAM Role for Spot Instances
resource "aws_iam_role" "ecs_spot" {
  name = "${var.project_name}-${var.environment}-ecs-spot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_spot" {
  role       = aws_iam_role.ecs_spot.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_spot" {
  name = "${var.project_name}-${var.environment}-ecs-spot-profile"
  role = aws_iam_role.ecs_spot.name

  tags = var.tags
}

# Scheduled Scaling for Night-time Cost Reduction
resource "aws_autoscaling_schedule" "scale_down_night" {
  count = var.enable_night_scaling ? 1 : 0
  
  scheduled_action_name  = "${var.project_name}-${var.environment}-scale-down-night"
  min_size               = var.night_min_size
  max_size               = var.night_max_size
  desired_capacity       = var.night_desired_capacity
  recurrence            = var.night_scale_down_cron
  auto_scaling_group_name = aws_autoscaling_group.ecs_spot.name
}

resource "aws_autoscaling_schedule" "scale_up_morning" {
  count = var.enable_night_scaling ? 1 : 0
  
  scheduled_action_name  = "${var.project_name}-${var.environment}-scale-up-morning"
  min_size               = var.min_spot_instances
  max_size               = var.max_spot_instances
  desired_capacity       = var.desired_spot_instances
  recurrence            = var.morning_scale_up_cron
  auto_scaling_group_name = aws_autoscaling_group.ecs_spot.name
}

# CloudWatch Alarms for Cost Monitoring
resource "aws_cloudwatch_metric_alarm" "daily_cost_alert" {
  alarm_name          = "${var.project_name}-${var.environment}-daily-cost-alert"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name        = "EstimatedCharges"
  namespace          = "AWS/Billing"
  period             = "86400" # 24 hours
  statistic          = "Maximum"
  threshold          = var.daily_cost_threshold
  alarm_description  = "Daily cost exceeded threshold"
  alarm_actions      = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    Currency = "USD"
  }

  tags = var.tags
}

# SNS Topic for Cost Alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "${var.project_name}-${var.environment}-cost-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "cost_alert_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Cost Allocation Tags
resource "aws_ce_cost_category" "service_costs" {
  name = "${var.project_name}-${var.environment}-service-costs"
  
  rule {
    value = "api-gateway"
    rule {
      dimension {
        key           = "SERVICE"
        values        = ["api-gateway"]
        match_options = ["EQUALS"]
      }
    }
  }
  
  rule {
    value = "platform-services"
    rule {
      dimension {
        key           = "SERVICE"
        values        = ["platform-services"]
        match_options = ["EQUALS"]
      }
    }
  }
  
  rule {
    value = "llm-orchestrator"
    rule {
      dimension {
        key           = "SERVICE"
        values        = ["llm-orchestrator"]
        match_options = ["EQUALS"]
      }
    }
  }

  tags = var.tags
}

# Reserved Capacity for Predictable Workloads
resource "aws_elasticache_reserved_cache_node" "redis_reserved" {
  count                = var.enable_redis_reserved ? 1 : 0
  reserved_cache_node_id = "${var.project_name}-${var.environment}-redis-reserved"
  cache_node_type      = var.redis_node_type
  duration             = var.reserved_duration
  offering_type        = "All Upfront"
  cache_nodes_count    = var.redis_reserved_nodes

  tags = var.tags
}

# Cost Optimization Lambda Function
resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.cost_optimizer.output_path
  function_name    = "${var.project_name}-${var.environment}-cost-optimizer"
  role            = aws_iam_role.cost_optimizer_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.cost_optimizer.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      CLUSTER_NAME     = var.cluster_name
      ENVIRONMENT      = var.environment
      SNS_TOPIC_ARN    = aws_sns_topic.cost_alerts.arn
      COST_THRESHOLD   = var.daily_cost_threshold
    }
  }

  tags = var.tags
}

# Lambda Function Code
data "archive_file" "cost_optimizer" {
  type        = "zip"
  output_path = "${path.module}/cost_optimizer.zip"
  
  source {
    content = templatefile("${path.module}/cost_optimizer.py", {
      cluster_name = var.cluster_name
    })
    filename = "index.py"
  }
}

# IAM Role for Cost Optimizer Lambda
resource "aws_iam_role" "cost_optimizer_role" {
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

  tags = var.tags
}

resource "aws_iam_policy" "cost_optimizer_policy" {
  name = "${var.project_name}-${var.environment}-cost-optimizer-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ecs:DescribeServices",
          "ecs:UpdateService",
          "ecs:DescribeClusters",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cost_optimizer_policy" {
  role       = aws_iam_role.cost_optimizer_role.name
  policy_arn = aws_iam_policy.cost_optimizer_policy.arn
}

# CloudWatch Event Rule for Regular Cost Optimization
resource "aws_cloudwatch_event_rule" "cost_optimization_schedule" {
  name                = "${var.project_name}-${var.environment}-cost-optimization"
  description         = "Trigger cost optimization checks"
  schedule_expression = var.cost_optimization_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "cost_optimizer_target" {
  rule      = aws_cloudwatch_event_rule.cost_optimization_schedule.name
  target_id = "CostOptimizerTarget"
  arn       = aws_lambda_function.cost_optimizer.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_optimization_schedule.arn
}