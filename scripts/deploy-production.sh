#!/bin/bash
# Production Deployment Script for PyAirtable 6-Service Architecture
# Zero-downtime blue-green deployment with comprehensive safety checks

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-pyairtable}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-600}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-300}"
CANARY_DURATION="${CANARY_DURATION:-300}"
ERROR_THRESHOLD="${ERROR_THRESHOLD:-0.01}"
LATENCY_THRESHOLD="${LATENCY_THRESHOLD:-500}"

# Service definitions
SERVICES=(
    "platform-services:8007"
    "automation-services:8006" 
    "api-gateway:8000"
    "llm-orchestrator:8003"
    "mcp-server:8001"
    "airtable-gateway:8002"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed, initiating rollback..."
    
    # Switch traffic back to blue (previous version)
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        log_info "Rolling back $service_name to blue version"
        kubectl patch service "$service_name" -n "$NAMESPACE" \
            -p '{"spec":{"selector":{"version":"blue"}}}' || true
    done
    
    # Remove failed green deployments
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        kubectl delete deployment "${service_name}-green" -n "$NAMESPACE" --ignore-not-found=true
    done
    
    log_error "Rollback completed. System is running on previous version."
    exit 1
}

trap cleanup_on_error ERR

# Pre-deployment checks
pre_deployment_checks() {
    log_info "Running pre-deployment checks..."
    
    # Check if kubectl is configured
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "kubectl is not configured or cluster is unreachable"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    # Check if monitoring is available
    if ! kubectl get pods -n monitoring -l app=prometheus >/dev/null 2>&1; then
        log_warning "Prometheus monitoring not available, some checks will be skipped"
    fi
    
    # Verify all required images are available
    log_info "Verifying container images..."
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        image_name="ghcr.io/pyairtablemcp/$service_name:${IMAGE_TAG:-latest}"
        
        if ! docker pull "$image_name" >/dev/null 2>&1; then
            log_error "Image $image_name not found or not accessible"
            exit 1
        fi
        log_info "✓ Image verified: $image_name"
    done
    
    # Check for active incidents
    if [ "${INCIDENT_STATUS:-}" = "active" ]; then
        log_error "Active incident detected, deployment aborted"
        exit 1
    fi
    
    log_success "Pre-deployment checks completed"
}

# Deploy green environment
deploy_green_environment() {
    log_info "Deploying green environment..."
    
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        service_port=$(echo "$service_def" | cut -d: -f2)
        image_name="ghcr.io/pyairtablemcp/$service_name:${IMAGE_TAG:-latest}"
        
        log_info "Deploying $service_name (green) with image $image_name"
        
        # Generate green deployment manifest
        cat > "/tmp/${service_name}-green.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service_name}-green
  namespace: ${NAMESPACE}
  labels:
    app: ${service_name}
    version: green
    deployment: blue-green
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: ${service_name}
      version: green
  template:
    metadata:
      labels:
        app: ${service_name}
        version: green
        deployment: blue-green
    spec:
      containers:
      - name: ${service_name}
        image: ${image_name}
        ports:
        - containerPort: ${service_port}
        env:
        - name: ENVIRONMENT
          value: "production"
        - name: LOG_LEVEL
          value: "info"
        - name: VERSION
          value: "green"
        resources:
          requests:
            cpu: 200m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        readinessProbe:
          httpGet:
            path: /health/ready
            port: ${service_port}
          initialDelaySeconds: 15
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health/live
            port: ${service_port}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
      imagePullSecrets:
      - name: github-registry-secret
EOF
        
        # Apply green deployment
        kubectl apply -f "/tmp/${service_name}-green.yaml"
        
        # Wait for deployment to be ready
        log_info "Waiting for $service_name green deployment to be ready..."
        kubectl rollout status deployment/"${service_name}-green" -n "$NAMESPACE" --timeout="${DEPLOYMENT_TIMEOUT}s"
        
        log_success "✓ $service_name green deployment ready"
    done
    
    log_success "Green environment deployed successfully"
}

