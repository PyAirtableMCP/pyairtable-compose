# PyAirtable Troubleshooting Guide

Comprehensive troubleshooting guide for PyAirtable local development issues.

## Table of Contents

- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [Common Issues](#common-issues)
- [Service-Specific Issues](#service-specific-issues)
- [Infrastructure Issues](#infrastructure-issues)
- [Performance Issues](#performance-issues)
- [Advanced Debugging](#advanced-debugging)
- [Recovery Procedures](#recovery-procedures)

## Quick Diagnostic Commands

### System Health Check

```bash
# Full system diagnostic
./scripts/health-monitor.sh check

# Generate detailed report
./scripts/health-monitor.sh report

# Check cluster resources
kubectl top pods -n pyairtable
kubectl top nodes
```

### Service Status

```bash
# Pod status overview
kubectl get pods -n pyairtable -o wide

# Service status
kubectl get services -n pyairtable

# Recent events
kubectl get events -n pyairtable --sort-by='.lastTimestamp' | tail -20
```

### Log Analysis

```bash
# Recent errors across all services
./scripts/logs-aggregator.sh search "error" all 20

# Service-specific logs
kubectl logs deployment/<service-name> -n pyairtable --tail=50

# Real-time log monitoring
./scripts/logs-aggregator.sh tail all
```

## Common Issues

### 1. Services Not Starting

**Symptoms:**
- Pods stuck in `Pending` or `CrashLoopBackOff` state
- Services fail health checks
- Error messages in pod logs

**Diagnostic Commands:**
```bash
# Check pod status
kubectl get pods -n pyairtable

# Describe problematic pod
kubectl describe pod <pod-name> -n pyairtable

# Check recent events
kubectl get events -n pyairtable --field-selector type=Warning
```

**Common Causes & Solutions:**

#### Insufficient Resources
```bash
# Check node resources
kubectl describe nodes | grep -A 10 "Allocated resources"

# Solution: Increase Minikube resources
minikube stop -p pyairtable
minikube start -p pyairtable --memory=8g --cpus=6
```

#### Missing Secrets
```bash
# Check if secrets exist
kubectl get secrets -n pyairtable

# Solution: Create/update secrets
./scripts/secrets-manager.sh generate
./scripts/secrets-manager.sh apply
```

#### Image Pull Issues
```bash
# Check image pull status
kubectl describe pod <pod-name> -n pyairtable | grep -A 5 "Events"

# Solution: Rebuild images
eval $(minikube docker-env -p pyairtable)
./scripts/deploy-local-complete.sh --phase images
```

### 2. Service Connectivity Issues

**Symptoms:**
- Services can't reach each other
- Health checks fail with connection errors
- DNS resolution failures

**Diagnostic Commands:**
```bash
# Test service connectivity
kubectl exec deployment/api-gateway -n pyairtable -- curl -v http://postgres:5432

# Check DNS resolution
kubectl exec deployment/api-gateway -n pyairtable -- nslookup postgres

# Check service endpoints
kubectl get endpoints -n pyairtable
```

**Solutions:**

#### DNS Issues
```bash
# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# Check DNS configuration
kubectl get configmap coredns -n kube-system -o yaml
```

#### Service Port Mismatches
```bash
# Verify service configurations
kubectl get services -n pyairtable -o yaml | grep -A 3 -B 3 "port:"

# Check deployment port configurations
kubectl get deployments -n pyairtable -o yaml | grep -A 3 -B 3 "containerPort:"
```

### 3. Database Connection Issues

**Symptoms:**
- Services report database connection failures
- PostgreSQL pod not ready
- Authentication failures

**Diagnostic Commands:**
```bash
# Check PostgreSQL status
kubectl exec deployment/postgres -n pyairtable -- pg_isready -U postgres

# Check database logs
kubectl logs deployment/postgres -n pyairtable --tail=100

# Test connection from service
kubectl exec deployment/platform-services -n pyairtable -- \
  python -c "import psycopg2; print('Connection test')"
```

**Solutions:**

#### PostgreSQL Not Ready
```bash
# Check PostgreSQL pod status
kubectl get pods -l app=postgres -n pyairtable

# Restart PostgreSQL
kubectl rollout restart deployment/postgres -n pyairtable

# Check persistent volume
kubectl get pvc -n pyairtable
```

#### Authentication Issues
```bash
# Verify database credentials
kubectl get secret pyairtable-secrets -n pyairtable -o yaml | \
  grep postgres-password | head -1 | awk '{print $2}' | base64 -d

# Reset database password
./scripts/secrets-manager.sh rotate database
```

#### Database Corruption
```bash
# Check database integrity
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -d pyairtable -c "SELECT version();"

# Restore from backup (if available)
./scripts/database-init.sh restore <backup-file>

# Complete reset (WARNING: destroys data)
./scripts/database-init.sh reset
```

### 4. Memory and Resource Issues

**Symptoms:**
- Pods killed with `OOMKilled` status
- Slow response times
- High resource usage warnings

**Diagnostic Commands:**
```bash
# Check memory usage
kubectl top pods -n pyairtable --sort-by=memory

# Check node resources
kubectl describe nodes | grep -A 15 "Allocated resources"

# Check resource limits
kubectl describe pods -n pyairtable | grep -A 10 -B 10 "Limits"
```

**Solutions:**

#### Optimize Resource Allocation
```bash
# Use resource-optimized configuration
helm upgrade pyairtable-stack k8s/helm/pyairtable-stack \
  --values k8s/values-local-optimized.yaml \
  --namespace pyairtable

# Increase Minikube resources
minikube stop -p pyairtable
minikube start -p pyairtable --memory=12g --cpus=8
```

#### Reduce Memory Usage
```bash
# Disable metrics and tracing
./scripts/secrets-manager.sh update enable-metrics "false"
./scripts/secrets-manager.sh update enable-tracing "false"

# Reduce log verbosity
./scripts/secrets-manager.sh update log-level "warn"
```

### 5. Frontend Access Issues

**Symptoms:**
- Cannot access frontend at `http://minikube-ip:30000`
- Frontend shows API connection errors
- Static assets not loading

**Diagnostic Commands:**
```bash
# Check frontend pod status
kubectl get pods -l app=frontend -n pyairtable

# Check NodePort service
kubectl get service frontend -n pyairtable

# Test frontend health
curl http://$(minikube ip -p pyairtable):30000/api/health
```

**Solutions:**

#### Service Configuration Issues
```bash
# Check service configuration
kubectl describe service frontend -n pyairtable

# Verify NodePort is accessible
minikube service frontend --url -p pyairtable -n pyairtable
```

#### API Gateway Connection Issues
```bash
# Check API gateway connectivity
kubectl exec deployment/frontend -n pyairtable -- \
  curl http://api-gateway:8000/health

# Verify environment variables
kubectl exec deployment/frontend -n pyairtable -- env | grep API
```

## Service-Specific Issues

### API Gateway Issues

**Common Problems:**
- Rate limiting errors
- Authentication failures
- Upstream service timeouts

**Diagnostic Commands:**
```bash
# Check API Gateway logs
kubectl logs deployment/api-gateway -n pyairtable --tail=100

# Test direct API calls
kubectl port-forward service/api-gateway 8000:8000 -n pyairtable &
curl http://localhost:8000/health
```

**Solutions:**
```bash
# Increase timeout values
kubectl patch deployment api-gateway -n pyairtable -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"api-gateway","env":[{"name":"TIMEOUT","value":"60s"}]}]}}}}'

# Check authentication configuration
kubectl exec deployment/api-gateway -n pyairtable -- env | grep API_KEY
```

### LLM Orchestrator Issues

**Common Problems:**
- Gemini API connection failures
- Token budget exceeded
- Memory leaks during processing

**Diagnostic Commands:**
```bash
# Check LLM Orchestrator logs
kubectl logs deployment/llm-orchestrator -n pyairtable --tail=100

# Check API key configuration
kubectl get secret pyairtable-secrets -n pyairtable -o jsonpath='{.data.gemini-api-key}' | base64 -d
```

**Solutions:**
```bash
# Update Gemini API key
./scripts/secrets-manager.sh update gemini-api-key "your-new-api-key"

# Reduce thinking budget
./scripts/secrets-manager.sh update thinking-budget "500"

# Restart with fresh memory
kubectl rollout restart deployment/llm-orchestrator -n pyairtable
```

### Database Services Issues

**PostgreSQL Issues:**
```bash
# Check PostgreSQL configuration
kubectl logs deployment/postgres -n pyairtable | grep -i error

# Check disk space
kubectl exec deployment/postgres -n pyairtable -- df -h

# Check database connections
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"
```

**Redis Issues:**
```bash
# Check Redis memory usage
kubectl exec deployment/redis -n pyairtable -- redis-cli info memory

# Check Redis connectivity
kubectl exec deployment/redis -n pyairtable -- redis-cli ping

# Check Redis logs
kubectl logs deployment/redis -n pyairtable --tail=50
```

## Infrastructure Issues

### Minikube Issues

**Cluster Won't Start:**
```bash
# Check Minikube status
minikube status -p pyairtable

# Check system resources
free -h  # Linux
vm_stat | head -10  # macOS

# Clean restart
minikube delete -p pyairtable
./scripts/minikube-setup.sh
```

**Docker Issues:**
```bash
# Check Docker daemon
docker info

# Check Minikube Docker environment
eval $(minikube docker-env -p pyairtable)
docker images | grep pyairtable
```

### Storage Issues

**Persistent Volume Problems:**
```bash
# Check PVC status
kubectl get pvc -n pyairtable

# Check storage classes
kubectl get storageclass

# Check volume usage
kubectl exec deployment/postgres -n pyairtable -- df -h /var/lib/postgresql/data
```

**Solutions:**
```bash
# Recreate PVC (WARNING: destroys data)
kubectl delete pvc postgres-data -n pyairtable
kubectl apply -f k8s/postgres-deployment.yaml -n pyairtable

# Clean up unused volumes
minikube ssh -p pyairtable "docker system prune -f"
```

### Networking Issues

**Ingress Controller Problems:**
```bash
# Check ingress controller status
kubectl get pods -n ingress-nginx

# Check ingress rules
kubectl get ingress -n pyairtable

# Test ingress connectivity
curl -H "Host: pyairtable.local" http://$(minikube ip -p pyairtable)
```

## Performance Issues

### Slow Response Times

**Diagnostic Steps:**
```bash
# Check resource usage
kubectl top pods -n pyairtable

# Check service response times
time curl http://$(minikube ip -p pyairtable):30800/health

# Monitor database performance
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -d pyairtable -c "SELECT * FROM pg_stat_activity WHERE state = 'active';"
```

**Optimization:**
```bash
# Enable database query optimization
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -d pyairtable -c "ANALYZE;"

# Optimize log levels
./scripts/secrets-manager.sh update log-level "error"

# Use resource-optimized values
helm upgrade pyairtable-stack k8s/helm/pyairtable-stack \
  --values k8s/values-local-optimized.yaml \
  --namespace pyairtable
```

### High Memory Usage

**Memory Optimization:**
```bash
# Identify memory-hungry pods
kubectl top pods -n pyairtable --sort-by=memory

# Reduce PostgreSQL memory
kubectl patch configmap postgres-config -n pyairtable -p \
  '{"data":{"shared_buffers":"32MB","work_mem":"1MB"}}'

# Restart services with new limits
kubectl rollout restart deployment/postgres -n pyairtable
```

## Advanced Debugging

### Deep Log Analysis

```bash
# Search for specific error patterns
./scripts/logs-aggregator.sh search "timeout\|connection.*failed\|out of memory" all 100

# Export logs for analysis
./scripts/logs-aggregator.sh export all json debug-logs-$(date +%Y%m%d).json

# Real-time error monitoring
./scripts/logs-aggregator.sh stream | grep -i error
```

### Network Debugging

```bash
# Test inter-service connectivity
kubectl run debug-pod --image=nicolaka/netshoot -n pyairtable --rm -it

# From debug pod, test connectivity:
# nslookup postgres
# curl http://api-gateway:8000/health
# nc -zv postgres 5432
```

### Database Debugging

```bash
# Enable query logging
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -c "ALTER SYSTEM SET log_statement = 'all';"

# Check slow queries
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -d pyairtable -c "SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"

# Monitor connections
watch kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -c "SELECT count(*),state FROM pg_stat_activity GROUP BY state;"
```

## Recovery Procedures

### Service Recovery

```bash
# Restart single service
kubectl rollout restart deployment/<service-name> -n pyairtable

# Restart all services
for svc in api-gateway llm-orchestrator mcp-server airtable-gateway platform-services automation-services saga-orchestrator frontend; do
  kubectl rollout restart deployment/$svc -n pyairtable
done

# Wait for rollout completion
kubectl rollout status deployment/<service-name> -n pyairtable
```

### Database Recovery

```bash
# Backup current database
./scripts/database-init.sh backup

# Restore from backup
./scripts/database-init.sh restore <backup-file>

# Complete database reset (if backup unavailable)
./scripts/database-init.sh reset
./scripts/database-init.sh init
```

### Complete System Recovery

```bash
# Stop all services gracefully
kubectl scale deployment --all --replicas=0 -n pyairtable

# Clean up resources
kubectl delete pods --all -n pyairtable
kubectl delete pvc --all -n pyairtable

# Restart cluster
minikube stop -p pyairtable
minikube start -p pyairtable

# Redeploy everything
./scripts/deploy-local-complete.sh
```

### Emergency Procedures

```bash
# Complete cluster reset (nuclear option)
minikube delete -p pyairtable
./scripts/minikube-setup.sh
./scripts/secrets-manager.sh generate
./scripts/secrets-manager.sh apply
./scripts/deploy-local-complete.sh

# Quick service restart (when debugging issues)
kubectl delete pods --all -n pyairtable
# Pods will be recreated automatically by deployments
```

### Data Recovery

```bash
# Export critical data before reset
kubectl exec deployment/postgres -n pyairtable -- \
  pg_dump -U postgres pyairtable > backup-$(date +%Y%m%d).sql

# Export user data
kubectl exec deployment/postgres -n pyairtable -- \
  psql -U postgres -d pyairtable -c "COPY auth.users TO STDOUT CSV HEADER;" > users-backup.csv
```

## Prevention Best Practices

### Regular Maintenance

```bash
# Weekly health check
./scripts/health-monitor.sh check > health-report-$(date +%Y%m%d).txt

# Weekly log cleanup
./scripts/logs-aggregator.sh cleanup 7

# Monthly secret rotation
./scripts/secrets-manager.sh rotate all
```

### Monitoring Setup

```bash
# Enable continuous health monitoring
./scripts/health-monitor.sh monitor > monitoring.log 2>&1 &

# Setup log aggregation
./scripts/logs-aggregator.sh setup
./scripts/logs-aggregator.sh stream > aggregated.log 2>&1 &
```

### Resource Management

```bash
# Monitor resource usage trends
kubectl top pods -n pyairtable > resource-usage-$(date +%Y%m%d).log

# Regular cleanup
minikube ssh -p pyairtable "docker system prune -f"
kubectl delete events --all -n pyairtable
```

## Getting Additional Help

### Diagnostic Information Collection

```bash
# Generate comprehensive diagnostic report
{
  echo "=== System Information ==="
  uname -a
  echo ""
  
  echo "=== Minikube Status ==="
  minikube status -p pyairtable
  echo ""
  
  echo "=== Kubernetes Resources ==="
  kubectl get all -n pyairtable
  echo ""
  
  echo "=== Recent Events ==="
  kubectl get events -n pyairtable --sort-by='.lastTimestamp' | tail -20
  echo ""
  
  echo "=== Resource Usage ==="
  kubectl top pods -n pyairtable 2>/dev/null || echo "Metrics not available"
  echo ""
  
  echo "=== Service Health ==="
  ./scripts/health-monitor.sh check
  echo ""
  
  echo "=== Recent Errors ==="
  ./scripts/logs-aggregator.sh search "error" all 10
  
} > diagnostic-report-$(date +%Y%m%d_%H%M%S).txt

echo "Diagnostic report generated: diagnostic-report-$(date +%Y%m%d_%H%M%S).txt"
```

### Log Collection for Support

```bash
# Export all logs
./scripts/logs-aggregator.sh export all json support-logs-$(date +%Y%m%d).json

# Export configuration
kubectl get configmaps -n pyairtable -o yaml > configmaps-$(date +%Y%m%d).yaml
kubectl get secrets -n pyairtable -o yaml > secrets-$(date +%Y%m%d).yaml
```

---

**Remember**: Always backup your data before attempting major recovery procedures. When in doubt, use the complete system recovery procedure to get back to a known good state.