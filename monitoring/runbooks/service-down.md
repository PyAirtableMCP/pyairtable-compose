# Service Down Runbook

## Alert: ServiceDown

**Severity:** Critical  
**Category:** Service Health  
**Expected Response Time:** < 5 minutes

## Overview

This runbook provides step-by-step procedures for responding to service downtime alerts in the PyAirtable platform.

## Immediate Actions (First 5 minutes)

### 1. Acknowledge the Alert
- [ ] Acknowledge the alert in Slack (#alerts-critical)
- [ ] Update incident status in PagerDuty if applicable
- [ ] Notify team lead if not already aware

### 2. Quick Status Check
```bash
# Check service status
docker-compose -f docker-compose.production.yml ps

# Check logs for the affected service
docker-compose -f docker-compose.production.yml logs --tail=100 <service-name>

# Check system resources
htop
df -h
free -h
```

### 3. Initial Triage
- [ ] Identify which service is down from the alert
- [ ] Check if multiple services are affected
- [ ] Verify external dependencies (database, external APIs)

## Investigation Steps (5-15 minutes)

### 4. Deep Dive Analysis

#### Check Service Health
```bash
# Check if container is running
docker ps | grep <service-name>

# Check container resource usage
docker stats <container-id>

# Check container logs
docker logs --since=30m <container-id>
```

#### Check Dependencies
```bash
# Test database connectivity
docker exec -it postgres-prod psql -U postgres -c "SELECT 1;"

# Test Redis connectivity
docker exec -it redis-prod redis-cli ping

# Check external API status
curl -I https://api.airtable.com/v0/meta/whoami
```

#### Check Resource Constraints
```bash
# Check disk space
df -h /opt/pyairtable

# Check memory usage
free -h

# Check CPU usage
top

# Check network connectivity
netstat -tuln
```

### 5. Common Issues and Solutions

#### Issue: Container Not Running
**Symptoms:**
- Container status shows "Exited"
- Service not responding to health checks

**Solution:**
```bash
# Restart the service
docker-compose -f docker-compose.production.yml restart <service-name>

# If restart fails, check logs
docker-compose -f docker-compose.production.yml logs <service-name>

# Force recreate if necessary
docker-compose -f docker-compose.production.yml up -d --force-recreate <service-name>
```

#### Issue: Database Connection Failure
**Symptoms:**
- Database connection errors in logs
- Service unable to query database

**Solution:**
```bash
# Check database status
docker-compose -f docker-compose.production.yml ps postgres

# Check database logs
docker-compose -f docker-compose.production.yml logs postgres

# Test database connectivity
docker exec -it postgres-prod psql -U postgres -c "SELECT version();"

# Restart database if needed (CAUTION: This may cause data loss)
docker-compose -f docker-compose.production.yml restart postgres
```

#### Issue: Out of Memory (OOM)
**Symptoms:**
- Container killed by OOM killer
- Memory usage at 100%

**Solution:**
```bash
# Check memory usage
docker stats --no-stream

# Identify memory-intensive processes
docker exec -it <container-id> ps aux --sort=-%mem

# Restart service to free memory
docker-compose -f docker-compose.production.yml restart <service-name>

# Consider scaling up resources if persistent
```

#### Issue: Port Conflict
**Symptoms:**
- Service fails to bind to port
- "Port already in use" errors

**Solution:**
```bash
# Check what's using the port
sudo netstat -tulpn | grep <port>

# Kill conflicting process if safe
sudo kill -9 <pid>

# Restart service
docker-compose -f docker-compose.production.yml restart <service-name>
```

## Recovery Procedures (15-30 minutes)

### 6. Service Recovery

#### Standard Recovery
```bash
# Stop affected service
docker-compose -f docker-compose.production.yml stop <service-name>

# Pull latest image if needed
docker-compose -f docker-compose.production.yml pull <service-name>

# Start service
docker-compose -f docker-compose.production.yml up -d <service-name>

# Verify service is healthy
curl -f http://localhost:<port>/health
```

#### Full Stack Recovery
```bash
# If multiple services are affected
docker-compose -f docker-compose.production.yml down

# Clear any stuck containers
docker system prune -f

# Restart entire stack
docker-compose -f docker-compose.production.yml up -d

# Wait for services to be healthy
./scripts/health-check.sh
```

### 7. Data Recovery (if needed)

#### Database Recovery
```bash
# If database corruption is suspected
docker-compose -f docker-compose.production.yml stop postgres

# Backup current data
cp -r /opt/pyairtable/monitoring/data/postgres /opt/pyairtable/monitoring/backup/postgres-$(date +%s)

# Restore from latest backup
./backup-monitoring-data.sh restore

# Start database
docker-compose -f docker-compose.production.yml up -d postgres
```

## Verification Steps (5-10 minutes)

### 8. Health Checks

#### Service Health
```bash
# Check all services are running
docker-compose -f docker-compose.production.yml ps

# Verify health endpoints
curl http://localhost:8080/health  # API Gateway
curl http://localhost:3000/api/health  # Grafana
curl http://localhost:3100/ready  # Loki
curl http://localhost:3200/ready  # Tempo
```

#### Functional Testing
```bash
# Test API endpoints
curl -X GET http://localhost:8080/api/v1/status

# Test authentication
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test"}'

# Test database queries
docker exec -it postgres-prod psql -U postgres -c "SELECT COUNT(*) FROM users;"
```

#### Monitoring Verification
- [ ] Check Grafana dashboards are loading
- [ ] Verify metrics are being collected
- [ ] Confirm alerts are resolving
- [ ] Test log aggregation in Loki

## Communication

### 9. Status Updates

#### Internal Communication
```markdown
**Incident Update #X - [TIMESTAMP]**

Status: [INVESTIGATING/IDENTIFIED/MONITORING/RESOLVED]
Impact: [Service/Users affected]
Root Cause: [Brief description]
ETA: [Expected resolution time]
Next Update: [When next update will be provided]

Actions Taken:
- [List of actions taken]

Next Steps:
- [List of planned actions]
```

#### External Communication (if needed)
- [ ] Update status page if customer-facing
- [ ] Notify key stakeholders
- [ ] Prepare customer communication if needed

## Post-Incident Actions

### 10. Cleanup and Documentation

#### Immediate Cleanup
```bash
# Clean up temporary files
rm -rf /tmp/incident-*

# Clear Docker system if needed
docker system prune -f

# Restart log rotation
sudo logrotate -f /etc/logrotate.d/pyairtable-monitoring
```

#### Documentation
- [ ] Update incident log with timeline
- [ ] Document root cause analysis
- [ ] Create post-mortem if major incident
- [ ] Update runbooks with lessons learned

### 11. Prevention Measures

#### Monitoring Improvements
- [ ] Add additional health checks if needed
- [ ] Adjust alert thresholds based on incident
- [ ] Implement additional monitoring for root cause

#### Infrastructure Improvements
- [ ] Review resource allocation
- [ ] Implement additional redundancy
- [ ] Improve automated recovery procedures

## Escalation Procedures

### When to Escalate
- Service down > 30 minutes
- Data corruption suspected
- Security breach suspected
- Multiple critical services affected

### Escalation Contacts
1. **Engineering Lead:** [Contact Info]
2. **Platform Team Lead:** [Contact Info]  
3. **CTO:** [Contact Info]
4. **CEO (if customer-facing):** [Contact Info]

## Related Documentation
- [High Error Rate Runbook](high-error-rate.md)
- [Infrastructure Issues Runbook](infrastructure-issues.md)
- [Database Issues Runbook](database-issues.md)
- [Security Incident Runbook](security-incident.md)

## Revision History
- v1.0 - Initial version
- v1.1 - Added Docker-specific troubleshooting
- v1.2 - Enhanced communication procedures

---
**Last Updated:** [DATE]  
**Next Review:** [DATE + 3 months]