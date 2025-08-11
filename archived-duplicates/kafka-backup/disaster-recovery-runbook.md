# Kafka Disaster Recovery Runbook for PyAirtable

This runbook provides step-by-step procedures for recovering from various Kafka disaster scenarios in the PyAirtable infrastructure.

## Overview

The PyAirtable Kafka cluster is designed with high availability and fault tolerance. However, in the event of catastrophic failures, this runbook provides procedures to restore service with minimal data loss.

## Prerequisites

- Access to Kafka backup files (local or S3)
- Administrative access to Kubernetes cluster or Docker infrastructure
- AWS CLI configured (if using S3 backups)
- Kafka client tools available

## Disaster Scenarios

### 1. Single Broker Failure

**Symptoms:**
- One Kafka broker is down
- Under-replicated partitions alerts
- Some topics may be unavailable

**Recovery Steps:**

```bash
# 1. Check cluster status
kubectl get pods -n kafka
# or for Docker
docker ps | grep kafka

# 2. Check broker logs
kubectl logs kafka-2 -n kafka
# or for Docker
docker logs kafka-2

# 3. Restart the failed broker
kubectl delete pod kafka-2 -n kafka
# or for Docker
docker restart kafka-2

# 4. Wait for broker to rejoin cluster
kafka-topics --bootstrap-server kafka-1:29092 --describe

# 5. Verify partition replication
kafka-topics --bootstrap-server kafka-1:29092 --describe --under-replicated-partitions
```

**Expected Recovery Time:** 5-10 minutes

### 2. Multiple Broker Failure (Majority Lost)

**Symptoms:**
- Multiple Kafka brokers down
- Cluster becomes unavailable
- All topics inaccessible

**Recovery Steps:**

```bash
# 1. Stop all remaining brokers to prevent split-brain
kubectl scale statefulset kafka --replicas=0 -n kafka

# 2. Check data integrity on remaining broker volumes
kubectl exec -it kafka-0 -n kafka -- ls -la /var/lib/kafka/data

# 3. Restart brokers one by one
kubectl scale statefulset kafka --replicas=1 -n kafka
# Wait for first broker to start
kubectl scale statefulset kafka --replicas=2 -n kafka
# Continue scaling up

# 4. Verify cluster health
kafka-broker-api-versions --bootstrap-server kafka-1:29092

# 5. Check for under-replicated partitions
kafka-topics --bootstrap-server kafka-1:29092 --describe --under-replicated-partitions

# 6. Trigger partition re-assignment if needed
kafka-reassign-partitions --bootstrap-server kafka-1:29092 --generate \
    --topics-to-move-json-file topics.json --broker-list "1,2,3"
```

**Expected Recovery Time:** 30-60 minutes

### 3. Complete Cluster Loss

**Symptoms:**
- All Kafka brokers destroyed
- ZooKeeper cluster also down
- Complete data loss scenario

**Recovery Steps:**

#### Phase 1: Infrastructure Recovery

```bash
# 1. Deploy new Kafka cluster
kubectl apply -f k8s/kafka-production-deployment.yaml

# 2. Wait for ZooKeeper to be ready
kubectl wait --for=condition=Ready pod -l app=zookeeper -n kafka --timeout=300s

# 3. Wait for Kafka brokers to start
kubectl wait --for=condition=Ready pod -l app=kafka -n kafka --timeout=600s

# 4. Verify cluster is operational
kafka-topics --bootstrap-server kafka-service:9092 --list
```

#### Phase 2: Data Recovery from Backup

```bash
# 1. List available backups
./kafka-backup/kafka-backup-script.sh list

# 2. Download latest full backup from S3 (if using S3)
aws s3 cp s3://pyairtable-kafka-backups/full-backups/full_backup_YYYYMMDD_HHMMSS.tar.gz ./

# 3. Restore topic metadata and structure
./kafka-backup/kafka-backup-script.sh restore full_backup_YYYYMMDD_HHMMSS.tar.gz metadata

# 4. Restore topic data
./kafka-backup/kafka-backup-script.sh restore full_backup_YYYYMMDD_HHMMSS.tar.gz data

# 5. Verify topic restoration
kafka-topics --bootstrap-server kafka-service:9092 --list | grep pyairtable

# 6. Check consumer groups and reset offsets if needed
kafka-consumer-groups --bootstrap-server kafka-service:9092 --list
```

#### Phase 3: Service Recovery

```bash
# 1. Restart PyAirtable services to reconnect to Kafka
kubectl rollout restart deployment -n pyairtable

# 2. Monitor service logs for Kafka connectivity
kubectl logs -f deployment/auth-service -n pyairtable

# 3. Verify event processing is working
# Check metrics in Grafana dashboard

# 4. Run health checks on all services
curl http://api-gateway/health/kafka
```

**Expected Recovery Time:** 2-4 hours

### 4. ZooKeeper Complete Failure

**Symptoms:**
- ZooKeeper ensemble completely down
- Kafka brokers losing coordination
- Unable to create/delete topics

**Recovery Steps:**

