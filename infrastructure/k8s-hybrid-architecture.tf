# Kubernetes Hybrid Architecture for PyAirtable
# Optimized for 22 services: Go (high-performance) + Python (AI/ML heavy)
# Target: $300-600/month with spot instances and autoscaling

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# EKS Cluster with Hybrid Node Groups
resource "aws_eks_cluster" "pyairtable" {
  name     = "${var.project_name}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-eks"
    Environment = var.environment
    Workload    = "hybrid-microservices"
  }
}

# Go Services Node Group - High Performance, Low Memory
resource "aws_eks_node_group" "go_services" {
  cluster_name    = aws_eks_cluster.pyairtable.name
  node_group_name = "go-services"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  # Instance types optimized for Go services
  instance_types = ["t3.medium", "t3.large"]
  capacity_type  = "SPOT"  # 70% cost savings
  
  scaling_config {
    desired_size = 2
    max_size     = 6
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Taints to ensure only Go services run here
  taint {
    key    = "workload"
    value  = "go-services"
    effect = "NO_SCHEDULE"
  }

  labels = {
    workload = "go-services"
    type     = "compute-optimized"
  }

  tags = {
    Name        = "${var.project_name}-go-services"
    Environment = var.environment
    Workload    = "go-services"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# Python AI/ML Services Node Group - High Memory, GPU Optional
resource "aws_eks_node_group" "python_ai_services" {
  cluster_name    = aws_eks_cluster.pyairtable.name
  node_group_name = "python-ai-services"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  # Memory-optimized instances for AI/ML workloads
  instance_types = ["r5.large", "r5.xlarge"]
  capacity_type  = "SPOT"  # 70% cost savings
  
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Taints for Python AI services
  taint {
    key    = "workload"
    value  = "python-ai"
    effect = "NO_SCHEDULE"
  }

  labels = {
    workload = "python-ai"
    type     = "memory-optimized"
  }

  tags = {
    Name        = "${var.project_name}-python-ai"
    Environment = var.environment
    Workload    = "python-ai"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# General Services Node Group - Balanced for databases and general workloads
resource "aws_eks_node_group" "general_services" {
  cluster_name    = aws_eks_cluster.pyairtable.name
  node_group_name = "general-services"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  # Balanced instances for databases and frontend
  instance_types = ["t3.medium", "t3.large"]
  capacity_type  = "ON_DEMAND"  # More stable for stateful services
  
  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "general"
    type     = "balanced"
  }

  tags = {
    Name        = "${var.project_name}-general"
    Environment = var.environment
    Workload    = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# Cluster Autoscaler
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.pyairtable.name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  depends_on = [aws_eks_cluster.pyairtable]
}

# Metrics Server for HPA
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  depends_on = [aws_eks_cluster.pyairtable]
}

# NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  version    = "4.8.0"

  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  depends_on = [aws_eks_cluster.pyairtable]
}

# EBS CSI Driver for persistent storage
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.pyairtable.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.24.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn
  
  tags = {
    Name = "${var.project_name}-ebs-csi"
  }
}

# Storage Classes for different performance tiers
resource "kubernetes_storage_class" "gp3_fast" {
  metadata {
    name = "gp3-fast"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  
  parameters = {
    type       = "gp3"
    iops       = "3000"
    throughput = "125"
    encrypted  = "true"
  }
}

resource "kubernetes_storage_class" "gp3_standard" {
  metadata {
    name = "gp3-standard"
  }
  
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# KMS Key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-eks-secrets"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

# CloudWatch Log Group for EKS
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.project_name}-${var.environment}/cluster"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-eks-logs"
  }
}

# Output cluster endpoint for kubectl configuration
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.pyairtable.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = aws_eks_cluster.pyairtable.vpc_config[0].cluster_security_group_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.pyairtable.name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.pyairtable.certificate_authority[0].data
}