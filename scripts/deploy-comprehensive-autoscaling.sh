#!/bin/bash

# Comprehensive Autoscaling Deployment Script for PyAirtable
# This script deploys all autoscaling components in the correct order

set -euo pipefail

# Configuration
ENVIRONMENT=${ENVIRONMENT:-"dev"}
CLUSTER_NAME=${CLUSTER_NAME:-"pyairtable-cluster"}
AWS_REGION=${AWS_REGION:-"us-east-1"}
NAMESPACE=${NAMESPACE:-"pyairtable"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    for tool in kubectl helm aws; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
    
    # Check Kubernetes connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
    
    success "Prerequisites check passed"
}

# Create namespaces
create_namespaces() {
    log "Creating required namespaces..."
    
    local namespaces=(
        "pyairtable"
        "pyairtable-monitoring"
        "keda"
        "predictive-scaling"
        "cost-optimization"
        "kafka-system"
        "batch-processing"
    )
    
    for ns in "${namespaces[@]}"; do
        if ! kubectl get namespace "$ns" &> /dev/null; then
            kubectl create namespace "$ns"
            kubectl label namespace "$ns" istio-injection=enabled --overwrite
            log "Created namespace: $ns"
        else
            log "Namespace $ns already exists"
        fi
    done
    
    success "Namespaces created successfully"
}

# Install KEDA
install_keda() {
    log "Installing KEDA..."
    
    # Add KEDA Helm repository
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    
    # Install or upgrade KEDA
    helm upgrade --install keda kedacore/keda \
        --namespace keda \
        --create-namespace \
        --set prometheus.metricServer.enabled=true \
        --set prometheus.operator.enabled=true \
        --set operator.replicaCount=2 \
        --set metricsServer.replicaCount=2 \
        --wait \
        --timeout=300s
    
    # Wait for KEDA to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda
    kubectl wait --for=condition=available --timeout=300s deployment/keda-metrics-apiserver -n keda
    
    success "KEDA installed successfully"
}

# Install VPA
install_vpa() {
    log "Installing Vertical Pod Autoscaler..."
    
    # Check if VPA is already installed
    if kubectl get deployment vpa-recommender -n kube-system &> /dev/null; then
        log "VPA already installed"
        return
    fi
    
    # Install VPA
    kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vpa-release.yaml
    
    # Wait for VPA components to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/vpa-recommender -n kube-system
    kubectl wait --for=condition=available --timeout=300s deployment/vpa-updater -n kube-system
    kubectl wait --for=condition=available --timeout=300s deployment/vpa-admission-controller -n kube-system
    
    success "VPA installed successfully"
}

# Install Prometheus and Grafana
install_monitoring() {
    log "Installing monitoring stack..."
    
    # Add Prometheus community Helm repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Create monitoring values file
    cat > /tmp/monitoring-values.yaml << EOF
prometheus:
  prometheusSpec:
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    additionalScrapeConfigs:
    - job_name: 'keda-metrics'
      kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names:
          - keda
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_name]
        action: keep
        regex: keda-operator-metrics-service

grafana:
  adminPassword: $(openssl rand -base64 32)
  persistence:
    enabled: true
    storageClassName: gp2
    size: 10Gi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'autoscaling'
        orgId: 1
        folder: 'Autoscaling'
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/autoscaling

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: gp2
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
EOF
    
    # Install or upgrade monitoring stack
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace pyairtable-monitoring \
        --create-namespace \
        --values /tmp/monitoring-values.yaml \
        --wait \
        --timeout=600s
    
    success "Monitoring stack installed successfully"
}

# Deploy infrastructure autoscaling (Terraform)
deploy_infrastructure_autoscaling() {
    log "Deploying infrastructure autoscaling with Terraform..."
    
    cd infrastructure
    
    # Initialize Terraform
    terraform init
    
    # Plan the deployment
    terraform plan -var="environment=$ENVIRONMENT" -var="project_name=pyairtable" -out=tfplan
    
    # Apply the plan
    terraform apply tfplan
    
    cd ..
    
    success "Infrastructure autoscaling deployed successfully"
}

