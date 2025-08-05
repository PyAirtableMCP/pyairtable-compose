# Karpenter Module for PyAirtable EKS Infrastructure
# Advanced auto-scaling and cost optimization

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

locals {
  name = "${var.project_name}-${var.environment}"
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Karpenter IAM Role
resource "aws_iam_role" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name = "${local.name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
            "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Karpenter Controller Policy
resource "aws_iam_role_policy" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name = "${local.name}-karpenter-controller-policy"
  role = aws_iam_role.karpenter_controller[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "iam:PassRole",
          "ec2:DescribeImages",
          "ec2:RunInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DeleteLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = data.aws_region.current.name
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/provisioner-name" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*"
        ]
        Condition = {
          StringLike = {
            "ec2:ResourceTag/karpenter.sh/provisioner-name" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances"
        ]
        Resource = [
          "arn:aws:ec2:*::image/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:subnet/*"
        ]
      }
    ]
  })
}

# Karpenter Node Instance Role
resource "aws_iam_role" "karpenter_node_instance_role" {
  count = var.enable_karpenter ? 1 : 0

  name = "${local.name}-karpenter-node-instance-role"

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

# Attach AWS managed policies to Karpenter node role
resource "aws_iam_role_policy_attachment" "karpenter_node_instance_role_policy" {
  for_each = var.enable_karpenter ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]) : []

  policy_arn = each.value
  role       = aws_iam_role.karpenter_node_instance_role[0].name
}

# Instance Profile for Karpenter nodes
resource "aws_iam_instance_profile" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name = "${local.name}-karpenter-node-instance-profile"
  role = aws_iam_role.karpenter_node_instance_role[0].name

  tags = var.tags
}

# SQS Queue for Karpenter interruption handling
resource "aws_sqs_queue" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name                       = "${local.name}-karpenter"
  message_retention_seconds  = 300
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

# SQS Queue Policy
resource "aws_sqs_queue_policy" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  queue_url = aws_sqs_queue.karpenter[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "EC2InterruptionPolicy"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter[0].arn
      }
    ]
  })
}

# EventBridge Rules for Spot Instance Interruption
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${local.name}-karpenter-spot-interruption"
  description = "Karpenter Spot Instance Interruption Warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  count = var.enable_karpenter ? 1 : 0

  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption[0].name
  target_id = "KarpenterSpotInterruptionQueueTarget"
  arn       = aws_sqs_queue.karpenter[0].arn
}

# EventBridge Rule for Instance State Changes
resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change" {
  count = var.enable_karpenter ? 1 : 0

  name        = "${local.name}-karpenter-instance-state-change"
  description = "Karpenter Instance State Change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change" {
  count = var.enable_karpenter ? 1 : 0

  rule      = aws_cloudwatch_event_rule.karpenter_instance_state_change[0].name
  target_id = "KarpenterInstanceStateChangeQueueTarget"
  arn       = aws_sqs_queue.karpenter[0].arn
}

# Karpenter Namespace
resource "kubernetes_namespace" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  metadata {
    name = "karpenter"
    labels = {
      "app.kubernetes.io/name" = "karpenter"
    }
  }
}

# Karpenter Helm Chart
resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace.karpenter[0].metadata[0].name

  values = [
    yamlencode({
      settings = {
        aws = {
          clusterName                = var.cluster_name
          clusterEndpoint           = var.cluster_endpoint
          defaultInstanceProfile   = aws_iam_instance_profile.karpenter[0].name
          interruptionQueueName    = aws_sqs_queue.karpenter[0].name
        }
      }

      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller[0].arn
        }
      }

      # Resource limits for cost optimization
      resources = {
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }

      # Pod disruption budget
      podDisruptionBudget = {
        name        = "karpenter"
        maxUnavailable = 1
      }

      # Node affinity to ensure Karpenter runs on stable nodes
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "karpenter.sh/provisioner-name"
                    operator = "DoesNotExist"
                  }
                ]
              }
            ]
          }
        }
      }

      # Tolerations for critical system workloads
      tolerations = [
        {
          key    = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]
    })
  ]

  depends_on = [
    kubernetes_namespace.karpenter,
    aws_iam_role.karpenter_controller,
    aws_iam_instance_profile.karpenter
  ]
}

