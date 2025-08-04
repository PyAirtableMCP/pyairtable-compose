# PyAirtable Autoscaling Operations Runbook

## Table of Contents
1. [Overview](#overview)
2. [Autoscaling Architecture](#autoscaling-architecture)
3. [Operational Procedures](#operational-procedures)
4. [Troubleshooting Guide](#troubleshooting-guide)
5. [Cost Management](#cost-management)
6. [Monitoring and Alerting](#monitoring-and-alerting)
7. [Emergency Procedures](#emergency-procedures)
8. [Maintenance and Updates](#maintenance-and-updates)

## Overview

This runbook provides comprehensive operational procedures for managing PyAirtable's multi-layered autoscaling infrastructure. The system includes:

- **Application Layer**: HPA, VPA, and KEDA-based scaling
- **Infrastructure Layer**: Database, Redis, and Kafka autoscaling
- **Cost Optimization**: Spot instances, scheduled scaling, and budget controls
- **Predictive Scaling**: ML-based forecasting and proactive scaling

### Key Components
- Kubernetes HPA (Horizontal Pod Autoscaler)
- KEDA (Kubernetes Event-Driven Autoscaling)
- VPA (Vertical Pod Autoscaler)
- AWS Aurora Serverless v2
- ElastiCache Auto Scaling
- MSK (Managed Streaming for Kafka)
- Custom predictive scaling engine
- Cost optimization controller

## Autoscaling Architecture

### Service Scaling Matrix

| Service | Scaling Type | Min Replicas | Max Replicas | Triggers | Cost Priority |
|---------|--------------|--------------|--------------|-----------|---------------|
| API Gateway | HPA + KEDA | 2 | 25 | CPU, Memory, RPS, P95 latency | Critical |
| Platform Services | HPA | 2 | 15 | CPU, Memory, DB connections | Critical |
| SAGA Orchestrator | KEDA | 1 | 15 | Kafka lag, Redis queue | High |
| File Service | KEDA | 0 | 12 | Redis queue, SQS messages | Medium |
| LLM Orchestrator | KEDA | 1 | 8 | Redis queue, GPU utilization | High |
| Analytics Service | KEDA | 1 | 10 | Redis queue, Kafka lag | Low |
| Batch Processing | KEDA | 0 | 20 | Redis queue, scheduled jobs | Low |

### Infrastructure Scaling

| Component | Type | Min Capacity | Max Capacity | Triggers |
|-----------|------|-------------|--------------|-----------|
| Aurora Serverless | ACU | 2 | 16 | CPU, connections, IO |
| Redis Cluster | Nodes | 3 | 9 | CPU, memory, connections |
| MSK Cluster | Brokers | 3 | 6 | Disk usage, throughput |
| OpenSearch | Instances | 1 | 6 | CPU, disk, search load |

## Operational Procedures

### Daily Operations

#### Morning Checklist (8:00 AM UTC)
```bash
# 1. Check cluster health
kubectl get nodes -o wide
kubectl get pods --all-namespaces | grep -E "(Pending|Error|CrashLoopBackOff)"

# 2. Verify autoscaling status
kubectl get hpa --all-namespaces
kubectl get scaledobjects --all-namespaces -n pyairtable
kubectl get vpa --all-namespaces

# 3. Check cost metrics
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  curl -s localhost:8080/metrics | grep cost_optimization

# 4. Review overnight scaling events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | \
  grep -E "(Scaled|SuccessfulCreate|SuccessfulDelete)" | tail -20
```

#### Business Hours Scaling (8:00 AM - 6:00 PM UTC)
- Services automatically scale up based on demand
- Monitor for any scaling limits reached
- Review cost dashboard for budget adherence

#### Evening Scale-Down (6:00 PM UTC)
```bash
# Verify scheduled scaling executed
kubectl get cronjobs -n pyairtable | grep scale
kubectl get jobs -n pyairtable | grep scale | tail -5
```

### Weekly Operations

#### Monday Morning (7:00 AM UTC)
```bash
# 1. Review weekend scaling performance
kubectl logs -n cost-optimization deployment/cost-optimization-controller --since=72h | \
  grep -E "(weekend|scaling)"

# 2. Check predictive model accuracy
kubectl exec -n predictive-scaling deployment/predictive-scaling-engine -- \
  curl -s localhost:8080/model-accuracy

# 3. Update scaling policies if needed
kubectl get configmap cost-optimization-config -n cost-optimization -o yaml

# 4. Review spot instance usage
kubectl get nodes -l node.kubernetes.io/instance-lifecycle=spot -o wide
```

#### Weekly Cost Review (Friday 5:00 PM UTC)
```bash
# Generate weekly cost report
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  python3 -c "
import boto3
import json
from datetime import datetime, timedelta

ce = boto3.client('ce')
end_date = datetime.now().strftime('%Y-%m-%d')
start_date = (datetime.now() - timedelta(days=7)).strftime('%Y-%m-%d')

response = ce.get_cost_and_usage(
    TimePeriod={'Start': start_date, 'End': end_date},
    Granularity='DAILY',
    Metrics=['BlendedCost'],
    GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
)

total_cost = 0
for day in response['ResultsByTime']:
    for group in day['Groups']:
        total_cost += float(group['Metrics']['BlendedCost']['Amount'])

print(f'Weekly infrastructure cost: ${total_cost:.2f}')
"
```

### Scaling Policy Management

#### Update HPA Configuration
```bash
# Example: Update API Gateway HPA
kubectl patch hpa api-gateway-hpa -n pyairtable --type='merge' -p='{
  "spec": {
    "minReplicas": 3,
    "maxReplicas": 30,
    "behavior": {
      "scaleUp": {
        "stabilizationWindowSeconds": 60,
        "policies": [
          {"type": "Percent", "value": 100, "periodSeconds": 30}
        ]
      }
    }
  }
}'
```

#### Update KEDA ScaledObject
```bash
# Example: Update File Service scaling
kubectl patch scaledobject file-service-processing-scaler -n pyairtable --type='merge' -p='{
  "spec": {
    "minReplicaCount": 0,
    "maxReplicaCount": 15,
    "triggers": [
      {
        "type": "redis",
        "metadata": {
          "address": "redis.pyairtable.svc.cluster.local:6379",
          "listName": "file_processing_queue",
          "listLength": "3"
        }
      }
    ]
  }
}'
```

#### Update Cost Optimization Settings
```bash
# Update cost optimization configuration
kubectl patch configmap cost-optimization-config -n cost-optimization --type='merge' -p='{
  "data": {
    "config.yaml": "cost_optimization:\n  max_hourly_cost: 60.0\n  target_cost_savings: 0.35"
  }
}'

# Restart cost controller to pick up changes
kubectl rollout restart deployment/cost-optimization-controller -n cost-optimization
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. HPA Not Scaling

**Symptoms:**
- Pods under high load but HPA not scaling up
- HPA shows "unknown" for metrics

**Diagnosis:**
```bash
# Check HPA status
kubectl describe hpa <hpa-name> -n pyairtable

# Check metrics server
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq .

# Check custom metrics API
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .
```

**Solutions:**
```bash
# Restart metrics server
kubectl rollout restart deployment/metrics-server -n kube-system

# Check prometheus adapter
kubectl logs -n pyairtable-monitoring deployment/prometheus-adapter

# Verify service monitors
kubectl get servicemonitor -n pyairtable-monitoring
```

#### 2. KEDA ScaledObject Not Working

**Symptoms:**
- ScaledObject exists but no scaling occurs
- Error events in ScaledObject

**Diagnosis:**
```bash
# Check ScaledObject status
kubectl describe scaledobject <name> -n pyairtable

# Check KEDA operator logs
kubectl logs -n keda deployment/keda-operator

# Check trigger authentication
kubectl describe triggerauthentication -n pyairtable
```

**Solutions:**
```bash
# Restart KEDA operator
kubectl rollout restart deployment/keda-operator -n keda

# Recreate ScaledObject
kubectl delete scaledobject <name> -n pyairtable
kubectl apply -f /path/to/scaledobject.yaml

# Check external scaler connectivity (Redis, Kafka, etc.)
kubectl exec -n pyairtable deployment/<service> -- nc -zv redis.pyairtable.svc.cluster.local 6379
```

#### 3. Cost Optimization Controller Issues

**Symptoms:**
- Scheduled scaling not executing
- Cost alerts not firing
- Spot instances not being used

**Diagnosis:**
```bash
# Check controller logs
kubectl logs -n cost-optimization deployment/cost-optimization-controller

# Check CronJob status
kubectl get cronjobs -n pyairtable
kubectl describe cronjob <cronjob-name> -n pyairtable

# Check spot instance nodes
kubectl get nodes -l node.kubernetes.io/instance-lifecycle=spot
```

**Solutions:**
```bash
# Restart cost optimization controller
kubectl rollout restart deployment/cost-optimization-controller -n cost-optimization

# Manually trigger scheduled scaling
kubectl create job --from=cronjob/business-hours-scale-up manual-scale-up -n pyairtable

# Check IAM permissions for spot instances
aws iam get-role --role-name pyairtable-cost-optimizer-role
```

#### 4. Predictive Scaling Model Issues

**Symptoms:**
- Predictions not updating
- Low model accuracy
- Scaling decisions not being made

**Diagnosis:**
```bash
# Check predictive scaling engine logs
kubectl logs -n predictive-scaling deployment/predictive-scaling-engine

# Check model training job
kubectl get jobs -n predictive-scaling | grep model-trainer
kubectl logs job/model-trainer-<timestamp> -n predictive-scaling

# Check S3 model storage
aws s3 ls s3://pyairtable-ml-models/models/ --recursive
```

**Solutions:**
```bash
# Restart predictive scaling engine
kubectl rollout restart deployment/predictive-scaling-engine -n predictive-scaling

# Manually trigger model training
kubectl create job --from=cronjob/model-trainer manual-training -n predictive-scaling

# Check database connectivity for historical data
kubectl exec -n predictive-scaling deployment/predictive-scaling-engine -- \
  pg_isready -h postgres.pyairtable.svc.cluster.local -p 5432
```

### Infrastructure Scaling Issues

#### Database Scaling Problems
```bash
# Check Aurora Serverless scaling
aws rds describe-db-clusters --db-cluster-identifier pyairtable-prod-serverless

# Check scaling events
aws logs filter-log-events --log-group-name /aws/rds/cluster/pyairtable-prod-serverless/postgresql \
  --filter-pattern "scaling"

# Monitor current capacity
aws rds describe-db-cluster-capacity --db-cluster-identifier pyairtable-prod-serverless
```

#### Redis Scaling Problems
```bash
# Check ElastiCache cluster status
aws elasticache describe-replication-groups --replication-group-id pyairtable-prod-redis

# Check scaling activities
aws application-autoscaling describe-scaling-activities --service-namespace elasticache
```

#### Kafka Scaling Problems
```bash
# Check MSK cluster status
aws kafka describe-cluster --cluster-arn arn:aws:kafka:us-east-1:ACCOUNT:cluster/pyairtable-prod-kafka

# Check storage scaling
aws kafka describe-configuration --arn arn:aws:kafka:us-east-1:ACCOUNT:configuration/pyairtable-kafka-config
```

## Cost Management

### Budget Monitoring

#### Daily Cost Check
```bash
# Get current daily spend
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  python3 -c "
import boto3
from datetime import datetime, timedelta

ce = boto3.client('ce')
today = datetime.now().strftime('%Y-%m-%d')
yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

response = ce.get_cost_and_usage(
    TimePeriod={'Start': yesterday, 'End': today},
    Granularity='DAILY',
    Metrics=['BlendedCost']
)

cost = float(response['ResultsByTime'][0]['Total']['BlendedCost']['Amount'])
print(f'Yesterday cost: ${cost:.2f}')

if cost > 600:  # Daily budget
    print('WARNING: Daily budget exceeded!')
"
```

#### Cost Optimization Actions

**Emergency Cost Reduction (if budget exceeded by 50%):**
```bash
# Scale down non-critical services
kubectl patch hpa analytics-service-hpa -n pyairtable --type='merge' -p='{"spec":{"minReplicas":0,"maxReplicas":2}}'
kubectl patch scaledobject file-service-processing-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":3}}'
kubectl patch scaledobject automation-services-celery-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":5}}'

# Scale down development environments
kubectl scale deployment --replicas=0 -n pyairtable-dev --all

# Notify stakeholders
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  aws sns publish --topic-arn arn:aws:sns:us-east-1:ACCOUNT:pyairtable-cost-alerts \
  --message "Emergency cost reduction measures activated due to budget overrun"
```

**Spot Instance Optimization:**
```bash
# Check spot instance availability
aws ec2 describe-spot-price-history --instance-types t3.medium t3.large m5.large \
  --product-descriptions "Linux/UNIX" --max-items 10

# Force spot instance preference for batch workloads
kubectl patch deployment batch-processing-spot -n pyairtable --type='merge' -p='{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "node.kubernetes.io/instance-lifecycle": "spot"
        }
      }
    }
  }
}'
```

### Right-Sizing Recommendations

#### Weekly Resource Analysis
```bash
# Generate VPA recommendations
kubectl get vpa --all-namespaces -o yaml | grep -A 10 recommendation

# Check resource utilization
kubectl top pods --all-namespaces --sort-by=cpu
kubectl top pods --all-namespaces --sort-by=memory

# Generate right-sizing report
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  python3 /scripts/generate-rightsizing-report.py
```

## Monitoring and Alerting

### Key Metrics to Monitor

#### Application Scaling Metrics
```promql
# HPA scaling velocity
rate(kube_horizontalpodautoscaler_status_current_replicas[5m])

# Services at maximum replicas
kube_horizontalpodautoscaler_status_current_replicas == kube_horizontalpodautoscaler_spec_max_replicas

# KEDA scaling events
increase(keda_scaled_object_replicas[5m])

# Resource utilization vs targets
avg(rate(container_cpu_usage_seconds_total[5m])) / avg(kube_pod_container_resource_requests{resource="cpu"})
```

#### Cost Metrics
```promql
# Hourly cost estimate
pyairtable:total_hourly_cost

# Spot instance savings
pyairtable:spot_instance_savings_hourly

# Resource waste percentage
pyairtable:cpu_waste_percentage
pyairtable:memory_waste_percentage
```

#### Infrastructure Metrics
```promql
# Database scaling events
aws_rds_serverless_scaling_events_total

# Redis CPU utilization
aws_elasticache_cpu_utilization

# Kafka disk usage
aws_kafka_disk_used_percentage
```

### Alert Response Procedures

#### Critical Alerts

**HPA Max Replicas Reached:**
1. Check service health and error rates
2. Investigate root cause (traffic spike, performance degradation)
3. Consider temporarily increasing max replicas
4. Review scaling thresholds and resource requests

```bash
# Quick response
kubectl patch hpa <hpa-name> -n pyairtable --type='merge' -p='{"spec":{"maxReplicas":40}}'

# Investigate
kubectl logs -n pyairtable deployment/<service> --tail=100
kubectl get events -n pyairtable --sort-by=.lastTimestamp | tail -20
```

**Cost Budget Exceeded:**
1. Immediately review cost dashboard
2. Identify cost spike source
3. Apply emergency cost reduction if needed
4. Notify finance and engineering teams

```bash
# Check recent scaling events
kubectl get events --all-namespaces --sort-by=.lastTimestamp | grep -E "(Scaled|Created)" | tail -50

# Review current resource usage
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=cpu | head -20
```

**Predictive Model Accuracy Low:**
1. Check data collection pipeline
2. Review model training logs
3. Validate external factors and seasonality
4. Consider manual scaling while investigating

```bash
# Check model health
kubectl exec -n predictive-scaling deployment/predictive-scaling-engine -- \
  curl -s localhost:8080/model-health

# Review training data
kubectl logs -n predictive-scaling deployment/historical-data-collector
```

## Emergency Procedures

### Complete Autoscaling Disable

**When to use:** Critical application issues caused by scaling

```bash
# Disable all HPA
kubectl get hpa --all-namespaces -o name | xargs kubectl patch --type='merge' -p='{"spec":{"minReplicas":1,"maxReplicas":1}}'

# Pause KEDA scaling
kubectl patch scaledobject --all -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":1,"maxReplicaCount":1}}'

# Disable VPA
kubectl patch vpa --all --type='merge' -p='{"spec":{"updatePolicy":{"updateMode":"Off"}}}'

# Notify teams
echo "Autoscaling disabled due to emergency at $(date)" | \
  kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  aws sns publish --topic-arn arn:aws:sns:us-east-1:ACCOUNT:pyairtable-alerts --message file:///dev/stdin
```

### Scale All Services to Minimum

**When to use:** Cost emergency or maintenance window

```bash
#!/bin/bash
# emergency-scale-down.sh

# Set all services to minimum replicas
kubectl patch hpa api-gateway-hpa -n pyairtable --type='merge' -p='{"spec":{"minReplicas":1,"maxReplicas":1}}'
kubectl patch hpa platform-services-hpa -n pyairtable --type='merge' -p='{"spec":{"minReplicas":1,"maxReplicas":1}}'

# Scale KEDA objects to zero where possible
kubectl patch scaledobject file-service-processing-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":0}}'
kubectl patch scaledobject analytics-service-batch-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":0}}'
kubectl patch scaledobject automation-services-celery-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":0}}'

# Keep critical services running
kubectl patch scaledobject saga-orchestrator-event-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":1,"maxReplicaCount":1}}'

echo "Emergency scale-down completed at $(date)"
```

### Restore Normal Scaling

```bash
#!/bin/bash
# restore-normal-scaling.sh

# Restore API Gateway
kubectl patch hpa api-gateway-hpa -n pyairtable --type='merge' -p='{"spec":{"minReplicas":2,"maxReplicas":25}}'

# Restore Platform Services
kubectl patch hpa platform-services-hpa -n pyairtable --type='merge' -p='{"spec":{"minReplicas":2,"maxReplicas":15}}'

# Restore KEDA scaling
kubectl patch scaledobject file-service-processing-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":12}}'
kubectl patch scaledobject analytics-service-batch-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":1,"maxReplicaCount":10}}'
kubectl patch scaledobject automation-services-celery-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":0,"maxReplicaCount":20}}'
kubectl patch scaledobject saga-orchestrator-event-scaler -n pyairtable --type='merge' -p='{"spec":{"minReplicaCount":1,"maxReplicaCount":15}}'

# Re-enable VPA
kubectl patch vpa --all --type='merge' -p='{"spec":{"updatePolicy":{"updateMode":"Auto"}}}'

echo "Normal scaling restored at $(date)"
```

## Maintenance and Updates

### Monthly Maintenance Tasks

#### First Week of Month
1. **Review and update scaling policies**
   - Analyze previous month's scaling patterns
   - Adjust min/max replicas based on usage trends
   - Update cost optimization thresholds

2. **Update predictive models**
   - Review model accuracy metrics
   - Retrain models with extended historical data
   - Validate seasonal adjustments

3. **Infrastructure capacity planning**
   - Review database performance and scaling
   - Analyze Kafka partition distribution
   - Plan Redis cluster adjustments

#### Security Updates
```bash
# Update KEDA
helm upgrade keda kedacore/keda -n keda

# Update VPA
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vpa-release.yaml

# Update metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Update Prometheus Operator
helm upgrade prometheus-operator prometheus-community/kube-prometheus-stack -n pyairtable-monitoring
```

### Quarterly Reviews

#### Q1: Architecture Review
- Evaluate new autoscaling technologies
- Review service dependencies and scaling relationships
- Plan infrastructure optimizations

#### Q2: Cost Optimization Deep Dive
- Comprehensive cost analysis
- Right-sizing recommendations implementation
- Spot instance strategy review

#### Q3: Performance Optimization
- Scaling response time analysis
- Resource utilization optimization
- Predictive model enhancement

#### Q4: Disaster Recovery Testing
- Test autoscaling during simulated failures
- Validate emergency procedures
- Update runbooks and documentation

### Configuration Backup and Recovery

#### Backup Current Configuration
```bash
#!/bin/bash
# backup-autoscaling-config.sh

BACKUP_DIR="/tmp/autoscaling-backup-$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup HPA configurations
kubectl get hpa --all-namespaces -o yaml > $BACKUP_DIR/hpa-config.yaml

# Backup KEDA configurations
kubectl get scaledobjects --all-namespaces -o yaml > $BACKUP_DIR/keda-config.yaml

# Backup VPA configurations
kubectl get vpa --all-namespaces -o yaml > $BACKUP_DIR/vpa-config.yaml

# Backup cost optimization config
kubectl get configmap -n cost-optimization -o yaml > $BACKUP_DIR/cost-config.yaml

# Backup predictive scaling config
kubectl get configmap -n predictive-scaling -o yaml > $BACKUP_DIR/predictive-config.yaml

# Upload to S3
aws s3 cp $BACKUP_DIR s3://pyairtable-config-backups/autoscaling/ --recursive

echo "Autoscaling configuration backed up to S3"
```

#### Restore Configuration
```bash
#!/bin/bash
# restore-autoscaling-config.sh

RESTORE_DATE=$1
if [ -z "$RESTORE_DATE" ]; then
  echo "Usage: $0 YYYYMMDD"
  exit 1
fi

RESTORE_DIR="/tmp/autoscaling-restore-$RESTORE_DATE"
mkdir -p $RESTORE_DIR

# Download from S3
aws s3 cp s3://pyairtable-config-backups/autoscaling/ $RESTORE_DIR --recursive

# Restore configurations
kubectl apply -f $RESTORE_DIR/hpa-config.yaml
kubectl apply -f $RESTORE_DIR/keda-config.yaml
kubectl apply -f $RESTORE_DIR/vpa-config.yaml
kubectl apply -f $RESTORE_DIR/cost-config.yaml
kubectl apply -f $RESTORE_DIR/predictive-config.yaml

echo "Autoscaling configuration restored from $RESTORE_DATE"
```

## Performance Tuning

### Scaling Response Time Optimization

#### HPA Tuning
```yaml
# Fast scaling for API services
behavior:
  scaleUp:
    stabilizationWindowSeconds: 30  # React quickly
    policies:
    - type: Percent
      value: 100
      periodSeconds: 30
  scaleDown:
    stabilizationWindowSeconds: 300  # Slow scale down
    policies:
    - type: Percent
      value: 25
      periodSeconds: 60
```

#### KEDA Tuning
```yaml
# Optimize polling for different workload types
spec:
  pollingInterval: 10  # Fast polling for interactive services
  cooldownPeriod: 60   # Short cooldown for responsive scaling
```

### Resource Efficiency Optimization

#### CPU and Memory Right-Sizing
```bash
# Weekly right-sizing analysis
kubectl exec -n cost-optimization deployment/cost-optimization-controller -- \
  python3 -c "
import subprocess
import json

# Get VPA recommendations
vpa_output = subprocess.check_output(['kubectl', 'get', 'vpa', '--all-namespaces', '-o', 'json'])
vpa_data = json.loads(vpa_output)

for item in vpa_data['items']:
    name = item['metadata']['name']
    if 'status' in item and 'recommendation' in item['status']:
        recommendations = item['status']['recommendation']['containerRecommendations']
        for rec in recommendations:
            container = rec['containerName']
            target_cpu = rec['target']['cpu']
            target_memory = rec['target']['memory']
            print(f'{name}/{container}: CPU={target_cpu}, Memory={target_memory}')
"
```

This runbook provides comprehensive operational procedures for managing PyAirtable's autoscaling infrastructure. Regular review and updates of these procedures ensure optimal performance, cost efficiency, and reliability of the scaling systems.