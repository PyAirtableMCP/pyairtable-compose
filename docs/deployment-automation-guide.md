# PyAirtable Deployment Automation Guide

## Overview

This guide provides comprehensive documentation for PyAirtable's deployment automation system, covering CI/CD pipelines, GitOps, infrastructure management, and operational procedures.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [CI/CD Pipeline](#cicd-pipeline)
3. [GitOps with ArgoCD](#gitops-with-argocd)
4. [Infrastructure as Code](#infrastructure-as-code)
5. [Deployment Strategies](#deployment-strategies)
6. [Operational Automation](#operational-automation)
7. [Security and Compliance](#security-and-compliance)
8. [Monitoring and Observability](#monitoring-and-observability)
9. [Troubleshooting](#troubleshooting)
10. [Runbooks](#runbooks)

## Architecture Overview

PyAirtable's deployment automation follows GitOps principles with a comprehensive automation stack:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │    │   GitHub        │    │   CI/CD         │
│   Commits       │───▶│   Repository    │───▶│   Pipeline      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Container     │    │   Security      │    │   Build &       │
│   Registry      │◀───│   Scanning      │◀───│   Test          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                                              │
         ▼                                              ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ArgoCD        │    │   GitOps        │    │   Environment   │
│   Deployment    │◀───│   Repository    │◀───│   Promotion     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │   Infrastructure│    │   Monitoring    │
│   Cluster       │◀───│   as Code       │───▶│   & Alerting    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Key Components

1. **GitHub Actions CI/CD**: Automated testing, building, and security scanning
2. **ArgoCD GitOps**: Declarative deployments with automatic synchronization
3. **Terraform IaC**: Infrastructure provisioning and management
4. **Kubernetes**: Container orchestration with advanced deployment strategies
5. **Prometheus/Grafana**: Monitoring and observability
6. **Chaos Engineering**: Reliability testing and resilience validation

## CI/CD Pipeline

### Pipeline Structure

The CI/CD pipeline is implemented using GitHub Actions and consists of multiple stages:

#### 1. Security and Quality Scanning
- **SAST**: CodeQL static analysis
- **Dependency Scanning**: Snyk vulnerability scanning
- **Container Scanning**: Trivy and Snyk container security
- **Infrastructure Scanning**: tfsec and Checkov
- **Secrets Scanning**: GitLeaks and TruffleHog

#### 2. Testing
- **Unit Tests**: Go, Python, and JavaScript test suites
- **Integration Tests**: Cross-service communication testing
- **Performance Tests**: K6 load testing
- **Contract Tests**: API contract validation

#### 3. Build and Packaging
- **Multi-arch Builds**: AMD64 and ARM64 container images
- **Image Signing**: Cosign container signing
- **SBOM Generation**: Software Bill of Materials
- **Vulnerability Scanning**: Pre-deployment security checks

#### 4. Deployment
- **Environment Promotion**: Dev → Staging → Production
- **Blue-Green Deployments**: Zero-downtime releases
- **Canary Releases**: Progressive traffic shifting
- **Rollback Capabilities**: Automated and manual rollback options

### Configuration Files

#### Main CI/CD Pipeline
- **File**: `.github/workflows/ci-cd-pipeline.yml`
- **Triggers**: Push to main/develop, PRs, manual dispatch
- **Environments**: Development, Staging, Production

#### Security Scanning
- **File**: `.github/workflows/security-scan.yml`
- **Schedule**: Daily security scans
- **Integration**: GitHub Security tab, Slack notifications

### Environment-Specific Deployments

#### Development Environment
- **Branch**: `develop`
- **Auto-deploy**: Enabled
- **Resources**: Minimal (cost-optimized)
- **Features**: Full feature flag access

#### Staging Environment
- **Branch**: `main`
- **Strategy**: Blue-green deployment
- **Resources**: Production-like
- **Validation**: Automated smoke tests

#### Production Environment
- **Trigger**: Manual approval required
- **Strategy**: Canary deployment with monitoring
- **Resources**: Full production scaling
- **Rollback**: Automated on failure detection

## GitOps with ArgoCD

### ArgoCD Configuration

ArgoCD manages deployments across all environments using the "App of Apps" pattern:

```
pyairtable-app-of-apps
├── pyairtable-dev
├── pyairtable-staging
└── pyairtable-prod
```

#### Installation
```bash
# Apply ArgoCD installation
kubectl apply -f gitops/argocd/install.yaml

# Configure initial application
kubectl apply -f gitops/applications/app-of-apps.yaml
```

#### Access ArgoCD Dashboard
- **URL**: https://argocd.pyairtable.com
- **Authentication**: GitHub OIDC
- **RBAC**: Role-based access control

### Sealed Secrets Management

Secrets are encrypted using Sealed Secrets and stored in Git:

#### Create Sealed Secret
```bash
# Create regular secret
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --dry-run=client -o yaml > secret.yaml

# Seal the secret
kubeseal --format=yaml --cert=public-key-cert.pem < secret.yaml > sealed-secret.yaml

# Commit sealed secret to Git
git add sealed-secret.yaml
git commit -m "Add sealed secret"
```

#### Environment-Specific Secrets
- **Development**: `gitops/secrets/dev-secrets.yaml`
- **Staging**: `gitops/secrets/staging-secrets.yaml`
- **Production**: `gitops/secrets/prod-secrets.yaml`

### Progressive Delivery with Flagger

Flagger enables automated canary deployments with monitoring:

#### Canary Configuration
```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: api-gateway
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  analysis:
    interval: 30s
    threshold: 5
    maxWeight: 50
    stepWeight: 10
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
```

## Infrastructure as Code

### Terraform Structure

Infrastructure is managed using Terraform with a modular approach:

```
infrastructure/terraform/
├── enhanced-main.tf           # Main infrastructure
├── enhanced-variables.tf     # Variable definitions
├── disaster-recovery.tf      # DR configuration
├── modules/                  # Reusable modules
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   └── redis/
└── environments/             # Environment configs
    ├── dev.tfvars
    ├── staging.tfvars
    └── prod.tfvars
```

### Deployment Commands

#### Initialize Terraform
```bash
cd infrastructure/terraform
terraform init -backend-config="key=infrastructure/prod/terraform.tfstate"
```

#### Plan and Apply
```bash
# Plan changes
terraform plan -var-file=environments/prod.tfvars

# Apply changes
terraform apply -var-file=environments/prod.tfvars
```

#### Disaster Recovery Setup
```bash
# Enable cross-region DR
terraform apply -var-file=environments/prod.tfvars -var="enable_cross_region_backup=true"
```

### State Management

- **Backend**: S3 with DynamoDB locking
- **Encryption**: Encrypted at rest
- **Versioning**: Enabled for rollback capabilities
- **Access Control**: IAM-based permissions

## Deployment Strategies

### Blue-Green Deployment

Zero-downtime deployments using two identical environments:

#### Switch to Green
```bash
cd deployment-strategies/blue-green
./switch-script.sh deploy green v1.2.3
```

#### Rollback to Blue
```bash
./switch-script.sh rollback
```

#### Status Check
```bash
./switch-script.sh status
```

### Canary Deployment

Progressive traffic shifting with automatic rollback:

#### Flagger Canary Process
1. Deploy new version to canary
2. Start with 10% traffic
3. Increase gradually: 10% → 20% → 50% → 100%
4. Monitor success metrics at each step
5. Automatic rollback on failure

#### Manual Canary Control
```bash
# Force promotion
kubectl patch canary api-gateway -p '{"spec":{"analysis":{"threshold":0}}}'

# Force rollback
kubectl patch canary api-gateway -p '{"spec":{"analysis":{"threshold":10000}}}'
```

### Feature Flags

Dynamic feature control without deployments:

#### Feature Flag Service
- **Configuration**: `deployment-strategies/feature-flags/feature-flag-service.yaml`
- **Controller**: Real-time config updates via Redis
- **Client Library**: Language-specific integrations

#### Usage Example
```python
from feature_flags import FeatureFlagClient

client = FeatureFlagClient(redis_url="redis://localhost:6379")

if client.is_enabled("new_ui_enabled", user_id="user123"):
    # Show new UI
    render_new_ui()
else:
    # Show old UI
    render_old_ui()
```

## Operational Automation

### Automated Backups

#### Database Backups
- **Schedule**: Daily at 2 AM UTC
- **Retention**: 30 days, with weekly/monthly archives
- **Cross-region**: Automatic replication to DR region
- **Monitoring**: Prometheus metrics and Slack notifications

#### Configuration Backups
- **Schedule**: Daily at 3 AM UTC
- **Scope**: ConfigMaps, Secrets metadata, PVCs
- **Storage**: S3 with encryption

#### Backup Restoration
```bash
# List available backups
aws s3 ls s3://pyairtable-prod-backups/database/

# Restore from backup
kubectl create job restore-db-20231201 \
  --from=cronjob/database-backup \
  --env=RESTORE_FROM=s3://pyairtable-prod-backups/database/20231201_020000/
```

### Certificate Management

Automated SSL/TLS certificate provisioning and renewal:

#### Certificate Issuers
- **Production**: Let's Encrypt production
- **Staging**: Let's Encrypt staging
- **Internal**: Self-signed CA for internal services

#### Certificate Monitoring
- **Expiry Alerts**: 30 days and 7 days before expiry
- **Renewal Monitoring**: Automated renewal with failure alerts
- **Compliance Checking**: Certificate validation and reporting

### Database Migrations

Automated schema migrations with rollback capabilities:

#### Migration Execution
```bash
# Run migrations
kubectl apply -f operational-automation/database-migrations.yaml

# Check migration status
curl http://migration-tracker:8080/api/migrations

# Manual migration
kubectl create job manual-migration-$(date +%s) \
  --from=job/database-migration-template \
  --env=MIGRATION_VERSION=003
```

#### Migration History
All migrations are tracked with:
- Source and target versions
- Execution timestamps
- Success/failure status
- Error messages and logs
- Rollback procedures

## Security and Compliance

### Security Scanning Pipeline

#### Container Security
- **Base Image Scanning**: Trivy vulnerability detection
- **Dependency Scanning**: Snyk package vulnerability analysis
- **Runtime Security**: Falco runtime anomaly detection

#### Infrastructure Security
- **IaC Scanning**: tfsec and Checkov policy validation
- **Network Policies**: Kubernetes network segmentation
- **RBAC**: Principle of least privilege access

#### Compliance Monitoring
- **Standards**: SOC2, PCI-DSS, GDPR compliance checks
- **Audit Logging**: Comprehensive audit trails
- **Policy Enforcement**: Open Policy Agent (OPA) policies

### Secrets Management

#### Sealed Secrets
- **Encryption**: RSA 4096-bit encryption
- **Key Rotation**: Automated key rotation every 30 days
- **Namespace Isolation**: Environment-specific secret scoping

#### External Secrets
- **AWS Secrets Manager**: Production secrets storage
- **Parameter Store**: Configuration parameters
- **Vault Integration**: Future HashiCorp Vault support

## Monitoring and Observability

### Metrics and Monitoring

#### Prometheus Stack
- **Metrics Collection**: Application and infrastructure metrics
- **Alert Manager**: Intelligent alert routing and grouping
- **Grafana**: Visualization and dashboards

#### Key Metrics
```yaml
# Application Metrics
- http_requests_total
- http_request_duration_seconds
- database_connections_active
- redis_cache_hit_ratio

# Infrastructure Metrics
- cpu_usage_percent
- memory_usage_percent
- disk_usage_percent
- network_io_bytes

# Business Metrics
- user_signups_total
- api_calls_per_minute
- feature_flag_evaluations
- deployment_frequency
```

#### Alerting Rules
```yaml
# Critical Alerts
- High Error Rate (>5% for 5 minutes)
- Service Down (0 healthy instances)
- Database Connection Failures
- Certificate Expiry (7 days)

# Warning Alerts
- High Latency (>1s P95 for 10 minutes)
- Memory Usage (>80% for 15 minutes)
- Disk Usage (>85%)
- Failed Backups
```

### Logging

#### Centralized Logging
- **Collection**: Fluent Bit log collection
- **Storage**: Elasticsearch cluster
- **Visualization**: Kibana dashboards
- **Retention**: 90 days for production, 30 days for staging

#### Log Structure
```json
{
  "timestamp": "2023-12-01T10:00:00Z",
  "level": "INFO",
  "service": "api-gateway",
  "environment": "prod",
  "trace_id": "abc123",
  "message": "Request processed successfully",
  "duration_ms": 150,
  "user_id": "user123"
}
```

### Distributed Tracing

#### Jaeger Integration
- **Trace Collection**: OpenTelemetry instrumentation
- **Service Map**: Dependency visualization
- **Performance Analysis**: Request flow optimization

## Troubleshooting

### Common Issues

#### Deployment Failures

**Symptom**: ArgoCD shows application in degraded state
```bash
# Check ArgoCD application status
kubectl describe application pyairtable-prod -n argocd

# Check pod status
kubectl get pods -n pyairtable-prod

# View pod logs
kubectl logs -l app=api-gateway -n pyairtable-prod --tail=100
```

**Solution**:
1. Check resource quotas and limits
2. Verify ConfigMap and Secret availability
3. Review recent changes in Git
4. Check node capacity and scheduling

#### CI/CD Pipeline Issues

**Symptom**: GitHub Actions workflow failing
```bash
# Check workflow status
gh workflow list

# View workflow run details
gh run view <run-id>

# Download workflow logs
gh run download <run-id>
```

**Solution**:
1. Review failed step logs
2. Check repository secrets and variables
3. Verify runner availability
4. Test changes in feature branch

#### Certificate Issues

**Symptom**: SSL certificate errors
```bash
# Check certificate status
kubectl get certificates -A

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate details
kubectl describe certificate pyairtable-com-tls -n pyairtable-prod
```

**Solution**:
1. Verify DNS configuration
2. Check Let's Encrypt rate limits
3. Review ClusterIssuer configuration
4. Check ACME challenge completion

### Diagnostic Commands

#### Cluster Health
```bash
# Node status
kubectl get nodes -o wide

# Resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Cluster events
kubectl get events --sort-by=.metadata.creationTimestamp
```

#### Application Health
```bash
# Service health checks
curl https://pyairtable.com/health

# Database connectivity
kubectl exec -it deployment/api-gateway -- pg_isready -h postgres

# Redis connectivity
kubectl exec -it deployment/api-gateway -- redis-cli -h redis ping
```

#### Network Troubleshooting
```bash
# Service discovery
kubectl get endpoints

# Network policies
kubectl get networkpolicies -A

# DNS resolution
kubectl run test-pod --image=busybox --rm -it -- nslookup api-gateway
```

## Runbooks

### Production Deployment Runbook

#### Pre-Deployment Checklist
- [ ] All tests passing in staging
- [ ] Security scans completed successfully
- [ ] Database migrations tested
- [ ] Rollback plan confirmed
- [ ] On-call engineer notified

#### Deployment Steps
1. **Create Release**
   ```bash
   gh release create v1.2.3 --title "Release v1.2.3" --notes "Release notes"
   ```

2. **Trigger Production Deployment**
   ```bash
   gh workflow run ci-cd-pipeline.yml \
     --field environment=prod \
     --field service=""
   ```

3. **Monitor Deployment**
   ```bash
   # Watch ArgoCD sync
   argocd app sync pyairtable-prod --watch

   # Monitor application health
   kubectl get pods -n pyairtable-prod -w
   ```

4. **Validate Deployment**
   ```bash
   # Run smoke tests
   ./scripts/smoke-test.sh prod

   # Check metrics
   curl https://pyairtable.com/metrics
   ```

#### Post-Deployment
- [ ] Verify all services healthy
- [ ] Check error rates and latency
- [ ] Monitor for 30 minutes
- [ ] Update deployment documentation

### Emergency Rollback Runbook

#### Immediate Actions
1. **Stop Current Deployment**
   ```bash
   # Cancel GitHub Actions workflow
   gh run cancel <run-id>

   # Pause ArgoCD sync if needed
   argocd app set pyairtable-prod --sync-policy none
   ```

2. **Execute Rollback**
   ```bash
   # Blue-green rollback
   cd deployment-strategies/blue-green
   ./switch-script.sh rollback

   # Or Helm rollback
   helm rollback pyairtable-prod -n pyairtable-prod
   ```

3. **Verify Rollback**
   ```bash
   # Check service health
   kubectl get pods -n pyairtable-prod
   curl https://pyairtable.com/health

   # Run smoke tests
   ./scripts/smoke-test.sh prod
   ```

#### Communication
1. **Notify Stakeholders**
   - Post in #incidents Slack channel
   - Send email to engineering team
   - Update status page if customer-facing

2. **Document Incident**
   - Create incident report
   - Document root cause
   - Plan remediation steps

### Database Emergency Runbook

#### Database Connection Issues
1. **Check Database Status**
   ```bash
   # Database pods
   kubectl get pods -l app=postgres -n pyairtable-prod

   # Connection from application
   kubectl exec -it deployment/api-gateway -- \
     pg_isready -h postgres -p 5432
   ```

2. **Check Resource Usage**
   ```bash
   # Database metrics
   kubectl top pods -l app=postgres -n pyairtable-prod

   # Connection count
   kubectl exec -it deployment/postgres -- \
     psql -c "SELECT count(*) FROM pg_stat_activity;"
   ```

3. **Emergency Actions**
   ```bash
   # Scale down applications if needed
   kubectl scale deployment api-gateway --replicas=1 -n pyairtable-prod

   # Restart database if required
   kubectl rollout restart deployment/postgres -n pyairtable-prod
   ```

#### Data Corruption or Loss
1. **Immediate Response**
   - Stop all write operations
   - Identify extent of corruption
   - Contact database administrator

2. **Recovery Options**
   ```bash
   # List available backups
   aws s3 ls s3://pyairtable-prod-backups/database/

   # Point-in-time recovery
   kubectl create job restore-pitr-$(date +%s) \
     --from=cronjob/database-backup \
     --env=RESTORE_TYPE=point-in-time \
     --env=RESTORE_TIME="2023-12-01 10:00:00 UTC"
   ```

### Security Incident Runbook

#### Suspected Compromise
1. **Immediate Actions**
   - Rotate all secrets and API keys
   - Enable additional monitoring
   - Preserve evidence for investigation

2. **Containment**
   ```bash
   # Block suspicious traffic
   kubectl apply -f security/emergency-network-policy.yaml

   # Scale down affected services
   kubectl scale deployment suspicious-service --replicas=0

   # Enable audit logging
   kubectl patch configmap audit-policy \
     --patch '{"data":{"audit-policy.yaml":"# Enhanced audit rules"}}'
   ```

3. **Investigation**
   - Review audit logs
   - Check container images for vulnerabilities
   - Analyze network traffic patterns
   - Coordinate with security team

### Chaos Engineering Runbook

#### Emergency Stop All Experiments
```bash
# Use chaos CLI
kubectl exec -it deployment/chaos-monitor -n chaos-engineering -- \
  /app/chaos.sh emergency-stop

# Or direct Kubernetes commands
kubectl patch schedule --all -n chaos-engineering \
  -p '{"spec":{"suspend":true}}'
```

#### Review Experiment Results
```bash
# List recent experiments
kubectl get schedule -n chaos-engineering

# Check experiment logs
kubectl logs -l app=chaos-monitor -n chaos-engineering

# Review metrics
curl http://chaos-monitor.chaos-engineering:8080/metrics
```

---

This comprehensive deployment automation guide provides the foundation for reliable, secure, and scalable deployments of PyAirtable. Regular review and updates of these procedures ensure continued operational excellence.

For additional support or questions, contact:
- **Engineering Team**: engineering@pyairtable.com
- **Operations Team**: ops@pyairtable.com
- **On-call Engineer**: +1-XXX-XXX-XXXX