# Monitoring Module Outputs

# Namespaces
output "monitoring_namespace" {
  description = "Namespace where monitoring stack is deployed"
  value       = var.enable_prometheus ? kubernetes_namespace.monitoring[0].metadata[0].name : null
}

output "cloudwatch_namespace" {
  description = "Namespace where CloudWatch components are deployed"
  value       = var.enable_container_insights ? kubernetes_namespace.amazon_cloudwatch[0].metadata[0].name : null
}

# Prometheus Stack
output "prometheus_service_name" {
  description = "Prometheus service name"
  value       = var.enable_prometheus ? "${helm_release.kube_prometheus_stack[0].name}-prometheus" : null
}

output "grafana_service_name" {
  description = "Grafana service name"
  value       = var.enable_grafana ? "${helm_release.kube_prometheus_stack[0].name}-grafana" : null
}

output "alertmanager_service_name" {
  description = "Alertmanager service name"
  value       = var.enable_alertmanager ? "${helm_release.kube_prometheus_stack[0].name}-alertmanager" : null
}

# Loki Stack
output "loki_service_name" {
  description = "Loki service name"
  value       = var.enable_loki ? helm_release.loki[0].name : null
}

output "promtail_daemonset_name" {
  description = "Promtail DaemonSet name"
  value       = var.enable_loki ? helm_release.promtail[0].name : null
}

# Tempo
output "tempo_service_name" {
  description = "Tempo service name"
  value       = var.enable_tempo ? helm_release.tempo[0].name : null
}

# OpenTelemetry
output "opentelemetry_collector_name" {
  description = "OpenTelemetry Collector name"
  value       = var.enable_opentelemetry ? helm_release.opentelemetry_collector[0].name : null
}

# CloudWatch Resources
output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.high_cpu_utilization[0].alarm_name,
    aws_cloudwatch_metric_alarm.pod_restart_rate[0].alarm_name
  ] : []
}

# Service Account
output "fluent_bit_service_account_name" {
  description = "Fluent Bit service account name"
  value       = var.enable_fluent_bit ? kubernetes_service_account.fluent_bit[0].metadata[0].name : null
}

# Grafana Access Information
output "grafana_admin_credentials" {
  description = "Grafana admin credentials (sensitive)"
  value = var.enable_grafana ? {
    username = var.grafana_admin_user
    password = var.grafana_admin_password
  } : null
  sensitive = true
}

# Service URLs (for port-forwarding)
output "service_urls" {
  description = "Service URLs for accessing monitoring components"
  value = {
    prometheus   = var.enable_prometheus ? "http://localhost:9090 (kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/${helm_release.kube_prometheus_stack[0].name}-prometheus 9090:9090)" : null
    grafana     = var.enable_grafana ? "http://localhost:3000 (kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/${helm_release.kube_prometheus_stack[0].name}-grafana 3000:80)" : null
    alertmanager = var.enable_alertmanager ? "http://localhost:9093 (kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/${helm_release.kube_prometheus_stack[0].name}-alertmanager 9093:9093)" : null
    loki        = var.enable_loki ? "http://localhost:3100 (kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/loki 3100:3100)" : null
    tempo       = var.enable_tempo ? "http://localhost:3110 (kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} svc/tempo 3110:3100)" : null
  }
}

# Monitoring Stack Summary
output "monitoring_summary" {
  description = "Summary of monitoring stack components"
  value = {
    prometheus_enabled           = var.enable_prometheus
    grafana_enabled             = var.enable_grafana
    alertmanager_enabled        = var.enable_alertmanager
    loki_enabled               = var.enable_loki
    tempo_enabled              = var.enable_tempo
    opentelemetry_enabled      = var.enable_opentelemetry
    container_insights_enabled = var.enable_container_insights
    fluent_bit_enabled         = var.enable_fluent_bit
    cloudwatch_alarms_enabled  = var.enable_cloudwatch_alarms
    cloudwatch_dashboard_enabled = var.enable_cloudwatch_dashboard
    monitoring_namespace       = var.enable_prometheus ? kubernetes_namespace.monitoring[0].metadata[0].name : null
  }
}