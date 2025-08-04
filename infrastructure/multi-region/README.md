# PyAirtable Multi-Region Infrastructure

This directory contains the complete multi-region infrastructure setup for PyAirtable, designed for global availability, low latency, and disaster recovery.

## Architecture Overview

The multi-region architecture spans three regions:
- **Primary**: US-East-1 (Virginia)
- **Secondary**: EU-West-1 (Ireland) 
- **Secondary**: AP-Southeast-1 (Singapore)

### Key Components

1. **Global Load Balancing & CDN**
   - CloudFront distribution with global edge locations
   - Route53 with geolocation routing
   - AWS WAF for DDoS protection and security

2. **Multi-Region Database**
   - PostgreSQL primary in US-East with read replicas in EU and AP
   - Automated streaming replication with conflict resolution
   - Cross-region backup and point-in-time recovery

3. **Global Caching**
   - Redis clusters in each region
   - Cross-region cache invalidation
   - Region-local cache optimization

4. **Event Streaming**
   - Amazon MSK (Kafka) clusters with cross-region mirroring
   - Consistent data partitioning across regions
   - Event-driven architecture support

5. **Container Orchestration**
   - EKS clusters in each region
   - Service mesh for cross-region communication
   - Auto-scaling and load balancing

6. **Disaster Recovery**
   - Automated failover procedures
   - Health monitoring and alerting
   - Recovery time objective (RTO): 30 minutes
   - Recovery point objective (RPO): 15 minutes

## Directory Structure

```
multi-region/
├── main.tf                    # Main infrastructure configuration
├── variables.tf               # Input variables
├── outputs.tf                 # Output values
├── terraform.tfvars.example   # Example configuration
├── deploy.sh                  # Deployment script
├── modules/                   # Terraform modules
│   ├── regional-infrastructure/    # Regional infrastructure module
│   ├── global-load-balancing/     # CloudFront and Route53 module
│   ├── database-replication/      # Database replication module
│   ├── disaster-recovery/         # DR automation module
│   └── kafka-cross-region/        # Kafka mirroring module
├── scripts/                   # Operational scripts
├── runbooks/                  # Operational procedures
└── docs/                      # Additional documentation
```

## Prerequisites

Before deploying the infrastructure, ensure you have:

1. **Required Tools**:
   - Terraform >= 1.5.0
   - AWS CLI >= 2.0.0
   - kubectl >= 1.28
   - jq (for JSON processing)

2. **AWS Permissions**:
   - AdministratorAccess or equivalent permissions
   - Access to all three regions (us-east-1, eu-west-1, ap-southeast-1)

3. **DNS & Certificates**:
   - Registered domain name
   - SSL certificates in AWS Certificate Manager for each region

4. **Configuration**:
   - Copy `terraform.tfvars.example` to `terraform.tfvars`
   - Customize the configuration for your environment

## Quick Start

### 1. Configuration

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration
vim terraform.tfvars
```

Key configuration items:
- `domain_name`: Your registered domain
- `certificate_arn*`: SSL certificate ARNs for each region
- `alert_email`: Email for monitoring alerts
- `environment`: Environment name (dev/staging/prod)

### 2. Deployment

```bash
# Deploy the infrastructure
./deploy.sh --environment prod

# Or with auto-approval for CI/CD
./deploy.sh --environment prod --auto-approve
```

The deployment script will:
1. Validate prerequisites and AWS permissions
2. Initialize Terraform backend
3. Create deployment plan
4. Apply infrastructure changes
5. Verify deployment
6. Configure kubectl contexts
7. Display deployment summary

### 3. Verification

After deployment, verify the infrastructure:

```bash
# Check Terraform outputs
terraform output

# Verify regional health
curl -I https://api.yourdomain.com/health

