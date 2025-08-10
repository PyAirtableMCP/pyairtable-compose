# PyAirtable Production Migration Guide

## Overview

This repository contains a complete production migration plan and automation toolkit for PyAirtable's microservices architecture. The migration enables zero-downtime transition from staging to production with comprehensive validation, monitoring, and rollback capabilities.

## 📋 Migration Components

### Core Documentation
- **[PRODUCTION_MIGRATION_PLAN.md](./PRODUCTION_MIGRATION_PLAN.md)** - Comprehensive migration plan with detailed procedures
- **[MIGRATION_README.md](./MIGRATION_README.md)** - This file - quick start and overview

### Automation Scripts
```
scripts/migration/
├── run-migration.sh                    # Main orchestration script
├── migration-orchestrator.py          # Python migration orchestrator  
├── database-migration-scripts.sql     # Database migration functions
├── service-deployment-automation.sh   # Service deployment automation
├── production-cutover.sh              # DNS and traffic management
├── post-migration-validation.py       # Comprehensive validation suite
└── migration-config.yaml              # Migration configuration
```

## 🚀 Quick Start

### Prerequisites

1. **Required Tools:**
   ```bash
   # Install required CLI tools
   brew install terraform kubectl helm aws-cli docker jq
   
   # Install Python dependencies
   pip3 install asyncio aiohttp asyncpg redis boto3 pyyaml
   ```

2. **Environment Variables:**
   ```bash
   export AWS_ACCOUNT_ID="123456789012"
   export SOURCE_DATABASE_URL="postgresql://staging:5432/pyairtable"
   export TARGET_DATABASE_URL="postgresql://production:5432/pyairtable" 
   export REDIS_URL="redis://production-redis:6379/0"
   export KAFKA_BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
   export HOSTED_ZONE_ID="Z1234567890ABC"
   export SSL_CERT_ARN="arn:aws:acm:eu-central-1:123456789012:certificate/..."
   export AIRTABLE_TOKEN="your-airtable-token"
   export GEMINI_API_KEY="your-gemini-api-key"
   export API_KEY="your-api-key"
   ```

3. **AWS Configuration:**
   ```bash
   aws configure
   # Or use AWS SSO
   aws sso login --profile your-profile
   ```

### Execution

1. **Validate Environment:**
   ```bash
   ./scripts/migration/run-migration.sh validate
   ```

2. **Execute Migration:**
   ```bash
   ./scripts/migration/run-migration.sh migrate
   ```

3. **Monitor Status:**
   ```bash
   ./scripts/migration/run-migration.sh status
   ```

4. **Rollback if Needed:**
   ```bash
   ./scripts/migration/run-migration.sh rollback
   ```

## 📊 Migration Architecture

### Service Topology
```
┌─────────────────────────────────────────────────────────────┐
│                    Production Migration                     │
├─────────────────────────────────────────────────────────────┤
│  Phase 1: Database Migration (Zero Downtime)               │
│  ├── Logical Replication Setup                             │
│  ├── Initial Data Sync                                     │
│  ├── Real-time Replication                                 │
│  └── Data Validation                                       │
├─────────────────────────────────────────────────────────────┤
│  Phase 2: Service Deployment (Blue-Green)                  │
│  ├── Infrastructure Services (Postgres, Redis, Kafka)     │
│  ├── Core Services (API Gateway, Auth)                    │
│  ├── Platform Services (User, Workspace, Permission)      │
│  ├── Domain Services (Airtable, LLM, MCP, Automation)     │
│  └── Frontend Services (Web BFF, Mobile BFF, UI)          │
├─────────────────────────────────────────────────────────────┤
│  Phase 3: Traffic Cutover (Gradual)                        │
│  ├── DNS TTL Reduction                                     │
│  ├── Load Balancer Configuration                           │
│  ├── Gradual Traffic Shift (10% → 25% → 50% → 75% → 100%) │
│  └── DNS Finalization                                      │
├─────────────────────────────────────────────────────────────┤
│  Phase 4: Validation & Monitoring                          │
│  ├── Performance Validation                                │
│  ├── Security Audit                                        │
│  ├── Backup Verification                                   │
│  └── Monitoring Setup                                      │
└─────────────────────────────────────────────────────────────┘
```

### Service Dependencies
```
Infrastructure Services
├── PostgreSQL (Aurora Serverless v2)
├── Redis (ElastiCache)
├── Kafka (MSK)
└── Istio Service Mesh

Core Services  
├── API Gateway (depends: postgres, redis)
└── Auth Service (depends: postgres, redis)

Platform Services
├── User Service (depends: postgres, auth-service)
├── Workspace Service (depends: postgres, user-service)  
└── Permission Service (depends: postgres)

Domain Services
├── Airtable Gateway (depends: redis, user-service)
├── LLM Orchestrator (depends: redis, mcp-server)
├── MCP Server (depends: airtable-gateway)
└── Automation Service (depends: kafka, postgres)

Frontend Services
├── Web BFF (depends: api-gateway)
├── Mobile BFF (depends: api-gateway)
└── Auth Frontend (depends: auth-service)
```

## 🔒 Security Considerations

### Network Security
- VPC with private subnets for all compute resources
- Security groups with minimal required access
- Kubernetes NetworkPolicies for pod-to-pod communication
- Istio service mesh with mTLS encryption