# Deploy application autoscaling configurations
deploy_application_autoscaling() {
    log "Deploying application autoscaling configurations..."
    
    # Deploy comprehensive event-driven autoscaling
    kubectl apply -f k8s/manifests/comprehensive-event-driven-autoscaling.yaml
    
    # Deploy predictive autoscaling
    kubectl apply -f k8s/manifests/predictive-autoscaling.yaml
    
    # Deploy cost-optimized autoscaling
    kubectl apply -f k8s/manifests/cost-optimized-autoscaling.yaml
    
    # Wait for deployments to be ready
    log "Waiting for autoscaling components to be ready..."
    
    kubectl wait --for=condition=available --timeout=300s deployment/predictive-scaling-engine -n predictive-scaling
    kubectl wait --for=condition=available --timeout=300s deployment/cost-optimization-controller -n cost-optimization
    
    success "Application autoscaling configurations deployed successfully"
}

# Deploy monitoring and alerting
deploy_monitoring_alerting() {
    log "Deploying autoscaling monitoring and alerting..."
    
    # Apply monitoring configuration
    kubectl apply -f monitoring/autoscaling-monitoring.yml
    
    # Wait for monitoring components
    kubectl wait --for=condition=available --timeout=300s deployment/prometheus-operator-kube-p-operator -n pyairtable-monitoring
    
    success "Monitoring and alerting deployed successfully"
}

# Configure AWS resources
configure_aws_resources() {
    log "Configuring AWS resources for autoscaling..."
    
    # Create S3 bucket for ML models
    aws s3 mb s3://pyairtable-ml-models-$ENVIRONMENT --region $AWS_REGION || true
    
    # Create SNS topic for cost alerts
    aws sns create-topic --name pyairtable-cost-alerts-$ENVIRONMENT --region $AWS_REGION || true
    
    # Create CloudWatch dashboard
    cat > /tmp/dashboard.json << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/EKS", "cluster_node_count", "ClusterName", "CLUSTER_NAME" ],
                    [ "AWS/EKS", "cluster_failed_node_count", "ClusterName", "CLUSTER_NAME" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "AWS_REGION",
                "title": "EKS Cluster Nodes"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "pyairtable-ENVIRONMENT-serverless" ],
                    [ "AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "pyairtable-ENVIRONMENT-serverless" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "AWS_REGION",
                "title": "Aurora Serverless Metrics"
            }
        }
    ]
}
EOF
    
    # Replace placeholders and create dashboard
    sed -i "s/CLUSTER_NAME/$CLUSTER_NAME/g" /tmp/dashboard.json
    sed -i "s/AWS_REGION/$AWS_REGION/g" /tmp/dashboard.json
    sed -i "s/ENVIRONMENT/$ENVIRONMENT/g" /tmp/dashboard.json
    
    aws cloudwatch put-dashboard \
        --dashboard-name "PyAirtable-Autoscaling-$ENVIRONMENT" \
        --dashboard-body file:///tmp/dashboard.json \
        --region $AWS_REGION
    
    success "AWS resources configured successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating autoscaling deployment..."
    
    # Check HPA
    local hpa_count=$(kubectl get hpa --all-namespaces --no-headers | wc -l)
    log "Found $hpa_count HPAs"
    
    # Check KEDA ScaledObjects
    local keda_count=$(kubectl get scaledobjects --all-namespaces --no-headers | wc -l)
    log "Found $keda_count KEDA ScaledObjects"
    
    # Check VPA
    local vpa_count=$(kubectl get vpa --all-namespaces --no-headers | wc -l)
    log "Found $vpa_count VPAs"
    
    # Check custom components
    kubectl get deployment predictive-scaling-engine -n predictive-scaling || warning "Predictive scaling engine not found"
    kubectl get deployment cost-optimization-controller -n cost-optimization || warning "Cost optimization controller not found"
    
    # Check CronJobs for scheduled scaling
    local cronjob_count=$(kubectl get cronjobs -n pyairtable --no-headers | wc -l)
    log "Found $cronjob_count scheduled scaling CronJobs"
    
    # Test metrics endpoints
    log "Testing metrics endpoints..."
    kubectl port-forward -n predictive-scaling deployment/predictive-scaling-engine 8080:8080 &
    local port_forward_pid=$!
    sleep 5
    
    if curl -s http://localhost:8080/metrics > /dev/null; then
        success "Predictive scaling metrics endpoint accessible"
    else
        warning "Predictive scaling metrics endpoint not accessible"
    fi
    
    kill $port_forward_pid 2>/dev/null || true
    
    success "Deployment validation completed"
}

