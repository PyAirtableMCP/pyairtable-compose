# PyAirtable Production Monitoring Runbooks

This directory contains operational runbooks for responding to production incidents and alerts in the PyAirtable platform.

## Quick Reference

### Critical Alerts (Response Time < 5 minutes)
- [Service Down](service-down.md) - When services are completely unavailable
- [Security Incident](security-incident.md) - Unauthorized access, data breaches, suspicious activity

### High Priority Alerts (Response Time < 10 minutes)  
- [High Error Rate](high-error-rate.md) - When error rates exceed 5%
- [High LLM Costs](high-llm-costs.md) - When LLM costs exceed budget thresholds

### Medium Priority Alerts (Response Time < 30 minutes)
- [Performance Degradation](performance-degradation.md) - Slow response times, high latency
- [Infrastructure Issues](infrastructure-issues.md) - CPU, memory, disk space issues
- [Database Issues](database-issues.md) - Database connectivity, performance problems

## Runbook Structure

Each runbook follows a standardized structure:

1. **Alert Information** - Severity, category, expected response time
2. **Overview** - Brief description of the issue and impact
3. **Immediate Actions** - First steps to take (5-15 minutes)
4. **Investigation Steps** - Detailed troubleshooting procedures  
5. **Resolution Procedures** - Step-by-step remediation
6. **Verification Steps** - How to confirm the issue is resolved
7. **Communication** - Internal and external communication templates
8. **Post-Incident Actions** - Cleanup, documentation, prevention

## Alert Severity Levels

### Critical (Red)
- **Response Time:** < 5 minutes
- **Escalation:** Immediate PagerDuty notification
- **Examples:** Service down, security breach, data corruption
- **Communication:** Slack #alerts-critical, immediate management notification

### Warning (Yellow)  
- **Response Time:** < 30 minutes
- **Escalation:** Slack notification, PagerDuty if unresolved in 1 hour
- **Examples:** High latency, resource constraints, business metric anomalies
- **Communication:** Slack #alerts-warnings, team notification

### Info (Blue)
- **Response Time:** < 2 hours  
- **Escalation:** Slack notification only
- **Examples:** Maintenance reminders, capacity planning alerts
- **Communication:** Slack #alerts-info

## Common Commands

### Health Checks
```bash
# Check all services
docker-compose -f docker-compose.production.yml ps

# Test API endpoints
curl -f http://localhost:8080/health

# Check database connectivity
docker exec -it postgres-prod psql -U postgres -c "SELECT 1;"
```

### Log Analysis
```bash
# View recent logs for a service
docker-compose -f docker-compose.production.yml logs --tail=100 <service-name>

# Search logs for errors
docker-compose -f docker-compose.production.yml logs --since=1h | grep -i error

# Query structured logs in Loki
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"ERROR\""
```

### Metrics Queries
```bash
# Check error rate
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(http_requests_total{status=~\"5..\"}[5m])"

# Check response time  
curl -s "http://localhost:8080/prometheus/api/v1/query?query=histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"

# Check resource usage
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(container_cpu_usage_seconds_total[5m])*100"
```

## Emergency Procedures

### Service Restart
```bash
# Restart specific service
docker-compose -f docker-compose.production.yml restart <service-name>

# Force recreate service
docker-compose -f docker-compose.production.yml up -d --force-recreate <service-name>

# Restart entire stack (use with caution)
docker-compose -f docker-compose.production.yml restart
```

### Emergency Contacts

#### Internal Team
- **On-Call Engineer:** [Contact Info]
- **Engineering Lead:** [Contact Info] 
- **Platform Team Lead:** [Contact Info]
- **CTO:** [Contact Info]

#### External Services
- **PagerDuty:** +1-844-732-3773
- **AWS Support:** [Account-specific number]
- **Airtable Support:** support@airtable.com

### Escalation Matrix

| Time | Action | Contact |
|------|--------|---------|
| 0-5 min | Acknowledge alert | On-call engineer |
| 15 min | Status update | Team lead |
| 30 min | Escalate if unresolved | Engineering manager |
| 1 hour | Executive notification | CTO |
| 2 hours | Customer communication | CEO/CMO |

## Monitoring Dashboards

### Grafana Dashboards
- **Service Health Overview:** http://localhost:3000/d/pyairtable-service-health
- **Business Metrics:** http://localhost:3000/d/pyairtable-business-metrics  
- **Cost Tracking:** http://localhost:3000/d/pyairtable-cost-tracking
- **Infrastructure Overview:** http://localhost:3000/d/pyairtable-infrastructure

### Alert Management
- **AlertManager:** http://localhost:9093
- **Slack Integration:** #alerts-critical, #alerts-warnings
- **PagerDuty:** [Service URL]

## Tools and Scripts

### Deployment Scripts
- `deploy-production-monitoring.sh` - Deploy LGTM stack
- `backup-monitoring-data.sh` - Backup monitoring data
- `restore-monitoring-data.sh` - Restore from backup

### Integration Scripts  
- `setup-slack-integration.sh` - Configure Slack notifications
- `setup-pagerduty-integration.sh` - Configure PagerDuty escalation
- `test-alerting.sh` - Test alert delivery

### Troubleshooting Scripts
- `health-check.sh` - Comprehensive health check
- `collect-diagnostics.sh` - Gather diagnostic information
- `analyze-performance.sh` - Performance analysis

## Best Practices

### During Incidents
1. **Stay Calm** - Panic leads to mistakes
2. **Follow the Runbook** - Don't skip steps
3. **Document Everything** - Timeline, actions, observations
4. **Communicate Regularly** - Keep stakeholders informed
5. **Focus on Recovery** - Investigation comes after service restoration

### Post-Incident
1. **Conduct Blameless Post-Mortem** - Focus on process, not people
2. **Update Runbooks** - Incorporate lessons learned
3. **Improve Monitoring** - Add alerts based on blind spots discovered
4. **Share Knowledge** - Document findings for the team

### Preventive Measures
1. **Regular Drills** - Practice incident response procedures
2. **Monitoring Reviews** - Regularly review and tune alerts
3. **Capacity Planning** - Proactive resource management
4. **Security Audits** - Regular security assessments

## Training and Onboarding

### New Team Members
1. Review all runbooks
2. Practice with staging environment
3. Shadow experienced engineer during on-call
4. Complete incident response training

### Regular Training
- Monthly runbook reviews
- Quarterly incident response drills
- Annual security training
- Tool-specific training as needed

## Runbook Maintenance

### Review Schedule
- **Monthly:** Review recent incidents and update procedures
- **Quarterly:** Full runbook review and testing
- **Annually:** Complete overhaul and reorganization

### Version Control
- All runbooks are version controlled
- Changes require peer review
- Major changes require team approval

### Feedback Loop
- Collect feedback after each incident
- Regular team retrospectives on runbook effectiveness
- Continuous improvement based on real-world usage

---

## Quick Links

- [Service Down Runbook](service-down.md)
- [High Error Rate Runbook](high-error-rate.md)  
- [High LLM Costs Runbook](high-llm-costs.md)
- [Security Incident Runbook](security-incident.md)
- [Emergency Contacts](emergency-contacts.md)
- [Escalation Procedures](escalation-procedures.md)

**For immediate assistance during a critical incident, contact the on-call engineer via PagerDuty or Slack #alerts-critical**