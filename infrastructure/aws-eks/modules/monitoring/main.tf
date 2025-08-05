# Monitoring Module for PyAirtable EKS Infrastructure
# Comprehensive monitoring with CloudWatch, Prometheus, Grafana, and Loki

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

# CloudWatch Container Insights
resource "kubernetes_namespace" "amazon_cloudwatch" {
  count = var.enable_container_insights ? 1 : 0

  metadata {
    name = "amazon-cloudwatch"
    labels = {
      name = "amazon-cloudwatch"
    }
  }
}

resource "kubernetes_config_map" "fluent_bit_config" {
  count = var.enable_fluent_bit ? 1 : 0

  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace.amazon_cloudwatch[0].metadata[0].name
  }

  data = {
    "fluent-bit.conf" = file("${path.module}/templates/fluent-bit.conf")
    "application-log.conf" = file("${path.module}/templates/application-log.conf")
    "dataplane-log.conf" = file("${path.module}/templates/dataplane-log.conf")
    "host-log.conf" = file("${path.module}/templates/host-log.conf")
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

resource "kubernetes_daemonset" "fluent_bit" {
  count = var.enable_fluent_bit ? 1 : 0

  metadata {
    name      = "fluent-bit"
    namespace = kubernetes_namespace.amazon_cloudwatch[0].metadata[0].name
    labels = {
      k8s-app = "fluent-bit"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app = "fluent-bit"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fluent_bit[0].metadata[0].name
        
        container {
          name  = "fluent-bit"
          image = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
          
          env {
            name = "AWS_REGION"
            value_from {
              config_map_key_ref {
                name = "fluent-bit-config"
                key  = "aws_region"
              }
            }
          }
          
          env {
            name = "CLUSTER_NAME"
            value = var.cluster_name
          }

          resources {
            limits = {
              memory = "200Mi"
              cpu    = "100m"
            }
            requests = {
              memory = "100Mi"
              cpu    = "50m"
            }
          }

          volume_mount {
            name       = "fluentbitstate"
            mount_path = "/var/fluent-bit/state"
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          volume_mount {
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
          }
        }

        volume {
          name = "fluentbitstate"
          host_path {
            path = "/var/fluent-bit/state"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "fluent-bit-config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config[0].metadata[0].name
          }
        }

        termination_grace_period_seconds = 10
      }
    }
  }

  depends_on = [kubernetes_service_account.fluent_bit, kubernetes_config_map.fluent_bit_config]
}

resource "kubernetes_service_account" "fluent_bit" {
  count = var.enable_fluent_bit ? 1 : 0

  metadata {
    name      = "fluent-bit"
    namespace = kubernetes_namespace.amazon_cloudwatch[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.cloudwatch_agent_irsa_role_arn
    }
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

# Prometheus Stack
resource "kubernetes_namespace" "monitoring" {
  count = var.enable_prometheus ? 1 : 0

  metadata {
    name = "monitoring"
    labels = {
      name = "monitoring"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  count = var.enable_prometheus ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_chart_version
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  values = [
    yamlencode({
      # Prometheus configuration
      prometheus = {
        enabled = true
        prometheusSpec = {
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
          retention = var.prometheus_retention
          resources = {
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
          # Cost optimization: reduce scrape intervals
          scrapeInterval = "30s"
          evaluationInterval = "30s"
        }
        service = {
          type = "ClusterIP"
        }
      }

      # Grafana configuration
      grafana = {
        enabled = var.enable_grafana
        admin = {
          existingSecret = "grafana-admin-secret"
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }
        persistence = {
          enabled          = true
          type            = "pvc"
          storageClassName = "gp3"
          size            = var.grafana_storage_size
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name            = "default"
                orgId           = 1
                folder          = ""
                type            = "file"
                disableDeletion = false
                editable        = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }
        dashboards = {
          default = {
            "kubernetes-cluster-monitoring" = {
              url = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json"
            }
            "kubernetes-pods-monitoring" = {
              url = "https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-pods.json"
            }
            "node-exporter-full" = {
              gnetId = 1860
              revision = 31
            }
          }
        }
        service = {
          type = "ClusterIP"
        }
      }

      # Node Exporter
      nodeExporter = {
        enabled = true
        resources = {
          limits = {
            cpu    = "100m"
            memory = "50Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "25Mi"
          }
        }
      }

      # kube-state-metrics
      kubeStateMetrics = {
        enabled = true
        resources = {
          limits = {
            cpu    = "100m"
            memory = "150Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "75Mi"
          }
        }
      }

      # Alertmanager
      alertmanager = {
        enabled = var.enable_alertmanager
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp3"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }
          resources = {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring, kubernetes_secret.grafana_admin]
}

# Grafana admin credentials secret
resource "kubernetes_secret" "grafana_admin" {
  count = var.enable_grafana ? 1 : 0

  metadata {
    name      = "grafana-admin-secret"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }

  data = {
    "admin-user"     = var.grafana_admin_user
    "admin-password" = var.grafana_admin_password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.monitoring]
}

# Loki for log aggregation
resource "helm_release" "loki" {
  count = var.enable_loki ? 1 : 0

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  values = [
    yamlencode({
      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        storage = {
          type = "filesystem"
        }
      }
      
      singleBinary = {
        replicas = 1
        persistence = {
          enabled          = true
          storageClass     = "gp3"
          size            = var.loki_storage_size
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }

      monitoring = {
        serviceMonitor = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

# Promtail for log collection
resource "helm_release" "promtail" {
  count = var.enable_loki ? 1 : 0

  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_chart_version
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  values = [
    yamlencode({
      config = {
        lokiAddress = "http://loki:3100/loki/api/v1/push"
      }
      
      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }

      serviceMonitor = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.loki]
}

# Tempo for distributed tracing
resource "helm_release" "tempo" {
  count = var.enable_tempo ? 1 : 0

  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  values = [
    yamlencode({
      tempo = {
        storage = {
          trace = {
            backend = "local"
            local = {
              path = "/var/tempo"
            }
          }
        }
      }

      persistence = {
        enabled      = true
        storageClass = "gp3"
        size        = var.tempo_storage_size
      }

      resources = {
        limits = {
          cpu    = "500m"
          memory = "1Gi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }

      serviceMonitor = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

# OpenTelemetry Collector
resource "helm_release" "opentelemetry_collector" {
  count = var.enable_opentelemetry ? 1 : 0

  name       = "opentelemetry-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = var.opentelemetry_chart_version
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  values = [
    yamlencode({
      mode = "daemonset"
      
      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:4317"
              }
              http = {
                endpoint = "0.0.0.0:4318"
              }
            }
          }
          prometheus = {
            config = {
              scrape_configs = [
                {
                  job_name = "opentelemetry-collector"
                  scrape_interval = "10s"
                  static_configs = [
                    {
                      targets = ["0.0.0.0:8888"]
                    }
                  ]
                }
              ]
            }
          }
        }
        
        processors = {
          batch = {}
          memory_limiter = {
            limit_mib = 512
          }
        }
        
        exporters = {
          prometheus = {
            endpoint = "0.0.0.0:8889"
          }
          otlp = {
            endpoint = var.enable_tempo ? "http://tempo:4317" : "http://jaeger:14250"
            tls = {
              insecure = true
            }
          }
          logging = {
            loglevel = "debug"
          }
        }
        
        service = {
          telemetry = {
            metrics = {
              address = "0.0.0.0:8888"
            }
          }
          pipelines = {
            traces = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "batch"]
              exporters  = var.enable_tempo ? ["otlp"] : ["logging"]
            }
            metrics = {
              receivers  = ["otlp", "prometheus"]
              processors = ["memory_limiter", "batch"]
              exporters  = ["prometheus"]
            }
            logs = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "batch"]
              exporters  = ["logging"]
            }
          }
        }
      }

      resources = {
        limits = {
          cpu    = "200m"
          memory = "512Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }

      serviceMonitor = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

# CloudWatch Alarms for critical metrics
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name}-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EKS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EKS cluster CPU utilization"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "pod_restart_rate" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.name}-high-pod-restart-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "pod_restart_rate"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors pod restart rate"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = var.tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0

  dashboard_name = "${local.name}-eks-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_count", "ClusterName", var.cluster_name],
            [".", "cluster_running_pod_count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "EKS Cluster Overview"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", var.cluster_name],
            [".", "pod_memory_utilization", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Pod Resource Utilization"
          period  = 300
        }
      }
    ]
  })
}

# Data source for region
data "aws_region" "current" {}