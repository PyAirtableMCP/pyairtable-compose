# PyAirtable Kubernetes Deployment

This directory contains Kubernetes manifests and scripts for deploying the PyAirtable microservices platform.

## Prerequisites

- Kubernetes cluster (Minikube, Docker Desktop, or cloud provider)
- kubectl CLI installed and configured
- Docker for building images
- At least 8GB RAM available for the cluster
- 20GB disk space for images and data

## Quick Start

1. **Set up environment variables**:
   ```bash
   export AIRTABLE_TOKEN=your-airtable-token
   export GEMINI_API_KEY=your-gemini-api-key
   ```

2. **Deploy everything**:
   ```bash
   ./deploy-local.sh
   ```

3. **Test the deployment**:
   ```bash
   ./test-deployment.sh
   ```

4. **Access the API Gateway**:
   - Minikube: The script will show the URL
   - Docker Desktop: http://localhost:30080

## Directory Structure

```
k8s/
├── namespace.yaml                  # PyAirtable namespace
├── configmap.yaml                  # Service URLs and configuration
├── postgres-deployment.yaml        # PostgreSQL with persistent storage
├── redis-deployment.yaml           # Redis for caching
├── api-gateway-deployment.yaml     # API Gateway (NodePort)
├── auth-service-deployment.yaml    # Authentication service
├── core-services-deployment.yaml   # Airtable Gateway, LLM, MCP
├── go-services-deployment.yaml     # All Go microservices
├── python-services-deployment.yaml # All Python microservices
├── deploy-local.sh                 # Deployment automation script
├── test-deployment.sh              # Test script
└── cleanup.sh                      # Clean up all resources
```

## Services Overview

### Core Services
- **API Gateway** (8080/30080): Routes all traffic to backend services
- **Auth Service** (8081): JWT authentication and user management
- **Airtable Gateway** (8093): Airtable API integration with caching
- **LLM Orchestrator** (8091): Gemini integration for chat
- **MCP Server** (8092): Model Context Protocol tools

### Go Services (8082-8090)
- User Service: User profile management
- Notification Service: Email/SMS notifications
- Audit Service: Activity logging
- Config Service: Dynamic configuration
- Metrics Service: Performance metrics
- Scheduler Service: Cron job management
- Webhook Service: Webhook processing
- Cache Service: Distributed caching
- Search Service: Full-text search

### Python Services (8094-8100)
- Analytics Service: Data analytics
- Workflow Engine: Business automation
- File Processor: Document processing
- Data Pipeline: ETL operations
- Report Generator: PDF/Excel reports
- Webhook Handler: Incoming webhooks
- Storage Service: File storage

## Deployment Commands

### Full Deployment
```bash
# Deploy everything with image building
./deploy-local.sh

# Deploy without building (images must exist)
kubectl apply -f k8s/
```

### Individual Components
```bash
# Deploy infrastructure only
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/redis-deployment.yaml

# Deploy specific service group
kubectl apply -f k8s/core-services-deployment.yaml
kubectl apply -f k8s/go-services-deployment.yaml
kubectl apply -f k8s/python-services-deployment.yaml
```

## Configuration

### Secrets
The deployment script creates secrets automatically. To customize:
```bash
kubectl create secret generic pyairtable-secrets \
    --namespace=pyairtable \
    --from-literal=postgres-password=your-password \
    --from-literal=redis-password=your-password \
    --from-literal=jwt-secret=your-32-char-secret \
    --from-literal=airtable-token=$AIRTABLE_TOKEN \
    --from-literal=gemini-api-key=$GEMINI_API_KEY \
    --from-literal=api-key=your-internal-api-key
```

### ConfigMap
Edit `configmap.yaml` to change service URLs or add configuration.

### Resource Limits
Each deployment has resource requests and limits:
- Core services: 128-256Mi memory, 100-500m CPU
- Data services: 512Mi-1Gi memory, 300-1000m CPU
- Adjust in deployment files based on your needs

## Monitoring

### View Logs
```bash
# Single service
kubectl logs -n pyairtable deployment/api-gateway

# Follow logs
kubectl logs -n pyairtable deployment/api-gateway -f

# All containers in a pod
kubectl logs -n pyairtable <pod-name> --all-containers
```

### Check Status
```bash
# All resources
kubectl get all -n pyairtable

# Detailed pod info
kubectl describe pod -n pyairtable <pod-name>

# Service endpoints
kubectl get endpoints -n pyairtable

# Events
kubectl get events -n pyairtable --sort-by='.lastTimestamp'
```

## Scaling

### Manual Scaling
```bash
# Scale a deployment
kubectl scale deployment/api-gateway --replicas=3 -n pyairtable

# Scale multiple deployments
kubectl scale deployment/api-gateway deployment/auth-service --replicas=3 -n pyairtable
```

### Horizontal Pod Autoscaler
```bash
# Create HPA (requires metrics-server)
kubectl autoscale deployment/api-gateway \
    --cpu-percent=70 \
    --min=2 \
    --max=10 \
    -n pyairtable
```

## Troubleshooting

### Pod Not Starting
```bash
# Check pod status
kubectl get pods -n pyairtable

# View pod events
kubectl describe pod -n pyairtable <pod-name>

# Check logs
kubectl logs -n pyairtable <pod-name> --previous
```

### Service Not Accessible
```bash
# Check service endpoints
kubectl get endpoints -n pyairtable

# Test from inside cluster
kubectl run test-pod --rm -it --image=busybox --restart=Never -- wget -qO- http://api-gateway.pyairtable:8080/health
```

### Database Connection Issues
```bash
# Check PostgreSQL
kubectl exec -it -n pyairtable deployment/postgres -- psql -U admin -d pyairtablemcp

# Check Redis
kubectl exec -it -n pyairtable deployment/redis -- redis-cli -a changeme ping
```

## Cleanup

### Remove Everything
```bash
# Interactive cleanup script
./cleanup.sh

# Manual cleanup
kubectl delete namespace pyairtable
```

### Partial Cleanup
```bash
# Delete deployments only
kubectl delete deployments --all -n pyairtable

# Delete a specific service
kubectl delete -f k8s/api-gateway-deployment.yaml
```

## Production Considerations

1. **Secrets Management**: Use Kubernetes Secrets management or external secret stores
2. **Persistent Storage**: Configure proper StorageClass for production PostgreSQL
3. **Ingress**: Set up Ingress controller instead of NodePort
4. **TLS**: Configure TLS certificates for all services
5. **Monitoring**: Deploy Prometheus and Grafana
6. **Backup**: Implement automated PostgreSQL backups
7. **High Availability**: Increase replica counts and configure pod disruption budgets
8. **Network Policies**: Implement network segmentation
9. **Resource Limits**: Fine-tune based on actual usage
10. **Security**: Run security scans and implement pod security policies

## Local Development Tips

### Minikube
```bash
# Start with enough resources
minikube start --cpus=4 --memory=8192 --disk-size=30g

# Enable ingress
minikube addons enable ingress

# Access services
minikube service api-gateway -n pyairtable
```

### Docker Desktop
- Enable Kubernetes in Docker Desktop settings
- Allocate at least 4 CPUs and 8GB RAM
- Services available at localhost:30080

### Port Forwarding
```bash
# Forward API Gateway
kubectl port-forward -n pyairtable service/api-gateway 8080:8080

# Forward multiple services
kubectl port-forward -n pyairtable service/postgres 5432:5432 &
kubectl port-forward -n pyairtable service/redis 6379:6379 &
```