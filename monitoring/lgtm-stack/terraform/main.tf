# LGTM Stack Terraform Configuration
# Deploys optimized Loki, Grafana, Tempo, Mimir stack for PyAirtable

terraform {
  required_version = ">= 1.0"
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

# Provider configuration
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "PyAirtable-LGTM"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = "Observability"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Local values for resource naming and configuration
locals {
  name_prefix = "pyairtable-lgtm-${var.environment}"
  
  common_tags = {
    Project     = "PyAirtable-LGTM"
    Environment = var.environment
    Stack       = "Observability"
  }
  
  # Storage configuration based on environment
  storage_config = {
    dev = {
      loki_retention_days    = 7
      tempo_retention_days   = 3
      mimir_retention_days   = 30
      storage_size           = "100Gi"
    }
    staging = {
      loki_retention_days    = 14
      tempo_retention_days   = 7
      mimir_retention_days   = 60
      storage_size           = "300Gi"
    }
    prod = {
      loki_retention_days    = 14
      tempo_retention_days   = 7
      mimir_retention_days   = 90
      storage_size           = "1Ti"
    }
  }
  
  # Resource limits based on environment
  resource_limits = {
    dev = {
      loki_memory    = "512Mi"
      loki_cpu       = "250m"
      tempo_memory   = "1Gi"
      tempo_cpu      = "500m"
      mimir_memory   = "2Gi"
      mimir_cpu      = "1000m"
      grafana_memory = "1Gi"
      grafana_cpu    = "500m"
    }
    staging = {
      loki_memory    = "1Gi"
      loki_cpu       = "500m"
      tempo_memory   = "2Gi"
      tempo_cpu      = "1000m"
      mimir_memory   = "4Gi"
      mimir_cpu      = "2000m"
      grafana_memory = "2Gi"
      grafana_cpu    = "1000m"
    }
    prod = {
      loki_memory    = "1Gi"
      loki_cpu       = "500m"
      tempo_memory   = "2Gi"
      tempo_cpu      = "1000m"
      mimir_memory   = "4Gi"
      mimir_cpu      = "2000m"
      grafana_memory = "2Gi"
      grafana_cpu    = "1000m"
    }
  }
}

# VPC for LGTM stack (if creating new infrastructure)
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  count = var.create_vpc ? 1 : 0
  
  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr
  
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true
  
  tags = local.common_tags
}

# EKS Cluster for LGTM stack
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  
  cluster_name    = "${local.name_prefix}-cluster"
  cluster_version = var.kubernetes_version
  
  # Use existing VPC or created VPC
  vpc_id     = var.create_vpc ? module.vpc[0].vpc_id : var.existing_vpc_id
  subnet_ids = var.create_vpc ? module.vpc[0].private_subnets : var.existing_subnet_ids
  
  # Cluster endpoint configuration
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = var.environment == "prod" ? false : true
  cluster_endpoint_public_access_cidrs = var.environment == "prod" ? [] : ["0.0.0.0/0"]
  
  # OIDC Identity provider
  enable_irsa = true
  
  # EKS Managed Node Groups
  eks_managed_node_groups = {
    # General purpose node group for LGTM components
    lgtm_nodes = {
      name = "lgtm-nodes"
      
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size
      
      # EBS optimized instances for better storage performance
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            iops                 = 3000
            throughput           = 150
            encrypted            = true
            delete_on_termination = true
          }
        }
      }
      
      # Node group specific tags
      labels = {
        role = "lgtm-observability"
      }
      
      taints = {
        observability = {
          key    = "observability"
          value  = "lgtm"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
  
  # AWS Load Balancer Controller
  enable_aws_load_balancer_controller = true
  
  # EBS CSI Driver for persistent storage
  enable_ebs_csi_driver = true
  
  tags = local.common_tags
}

# S3 bucket for shared object storage (alternative to MinIO for production)
resource "aws_s3_bucket" "lgtm_storage" {
  count = var.use_s3_storage ? 1 : 0
  
  bucket = "${local.name_prefix}-storage"
  
  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "lgtm_storage" {
  count = var.use_s3_storage ? 1 : 0
  
  bucket = aws_s3_bucket.lgtm_storage[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "lgtm_storage" {
  count = var.use_s3_storage ? 1 : 0
  
  bucket = aws_s3_bucket.lgtm_storage[0].id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
      bucket_key_enabled = true
    }
  }
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "lgtm_storage" {
  count = var.use_s3_storage ? 1 : 0
  
  bucket = aws_s3_bucket.lgtm_storage[0].id
  
  rule {
    id     = "loki_lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "loki/"
    }
    
    expiration {
      days = local.storage_config[var.environment].loki_retention_days
    }
    
    transition {
      days          = 3
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 7
      storage_class = "GLACIER"
    }
  }
  
  rule {
    id     = "tempo_lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "tempo/"
    }
    
    expiration {
      days = local.storage_config[var.environment].tempo_retention_days
    }
  }
  
  rule {
    id     = "mimir_lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "mimir/"
    }
    
    expiration {
      days = local.storage_config[var.environment].mimir_retention_days
    }
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }
}