# Check EKS clusters
kubectl config get-contexts
kubectl --context pyairtable-prod-us-east get nodes
kubectl --context pyairtable-prod-eu-west get nodes
kubectl --context pyairtable-prod-ap-southeast get nodes
```

## Infrastructure Components

### Global Load Balancing

**CloudFront Distribution**:
- Global CDN with edge locations worldwide
- Origin Shield enabled for cost optimization
- Custom error pages and security headers
- Real-time logs and metrics

**Route53 DNS**:
- Geolocation-based routing
- Health checks for each region
- Automatic failover to healthy regions
- ALIAS records for optimal performance

**AWS WAF**:
- DDoS protection with rate limiting
- OWASP Top 10 protection
- Geographic restrictions (configurable)
- Real-time threat intelligence

### Database Architecture

**Primary Database (US-East)**:
- PostgreSQL 15.4 on RDS
- Multi-AZ deployment for high availability
- Performance Insights enabled
- Automated backups with 30-day retention

**Read Replicas**:
- Streaming replication to EU-West and AP-Southeast
- Cross-region automated backups
- Lag monitoring and alerting
- Conflict resolution procedures

**Backup Strategy**:
- Automated daily backups
- Cross-region backup replication
- Point-in-time recovery (PITR)
- 30-day retention policy

### Caching Strategy

**Regional Redis Clusters**:
- ElastiCache with cluster mode enabled
- Multi-AZ deployment for availability
- Encryption at rest and in transit
- Regional cache optimization

**Cache Patterns**:
- Read-through caching for database queries
- Write-behind for performance optimization
- Cache invalidation across regions
- Session storage and rate limiting

### Event Streaming

**Amazon MSK (Kafka)**:
- Multi-broker clusters in each region
- Cross-region mirroring with MirrorMaker 2.0
- Topics: events, audit-logs, notifications
- Retention: 7 days (configurable)

**Cross-Region Replication**:
- Automated topic replication
- Consistent partitioning strategy
- Conflict resolution for concurrent writes
- Monitoring and alerting

### Container Orchestration

**EKS Clusters**:
- Kubernetes 1.28 in each region
- Managed node groups with auto-scaling
- Pod security standards
- Network policies for security

**Service Mesh**:
- Istio for service-to-service communication
- mTLS for security
- Traffic management and load balancing
- Distributed tracing with Jaeger

### Monitoring & Observability

**CloudWatch Integration**:
- Custom metrics and dashboards
- Log aggregation from all services
- Automated alerting rules
- Cost and performance monitoring

**Health Checks**:
- Application-level health endpoints
- Database connectivity checks
- Cache availability monitoring
- Cross-region latency measurement

## Disaster Recovery

### Automated Failover

The infrastructure includes automated failover capabilities:

1. **Health Monitoring**: Continuous health checks every 30 seconds
2. **Failure Detection**: 3 consecutive failures trigger failover process
3. **DNS Update**: Route53 records updated to healthy region
4. **Database Promotion**: Read replica promoted to primary
5. **Service Scaling**: Auto-scaling groups adjusted for increased load

### Manual Failover

For planned maintenance or testing:

```bash
# Trigger manual failover to EU region
aws events put-events --entries '[{
  "Source": "custom.disaster-recovery",
  "DetailType": "Manual Failover Request",
  "Detail": "{\"project\":\"pyairtable\",\"environment\":\"prod\",\"action\":\"failover\",\"target_region\":\"eu-west-1\",\"reason\":\"planned-maintenance\"}"
}]'
```

### Recovery Procedures

1. **Database Recovery**: Automated promotion of read replicas
2. **Service Recovery**: EKS workloads scaled up in target region
3. **Cache Warming**: Redis clusters populated from database
4. **Validation**: Automated health checks confirm recovery
5. **Notification**: Stakeholders notified of failover completion

## Security

### Network Security

- **VPC Isolation**: Separate VPCs per region with private subnets
- **VPC Peering**: Secure cross-region communication
- **Security Groups**: Restrictive ingress/egress rules
- **NACLs**: Additional network-level protection

### Data Security

- **Encryption at Rest**: All databases and storage encrypted
- **Encryption in Transit**: TLS 1.2+ for all communications
- **Key Management**: AWS KMS with rotation enabled
- **Secrets Management**: AWS Secrets Manager for credentials

### Access Control

- **IAM Roles**: Least privilege access principles
- **RBAC**: Kubernetes role-based access control
- **MFA**: Multi-factor authentication required
- **Audit Logging**: All administrative actions logged

### Compliance

- **GDPR**: Data residency controls for EU users
- **SOC2**: Security controls and monitoring
- **ISO27001**: Information security management
- **Data Classification**: Automated tagging and classification

## Cost Optimization

### Current Optimizations

1. **Right-Sizing**: Instance types optimized for workload
2. **Auto-Scaling**: Automatic capacity adjustment
3. **Spot Instances**: Available for non-production workloads
4. **Reserved Instances**: Long-term capacity reservations
5. **S3 Lifecycle**: Automated data archival and deletion

### Monthly Cost Estimate (Production)

| Component | US-East | EU-West | AP-Southeast | Total |
|-----------|---------|---------|--------------|-------|
| EKS Clusters | $800 | $600 | $600 | $2,000 |
| RDS Databases | $1,200 | $800 | $800 | $2,800 |
| ElastiCache | $400 | $300 | $300 | $1,000 |
| MSK Kafka | $600 | $400 | $400 | $1,400 |
| CloudFront | - | - | - | $500 |
| Load Balancers | $100 | $100 | $100 | $300 |
| NAT Gateways | $150 | $150 | $150 | $450 |
| Data Transfer | $200 | $150 | $150 | $500 |
| **Total** | **$3,450** | **$2,500** | **$2,500** | **$8,950** |

*Estimates based on moderate usage. Actual costs may vary.*

### Cost Monitoring

- **Budget Alerts**: Monthly budget limits with notifications
- **Cost Anomaly Detection**: Machine learning-based anomaly detection
- **Resource Tagging**: Detailed cost allocation by service/team
- **Regular Reviews**: Monthly cost optimization assessments

## Performance Benchmarks

### Latency Targets

| Region | RTT to Users | Database Latency | Cache Latency |
|--------|--------------|------------------|---------------|
| US-East | < 50ms | < 10ms | < 2ms |
| EU-West | < 80ms | < 15ms | < 3ms |
| AP-Southeast | < 100ms | < 20ms | < 4ms |

### Throughput Targets

- **API Requests**: 10,000 requests/second per region
- **Database**: 5,000 connections, 100,000 IOPS
- **Cache**: 1M operations/second
- **Message Queue**: 100,000 messages/second

### Availability Targets

- **Overall Availability**: 99.95% (4.38 hours downtime/year)
- **Regional Availability**: 99.9% per region
- **Database Availability**: 99.95% with Multi-AZ
- **Cache Availability**: 99.9% with cluster mode

## Operational Procedures

### Daily Operations

1. **Health Checks**: Automated monitoring dashboard review
2. **Performance Metrics**: Latency and throughput monitoring
3. **Cost Monitoring**: Daily spend tracking and optimization
4. **Security Alerts**: Review and respond to security incidents

### Weekly Operations

1. **Capacity Planning**: Review auto-scaling metrics
2. **Backup Verification**: Test backup restoration procedures
3. **Performance Tuning**: Database and cache optimization
4. **Cost Optimization**: Identify unused or underutilized resources

### Monthly Operations

1. **Disaster Recovery Testing**: Full failover testing
2. **Security Audits**: Access review and vulnerability assessment
3. **Capacity Forecasting**: Growth planning and scaling decisions
4. **Cost Review**: Budget analysis and optimization recommendations

### Incident Response

1. **Alert Triage**: 24/7 monitoring and alerting
2. **Escalation**: Automated escalation to on-call engineers
3. **Communication**: Status page updates and stakeholder notifications
4. **Resolution**: Automated and manual remediation procedures
5. **Post-Incident**: Root cause analysis and improvement planning

## Troubleshooting

### Common Issues

**Database Connection Issues**:
```bash
# Check database status
aws rds describe-db-instances --region us-east-1

