# Pod Failure Scenarios - Runbook

## Overview

This runbook covers procedures for handling pod failure scenarios in the PyAirtable platform during chaos engineering experiments.

## Failure Scenarios

### 1. API Gateway Pod Failure

**Scenario**: API Gateway pod is killed or becomes unresponsive
**Impact**: External API access is disrupted
**Expected Recovery Time**: 30-60 seconds

#### Detection

```bash
# Check pod status
kubectl get pods -n pyairtable -l app=api-gateway

# Check service endpoints
kubectl get endpoints -n pyairtable api-gateway

# Test health endpoint
curl -f http://api-gateway.pyairtable.svc.cluster.local:8080/health
```

#### Automatic Recovery

- Kubernetes will automatically restart the pod
- Load balancer will route traffic to healthy replicas
- Circuit breakers should prevent cascade failures

#### Manual Intervention (if needed)

```bash
# Force pod restart
kubectl delete pod -n pyairtable -l app=api-gateway

# Scale up replicas temporarily
kubectl scale deployment api-gateway -n pyairtable --replicas=3

# Check logs for issues
kubectl logs -n pyairtable -l app=api-gateway --tail=100
```

#### Validation

```bash
# Verify pod is running
kubectl get pods -n pyairtable -l app=api-gateway

# Test functionality
curl -f http://api-gateway.pyairtable.svc.cluster.local:8080/health
curl -f http://api-gateway.pyairtable.svc.cluster.local:8080/api/status
```

### 2. Auth Service Pod Failure

**Scenario**: Authentication service pod failure
**Impact**: New authentication requests fail, existing sessions may continue
**Expected Recovery Time**: 30-60 seconds

#### Detection

```bash
# Check auth service status
kubectl get pods -n pyairtable -l app=auth-service

# Test auth endpoint
curl -f http://auth-service.pyairtable.svc.cluster.local:8081/health
```

#### Expected Behavior

- Existing authenticated sessions should continue working
- New login attempts will fail temporarily
- Services should use cached authentication data
- Circuit breakers should activate for auth service calls

#### Recovery Actions

```bash
# Check if pod is restarting
kubectl describe pod -n pyairtable -l app=auth-service

# Force restart if stuck
kubectl delete pod -n pyairtable -l app=auth-service

# Verify database connectivity
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pg_isready
```

### 3. Platform Services Pod Failure

**Scenario**: Core platform services pod failure
**Impact**: Core business logic unavailable
**Expected Recovery Time**: 60-90 seconds

#### Detection

```bash
# Check platform services
kubectl get pods -n pyairtable -l app=platform-services

# Test platform health
curl -f http://platform-services.pyairtable.svc.cluster.local:8000/health
```

#### Recovery Actions

```bash
# Check for resource constraints
kubectl describe nodes
kubectl top nodes
kubectl top pods -n pyairtable

# Restart service if needed
kubectl rollout restart deployment/platform-services -n pyairtable

# Monitor rollout
kubectl rollout status deployment/platform-services -n pyairtable
```

### 4. Database Pod Failure

**Scenario**: PostgreSQL pod failure
**Impact**: Data access unavailable, potential data loss risk
**Expected Recovery Time**: 2-5 minutes

#### Detection

```bash
# Check database pod
kubectl get pods -n pyairtable -l app=postgres

# Test database connectivity  
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- pg_isready
```

#### Critical Actions

1. **Immediate Assessment**
   ```bash
   # Check if pod is restarting
   kubectl describe pod -n pyairtable -l app=postgres
   
   # Check persistent volume
   kubectl get pv,pvc -n pyairtable
   ```

2. **Data Integrity Check**
   ```bash
   # Once pod is running, check database integrity
   kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=postgres -o jsonpath='{.items[0].metadata.name}') -- psql -U postgres -c "SELECT datname FROM pg_database;"
   ```

3. **Service Recovery**
   ```bash
   # Restart dependent services after DB recovery
   kubectl rollout restart deployment/platform-services -n pyairtable
   kubectl rollout restart deployment/auth-service -n pyairtable
   ```

## General Recovery Procedures

### 1. Emergency Stop

If multiple pods are failing or system is unstable:

```bash
# Run emergency stop script
cd /path/to/chaos-engineering/safety
./emergency-stop.sh
```

### 2. Health Check Validation

After any pod recovery:

```bash
# Run comprehensive health check
cd /path/to/chaos-engineering/experiments
./health-check.sh post
```

### 3. Performance Validation

```bash
# Test response times
for i in {1..10}; do
  curl -w "Response time: %{time_total}s\n" -s -o /dev/null \
    http://api-gateway.pyairtable.svc.cluster.local:8080/health
  sleep 1
done
```

## Metrics and Monitoring

### Key Metrics to Monitor

- Pod restart count: `kube_pod_container_status_restarts_total`
- Pod ready status: `kube_pod_status_ready`
- Service availability: `up{job="pyairtable-services"}`
- Response times: `http_request_duration_seconds`
- Error rates: `http_requests_total{status=~"5.."}`

### Grafana Dashboards

- **PyAirtable Chaos Engineering Overview**: Monitor during experiments
- **Kubernetes Pod Status**: Track pod health and restarts
- **Application Performance**: Monitor response times and error rates

## Troubleshooting Guide

### Pod Stuck in Pending State

```bash
# Check resource availability
kubectl describe nodes

# Check pod events
kubectl describe pod -n pyairtable <pod-name>

# Check resource requests vs available
kubectl top nodes
```

### Pod Crash Loop

```bash
# Check pod logs
kubectl logs -n pyairtable <pod-name> --previous

# Check resource limits
kubectl describe pod -n pyairtable <pod-name>

# Check configuration
kubectl get configmaps,secrets -n pyairtable
```

### Service Unavailable After Pod Recovery

```bash
# Check service endpoints
kubectl get endpoints -n pyairtable

# Check service selector
kubectl describe service -n pyairtable <service-name>

# Verify pod labels
kubectl get pods -n pyairtable --show-labels
```

## Post-Incident Actions

1. **Document the incident**
   - Record timeline of events
   - Note any manual interventions required
   - Identify any unexpected behaviors

2. **Update monitoring**
   - Add alerts for any new failure modes discovered
   - Adjust thresholds based on observed behavior

3. **Improve automation**
   - Update automated recovery procedures
   - Enhance health checks based on learnings

4. **Team notification**
   - Share lessons learned with development team
   - Update operational procedures if needed

## Contact Information

- **Platform Team**: platform-team@company.com
- **SRE Team**: sre-team@company.com
- **On-call**: Use PagerDuty escalation policy

## Related Documents

- [Network Failure Runbook](runbook-network-failures.md)
- [Database Failure Runbook](runbook-database-failures.md)
- [Emergency Procedures](runbook-emergency-procedures.md)