# High Error Rate Runbook

## Alert: HighErrorRate

**Severity:** Critical  
**Category:** Performance  
**Expected Response Time:** < 10 minutes

## Overview

This runbook provides procedures for investigating and resolving high error rates (>5%) in PyAirtable services.

## Immediate Actions (First 10 minutes)

### 1. Acknowledge and Assess
- [ ] Acknowledge the alert
- [ ] Identify affected service from alert labels
- [ ] Check current error rate in Grafana dashboard
- [ ] Determine if error rate is increasing or stable

### 2. Quick Impact Assessment
```bash
# Check current error metrics
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(http_requests_total{status=~\"5..\"}[5m])"

# Check affected endpoints
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(http_requests_total{status=~\"5..\"}[5m]) by (endpoint)"

# Check error types
docker-compose -f docker-compose.production.yml logs --tail=100 <service-name> | grep -i error
```

## Investigation Steps (10-20 minutes)

### 3. Error Analysis

#### Identify Error Patterns
```bash
# Get recent error logs
docker-compose -f docker-compose.production.yml logs --since=30m <service-name> | grep -E "(ERROR|CRITICAL|5[0-9][0-9])"

# Check error distribution by endpoint
curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"pyairtable-apps\",service=\"<service-name>\"} |= \"ERROR\"" | jq .

# Analyze error trends
curl -s "http://localhost:8080/prometheus/api/v1/query_range?query=rate(http_requests_total{status=~\"5..\"}[5m])&start=$(date -d '1 hour ago' -u +%s)&end=$(date -u +%s)&step=60"
```

#### Common Error Types

##### Database Errors
**Symptoms:**
- Connection timeout errors
- Query timeout errors
- Database connection pool exhausted

**Investigation:**
```bash
# Check database connections
docker exec -it postgres-prod psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Check slow queries
docker exec -it postgres-prod psql -U postgres -c "SELECT query, query_start, now() - query_start AS duration FROM pg_stat_activity WHERE state = 'active' ORDER BY duration DESC;"

# Check database locks
docker exec -it postgres-prod psql -U postgres -c "SELECT blocked_locks.pid AS blocked_pid, blocked_activity.usename AS blocked_user, blocking_locks.pid AS blocking_pid, blocking_activity.usename AS blocking_user, blocked_activity.query AS blocked_statement, blocking_activity.query AS current_statement_in_blocking_process FROM pg_catalog.pg_locks blocked_locks JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid AND blocking_locks.pid != blocked_locks.pid JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid WHERE NOT blocked_locks.GRANTED;"
```

##### External API Errors
**Symptoms:**
- Timeout errors from external services
- Rate limiting responses (429)
- Authentication failures

**Investigation:**
```bash
# Check Airtable API status
curl -I https://api.airtable.com/v0/meta/whoami

# Check rate limiting
grep -i "rate limit" /opt/pyairtable/monitoring/data/*/logs/*.log

# Check API response times
curl -w "@curl-format.txt" -o /dev/null -s https://api.airtable.com/v0/meta/whoami
```

##### Memory/Resource Errors
**Symptoms:**
- Out of memory errors
- CPU throttling
- Container restarts

**Investigation:**
```bash
# Check container resource usage
docker stats --no-stream <container-name>

# Check memory leaks
docker exec -it <container-name> ps aux --sort=-%mem | head -10

# Check file descriptor limits
docker exec -it <container-name> ls -la /proc/self/fd | wc -l
```

### 4. Service-Specific Debugging

#### API Gateway Errors
```bash
# Check gateway routing
curl -v http://localhost:8080/api/v1/health

# Check upstream services
for service in ai airtable automation platform; do
  echo "Checking $service:"
  curl -f http://pyairtable-$service:8080/health || echo "FAILED"
done

# Check load balancer status
docker exec -it pyairtable-gateway nginx -t
```

#### AI Service Errors
```bash
# Check LLM API connectivity
curl -I https://api.openai.com/v1/models

# Check token usage and limits
grep -i "token" /opt/pyairtable/monitoring/data/*/logs/*ai*.log | tail -20

# Check model availability
curl -s "http://localhost:8080/prometheus/api/v1/query?query=pyairtable_llm_requests_total"
```

#### Airtable Service Errors
```bash
# Check Airtable API rate limits
curl -I -H "Authorization: Bearer $AIRTABLE_API_KEY" https://api.airtable.com/v0/meta/whoami

# Check base access permissions
curl -H "Authorization: Bearer $AIRTABLE_API_KEY" https://api.airtable.com/v0/meta/bases

# Check webhook delivery
grep -i "webhook" /opt/pyairtable/monitoring/data/*/logs/*airtable*.log | tail -10
```

## Resolution Procedures (20-40 minutes)

### 5. Error-Specific Solutions

