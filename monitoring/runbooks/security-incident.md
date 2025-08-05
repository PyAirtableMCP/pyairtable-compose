# Security Incident Runbook

## Alert: UnauthorizedAccessAttempts / SuspiciousUserActivity / MultipleFailedLogins

**Severity:** Critical  
**Category:** Security  
**Expected Response Time:** < 5 minutes

## Overview

This runbook provides immediate response procedures for security incidents in the PyAirtable platform.

⚠️ **CRITICAL**: Security incidents require immediate action and may involve law enforcement. Follow all procedures carefully and document everything.

## Immediate Actions (First 5 minutes)

### 1. Alert Acknowledgment and Initial Assessment
- [ ] Acknowledge the security alert immediately
- [ ] **DO NOT** ignore or delay security alerts
- [ ] Notify security team lead immediately
- [ ] Begin incident documentation with timestamp

### 2. Quick Threat Assessment
```bash
# Check current failed login attempts
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_login_attempts_total{status=\"failed\"}[5m])"

# Identify source IPs
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"failed_login\" | json | line_format \"{{.source_ip}} {{.user_id}} {{.timestamp}}\""

# Check for successful logins from suspicious IPs
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"successful_login\" | json | line_format \"{{.source_ip}} {{.user_id}} {{.timestamp}}\""

# Check current active sessions
curl -s "http://localhost:8080/prometheus/api/v1/query?query=pyairtable_active_sessions_total"
```

### 3. Immediate Containment
```bash
# Block suspicious IP addresses (if identified)
curl -X POST http://localhost:8080/api/v1/security/block-ip \
  -H "Content-Type: application/json" \
  -d '{"ip_addresses": ["x.x.x.x"], "reason": "security_incident", "duration": "24h"}'

# Enable emergency security mode
curl -X POST http://localhost:8080/api/v1/security/emergency-mode \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "reason": "security_incident"}'

# Force MFA for all logins
curl -X POST http://localhost:8080/api/v1/security/force-mfa \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "duration": "24h"}'
```

## Investigation Phase (5-30 minutes)

### 4. Evidence Collection

#### System Logs Analysis
```bash
# Collect authentication logs
docker-compose -f docker-compose.production.yml logs --since=24h pyairtable-auth > /tmp/auth-logs-$(date +%s).log

# Collect API gateway logs
docker-compose -f docker-compose.production.yml logs --since=24h pyairtable-gateway > /tmp/gateway-logs-$(date +%s).log

# Collect application logs
docker-compose -f docker-compose.production.yml logs --since=24h > /tmp/full-logs-$(date +%s).log

# Export security-relevant metrics
curl -s "http://localhost:8080/prometheus/api/v1/query_range?query=rate(http_requests_total{status=\"401\"}[5m])&start=$(date -d '24 hours ago' -u +%s)&end=$(date -u +%s)&step=300" > /tmp/security-metrics-$(date +%s).json
```

#### Network Analysis
```bash
# Check current network connections
netstat -tuln | grep :8080

# Check for unusual network activity
ss -tuln | grep ESTABLISHED

# Monitor real-time connections
watch 'netstat -tuln | grep :8080 | wc -l'
```

#### User Activity Analysis
```bash
# Identify affected user accounts
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"suspicious_activity\" | json | .user_id" | sort | uniq

# Check user session patterns
curl -s "http://localhost:8080/prometheus/api/v1/query?query=sum(rate(pyairtable_user_sessions_total[1h])) by (user_id)"

# Review recent user privilege changes
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"privilege_change\" | json"
```

### 5. Attack Pattern Identification

#### Brute Force Attacks
```bash
# Identify brute force patterns
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"failed_login\" | json | line_format \"{{.source_ip}}\"" | sort | uniq -c | sort -nr

# Check for distributed attacks
curl -s "http://localhost:8080/prometheus/api/v1/query?query=count by (source_ip) (rate(pyairtable_login_attempts_total{status=\"failed\"}[5m]) > 5)"

# Analyze timing patterns
curl -s "http://localhost:3100/loki/api/v1/query_range?query={job=\"pyairtable-apps\"} |= \"failed_login\"&start=$(date -d '2 hours ago' -u +%s)&end=$(date -u +%s)"
```

#### Data Exfiltration Attempts
```bash
# Check for unusual data access patterns
curl -s "http://localhost:8080/prometheus/api/v1/query?query=rate(pyairtable_data_requests_total[1h]) > 1000"

# Monitor large data transfers
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"large_transfer\" | json"

# Check API usage patterns
curl -s "http://localhost:8080/prometheus/api/v1/query?query=topk(10, sum(rate(http_requests_total[1h])) by (user_id))"
```

#### Privilege Escalation
```bash
# Check for privilege escalation attempts
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"privilege_escalation\" | json"

# Monitor admin actions
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"admin_action\" | json"

# Check for unauthorized database access
docker exec -it postgres-prod psql -U postgres -c "SELECT usename, query, query_start FROM pg_stat_activity WHERE state = 'active';"
```

## Containment and Mitigation (30-60 minutes)

### 6. User Account Security

