# PyAirtable Production Deployment Guide

This guide provides step-by-step instructions for deploying PyAirtable to AWS EKS production environment.

## 🏗️ Architecture Overview

### Infrastructure Components
- **EKS Cluster**: Kubernetes cluster with multi-AZ node groups
- **RDS PostgreSQL**: Multi-AZ database with automated backups
- **ElastiCache Redis**: High-availability Redis cluster
- **Application Load Balancer**: SSL termination and traffic distribution
- **AWS Secrets Manager**: Secure credential management
- **CloudWatch**: Comprehensive monitoring and logging
- **LGTM Stack**: Prometheus, Grafana, and Loki for observability

### Microservices Architecture
- **API Gateway** (Port 8000): Main entry point and request routing
- **LLM Orchestrator** (Port 8003): Gemini 2.5 Flash integration
- **MCP Server** (Port 8001): Protocol implementation
- **Airtable Gateway** (Port 8002): Direct Airtable API integration
- **Platform Services** (Port 8007): Authentication and analytics
- **Automation Services** (Port 8006): File processing and workflows
- **SAGA Orchestrator** (Port 8008): Distributed transaction coordination
- **Frontend** (Port 3000): Next.js web interface

## 📋 Prerequisites

### Required Tools
```bash
# AWS CLI
aws --version

# kubectl
kubectl version --client

# Terraform
terraform version

# Helm
helm version

# Docker (for local testing)
docker --version
```

### AWS Requirements
- AWS Account with administrative access
- Domain name for SSL certificates
- ACM certificate for your domain
- S3 bucket for Terraform state (created automatically)
- DynamoDB table for Terraform locking (created automatically)

### AWS Permissions Required
The deployment requires the following AWS services:
- EKS (Elastic Kubernetes Service)
- EC2 (Elastic Compute Cloud)
- RDS (Relational Database Service)
- ElastiCache
- VPC (Virtual Private Cloud)
- IAM (Identity and Access Management)
- Secrets Manager
- CloudWatch
- Application Load Balancer
- Route 53 (for DNS)
- ACM (AWS Certificate Manager)

## 🚀 Deployment Steps

### Step 1: Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd pyairtable-compose

# Set up environment
export AWS_REGION="us-west-2"
export PROJECT_NAME="pyairtable"
export ENVIRONMENT="production"
```

### Step 2: Configure Terraform Variables

Edit `infrastructure/aws-eks/terraform.tfvars`:

```hcl
# Update these values for your deployment
aws_region = "us-west-2"
environment = "production"
cost_alert_emails = ["your-email@domain.com"]

# Update secrets with real values
secrets_config = {
  "pyairtable/production/api" = {
    description = "Production API keys and tokens"
    secret_string = {
      airtable_token    = "YOUR_AIRTABLE_TOKEN"
      gemini_api_key    = "YOUR_GEMINI_API_KEY"
      api_key           = "YOUR_INTERNAL_API_KEY"
      # ... other secrets
    }
  }
}
```

### Step 3: Update SSL Configuration

Update the certificate ARNs in the Kubernetes manifests:

```bash
# Get your ACM certificate ARN
aws acm list-certificates --region us-west-2

# Update the certificate ARN in:
# - k8s/production/10-ingress-alb.yaml
# Replace CERTIFICATE_ID with your actual certificate ID
```

### Step 4: Deploy Infrastructure

```bash
# Run the automated deployment script
./scripts/deploy-production-eks.sh
```

This script will:
1. Run pre-flight checks
2. Deploy EKS infrastructure with Terraform
3. Configure kubectl
4. Install necessary Kubernetes addons
5. Deploy all microservices
6. Set up monitoring stack
7. Validate the deployment

### Step 5: Configure DNS

After deployment, update your DNS records:

```bash
# Get the Load Balancer endpoints
kubectl get ingress -n pyairtable-production

# Create DNS records:
# pyairtable.com -> Frontend ALB
# www.pyairtable.com -> Frontend ALB  
# api.pyairtable.com -> API ALB
```

### Step 6: Validate Deployment

```bash
# Run comprehensive validation
./scripts/validate-production-deployment.sh
```

## 🔧 Configuration Management

### Environment Variables

The deployment uses AWS Secrets Manager for secure configuration. Update these secrets:

1. **API Keys** (`pyairtable/production/api-keys`):
   - `airtable_token`: Your Airtable API token
   - `gemini_api_key`: Google Gemini API key
   - `api_key`: Internal API key for service communication

2. **Database** (`pyairtable/production/database`):
   - Automatically configured by Terraform
   - Contains database connection strings

3. **Application Config** (`pyairtable/production/app-config`):
   - CORS settings
   - Feature flags
   - Workflow timeouts

### SSL/TLS Certificates

The deployment uses AWS Certificate Manager (ACM) for SSL certificates:

1. Request certificates for your domains in ACM
2. Validate domain ownership
3. Update the certificate ARNs in the ingress configuration

## 📊 Monitoring and Observability

### LGTM Stack Components

1. **Prometheus**: Metrics collection and alerting
   - Endpoint: `http://<grafana-lb>:9090`
   - Scrapes metrics from all services

2. **Grafana**: Visualization and dashboards
   - Endpoint: `http://<grafana-lb>:3000`
   - Default credentials: `admin/admin123`

3. **Loki**: Log aggregation
   - Integrated with Grafana for log queries

