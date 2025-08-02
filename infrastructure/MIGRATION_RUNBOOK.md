# PyAirtable Cloud Migration Runbook
*Comprehensive guide for phased migration with cost optimization and disaster recovery*

## Executive Summary

This runbook provides step-by-step instructions for migrating PyAirtable from the current monolithic architecture to a cost-optimized, scalable microservices platform on AWS. The migration follows a 4-phase approach with built-in rollback procedures and continuous cost monitoring.

### Key Metrics
- **Target Cost Reduction**: 40-60% for non-production environments
- **Migration Timeline**: 4-6 weeks
- **Downtime Target**: <5 minutes per phase
- **Cost Targets**: Dev ($98/month), Staging ($150/month), Production ($395/month)

## Pre-Migration Checklist

### Infrastructure Requirements
- [ ] AWS Account with appropriate permissions
- [ ] GitHub repository access with Actions enabled
- [ ] Domain and SSL certificates (production)
- [ ] Backup of current production data
- [ ] Cost monitoring alerts configured

### Access Requirements
- [ ] AWS CLI configured with appropriate role
- [ ] kubectl installed and configured
- [ ] Terraform >= 1.5.0 installed
- [ ] Docker and docker-compose installed
- [ ] GitHub CLI (gh) installed

### Security Requirements
- [ ] AWS Secrets Manager configured
- [ ] External Secrets Operator deployed
- [ ] RBAC policies defined
- [ ] Network security groups configured
- [ ] Encryption at rest and in transit enabled

## Phase 1: Registry Consolidation & Cost Foundation (Week 1)

### Objectives
- Consolidate container registry structure
- Implement cost monitoring and alerting
- Establish baseline metrics

### Steps

#### 1.1 Registry Migration
```bash
# Set up new registry structure
export GITHUB_ORG="pyairtable-org"
export REGISTRY="ghcr.io"

# Migrate legacy images
docker tag ghcr.io/reg-kris/pyairtable-api-gateway:latest \
  $REGISTRY/$GITHUB_ORG/legacy/api-gateway:v1.0.0

docker push $REGISTRY/$GITHUB_ORG/legacy/api-gateway:v1.0.0

# Repeat for all legacy services
for service in platform-services automation-services llm-orchestrator mcp-server airtable-gateway; do
  docker tag ghcr.io/reg-kris/$service:latest \
    $REGISTRY/$GITHUB_ORG/legacy/$service:v1.0.0
  docker push $REGISTRY/$GITHUB_ORG/legacy/$service:v1.0.0
done
```

#### 1.2 Deploy Cost Monitoring Infrastructure
```bash
cd infrastructure/

# Initialize Terraform for cost monitoring
terraform init
terraform workspace new dev
terraform plan -var="migration_phase=1" -var="environment=dev"
terraform apply -auto-approve
```

#### 1.3 Validate Cost Monitoring
```bash
# Check budget creation
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text)

# Verify SNS topic
aws sns list-topics | grep cost-alerts

# Test CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name pyairtable-dev-cost-optimization
```

### Rollback Procedure
```bash
# Remove cost monitoring infrastructure
terraform destroy -var="migration_phase=1" -var="environment=dev" -auto-approve

# Revert to original registry structure
# (Images remain in original locations)
```

### Success Criteria
- [ ] Cost monitoring dashboard accessible
- [ ] Budget alerts configured and tested
- [ ] Registry lifecycle policies active
- [ ] Baseline cost metrics established

### Cost Impact
- **Setup Cost**: ~$5/month (CloudWatch, SNS)
- **Expected Savings**: $0 (baseline establishment)

---

## Phase 2: Multi-Environment Strategy (Week 2)

### Objectives
- Deploy environment-specific infrastructure
- Implement auto-scaling and spot instances
- Establish blue-green deployment capability

### Steps

#### 2.1 Deploy Development Environment
```bash
# Deploy with spot instances for cost optimization
terraform workspace select dev
terraform plan -var="migration_phase=2" -var="environment=dev"
terraform apply -auto-approve

# Verify EKS cluster
export CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME

kubectl get nodes
kubectl get pods --all-namespaces
```

