# PyAirtable Cloud Deployment Runbook

## Overview

This runbook provides comprehensive instructions for deploying PyAirtable's hybrid microservices architecture to AWS EKS in Central Europe (eu-central-1) region. The infrastructure is optimized for your European clients with three environments: local, dev, and prod.

## Architecture Summary

### Infrastructure Components

1. **EKS Cluster**: Kubernetes 1.28 with hybrid node groups
2. **Node Groups**: 
   - Go Services: Compute-optimized (t3.medium/large → c5.large/xlarge)
   - Python AI: Memory-optimized (r5.large/xlarge → r5.xlarge/2xlarge)
   - General: Balanced (t3.medium/large → m5.large/xlarge)
3. **Database**: Aurora Serverless v2 PostgreSQL + ElastiCache Redis
4. **Serverless**: Lambda functions for batch processing
5. **CI/CD**: CodePipeline with multi-environment deployment
6. **Monitoring**: CloudWatch + Prometheus on EKS

### Service Distribution

**22 Total Services:**
- **Go Services (High Performance)**: API Gateway, Platform Services 
- **Python Services (AI/ML Heavy)**: LLM Orchestrator, MCP Server
- **General Services**: Airtable Gateway, Automation Services, Frontend
- **Infrastructure**: PostgreSQL, Redis, Lambda Functions, Monitoring

## Prerequisites

### Required Tools
```bash
# Install required CLI tools
brew install terraform
brew install kubectl  
brew install helm
brew install aws-cli
```

### AWS Setup
```bash
# Configure AWS CLI
aws configure
# Or use AWS SSO
aws sso login --profile your-profile

# Verify access
aws sts get-caller-identity
aws eks list-clusters --region eu-central-1
```

### Environment Variables
Create `.env` files for each environment:

```bash
# .env.local
AWS_PROFILE=your-profile
AWS_REGION=eu-central-1
POSTGRES_PASSWORD=your-secure-password
REDIS_AUTH_TOKEN=your-redis-token
GITHUB_TOKEN=your-github-token
```

## Deployment Process

### 1. Infrastructure Deployment

#### Local Environment
```bash
cd infrastructure/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var-file="environments/local.tfvars" -out=local.tfplan

# Apply infrastructure
terraform apply local.tfplan

# Configure kubectl
aws eks update-kubeconfig --region eu-central-1 --name pyairtable-dev
```

#### Development Environment
```bash
# Switch to dev workspace
terraform workspace new dev || terraform workspace select dev

# Plan and apply
terraform plan -var-file="environments/dev.tfvars" -out=dev.tfplan
terraform apply dev.tfplan

# Update kubeconfig
aws eks update-kubeconfig --region eu-central-1 --name pyairtable-dev
```

#### Production Environment
```bash
# Switch to prod workspace
terraform workspace new prod || terraform workspace select prod

# Plan with careful review
terraform plan -var-file="environments/prod.tfvars" -out=prod.tfplan

# Review plan carefully before applying
terraform show prod.tfplan

# Apply infrastructure
terraform apply prod.tfplan

# Update kubeconfig
aws eks update-kubeconfig --region eu-central-1 --name pyairtable-prod
```

### 2. Application Deployment

#### Kubernetes Resources
```bash
# Navigate to k8s directory
cd ../k8s/

# Deploy secrets (update with your values)
kubectl create namespace pyairtable
kubectl apply -f secrets.yaml

# Deploy Helm chart
helm install pyairtable-stack helm/pyairtable-stack/ \
  --namespace pyairtable \
  --values helm/pyairtable-stack/values-${ENVIRONMENT}.yaml
```

#### Verify Deployment
```bash
# Check pods
kubectl get pods -n pyairtable

# Check services
kubectl get svc -n pyairtable

# Check ingress
kubectl get ingress -n pyairtable

# View logs
kubectl logs -f deployment/api-gateway -n pyairtable
```

### 3. CI/CD Pipeline Setup

#### GitHub Repository Setup
1. Fork the repository to your GitHub account
2. Add repository secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `GEMINI_API_KEY`
   - `AIRTABLE_TOKEN`

#### Pipeline Configuration
```bash
# The pipeline is automatically created by Terraform
# Check pipeline status
aws codepipeline list-pipelines --region eu-central-1
aws codepipeline get-pipeline-state --name pyairtable-dev-microservices-pipeline
```

## Environment-Specific Configurations

### Local Environment
- **Purpose**: Local development with minimal resources
- **Compute**: Spot instances, minimal node counts
- **Database**: Aurora Serverless min 0.5 ACU
- **Monitoring**: Basic CloudWatch logs (7 days retention)
- **Cost**: ~$150-200/month

### Development Environment
- **Purpose**: Integration testing and QA
- **Compute**: Spot instances with reasonable scaling
- **Database**: Aurora Serverless up to 4 ACU
- **Monitoring**: Standard logging (14 days retention)
- **Cost**: ~$300-400/month

### Production Environment
- **Purpose**: Live system serving Central Europe clients
- **Compute**: On-demand instances for reliability
- **Database**: Aurora Serverless up to 16 ACU with read replicas
- **Monitoring**: Full observability (30 days retention)
- **Security**: Maximum security policies enabled
- **Cost**: ~$800-1200/month (scales with usage)

## Service Resource Allocation

### Go Services (High Performance, Low Memory)
```yaml
api-gateway:
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits: { cpu: 500m, memory: 512Mi }
  nodeSelector: { workload: go-services }
  
platform-services:
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits: { cpu: 500m, memory: 512Mi }
  nodeSelector: { workload: go-services }
```

