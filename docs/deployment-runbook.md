# Deployment Runbook

## Overview

This runbook provides step-by-step procedures for deploying PyAirtable microservices to AWS ECS Fargate using our CI/CD pipeline.

## Architecture Overview

### Services
- **frontend** (Next.js) - Port 3000
- **api-gateway** (FastAPI) - Port 8000  
- **llm-orchestrator** (FastAPI + Gemini) - Port 8003
- **mcp-server** (FastAPI) - Port 8001
- **airtable-gateway** (FastAPI) - Port 8002
- **platform-services** (FastAPI) - Port 8007
- **automation-services** (FastAPI) - Port 8006

### Environments
- **Development** - Auto-deploy from `develop` branch
- **Staging** - Auto-deploy from `staging` branch  
- **Production** - Auto-deploy from `main` branch (requires approval)

## Pre-Deployment Checklist

### Infrastructure Requirements
- [ ] AWS credentials configured in GitHub Secrets
- [ ] ECR repositories created for all services
- [ ] ECS cluster and services deployed via Terraform
- [ ] RDS PostgreSQL database running
- [ ] ElastiCache Redis cluster running
- [ ] Application Load Balancer configured

### GitHub Secrets Required
```
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_ACCOUNT_ID
SEMGREP_APP_TOKEN (optional)
```

### Environment Variables in AWS Systems Manager
```
/pyairtable/{environment}/api-key
/pyairtable/{environment}/database-url
/pyairtable/{environment}/redis-url
/pyairtable/{environment}/gemini-api-key
/pyairtable/{environment}/airtable-token
/pyairtable/{environment}/airtable-base
```

## Deployment Procedures

### 1. Automated Deployment (Recommended)

#### Development Deployment
1. Create feature branch from `develop`
2. Make changes and push to feature branch
3. Create PR to `develop` branch
4. Wait for PR validation to complete
5. Merge PR - automatic deployment begins
6. Monitor deployment in Actions tab

#### Staging Deployment  
1. Create PR from `develop` to `staging`
2. Get approval from team lead
3. Merge PR - automatic deployment begins
4. Run staging tests to verify deployment

#### Production Deployment
1. Create PR from `staging` to `main`
2. Get approval from both team members
3. Merge PR - automatic deployment begins
4. Monitor production metrics closely

### 2. Manual Deployment (Emergency Use)

#### Trigger Manual Deployment
1. Go to GitHub Actions → "Build and Deploy Microservices"
2. Click "Run workflow"
3. Select:
   - **Environment**: dev/staging/prod
   - **Service**: all or specific service
4. Monitor deployment progress

#### Manual Service Restart
```bash
# Configure AWS CLI
aws configure set aws_access_key_id YOUR_ACCESS_KEY
aws configure set aws_secret_access_key YOUR_SECRET_KEY
aws configure set default.region us-east-1

# Restart specific service
aws ecs update-service \
  --cluster pyairtable-{environment} \
  --service pyairtable-{service}-{environment} \
  --force-new-deployment

# Example: Restart API Gateway in production
aws ecs update-service \
  --cluster pyairtable-prod \
  --service pyairtable-api-gateway-prod \
  --force-new-deployment
```

## Health Check Procedures

### 1. Service Health Verification

#### Automated Health Checks
Services are automatically health-checked during deployment:
- **HTTP Health Endpoints**: `/health` for backend services, `/api/health` for frontend
- **ECS Health Checks**: Container-level health monitoring
- **ALB Health Checks**: Load balancer target group health

#### Manual Health Verification
```bash
# Check service health via load balancer
curl -f https://api-{environment}.yourdomain.com/health

# Check individual service health
curl -f https://api-{environment}.yourdomain.com/{service}/health

# Examples
curl -f https://api-dev.yourdomain.com/api-gateway/health
curl -f https://api-dev.yourdomain.com/llm-orchestrator/health
curl -f https://api-dev.yourdomain.com/mcp-server/health
```

### 2. Infrastructure Health Checks

#### ECS Service Status
```bash
# Check all services in cluster
aws ecs list-services --cluster pyairtable-{environment}

# Check specific service details
aws ecs describe-services \
  --cluster pyairtable-{environment} \
  --services pyairtable-{service}-{environment}

# Check task health
aws ecs list-tasks --cluster pyairtable-{environment}
aws ecs describe-tasks --cluster pyairtable-{environment} --tasks TASK_ARN
```

