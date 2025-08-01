# PyAirtable Kubernetes Migration

This directory contains the complete Kubernetes deployment configuration for the PyAirtable microservices stack, migrated from docker-compose to run on Minikube for local development.

## 🏗️ Architecture Overview

The application consists of 8 microservices:

### Application Services
- **Frontend** (port 3000) - Next.js web interface
- **API Gateway** (port 8000) - Main entry point and request routing
- **LLM Orchestrator** (port 8003) - Gemini 2.5 Flash integration
- **MCP Server** (port 8001) - Protocol implementation
- **Airtable Gateway** (port 8002) - Direct Airtable API integration
- **Platform Services** (port 8007) - Unified auth & analytics
- **Automation Services** (port 8006) - File processing and workflow automation

### Infrastructure Services
- **PostgreSQL** (port 5432) - Primary database for sessions and metadata
- **Redis** (port 6379) - Caching and session storage

## 📁 Directory Structure

```
k8s/
├── helm/pyairtable-stack/           # Helm chart for the entire stack
│   ├── Chart.yaml                   # Chart metadata
│   ├── values.yaml                  # Default configuration values
│   ├── values-dev.yaml              # Development-specific overrides
│   └── templates/                   # Kubernetes resource templates
│       ├── _helpers.tpl             # Template helpers
│       ├── secrets.yaml             # Secrets and ConfigMaps
│       ├── persistent-volumes.yaml  # PVC definitions
│       ├── postgres.yaml            # PostgreSQL deployment
│       ├── redis.yaml               # Redis deployment
│       ├── api-gateway.yaml         # API Gateway service
│       ├── llm-orchestrator.yaml    # LLM Orchestrator service
│       ├── mcp-server.yaml          # MCP Server service
│       ├── airtable-gateway.yaml    # Airtable Gateway service
│       ├── platform-services.yaml   # Platform Services
│       ├── automation-services.yaml # Automation Services
│       ├── frontend.yaml            # Frontend service
│       └── ingress.yaml             # Ingress configuration
├── deploy-dev.sh                    # Development deployment script
├── cleanup-dev.sh                   # Cleanup script
├── monitor-dev.sh                   # Monitoring and debugging script
└── README.md                        # This file
```

## 🚀 Quick Start

### Prerequisites

1. **Docker Desktop** - Running and properly configured
2. **Minikube** - For local Kubernetes cluster
3. **kubectl** - Kubernetes command-line tool
4. **Helm** - Package manager for Kubernetes

All prerequisites are automatically installed by the deployment script if missing.

### 1. Start Minikube

```bash
minikube start --memory=2500 --cpus=2
```

### 2. Deploy the Application

```bash
cd k8s
./deploy-dev.sh
```

This script will:
- Check and install missing prerequisites
- Create the `pyairtable` namespace
- Deploy all services using Helm
- Set up port forwarding options
- Provide service access information

### 3. Access the Application

After deployment, access services via port forwarding:

```bash
# Frontend
kubectl port-forward -n pyairtable service/frontend 3000:3000

# API Gateway  
kubectl port-forward -n pyairtable service/api-gateway 8000:8000
```

Then open:
- Frontend: http://localhost:3000
- API Gateway: http://localhost:8000

## 🛠️ Configuration

### Environment Variables

All sensitive configuration is managed through Kubernetes Secrets and ConfigMaps. Key variables to configure in `values-dev.yaml`:

```yaml
secrets:
  apiKey: "your-api-key-here"
  geminiApiKey: "your-gemini-api-key-here"
  airtableToken: "your-airtable-token-here"
  airtableBase: "your-airtable-base-here"
  # ... other secrets
```

### Resource Allocation

Development resource limits are optimized for local machines:

```yaml
services:
  apiGateway:
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
```

### Storage

Persistent volumes are created for:
- PostgreSQL data (2Gi in development)
- Redis data (500Mi in development)  
- File uploads (1Gi in development)

## 📊 Monitoring and Debugging

### Monitor Services

```bash
./monitor-dev.sh
```

This interactive script provides:
- Pod status overview
- Log viewing for individual services
- Port forwarding setup
- Issue debugging
- Real-time pod watching
- Kubernetes dashboard access

### Manual Commands

```bash
# Check pod status
kubectl get pods -n pyairtable

# View logs for a specific service
kubectl logs -f deployment/pyairtable-dev-api-gateway -n pyairtable

# Check service endpoints
kubectl get services -n pyairtable

# Debug failing pods
kubectl describe pod POD_NAME -n pyairtable
```

## 🔧 Development Workflow

### Making Changes