#### Database Connection Issues
```bash
# Restart database connections
docker-compose -f docker-compose.production.yml restart <service-name>

# Increase connection pool if needed
# Edit docker-compose.yml to increase database connection limits

# Clear connection pool
docker exec -it postgres-prod psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND state_change < now() - interval '30 minutes';"
```

#### Rate Limiting Issues
```bash
# Implement exponential backoff
# Check service configuration for retry policies

# Add circuit breaker if not present
# Temporarily reduce request rate

# Contact external service provider if needed
```

#### Resource Exhaustion
```bash
# Scale service horizontally
docker-compose -f docker-compose.production.yml up -d --scale <service-name>=3

# Increase resource limits
# Edit docker-compose.yml to increase memory/CPU limits

# Clear caches if applicable
docker exec -it redis-prod redis-cli FLUSHDB
```

### 6. Traffic Management

#### Load Shedding
```bash
# Enable rate limiting at gateway level
# Add temporary rate limits to reduce load

# Implement priority queuing
# Prioritize critical requests over non-critical ones

# Enable graceful degradation
# Disable non-essential features temporarily
```

#### Circuit Breaker Activation
```bash
# Check circuit breaker status
curl http://localhost:8080/api/v1/circuit-breaker/status

# Manually open circuit breaker if needed
curl -X POST http://localhost:8080/api/v1/circuit-breaker/open

# Monitor recovery metrics
curl http://localhost:8080/api/v1/circuit-breaker/metrics
```

## Verification Steps

### 7. Error Rate Monitoring
```bash
# Monitor error rate reduction
watch 'curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(http_requests_total{status=~\"5..\"}[5m])" | jq ".data.result[0].value[1]"'

# Check response time improvement  
curl -s "http://localhost:8080/prometheus/api/v1/query?query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"

# Verify service health
for endpoint in /health /ready /metrics; do
  curl -f http://localhost:8080$endpoint && echo " - $endpoint OK" || echo " - $endpoint FAILED"
done
```

### 8. User Impact Assessment
```bash
# Check active user metrics
curl -s "http://localhost:8080/prometheus/api/v1/query?query=pyairtable_active_users_total"

# Monitor user session errors
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"session_error\""

# Check business metric impact
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_workflow_executions_total{status=\"failed\"}[5m])"
```

## Communication

### 9. Status Updates

#### High Error Rate Template
```markdown
**Error Rate Incident - [SERVICE_NAME]**

Current Status: [INVESTIGATING/MITIGATING/RESOLVED]
Error Rate: [X%] (threshold: 5%)
Affected Endpoints: [List of endpoints]
Impact: [Description of user impact]

Root Cause: [Brief description if identified]
Mitigation: [Actions being taken]

ETA for Resolution: [Time estimate]
Next Update: [When next update will be provided]
```

### 10. Customer Communication
- [ ] Assess if customer-facing impact requires notification
- [ ] Update status page if significant impact
- [ ] Prepare customer communication if error rate >10%

## Post-Incident Actions

### 11. Root Cause Analysis

#### Data Collection
```bash
# Export error logs for analysis
docker-compose -f docker-compose.production.yml logs --since=2h <service-name> > /tmp/error-analysis-$(date +%s).log

# Export metrics for the incident period
curl -s "http://localhost:8080/prometheus/api/v1/query_range?query=rate(http_requests_total[5m])&start=$START_TIME&end=$END_TIME&step=60" > /tmp/metrics-$(date +%s).json

# Generate incident timeline
./scripts/generate-incident-timeline.sh $START_TIME $END_TIME
```

#### Performance Analysis
- [ ] Identify bottlenecks in the request flow
- [ ] Analyze database query performance
- [ ] Review external API dependency performance  
- [ ] Check for memory leaks or resource exhaustion

### 12. Prevention Measures

#### Monitoring Improvements
```bash
# Add more granular error monitoring
# Update alert thresholds based on incident learnings
# Implement predictive alerting for error trends

# Add synthetic transaction monitoring
# Implement user journey monitoring
# Add business metric correlation
```

#### Code/Infrastructure Changes
- [ ] Implement better error handling
- [ ] Add circuit breakers where missing
- [ ] Improve retry logic with exponential backoff
- [ ] Add resource monitoring and auto-scaling
- [ ] Implement request queuing and load shedding

## Related Runbooks
- [Service Down Runbook](service-down.md)
- [High Latency Runbook](high-latency.md)
- [Database Issues Runbook](database-issues.md)
- [External API Issues Runbook](external-api-issues.md)

## Metrics and Alerts

### Key Metrics to Monitor
- Error rate by service and endpoint
- Request volume and patterns
- Response time percentiles
- Database connection pool usage
- External API response times
- Resource utilization (CPU, memory, disk)

### Alert Tuning
- Consider adjusting error rate threshold based on service criticality
- Implement different thresholds for different times of day
- Add alert fatigue reduction measures

---
**Last Updated:** [DATE]  
**Next Review:** [DATE + 3 months]