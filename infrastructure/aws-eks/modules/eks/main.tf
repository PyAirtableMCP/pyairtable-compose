# EKS Cluster Module for PyAirtable Platform
# Comprehensive EKS setup with multi-AZ, auto-scaling, and cost optimization

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

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = var.cluster_service_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    
    public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  }

  # Enable EKS Cluster logging
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Encryption configuration
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # Ensure proper ordering of resource creation
  depends_on = [
    aws_cloudwatch_log_group.eks,
  ]

  tags = var.tags
}

# KMS Key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name}-eks-encryption-key"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.name}-eks-encryption-key"
  target_key_id = aws_kms_key.eks.key_id
}

# CloudWatch Log Group for EKS
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.eks.arn

  tags = merge(var.tags, {
    Name = "${local.name}-eks-cluster-logs"
  })
}

# EKS Node Groups
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = var.node_instance_role_arn
  subnet_ids      = var.subnet_ids

  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type
  disk_size      = each.value.disk_size

  # Scaling configuration
  scaling_config {
    desired_size = each.value.scaling_config.desired_size
    max_size     = each.value.scaling_config.max_size
    min_size     = each.value.scaling_config.min_size
  }

  # Update configuration
  update_config {
    max_unavailable_percentage = each.value.update_config.max_unavailable_percentage
  }

  # Remote access configuration
  remote_access {
    ec2_ssh_key               = var.node_groups_defaults.ec2_ssh_key
    source_security_group_ids = var.node_security_group_ids
  }

  # Labels
  labels = merge(
    {
      "node-group"                                    = each.key
      "kubernetes.io/cluster/${var.cluster_name}"    = "owned"
    },
    each.value.labels
  )

  # Taints
  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  # Launch template for advanced configuration
  launch_template {
    id      = aws_launch_template.node_group[each.key].id
    version = aws_launch_template.node_group[each.key].latest_version
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  depends_on = [
    aws_eks_cluster.main,
  ]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${each.key}-node-group"
  })

  # Allow external changes without Terraform plan difference
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# Launch templates for node groups
resource "aws_launch_template" "node_group" {
  for_each = var.node_groups

  name_prefix   = "${var.cluster_name}-${each.key}-"
  image_id      = data.aws_ssm_parameter.eks_ami_release_version[each.key].value
  instance_type = each.value.instance_types[0] # Use first instance type as default

  vpc_security_group_ids = [var.node_security_group_id]

  # User data for EKS optimized AMI
  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh", {
    cluster_name        = var.cluster_name
    cluster_endpoint    = aws_eks_cluster.main.endpoint
    cluster_ca          = aws_eks_cluster.main.certificate_authority[0].data
    bootstrap_arguments = var.bootstrap_arguments
    kubelet_extra_args  = var.kubelet_extra_args
  }))

  # Instance metadata options
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 2
  }

  # Block device mappings for encryption
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs.arn
      delete_on_termination = true
    }
  }

  # Monitoring
  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${each.key}-node"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# KMS Key for EBS encryption
resource "aws_kms_key" "ebs" {
  description             = "EBS Encryption Key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${local.name}-ebs-encryption-key"
  })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${local.name}-ebs-encryption-key"
  target_key_id = aws_kms_key.ebs.key_id
}

# Data source to get the latest EKS optimized AMI
data "aws_ssm_parameter" "eks_ami_release_version" {
  for_each = var.node_groups

  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2${each.value.ami_type == "AL2_ARM_64" ? "-arm64" : ""}/recommended/image_id"
}

# EKS Add-ons
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = var.addon_versions.vpc_cni
  resolve_conflicts        = "OVERWRITE"
  service_account_role_arn = var.vpc_cni_irsa_role_arn

  tags = var.tags

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "coredns"
  addon_version     = var.addon_versions.coredns
  resolve_conflicts = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.main.name
  addon_name        = "kube-proxy"
  addon_version     = var.addon_versions.kube_proxy
  resolve_conflicts = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.main]
}

# EBS CSI Driver Add-on
resource "aws_eks_addon" "ebs_csi_driver" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.addon_versions.ebs_csi_driver
  resolve_conflicts        = "OVERWRITE"
  service_account_role_arn = var.ebs_csi_irsa_role_arn

  tags = var.tags

  depends_on = [aws_eks_node_group.main]
}

# EFS CSI Driver Add-on
resource "aws_eks_addon" "efs_csi_driver" {
  count = var.enable_efs_csi_driver ? 1 : 0

  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = var.addon_versions.efs_csi_driver
  resolve_conflicts        = "OVERWRITE"
  service_account_role_arn = var.efs_csi_irsa_role_arn

  tags = var.tags

  depends_on = [aws_eks_node_group.main]
}

# Pod Disruption Budget for cluster autoscaler
resource "kubernetes_pod_disruption_budget" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
  }

  spec {
    min_available = 1

    selector {
      match_labels = {
        app = "cluster-autoscaler"
      }
    }
  }

  depends_on = [aws_eks_cluster.main]
}

# OIDC Identity Provider for IRSA
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${local.name}-eks-oidc"
  })
}