1. **Update Helm Values**: Modify `values-dev.yaml` for configuration changes
2. **Update Templates**: Modify files in `templates/` for structural changes
3. **Redeploy**: Run `./deploy-dev.sh` to apply changes

### Upgrading Services

```bash
# Upgrade specific release
helm upgrade pyairtable-dev ./helm/pyairtable-stack \
    --namespace pyairtable \
    --values ./helm/pyairtable-stack/values-dev.yaml
```

### Scaling Services

```bash
# Scale a specific service
kubectl scale deployment pyairtable-dev-api-gateway --replicas=2 -n pyairtable
```

## 🧹 Cleanup

### Remove Application Only

```bash
./cleanup-dev.sh
```

### Remove Everything (including Minikube)

```bash
./cleanup-dev.sh
# Then select 'y' when prompted to delete Minikube cluster
```

## 🆚 Docker Compose vs Kubernetes Comparison

| Aspect | Docker Compose | Kubernetes |
|--------|----------------|------------|
| **Orchestration** | Simple, single-host | Advanced, multi-host capable |
| **Service Discovery** | Built-in DNS | Native service discovery |
| **Load Balancing** | Basic | Advanced with multiple algorithms |
| **Health Checks** | Limited | Comprehensive liveness/readiness |
| **Scaling** | Manual | Manual and automatic (HPA) |
| **Rolling Updates** | Not supported | Built-in |
| **Configuration** | Environment files | ConfigMaps and Secrets |
| **Storage** | Named volumes | Persistent Volumes with classes |
| **Networking** | Bridge networks | CNI with network policies |
| **Resource Limits** | Basic | Granular CPU/memory controls |

## 🎯 Benefits of Kubernetes Migration

### 1. **Production Readiness**
- Industry-standard container orchestration
- Battle-tested in production environments
- Mature ecosystem of tools and practices

### 2. **Enhanced Observability**
- Built-in health checks and readiness probes
- Resource usage monitoring
- Structured logging integration
- Metrics collection endpoints

### 3. **Improved Resource Management**
- Granular CPU and memory limits
- Quality of Service (QoS) classes
- Resource quotas and limits
- Efficient resource utilization

### 4. **Better Service Management**
- Rolling updates with zero downtime
- Automatic service discovery
- Load balancing across replicas
- Service mesh integration capabilities

### 5. **Configuration Management**
- Secrets management with encryption at rest
- ConfigMaps for non-sensitive configuration
- Environment-specific value overrides
- Centralized configuration management

### 6. **Development to Production Parity**
- Same orchestration platform from dev to prod
- Consistent deployment patterns
- Infrastructure as Code with Helm charts
- Environment promotion workflows

## ⚠️ Known Issues and Solutions

### 1. **Image Pull Errors**
```bash
# If you see ImagePullBackOff errors
minikube ssh
docker pull ghcr.io/reg-kris/SERVICE_NAME:latest
```

### 2. **Resource Constraints**
```bash
# Increase Minikube resources
minikube delete
minikube start --memory=4000 --cpus=3
```

### 3. **Persistent Volume Issues**
```bash
# Check storage class
kubectl get storageclass

# Manually create PVs if needed
kubectl apply -f templates/persistent-volumes.yaml
```

### 4. **Service Communication Issues**
```bash
# Check service endpoints
kubectl get endpoints -n pyairtable

# Test internal DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup api-gateway.pyairtable.svc.cluster.local
```

## 🔮 Future Enhancements

### 1. **Production Deployment**
- Create production-ready Helm values
- Implement proper secrets management (Vault, External Secrets)
- Add network policies for security
- Configure resource quotas and limits

### 2. **CI/CD Integration**
- GitHub Actions workflows for automated deployment
- Helm chart testing and validation
- Security scanning integration
- Automated rollback capabilities

### 3. **Monitoring Stack**
- Prometheus and Grafana integration
- Application metrics collection
- Distributed tracing with Jaeger
- Log aggregation with ELK stack

### 4. **Service Mesh**
- Istio integration for advanced traffic management
- mTLS between services
- Circuit breakers and retry policies
- Canary deployments

## 🤝 Contributing

1. **Testing Changes**: Always test changes in development environment
2. **Documentation**: Update this README for any architectural changes
3. **Resource Limits**: Be mindful of resource consumption in shared environments
4. **Security**: Never commit secrets to version control

## 📞 Support

For issues and questions:
1. Check the monitoring dashboard: `./monitor-dev.sh`
2. Review pod logs for error messages
3. Verify resource constraints and limits
4. Check Kubernetes events: `kubectl get events -n pyairtable`

---

**Happy Kuberneting! 🚢**