# PyAirtable Local Development Guide

Complete guide for setting up and working with PyAirtable on Minikube for local development.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Development Workflow](#development-workflow)
- [Service Management](#service-management)
- [Database Operations](#database-operations)
- [Debugging and Troubleshooting](#debugging-and-troubleshooting)
- [Performance Optimization](#performance-optimization)
- [Best Practices](#best-practices)
- [Common Issues](#common-issues)

## Quick Start

For experienced developers who want to get started immediately:

```bash
# 1. Setup Minikube cluster
./scripts/minikube-setup.sh

# 2. Generate and configure secrets
./scripts/secrets-manager.sh generate
./scripts/secrets-manager.sh apply

# 3. Deploy all services
./scripts/deploy-local-complete.sh

# 4. Verify deployment
./scripts/health-monitor.sh check

# 5. Access the application
open http://$(minikube ip -p pyairtable):30000
```

## Prerequisites

### Required Software

| Tool | Version | Installation |
|------|---------|-------------|
| **Minikube** | v1.30+ | [Install Guide](https://minikube.sigs.k8s.io/docs/start/) |
| **kubectl** | v1.28+ | [Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | v3.12+ | [Install Guide](https://helm.sh/docs/intro/install/) |
| **Docker** | v24.0+ | [Install Guide](https://docs.docker.com/get-docker/) |

### System Requirements

- **Memory**: 8GB RAM minimum, 16GB recommended
- **CPU**: 4 cores minimum, 8 cores recommended  
- **Disk**: 20GB free space minimum
- **OS**: macOS 10.15+, Ubuntu 20.04+, Windows 10+

### Verification

Run these commands to verify your setup:

```bash
# Check versions
minikube version
kubectl version --client
helm version
docker --version

# Check Docker daemon
docker info

# Check available resources
free -h  # Linux
vm_stat | head -10  # macOS
```

## Initial Setup

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd pyairtable-compose
```

### 2. Minikube Cluster Setup

The setup script handles cluster creation, addon configuration, and resource optimization:

```bash
# Full setup with defaults (6GB RAM, 4 CPUs)
./scripts/minikube-setup.sh

# Custom resource allocation
./scripts/minikube-setup.sh --memory 8g --cpus 6 --disk-size 50g

# Clean setup (removes existing cluster)
./scripts/minikube-setup.sh --clean
```

**What this does:**
- Creates optimized Minikube profile
- Enables required addons (ingress, registry, metrics-server)
- Configures storage classes
- Sets up local registry
- Configures kubectl context

### 3. Secrets Configuration

PyAirtable uses a comprehensive secrets management system:

```bash
# Generate development secrets template
./scripts/secrets-manager.sh template

# Generate secure development secrets
./scripts/secrets-manager.sh generate

# Edit secrets (add your API keys)
nano .env.local

# Apply secrets to Kubernetes
./scripts/secrets-manager.sh apply
```

**Required secrets to configure:**
- `GEMINI_API_KEY`: Your Google Gemini API key
- `AIRTABLE_TOKEN`: Your Airtable API token  
- `AIRTABLE_BASE`: Your Airtable base ID

### 4. Complete Deployment

Deploy all services with a single command:

```bash
# Full deployment
./scripts/deploy-local-complete.sh

# Deploy specific phases
./scripts/deploy-local-complete.sh --phase cluster,images,database,services

# Skip image building (use existing images)
./scripts/deploy-local-complete.sh --skip-build
```

**Deployment phases:**
1. **Preflight**: System checks and validation
2. **Cluster**: Minikube setup and configuration  
3. **Images**: Docker image building
4. **Database**: PostgreSQL and Redis initialization
5. **Secrets**: Kubernetes secrets and config maps
6. **Services**: Application service deployment
7. **Validation**: Health checks and connectivity tests
8. **Dashboard**: Access information and monitoring setup

## Development Workflow

### Daily Development Routine

1. **Start Development Session**
   ```bash
   # Check cluster status
   minikube status -p pyairtable
   
   # Start if stopped
   minikube start -p pyairtable
   
   # Check service health
   ./scripts/health-monitor.sh check
   ```

2. **Monitor Services**
   ```bash
   # Real-time health dashboard
   ./scripts/health-monitor.sh monitor
   
   # Stream all logs
   ./scripts/logs-aggregator.sh stream
   
   # Monitor specific service
   ./scripts/logs-aggregator.sh tail api-gateway
   ```

3. **Make Code Changes**
   - Edit service code in respective directories
   - Services with hot reload will update automatically
   - For services requiring rebuild, see [Image Management](#image-management)

4. **Test Changes**
   ```bash
   # Run health checks
   ./scripts/health-monitor.sh check
   
   # Test specific endpoints
   curl http://$(minikube ip -p pyairtable):30800/health
   
   # View application
   open http://$(minikube ip -p pyairtable):30000
   ```

### Image Management

When you make code changes that require rebuilding images:

```bash
# Build all images
./scripts/deploy-local-complete.sh --phase images

# Build specific service
eval $(minikube docker-env -p pyairtable)
docker build -t pyairtable-api-gateway:latest ../pyairtable-api-gateway

# Restart service to use new image
kubectl rollout restart deployment/api-gateway -n pyairtable
```

### Service Configuration

Modify service behavior through environment variables:

```bash
# Update configuration
./scripts/secrets-manager.sh update thinking-budget "3000"
./scripts/secrets-manager.sh update log-level "debug"

# Restart services to pick up changes
kubectl rollout restart deployment/llm-orchestrator -n pyairtable
```

## Service Management

### Service Access

| Service | Internal URL | External URL | Purpose |
|---------|-------------|--------------|---------|
| **Frontend** | `frontend:3000` | `http://minikube-ip:30000` | Web interface |
| **API Gateway** | `api-gateway:8000` | `http://minikube-ip:30800` | Main API entry |
| **LLM Orchestrator** | `llm-orchestrator:8003` | Port-forward | AI integration |
| **MCP Server** | `mcp-server:8001` | Port-forward | Protocol implementation |
| **Airtable Gateway** | `airtable-gateway:8002` | Port-forward | Airtable API integration |
| **Platform Services** | `platform-services:8007` | Port-forward | Auth & Analytics |
| **Automation Services** | `automation-services:8006` | Port-forward | File processing |
| **SAGA Orchestrator** | `saga-orchestrator:8008` | Port-forward | Transaction coordination |

### Port Forwarding

Access internal services for debugging:

```bash
# Forward specific service
kubectl port-forward service/llm-orchestrator 8003:8003 -n pyairtable

# Forward multiple services
kubectl port-forward service/platform-services 8007:8007 -n pyairtable &
kubectl port-forward service/automation-services 8006:8006 -n pyairtable &
```

### Service Scaling

```bash
# Scale service replicas
kubectl scale deployment api-gateway --replicas=2 -n pyairtable

# View current scaling
kubectl get deployments -n pyairtable

# Reset to single replica (recommended for local dev)
kubectl scale deployment api-gateway --replicas=1 -n pyairtable
```

### Service Logs

```bash
# View recent logs
kubectl logs deployment/api-gateway -n pyairtable --tail=100

# Follow logs in real-time
kubectl logs -f deployment/llm-orchestrator -n pyairtable

# View logs from all containers
kubectl logs deployment/platform-services -n pyairtable --all-containers=true
```

## Database Operations

### PostgreSQL Management

```bash
# Initialize database
./scripts/database-init.sh init

# Run migrations only
./scripts/database-init.sh migrate

# Create backup
./scripts/database-init.sh backup

# Reset database (WARNING: destroys data)
./scripts/database-init.sh reset

# Verify setup
./scripts/database-init.sh verify
```

### Database Access

```bash
# Connect to PostgreSQL
kubectl exec -it deployment/postgres -n pyairtable -- psql -U postgres -d pyairtable

# Run SQL queries
kubectl exec -it deployment/postgres -n pyairtable -- psql -U postgres -d pyairtable -c "SELECT * FROM auth.users;"

# Import SQL file
kubectl exec -i deployment/postgres -n pyairtable -- psql -U postgres -d pyairtable < migration.sql
```

### Redis Operations

```bash
# Connect to Redis
kubectl exec -it deployment/redis -n pyairtable -- redis-cli

# Check Redis info
kubectl exec deployment/redis -n pyairtable -- redis-cli info

# Flush Redis (clear all data)
kubectl exec deployment/redis -n pyairtable -- redis-cli flushall
```

## Debugging and Troubleshooting

### Health Monitoring

```bash
# Comprehensive health check
./scripts/health-monitor.sh check

# Continuous monitoring
./scripts/health-monitor.sh monitor

# Generate detailed report
./scripts/health-monitor.sh report

# Restart unhealthy services
./scripts/health-monitor.sh restart

# View cluster resources
./scripts/health-monitor.sh resources
```

### Log Analysis

```bash
# Setup log aggregation
./scripts/logs-aggregator.sh setup

# Stream all logs with filtering
./scripts/logs-aggregator.sh stream

# Search for specific issues
./scripts/logs-aggregator.sh search "error" api-gateway
./scripts/logs-aggregator.sh search "timeout" all

# View log statistics
./scripts/logs-aggregator.sh stats

# Real-time dashboard
./scripts/logs-aggregator.sh dashboard
```

### Service Debugging

1. **Check Pod Status**
   ```bash
   kubectl get pods -n pyairtable
   kubectl describe pod <pod-name> -n pyairtable
   ```

2. **View Events**
   ```bash
   kubectl get events -n pyairtable --sort-by='.lastTimestamp'
   ```

3. **Execute Commands in Pods**
   ```bash
   kubectl exec -it deployment/api-gateway -n pyairtable -- /bin/bash
   kubectl exec deployment/postgres -n pyairtable -- pg_isready
   ```

4. **Check Resource Usage**
   ```bash
   kubectl top pods -n pyairtable
   kubectl top nodes
   ```

### Network Debugging

```bash
# Test service connectivity
kubectl exec deployment/api-gateway -n pyairtable -- curl http://llm-orchestrator:8003/health

# Check service DNS resolution
kubectl exec deployment/api-gateway -n pyairtable -- nslookup postgres

# View network policies
kubectl get networkpolicies -n pyairtable
```

## Performance Optimization

### Resource Tuning

The system includes three resource profiles:

1. **Laptop Profile** (default): 4GB RAM, 2 CPU cores
2. **Workstation Profile**: 8GB RAM, 4 CPU cores  
3. **Server Profile**: 16GB RAM, 8 CPU cores

```bash
# Switch to workstation profile
helm upgrade pyairtable-stack k8s/helm/pyairtable-stack \
  --set global.resourceOptimization.profile=workstation \
  --namespace pyairtable
```

### Memory Optimization

```bash
# Check memory usage
kubectl top pods -n pyairtable --sort-by=memory

# Identify memory-hungry services
kubectl describe nodes | grep -A 10 "Allocated resources"

# Optimize PostgreSQL
kubectl patch configmap postgres-config -n pyairtable -p '{"data":{"shared_buffers":"32MB"}}'
kubectl rollout restart deployment/postgres -n pyairtable
```

### CPU Optimization

```bash
# Monitor CPU usage
kubectl top pods -n pyairtable --sort-by=cpu

# Reduce CPU-intensive logging
./scripts/secrets-manager.sh update log-level "warn"
kubectl rollout restart deployment/llm-orchestrator -n pyairtable
```

### Storage Optimization

```bash
# Check disk usage
kubectl exec deployment/postgres -n pyairtable -- df -h

# Clean up old logs
./scripts/logs-aggregator.sh cleanup 3

# Compact database
kubectl exec deployment/postgres -n pyairtable -- psql -U postgres -d pyairtable -c "VACUUM FULL;"
```

## Best Practices

### Development Environment

1. **Use Resource Limits**
   - Always use the optimized values files
   - Monitor resource usage regularly
   - Scale down when not actively developing

2. **Log Management**
   - Use structured logging
   - Set appropriate log levels
   - Clean up logs regularly

3. **Secret Management**
   - Never commit actual secrets
   - Rotate secrets regularly
   - Use development-specific values

4. **Database Management**
   - Run migrations in order
   - Create backups before major changes
   - Use seed data for consistent testing

### Code Changes

1. **Service Updates**
   - Test changes in isolation first
   - Use health checks to verify functionality
   - Monitor logs during deployment

2. **Database Changes**
   - Write reversible migrations
   - Test migrations on development data
   - Document schema changes

3. **Configuration Changes**
   - Use ConfigMaps for non-sensitive config
   - Use Secrets for sensitive information
   - Document configuration dependencies

### Monitoring and Alerting

1. **Health Monitoring**
   - Check health endpoints regularly
   - Monitor service dependencies
   - Set up alerts for critical services

2. **Performance Monitoring**
   - Track resource usage trends
   - Monitor response times
   - Identify bottlenecks early

## Common Issues

### Startup Issues

**Problem**: Services fail to start
```bash
# Check pod status
kubectl get pods -n pyairtable

# Check events
kubectl get events -n pyairtable --sort-by='.lastTimestamp'

# Check logs
kubectl logs deployment/<service-name> -n pyairtable
```

**Solutions**:
- Verify secrets are properly configured
- Check resource availability
- Ensure dependencies are healthy
- Verify image availability

### Memory Issues

**Problem**: Out of memory errors
```bash
# Check memory usage
kubectl top pods -n pyairtable
minikube addons enable metrics-server -p pyairtable
```

**Solutions**:
- Use `values-local-optimized.yaml`
- Increase Minikube memory allocation
- Reduce service replicas
- Optimize application memory usage

### Network Issues

**Problem**: Services can't communicate
```bash
# Test service connectivity
kubectl exec deployment/api-gateway -n pyairtable -- curl http://postgres:5432

# Check DNS resolution
kubectl exec deployment/api-gateway -n pyairtable -- nslookup postgres
```

**Solutions**:
- Verify service names and ports
- Check namespace configuration
- Ensure services are running
- Verify network policies

### Database Issues

**Problem**: Database connection failures
```bash
# Check PostgreSQL status
kubectl exec deployment/postgres -n pyairtable -- pg_isready -U postgres

# Check database logs
kubectl logs deployment/postgres -n pyairtable
```

**Solutions**:
- Verify database credentials
- Check PostgreSQL configuration  
- Ensure database is initialized
- Verify persistent volume claims

### Performance Issues

**Problem**: Slow response times
```bash
# Check resource usage
kubectl top pods -n pyairtable
kubectl top nodes

# Check service health
./scripts/health-monitor.sh check
```

**Solutions**:
- Use resource-optimized configuration
- Increase Minikube resources
- Optimize database queries
- Reduce logging verbosity
- Check for resource contention

### Image Issues

**Problem**: Image pull failures
```bash
# Check image status
kubectl describe pod <pod-name> -n pyairtable

# List available images
minikube image ls -p pyairtable
```

**Solutions**:
- Ensure images are built locally
- Use correct image tags
- Check image pull policy
- Verify Docker daemon connection

## Getting Help

### Quick Diagnostics

Run this comprehensive diagnostic command:

```bash
# Full system diagnostic
{
  echo "=== System Info ==="
  minikube version
  kubectl version --client
  
  echo -e "\n=== Cluster Status ==="
  minikube status -p pyairtable
  
  echo -e "\n=== Pod Status ==="
  kubectl get pods -n pyairtable
  
  echo -e "\n=== Service Health ==="
  ./scripts/health-monitor.sh check
  
  echo -e "\n=== Recent Events ==="
  kubectl get events -n pyairtable --sort-by='.lastTimestamp' | tail -10
  
  echo -e "\n=== Resource Usage ==="
  kubectl top pods -n pyairtable 2>/dev/null || echo "Metrics server not available"
} | tee diagnostic-report.txt
```

### Log Collection

```bash
# Collect all logs for support
./scripts/logs-aggregator.sh export all json logs-$(date +%Y%m%d).json
```

### Useful Commands Reference

```bash
# Quick service restart
kubectl rollout restart deployment/<service-name> -n pyairtable

# Quick cluster cleanup
./scripts/deploy-local-complete.sh --clean

# Complete reset
minikube delete -p pyairtable
./scripts/minikube-setup.sh
./scripts/deploy-local-complete.sh

# Emergency stop
minikube stop -p pyairtable

# View all resources
kubectl get all -n pyairtable
```

---

For additional support, check the troubleshooting logs and service documentation in the respective service directories.