### Data Protection
- Encryption at rest and in transit
- Automated database backups with 30-day retention
- Secrets managed via AWS Secrets Manager
- Audit logging for all API calls

### Access Control
- IAM roles with least privilege principles
- Kubernetes RBAC for service accounts
- Pod Security Standards enforcement
- Regular security audits and vulnerability scanning

## 📈 Performance Targets

### Response Time Targets
- Health endpoints: < 100ms
- Authentication APIs: < 200ms
- Business logic APIs: < 500ms
- AI/ML services: < 2000ms

### Availability Targets
- Service uptime: 99.9% (8.77 hours downtime/year)
- Database availability: 99.95% (4.38 hours downtime/year)
- Migration downtime: 0 minutes (zero-downtime migration)

### Scalability Targets
- Horizontal pod autoscaling: 2-10 replicas per service
- Database scaling: Aurora Serverless 0.5-16 ACU
- Load testing: 1000+ RPS with <1% error rate

## 🚨 Emergency Procedures

### Immediate Rollback
```bash
# Emergency rollback - restores traffic to staging in <5 minutes
./scripts/migration/production-cutover.sh rollback
```

### Service-Specific Rollback
```bash
# Rollback specific service to previous version
./scripts/migration/service-deployment-automation.sh rollback api-gateway
```

### Database Recovery
```bash
# Point-in-time recovery (if needed)
./scripts/migration/database-recovery.sh --timestamp="2024-01-01T12:00:00Z"
```

## 📞 Support Contacts

### Critical Escalation
- **Primary On-Call**: DevOps Team Lead
- **Database Issues**: Database Administrator  
- **Security Incidents**: Security Team Lead
- **Business Impact**: Product Manager

### Monitoring Access
- **Grafana**: https://grafana.pyairtable.com
- **Prometheus**: https://prometheus.pyairtable.com
- **AlertManager**: https://alerts.pyairtable.com
- **Logs**: https://logs.pyairtable.com

## 📚 Additional Resources

### Migration Documentation
- [Infrastructure Deployment Guide](./infrastructure/DEPLOYMENT_GUIDE.md)
- [Kubernetes Deployment Runbook](./k8s/DEPLOYMENT_RUNBOOK.md)
- [Security Audit Report](./SECURITY_AUDIT_REPORT.md)
- [Observability Foundation](./docs/OBSERVABILITY_FOUNDATION.md)

### Development Resources
- [API Design Documentation](./go-services/API_DESIGN.md)
- [Event System README](./go-services/EVENT_SYSTEM_README.md)
- [CQRS Implementation](./go-services/CQRS_IMPLEMENTATION.md)
- [Service Governance Framework](./team-organization/service-governance-framework.md)

### Operational Runbooks
- [Deployment Runbook](./docs/deployment-runbook.md)
- [Autoscaling Operations](./docs/autoscaling-operations-runbook.md)
- [Kafka Operations](./kafka-operations-runbook.md)
- [Disaster Recovery](./kafka-backup/disaster-recovery-runbook.md)

## ✅ Migration Checklist

### Pre-Migration (Week -2)
- [ ] All environment variables configured
- [ ] AWS infrastructure provisioned and validated
- [ ] SSL certificates obtained and configured
- [ ] Database replication tested in staging
- [ ] Service images built and pushed to ECR
- [ ] Monitoring and alerting configured
- [ ] Team communication plan activated

### Migration Day
- [ ] Final validation of all systems
- [ ] Execute database migration phase
- [ ] Deploy services in dependency order
- [ ] Perform gradual traffic cutover
- [ ] Run comprehensive validation suite
- [ ] Monitor for 4 hours post-migration
- [ ] Document any issues or learnings

### Post-Migration (Week +1)
- [ ] Performance baseline validation
- [ ] Security audit completion
- [ ] Backup system verification
- [ ] Team handover documentation
- [ ] Cost optimization review
- [ ] Migration retrospective meeting

## 🎯 Success Criteria

**Technical Success:**
- ✅ All 22+ services deployed and healthy
- ✅ Zero data loss during migration
- ✅ Performance meets or exceeds baselines
- ✅ Security policies active and validated
- ✅ Monitoring and alerting operational

**Business Success:**
- ✅ User authentication working (100% login success)
- ✅ Airtable integration functional
- ✅ AI/ML services operational
- ✅ Real-time features working
- ✅ API rate limits enforced

**Operational Success:**
- ✅ Zero-downtime achieved
- ✅ Rollback procedures tested and validated
- ✅ Team handover completed
- ✅ Documentation updated
- ✅ Cost targets maintained

---

## 🏁 Getting Started

Ready to migrate? Follow these steps:

1. **Review** the [PRODUCTION_MIGRATION_PLAN.md](./PRODUCTION_MIGRATION_PLAN.md) document thoroughly
2. **Configure** your environment variables and AWS credentials  
3. **Validate** your setup: `./scripts/migration/run-migration.sh validate`
4. **Execute** the migration: `./scripts/migration/run-migration.sh migrate`
5. **Monitor** and verify: `./scripts/migration/run-migration.sh status`

The migration is designed to be safe, automated, and fully reversible. With comprehensive testing, monitoring, and rollback procedures, you can execute this migration with confidence.

**Questions?** Contact the DevOps team or refer to the detailed documentation linked above.