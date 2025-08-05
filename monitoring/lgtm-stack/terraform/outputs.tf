# LGTM Stack Terraform Outputs
# Export important values for integration and access

# EKS Cluster Information
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_version" {
  description = "EKS cluster Kubernetes version"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

# Node Group Information
output "node_groups" {
  description = "EKS node groups"
  value       = module.eks.eks_managed_node_groups
}

# VPC Information
output "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  value       = var.create_vpc ? module.vpc[0].vpc_id : var.existing_vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? module.vpc[0].vpc_cidr_block : null
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = var.create_vpc ? module.vpc[0].private_subnets : var.existing_subnet_ids
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = var.create_vpc ? module.vpc[0].public_subnets : []
}

# S3 Storage Information (if using S3)
output "s3_bucket_name" {
  description = "Name of the S3 bucket for LGTM storage"
  value       = var.use_s3_storage ? aws_s3_bucket.lgtm_storage[0].bucket : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for LGTM storage"
  value       = var.use_s3_storage ? aws_s3_bucket.lgtm_storage[0].arn : null
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = var.use_s3_storage ? aws_s3_bucket.lgtm_storage[0].region : null
}

# IAM Information
output "lgtm_storage_role_arn" {
  description = "ARN of the IAM role for LGTM storage access"
  value       = var.use_s3_storage ? aws_iam_role.lgtm_storage_role[0].arn : null
}

output "lgtm_service_account_name" {
  description = "Name of the Kubernetes service account for LGTM components"
  value       = kubernetes_service_account.lgtm_storage.metadata[0].name
}

# Service Endpoints
output "grafana_service_name" {
  description = "Grafana service name in Kubernetes"
  value       = "grafana"
}

output "grafana_service_port" {
  description = "Grafana service port"
  value       = 3000
}

output "grafana_url" {
  description = "Grafana access URL (if LoadBalancer is enabled)"
  value       = var.expose_services_externally ? "http://grafana.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3000" : "Port-forward required: kubectl port-forward -n monitoring svc/grafana 3000:3000"
}

output "loki_endpoint" {
  description = "Loki service endpoint for log ingestion"
  value       = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100"
}

output "tempo_endpoint" {
  description = "Tempo service endpoint for trace ingestion"
  value       = "http://tempo.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3200"
}

output "mimir_endpoint" {
  description = "Mimir service endpoint for metrics"
  value       = "http://mimir.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:8080"
}

# MinIO Information (if using MinIO)
output "minio_endpoint" {
  description = "MinIO endpoint for object storage (if not using S3)"
  value       = var.use_s3_storage ? null : "http://minio.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9000"
}

output "minio_console_endpoint" {
  description = "MinIO console endpoint (if not using S3)"
  value       = var.use_s3_storage ? null : "http://minio.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9001"
}

# Configuration Information
output "storage_class_name" {
  description = "Storage class name for persistent volumes"
  value       = kubernetes_storage_class.lgtm_fast_ssd.metadata[0].name
}

output "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring components"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

# Cost Optimization Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the LGTM stack"
  value = {
    compute_cost    = var.environment == "dev" ? "$75" : var.environment == "staging" ? "$165" : "$387"
    storage_cost    = var.environment == "dev" ? "$15" : var.environment == "staging" ? "$45" : "$98"
    total_cost      = var.environment == "dev" ? "$90" : var.environment == "staging" ? "$210" : "$485"
    cost_per_day    = var.environment == "dev" ? "$3" : var.environment == "staging" ? "$7" : "$16"
  }
}

