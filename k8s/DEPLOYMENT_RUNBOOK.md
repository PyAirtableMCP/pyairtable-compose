# PyAirtable Kubernetes Deployment Runbook

## Overview

This runbook provides step-by-step instructions for deploying the PyAirtable microservices stack to Kubernetes with production-ready configurations including security policies, monitoring, and service mesh capabilities.

## Architecture

The PyAirtable stack consists of:

### Go Services (Core Performance Services)
- **API Gateway** (port 8000) - High-performance reverse proxy and rate limiting
- **Platform Services** (port 8001) - Authentication, user management, and analytics
- **Automation Services** (port 8002) - File processing and workflow automation

### Python Services (AI/ML and Business Logic)
- **LLM Orchestrator** (port 8003) - Gemini 2.5 Flash integration
- **MCP Server** (port 8001) - Protocol implementation
- **Airtable Gateway** (port 8002) - Direct Airtable API integration
- **Frontend** (port 3000) - Next.js web interface

### Infrastructure Services
- **PostgreSQL** (port 5432) - Primary database
- **Redis** (port 6379) - Caching and session storage

### Observability Stack
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Metrics visualization
- **Jaeger** - Distributed tracing
- **Istio** - Service mesh (optional)

## Prerequisites

### Required Tools
- Docker Desktop (running)
- kubectl (Kubernetes CLI)
- Helm (Package manager)
- Minikube or Kind (local clusters)

### Optional Tools
- istioctl (for service mesh)
- psql (PostgreSQL client)
- redis-cli (Redis client)

## Quick Start Guide

### 1. Prepare Local Environment

```bash
# Start Minikube with sufficient resources
minikube start --memory=4000 --cpus=3 --disk-size=20g

# OR start Kind cluster
kind create cluster --name pyairtable --config k8s/kind-config.yaml

# Verify cluster is ready
kubectl cluster-info
```

### 2. Deploy Core Services

```bash
# Navigate to deployment directory
cd k8s

# Deploy core services (builds images, deploys infrastructure and services)
./scripts/deploy-core-services.sh

# This will:
# - Build Docker images for Go services
# - Deploy PostgreSQL and Redis
# - Deploy all application services
# - Setup security policies
# - Configure health checks
```

### 3. Verify Deployment

```bash
# Run health checks
./scripts/health-check.sh

# Run end-to-end tests
./scripts/e2e-test.sh
```

### 4. Setup Monitoring (Optional)

```bash
# Deploy monitoring stack
./scripts/deploy-monitoring.sh

# Access monitoring dashboards
kubectl port-forward -n pyairtable-monitoring service/prometheus-grafana 3001:80
# Visit http://localhost:3001 (admin/admin)
```

### 5. Setup Service Mesh (Optional)

```bash
# Apply Istio configuration (if Istio is installed)
kubectl apply -f manifests/istio-service-mesh.yaml
```

## Detailed Deployment Steps

### Step 1: Infrastructure Setup

#### 1.1 Cluster Preparation
```bash
# For Minikube
minikube start --memory=4000 --cpus=3 --disk-size=20g --addons=ingress,registry,metrics-server

# For Kind
kind create cluster --name pyairtable
```

#### 1.2 Security Policies
```bash
# Apply security policies first
kubectl apply -f manifests/security-policies.yaml

# This creates:
# - Namespace with Pod Security Standards
# - Service accounts and RBAC
# - Network policies
# - Resource quotas and limits
# - Pod disruption budgets
```

### Step 2: Infrastructure Services

#### 2.1 Database Deployment
```bash
# Deploy PostgreSQL with Helm
helm upgrade --install postgresql-dev \
    oci://registry-1.docker.io/bitnamicharts/postgresql \
    --namespace pyairtable \
    --set auth.postgresPassword="secure-password" \
    --set auth.database="pyairtable" \
    --set primary.persistence.enabled=true \
    --set primary.persistence.size="5Gi"
```

#### 2.2 Cache Deployment
```bash
# Deploy Redis with Helm
helm upgrade --install redis-dev \
    oci://registry-1.docker.io/bitnamicharts/redis \
    --namespace pyairtable \
    --set auth.password="secure-password" \
    --set master.persistence.enabled=true \
    --set master.persistence.size="1Gi"
```

### Step 3: Application Services

#### 3.1 Build Docker Images
```bash
# Build Go services
cd go-services
for service in api-gateway platform-services automation-services; do
    docker build -t localhost:5000/pyairtable-${service}:latest \
        -f cmd/${service}/Dockerfile .
done

# Build Python services (if needed)
cd ../llm-orchestrator-py
docker build -t localhost:5000/pyairtable-llm-orchestrator:latest .
```