#### Affected Account Lockdown
```bash
# Suspend compromised user accounts
curl -X POST http://localhost:8080/api/v1/users/suspend \
  -H "Content-Type: application/json" \
  -d '{"user_ids": ["user1", "user2"], "reason": "security_incident", "immediate": true}'

# Terminate all sessions for affected users
curl -X POST http://localhost:8080/api/v1/sessions/terminate \
  -H "Content-Type: application/json" \
  -d '{"user_ids": ["user1", "user2"], "reason": "security_incident"}'

# Force password reset for all users (if widespread compromise)
curl -X POST http://localhost:8080/api/v1/security/force-password-reset \
  -H "Content-Type: application/json" \
  -d '{"all_users": true, "reason": "security_incident"}'
```

#### Access Token Revocation
```bash
# Revoke API tokens for affected users
curl -X POST http://localhost:8080/api/v1/tokens/revoke \
  -H "Content-Type: application/json" \
  -d '{"user_ids": ["user1", "user2"], "token_types": ["api", "refresh"]}'

# Revoke OAuth tokens
curl -X POST http://localhost:8080/api/v1/oauth/revoke-all \
  -H "Content-Type: application/json" \
  -d '{"user_ids": ["user1", "user2"]}'
```

### 7. Network-Level Protection

#### IP Blocking and Rate Limiting
```bash
# Block malicious IP ranges
curl -X POST http://localhost:8080/api/v1/security/block-ip-range \
  -H "Content-Type: application/json" \
  -d '{"ip_ranges": ["x.x.x.0/24"], "reason": "security_incident", "duration": "72h"}'

# Implement aggressive rate limiting
curl -X POST http://localhost:8080/api/v1/security/emergency-rate-limit \
  -H "Content-Type: application/json" \
  -d '{"requests_per_minute": 10, "duration": "24h"}'

# Enable CAPTCHA for all logins
curl -X POST http://localhost:8080/api/v1/security/enable-captcha \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "threshold": 1}'
```

#### WAF and DDoS Protection
```bash
# Enable Web Application Firewall rules
curl -X POST http://localhost:8080/api/v1/security/waf/enable-rules \
  -H "Content-Type: application/json" \
  -d '{"rules": ["sql_injection", "xss", "brute_force"], "mode": "block"}'

# Activate DDoS protection
curl -X POST http://localhost:8080/api/v1/security/ddos-protection \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "sensitivity": "high"}'
```

### 8. Data Protection

#### Database Security
```bash
# Check for unauthorized database queries
docker exec -it postgres-prod psql -U postgres -c "SELECT query, usename, client_addr, query_start FROM pg_stat_activity WHERE state = 'active';"

# Enable database audit logging
docker exec -it postgres-prod psql -U postgres -c "ALTER SYSTEM SET log_statement = 'all';"
docker exec -it postgres-prod psql -U postgres -c "SELECT pg_reload_conf();"

# Create database snapshot for forensics
docker exec postgres-prod pg_dump -U postgres pyairtable > /tmp/forensic-snapshot-$(date +%s).sql
```

#### Encryption and Secrets
```bash
# Rotate API keys
curl -X POST http://localhost:8080/api/v1/security/rotate-api-keys \
  -H "Content-Type: application/json" \
  -d '{"force": true, "reason": "security_incident"}'

# Rotate database credentials
curl -X POST http://localhost:8080/api/v1/security/rotate-db-credentials \
  -H "Content-Type: application/json" \
  -d '{"immediate": true}'

# Enable additional encryption
curl -X POST http://localhost:8080/api/v1/security/enhance-encryption \
  -H "Content-Type: application/json" \
  -d '{"enabled": true}'
```

## Communication and Escalation

### 9. Internal Communication

#### Security Team Notification
```markdown
**SECURITY INCIDENT - IMMEDIATE ATTENTION REQUIRED**

Incident ID: SEC-$(date +%Y%m%d-%H%M%S)
Severity: [CRITICAL/HIGH/MEDIUM]
Type: [Brute Force/Data Breach/Unauthorized Access/DDoS/Other]

Initial Detection: [Timestamp and alert source]
Affected Systems: [List of affected services/systems]
Affected Users: [Number and list if known]

Immediate Actions Taken:
- [ ] IP blocking: [List of blocked IPs]
- [ ] User suspension: [List of suspended users]
- [ ] Emergency measures: [List of emergency controls activated]

Evidence Preservation:
- Logs captured: [List of log files]
- Metrics exported: [List of metric files]
- Database snapshots: [List of snapshots]

Next Steps:
- [ ] Forensic analysis
- [ ] Legal notification assessment
- [ ] Customer communication assessment
- [ ] Regulatory reporting assessment

Incident Commander: [Name and contact]
Next Update: [Timestamp]
```

#### Management Escalation
- [ ] Notify CISO immediately
- [ ] Escalate to CEO if customer data involved
- [ ] Contact legal team for regulatory requirements
- [ ] Prepare communication for board if major incident

### 10. External Communication

