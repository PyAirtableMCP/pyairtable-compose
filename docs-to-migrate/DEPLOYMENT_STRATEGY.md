# PyAirtable Local Deployment Strategy

## 🎯 Overview

This document outlines the comprehensive strategy for deploying the entire PyAirtable ecosystem locally using Minikube, ensuring all services are properly tested and integrated before production deployment.

## 🏗️ Architecture Summary

### Services to Deploy:
1. **Frontend**: Next.js 15 (Port 3000)
2. **API Gateway**: Go (Port 8080)
3. **Auth Service**: Go (Port 8081)
4. **Python Services**:
   - LLM Orchestrator (8003)
   - MCP Server (8001)
   - Analytics Service (8005)
   - Workflow Engine (8004)
5. **Go Services**:
   - File Processing Service (8092)
   - Webhook Service (8096)
   - Plugin Service (8097)
   - User/Workspace/Table/Record Services (8082-8087)
6. **Infrastructure**:
   - PostgreSQL (5432)
   - Redis (6379)

## 📋 Pre-Deployment Checklist

### 1. System Requirements
- Docker Desktop 4.25+ (LTS)
- Minikube 1.32+ (Latest stable)
- Kubernetes 1.28+ (LTS)
- Helm 3.13+ (LTS)
- Node.js 20.x LTS
- Go 1.21+ (Latest stable)
- Python 3.11+ (LTS)

### 2. Dependency Management
```yaml
# LTS Versions Lock File
dependencies:
  frontend:
    node: "20.11.0"  # LTS
    next: "14.1.0"   # Latest stable
    react: "18.2.0"  # LTS
  
  backend:
    go: "1.21.5"
    python: "3.11.7"
    
  infrastructure:
    postgresql: "15.5"  # LTS
    redis: "7.2.3"      # Stable
    nginx: "1.24.0"     # Stable
```

## 🚀 Deployment Strategy

### Phase 1: Infrastructure Setup
```bash
# 1. Start Minikube with adequate resources
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=20g \
  --kubernetes-version=v1.28.5

# 2. Enable necessary addons
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard
```

### Phase 2: Database & Cache Deployment
```yaml
# PostgreSQL deployment with persistent volume
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
spec:
  serviceName: postgresql
  replicas: 1
  template:
    spec:
      containers:
      - name: postgresql
        image: postgres:15.5-alpine
        env:
        - name: POSTGRES_DB
          value: pyairtable
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
```

### Phase 3: Service Deployment Order
```
1. Infrastructure Layer
   ├── PostgreSQL (with migrations)
   ├── Redis
   └── Config/Secrets

2. Core Services Layer  
   ├── Auth Service (Go)
   ├── API Gateway (Go)
   └── User Service (Go)

3. Application Services Layer
   ├── Workspace Service
   ├── Table Service
   ├── Record Service
   └── Field Service

4. Feature Services Layer
   ├── File Processing (Go)
   ├── Webhook Service (Go)
   ├── Plugin Service (Go)
   ├── LLM Orchestrator (Python)
   └── Analytics Service (Python)

5. Frontend Layer
   └── Next.js Application
```

## 🔧 Implementation Scripts

### 1. One-Command Deployment Script
```bash
#!/bin/bash
# deploy-local.sh

set -e

echo "🚀 Starting PyAirtable Local Deployment..."

# Check prerequisites
./scripts/check-prerequisites.sh

# Start Minikube
./scripts/setup-minikube.sh

# Deploy infrastructure
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secrets/
kubectl apply -f k8s/infrastructure/

# Wait for databases
./scripts/wait-for-postgres.sh
./scripts/wait-for-redis.sh

# Run migrations
./scripts/run-migrations.sh

# Deploy services in order
./scripts/deploy-services.sh

# Deploy frontend
./scripts/deploy-frontend.sh

# Validate deployment
./scripts/validate-deployment.sh

echo "✅ Deployment complete!"
echo "🌐 Access the application at: $(minikube service frontend --url)"
```