# Test connectivity
psql -h [endpoint] -U [username] -d [database] -c "SELECT 1;"
```

**Cache Connection Issues**:
```bash
# Check Redis cluster status
aws elasticache describe-replication-groups --region us-east-1

# Test connectivity (from EC2 instance)
redis-cli -h [endpoint] ping
```

**DNS Resolution Issues**:
```bash
# Check Route53 health checks
aws route53 get-health-check --health-check-id [id]

# Test DNS resolution
dig api.yourdomain.com
nslookup api.yourdomain.com
```

**EKS Connectivity Issues**:
```bash
# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name [cluster-name]

# Check cluster status
kubectl cluster-info
kubectl get nodes
```

### Monitoring Commands

```bash
# View CloudWatch logs
aws logs describe-log-groups
aws logs get-log-events --log-group-name [group] --log-stream-name [stream]

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ELB \
  --metric-name RequestCount \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum

# View Route53 health check status
aws route53 list-health-checks
aws route53 get-health-check-status --health-check-id [id]
```

## Maintenance

### Regular Maintenance Tasks

1. **Certificate Renewal**: SSL certificates (automated with ACM)
2. **Security Updates**: OS and application patches
3. **Database Maintenance**: Minor version upgrades during maintenance windows
4. **Cache Maintenance**: Redis parameter group updates
5. **EKS Updates**: Kubernetes version upgrades

### Planned Maintenance Windows

- **Database**: Sundays 04:00-05:00 UTC
- **Cache**: Sundays 05:00-06:00 UTC  
- **EKS**: Saturdays 02:00-04:00 UTC
- **Network**: As needed with 7-day notice

## Support

### Documentation

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

### Contacts

- **Platform Team**: platform-team@yourcompany.com
- **On-Call**: +1-XXX-XXX-XXXX
- **Slack**: #platform-support

### Emergency Procedures

1. **Severity 1 (Critical)**: Page on-call engineer immediately
2. **Severity 2 (High)**: Create incident ticket, notify team
3. **Severity 3 (Medium)**: Create ticket for next business day
4. **Severity 4 (Low)**: Add to backlog for future sprint

---

## License

This infrastructure code is proprietary to PyAirtable. All rights reserved.

## Contributing

Please follow the infrastructure change management process:

1. Create feature branch from main
2. Make infrastructure changes
3. Test in development environment
4. Submit pull request with terraform plan output
5. Obtain approvals from platform team
6. Deploy to staging for validation
7. Deploy to production during maintenance window

For questions or support, contact the Platform Team.