#### 2.2 Deploy Go Microservices
```bash
cd go-services/

# Build and push microservices
for service in auth-service user-service tenant-service workspace-service; do
  cd $service
  docker build -t $REGISTRY/$GITHUB_ORG/microservices/$service:v2.0.0 .
  docker push $REGISTRY/$GITHUB_ORG/microservices/$service:v2.0.0
  cd ..
done

# Deploy to Kubernetes
kubectl apply -f ../k8s/go-services-deployment.yaml
```

#### 2.3 Configure Auto-Scaling
```bash
# Apply horizontal pod autoscaler
kubectl apply -f - <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: auth-service-hpa
  namespace: pyairtable
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: auth-service
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF
```

### Cost Optimization Validation
```bash
# Check spot instance usage
kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.beta\\.kubernetes\\.io/instance-type,LIFECYCLE:.metadata.labels.eks\\.amazonaws\\.com/capacityType

# Verify auto-scaling metrics
kubectl get hpa -n pyairtable
```

### Rollback Procedure
```bash
# Scale down services
kubectl scale deployment --all --replicas=0 -n pyairtable

# Destroy infrastructure
terraform destroy -var="migration_phase=2" -var="environment=dev" -auto-approve
```

### Success Criteria
- [ ] EKS cluster operational with spot instances
- [ ] Go microservices deployed and healthy
- [ ] Auto-scaling configured and tested
- [ ] Cost reduction visible in monitoring

### Cost Impact
- **Infrastructure Cost**: ~$85/month (with 80% spot instances)
- **Expected Savings**: 60% compared to on-demand pricing

---

## Phase 3: Secrets & Configuration Management (Week 3)

### Objectives
- Migrate from environment variables to AWS Secrets Manager
- Implement External Secrets Operator
- Enhance security posture

### Steps

#### 3.1 Deploy External Secrets Operator
```bash
# Add External Secrets Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install External Secrets Operator
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

#### 3.2 Migrate Secrets to AWS Secrets Manager
```bash
# Create secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name pyairtable/dev/database \
  --description "Database credentials for PyAirtable dev environment" \
  --secret-string '{
    "username": "admin",
    "password": "'$(openssl rand -base64 24)'",
    "host": "postgres.pyairtable.svc.cluster.local",
    "port": "5432",
    "database": "pyairtable"
  }'

aws secretsmanager create-secret \
  --name pyairtable/dev/redis \
  --description "Redis credentials for PyAirtable dev environment" \
  --secret-string '{
    "password": "'$(openssl rand -base64 24)'",
    "host": "redis.pyairtable.svc.cluster.local",
    "port": "6379"
  }'

aws secretsmanager create-secret \
  --name pyairtable/dev/api-keys \
  --description "API keys for PyAirtable dev environment" \
  --secret-string '{
    "jwt_secret": "'$(openssl rand -base64 32)'",
    "api_key": "'$(openssl rand -base64 24)'",
    "airtable_token": "'${AIRTABLE_TOKEN}'",
    "gemini_api_key": "'${GEMINI_API_KEY}'"
  }'
```

#### 3.3 Configure External Secrets
```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager
  namespace: pyairtable
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-secret
  namespace: pyairtable
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: pyairtable/dev/database
      property: username
  - secretKey: password
    remoteRef:
      key: pyairtable/dev/database
      property: password
EOF
```

#### 3.4 Update Service Deployments
```bash
# Update deployments to use secrets from External Secrets
kubectl patch deployment auth-service -n pyairtable -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "auth-service",
          "env": [
            {
              "name": "DB_PASSWORD",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "database-credentials",
                  "key": "password"
                }
              }
            }
          ]
        }]
      }
    }
  }
}'
```

### Security Validation
```bash
# Verify External Secrets Operator
kubectl get pods -n external-secrets-system

# Check secret synchronization
kubectl get externalsecrets -n pyairtable
kubectl get secrets -n pyairtable

# Test secret rotation
aws secretsmanager update-secret \
  --secret-id pyairtable/dev/database \
  --secret-string '{"username":"admin","password":"'$(openssl rand -base64 24)'"}'

