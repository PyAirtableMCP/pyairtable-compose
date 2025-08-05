# Monitoring Module Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

# CloudWatch Container Insights
variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "enable_fluent_bit" {
  description = "Enable Fluent Bit for log forwarding"
  type        = bool
  default     = true
}

variable "cloudwatch_agent_irsa_role_arn" {
  description = "ARN of the CloudWatch Agent IRSA role"
  type        = string
  default     = ""
}

# Prometheus Stack
variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "prometheus_chart_version" {
  description = "Chart version for kube-prometheus-stack"
  type        = string
  default     = "55.5.0"
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "20Gi"
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "15d"
}

# Grafana
variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana"
  type        = string
  default     = "5Gi"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin123"
  sensitive   = true
}

# Alertmanager
variable "enable_alertmanager" {
  description = "Enable Alertmanager for alerts"
  type        = bool
  default     = true
}

# Loki
variable "enable_loki" {
  description = "Enable Loki for log aggregation"
  type        = bool
  default     = true
}

variable "loki_chart_version" {
  description = "Chart version for Loki"
  type        = string
  default     = "5.36.2"
}

variable "loki_storage_size" {
  description = "Storage size for Loki"
  type        = string
  default     = "10Gi"
}

variable "promtail_chart_version" {
  description = "Chart version for Promtail"
  type        = string
  default     = "6.15.3"
}

# Tempo
variable "enable_tempo" {
  description = "Enable Tempo for distributed tracing"
  type        = bool
  default     = false
}

variable "tempo_chart_version" {
  description = "Chart version for Tempo"
  type        = string
  default     = "1.7.1"
}

variable "tempo_storage_size" {
  description = "Storage size for Tempo"
  type        = string
  default     = "10Gi"
}

# OpenTelemetry
variable "enable_opentelemetry" {
  description = "Enable OpenTelemetry Collector"
  type        = bool
  default     = false
}

variable "opentelemetry_chart_version" {
  description = "Chart version for OpenTelemetry Collector"
  type        = string
  default     = "0.82.0"
}

# CloudWatch Alarms
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}