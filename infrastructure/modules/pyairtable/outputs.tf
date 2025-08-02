# Outputs for PyAirtable Infrastructure Module

# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_certificate_authority_data" {
  description = "Certificate authority data for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# Networking
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways"
  value       = module.vpc.nat_gateway_ids
}

# Database
output "database_endpoint" {
  description = "Endpoint of the RDS database"
  value       = module.database.endpoint
}

output "database_port" {
  description = "Port of the RDS database"
  value       = module.database.port
}

output "database_name" {
  description = "Name of the database"
  value       = module.database.db_name
}

output "database_username" {
  description = "Username for the database"
  value       = module.database.username
  sensitive   = true
}

output "database_secret_arn" {
  description = "ARN of the database secret in Secrets Manager"
  value       = module.secrets.secret_arns["database"]
  sensitive   = true
}

# Cache
output "redis_primary_endpoint" {
  description = "Primary endpoint of the Redis cluster"
  value       = module.redis.primary_endpoint
}

output "redis_reader_endpoint" {
  description = "Reader endpoint of the Redis cluster"
  value       = module.redis.reader_endpoint
}

output "redis_port" {
  description = "Port of the Redis cluster"
  value       = module.redis.port
}

output "redis_secret_arn" {
  description = "ARN of the Redis secret in Secrets Manager"
  value       = module.secrets.secret_arns["redis"]
  sensitive   = true
}

# Load Balancer
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = module.alb.zone_id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.arn
}

# S3 Buckets
output "s3_bucket_names" {
  description = "Names of the S3 buckets"
  value       = module.s3_buckets.bucket_names
}

output "s3_bucket_arns" {
  description = "ARNs of the S3 buckets"
  value       = module.s3_buckets.bucket_arns
}

# Secrets
output "secret_arns" {
  description = "ARNs of all secrets in Secrets Manager"
  value       = module.secrets.secret_arns
  sensitive   = true
}

# IAM Roles
output "irsa_role_arns" {
  description = "ARNs of IAM roles for service accounts"
  value       = module.irsa_roles.role_arns
}

output "irsa_role_names" {
  description = "Names of IAM roles for service accounts"
  value       = module.irsa_roles.role_names
}

# Monitoring
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "cloudwatch_log_groups" {
  description = "Names of CloudWatch log groups"
  value       = [for lg in aws_cloudwatch_log_group.application_logs : lg.name]
}

# Cost Management
output "budget_name" {
  description = "Name of the cost budget"
  value       = aws_budgets_budget.monthly_budget.name
}

output "budget_limit" {
  description = "Monthly budget limit"
  value       = aws_budgets_budget.monthly_budget.limit_amount
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

# Service Configuration Summary
output "service_configurations" {
  description = "Service resource configurations"
  value       = local.service_configs
}

output "environment_config" {
  description = "Environment-specific configuration"
  value = {
    instance_types         = local.config.instance_types
    min_size              = local.config.min_size
    max_size              = local.config.max_size
    desired_capacity      = local.config.desired_capacity
    spot_percentage       = local.config.spot_percentage
    backup_retention_days = local.config.backup_retention_days
    log_retention_days    = local.config.log_retention_days
    db_instance_class     = local.config.db_instance_class
    redis_node_type       = local.config.redis_node_type
  }
}

# Connectivity Information for Applications
output "connectivity_info" {
  description = "Information needed for application connectivity"
  value = {
    database = {
      host     = module.database.endpoint
      port     = module.database.port
      database = module.database.db_name
      secret_arn = module.secrets.secret_arns["database"]
    }
    
    redis = {
      host       = module.redis.primary_endpoint
      port       = module.redis.port
      secret_arn = module.secrets.secret_arns["redis"]
    }
    
    s3_buckets = {
      uploads = module.s3_buckets.bucket_names["uploads"]
      backups = module.s3_buckets.bucket_names["backups"]
      assets  = module.s3_buckets.bucket_names["assets"]
    }
    
    load_balancer = {
      dns_name = module.alb.dns_name
      zone_id  = module.alb.zone_id
    }
  }
  sensitive = true
}

# Kubernetes Configuration
output "kubeconfig" {
  description = "kubectl configuration"
  value = {
    cluster_name = module.eks.cluster_name
    endpoint     = module.eks.cluster_endpoint
    region       = var.aws_region
  }
}

# Security Information
output "security_info" {
  description = "Security-related information"
  value = {
    cluster_security_group_id = module.eks.cluster_security_group_id
    vpc_id                   = module.vpc.vpc_id
    private_subnet_ids       = module.vpc.private_subnet_ids
    secrets_manager_arns     = module.secrets.secret_arns
  }
  sensitive = true
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Cost optimization features and settings"
  value = {
    spot_instances_enabled = local.config.spot_percentage > 0
    spot_percentage       = local.config.spot_percentage
    backup_retention_days = local.config.backup_retention_days
    log_retention_days    = local.config.log_retention_days
    auto_shutdown_enabled = var.environment == "development"
    
    estimated_monthly_costs = {
      compute    = var.environment == "production" ? 2000 : (var.environment == "staging" ? 500 : 200)
      database   = var.environment == "production" ? 800 : (var.environment == "staging" ? 200 : 50)
      storage    = var.environment == "production" ? 300 : (var.environment == "staging" ? 100 : 25)
      networking = var.environment == "production" ? 200 : (var.environment == "staging" ? 50 : 25)
      monitoring = var.environment == "production" ? 500 : (var.environment == "staging" ? 150 : 75)
      total      = var.environment == "production" ? 3800 : (var.environment == "staging" ? 1000 : 375)
    }
    
    cost_savings = {
      spot_instances = "${local.config.spot_percentage}% cost reduction on compute"
      auto_scaling   = "15-25% through right-sizing"
      lifecycle_policies = "20-30% on storage costs"
    }
  }
}

# Deployment Information
output "deployment_info" {
  description = "Information for deployment automation"
  value = {
    cluster_name    = module.eks.cluster_name
    namespace       = "pyairtable"
    service_account = "pyairtable-service-account"
    
    helm_values = {
      image = {
        repository = "ghcr.io/pyairtable"
        tag        = "latest"
      }
      
      database = {
        secretName = "database-secret"
        secretKey  = "connection-string"
      }
      
      redis = {
        secretName = "redis-secret"
        secretKey  = "connection-string"
      }
      
      ingress = {
        enabled = true
        host    = var.environment == "production" ? "api.pyairtable.com" : "${var.environment}.pyairtable.local"
      }
      
      autoscaling = {
        enabled     = true
        minReplicas = local.config.min_size
        maxReplicas = local.config.max_size
      }
      
      resources = local.service_configs
    }
  }
}

# Monitoring and Alerting
output "monitoring_info" {
  description = "Monitoring and alerting configuration"
  value = {
    sns_topic_arn = aws_sns_topic.alerts.arn
    dashboard_url = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
    log_groups    = [for lg in aws_cloudwatch_log_group.application_logs : lg.name]
    
    prometheus_endpoints = {
      cluster_metrics = "http://prometheus.pyairtable-monitoring:9090"
      application_metrics = "http://prometheus.pyairtable:9090"
    }
    
    grafana_url = var.environment == "production" ? "https://grafana.pyairtable.com" : "http://grafana.${var.environment}.pyairtable.local"
    
    jaeger_url = var.environment == "production" ? "https://jaeger.pyairtable.com" : "http://jaeger.${var.environment}.pyairtable.local"
  }
}