# Wait 15 seconds and verify update
sleep 15
kubectl get secret database-credentials -n pyairtable -o jsonpath='{.data.password}' | base64 -d
```

### Rollback Procedure
```bash
# Revert to environment variable configuration
kubectl patch deployment auth-service -n pyairtable -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "auth-service",
          "env": [
            {
              "name": "DB_PASSWORD",
              "value": "fallback-password"
            }
          ]
        }]
      }
    }
  }
}'

# Remove External Secrets Operator
helm uninstall external-secrets -n external-secrets-system
```

### Success Criteria
- [ ] External Secrets Operator deployed and functional
- [ ] All secrets migrated to AWS Secrets Manager
- [ ] Services using secrets without hardcoded values
- [ ] Secret rotation tested and working

### Cost Impact
- **Additional Cost**: ~$3/month (Secrets Manager)
- **Security Enhancement**: Significant improvement in secret management

---

## Phase 4: Production Deployment & Blue-Green Strategy (Week 4)

### Objectives
- Deploy production-ready infrastructure
- Implement blue-green deployment
- Complete migration with zero-downtime cutover

### Steps

#### 4.1 Deploy Production Infrastructure
```bash
# Switch to production workspace
terraform workspace new prod
terraform plan -var="migration_phase=4" -var="environment=prod" -var="blue_green_enabled=true"
terraform apply -auto-approve

# Verify production cluster
export PROD_CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region us-east-1 --name $PROD_CLUSTER_NAME --alias prod-cluster
```

#### 4.2 Setup Blue-Green Deployment
```bash
# Deploy blue environment (current production)
kubectl apply -f k8s/blue-environment/ -n pyairtable

# Verify blue environment health
kubectl get pods -n pyairtable -l version=blue
kubectl get svc -n pyairtable -l version=blue

# Deploy green environment (new microservices)
kubectl apply -f k8s/green-environment/ -n pyairtable

# Verify green environment health
kubectl get pods -n pyairtable -l version=green
kubectl get svc -n pyairtable -l version=green
```

#### 4.3 Traffic Switching Strategy
```bash
# Gradual traffic shift: 90% blue, 10% green
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway
  namespace: pyairtable
spec:
  hosts:
  - api-gateway.pyairtable.svc.cluster.local
  http:
  - match:
    - headers:
        canary:
          exact: "true"
    route:
    - destination:
        host: api-gateway
        subset: green
  - route:
    - destination:
        host: api-gateway
        subset: blue
      weight: 90
    - destination:
        host: api-gateway
        subset: green
      weight: 10
EOF

# Monitor metrics for 30 minutes
kubectl get pods -n pyairtable -w

# If healthy, switch to 50/50
kubectl patch virtualservice api-gateway -n pyairtable -p '{
  "spec": {
    "http": [{
      "route": [{
        "destination": {"host": "api-gateway", "subset": "blue"},
        "weight": 50
      }, {
        "destination": {"host": "api-gateway", "subset": "green"},
        "weight": 50
      }]
    }]
  }
}'

# Final cutover: 100% green
kubectl patch virtualservice api-gateway -n pyairtable -p '{
  "spec": {
    "http": [{
      "route": [{
        "destination": {"host": "api-gateway", "subset": "green"},
        "weight": 100
      }]
    }]
  }
}'
```

#### 4.4 Production Validation
```bash
# Health check all services
kubectl get pods -n pyairtable
kubectl top pods -n pyairtable

# Test critical endpoints
API_GATEWAY_URL=$(kubectl get service api-gateway -n pyairtable -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl -f $API_GATEWAY_URL/health
curl -f $API_GATEWAY_URL/api/v1/auth/health
curl -f $API_GATEWAY_URL/api/v1/users/health

# Load testing
hey -n 1000 -c 10 $API_GATEWAY_URL/health
```

### Disaster Recovery Testing
```bash
# Simulate node failure
kubectl drain $(kubectl get nodes -o name | head -1) --ignore-daemonsets --delete-emptydir-data

# Verify automatic recovery
kubectl get pods -n pyairtable -w

# Uncordon node
kubectl uncordon $(kubectl get nodes -o name | head -1 | cut -d/ -f2)

# Test backup restoration
kubectl exec -it postgres-0 -n pyairtable -- pg_dump -U admin pyairtable > backup.sql
kubectl exec -i postgres-0 -n pyairtable -- psql -U admin pyairtable < backup.sql
```

### Rollback Procedure (Emergency)
```bash
# Immediate rollback to blue environment
kubectl patch virtualservice api-gateway -n pyairtable -p '{
  "spec": {
    "http": [{
      "route": [{
        "destination": {"host": "api-gateway", "subset": "blue"},
        "weight": 100
      }]
    }]
  }
}'

