# Optimized Variables for PyAirtable Infrastructure
# Cost-conscious defaults with performance targets

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "pyairtable"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"  # Central Europe for client proximity
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# EKS Configuration
variable "eks_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.28"
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "enable_spot_fleet" {
  description = "Enable spot fleet for additional cost savings"
  type        = bool
  default     = false  # Disabled by default for simplicity
}

# Node Group Configurations
variable "go_services_node_config" {
  description = "Configuration for Go services node group"
  type = object({
    instance_types = list(string)
    min_size      = number
    max_size      = number
    desired_size  = number
    capacity_type = string
  })
  default = {
    instance_types = ["t3.medium", "t3.large"]
    min_size       = 1
    max_size       = 6
    desired_size   = 2
    capacity_type  = "SPOT"
  }
}

variable "python_ai_node_config" {
  description = "Configuration for Python AI services node group"
  type = object({
    instance_types = list(string)
    min_size      = number
    max_size      = number
    desired_size  = number
    capacity_type = string
  })
  default = {
    instance_types = ["r5.large", "r5.xlarge"]
    min_size       = 1
    max_size       = 4
    desired_size   = 2
    capacity_type  = "SPOT"
  }
}

variable "general_services_node_config" {
  description = "Configuration for general services node group"
  type = object({
    instance_types = list(string)
    min_size      = number
    max_size      = number
    desired_size  = number
    capacity_type = string
  })
  default = {
    instance_types = ["t3.medium", "t3.large"]
    min_size       = 1
    max_size       = 4
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
  }
}

# Database Configuration
variable "postgres_db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "pyairtable"
}

variable "postgres_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgres"
}

variable "postgres_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Redis authentication token"
  type        = string
  sensitive   = true
}

# Aurora Serverless Configuration
variable "aurora_serverless_config" {
  description = "Aurora Serverless v2 configuration"
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = {
    min_capacity = 0.5
    max_capacity = 4
  }
}

# Service Configuration
variable "services" {
  description = "List of microservices to deploy"
  type        = list(string)
  default = [
    "api-gateway",
    "llm-orchestrator",
    "mcp-server", 
    "airtable-gateway",
    "platform-services",
    "automation-services",
    "frontend"
  ]
}

# Resource Limits
variable "resource_quotas" {
  description = "Kubernetes resource quotas"
  type = object({
    cpu_requests    = string
    memory_requests = string
    cpu_limits      = string
    memory_limits   = string
    pods           = string
  })
  default = {
    cpu_requests    = "10"
    memory_requests = "20Gi"
    cpu_limits      = "20"
    memory_limits   = "40Gi"
    pods           = "25"
  }
}

# Monitoring Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14  # Reduced for cost optimization
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring (additional cost)"
  type        = bool
  default     = false
}

# CI/CD Configuration
variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "reg-kris"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "pyairtable-compose"
}

variable "github_branch" {
  description = "GitHub branch for CI/CD"
  type        = string
  default     = "main"
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

# Cost Optimization Settings
variable "cost_optimization_enabled" {
  description = "Enable aggressive cost optimization features"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 600
}

variable "cost_alert_threshold" {
  description = "Cost alert threshold as percentage of budget"
  type        = number
  default     = 80
}

# Auto-scaling Configuration
variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler"
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaler" {
  description = "Enable vertical pod autoscaler"
  type        = bool
  default     = true
}

variable "enable_horizontal_pod_autoscaler" {
  description = "Enable horizontal pod autoscaler"
  type        = bool
  default     = true
}

# Backup and DR Configuration
variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backups"
  type        = bool
  default     = false  # Disabled for cost optimization
}

# Security Configuration
variable "enable_pod_security_standards" {
  description = "Enable Kubernetes Pod Security Standards"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Kubernetes Network Policies"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda functions"
  type        = number
  default     = 10
}

variable "lambda_provisioned_concurrency" {
  description = "Provisioned concurrency for Lambda functions"
  type        = number
  default     = 0  # Disabled for cost optimization
}

