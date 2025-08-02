# Autoscaling and Cost Optimization for PyAirtable
# Intelligent scaling policies with spot instances and cost controls

# Horizontal Pod Autoscaler (HPA) for Go services
resource "kubernetes_horizontal_pod_autoscaler_v2" "go_services_hpa" {
  for_each = toset(["api-gateway", "platform-services", "automation-services"])
  
  metadata {
    name      = "${each.key}-hpa"
    namespace = "pyairtable"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = each.key
    }

    min_replicas = 1
    max_replicas = var.environment == "prod" ? 10 : 5

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    # Scale down behavior - aggressive for cost savings
    behavior {
      scale_down {
        stabilization_window_seconds = 300
        select_policy               = "Min"
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
        policy {
          type          = "Pods"
          value         = 2
          period_seconds = 60
        }
      }
      
      scale_up {
        stabilization_window_seconds = 60
        select_policy               = "Max"
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 60
        }
        policy {
          type          = "Pods"
          value         = 2
          period_seconds = 60
        }
      }
    }
  }
}

# HPA for Python AI services (different scaling characteristics)
resource "kubernetes_horizontal_pod_autoscaler_v2" "python_ai_hpa" {
  for_each = toset(["llm-orchestrator", "mcp-server"])
  
  metadata {
    name      = "${each.key}-hpa"
    namespace = "pyairtable"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = each.key
    }

    min_replicas = 1
    max_replicas = var.environment == "prod" ? 6 : 3

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60  # Lower threshold for AI workloads
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 75
        }
      }
    }

    # More conservative scaling for AI services
    behavior {
      scale_down {
        stabilization_window_seconds = 600  # 10 minutes
        select_policy               = "Min"
        policy {
          type          = "Percent"
          value         = 25
          period_seconds = 120
        }
      }
      
      scale_up {
        stabilization_window_seconds = 120
        select_policy               = "Max"
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 120
        }
      }
    }
  }
}

# Vertical Pod Autoscaler (VPA) for database and static services
resource "kubernetes_manifest" "postgres_vpa" {
  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      name      = "postgres-vpa"
      namespace = "pyairtable"
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "StatefulSet"
        name       = "postgres"
      }
      updatePolicy = {
        updateMode = "Off"  # Recommendation only to avoid disrupting stateful services
      }
      resourcePolicy = {
        containerPolicies = [{
          containerName = "postgres"
          minAllowed = {
            cpu    = "250m"
            memory = "512Mi"
          }
          maxAllowed = {
            cpu    = "2000m"
            memory = "4Gi"
          }
        }]
      }
    }
  }
}

# Cost optimization: Pod Disruption Budgets
resource "kubernetes_pod_disruption_budget_v1" "go_services_pdb" {
  for_each = toset(["api-gateway", "platform-services"])
  
  metadata {
    name      = "${each.key}-pdb"
    namespace = "pyairtable"
  }
  
  spec {
    min_available = "50%"
    selector {
      match_labels = {
        app = each.key
      }
    }
  }
}