# Scale down green environment
kubectl scale deployment --all --replicas=0 -n pyairtable -l version=green

# If database issues, restore from backup
kubectl exec -i postgres-0 -n pyairtable -- psql -U admin pyairtable < emergency-backup.sql
```

### Success Criteria
- [ ] Production infrastructure deployed successfully
- [ ] Blue-green deployment functional
- [ ] All services healthy and responding
- [ ] Load testing passed
- [ ] Disaster recovery procedures tested
- [ ] Cost targets met

### Cost Impact
- **Production Infrastructure**: ~$395/month
- **Cost Optimization**: 30% savings through reserved instances and right-sizing

---

## Post-Migration Monitoring

### Daily Operations
```bash
# Check cluster health
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# Monitor costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "$(date +%Y-%m-01)" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Check autoscaling
kubectl get hpa -n pyairtable
```

### Weekly Cost Review
```bash
# Generate cost report
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "last monday" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity WEEKLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE > weekly-cost-report.json

# Check budget status
aws budgets describe-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name pyairtable-prod-monthly-budget
```

### Monthly Optimization Review
1. **Resource Utilization Analysis**
   - Review CPU/Memory usage patterns
   - Identify over-provisioned services
   - Adjust resource requests/limits

2. **Cost Optimization Opportunities**
   - Evaluate Reserved Instance purchases
   - Review spot instance utilization
   - Optimize storage costs

3. **Security Review**
   - Rotate secrets
   - Review IAM permissions
   - Update security policies

## Troubleshooting Guide

### Common Issues and Solutions

#### High Costs
```bash
# Identify expensive resources
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "7 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE | jq '.ResultsByTime[].Groups[] | select(.Metrics.BlendedCost.Amount > "10")'

# Scale down non-essential services
kubectl scale deployment analytics-service --replicas=0 -n pyairtable
```

#### Service Health Issues
```bash
# Check pod logs
kubectl logs -n pyairtable deployment/auth-service --tail=100

# Restart deployment
kubectl rollout restart deployment/auth-service -n pyairtable

# Check resource limits
kubectl top pods -n pyairtable
```

#### Database Connection Issues
```bash
# Check PostgreSQL health
kubectl exec -it postgres-0 -n pyairtable -- pg_isready -U admin

# Test connection from application
kubectl exec -it deployment/auth-service -n pyairtable -- nc -zv postgres 5432

# Check secrets
kubectl get secret database-credentials -n pyairtable -o yaml
```

## Success Metrics

### Technical Metrics
- **Uptime**: >99.9% availability
- **Response Time**: <200ms p95
- **Error Rate**: <0.1%
- **Deployment Frequency**: Multiple times per day
- **Recovery Time**: <5 minutes

### Cost Metrics
- **Monthly Costs**: Within budget targets
- **Cost per Transaction**: 40% reduction
- **Resource Utilization**: >70% CPU/Memory
- **Spot Instance Usage**: >50% for non-production

### Security Metrics
- **Secret Rotation**: Monthly
- **Security Scan Results**: Zero critical vulnerabilities
- **Access Reviews**: Quarterly
- **Backup Success Rate**: 100%

## Conclusion

This migration strategy provides a comprehensive, cost-optimized approach to modernizing the PyAirtable platform. The phased approach minimizes risk while maximizing cost savings and operational efficiency.

### Key Achievements
1. **60% cost reduction** in development environment
2. **30% cost reduction** in production environment
3. **Zero-downtime** migration capability
4. **Enhanced security** posture with automated secret management
5. **Improved scalability** with auto-scaling and spot instances

### Next Steps
1. Monitor cost trends and optimize further
2. Implement advanced observability (Prometheus/Grafana)
3. Explore serverless opportunities for batch workloads
4. Implement chaos engineering for resilience testing