#### Database Health
```bash
# Check RDS instance
aws rds describe-db-instances --db-instance-identifier pyairtable-{environment}-db

# Check ElastiCache cluster
aws elasticache describe-cache-clusters --cache-cluster-id pyairtable-{environment}-redis
```

## Rollback Procedures

### 1. Automated Rollback

#### GitHub Actions Rollback
1. Go to GitHub Actions → "Rollback Deployment"
2. Click "Run workflow"
3. Select:
   - **Environment**: dev/staging/prod
   - **Service**: all or specific service
   - **Rollback Steps**: number of deployments to rollback (default: 1)
4. Confirm rollback initiation
5. Monitor rollback progress

### 2. Manual Rollback

#### ECS Service Rollback
```bash
# Get current task definition
CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster pyairtable-{environment} \
  --services pyairtable-{service}-{environment} \
  --query 'services[0].taskDefinition' --output text)

# Get task definition family and revision
FAMILY=$(echo $CURRENT_TASK_DEF | cut -d':' -f6)
CURRENT_REVISION=$(echo $CURRENT_TASK_DEF | cut -d':' -f7)
ROLLBACK_REVISION=$((CURRENT_REVISION - 1))

# Rollback to previous revision
aws ecs update-service \
  --cluster pyairtable-{environment} \
  --service pyairtable-{service}-{environment} \
  --task-definition "$FAMILY:$ROLLBACK_REVISION"

# Wait for rollback to complete
aws ecs wait services-stable \
  --cluster pyairtable-{environment} \
  --services pyairtable-{service}-{environment}
```

#### Database Rollback (If Required)
```bash
# Create snapshot before rollback
aws rds create-db-snapshot \
  --db-instance-identifier pyairtable-{environment}-db \
  --db-snapshot-identifier pyairtable-{environment}-pre-rollback-$(date +%Y%m%d-%H%M%S)

# If database changes need to be reverted, use migration rollback
# This should be done through application-level migrations
```

## Monitoring and Alerting

### 1. CloudWatch Metrics

#### Key Metrics to Monitor
- **ECS Service**: CPU utilization, memory utilization, task count
- **ALB**: Request count, response time, error rate
- **RDS**: CPU utilization, database connections, read/write IOPS
- **ElastiCache**: CPU utilization, cache hit rate, evictions

#### CloudWatch Dashboard
Access via AWS Console → CloudWatch → Dashboards → "PyAirtable-{Environment}"

### 2. Application Logs

#### ECS Logs
```bash
# View service logs
aws logs get-log-events \
  --log-group-name /ecs/pyairtable-{environment} \
  --log-stream-name {service}/pyairtable-{service}-{environment}/TASK_ID

# Tail logs (requires AWS CLI v2)
aws logs tail /ecs/pyairtable-{environment} --follow
```

#### Log Analysis
- **Error Patterns**: Search for "ERROR", "CRITICAL", "Exception"
- **Performance Issues**: Look for slow response times
- **Health Check Failures**: Monitor health endpoint errors

### 3. Alerting

#### CloudWatch Alarms
- **High CPU Usage**: > 80% for 5 minutes
- **High Memory Usage**: > 90% for 5 minutes
- **Health Check Failures**: > 3 consecutive failures
- **High Error Rate**: > 5% error rate for 5 minutes

## Troubleshooting Guide

### Common Issues

#### 1. Service Won't Start
**Symptoms**: Tasks keep stopping, health checks failing
**Troubleshooting**:
```bash
# Check task logs
aws ecs describe-tasks --cluster pyairtable-{environment} --tasks TASK_ARN

# Check service events
aws ecs describe-services \
  --cluster pyairtable-{environment} \
  --services pyairtable-{service}-{environment} \
  --query 'services[0].events'

# Common fixes:
# - Check environment variables in task definition
# - Verify secrets in Systems Manager
# - Check Docker image exists in ECR
# - Verify security group rules
```