# Data Sources
data "aws_ami" "eks_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_version}-v*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Local Values for Cost Calculations
locals {
  # Cost calculations (monthly estimates in USD)
  cost_breakdown = {
    # EKS Control Plane
    eks_cluster = 72.00  # $0.10/hour * 24 * 30

    # Compute Costs (with 70% spot savings)
    compute_costs = {
      go_services_spot     = 54.00   # t3.medium spot: ~$0.025/hour * 2 instances * 24 * 30
      python_ai_spot       = 180.00  # r5.large spot: ~$0.042/hour * 2 instances * 24 * 30  
      general_on_demand    = 96.00   # t3.medium on-demand: ~$0.067/hour * 2 instances * 24 * 30
      total_compute        = 330.00
    }

    # Database Costs
    database_costs = {
      aurora_serverless    = 60.00   # Min 0.5 ACU * $0.168/hour * 24 * 30
      aurora_storage       = 15.00   # 100GB * $0.15/GB
      redis_cluster        = 30.00   # cache.t3.micro * 2 * $0.021/hour * 24 * 30
      total_database       = 105.00
    }

    # Serverless Costs
    serverless_costs = {
      lambda_functions     = 15.00   # Conservative estimate for processing
      api_gateway         = 5.00    # Minimal usage
      s3_storage          = 10.00   # 100GB + requests
      total_serverless    = 30.00
    }

    # Network and Data Transfer
    network_costs = {
      nat_gateway         = 45.00   # $0.045/hour * 2 * 24 * 30
      load_balancer       = 16.20   # NLB: $0.0225/hour * 24 * 30
      data_transfer       = 20.00   # Inter-AZ and egress
      total_network       = 81.20
    }

    # Monitoring and Logging
    observability_costs = {
      cloudwatch_logs     = 5.00    # With reduced retention
      cloudwatch_metrics  = 10.00   # Custom metrics
      prometheus          = 0.00    # Self-hosted on EKS
      total_observability = 15.00
    }

    # CI/CD Costs
    cicd_costs = {
      codebuild          = 10.00    # build.general1.small usage
      codepipeline       = 1.00     # $1 per active pipeline
      ecr_storage        = 5.00     # Container image storage
      total_cicd         = 16.00
    }

    # Total Monthly Cost
    total_monthly = 649.20
  }

  # Environment-specific cost adjustments
  environment_cost_multipliers = {
    dev     = 0.6   # Reduced resources for development
    staging = 0.8   # Moderate resources for testing
    prod    = 1.0   # Full resources for production
  }

  # Final cost calculation
  estimated_monthly_cost = local.cost_breakdown.total_monthly * local.environment_cost_multipliers[var.environment]

  # Cost optimization recommendations
  cost_optimizations = {
    current_estimate = local.estimated_monthly_cost
    target_range     = "300-600"
    within_budget    = local.estimated_monthly_cost <= var.monthly_budget_limit
    
    savings_opportunities = {
      "Enable more spot instances"          = "Additional 20% savings (~$65/month)"
      "Use Fargate for batch workloads"    = "Pay per use, ~$30/month savings"
      "Implement scheduled scaling"        = "Scale down off-hours, ~$80/month savings"
      "Optimize storage classes"           = "Use different tiers, ~$15/month savings"
      "Reserved instances for stable workloads" = "Up to 75% savings, ~$100/month"
    }

    immediate_actions = local.estimated_monthly_cost > var.monthly_budget_limit ? [
      "Reduce node group sizes",
      "Enable more aggressive spot instance usage",
      "Implement scheduled scaling for non-prod environments",
      "Use smaller instance types where possible"
    ] : [
      "Monitor actual usage patterns",
      "Consider reserved instances for stable workloads",
      "Implement more advanced autoscaling policies"
    ]
  }

  # Service-to-node-group mapping
  service_node_assignment = {
    # Go services -> compute-optimized nodes
    "api-gateway"        = "go-services"
    "platform-services"  = "go-services"
    
    # Python AI services -> memory-optimized nodes  
    "llm-orchestrator"   = "python-ai"
    "mcp-server"        = "python-ai"
    
    # Other services -> general nodes
    "airtable-gateway"   = "general"
    "automation-services" = "general"
    "frontend"           = "general"
    "postgres"           = "general"
    "redis"             = "general"
  }

  # Tags for all resources
  common_tags = {
    Project              = var.project_name
    Environment          = var.environment
    ManagedBy           = "Terraform"
    CostCenter          = "Engineering"
    Owner               = "DevOps"
    Backup              = var.environment == "prod" ? "Required" : "Optional"
    MonitoringLevel     = var.environment == "prod" ? "High" : "Standard"
    CostOptimization    = var.cost_optimization_enabled ? "Enabled" : "Disabled"
  }
}

# Outputs for cost analysis
output "cost_analysis" {
  description = "Detailed cost breakdown and optimization recommendations"
  value = {
    estimated_monthly_cost = "$${format("%.2f", local.estimated_monthly_cost)}"
    cost_breakdown = {
      for category, cost in local.cost_breakdown : category => "$${format("%.2f", cost)}"
    }
    environment_multiplier = local.environment_cost_multipliers[var.environment]
    within_budget         = local.cost_optimizations.within_budget
    target_range          = local.cost_optimizations.target_range
    cost_optimizations    = local.cost_optimizations.savings_opportunities
    immediate_actions     = local.cost_optimizations.immediate_actions
  }
}

output "deployment_configuration" {
  description = "Deployment configuration summary"
  value = {
    environment               = var.environment
    region                   = var.aws_region
    total_services           = length(var.services)
    node_groups             = 3
    spot_instances_enabled  = var.enable_spot_instances
    autoscaling_enabled     = var.enable_cluster_autoscaler
    serverless_functions    = 3
    estimated_monthly_cost  = "$${format("%.2f", local.estimated_monthly_cost)}"
    service_node_mapping    = local.service_node_assignment
  }
}