### 2. Health Check Validation
```go
// healthcheck/main.go
package main

import (
    "fmt"
    "net/http"
    "time"
)

var services = map[string]string{
    "API Gateway": "http://localhost:8080/health",
    "Auth Service": "http://localhost:8081/health",
    "Frontend": "http://localhost:3000/api/health",
    // ... all services
}

func checkHealth() {
    for name, url := range services {
        resp, err := http.Get(url)
        if err != nil || resp.StatusCode != 200 {
            fmt.Printf("❌ %s is unhealthy\n", name)
        } else {
            fmt.Printf("✅ %s is healthy\n", name)
        }
    }
}
```

### 3. Resource Configuration
```yaml
# Local development resource limits
resources:
  limits:
    cpu: "500m"
    memory: "512Mi"
  requests:
    cpu: "100m"
    memory: "128Mi"
```

## 📊 Monitoring & Logging

### 1. Centralized Logging
```yaml
# Fluentd configuration for log aggregation
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/containers/*.log
      tag pyairtable.*
    </source>
```

### 2. Service Mesh (Optional)
```bash
# Install Linkerd for observability
linkerd install | kubectl apply -f -
linkerd inject k8s/deployments/ | kubectl apply -f -
```

## 🔒 Local Secrets Management

### 1. Secret Generation Script
```bash
#!/bin/bash
# generate-secrets.sh

# Generate secure passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 64)

# Create Kubernetes secrets
kubectl create secret generic db-credentials \
  --from-literal=username=pyairtable \
  --from-literal=password=$POSTGRES_PASSWORD

kubectl create secret generic redis-credentials \
  --from-literal=password=$REDIS_PASSWORD

kubectl create secret generic jwt-secret \
  --from-literal=secret=$JWT_SECRET
```

## 🧪 Testing Integration

### Pre-Deployment Tests
```bash
# Run before deployment
make test-unit
make test-integration
make test-contracts
```

### Post-Deployment Tests
```bash
# Run after deployment
make test-e2e
make test-performance
make test-security
```

## 📝 Development Workflow

### 1. Local Development Mode
```bash
# Start only infrastructure
minikube start
kubectl apply -f k8s/infrastructure/

# Run services locally
make dev-backend    # Starts all backend services
make dev-frontend   # Starts frontend with hot reload
```

### 2. Full Kubernetes Mode
```bash
# Deploy everything to Minikube
make deploy-all

# Watch logs
make logs-all

# Access services
make port-forward-all
```

## 🚨 Troubleshooting

### Common Issues:
1. **Insufficient Resources**: Increase Minikube memory/CPU
2. **Image Pull Errors**: Build images locally first
3. **Database Connection**: Check secrets and network policies
4. **Service Discovery**: Verify DNS and service names

### Debug Commands:
```bash
# Check pod status
kubectl get pods -n pyairtable

# View logs
kubectl logs -f deployment/api-gateway -n pyairtable

# Describe issues
kubectl describe pod <pod-name> -n pyairtable

# Access pod shell
kubectl exec -it <pod-name> -n pyairtable -- /bin/sh
```

## 📈 Next Steps

1. **Implement CI/CD Pipeline**: Automate testing and deployment
2. **Add Observability**: Prometheus + Grafana for metrics
3. **Security Scanning**: Integrate vulnerability scanning
4. **Performance Testing**: Load testing with K6
5. **Documentation**: Update with deployment experiences

## 🎯 Success Criteria

- [ ] All services healthy and responding
- [ ] Frontend accessible via browser
- [ ] Authentication flow working
- [ ] Database migrations completed
- [ ] Redis caching operational
- [ ] API Gateway routing correctly
- [ ] WebSocket connections established
- [ ] File uploads working
- [ ] Background jobs processing

This deployment strategy ensures a smooth, reliable local development and testing environment for the entire PyAirtable ecosystem.