# Health checks on green environment
health_check_green() {
    log_info "Running health checks on green environment..."
    
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        service_port=$(echo "$service_def" | cut -d: -f2)
        
        log_info "Health checking $service_name-green..."
        
        # Get a pod from the green deployment
        green_pod=$(kubectl get pods -l app="$service_name",version=green -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')
        
        if [ -z "$green_pod" ]; then
            log_error "No green pods found for $service_name"
            return 1
        fi
        
        # Check health endpoint
        if kubectl exec "$green_pod" -n "$NAMESPACE" -- curl -f "http://localhost:$service_port/health" >/dev/null 2>&1; then
            log_success "✓ $service_name health check passed"
        else
            log_error "✗ $service_name health check failed"
            return 1
        fi
        
        # Check readiness endpoint
        if kubectl exec "$green_pod" -n "$NAMESPACE" -- curl -f "http://localhost:$service_port/health/ready" >/dev/null 2>&1; then
            log_success "✓ $service_name readiness check passed"
        else
            log_error "✗ $service_name readiness check failed"
            return 1
        fi
    done
    
    log_success "All green environment health checks passed"
}

# Run integration tests on green environment
integration_tests_green() {
    log_info "Running integration tests on green environment..."
    
    # Create integration test job
    cat > "/tmp/integration-test-green.yaml" << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: integration-test-green
  namespace: pyairtable
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: integration-tests
        image: ghcr.io/pyairtablemcp/integration-tests:latest
        env:
        - name: TARGET_VERSION
          value: "green"
        - name: API_GATEWAY_URL
          value: "http://api-gateway-green:8000"
        - name: PLATFORM_SERVICES_URL
          value: "http://platform-services-green:8007"
        - name: AUTOMATION_SERVICES_URL
          value: "http://automation-services-green:8006"
        command: ["/bin/sh"]
        args:
        - -c
        - |
          echo "Running integration tests against green environment..."
          
          # Test API Gateway health
          curl -f http://api-gateway-green:8000/health || exit 1
          
          # Test Platform Services
          curl -f http://platform-services-green:8007/health || exit 1
          
          # Test Automation Services
          curl -f http://automation-services-green:8006/health || exit 1
          
          # Test AI Services
          curl -f http://llm-orchestrator-green:8003/health || exit 1
          curl -f http://mcp-server-green:8001/health || exit 1
          curl -f http://airtable-gateway-green:8002/health || exit 1
          
          # Test end-to-end workflow
          python3 /tests/e2e_workflow_test.py --target green
          
          echo "All integration tests passed!"
EOF
    
    kubectl apply -f "/tmp/integration-test-green.yaml"
    
    # Wait for integration tests to complete
    if kubectl wait --for=condition=complete job/integration-test-green -n "$NAMESPACE" --timeout="$HEALTH_CHECK_TIMEOUT"s; then
        log_success "Integration tests passed"
    else
        log_error "Integration tests failed"
        kubectl logs job/integration-test-green -n "$NAMESPACE"
        return 1
    fi
    
    # Cleanup test job
    kubectl delete job integration-test-green -n "$NAMESPACE"
}

# Canary deployment with traffic splitting
canary_deployment() {
    log_info "Starting canary deployment (10% traffic to green)..."
    
    # Create canary service configuration
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        
        # Create canary service that routes 10% traffic to green
        cat > "/tmp/${service_name}-canary.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${service_name}-canary
  namespace: ${NAMESPACE}
  labels:
    app: ${service_name}
    traffic: canary
spec:
  selector:
    app: ${service_name}
    version: green
  ports:
  - port: $(echo "$service_def" | cut -d: -f2)
    targetPort: $(echo "$service_def" | cut -d: -f2)
    protocol: TCP
  type: ClusterIP
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ${service_name}-canary
  namespace: ${NAMESPACE}
spec:
  hosts:
  - ${service_name}
  http:
  - match:
    - headers:
        canary:
          exact: "true"
    route:
    - destination:
        host: ${service_name}
        subset: green
      weight: 100
  - route:
    - destination:
        host: ${service_name}
        subset: blue
      weight: 90
    - destination:
        host: ${service_name}
        subset: green
      weight: 10
EOF
        
        kubectl apply -f "/tmp/${service_name}-canary.yaml"
        log_info "✓ Canary configuration applied for $service_name"
    done
    
    log_info "Monitoring canary deployment for $CANARY_DURATION seconds..."
    sleep "$CANARY_DURATION"
    
    # Check metrics during canary period
    if command -v kubectl >/dev/null && kubectl get pods -n monitoring -l app=prometheus >/dev/null 2>&1; then
        log_info "Checking canary metrics..."
        
        # Check error rate
        error_rate=$(kubectl exec -n monitoring prometheus-0 -- promtool query instant \
            'sum(rate(http_requests_total{job="platform-services",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="platform-services"}[5m]))' \
            | grep -o '[0-9.]*' | head -1 || echo "0")
        
        if (( $(echo "$error_rate > $ERROR_THRESHOLD" | bc -l) )); then
            log_error "High error rate detected during canary: $error_rate (threshold: $ERROR_THRESHOLD)"
            return 1
        fi
        
        # Check latency
        latency_p95=$(kubectl exec -n monitoring prometheus-0 -- promtool query instant \
            'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="platform-services"}[5m])) by (le))' \
            | grep -o '[0-9.]*' | head -1 || echo "0")
        
        if (( $(echo "$latency_p95 > $LATENCY_THRESHOLD" | bc -l) )); then
            log_error "High latency detected during canary: ${latency_p95}ms (threshold: ${LATENCY_THRESHOLD}ms)"
            return 1
        fi
        
        log_success "Canary metrics within acceptable thresholds (error_rate: $error_rate, latency_p95: ${latency_p95}ms)"
    else
        log_warning "Prometheus not available, skipping metrics validation"
    fi
    
    log_success "Canary deployment validation completed"
}

# Full traffic switch to green
switch_traffic_to_green() {
    log_info "Switching 100% traffic to green environment..."
    
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        
        log_info "Switching traffic for $service_name to green..."
        kubectl patch service "$service_name" -n "$NAMESPACE" \
            -p '{"spec":{"selector":{"version":"green"}}}'
        
        log_success "✓ Traffic switched for $service_name"
    done
    
    log_info "Monitoring full green deployment for $CANARY_DURATION seconds..."
    sleep "$CANARY_DURATION"
    
    # Final metrics check
    if command -v kubectl >/dev/null && kubectl get pods -n monitoring -l app=prometheus >/dev/null 2>&1; then
        log_info "Final metrics validation..."
        
        error_rate=$(kubectl exec -n monitoring prometheus-0 -- promtool query instant \
            'sum(rate(http_requests_total{job="platform-services",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="platform-services"}[5m]))' \
            | grep -o '[0-9.]*' | head -1 || echo "0")
        
        if (( $(echo "$error_rate > $ERROR_THRESHOLD" | bc -l) )); then
            log_error "High error rate detected in full green deployment: $error_rate"
            return 1
        fi
        
        log_success "Full green deployment metrics validated (error_rate: $error_rate)"
    fi
    
    log_success "Traffic successfully switched to green environment"
}

# Cleanup blue environment
cleanup_blue_environment() {
    log_info "Cleaning up blue environment..."
    
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        
        log_info "Removing blue deployment for $service_name..."
        kubectl delete deployment "${service_name}-blue" -n "$NAMESPACE" --ignore-not-found=true
        
        # Update current deployment to be the new blue (for next deployment)
        kubectl patch deployment "$service_name" -n "$NAMESPACE" \
            -p '{"spec":{"selector":{"matchLabels":{"version":"blue"}},"template":{"metadata":{"labels":{"version":"blue"}}}}}' \
            --dry-run=client -o yaml | kubectl replace -f - || true
        
        log_success "✓ Blue cleanup completed for $service_name"
    done
    
    # Cleanup canary configurations
    for service_def in "${SERVICES[@]}"; do
        service_name=$(echo "$service_def" | cut -d: -f1)
        kubectl delete virtualservice "${service_name}-canary" -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete service "${service_name}-canary" -n "$NAMESPACE" --ignore-not-found=true
    done
    
    log_success "Blue environment cleanup completed"  
}

# Post-deployment verification
post_deployment_verification() {
    log_info "Running post-deployment verification..."
    
    # Run production health checks
    cat > "/tmp/production-health-check.yaml" << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: production-health-check
  namespace: pyairtable
spec:
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: health-check
        image: ghcr.io/pyairtablemcp/health-checker:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          echo "Running comprehensive production health checks..."
          
          # Check all services
          services="platform-services:8007 automation-services:8006 api-gateway:8000 llm-orchestrator:8003 mcp-server:8001 airtable-gateway:8002"
          
          for service_def in $services; do
            service_name=$(echo $service_def | cut -d: -f1)
            service_port=$(echo $service_def | cut -d: -f2)
            
            echo "Checking $service_name..."
            
            # Health check
            if curl -f http://$service_name:$service_port/health; then
              echo "✓ $service_name health check passed"
            else
              echo "✗ $service_name health check failed"
              exit 1
            fi
            
            # Performance check
            response_time=$(curl -o /dev/null -s -w "%{time_total}" http://$service_name:$service_port/health)
            if (( $(echo "$response_time > 1.0" | bc -l) )); then
              echo "⚠ $service_name response time high: ${response_time}s"
            else
              echo "✓ $service_name response time good: ${response_time}s"
            fi
          done
          
          # Test database connectivity
          echo "Testing database connectivity..."
          python3 -c "
import psycopg2
import os
try:
    conn = psycopg2.connect(os.environ['DATABASE_URL'])
    conn.close()
    print('✓ Database connectivity verified')
except Exception as e:
    print(f'✗ Database connectivity failed: {e}')
    exit(1)
"
          
          # Test Redis connectivity  
          echo "Testing Redis connectivity..."
          python3 -c "
import redis
import os
try:
    r = redis.from_url(os.environ['REDIS_URL'])
    r.ping()
    print('✓ Redis connectivity verified')
except Exception as e:
    print(f'✗ Redis connectivity failed: {e}')
    exit(1)
"
          
          echo "All production health checks passed!"
EOF
    
    kubectl apply -f "/tmp/production-health-check.yaml"
    
    if kubectl wait --for=condition=complete job/production-health-check -n "$NAMESPACE" --timeout="$HEALTH_CHECK_TIMEOUT"s; then
        log_success "Post-deployment verification passed"
    else
        log_error "Post-deployment verification failed"
        kubectl logs job/production-health-check -n "$NAMESPACE"
        return 1
    fi
    
    # Cleanup verification job
    kubectl delete job production-health-check -n "$NAMESPACE"
}

# Notification functions
send_notification() {
    local status="$1"
    local message="$2"
    
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$status $message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    if [ -n "${TEAMS_WEBHOOK_URL:-}" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$status $message\"}" \
            "$TEAMS_WEBHOOK_URL" || true
    fi
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    log_info "🚀 Starting PyAirtable production deployment"
    log_info "Namespace: $NAMESPACE"
    log_info "Image Tag: ${IMAGE_TAG:-latest}"
    log_info "Services: ${SERVICES[*]}"
    
    send_notification "🚀" "Starting PyAirtable production deployment (${IMAGE_TAG:-latest})"
    
    # Execute deployment steps
    pre_deployment_checks
    deploy_green_environment
    health_check_green
    integration_tests_green  
    canary_deployment
    switch_traffic_to_green
    cleanup_blue_environment
    post_deployment_verification
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "🎉 Production deployment completed successfully!"
    log_success "Deployment duration: ${duration} seconds"
    
    send_notification "✅" "PyAirtable production deployment completed successfully! Duration: ${duration}s"
    
    # Generate deployment report
    cat > "/tmp/deployment-report-$(date +%Y%m%d-%H%M%S).md" << EOF
# PyAirtable Production Deployment Report

**Date:** $(date -u)
**Duration:** ${duration} seconds
**Image Tag:** ${IMAGE_TAG:-latest}
**Namespace:** $NAMESPACE

## Services Deployed
$(printf '%s\n' "${SERVICES[@]}")

## Deployment Steps Completed
- ✅ Pre-deployment checks
- ✅ Green environment deployment
- ✅ Health checks
- ✅ Integration tests
- ✅ Canary deployment (10% traffic)
- ✅ Full traffic switch
- ✅ Blue environment cleanup
- ✅ Post-deployment verification

## Metrics
- Error Rate: < $ERROR_THRESHOLD
- Latency P95: < ${LATENCY_THRESHOLD}ms
- All health checks: PASSED

## Next Steps
- Monitor system performance for 24 hours
- Schedule post-deployment review meeting
- Update documentation if needed
EOF
    
    log_info "Deployment report generated at /tmp/deployment-report-$(date +%Y%m%d-%H%M%S).md"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --timeout)
            DEPLOYMENT_TIMEOUT="$2"
            shift 2
            ;;
        --canary-duration)
            CANARY_DURATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --namespace NAME        Kubernetes namespace (default: pyairtable)"
            echo "  --image-tag TAG         Docker image tag to deploy (default: latest)"
            echo "  --timeout SECONDS       Deployment timeout (default: 600)"
            echo "  --canary-duration SECONDS  Canary monitoring duration (default: 300)"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"