# Generate deployment report
generate_report() {
    log "Generating deployment report..."
    
    local report_file="autoscaling-deployment-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
PyAirtable Comprehensive Autoscaling Deployment Report
Generated: $(date)
Environment: $ENVIRONMENT
Cluster: $CLUSTER_NAME
Region: $AWS_REGION

=== DEPLOYMENT SUMMARY ===
✓ KEDA installed and configured
✓ VPA installed and configured
✓ Prometheus and Grafana monitoring stack deployed
✓ Infrastructure autoscaling (Terraform) deployed
✓ Application autoscaling configurations applied
✓ Predictive scaling engine deployed
✓ Cost optimization controller deployed
✓ Monitoring and alerting configured
✓ AWS resources configured

=== AUTOSCALING COMPONENTS ===
HPAs: $(kubectl get hpa --all-namespaces --no-headers | wc -l)
KEDA ScaledObjects: $(kubectl get scaledobjects --all-namespaces --no-headers | wc -l)
VPAs: $(kubectl get vpa --all-namespaces --no-headers | wc -l)
Scheduled Scaling Jobs: $(kubectl get cronjobs -n pyairtable --no-headers | wc -l)

=== COST OPTIMIZATION ===
- Spot instance support enabled
- Scheduled scaling for business hours
- Budget monitoring and alerts configured
- Resource right-sizing recommendations enabled

=== PREDICTIVE SCALING ===
- ML-based forecasting engine deployed
- Historical data collection configured
- Model training scheduled daily
- Prediction accuracy monitoring enabled

=== NEXT STEPS ===
1. Review and adjust scaling policies in:
   - k8s/manifests/comprehensive-event-driven-autoscaling.yaml
   - k8s/manifests/cost-optimized-autoscaling.yaml

2. Configure notification channels:
   - Update Slack webhook URLs in AlertManager
   - Configure email recipients for cost alerts

3. Monitor and tune:
   - Review Grafana dashboards
   - Adjust scaling thresholds based on usage patterns
   - Monitor cost metrics and optimize

4. Test emergency procedures:
   - Practice scaling during high load
   - Test emergency cost reduction procedures
   - Validate disaster recovery procedures

=== USEFUL COMMANDS ===
# Check autoscaling status
kubectl get hpa,scaledobjects,vpa --all-namespaces

# View scaling events
kubectl get events --all-namespaces --sort-by=.lastTimestamp | grep -E "(Scaled|Created|Deleted)"

# Check cost optimization metrics
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- curl -s localhost:8080/metrics

# View predictive scaling predictions
kubectl logs -n predictive-scaling deployment/predictive-scaling-engine

# Monitor resource usage
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=cpu

=== TROUBLESHOOTING ===
Refer to the operational runbook at:
docs/autoscaling-operations-runbook.md

For issues, check logs:
kubectl logs -n keda deployment/keda-operator
kubectl logs -n predictive-scaling deployment/predictive-scaling-engine
kubectl logs -n cost-optimization deployment/cost-optimization-controller

EOF
    
    success "Deployment report generated: $report_file"
    cat "$report_file"
}

# Main deployment function
main() {
    echo "=================================================="
    echo "PyAirtable Comprehensive Autoscaling Deployment"
    echo "=================================================="
    echo "Environment: $ENVIRONMENT"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo "Namespace: $NAMESPACE"
    echo "=================================================="
    
    check_prerequisites
    create_namespaces
    install_keda
    install_vpa
    install_monitoring
    deploy_infrastructure_autoscaling
    deploy_application_autoscaling
    deploy_monitoring_alerting
    configure_aws_resources
    validate_deployment
    generate_report
    
    success "PyAirtable comprehensive autoscaling deployment completed successfully!"
    
    echo ""
    echo "🎉 Deployment Complete! 🎉"
    echo ""
    echo "Access your monitoring dashboards:"
    echo "Grafana: kubectl port-forward -n pyairtable-monitoring svc/prometheus-grafana 3000:80"
    echo "Prometheus: kubectl port-forward -n pyairtable-monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
    echo ""
    echo "Refer to docs/autoscaling-operations-runbook.md for operational procedures."
}

# Handle script interruption
trap 'error "Deployment interrupted. Check logs and retry."' ERR

# Run main function
main "$@"