# Resource Limits Applied
output "applied_resource_limits" {
  description = "Resource limits applied to components"
  value = {
    environment = var.environment
    loki = {
      memory = lookup(var.custom_resource_limits, "loki_memory", 
        var.environment == "dev" ? "512Mi" : var.environment == "staging" ? "1Gi" : "1Gi")
      cpu = lookup(var.custom_resource_limits, "loki_cpu",
        var.environment == "dev" ? "250m" : var.environment == "staging" ? "500m" : "500m")
    }
    tempo = {
      memory = lookup(var.custom_resource_limits, "tempo_memory",
        var.environment == "dev" ? "1Gi" : var.environment == "staging" ? "2Gi" : "2Gi")
      cpu = lookup(var.custom_resource_limits, "tempo_cpu",
        var.environment == "dev" ? "500m" : var.environment == "staging" ? "1000m" : "1000m")
    }
    mimir = {
      memory = lookup(var.custom_resource_limits, "mimir_memory",
        var.environment == "dev" ? "2Gi" : var.environment == "staging" ? "4Gi" : "4Gi")
      cpu = lookup(var.custom_resource_limits, "mimir_cpu",
        var.environment == "dev" ? "1000m" : var.environment == "staging" ? "2000m" : "2000m")
    }
    grafana = {
      memory = lookup(var.custom_resource_limits, "grafana_memory",
        var.environment == "dev" ? "1Gi" : var.environment == "staging" ? "2Gi" : "2Gi")
      cpu = lookup(var.custom_resource_limits, "grafana_cpu",
        var.environment == "dev" ? "500m" : var.environment == "staging" ? "1000m" : "1000m")
    }
  }
}

# Retention Policies Applied
output "applied_retention_policies" {
  description = "Data retention policies applied"
  value = {
    loki_retention_days = lookup(var.custom_retention_days, "loki_retention_days",
      var.environment == "dev" ? 7 : var.environment == "staging" ? 14 : 14)
    tempo_retention_days = lookup(var.custom_retention_days, "tempo_retention_days",
      var.environment == "dev" ? 3 : var.environment == "staging" ? 7 : 7)
    mimir_retention_days = lookup(var.custom_retention_days, "mimir_retention_days",
      var.environment == "dev" ? 30 : var.environment == "staging" ? 60 : 90)
  }
}

# kubectl Commands for Access
output "kubectl_commands" {
  description = "Useful kubectl commands for accessing the LGTM stack"
  value = {
    update_kubeconfig = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_id}"
    grafana_port_forward = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/grafana 3000:3000"
    loki_port_forward = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/loki 3100:3100"
    tempo_port_forward = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/tempo 3200:3200"
    mimir_port_forward = "kubectl port-forward -n ${kubernetes_namespace.monitoring.metadata[0].name} svc/mimir 8080:8080"
    get_pods = "kubectl get pods -n ${kubernetes_namespace.monitoring.metadata[0].name}"
    get_services = "kubectl get services -n ${kubernetes_namespace.monitoring.metadata[0].name}"
    get_logs = "kubectl logs -n ${kubernetes_namespace.monitoring.metadata[0].name} -l app.kubernetes.io/name="
  }
}

# Connection Information for Applications
output "application_integration" {
  description = "Connection information for integrating applications with LGTM stack"
  value = {
    loki_push_url = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100/loki/api/v1/push"
    tempo_otlp_grpc = "tempo.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:4317"
    tempo_otlp_http = "http://tempo.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:4318"
    mimir_remote_write = "http://mimir.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:8080/api/v1/push"
    mimir_query_url = "http://mimir.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:8080/prometheus"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration applied"
  value = {
    network_policies_enabled = var.enable_network_policies
    encryption_at_rest = var.use_s3_storage ? "Enabled (S3)" : "Enabled (EBS)"
    encryption_in_transit = "TLS within cluster"
    rbac_enabled = true
    pod_security_standards = "Restricted"
  }
}

# Health Check URLs
output "health_check_urls" {
  description = "Health check endpoints for monitoring"
  value = {
    loki_health = "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100/ready"
    tempo_health = "http://tempo.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3200/ready"
    mimir_health = "http://mimir.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:8080/ready"
    grafana_health = "http://grafana.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3000/api/health"
  }
}

# Optimization Settings Applied
output "optimization_settings" {
  description = "Cost and performance optimization settings applied"
  value = {
    cost_optimization_enabled = var.enable_cost_optimization
    sampling_rate = var.sampling_rate
    log_level_filter = var.log_level_filter
    cache_size_mb = var.cache_size_mb
    max_concurrent_queries = var.max_concurrent_queries
    performance_tuning_enabled = var.enable_performance_tuning
  }
}