#### 3.2 Deploy Services
```bash
# Option 1: Using enhanced manifests
kubectl apply -f manifests/enhanced-deployments.yaml

# Option 2: Using Helm charts
helm upgrade --install pyairtable-dev ./helm/pyairtable-stack \
    --namespace pyairtable \
    --values helm/pyairtable-stack/values-dev.yaml
```

### Step 4: Service Mesh (Optional)

#### 4.1 Install Istio
```bash
# Download and install Istio
curl -L https://istio.io/downloadIstio | sh -
export PATH="$PWD/istio-*/bin:$PATH"
istioctl install --set values.defaultRevision=default -y

# Enable sidecar injection
kubectl label namespace pyairtable istio-injection=enabled
```

#### 4.2 Configure Service Mesh
```bash
# Apply Istio configurations
kubectl apply -f manifests/istio-service-mesh.yaml

# This configures:
# - Gateway for external access
# - Virtual services for routing
# - Destination rules for load balancing
# - Security policies (mTLS, authorization)
# - Telemetry configuration
```

### Step 5: Monitoring Stack

#### 5.1 Deploy Monitoring
```bash
# Deploy using Helm (recommended)
./scripts/deploy-monitoring.sh

# OR deploy using manifests
kubectl apply -f manifests/monitoring-stack.yaml
```

#### 5.2 Access Monitoring Dashboards
```bash
# Grafana
kubectl port-forward -n pyairtable-monitoring service/prometheus-grafana 3001:80

# Prometheus
kubectl port-forward -n pyairtable-monitoring service/prometheus-kube-prometheus-prometheus 9090:9090

# Jaeger
kubectl port-forward -n pyairtable-monitoring service/jaeger-query 16686:16686
```

## Configuration Management

### Environment Variables

Core services use these key environment variables:

```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/dbname

# Redis
REDIS_URL=redis://host:6379
REDIS_PASSWORD=secure-password

# Authentication
JWT_SECRET=64-character-secure-secret
API_KEY=secure-api-key

# External APIs
GEMINI_API_KEY=your-gemini-key
AIRTABLE_TOKEN=your-airtable-token
AIRTABLE_BASE=your-base-id
```

### Secrets Management

Secrets are managed through Kubernetes Secrets:

```bash
# Create secrets
kubectl create secret generic pyairtable-secrets \
    --namespace=pyairtable \
    --from-literal=jwt-secret="your-jwt-secret" \
    --from-literal=api-key="your-api-key" \
    --from-literal=database-url="postgresql://..." \
    --from-literal=redis-password="your-redis-password" \
    --from-literal=gemini-api-key="your-gemini-key" \
    --from-literal=airtable-token="your-airtable-token"
```

### ConfigMap Configuration

Application configuration through ConfigMaps:

```bash
kubectl create configmap pyairtable-config \
    --namespace=pyairtable \
    --from-literal=environment="production" \
    --from-literal=log-level="info" \
    --from-literal=metrics-enabled="true"
```

## Health Checks and Monitoring

### Health Check Endpoints

All services expose these endpoints:
- `/health` - Basic health check
- `/ready` - Readiness probe
- `/metrics` - Prometheus metrics

### Health Check Script

```bash
# Comprehensive health check
./scripts/health-check.sh pyairtable

# This checks:
# - Pod status
# - Service endpoints
# - HTTP health endpoints
# - Database connectivity
# - Resource usage
```

### Monitoring Queries

Key Prometheus queries for monitoring:

```promql
# Request rate
sum(rate(http_requests_total[5m])) by (service)

# Error rate
sum(rate(http_requests_total{code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Response time (95th percentile)
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# Pod memory usage
sum(container_memory_usage_bytes{namespace="pyairtable"}) by (pod)
```

## Scaling and Performance

### Horizontal Pod Autoscaling

HPA is configured for key services:

```yaml
# Example HPA configuration
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Manual Scaling

```bash
# Scale a specific service
kubectl scale deployment api-gateway --replicas=5 -n pyairtable

# Scale all services
kubectl scale deployment --all --replicas=3 -n pyairtable
```

### Performance Tuning

Key performance settings:

```yaml
# Resource requests and limits
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Connection pooling (application-level)
DB_MAX_OPEN_CONNS=25
DB_MAX_IDLE_CONNS=5
DB_CONN_MAX_LIFETIME=300
```

## Security Best Practices

### Pod Security

All pods run with security contexts:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

### Network Security

Network policies restrict inter-pod communication:

```yaml
# Example: Allow API Gateway to backend services only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-gateway-policy
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: api-gateway
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/component: platform-services
    ports:
    - protocol: TCP
      port: 8001
```

### Secrets Management

- Use Kubernetes Secrets for sensitive data
- Enable encryption at rest
- Rotate secrets regularly
- Use external secret management in production

## Troubleshooting

### Common Issues

#### 1. Pod Not Starting
```bash
# Check pod status
kubectl describe pod <pod-name> -n pyairtable