```bash
# 1. Stop all Kafka brokers
kubectl scale statefulset kafka --replicas=0 -n kafka

# 2. Restart ZooKeeper ensemble
kubectl delete pod -l app=zookeeper -n kafka
kubectl wait --for=condition=Ready pod -l app=zookeeper -n kafka --timeout=300s

# 3. Verify ZooKeeper cluster health
kubectl exec zookeeper-0 -n kafka -- zkCli.sh -server localhost:2181 ls /

# 4. Restart Kafka brokers
kubectl scale statefulset kafka --replicas=3 -n kafka

# 5. Verify Kafka cluster registration with ZooKeeper
kafka-topics --bootstrap-server kafka-service:9092 --list
```

**Expected Recovery Time:** 15-30 minutes

### 5. Schema Registry Failure

**Symptoms:**
- Schema Registry unavailable
- Avro serialization/deserialization failures
- Applications unable to process events

**Recovery Steps:**

```bash
# 1. Check Schema Registry status
kubectl get pods -n kafka | grep schema-registry

# 2. Restart Schema Registry
kubectl rollout restart deployment schema-registry -n kafka

# 3. Verify Schema Registry is accessible
curl http://schema-registry-service:8081/subjects

# 4. Re-register schemas if necessary
cd kafka-schemas
./register-schemas.sh

# 5. Test schema compatibility
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    --data '{"schema": "..."}' \
    http://schema-registry-service:8081/compatibility/subjects/pyairtable.auth.events-value/versions/latest
```

**Expected Recovery Time:** 10-20 minutes

## Data Loss Assessment

After any disaster recovery, assess data loss:

### 1. Check Latest Offsets

```bash
# Get latest offset for each topic
for topic in $(kafka-topics --bootstrap-server kafka-service:9092 --list | grep pyairtable); do
    echo "Topic: $topic"
    kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list kafka-service:9092 \
        --topic $topic \
        --time -1
done
```

### 2. Compare with Backup Manifests

```bash
# Extract and check backup manifest
tar -xzf latest_backup.tar.gz backup-manifest.json
cat backup-manifest.json | jq '.topics'
```

### 3. Calculate Data Loss Window

```bash
# Check backup timestamp vs current time
backup_time=$(cat backup-manifest.json | jq -r '.backup_date')
current_time=$(date '+%Y%m%d_%H%M%S')
echo "Backup time: $backup_time"
echo "Recovery time: $current_time"
```

## Post-Recovery Verification

### 1. System Health Checks

```bash
# Check all Kafka brokers are healthy
kubectl get pods -n kafka -l app=kafka

# Verify no under-replicated partitions
kafka-topics --bootstrap-server kafka-service:9092 --describe --under-replicated-partitions

# Check Schema Registry
curl -f http://schema-registry-service:8081/subjects

# Verify Kafka Connect
curl -f http://kafka-connect-service:8083/connectors
```

### 2. Application Integration Tests

```bash
# Test event publishing
curl -X POST http://api-gateway/api/v1/events/test \
    -H "Content-Type: application/json" \
    -d '{"test": "recovery"}'

# Verify event consumption
kubectl logs -f deployment/auth-service -n pyairtable | grep "Event received"

# Check consumer lag
kafka-consumer-groups --bootstrap-server kafka-service:9092 --describe --all-groups
```

### 3. Performance Validation

```bash
# Run performance tests
cd tests/performance
./kafka-performance-test.sh

# Check metrics in Grafana
# Verify throughput has returned to normal levels
```

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

| Scenario | RTO Target | RPO Target | Achieved RTO | Achieved RPO |
|----------|------------|------------|--------------|--------------|
| Single Broker Failure | 10 minutes | 0 (no data loss) | 5-10 minutes | 0 |
| Multiple Broker Failure | 1 hour | 5 minutes | 30-60 minutes | 0-5 minutes |
| Complete Cluster Loss | 4 hours | 1 hour | 2-4 hours | 15 minutes - 1 hour |
| ZooKeeper Failure | 30 minutes | 0 (no data loss) | 15-30 minutes | 0 |
| Schema Registry Failure | 20 minutes | 0 (no data loss) | 10-20 minutes | 0 |

## Prevention and Mitigation

### 1. Regular Backup Verification

```bash
# Weekly backup verification
./kafka-backup/kafka-backup-script.sh verify latest_backup.tar.gz

# Monthly disaster recovery drill
# Follow complete cluster loss procedure in test environment
```

### 2. Monitoring and Alerting

- Monitor under-replicated partitions
- Alert on broker failures
- Track consumer lag
- Monitor disk usage
- Set up automated backup verification

### 3. Infrastructure Hardening

- Use anti-affinity rules for broker placement
- Implement automated backup rotation
- Regular security updates
- Network partition testing
- Chaos engineering exercises

## Escalation Contacts

| Role | Primary Contact | Secondary Contact |
|------|-----------------|-------------------|
| DevOps Engineer | devops-primary@pyairtable.com | devops-secondary@pyairtable.com |
| Platform Engineer | platform@pyairtable.com | platform-oncall@pyairtable.com |
| VP Engineering | vp-eng@pyairtable.com | cto@pyairtable.com |

## Lessons Learned Template

After each incident, document:

1. **Incident Timeline**
   - Initial detection
   - Response actions
   - Resolution time

2. **Root Cause Analysis**
   - Primary cause
   - Contributing factors
   - Detection gaps

3. **Action Items**
   - Immediate fixes
   - Process improvements
   - Monitoring enhancements

4. **Prevention Measures**
   - Infrastructure changes
   - Automation improvements
   - Training needs

---

**Last Updated:** $(date)
**Version:** 1.0
**Next Review:** $(date -d '+3 months')