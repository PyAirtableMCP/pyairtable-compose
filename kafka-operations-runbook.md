# Kafka Operations and Performance Tuning Runbook

This comprehensive runbook provides operational procedures, performance tuning guidelines, and troubleshooting steps for the PyAirtable Kafka infrastructure.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Performance Monitoring](#performance-monitoring)
3. [Performance Tuning](#performance-tuning)
4. [Troubleshooting](#troubleshooting)
5. [Capacity Planning](#capacity-planning)
6. [Security Operations](#security-operations)
7. [Maintenance Procedures](#maintenance-procedures)

## Daily Operations

### Morning Health Check

```bash
#!/bin/bash
# Daily Kafka health check script

echo "=== PyAirtable Kafka Health Check - $(date) ==="

# Check all brokers are up
echo "1. Broker Status:"
kubectl get pods -n kafka -l app=kafka

# Check cluster connectivity
echo "2. Cluster Connectivity:"
kafka-broker-api-versions --bootstrap-server kafka-service:9092 | head -3

# Check under-replicated partitions
echo "3. Under-replicated Partitions:"
kafka-topics --bootstrap-server kafka-service:9092 --describe --under-replicated-partitions

# Check consumer lag
echo "4. Consumer Lag Summary:"
kafka-consumer-groups --bootstrap-server kafka-service:9092 --describe --all-groups | \
    awk 'NR>1 && $5 != "-" {sum+=$5; count++} END {
        if(count>0) print "Average lag:", sum/count; 
        else print "No active consumers"
    }'

# Check topic sizes
echo "5. Topic Size Summary:"
for topic in $(kafka-topics --bootstrap-server kafka-service:9092 --list | grep pyairtable | head -5); do
    size=$(kafka-log-dirs --bootstrap-server kafka-service:9092 --topic-list $topic --describe | \
           jq '.brokers[].logDirs[].partitions[].size' | awk '{sum+=$1} END {print sum}')
    echo "$topic: $(echo $size | numfmt --to=iec-i --suffix=B)"
done

# Check disk usage
echo "6. Disk Usage:"
kubectl exec kafka-0 -n kafka -- df -h | grep kafka

echo "=== Health Check Complete ==="
```

### Key Metrics to Monitor Daily

1. **Broker Health**
   - All brokers online
   - CPU and memory usage < 80%
   - Disk usage < 85%

2. **Cluster Health**
   - No under-replicated partitions
   - All topics accessible
   - Schema Registry responsive

3. **Performance Metrics**
   - Average consumer lag < 10,000 messages
   - Request latency p99 < 100ms
   - Throughput within expected ranges

4. **PyAirtable Specific**
   - Auth events processing normally
   - Airtable sync events flowing
   - No excessive DLQ messages

## Performance Monitoring

### Key Performance Indicators (KPIs)

#### Throughput Metrics
```bash
# Messages per second by topic
kafka-run-class kafka.tools.ConsumerPerformance \
    --bootstrap-server kafka-service:9092 \
    --topic pyairtable.airtable.events \
    --messages 1000 \
    --reporting-interval 1000

# Producer throughput test
kafka-producer-perf-test \
    --topic pyairtable.test \
    --num-records 100000 \
    --record-size 1024 \
    --throughput 1000 \
    --producer-props bootstrap.servers=kafka-service:9092
```

#### Latency Metrics
```bash
# End-to-end latency measurement
kafka-run-class kafka.tools.EndToEndLatency \
    kafka-service:9092 \
    pyairtable.test \
    1000 \
    1 \
    1024
```

#### Resource Utilization
```bash
# Broker resource usage
kubectl top pods -n kafka

# JVM heap usage
kubectl exec kafka-0 -n kafka -- jstat -gc -t $(pgrep java) 5s 3

# Network I/O
kubectl exec kafka-0 -n kafka -- netstat -i
```

### Performance Baselines

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| Producer Latency (p99) | < 50ms | > 100ms | > 500ms |
| Consumer Lag | < 1000 msgs | > 10000 msgs | > 50000 msgs |
| Broker CPU | < 60% | > 80% | > 95% |
| Broker Memory | < 70% | > 85% | > 95% |
| Disk Usage | < 70% | > 85% | > 95% |
| Under-replicated Partitions | 0 | > 0 | > 10 |

## Performance Tuning

### Broker-Level Tuning

#### JVM Heap Sizing
```bash
# For 16GB RAM brokers
KAFKA_HEAP_OPTS="-Xmx8G -Xms8G"

# GC tuning for low latency
KAFKA_JVM_PERFORMANCE_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35"
```

#### Server Properties Optimization
```properties
# Network threads (2x number of CPU cores)
num.network.threads=16

# I/O threads (number of CPU cores)
num.io.threads=8

# Socket buffer sizes
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

# Log configuration for performance
log.flush.interval.messages=10000
log.flush.interval.ms=1000
log.segment.bytes=1073741824

# Compression
compression.type=snappy

# Replication settings
replica.fetch.max.bytes=1048576
replica.socket.receive.buffer.bytes=65536
```

### Producer Tuning

#### High Throughput Configuration
```properties
# Batch size for throughput
batch.size=16384
linger.ms=5
buffer.memory=33554432

# Compression
compression.type=snappy

# Reliability
acks=all
retries=2147483647
enable.idempotence=true
max.in.flight.requests.per.connection=5
```

#### Low Latency Configuration  
```properties
# Immediate send
batch.size=0
linger.ms=0

# Reduced buffering
buffer.memory=16777216

# Single inflight request
max.in.flight.requests.per.connection=1
```

### Consumer Tuning

#### High Throughput Consumer
```properties
# Fetch sizes
fetch.min.bytes=1
fetch.max.bytes=52428800
max.partition.fetch.bytes=1048576

# Polling
max.poll.records=500
max.poll.interval.ms=300000

# Processing
session.timeout.ms=30000
heartbeat.interval.ms=3000
```

#### Real-time Consumer
```properties
# Minimal fetch delay
fetch.min.bytes=1
fetch.max.wait.ms=500

# Smaller batches
max.poll.records=100

# Shorter timeouts
session.timeout.ms=10000
heartbeat.interval.ms=3000
```

### Topic-Level Tuning

#### High Throughput Topics
```bash
kafka-configs --bootstrap-server kafka-service:9092 \
    --alter --entity-type topics --entity-name pyairtable.airtable.events \
    --add-config compression.type=lz4,segment.ms=86400000
```

#### Low Latency Topics
```bash
kafka-configs --bootstrap-server kafka-service:9092 \
    --alter --entity-type topics --entity-name pyairtable.auth.events \
    --add-config compression.type=snappy,segment.ms=3600000,min.insync.replicas=2
```

### Partition Strategy

#### Optimal Partition Count Calculation
```bash
# Formula: max(T/p, T/c)
# T = target throughput (messages/sec)
# p = partition throughput (messages/sec)
# c = consumer throughput (messages/sec)

# Example for 10,000 msg/sec target:
# If partition handles 1,000 msg/sec and consumer handles 500 msg/sec
# Partitions needed = max(10000/1000, 10000/500) = max(10, 20) = 20

# Create topic with optimal partitions
kafka-topics --bootstrap-server kafka-service:9092 \
    --create --topic pyairtable.high-volume.events \
    --partitions 20 --replication-factor 3
```

## Troubleshooting

### Common Issues and Solutions

#### 1. High Consumer Lag

**Symptoms:**
- Consumer lag increasing steadily
- Processing delays in applications

**Diagnosis:**
```bash
# Check consumer group details
kafka-consumer-groups --bootstrap-server kafka-service:9092 \
    --describe --group pyairtable-auth-service

# Check consumer performance
kafka-consumer-perf-test \
    --bootstrap-server kafka-service:9092 \
    --topic pyairtable.auth.events \
    --messages 1000
```

**Solutions:**
1. Scale up consumer instances
2. Optimize consumer processing logic
3. Increase partition count (requires careful planning)
4. Tune consumer fetch settings

#### 2. Under-replicated Partitions

**Symptoms:**
- Under-replicated partitions alerts
- Potential data loss risk

**Diagnosis:**
```bash
# Identify under-replicated partitions
kafka-topics --bootstrap-server kafka-service:9092 \
    --describe --under-replicated-partitions

# Check broker logs
kubectl logs kafka-1 -n kafka | grep -i replica
```

**Solutions:**
```bash
# Generate reassignment plan
kafka-reassign-partitions --bootstrap-server kafka-service:9092 \
    --generate --topics-to-move-json-file topics.json \
    --broker-list "1,2,3"

# Execute reassignment
kafka-reassign-partitions --bootstrap-server kafka-service:9092 \
    --execute --reassignment-json-file reassignment.json

# Verify reassignment
kafka-reassign-partitions --bootstrap-server kafka-service:9092 \
    --verify --reassignment-json-file reassignment.json
```

#### 3. High Request Latency

**Symptoms:**
- Slow producer/consumer operations
- Application timeouts

**Diagnosis:**
```bash
# Check request handler idle ratio
kubectl exec kafka-0 -n kafka -- \
    kafka-run-class kafka.tools.JmxTool \
    --object-name kafka.server:type=KafkaRequestHandlerPool,name=RequestHandlerAvgIdlePercent
```

**Solutions:**
1. Increase network threads
2. Optimize disk I/O
3. Check for GC pressure
4. Review batch sizes

#### 4. Disk Space Issues

**Symptoms:**
- Disk usage alerts
- Broker instability

**Diagnosis:**
```bash
# Check disk usage by topic
kubectl exec kafka-0 -n kafka -- \
    kafka-log-dirs --bootstrap-server localhost:9092 --describe | \
    jq '.brokers[].logDirs[].partitions[] | select(.size > 1000000000)'
```

**Solutions:**
```bash
# Reduce retention for high-volume topics
kafka-configs --bootstrap-server kafka-service:9092 \
    --alter --entity-type topics --entity-name pyairtable.analytics.events \
    --add-config retention.ms=43200000  # 12 hours

# Delete old topics
kafka-topics --bootstrap-server kafka-service:9092 \
    --delete --topic obsolete-topic

# Increase log segment size to reduce segment files
kafka-configs --bootstrap-server kafka-service:9092 \
    --alter --entity-type topics --entity-name pyairtable.files.events \
    --add-config segment.bytes=2147483648  # 2GB
```

### Performance Troubleshooting Checklist

1. **Network Issues**
   - Check network latency between brokers
   - Verify network bandwidth utilization
   - Monitor packet loss

2. **Disk I/O Issues**
   - Monitor disk queue depth
   - Check for I/O wait time
   - Verify disk throughput

3. **Memory Issues**
   - Monitor JVM heap usage
   - Check for GC pressure
   - Verify page cache utilization

4. **Configuration Issues**
   - Review producer/consumer configs
   - Validate topic configurations
   - Check for suboptimal settings

## Capacity Planning

### Growth Projections

#### Data Volume Estimation
```bash
# Current daily message volume
current_daily_volume=$(kafka-run-class kafka.tools.GetOffsetShell \
    --broker-list kafka-service:9092 \
    --topic pyairtable.airtable.events \
    --time -1 | awk -F: '{sum+=$2} END {print sum}')

# Estimate storage requirements
# Average message size: 2KB
# Retention: 7 days
# Replication factor: 3
storage_needed=$(echo "$current_daily_volume * 2048 * 7 * 3" | bc)
echo "Storage needed: $(echo $storage_needed | numfmt --to=iec-i --suffix=B)"
```

#### Scaling Thresholds

| Resource | Current | Warning | Scale Up |
|----------|---------|---------|----------|
| Daily Message Volume | 10M | 8M | 9M |
| Peak Messages/sec | 1K | 800 | 900 |
| Broker CPU | 40% | 60% | 70% |
| Broker Memory | 50% | 70% | 80% |
| Disk Usage | 40% | 70% | 80% |

### Scaling Procedures

#### Horizontal Scaling (Add Brokers)
```bash
# 1. Update StatefulSet replica count
kubectl scale statefulset kafka --replicas=4 -n kafka

# 2. Wait for new broker to join
kubectl wait --for=condition=Ready pod kafka-3 -n kafka

# 3. Rebalance partitions to include new broker
kafka-reassign-partitions --bootstrap-server kafka-service:9092 \
    --generate --topics-to-move-json-file all-topics.json \
    --broker-list "1,2,3,4"
```

#### Vertical Scaling (Increase Resources)
```bash
# 1. Update resource limits in StatefulSet
kubectl patch statefulset kafka -n kafka -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "kafka",
          "resources": {
            "limits": {"memory": "8Gi", "cpu": "4"},
            "requests": {"memory": "6Gi", "cpu": "2"}
          }
        }]
      }
    }
  }
}'

# 2. Rolling restart
kubectl rollout restart statefulset kafka -n kafka
```

## Security Operations

### SSL Certificate Management

#### Certificate Rotation
```bash
# 1. Generate new certificates
cd kafka-security
./generate-ssl-certs.sh

# 2. Update Kubernetes secret
kubectl create secret generic kafka-ssl-secret-new \
    --from-file=kafka-security/ -n kafka

# 3. Update StatefulSet to use new secret
kubectl patch statefulset kafka -n kafka -p '
{
  "spec": {
    "template": {
      "spec": {
        "volumes": [{
          "name": "kafka-secrets",
          "secret": {"secretName": "kafka-ssl-secret-new"}
        }]
      }
    }
  }
}'

# 4. Rolling restart
kubectl rollout restart statefulset kafka -n kafka
```

#### SASL User Management
```bash
# Add new SASL user
kafka-configs --bootstrap-server kafka-service:9092 \
    --alter --add-config 'SCRAM-SHA-256=[password=new-user-password]' \
    --entity-type users --entity-name new-user

# List SASL users
kafka-configs --bootstrap-server kafka-service:9092 \
    --describe --entity-type users
```

### Access Control (ACLs)

#### Service Account ACLs
```bash
# Grant read access to specific topics
kafka-acls --bootstrap-server kafka-service:9092 \
    --add --allow-principal User:auth-service \
    --operation Read --topic pyairtable.auth.events

# Grant write access to DLQ
kafka-acls --bootstrap-server kafka-service:9092 \
    --add --allow-principal User:all-services \
    --operation Write --topic pyairtable.dlq.events

# List current ACLs
kafka-acls --bootstrap-server kafka-service:9092 --list
```

## Maintenance Procedures

### Rolling Updates

#### Kafka Version Upgrade
```bash
# 1. Update image version in StatefulSet
kubectl patch statefulset kafka -n kafka -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "kafka",
          "image": "confluentinc/cp-kafka:7.6.0"
        }]
      }
    }
  }
}'

# 2. Perform rolling update one broker at a time
kubectl delete pod kafka-0 -n kafka
kubectl wait --for=condition=Ready pod kafka-0 -n kafka

# Repeat for each broker
```

#### Configuration Updates
```bash
# 1. Update ConfigMap
kubectl patch configmap kafka-config -n kafka -p '
{
  "data": {
    "server.properties": "# Updated configuration..."
  }
}'

# 2. Rolling restart to pick up changes
kubectl rollout restart statefulset kafka -n kafka
```

### Cleanup Procedures

#### Log Cleanup
```bash
# Clean up old log segments
kubectl exec kafka-0 -n kafka -- \
    kafka-log-dirs --bootstrap-server localhost:9092 --describe | \
    jq '.brokers[].logDirs[].partitions[] | select(.size > 10000000000)' | \
    # Process results for cleanup
```

#### Topic Cleanup
```bash
# List unused topics
kafka-topics --bootstrap-server kafka-service:9092 --list | \
    grep -v pyairtable

# Delete old test topics
kafka-topics --bootstrap-server kafka-service:9092 \
    --delete --topic test-topic-old
```

### Backup Procedures

#### Automated Daily Backup
```bash
# Add to crontab
0 2 * * * /path/to/kafka-backup/kafka-backup-script.sh full-backup

# Weekly full backup with verification
0 2 * * 0 /path/to/kafka-backup/kafka-backup-script.sh full-backup && \
          /path/to/kafka-backup/kafka-backup-script.sh verify $(ls -t /var/kafka-backups/*.tar.gz | head -1)
```

#### Manual Backup Before Maintenance
```bash
# Create backup before major changes
./kafka-backup/kafka-backup-script.sh full-backup
./kafka-backup/kafka-backup-script.sh verify $(ls -t /var/kafka-backups/*.tar.gz | head -1)
```

---

## Emergency Contacts

- **Primary On-Call:** kafka-oncall@pyairtable.com
- **DevOps Team:** devops@pyairtable.com
- **Platform Team:** platform@pyairtable.com
- **Emergency Hotline:** +1-555-KAFKA-911

## References

- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Confluent Platform Best Practices](https://docs.confluent.io/platform/current/kafka/deployment.html)
- [PyAirtable Kafka Architecture](./kafka-architecture.md)
- [Monitoring Dashboard](http://grafana.pyairtable.com/d/kafka)

---

**Last Updated:** $(date)
**Version:** 1.0
**Next Review:** $(date -d '+1 month')