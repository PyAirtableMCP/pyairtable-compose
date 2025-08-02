#!/bin/bash

# PyAirtable Monitoring Stack Deployment Script
# Deploys Prometheus, Grafana, and Jaeger for observability

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="${NAMESPACE:-pyairtable}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-pyairtable-monitoring}"
CLUSTER_TYPE="${CLUSTER_TYPE:-minikube}"

echo -e "${BLUE}📊 Starting PyAirtable Monitoring Stack Deployment${NC}"
echo -e "${BLUE}🎯 Application Namespace: ${NAMESPACE}${NC}"
echo -e "${BLUE}📈 Monitoring Namespace: ${MONITORING_NAMESPACE}${NC}"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites${NC}"
    
    local missing_tools=()
    
    # Check required tools
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}Please install the missing tools and try again${NC}"
        exit 1
    fi
    
    # Check if main namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Application namespace '$NAMESPACE' not found${NC}"
        echo -e "${YELLOW}Please deploy the main application first${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites satisfied${NC}"
}

# Function to create monitoring namespace
create_monitoring_namespace() {
    echo -e "${BLUE}📦 Creating monitoring namespace${NC}"
    
    kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Label the namespace for monitoring
    kubectl label namespace "$MONITORING_NAMESPACE" name=monitoring --overwrite
    
    echo -e "${GREEN}✅ Monitoring namespace created${NC}"
}

# Function to deploy monitoring stack using manifests
deploy_monitoring_manifests() {
    echo -e "${BLUE}📊 Deploying monitoring stack with manifests${NC}"
    
    # Apply monitoring stack manifests
    kubectl apply -f k8s/manifests/monitoring-stack.yaml
    
    echo -e "${GREEN}✅ Monitoring manifests applied${NC}"
}

# Function to deploy monitoring stack using Helm
deploy_monitoring_helm() {
    echo -e "${BLUE}📊 Deploying monitoring stack with Helm${NC}"
    
    # Add Helm repositories
    echo -e "${YELLOW}📦 Adding Helm repositories${NC}"
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
    helm repo update
    
    # Deploy Prometheus
    echo -e "${PURPLE}🔍 Deploying Prometheus${NC}"
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace "$MONITORING_NAMESPACE" \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.retention=15d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
        --set grafana.adminPassword=admin \
        --set grafana.persistence.enabled=true \
        --set grafana.persistence.size=1Gi \
        --wait
    
    # Deploy Jaeger
    echo -e "${PURPLE}🔍 Deploying Jaeger${NC}"
    helm upgrade --install jaeger jaegertracing/jaeger \
        --namespace "$MONITORING_NAMESPACE" \
        --set provisionDataStore.cassandra=false \
        --set provisionDataStore.elasticsearch=false \
        --set allInOne.enabled=true \
        --set agent.enabled=false \
        --set collector.enabled=false \
        --set query.enabled=false \
        --wait
    
    echo -e "${GREEN}✅ Monitoring stack deployed with Helm${NC}"
}

# Function to configure service monitors
configure_service_monitors() {
    echo -e "${BLUE}📊 Configuring service monitors${NC}"
    
    # Create ServiceMonitor for PyAirtable services
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pyairtable-services
  namespace: $MONITORING_NAMESPACE
  labels:
    app: pyairtable
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: pyairtable
  namespaceSelector:
    matchNames:
    - $NAMESPACE
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF
    
    # Create ServiceMonitor for Istio (if available)
    if kubectl get namespace istio-system >/dev/null 2>&1; then
        echo -e "${YELLOW}🕸️  Configuring Istio service monitor${NC}"
        cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-mesh
  namespace: $MONITORING_NAMESPACE
  labels:
    app: istio
    release: prometheus
spec:
  selector:
    matchLabels:
      app: istiod
  namespaceSelector:
    matchNames:
    - istio-system
  endpoints:
  - port: http-monitoring
    interval: 30s
    path: /stats/prometheus
EOF
    fi
    
    echo -e "${GREEN}✅ Service monitors configured${NC}"
}