### Python AI Services (AI/ML Heavy)
```yaml
llm-orchestrator:
  resources:
    requests: { cpu: 500m, memory: 512Mi }
    limits: { cpu: 1000m, memory: 1Gi }
  nodeSelector: { workload: python-ai }
  
mcp-server:
  resources:
    requests: { cpu: 250m, memory: 256Mi }
    limits: { cpu: 500m, memory: 512Mi }
  nodeSelector: { workload: python-ai }
```

### Serverless Functions
- **File Processor**: Python 3.11, 1024MB memory, 300s timeout
- **Workflow Processor**: Go binary, 512MB memory, 180s timeout
- **Deployment Orchestrator**: Python 3.11, 512MB memory, 900s timeout

## Cost Optimization Features

### Enabled by Default
1. **Spot Instances**: 70% cost savings on compute
2. **Aurora Serverless v2**: Pay for actual usage
3. **Cluster Autoscaler**: Scale nodes based on demand
4. **Horizontal Pod Autoscaler**: Scale pods based on CPU/memory
5. **Scheduled Scaling**: Scale down during off-hours (non-prod)

### Additional Optimizations
1. **Reserved Instances**: For predictable workloads (consider after 3 months)
2. **Savings Plans**: Compute savings plans for consistent usage
3. **Storage Optimization**: Different EBS types for different workloads
4. **Data Transfer Optimization**: Keep traffic within same AZ when possible

## Monitoring and Observability

### CloudWatch Dashboards
- **Infrastructure**: EKS cluster, nodes, and resources
- **Applications**: Service metrics, request rates, error rates
- **CI/CD**: Pipeline execution, build times, deployment success

### Alerts and Notifications
- **Cost Alerts**: Budget threshold notifications
- **Performance Alerts**: High CPU, memory usage
- **Error Rate Alerts**: Application error thresholds
- **Infrastructure Alerts**: Node failures, storage issues

### Log Management
- **Application Logs**: Centralized in CloudWatch Logs
- **Infrastructure Logs**: EKS control plane logs
- **Audit Logs**: API access and security events

## Security Best Practices

### Network Security
- **VPC**: Private subnets for all compute resources
- **Security Groups**: Minimal required access
- **Network Policies**: Kubernetes network segmentation
- **NAT Gateways**: Secure outbound internet access

### Identity and Access Management
- **IAM Roles**: Service-specific permissions
- **RBAC**: Kubernetes role-based access control
- **Pod Security Standards**: Enforce security policies
- **Secrets Management**: AWS Secrets Manager integration

### Data Protection
- **Encryption**: At rest and in transit
- **Backup**: Automated database backups
- **Audit Logging**: All API calls logged
- **Compliance**: SOC 2 Type II ready

## Disaster Recovery

### Backup Strategy
- **Database**: Daily automated backups with 30-day retention
- **Application Data**: S3 versioning and lifecycle policies
- **Configuration**: Infrastructure as Code in Git

### Recovery Procedures
1. **Database Recovery**: Point-in-time recovery from Aurora backups
2. **Infrastructure Recovery**: Terraform re-deployment
3. **Application Recovery**: Container registry and CI/CD pipeline

### RTO/RPO Targets
- **RTO (Recovery Time Objective)**: 4 hours
- **RPO (Recovery Point Objective)**: 1 hour

## Troubleshooting Guide

### Common Issues

#### Pod Scheduling Issues
```bash
# Check node resources
kubectl describe nodes

# Check pod events
kubectl describe pod <pod-name> -n pyairtable

# Check node taints and tolerations
kubectl get nodes -o custom-columns="NAME:.metadata.name,TAINTS:.spec.taints"
```

#### Database Connection Issues
```bash
# Check Aurora cluster status
aws rds describe-db-clusters --region eu-central-1

# Test connectivity from pod
kubectl exec -it <pod-name> -n pyairtable -- nc -zv <rds-endpoint> 5432
```

#### Application Performance Issues
```bash
# Check resource usage
kubectl top pods -n pyairtable
kubectl top nodes

# Check HPA status
kubectl get hpa -n pyairtable
```

### Support Contacts
- **Infrastructure**: DevOps team
- **Applications**: Development team
- **Security**: Security team
- **On-call**: 24/7 monitoring and alerting

## Cost Monitoring

### Current Estimates
- **Local**: $150-200/month
- **Dev**: $300-400/month  
- **Prod**: $800-1200/month

### Cost Breakdown
- **Compute (40%)**: EKS nodes and Fargate
- **Database (25%)**: Aurora Serverless and Redis
- **Storage (15%)**: EBS volumes and S3
- **Network (10%)**: Load balancers and data transfer
- **Other (10%)**: Lambda, monitoring, CI/CD

### Optimization Opportunities
1. **Spot Fleet**: Additional 20% savings on compute
2. **Reserved Instances**: Up to 75% savings on predictable workloads
3. **Storage Optimization**: Tiered storage for different access patterns
4. **Network Optimization**: VPC endpoints for AWS services

## Next Steps

1. **Deploy Local Environment**: Start with local for testing
2. **Set Up Monitoring**: Configure alerts and dashboards
3. **Deploy Dev Environment**: Full integration testing
4. **Performance Testing**: Load testing and optimization
5. **Deploy Production**: Gradual rollout with monitoring
6. **Optimize Costs**: Monitor usage patterns and optimize
7. **Scale Operations**: Add more services as needed

This runbook provides a comprehensive guide for deploying and managing your PyAirtable infrastructure. The focus on Central Europe ensures optimal performance for your clients while maintaining cost efficiency and operational excellence.