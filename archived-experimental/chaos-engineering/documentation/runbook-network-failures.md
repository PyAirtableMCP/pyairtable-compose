# Network Failure Scenarios - Runbook

## Overview

This runbook covers procedures for handling network-related failures in the PyAirtable platform during chaos engineering experiments.

## Network Failure Types

### 1. Network Latency Injection

**Scenario**: Artificial latency added to network communication
**Impact**: Increased response times, potential timeouts
**Expected Recovery**: Immediate after experiment ends

#### Detection

```bash
# Check network policies
kubectl get networkpolicies -n pyairtable

# Monitor response times
curl -w "Total time: %{time_total}s\n" -s -o /dev/null \
  http://api-gateway.pyairtable.svc.cluster.local:8080/health

# Check active chaos experiments
kubectl get networkchaos -n chaos-engineering
```

#### Expected System Behavior

- **Timeouts**: Services should implement proper timeout handling
- **Circuit Breakers**: Should activate when latency exceeds thresholds
- **Retries**: Should use exponential backoff
- **Graceful Degradation**: Non-critical features should degrade gracefully

#### Monitoring During Latency Injection

```bash
# Monitor response times continuously
while true; do
  start=$(date +%s%N)
  curl -f -m 10 http://api-gateway.pyairtable.svc.cluster.local:8080/health >/dev/null 2>&1
  end=$(date +%s%N)
  duration=$(( (end - start) / 1000000 ))
  echo "$(date): Response time: ${duration}ms"
  sleep 5
done
```

#### Recovery Actions

Network latency should resolve automatically when experiment ends. If issues persist:

```bash
# Check for remaining network chaos
kubectl get networkchaos -n chaos-engineering

# Force cleanup
kubectl delete networkchaos --all -n chaos-engineering

# Restart affected pods if needed
kubectl rollout restart deployment/api-gateway -n pyairtable
```

### 2. Network Partition

**Scenario**: Network communication blocked between services
**Impact**: Services cannot communicate with each other
**Expected Recovery**: 1-2 minutes after partition ends

#### Detection

```bash
# Check network chaos experiments
kubectl get networkchaos -n chaos-engineering -o wide

# Test service connectivity
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=api-gateway -o jsonpath='{.items[0].metadata.name}') -- \
  curl -f -m 5 http://auth-service.pyairtable.svc.cluster.local:8081/health
```

#### Expected System Behavior

- **Service Isolation**: Partitioned services should operate independently
- **Cached Data**: Services should use cached data when available
- **Circuit Breakers**: Should open immediately for partitioned services
- **Fallback Mechanisms**: Should activate for unavailable dependencies

#### Monitoring Network Partitions

```bash
# Monitor service connectivity matrix
services=("api-gateway" "auth-service" "platform-services")

for source in "${services[@]}"; do
  echo "Testing connectivity from $source:"
  for target in "${services[@]}"; do
    if [ "$source" != "$target" ]; then
      kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=$source -o jsonpath='{.items[0].metadata.name}') -- \
        curl -f -m 3 http://$target.pyairtable.svc.cluster.local:8080/health >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "  ✅ $source -> $target: Connected"
      else
        echo "  ❌ $source -> $target: Partitioned"
      fi
    fi
  done
done
```

### 3. Packet Loss

**Scenario**: Random packet loss on network communication
**Impact**: Intermittent connection failures, retransmissions
**Expected Recovery**: Immediate after experiment ends

#### Detection

```bash
# Check packet loss chaos experiments
kubectl get networkchaos -n chaos-engineering

# Monitor connection success rate
success=0
total=20
for i in $(seq 1 $total); do
  if curl -f -m 5 http://api-gateway.pyairtable.svc.cluster.local:8080/health >/dev/null 2>&1; then
    ((success++))
  fi
  sleep 1
done
echo "Success rate: $(( success * 100 / total ))%"
```

#### Expected System Behavior

- **Retry Logic**: Should handle transient failures
- **Connection Pooling**: Should maintain healthy connections
- **Error Handling**: Should distinguish between transient and permanent failures

### 4. DNS Resolution Failures

**Scenario**: DNS resolution fails for service discovery
**Impact**: Services cannot resolve each other's addresses
**Expected Recovery**: Immediate after DNS is restored

#### Detection

```bash
# Test DNS resolution
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=api-gateway -o jsonpath='{.items[0].metadata.name}') -- \
  nslookup auth-service.pyairtable.svc.cluster.local

# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

#### Recovery Actions

```bash
# Restart CoreDNS if needed
kubectl rollout restart deployment/coredns -n kube-system

# Flush DNS cache in affected pods
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=api-gateway -o jsonpath='{.items[0].metadata.name}') -- \
  nscd -i hosts 2>/dev/null || true
```

## General Network Troubleshooting

### Network Policy Issues

```bash
# List all network policies
kubectl get networkpolicies -A

# Check if policies are blocking traffic
kubectl describe networkpolicy -n pyairtable