#### Customer Notification Assessment
```bash
# Assess if customer data was accessed
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"data_access\" | json | .data_type"

# Check if PII was involved
curl -s "http://localhost:3100/loki/api/v1/query?query={job=\"pyairtable-apps\"} |= \"pii_access\" | json"

# Determine scope of customer impact
curl -s "http://localhost:8080/prometheus/api/v1/query?query=count(count by (tenant_id) (pyairtable_affected_tenants_total))"
```

#### Regulatory Notification
- [ ] GDPR notification (if EU customers affected)
- [ ] SOC 2 auditor notification
- [ ] Industry-specific compliance notifications
- [ ] Law enforcement notification (if required)

## Forensic Analysis and Recovery

### 11. Detailed Forensic Investigation

#### Timeline Reconstruction
```bash
# Generate detailed incident timeline
./scripts/generate-security-timeline.sh $INCIDENT_START_TIME $INCIDENT_END_TIME > /tmp/security-timeline-$(date +%s).txt

# Correlate events across systems
./scripts/correlate-security-events.sh > /tmp/event-correlation-$(date +%s).json

# Generate attack flow diagram
./scripts/generate-attack-flow.sh > /tmp/attack-flow-$(date +%s).png
```

#### Impact Assessment
```bash
# Assess data integrity
./scripts/verify-data-integrity.sh > /tmp/integrity-check-$(date +%s).log

# Check for data modification
docker exec -it postgres-prod psql -U postgres -c "SELECT schemaname, tablename, n_tup_ins, n_tup_upd, n_tup_del FROM pg_stat_user_tables WHERE n_tup_upd > 0 OR n_tup_del > 0;"

# Verify system integrity
./scripts/system-integrity-check.sh > /tmp/system-integrity-$(date +%s).log
```

### 12. System Recovery

#### Clean Environment Restoration
```bash
# Deploy clean container images
docker-compose -f docker-compose.production.yml pull
docker-compose -f docker-compose.production.yml up -d --force-recreate

# Restore from clean backup if needed
./restore-from-backup.sh --verify-integrity --pre-incident-timestamp

# Verify system cleanliness
./scripts/security-scan.sh > /tmp/post-recovery-scan-$(date +%s).log
```

#### Security Hardening
```bash
# Apply additional security measures
curl -X POST http://localhost:8080/api/v1/security/hardening \
  -H "Content-Type: application/json" \
  -d '{"level": "maximum", "immediate": true}'

# Update security policies
curl -X POST http://localhost:8080/api/v1/security/update-policies \
  -H "Content-Type: application/json" \
  -d '{"incident_response": true}'

# Implement additional monitoring
curl -X POST http://localhost:8080/api/v1/monitoring/security-enhanced \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "sensitivity": "high"}'
```

## Post-Incident Activities

### 13. Documentation and Reporting

#### Incident Report Generation
```bash
# Generate comprehensive incident report
./scripts/generate-incident-report.sh $INCIDENT_ID > /tmp/incident-report-$INCIDENT_ID.pdf

# Create executive summary
./scripts/generate-executive-summary.sh $INCIDENT_ID > /tmp/executive-summary-$INCIDENT_ID.pdf

# Prepare technical analysis
./scripts/generate-technical-analysis.sh $INCIDENT_ID > /tmp/technical-analysis-$INCIDENT_ID.pdf
```

#### Evidence Preservation
- [ ] Archive all logs and metrics
- [ ] Create forensic disk images if needed
- [ ] Document chain of custody
- [ ] Prepare evidence for potential legal proceedings

### 14. Lessons Learned and Improvements

#### Security Enhancements
- [ ] Review and update security policies
- [ ] Implement additional monitoring based on attack vectors
- [ ] Enhance employee security training
- [ ] Update incident response procedures

#### Technical Improvements
- [ ] Patch identified vulnerabilities
- [ ] Improve logging and monitoring
- [ ] Enhance access controls
- [ ] Implement additional security tools

## Recovery Verification

### 15. Security Validation
```bash
# Run security scan
./scripts/comprehensive-security-scan.sh > /tmp/security-validation-$(date +%s).log

# Verify all security controls are active
curl http://localhost:8080/api/v1/security/status

# Test incident response procedures
./scripts/test-incident-response.sh

# Validate monitoring and alerting
./scripts/test-security-alerts.sh
```

### 16. Business Continuity Verification
```bash
# Test all critical business functions
./scripts/test-business-functions.sh

# Verify customer access is restored
curl -f http://localhost:8080/api/v1/health/customer-facing

# Monitor for any lingering issues
watch 'curl -s http://localhost:8080/api/v1/security/threat-level'
```

## Related Resources
- [Emergency Contact List](emergency-contacts.md)
- [Legal Notification Requirements](legal-notifications.md)
- [Customer Communication Templates](customer-communications.md)
- [Regulatory Compliance Checklist](regulatory-compliance.md)

---
**CONFIDENTIAL - SECURITY INCIDENT RESPONSE**  
**Last Updated:** [DATE]  
**Next Review:** [DATE + 1 month]

**Emergency Contacts:**
- Security Team Lead: [Phone/Email]
- CISO: [Phone/Email] 
- Legal: [Phone/Email]
- CEO: [Phone/Email]