# Karpenter Provisioner for general workloads
resource "kubernetes_manifest" "karpenter_provisioner_general" {
  count = var.enable_karpenter ? 1 : 0

  manifest = {
    apiVersion = "karpenter.sh/v1alpha5"
    kind       = "Provisioner"
    metadata = {
      name = "general-purpose"
    }
    spec = {
      # Scaling limits
      limits = {
        resources = {
          cpu    = var.max_cpu_limit
          memory = var.max_memory_limit
        }
      }

      # Instance requirements for cost optimization
      requirements = [
        {
          key      = "kubernetes.io/arch"
          operator = "In"
          values   = var.supported_architectures
        },
        {
          key      = "node.kubernetes.io/instance-type"
          operator = "In"
          values   = var.instance_types
        },
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = var.capacity_types
        }
      ]

      # Spot instance configuration
      providerRef = {
        name = kubernetes_manifest.karpenter_node_pool_general[0].manifest.metadata.name
      }

      # Taints for spot instances
      taints = var.enable_spot_taints ? [
        {
          key    = "spot-instance"
          value  = "true"
          effect = "NoSchedule"
        }
      ] : []

      # TTL settings for cost optimization
      ttlSecondsAfterEmpty = var.ttl_seconds_after_empty
      ttlSecondsUntilExpired = var.ttl_seconds_until_expired
    }
  }

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool (v1beta1 API)
resource "kubernetes_manifest" "karpenter_node_pool_general" {
  count = var.enable_karpenter ? 1 : 0

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "general-purpose"
    }
    spec = {
      amiFamily = "AL2"
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      instanceStorePolicy = "RAID0"
      userData = base64encode(templatefile("${path.module}/templates/userdata.sh", {
        cluster_name = var.cluster_name
      }))

      # Block device mappings
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = var.node_volume_size
            volumeType = "gp3"
            encrypted  = true
            deleteOnTermination = true
          }
        }
      ]

      # Instance metadata options
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens             = "required"
      }

      tags = merge(var.tags, {
        "karpenter.sh/discovery" = var.cluster_name
      })
    }
  }

  depends_on = [helm_release.karpenter]
}

# Karpenter Provisioner for burstable workloads
resource "kubernetes_manifest" "karpenter_provisioner_burstable" {
  count = var.enable_karpenter && var.enable_burstable_provisioner ? 1 : 0

  manifest = {
    apiVersion = "karpenter.sh/v1alpha5"
    kind       = "Provisioner"
    metadata = {
      name = "burstable"
    }
    spec = {
      limits = {
        resources = {
          cpu = "1000"
        }
      }

      requirements = [
        {
          key      = "node.kubernetes.io/instance-type"
          operator = "In"
          values   = ["t3.micro", "t3.small", "t3.medium", "t3a.micro", "t3a.small", "t3a.medium"]
        },
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = ["spot", "on-demand"]
        }
      ]

      providerRef = {
        name = kubernetes_manifest.karpenter_node_pool_burstable[0].manifest.metadata.name
      }

      taints = [
        {
          key    = "burstable"
          value  = "true"
          effect = "NoSchedule"
        }
      ]

      ttlSecondsAfterEmpty = 30
    }
  }

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_node_pool_burstable" {
  count = var.enable_karpenter && var.enable_burstable_provisioner ? 1 : 0

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "burstable"
    }
    spec = {
      amiFamily = "AL2"
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = 20
            volumeType = "gp3"
            encrypted  = true
            deleteOnTermination = true
          }
        }
      ]

      tags = merge(var.tags, {
        "karpenter.sh/discovery" = var.cluster_name
        "NodeType" = "burstable"
      })
    }
  }

  depends_on = [helm_release.karpenter]
}