# Test connectivity with netshoot
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- /bin/bash
```

### Service Discovery Problems

```bash
# Check service endpoints
kubectl get endpoints -n pyairtable

# Verify service selectors
kubectl describe service -n pyairtable

# Check pod labels
kubectl get pods -n pyairtable --show-labels
```

### Network Performance Issues

```bash
# Test bandwidth between pods
kubectl run iperf-server --image=networkstatic/iperf3 -- iperf3 -s
kubectl run iperf-client --rm -it --image=networkstatic/iperf3 -- iperf3 -c iperf-server
```

## Monitoring and Alerting

### Key Network Metrics

- Connection success rate: `probe_success{job="blackbox"}`
- DNS resolution time: `probe_dns_lookup_time_seconds`
- Network latency: `probe_duration_seconds`
- TCP connection time: `probe_tcp_duration_seconds`

### Critical Alerts

1. **High Network Latency**
   ```yaml
   alert: HighNetworkLatency
   expr: probe_duration_seconds > 1
   for: 2m
   ```

2. **Service Unreachable**
   ```yaml
   alert: ServiceUnreachable
   expr: probe_success == 0
   for: 30s
   ```

3. **DNS Resolution Failure**
   ```yaml
   alert: DNSResolutionFailure
   expr: probe_dns_lookup_time_seconds > 5
   for: 1m
   ```

## Recovery Procedures

### Immediate Actions

1. **Stop Network Chaos**
   ```bash
   kubectl delete networkchaos --all -n chaos-engineering
   ```

2. **Verify Network Connectivity**
   ```bash
   # Test all service interconnectivity
   ./test-service-connectivity.sh
   ```

3. **Check for Residual Effects**
   ```bash
   # Look for stuck connections
   kubectl exec -n pyairtable -it <pod> -- netstat -an | grep CLOSE_WAIT
   ```

### Service-Specific Recovery

#### API Gateway Network Issues

```bash
# Restart nginx/envoy proxy
kubectl rollout restart deployment/api-gateway -n pyairtable

# Clear connection pools
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=api-gateway -o jsonpath='{.items[0].metadata.name}') -- \
  pkill -HUP nginx
```

#### Database Connection Issues

```bash
# Check database connection pool
kubectl exec -n pyairtable -it $(kubectl get pods -n pyairtable -l app=platform-services -o jsonpath='{.items[0].metadata.name}') -- \
  curl localhost:8000/debug/db-pool-status

# Restart services to reset connection pools
kubectl rollout restart deployment/platform-services -n pyairtable
```

## Validation After Recovery

### Connectivity Matrix Test

```bash
#!/bin/bash
# test-service-connectivity.sh

services=("api-gateway:8080" "auth-service:8081" "platform-services:8000")
echo "🔗 Testing service connectivity matrix"

for source_service in "${services[@]}"; do
  IFS=':' read -r source_name source_port <<< "$source_service"
  source_pod=$(kubectl get pods -n pyairtable -l app=$source_name -o jsonpath='{.items[0].metadata.name}')
  
  echo "From $source_name:"
  for target_service in "${services[@]}"; do
    IFS=':' read -r target_name target_port <<< "$target_service"
    
    if [ "$source_name" != "$target_name" ]; then
      if kubectl exec -n pyairtable $source_pod -- curl -f -m 5 http://$target_name.pyairtable.svc.cluster.local:$target_port/health >/dev/null 2>&1; then
        echo "  ✅ -> $target_name: OK"
      else
        echo "  ❌ -> $target_name: FAILED"
      fi
    fi
  done
done
```

### Performance Validation

```bash
# Test response times post-recovery
echo "📊 Performance validation"
for i in {1..10}; do
  start=$(date +%s%N)
  curl -f -m 5 http://api-gateway.pyairtable.svc.cluster.local:8080/health >/dev/null 2>&1
  end=$(date +%s%N)
  duration=$(( (end - start) / 1000000 ))
  echo "Test $i: ${duration}ms"
done
```

## Best Practices

### During Network Chaos Experiments

1. **Monitor Key Metrics**: Response times, error rates, connection counts
2. **Validate Failover**: Ensure services failover to healthy instances
3. **Check Circuit Breakers**: Verify they activate and recover properly
4. **Test Retry Logic**: Confirm exponential backoff is working

### Post-Experiment

1. **Verify Clean State**: Ensure no residual network policies exist
2. **Check Connection Pools**: Verify healthy connection pool state
3. **Monitor for Delayed Effects**: Some issues may appear after chaos ends
4. **Update Documentation**: Record any unexpected behaviors

## Emergency Contacts

- **Network Team**: network-ops@company.com  
- **Platform SRE**: sre-platform@company.com
- **On-Call**: PagerDuty escalation

## Related Runbooks

- [Pod Failure Runbook](runbook-pod-failures.md)
- [Database Failure Runbook](runbook-database-failures.md)
- [Emergency Procedures](runbook-emergency-procedures.md)