### CloudWatch Integration

- **Container Insights**: EKS cluster metrics
- **Application Logs**: Centralized logging
- **Custom Metrics**: Business metrics from services
- **Alarms**: Automated alerting for critical issues

### Key Metrics to Monitor

- **Service Health**: Uptime and response times
- **Resource Usage**: CPU, memory, storage
- **Database Performance**: Connection count, query times
- **Error Rates**: HTTP 5xx responses
- **Cost Metrics**: AWS spend tracking

## 💰 Cost Optimization

### Monthly Cost Estimate

| Component | Estimated Cost |
|-----------|----------------|
| EKS Cluster | ~$73/month |
| EC2 Instances (mixed spot/on-demand) | ~$150-300/month |
| RDS PostgreSQL (Multi-AZ) | ~$50-100/month |
| ElastiCache Redis | ~$25-50/month |
| Load Balancers | ~$25/month |
| Data Transfer | ~$10-50/month |
| **Total** | **~$333-598/month** |

### Cost Optimization Features

1. **Spot Instances**: 70% of nodes use spot instances for cost savings
2. **ARM64 Nodes**: Better price/performance ratio
3. **Auto-scaling**: Automatic scaling based on demand
4. **Karpenter**: Advanced node provisioning and optimization
5. **Storage Optimization**: GP3 volumes with optimal IOPS
6. **Reserved Capacity**: Option for production workloads

## 🔒 Security Features

### Network Security
- **VPC**: Isolated network environment
- **Network Policies**: Pod-to-pod communication restrictions
- **Security Groups**: Fine-grained access control
- **Private Subnets**: Database and internal services isolation

### Application Security
- **Non-root Containers**: All containers run as non-root users
- **Resource Limits**: CPU and memory constraints
- **Secret Management**: AWS Secrets Manager integration
- **RBAC**: Kubernetes role-based access control

### Data Security
- **Encryption at Rest**: RDS, ElastiCache, and EBS volumes
- **Encryption in Transit**: TLS for all communications
- **Backup Encryption**: Automated encrypted backups
- **Key Management**: AWS KMS for encryption keys

## 🔄 Scaling Configuration

### Horizontal Pod Autoscaler (HPA)
- **CPU Threshold**: 70% average utilization
- **Memory Threshold**: 80% average utilization
- **Min/Max Replicas**: Service-specific scaling limits

### Cluster Autoscaler
- **Node Scaling**: Automatic EC2 instance provisioning
- **Cost Optimization**: Prefers spot instances
- **Multi-AZ**: Distributes nodes across availability zones

### Vertical Pod Autoscaler (VPA)
- **Resource Optimization**: Automatic resource recommendation
- **Right-sizing**: Prevents over/under-provisioning

## 🚨 Troubleshooting

### Common Issues

1. **Pods Stuck in Pending**
   ```bash
   kubectl describe pod <pod-name> -n pyairtable-production
   # Check for resource constraints or node capacity
   ```

2. **Services Not Responding**
   ```bash
   kubectl logs -f deployment/<service-name> -n pyairtable-production
   # Check application logs for errors
   ```

3. **Database Connection Issues**
   ```bash
   kubectl get secret pyairtable-database -n pyairtable-production -o yaml
   # Verify database credentials and connectivity
   ```

4. **Load Balancer Not Working**
   ```bash
   kubectl describe ingress -n pyairtable-production
   # Check ALB controller logs and certificate configuration
   ```

### Health Check Commands

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -n pyairtable-production

# Check service health
./scripts/validate-production-deployment.sh

# Monitor resources
kubectl top nodes
kubectl top pods -n pyairtable-production

# View logs
kubectl logs -f deployment/api-gateway -n pyairtable-production
```

## 📝 Maintenance Tasks

### Regular Maintenance

1. **Security Updates**
   - Update container images regularly
   - Apply Kubernetes patches
   - Rotate secrets periodically

2. **Backup Verification**
   - Test database restore procedures
   - Verify backup completeness
   - Document recovery procedures

3. **Performance Monitoring**
   - Review resource utilization
   - Optimize scaling parameters
   - Monitor costs and optimize

4. **Certificate Management**
   - Monitor certificate expiration
   - Renew certificates before expiry
   - Update certificate ARNs if needed

### Disaster Recovery

1. **Database Recovery**
   - RDS automated backups (30 days retention)
   - Point-in-time recovery available
   - Cross-region backup replication

2. **Application Recovery**
   - Container images in ECR
   - Infrastructure as Code in Git
   - Automated deployment scripts

## 📞 Support and Contacts

### Important URLs
- **Production Frontend**: https://pyairtable.com
- **Production API**: https://api.pyairtable.com
- **Grafana Dashboard**: http://[grafana-lb]:3000
- **AWS Console**: https://console.aws.amazon.com

### Monitoring Alerts
- **Email**: Configure in `cost_alert_emails`
- **Slack**: Configure webhook in monitoring config
- **PagerDuty**: Configure integration key

### Emergency Procedures
1. **Scale down non-critical services**
2. **Check AWS service health dashboard**
3. **Review CloudWatch alarms**
4. **Escalate to AWS support if needed**

---

**Note**: This deployment guide assumes familiarity with AWS, Kubernetes, and the PyAirtable application architecture. For additional support, please refer to the troubleshooting section or contact the development team.