#### 2. Database Connection Issues
**Symptoms**: Services report database connection errors
**Troubleshooting**:
```bash
# Check database status
aws rds describe-db-instances --db-instance-identifier pyairtable-{environment}-db

# Check security groups
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test connection from ECS task
aws ecs execute-command \
  --cluster pyairtable-{environment} \
  --task TASK_ARN \
  --container {service} \
  --interactive \
  --command "/bin/bash"

# Inside container:
nc -zv DATABASE_HOST 5432
```

#### 3. Load Balancer Issues
**Symptoms**: 503 errors, services unreachable
**Troubleshooting**:
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn TARGET_GROUP_ARN

# Check ALB logs (if enabled)
aws s3 ls s3://your-alb-logs-bucket/

# Common fixes:
# - Verify health check configuration
# - Check security group rules
# - Verify service registration
```

#### 4. High Resource Usage
**Symptoms**: Services running slowly, scaling issues
**Actions**:
```bash
# Scale up service manually
aws ecs update-service \
  --cluster pyairtable-{environment} \
  --service pyairtable-{service}-{environment} \
  --desired-count 3

# Check resource utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=pyairtable-{service}-{environment} Name=ClusterName,Value=pyairtable-{environment} \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

## Emergency Procedures

### 1. Complete System Outage

#### Immediate Response
1. **Assess Impact**: Check all services and determine scope
2. **Communicate**: Notify stakeholders of outage
3. **Investigate**: Check recent deployments, infrastructure changes
4. **Isolate**: If deployment-related, immediately rollback

#### Recovery Steps
```bash
# 1. Rollback all services to last known good version
for service in frontend api-gateway llm-orchestrator mcp-server airtable-gateway platform-services automation-services; do
  aws ecs update-service \
    --cluster pyairtable-prod \
    --service pyairtable-$service-prod \
    --task-definition pyairtable-$service-prod:LAST_GOOD_REVISION
done

# 2. Scale up if needed
for service in frontend api-gateway llm-orchestrator mcp-server airtable-gateway platform-services automation-services; do
  aws ecs update-service \
    --cluster pyairtable-prod \
    --service pyairtable-$service-prod \
    --desired-count 3
done

# 3. Monitor recovery
aws ecs wait services-stable --cluster pyairtable-prod --services pyairtable-frontend-prod pyairtable-api-gateway-prod
```

### 2. Database Emergency

#### Database Failure
```bash
# 1. Check database status
aws rds describe-db-instances --db-instance-identifier pyairtable-prod-db

# 2. If needed, restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier pyairtable-prod-db-restore \
  --db-snapshot-identifier pyairtable-prod-db-snapshot-YYYYMMDD

# 3. Update services to use new database
# Update database URL in Systems Manager Parameter Store
```

### 3. Security Incident

#### Immediate Actions
1. **Isolate**: Remove public access if compromised
2. **Investigate**: Check logs for suspicious activity
3. **Rotate**: Rotate all secrets and access keys
4. **Patch**: Apply emergency patches if needed

```bash
# Remove public access (emergency)
aws ec2 revoke-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Rotate secrets
aws ssm put-parameter \
  --name "/pyairtable/prod/api-key" \
  --value "NEW_API_KEY" \
  --type "SecureString" \
  --overwrite
```

## Post-Deployment Verification

### 1. Functional Testing
- [ ] All service health checks passing
- [ ] Frontend application loading correctly
- [ ] API endpoints responding correctly
- [ ] Database connections working
- [ ] Redis caching functional

### 2. Performance Testing
- [ ] Response times within acceptable range
- [ ] Resource utilization normal
- [ ] Auto-scaling working if configured
- [ ] Load balancer distributing traffic correctly

### 3. Security Validation
- [ ] No exposed sensitive information
- [ ] HTTPS working correctly
- [ ] Security groups properly configured
- [ ] Secrets properly managed

## Contact Information

### Team Contacts
- **Primary DevOps**: [Contact Info]
- **Secondary DevOps**: [Contact Info]
- **Team Lead**: [Contact Info]

### Emergency Escalation
1. **Level 1**: Team members
2. **Level 2**: Technical lead
3. **Level 3**: Management

### Key Resources
- **AWS Console**: https://console.aws.amazon.com
- **GitHub Repository**: https://github.com/your-org/pyairtable-compose
- **Monitoring Dashboard**: [CloudWatch Dashboard URL]
- **Documentation**: [Documentation URL]