# Function to setup Grafana dashboards
setup_grafana_dashboards() {
    echo -e "${BLUE}📊 Setting up Grafana dashboards${NC}"
    
    # Wait for Grafana to be ready
    echo -e "${YELLOW}⏳ Waiting for Grafana to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus-grafana -n "$MONITORING_NAMESPACE"
    
    # Create PyAirtable dashboard configmap
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: pyairtable-dashboard
  namespace: $MONITORING_NAMESPACE
  labels:
    grafana_dashboard: "1"
data:
  pyairtable-overview.json: |
    {
      "dashboard": {
        "id": null,
        "title": "PyAirtable Overview",
        "tags": ["pyairtable"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Request Rate",
            "type": "stat",
            "targets": [
              {
                "expr": "sum(rate(http_requests_total{namespace=\"$NAMESPACE\"}[5m]))",
                "format": "time_series",
                "legendFormat": "Requests/sec"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "reqps"
              }
            },
            "gridPos": {"h": 8, "w": 6, "x": 0, "y": 0}
          },
          {
            "id": 2,
            "title": "Error Rate",
            "type": "stat",
            "targets": [
              {
                "expr": "sum(rate(http_requests_total{namespace=\"$NAMESPACE\",code=~\"5..\"}[5m])) / sum(rate(http_requests_total{namespace=\"$NAMESPACE\"}[5m])) * 100",
                "format": "time_series",
                "legendFormat": "Error %"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "percent"
              }
            },
            "gridPos": {"h": 8, "w": 6, "x": 6, "y": 0}
          },
          {
            "id": 3,
            "title": "Average Response Time",
            "type": "stat",
            "targets": [
              {
                "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace=\"$NAMESPACE\"}[5m])) by (le))",
                "format": "time_series",
                "legendFormat": "P95 Latency"
              }
            ],
            "fieldConfig": {
              "defaults": {
                "unit": "s"
              }
            },
            "gridPos": {"h": 8, "w": 6, "x": 12, "y": 0}
          },
          {
            "id": 4,
            "title": "Active Pods",
            "type": "stat",
            "targets": [
              {
                "expr": "count(up{namespace=\"$NAMESPACE\"} == 1)",
                "format": "time_series",
                "legendFormat": "Healthy Pods"
              }
            ],
            "gridPos": {"h": 8, "w": 6, "x": 18, "y": 0}
          }
        ],
        "time": {"from": "now-1h", "to": "now"},
        "refresh": "30s"
      }
    }
EOF
    
    echo -e "${GREEN}✅ Grafana dashboards configured${NC}"
}

# Function to configure Jaeger tracing
configure_jaeger_tracing() {
    echo -e "${BLUE}🔍 Configuring Jaeger tracing${NC}"
    
    # Wait for Jaeger to be ready
    echo -e "${YELLOW}⏳ Waiting for Jaeger to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment/jaeger -n "$MONITORING_NAMESPACE" || true
    
    # Configure Istio to send traces to Jaeger (if Istio is installed)
    if kubectl get namespace istio-system >/dev/null 2>&1; then
        echo -e "${YELLOW}🕸️  Configuring Istio tracing${NC}"
        kubectl apply -f - <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: tracing-config
  namespace: istio-system
spec:
  meshConfig:
    extensionProviders:
    - name: jaeger
      envoyExtAuthzHttp:
        service: jaeger.${MONITORING_NAMESPACE}.svc.cluster.local
        port: 14268
    defaultProviders:
      tracing:
      - jaeger
EOF
    fi
    
    echo -e "${GREEN}✅ Jaeger tracing configured${NC}"
}

# Function to verify monitoring deployment
verify_monitoring_deployment() {
    echo -e "${BLUE}🔍 Verifying monitoring deployment${NC}"
    
    # Check pod status
    echo -e "${YELLOW}📋 Monitoring pod status:${NC}"
    kubectl get pods -n "$MONITORING_NAMESPACE" -o wide
    
    # Check service status
    echo -e "${YELLOW}🌐 Monitoring service status:${NC}"
    kubectl get services -n "$MONITORING_NAMESPACE"
    
    # Wait for key components to be ready
    echo -e "${YELLOW}⏳ Waiting for monitoring components to be ready...${NC}"
    kubectl wait --for=condition=available --timeout=300s deployment --all -n "$MONITORING_NAMESPACE" || true
    
    echo -e "${GREEN}✅ Monitoring deployment verification complete${NC}"
}