# Check logs
kubectl logs <pod-name> -n pyairtable

# Check events
kubectl get events -n pyairtable --sort-by='.lastTimestamp'
```

#### 2. Service Connectivity Issues
```bash
# Test service connectivity
kubectl exec -it <pod-name> -n pyairtable -- curl http://service-name:port/health

# Check service endpoints
kubectl get endpoints -n pyairtable

# Test DNS resolution
kubectl exec -it <pod-name> -n pyairtable -- nslookup service-name.pyairtable.svc.cluster.local
```

#### 3. Database Connection Issues
```bash
# Check database pod
kubectl logs deployment/postgresql-dev -n pyairtable

# Test connection
kubectl port-forward service/postgresql-dev 5432:5432 -n pyairtable
psql -h localhost -U postgres -d pyairtable
```

#### 4. High Resource Usage
```bash
# Check resource usage
kubectl top pods -n pyairtable

# Check resource limits
kubectl describe pod <pod-name> -n pyairtable | grep -A 5 "Limits"

# Check HPA status
kubectl get hpa -n pyairtable
```

### Log Analysis

```bash
# View logs for all services
kubectl logs -f deployment/api-gateway -n pyairtable

# View logs with specific labels
kubectl logs -l app.kubernetes.io/component=platform-services -n pyairtable

# Export logs for analysis
kubectl logs deployment/api-gateway -n pyairtable > api-gateway.log
```

### Performance Debugging

```bash
# Get detailed pod metrics
kubectl describe pod <pod-name> -n pyairtable

# Check resource quotas
kubectl describe resourcequota -n pyairtable

# Monitor resource usage in real-time
watch kubectl top pods -n pyairtable
```

## Disaster Recovery

### Backup Procedures

#### Database Backup
```bash
# Create database backup
kubectl exec -it deployment/postgresql-dev -n pyairtable -- \
    pg_dump -U postgres pyairtable > backup-$(date +%Y%m%d).sql

# Schedule regular backups with CronJob
kubectl apply -f manifests/backup-cronjob.yaml
```

#### Configuration Backup
```bash
# Backup all configurations
kubectl get all,configmap,secret,pvc -n pyairtable -o yaml > pyairtable-backup.yaml

# Backup Helm values
helm get values pyairtable-dev -n pyairtable > values-backup.yaml
```

### Recovery Procedures

#### Service Recovery
```bash
# Restart all services
kubectl rollout restart deployment -n pyairtable

# Restore from backup
kubectl apply -f pyairtable-backup.yaml

# Restore database
kubectl exec -i deployment/postgresql-dev -n pyairtable -- \
    psql -U postgres pyairtable < backup-20240801.sql
```

## Cleanup

### Remove Services Only
```bash
# Use cleanup script
./scripts/cleanup.sh pyairtable

# OR manually remove
helm uninstall pyairtable-dev postgresql-dev redis-dev -n pyairtable
kubectl delete namespace pyairtable
```

### Remove Everything Including Cluster
```bash
# For Minikube
minikube delete

# For Kind
kind delete cluster --name pyairtable
```

## Production Considerations

### Resource Planning

Minimum resource requirements:
- CPU: 4 vCPU
- Memory: 8GB RAM
- Storage: 50GB
- Network: 1Gbps

Production resource requirements:
- CPU: 8+ vCPU
- Memory: 16+ GB RAM
- Storage: 100+ GB (with fast SSD)
- Network: 10Gbps

### High Availability

For production deployment:
- Run multiple replicas (minimum 3)
- Use Pod Disruption Budgets
- Deploy across multiple availability zones
- Use external load balancers
- Implement database clustering
- Use external secret management

### Security Hardening

Additional security measures for production:
- Enable audit logging
- Use Pod Security Policies/Pod Security Standards
- Implement network segmentation
- Use service mesh for mTLS
- Regular security scanning
- Implement secrets rotation

### Monitoring and Alerting

Production monitoring should include:
- Application performance monitoring (APM)
- Infrastructure monitoring
- Log aggregation and analysis
- Alerting rules for critical metrics
- SLA/SLO monitoring
- Capacity planning metrics

## Support and Maintenance

### Regular Maintenance Tasks

- Update container images monthly
- Rotate secrets quarterly
- Review and update resource limits
- Monitor and clean up old logs
- Update Kubernetes cluster regularly
- Review and update network policies

### Monitoring Key Metrics

- Request rate and latency
- Error rates
- Resource utilization
- Database performance
- Cache hit rates
- Pod restart rates

---

**Last Updated:** $(date)
**Version:** 1.0.0
**Maintainer:** PyAirtable Team