# Spot instance optimization: Node pool with mixed instance types
resource "aws_eks_node_group" "spot_optimized" {
  count = var.enable_spot_instances ? 1 : 0
  
  cluster_name    = aws_eks_cluster.pyairtable.name
  node_group_name = "spot-optimized"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  # Mixed instance types for better spot availability
  instance_types = ["t3.medium", "t3.large", "t3a.medium", "t3a.large", "m5.large", "m5a.large"]
  capacity_type  = "SPOT"
  
  scaling_config {
    desired_size = 2
    max_size     = 8
    min_size     = 0  # Can scale to zero for maximum cost savings
  }

  update_config {
    max_unavailable_percentage = 50  # Allow more disruption for cost savings
  }

  # Taints for spot instances
  taint {
    key    = "spot-instance"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    "node.kubernetes.io/instance-lifecycle" = "spot"
    "workload"                              = "batch-processing"
  }

  tags = {
    Name                              = "${var.project_name}-spot-optimized"
    Environment                       = var.environment
    "k8s.io/cluster-autoscaler/enabled" = "true"
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.pyairtable.name}" = "owned"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# Spot Fleet Request for additional cost savings
resource "aws_spot_fleet_request" "batch_processing" {
  count = var.enable_spot_fleet ? 1 : 0
  
  iam_fleet_role      = aws_iam_role.spot_fleet[0].arn
  allocation_strategy = "diversified"
  target_capacity     = 2
  spot_price         = "0.05"  # Maximum price per hour
  
  # Multiple instance types and AZs for better availability
  launch_specification {
    image_id      = data.aws_ami.eks_optimized.id
    instance_type = "t3.medium"
    subnet_id     = aws_subnet.private[0].id
    
    vpc_security_group_ids = [aws_eks_cluster.pyairtable.vpc_config[0].cluster_security_group_id]
    
    user_data = base64encode(templatefile("${path.module}/spot-userdata.tpl", {
      cluster_name = aws_eks_cluster.pyairtable.name
      endpoint     = aws_eks_cluster.pyairtable.endpoint
      ca_cert      = aws_eks_cluster.pyairtable.certificate_authority[0].data
    }))
    
    tags = {
      Name = "${var.project_name}-spot-instance"
    }
  }
  
  launch_specification {
    image_id      = data.aws_ami.eks_optimized.id
    instance_type = "t3.large"
    subnet_id     = aws_subnet.private[1].id
    
    vpc_security_group_ids = [aws_eks_cluster.pyairtable.vpc_config[0].cluster_security_group_id]
    
    user_data = base64encode(templatefile("${path.module}/spot-userdata.tpl", {
      cluster_name = aws_eks_cluster.pyairtable.name
      endpoint     = aws_eks_cluster.pyairtable.endpoint
      ca_cert      = aws_eks_cluster.pyairtable.certificate_authority[0].data
    }))
    
    tags = {
      Name = "${var.project_name}-spot-instance"
    }
  }
  
  tags = {
    Name        = "${var.project_name}-spot-fleet"
    Environment = var.environment
  }
}

# IAM role for Spot Fleet
resource "aws_iam_role" "spot_fleet" {
  count = var.enable_spot_fleet ? 1 : 0
  name  = "${var.project_name}-${var.environment}-spot-fleet-role"

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
}

resource "aws_iam_role_policy_attachment" "spot_fleet" {
  count      = var.enable_spot_fleet ? 1 : 0
  role       = aws_iam_role.spot_fleet[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRequestRole"
}

# Cost optimization: Fargate profiles for specific workloads
resource "aws_eks_fargate_profile" "batch_jobs" {
  cluster_name           = aws_eks_cluster.pyairtable.name
  fargate_profile_name   = "batch-jobs"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids            = aws_subnet.private[*].id

  selector {
    namespace = "batch-processing"
    labels = {
      workload = "batch-job"
    }
  }

  tags = {
    Name = "${var.project_name}-batch-jobs-fargate"
  }
}

# IAM role for Fargate pod execution
resource "aws_iam_role" "fargate_pod_execution" {
  name = "${var.project_name}-${var.environment}-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution.name
}

# Cost optimization: Scheduled scaling for predictable workloads
resource "aws_autoscaling_schedule" "scale_down_evening" {
  count = var.environment != "prod" ? 1 : 0
  
  scheduled_action_name  = "${var.project_name}-scale-down-evening"
  min_size              = 0
  max_size              = 2
  desired_capacity      = 1
  recurrence            = "0 22 * * MON-FRI"  # 10 PM weekdays
  time_zone             = "UTC"
  autoscaling_group_name = aws_eks_node_group.general_services.resources[0].autoscaling_groups[0].name
}

resource "aws_autoscaling_schedule" "scale_up_morning" {
  count = var.environment != "prod" ? 1 : 0
  
  scheduled_action_name  = "${var.project_name}-scale-up-morning"
  min_size              = 1
  max_size              = 4
  desired_capacity      = 2
  recurrence            = "0 8 * * MON-FRI"   # 8 AM weekdays
  time_zone             = "UTC"
  autoscaling_group_name = aws_eks_node_group.general_services.resources[0].autoscaling_groups[0].name
}

# CloudWatch metrics for cost monitoring
resource "aws_cloudwatch_metric_alarm" "high_cost_alarm" {
  alarm_name          = "${var.project_name}-${var.environment}-high-cost-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"  # Daily
  statistic           = "Maximum"
  threshold           = var.environment == "prod" ? "600" : "300"
  alarm_description   = "This metric monitors estimated charges"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    Currency = "USD"
  }

  tags = {
    Name = "${var.project_name}-cost-alarm"
  }
}

# Resource quotas to prevent runaway costs
resource "kubernetes_resource_quota" "compute_quota" {
  metadata {
    name      = "compute-quota"
    namespace = "pyairtable"
  }
  
  spec {
    hard = {
      "requests.cpu"    = var.environment == "prod" ? "20" : "10"
      "requests.memory" = var.environment == "prod" ? "40Gi" : "20Gi"
      "limits.cpu"      = var.environment == "prod" ? "40" : "20"
      "limits.memory"   = var.environment == "prod" ? "80Gi" : "40Gi"
      "pods"           = var.environment == "prod" ? "50" : "25"
    }
  }
}

# Limit ranges for individual pods
resource "kubernetes_limit_range" "pod_limits" {
  metadata {
    name      = "pod-limits"
    namespace = "pyairtable"
  }
  
  spec {
    limit {
      type = "Pod"
      max = {
        cpu    = "2000m"
        memory = "4Gi"
      }
      min = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
    
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "250m"
        memory = "256Mi"
      }
    }
  }
}

# Cost optimization outputs
output "cost_optimization_enabled" {
  description = "Cost optimization features enabled"
  value = {
    spot_instances     = var.enable_spot_instances
    spot_fleet        = var.enable_spot_fleet
    scheduled_scaling = var.environment != "prod"
    fargate_batch     = true
    resource_quotas   = true
  }
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    eks_cluster       = "72"      # $0.10/hour * 24 * 30
    node_groups_spot  = "180"     # ~$0.25/hour * 24 * 30 (70% savings)
    rds_serverless    = "120"     # Aurora Serverless v2 minimum
    redis             = "45"      # t3.micro * 2 instances
    lambda_functions  = "20"      # Conservative estimate
    s3_storage       = "15"      # 100GB + requests
    data_transfer    = "30"      # Inter-AZ and egress
    monitoring       = "25"      # CloudWatch + alerts
    total            = "507"     # Total estimated cost
  }
}