# Function to setup port forwarding for monitoring services
setup_monitoring_access() {
    echo -e "${BLUE}🌐 Setting up monitoring access${NC}"
    
    echo -e "${YELLOW}To access monitoring services, run these commands in separate terminals:${NC}"
    echo -e "Prometheus:  kubectl port-forward -n $MONITORING_NAMESPACE service/prometheus-kube-prometheus-prometheus 9090:9090"
    echo -e "Grafana:     kubectl port-forward -n $MONITORING_NAMESPACE service/prometheus-grafana 3001:80"
    echo -e "Jaeger:      kubectl port-forward -n $MONITORING_NAMESPACE service/jaeger-query 16686:16686"
    echo -e "AlertManager: kubectl port-forward -n $MONITORING_NAMESPACE service/prometheus-kube-prometheus-alertmanager 9093:9093"
    echo -e ""
    echo -e "${BLUE}Default Grafana credentials: admin/admin${NC}"
    echo -e ""
    
    # Optional: Start port forwarding automatically
    read -p "Start port forwarding for monitoring services automatically? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}🚀 Starting port forwarding...${NC}"
        echo -e "${YELLOW}Press Ctrl+C to stop port forwarding${NC}"
        
        # Start port forwarding in background
        kubectl port-forward -n "$MONITORING_NAMESPACE" service/prometheus-grafana 3001:80 &
        GRAFANA_PID=$!
        kubectl port-forward -n "$MONITORING_NAMESPACE" service/prometheus-kube-prometheus-prometheus 9090:9090 &
        PROMETHEUS_PID=$!
        kubectl port-forward -n "$MONITORING_NAMESPACE" service/jaeger-query 16686:16686 &
        JAEGER_PID=$!
        
        echo -e "${GREEN}✅ Port forwarding started:${NC}"
        echo -e "   Grafana: http://localhost:3001 (admin/admin)"
        echo -e "   Prometheus: http://localhost:9090"
        echo -e "   Jaeger: http://localhost:16686"
        
        # Wait for user to stop
        trap "kill $GRAFANA_PID $PROMETHEUS_PID $JAEGER_PID 2>/dev/null; exit" INT
        wait
    fi
}

# Function to display monitoring information
display_monitoring_info() {
    echo -e "${GREEN}🎉 PyAirtable Monitoring Stack Deployment Complete!${NC}"
    echo -e ""
    echo -e "${BLUE}📊 Monitoring Components Deployed:${NC}"
    echo -e "• Prometheus - Metrics collection and alerting"
    echo -e "• Grafana - Metrics visualization and dashboards"
    echo -e "• Jaeger - Distributed tracing"
    echo -e "• AlertManager - Alert routing and notification"
    echo -e ""
    echo -e "${BLUE}🔧 Management Commands:${NC}"
    echo -e "View pods:       kubectl get pods -n $MONITORING_NAMESPACE"
    echo -e "View services:   kubectl get services -n $MONITORING_NAMESPACE"
    echo -e "View logs:       kubectl logs -f deployment/DEPLOYMENT_NAME -n $MONITORING_NAMESPACE"
    echo -e ""
    echo -e "${BLUE}🧹 Cleanup:${NC}"
    echo -e "Remove monitoring: helm uninstall prometheus jaeger -n $MONITORING_NAMESPACE"
    echo -e "Remove namespace:  kubectl delete namespace $MONITORING_NAMESPACE"
}

# Main execution function
main() {
    echo -e "${BLUE}Starting monitoring deployment with the following configuration:${NC}"
    echo -e "  Application Namespace: $NAMESPACE"
    echo -e "  Monitoring Namespace: $MONITORING_NAMESPACE"
    echo -e "  Cluster Type: $CLUSTER_TYPE"
    echo -e ""
    
    # Check if user wants to continue
    read -p "Continue with monitoring deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Monitoring deployment cancelled${NC}"
        exit 0
    fi
    
    check_prerequisites
    create_monitoring_namespace
    
    # Choose deployment method
    echo -e "${BLUE}📦 Choose deployment method:${NC}"
    echo -e "1. Helm (recommended) - Full-featured monitoring stack"
    echo -e "2. Manifests - Basic monitoring components"
    echo ""
    read -p "Select deployment method (1-2): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            deploy_monitoring_helm
            configure_service_monitors
            setup_grafana_dashboards
            ;;
        2)
            deploy_monitoring_manifests
            ;;
        *)
            echo -e "${RED}Invalid option, using Helm deployment${NC}"
            deploy_monitoring_helm
            configure_service_monitors
            setup_grafana_dashboards
            ;;
    esac
    
    configure_jaeger_tracing
    verify_monitoring_deployment
    setup_monitoring_access
    display_monitoring_info
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --monitoring-namespace)
            MONITORING_NAMESPACE="$2"
            shift 2
            ;;
        --cluster-type)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --namespace NAMESPACE              Target application namespace (default: pyairtable)"
            echo "  --monitoring-namespace NAMESPACE   Monitoring namespace (default: pyairtable-monitoring)"
            echo "  --cluster-type TYPE                Cluster type: minikube or kind (default: minikube)"
            echo "  --help                            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"