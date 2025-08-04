# Multi-Region Infrastructure Outputs

# Global DNS and CDN Outputs
output "domain_name" {
  description = "Primary domain name"
  value       = var.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.global_load_balancing.cloudfront_distribution_id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.global_load_balancing.cloudfront_domain_name
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

# Regional Infrastructure Outputs
output "us_east_region" {
  description = "US East region infrastructure details"
  value = {
    vpc_id                = module.us_east_region.vpc_id
    alb_dns_name         = module.us_east_region.alb_dns_name
    alb_zone_id          = module.us_east_region.alb_zone_id
    db_endpoint          = module.us_east_region.db_endpoint
    redis_endpoint       = module.us_east_region.redis_endpoint
    eks_cluster_endpoint = module.us_east_region.eks_cluster_endpoint
    region              = "us-east-1"
  }
}

output "eu_west_region" {
  description = "EU West region infrastructure details"
  value = {
    vpc_id                = module.eu_west_region.vpc_id
    alb_dns_name         = module.eu_west_region.alb_dns_name
    alb_zone_id          = module.eu_west_region.alb_zone_id
    db_endpoint          = module.eu_west_region.db_endpoint
    redis_endpoint       = module.eu_west_region.redis_endpoint
    eks_cluster_endpoint = module.eu_west_region.eks_cluster_endpoint
    region              = "eu-west-1"
  }
}

output "ap_southeast_region" {
  description = "AP Southeast region infrastructure details"
  value = {
    vpc_id                = module.ap_southeast_region.vpc_id
    alb_dns_name         = module.ap_southeast_region.alb_dns_name
    alb_zone_id          = module.ap_southeast_region.alb_zone_id
    db_endpoint          = module.ap_southeast_region.db_endpoint
    redis_endpoint       = module.ap_southeast_region.redis_endpoint
    eks_cluster_endpoint = module.ap_southeast_region.eks_cluster_endpoint
    region              = "ap-southeast-1"
  }
}

# Database Replication Outputs
output "database_configuration" {
  description = "Database replication configuration"
  value = {
    primary_endpoint = module.us_east_region.db_endpoint
    replicas = {
      eu_west      = module.eu_west_region.db_endpoint
      ap_southeast = module.ap_southeast_region.db_endpoint
    }
    backup_retention_days = var.backup_retention_period
    multi_az_enabled     = true
  }
  sensitive = true
}

# Global Load Balancing Configuration
output "global_load_balancing" {
  description = "Global load balancing configuration"
  value = {
    cloudfront_distribution_id = module.global_load_balancing.cloudfront_distribution_id
    waf_web_acl_id           = module.global_load_balancing.waf_web_acl_id
    static_content_bucket    = module.global_load_balancing.static_content_bucket
    geographic_routing       = module.global_load_balancing.geographic_routing
  }
}

# Security Configuration
output "security_features" {
  description = "Security features enabled"
  value = {
    encryption_at_rest        = var.enable_encryption_at_rest
    encryption_in_transit     = var.enable_encryption_in_transit
    vpc_flow_logs_enabled    = var.enable_vpc_flow_logs
    waf_enabled              = var.enable_waf
    security_headers_enabled = true
  }
}

# Monitoring and Alerting
output "monitoring_configuration" {
  description = "Monitoring and alerting configuration"
  value = {
    health_checks = {
      us_east      = module.us_east_region.health_check_id
      eu_west      = module.eu_west_region.health_check_id
      ap_southeast = module.ap_southeast_region.health_check_id
    }
    log_retention_days      = var.log_retention_days
    detailed_monitoring     = var.enable_detailed_monitoring
    cloudwatch_dashboards   = true
  }
}

# Disaster Recovery Configuration
output "disaster_recovery" {
  description = "Disaster recovery configuration"
  value = {
    auto_failover_enabled      = var.auto_failover_enabled
    failover_threshold_seconds = var.failover_threshold_seconds
    rto_minutes               = var.rto_minutes
    rpo_minutes               = var.rpo_minutes
    sns_topic_arn             = module.disaster_recovery.sns_topic_arn
    step_function_arn         = module.disaster_recovery.step_function_arn
  }
}

# Cost Optimization
output "cost_optimization" {
  description = "Cost optimization features"
  value = {
    spot_instances_enabled      = var.enable_spot_instances
    auto_scaling_enabled       = var.enable_auto_scaling
    cost_anomaly_detection     = var.enable_cost_anomaly_detection
    monthly_budget_limit       = var.monthly_budget_limit
    storage_lifecycle_policies = true
  }
}

# Network Configuration
output "network_configuration" {
  description = "Multi-region network configuration"
  value = {
    vpc_peering_connections = {
      us_to_eu = aws_vpc_peering_connection.us_to_eu.id
      us_to_ap = aws_vpc_peering_connection.us_to_ap.id
    }
    transit_gateway_enabled = var.enable_transit_gateway
    private_link_enabled   = var.enable_private_link
    cross_region_connectivity = true
  }
}

# Kubernetes Configuration
output "kubernetes_clusters" {
  description = "EKS cluster information"
  value = {
    us_east = {
      cluster_name     = module.us_east_region.eks_cluster_id
      cluster_endpoint = module.us_east_region.eks_cluster_endpoint
      cluster_version  = module.us_east_region.eks_cluster_version
    }
    eu_west = {
      cluster_name     = module.eu_west_region.eks_cluster_id
      cluster_endpoint = module.eu_west_region.eks_cluster_endpoint
      cluster_version  = module.eu_west_region.eks_cluster_version
    }
    ap_southeast = {
      cluster_name     = module.ap_southeast_region.eks_cluster_id
      cluster_endpoint = module.ap_southeast_region.eks_cluster_endpoint
      cluster_version  = module.ap_southeast_region.eks_cluster_version
    }
  }
}

# Compliance and Data Residency
output "compliance_features" {
  description = "Compliance and data residency features"
  value = {
    gdpr_compliance_enabled = var.enable_gdpr_compliance
    data_classification    = var.data_classification_tags
    regional_data_residency = {
      us_east      = "United States"
      eu_west      = "European Union"
      ap_southeast = "Asia Pacific"
    }
    audit_logging_enabled = true
  }
}

# Service Endpoints
output "service_endpoints" {
  description = "Service endpoints for each region"
  value = {
    global = {
      primary_domain = var.domain_name
      api_domain    = "api.${var.domain_name}"
      cdn_domain    = module.global_load_balancing.cloudfront_domain_name
    }
    regional = {
      us_east = {
        alb_endpoint = module.us_east_region.alb_dns_name
        region       = "us-east-1"
      }
      eu_west = {
        alb_endpoint = module.eu_west_region.alb_dns_name
        region       = "eu-west-1"
      }
      ap_southeast = {
        alb_endpoint = module.ap_southeast_region.alb_dns_name
        region       = "ap-southeast-1"
      }
    }
  }
}

# Performance Metrics
output "performance_configuration" {
  description = "Performance optimization settings"
  value = {
    auto_scaling = {
      enabled                   = var.enable_auto_scaling
      target_cpu_utilization   = var.target_cpu_utilization
      target_memory_utilization = var.target_memory_utilization
    }
    database_performance = {
      performance_insights_enabled = true
      enhanced_monitoring_enabled  = true
      multi_az_enabled            = true
    }
    cache_configuration = {
      redis_cluster_mode_enabled = true
      cache_node_type           = var.redis_node_type
      num_cache_nodes          = var.redis_num_cache_nodes
    }
  }
}

# Operational Information
output "operational_information" {
  description = "Key operational information for managing the infrastructure"
  value = {
    terraform_state_bucket = "pyairtable-terraform-state-global"
    deployment_regions    = ["us-east-1", "eu-west-1", "ap-southeast-1"]
    primary_region       = var.primary_region
    environment         = var.environment
    project_name        = var.project_name
    managed_by          = "Terraform"
    last_updated        = timestamp()
  }
}

# Connection Strings (Sensitive)
output "connection_strings" {
  description = "Database and cache connection strings"
  value = {
    database_secrets = {
      primary_secret_arn = module.us_east_region.database_secret_arn
      eu_secret_arn     = module.eu_west_region.database_secret_arn
      ap_secret_arn     = module.ap_southeast_region.database_secret_arn
    }
    redis_secrets = {
      primary_secret_arn = module.us_east_region.redis_secret_arn
      eu_secret_arn     = module.eu_west_region.redis_secret_arn
      ap_secret_arn     = module.ap_southeast_region.redis_secret_arn
    }
  }
  sensitive = true
}

# Cost Tracking Information
output "cost_tracking" {
  description = "Cost tracking and allocation information"
  value = {
    cost_allocation_tags = {
      Project         = var.project_name
      Environment     = var.environment
      ManagedBy       = "Terraform"
      CostCenter      = "Engineering"
      BusinessUnit    = "Platform"
    }
    monthly_budget_limit    = var.monthly_budget_limit
    cost_anomaly_detection = var.enable_cost_anomaly_detection
    regions_deployed       = ["us-east-1", "eu-west-1", "ap-southeast-1"]
  }
}

# Backup and Recovery Information
output "backup_recovery" {
  description = "Backup and recovery configuration"
  value = {
    database_backups = {
      retention_days     = var.backup_retention_period
      backup_window     = var.backup_window
      cross_region_backup = true
    }
    s3_backup_buckets = {
      primary = aws_s3_bucket.cross_region_backup.bucket
      eu      = aws_s3_bucket.eu_backup.bucket
      ap      = aws_s3_bucket.ap_backup.bucket
    }
    disaster_recovery_enabled = true
  }
}