# IAM role for LGTM components to access S3
resource "aws_iam_role" "lgtm_storage_role" {
  count = var.use_s3_storage ? 1 : 0
  
  name = "${local.name_prefix}-storage-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:monitoring:lgtm-storage"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "lgtm_storage_policy" {
  count = var.use_s3_storage ? 1 : 0
  
  name = "${local.name_prefix}-storage-policy"
  role = aws_iam_role.lgtm_storage_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.lgtm_storage[0].arn,
          "${aws_s3_bucket.lgtm_storage[0].arn}/*"
        ]
      }
    ]
  })
}

# Kubernetes namespace for LGTM stack
resource "kubernetes_namespace" "monitoring" {
  depends_on = [module.eks]
  
  metadata {
    name = "monitoring"
    
    labels = {
      name = "monitoring"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# Service account for LGTM components
resource "kubernetes_service_account" "lgtm_storage" {
  depends_on = [kubernetes_namespace.monitoring]
  
  metadata {
    name      = "lgtm-storage"
    namespace = "monitoring"
    
    annotations = var.use_s3_storage ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lgtm_storage_role[0].arn
    } : {}
  }
}

# Storage class for LGTM components
resource "kubernetes_storage_class" "lgtm_fast_ssd" {
  depends_on = [module.eks]
  
  metadata {
    name = "lgtm-fast-ssd"
  }
  
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy        = "Retain"
  volume_binding_mode   = "WaitForFirstConsumer"
  allow_volume_expansion = true
  
  parameters = {
    type      = "gp3"
    iops      = "3000"
    throughput = "150"
    encrypted = "true"
  }
}

# Persistent Volume Claims for local storage
resource "kubernetes_persistent_volume_claim" "minio_data" {
  count = var.use_s3_storage ? 0 : 1
  
  depends_on = [kubernetes_storage_class.lgtm_fast_ssd]
  
  metadata {
    name      = "minio-data"
    namespace = "monitoring"
  }
  
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "lgtm-fast-ssd"
    
    resources {
      requests = {
        storage = local.storage_config[var.environment].storage_size
      }
    }
  }
}

# Helm release for MinIO (if not using S3)
resource "helm_release" "minio" {
  count = var.use_s3_storage ? 0 : 1
  
  depends_on = [kubernetes_namespace.monitoring, kubernetes_persistent_volume_claim.minio_data]
  
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.0.14"
  namespace  = "monitoring"
  
  values = [
    yamlencode({
      auth = {
        rootUser     = var.minio_root_user
        rootPassword = var.minio_root_password
      }
      
      defaultBuckets = "loki-data,tempo-data,mimir-data"
      
      persistence = {
        enabled      = true
        existingClaim = "minio-data"
      }
      
      resources = {
        requests = {
          memory = var.environment == "prod" ? "4Gi" : "2Gi"
          cpu    = var.environment == "prod" ? "2000m" : "1000m"
        }
        limits = {
          memory = var.environment == "prod" ? "8Gi" : "4Gi"
          cpu    = var.environment == "prod" ? "4000m" : "2000m"
        }
      }
      
      service = {
        type = "ClusterIP"
        port = 9000
      }
      
      consoleService = {
        type = "ClusterIP"
        port = 9001
      }
      
      nodeSelector = {
        role = "lgtm-observability"
      }
      
      tolerations = [
        {
          key      = "observability"
          operator = "Equal"
          value    = "lgtm"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}

# ConfigMap for Loki configuration
resource "kubernetes_config_map" "loki_config" {
  depends_on = [kubernetes_namespace.monitoring]
  
  metadata {
    name      = "loki-config"
    namespace = "monitoring"
  }
  
  data = {
    "loki.yml" = file("${path.module}/../loki/loki-optimized.yml")
  }
}

# ConfigMap for Tempo configuration
resource "kubernetes_config_map" "tempo_config" {
  depends_on = [kubernetes_namespace.monitoring]
  
  metadata {
    name      = "tempo-config"
    namespace = "monitoring"
  }
  
  data = {
    "tempo.yml" = file("${path.module}/../tempo/tempo-optimized.yml")
  }
}

# ConfigMap for Mimir configuration
resource "kubernetes_config_map" "mimir_config" {
  depends_on = [kubernetes_namespace.monitoring]
  
  metadata {
    name      = "mimir-config"
    namespace = "monitoring"
  }
  
  data = {
    "mimir.yml" = file("${path.module}/../mimir/mimir-optimized.yml")
  }
}

# Helm release for Grafana with LGTM configuration
resource "helm_release" "grafana" {
  depends_on = [kubernetes_namespace.monitoring]
  
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "7.0.3"
  namespace  = "monitoring"
  
  values = [
    yamlencode({
      adminPassword = var.grafana_admin_password
      
      persistence = {
        enabled      = true
        storageClassName = "lgtm-fast-ssd"
        size         = "10Gi"
      }
      
      resources = {
        requests = {
          memory = local.resource_limits[var.environment].grafana_memory
          cpu    = local.resource_limits[var.environment].grafana_cpu
        }
        limits = {
          memory = local.resource_limits[var.environment].grafana_memory
          cpu    = local.resource_limits[var.environment].grafana_cpu
        }
      }
      
      grafana.ini = {
        "feature_toggles" = {
          enable = "traceqlEditor"
        }
        "install_plugins" = [
          "grafana-piechart-panel",
          "grafana-worldmap-panel",
          "grafana-clock-panel"
        ]
      }
      
      sidecar = {
        datasources = {
          enabled = true
          label   = "grafana_datasource"
        }
        dashboards = {
          enabled = true
          label   = "grafana_dashboard"
        }
      }
      
      service = {
        type = var.environment == "prod" ? "ClusterIP" : "LoadBalancer"
        port = 3000
      }
      
      nodeSelector = {
        role = "lgtm-observability"
      }
      
      tolerations = [
        {
          key      = "observability"
          operator = "Equal"
          value    = "lgtm"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}

# Network policies for security
resource "kubernetes_network_policy" "lgtm_network_policy" {
  depends_on = [kubernetes_namespace.monitoring]
  
  metadata {
    name      = "lgtm-network-policy"
    namespace = "monitoring"
  }
  
  spec {
    pod_selector {
      match_labels = {
        app = "lgtm"
      }
    }
    
    policy_types = ["Ingress", "Egress"]
    
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "pyairtable"
          }
        }
      }
      
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }
    }
    
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }
      
      # Allow egress to AWS services (for S3 access)
      to {}
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
  }
}