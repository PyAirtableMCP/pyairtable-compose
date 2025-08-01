# PyAirtable Infrastructure Deployment Guide

This guide is designed for a 2-person team to deploy and maintain the PyAirtable microservices infrastructure.

## Prerequisites

1. **AWS CLI configured** with appropriate permissions
2. **Terraform 1.5+** installed
3. **Docker** for building container images

## Quick Start

### 1. One-Time Setup

```bash
# 1. Create S3 bucket for Terraform state (do this once)
aws s3 mb s3://pyairtable-terraform-state --region us-east-1
aws s3api put-bucket-versioning --bucket pyairtable-terraform-state --versioning-configuration Status=Enabled

# 2. Create backend config file
cat > backend-config.hcl << EOF
bucket = "pyairtable-terraform-state"
key    = "terraform.tfstate"
region = "us-east-1"
EOF
```

### 2. Deploy Development Environment

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init -backend-config=backend-config.hcl

# Deploy development
terraform workspace new dev || terraform workspace select dev
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### 3. Deploy Production Environment

```bash
# Deploy production
terraform workspace new prod || terraform workspace select prod
terraform plan -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars
```

## Container Deployment

After infrastructure is deployed, deploy your applications:

```bash
# Get ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Build and push each service (example for api-gateway)
cd ../../pyairtable-automation-services  # Your service directory
docker build -t pyairtable-api-gateway .
docker tag pyairtable-api-gateway:latest YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/pyairtable-api-gateway:latest
docker push YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/pyairtable-api-gateway:latest

# Update ECS service
aws ecs update-service --cluster pyairtable-dev-cluster --service pyairtable-dev-api-gateway --force-new-deployment
```

## Day-to-Day Operations

### View Application Logs

```bash
# View logs for a specific service
aws logs tail "/ecs/pyairtable-dev" --follow --filter-pattern "api-gateway"
```

### Check Service Health

```bash
# Get load balancer URL
terraform output application_url

# Test your services
curl http://YOUR_ALB_DNS/api-gateway/health
curl http://YOUR_ALB_DNS/mcp-server/health
```

### Update Infrastructure

```bash
# Make changes to .tfvars files, then:
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### Scale Services

```bash
# Update desired_count in your .tfvars file, then apply
# Or use AWS CLI for quick scaling:
aws ecs update-service --cluster pyairtable-dev-cluster --service pyairtable-dev-api-gateway --desired-count 2
```

## Production Considerations

### SSL Certificate Setup

1. Request certificate in AWS Certificate Manager
2. Verify domain ownership
3. Update `certificate_arn` in `prod.tfvars`
4. Set up Route 53 hosted zone and update `domain_name`

### Monitoring Setup

The infrastructure includes basic CloudWatch monitoring. For production:

1. Set up CloudWatch dashboards
2. Configure SNS alerts (email configured via `alert_email` variable)
3. Monitor ECS service health and ALB metrics

### Database Management

```bash
# Connect to database (from an EC2 instance or ECS task)
psql $DATABASE_URL

# Create database backups (automated, but for manual backup)
aws rds create-db-snapshot --db-instance-identifier pyairtable-prod --db-snapshot-identifier manual-backup-$(date +%Y%m%d)
```

### Security Best Practices

1. **Secrets Management**: Store API keys and secrets in SSM Parameter Store
   ```bash
   aws ssm put-parameter --name "/pyairtable/prod/openai-api-key" --type "SecureString" --value "your-api-key"
   ```

2. **Network Security**: Services are isolated in private subnets with proper security groups

3. **Encryption**: All data is encrypted at rest and in transit

## Troubleshooting

### Common Issues

1. **ECS Task Won't Start**
   ```bash
   # Check task definition and logs
   aws ecs describe-services --cluster pyairtable-dev-cluster --services pyairtable-dev-api-gateway
   aws logs describe-log-streams --log-group-name "/ecs/pyairtable-dev"
   ```

2. **Database Connection Issues**
   ```bash
   # Check security groups and parameter store
   aws ssm get-parameter --name "/pyairtable/dev/database-url" --with-decryption
   ```

3. **Load Balancer 503 Errors**
   ```bash
   # Check target group health
   aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
   ```

### Getting Help

1. Check CloudWatch logs first
2. Verify security group rules
3. Check ECS service events
4. Review Terraform state for configuration issues

## Cost Management

### Development Environment
- Uses Spot instances when possible
- Single NAT Gateway
- Minimal database and Redis instances
- No enhanced monitoring

### Production Environment
- Uses on-demand instances for reliability
- Multi-AZ database for high availability
- Enhanced monitoring enabled
- Automated backups configured

### Cost Monitoring
Set up AWS Budgets to monitor spending:
```bash
aws budgets create-budget --account-id YOUR_ACCOUNT --budget file://budget.json
```

## Maintenance Tasks

### Monthly
- Review CloudWatch costs and usage
- Update container images with security patches
- Review and rotate secrets if needed

### Quarterly
- Review Terraform modules for updates
- Update AWS provider version
- Review security group rules and access patterns

## Emergency Procedures

### Rolling Back Deployments
```bash
# Rollback to previous task definition
aws ecs update-service --cluster pyairtable-prod-cluster --service pyairtable-prod-api-gateway --task-definition pyairtable-api-gateway-prod:PREVIOUS_REVISION
```

### Database Recovery
```bash
# Restore from automated backup
aws rds restore-db-instance-from-db-snapshot --db-instance-identifier pyairtable-prod-restored --db-snapshot-identifier SNAPSHOT_ID
```

This guide provides the essentials for managing your PyAirtable infrastructure. Keep it simple, monitor regularly, and scale as needed.