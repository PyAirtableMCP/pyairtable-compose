# PostgreSQL Persistent Storage Guide for Kubernetes

## Overview

This guide provides comprehensive documentation for the PostgreSQL persistent storage solution implemented for the PyAirtable application in Kubernetes. The solution ensures zero data loss during pod restarts and scaling operations while providing robust backup, monitoring, and disaster recovery capabilities.

## Architecture Components

### 1. StatefulSet Configuration
- **Primary**: PostgreSQL StatefulSet with persistent volume claims
- **Replicas**: Optional read-only replicas for load distribution
- **Storage**: Persistent volumes with configurable storage classes
- **Security**: RBAC, service accounts, and security contexts

### 2. Storage Classes

#### Development Environment (`postgres-dev-ssd`)
- **Purpose**: Local development and testing
- **Type**: SSD storage for fast development cycles
- **Reclaim Policy**: Delete (cost-effective for dev)
- **Encryption**: Optional

#### Staging Environment (`postgres-staging-balanced`)
- **Purpose**: Pre-production testing and staging
- **Type**: Balanced performance and cost (pd-balanced)
- **Reclaim Policy**: Retain (preserve data for analysis)
- **Encryption**: Enabled
- **Multi-zone**: Regional persistent disks

#### Production Environment (`postgres-prod-ssd`)
- **Purpose**: Production workloads
- **Type**: High-performance SSD (pd-ssd)
- **Reclaim Policy**: Retain (data protection)
- **Encryption**: Mandatory
- **Multi-zone**: Regional persistent disks with high IOPS
- **Features**: Optimized for low latency and high throughput

#### Backup Storage (`postgres-backup-standard`)
- **Purpose**: Cost-optimized backup storage
- **Type**: Standard storage (pd-standard)
- **Reclaim Policy**: Retain
- **Encryption**: Enabled
- **Binding Mode**: Immediate (for backup jobs)

### 3. Backup and Disaster Recovery

#### Automated Backups
- **Schedule**: Daily at 2 AM (configurable via `backup.schedule`)
- **Retention**: 7 days (configurable via `backup.retentionDays`)
- **Format**: PostgreSQL custom format with compression
- **Storage**: Separate PVC for backup storage
- **Verification**: Automatic backup integrity checks

#### Volume Snapshots
- **Schedule**: Daily at 3 AM (configurable via `snapshots.schedule`)
- **Retention**: 7 snapshots (configurable via `snapshots.retentionCount`)
- **Type**: Kubernetes VolumeSnapshot API
- **Driver**: CSI-compatible (e.g., GKE PD CSI)
- **Automation**: CronJob-based with cleanup

#### Manual Operations
- **On-demand backups**: Via operational script
- **Point-in-time recovery**: Using backup restoration
- **Cross-region sync**: Optional cloud storage integration

### 4. Monitoring and Alerting

#### Metrics Collection
- **PostgreSQL Exporter**: Prometheus-compatible metrics
- **Custom Metrics**: Database-specific metrics collection
- **Storage Metrics**: PVC usage and I/O monitoring
- **Health Checks**: Liveness, readiness, and startup probes

#### Alert Rules
- **Disk Space**: Critical (85%) and warning (70%) thresholds
- **Connection Usage**: High connection count alerts
- **Replication Lag**: Replica synchronization monitoring
- **Backup Failures**: Failed backup job notifications
- **Performance**: Slow query and deadlock detection
- **Availability**: Database and pod health monitoring

### 5. Multi-Region Replication

#### Streaming Replication
- **Primary-Replica**: Hot standby configuration
- **WAL Streaming**: Real-time replication
- **Read-Only Access**: Dedicated read-only service
- **Failover**: Manual promotion capabilities

#### Cross-Region Backup
- **Cloud Storage**: GCS, S3, or Azure Blob integration
- **Schedule**: Every 6 hours (configurable)
- **Automation**: CronJob-based synchronization
- **Credentials**: Kubernetes secrets management

## Deployment Instructions

### Prerequisites
```bash
# Install required tools
kubectl version --client
helm version

# Ensure cluster has CSI driver for snapshots
kubectl get csidriver

# Verify storage classes
kubectl get storageclass
```

### Basic Deployment
```bash
# Deploy with default configuration
helm install pyairtable-stack ./helm/pyairtable-stack \
  --namespace pyairtable \
  --create-namespace

# Enable advanced features
helm upgrade pyairtable-stack ./helm/pyairtable-stack \
  --set databases.postgres.backup.enabled=true \
  --set databases.postgres.snapshots.enabled=true \
  --set databases.postgres.monitoring.enabled=true
```

### Production Deployment
```bash
# Production deployment with all features
helm install pyairtable-stack ./helm/pyairtable-stack \
  --namespace pyairtable-prod \
  --create-namespace \
  --values values-prod.yaml \
  --set databases.postgres.persistence.storageClass=postgres-prod-ssd \
  --set databases.postgres.backup.enabled=true \
  --set databases.postgres.snapshots.enabled=true \
  --set databases.postgres.monitoring.enabled=true \
  --set databases.postgres.replication.enabled=true
```

### Environment-Specific Values

#### Development (`values-dev.yaml`)
```yaml
databases:
  postgres:
    persistence:
      storageClass: postgres-dev-ssd
      size: 5Gi
    backup:
      enabled: false
    snapshots:
      enabled: false
    monitoring:
      enabled: true
```

#### Staging (`values-staging.yaml`)
```yaml
databases:
  postgres:
    persistence:
      storageClass: postgres-staging-balanced
      size: 20Gi
    backup:
      enabled: true
      retentionDays: 3
    snapshots:
      enabled: true
      retentionCount: 5
    monitoring:
      enabled: true
```

#### Production (`values-prod.yaml`)
```yaml
databases:
  postgres:
    persistence:
      storageClass: postgres-prod-ssd
      size: 100Gi
    backup:
      enabled: true
      retentionDays: 30
      storageSize: 200Gi
    snapshots:
      enabled: true
      retentionCount: 14
    monitoring:
      enabled: true
    replication:
      enabled: true
      replicas: 2
```

## Operational Procedures

### Daily Operations

#### Using the Operational Script
```bash
# Check PostgreSQL status
./scripts/postgres-ops.sh status

# Create manual backup
./scripts/postgres-ops.sh backup critical-point-backup

# Monitor performance
./scripts/postgres-ops.sh monitor

# Connect to database
./scripts/postgres-ops.sh connect
```

#### Manual Backup
```bash
# Create immediate backup
kubectl create job --from=cronjob/pyairtable-stack-postgres-backup manual-backup-$(date +%Y%m%d)

# Check backup status
kubectl get jobs -l app.kubernetes.io/component=postgres-backup
```

#### Volume Snapshot
```bash
# Create manual snapshot
./scripts/postgres-ops.sh snapshot emergency-snapshot

# List all snapshots
kubectl get volumesnapshots -n pyairtable
```

### Disaster Recovery Procedures

#### Complete Database Restoration
```bash
# 1. Scale down applications
kubectl scale deployment --replicas=0 -l app.kubernetes.io/name=pyairtable-stack

# 2. Stop PostgreSQL
kubectl scale statefulset pyairtable-stack-postgres --replicas=0

# 3. Restore from volume snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-restored-pvc
  namespace: pyairtable
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 100Gi
  dataSource:
    name: snapshot-name
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# 4. Update StatefulSet to use restored PVC
# 5. Scale up PostgreSQL
kubectl scale statefulset pyairtable-stack-postgres --replicas=1

# 6. Verify data integrity
./scripts/postgres-ops.sh status

# 7. Scale up applications
kubectl scale deployment --replicas=1 -l app.kubernetes.io/name=pyairtable-stack
```

#### Point-in-Time Recovery
```bash
# 1. Identify backup file
./scripts/postgres-ops.sh list-backups

# 2. Create restore job
helm upgrade pyairtable-stack ./helm/pyairtable-stack \
  --set databases.postgres.restore.enabled=true \
  --set databases.postgres.restore.backupFile="/backups/postgres/backup_20240101_020000.sql.gz"

# 3. Monitor restore progress
kubectl logs -f job/pyairtable-stack-postgres-restore-latest
```

### Scaling Operations

#### Horizontal Scaling (Read Replicas)
```bash
# Enable replication
helm upgrade pyairtable-stack ./helm/pyairtable-stack \
  --set databases.postgres.replication.enabled=true \
  --set databases.postgres.replication.replicas=2

# Verify replica status
kubectl exec -it pyairtable-stack-postgres-0 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

#### Vertical Scaling (Storage)
```bash
# Expand PVC (if storage class supports it)
kubectl patch pvc postgres-storage-pyairtable-stack-postgres-0 \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'

# Monitor expansion
kubectl get pvc postgres-storage-pyairtable-stack-postgres-0 -w
```

### Migration Procedures

#### Database Schema Migration
```bash
# Enable migration
helm upgrade pyairtable-stack ./helm/pyairtable-stack \
  --set databases.postgres.migration.enabled=true \
  --set databases.postgres.migration.version="2.0.0" \
  --set databases.postgres.migration.description="Add user management tables"

# Monitor migration
kubectl logs -f job/pyairtable-stack-postgres-migration-2.0.0
```

#### Kubernetes Cluster Migration
```bash
# 1. Create final backup
./scripts/postgres-ops.sh backup cluster-migration-backup

# 2. Create volume snapshot
./scripts/postgres-ops.sh snapshot cluster-migration-snapshot

# 3. Export backup to external storage
kubectl cp pyairtable/pyairtable-stack-postgres-0:/backups/postgres/cluster-migration-backup.sql.gz ./cluster-migration-backup.sql.gz

# 4. Deploy to new cluster
helm install pyairtable-stack ./helm/pyairtable-stack \
  --namespace pyairtable \
  --create-namespace \
  --values values-prod.yaml

# 5. Restore data
./scripts/postgres-ops.sh restore ./cluster-migration-backup.sql.gz
```

## Monitoring and Alerting

### Prometheus Metrics
Key metrics exposed by the PostgreSQL exporter:
- `pg_up`: Database availability
- `pg_database_size_bytes`: Database size
- `pg_stat_database_*`: Database statistics
- `pg_stat_replication_*`: Replication metrics
- `pg_locks_count`: Lock information

### Grafana Dashboards
Recommended dashboard queries:
```promql
# Database size growth
increase(pg_database_size_bytes[24h])

# Connection usage
pg_stat_database_numbackends / pg_settings_max_connections * 100

# Cache hit ratio
pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read) * 100

# Replication lag
pg_stat_replication_lag_seconds
```

### Alert Manager Integration
Example alert configuration:
```yaml
groups:
- name: postgres-storage
  rules:
  - alert: PostgreSQLDiskSpaceCritical
    expr: (pg_database_size_bytes / on(instance) kube_persistentvolume_capacity_bytes) * 100 > 85
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "PostgreSQL disk space critically low"
      description: "Database is using {{ $value }}% of available space"
```

## Troubleshooting

### Common Issues

#### Storage Full
```bash
# Check disk usage
kubectl exec pyairtable-stack-postgres-0 -- df -h /var/lib/postgresql/data

# Clean up old WAL files
kubectl exec pyairtable-stack-postgres-0 -- find /var/lib/postgresql/data/pg_wal -name "*.backup" -mtime +7 -delete

# Expand PVC if possible
kubectl patch pvc postgres-storage-pyairtable-stack-postgres-0 -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

#### Pod Stuck in Pending
```bash
# Check PVC status
kubectl describe pvc postgres-storage-pyairtable-stack-postgres-0

# Check storage class
kubectl describe storageclass postgres-prod-ssd

# Check node resources
kubectl describe nodes
```

#### Backup Failures
```bash
# Check backup job logs
kubectl logs job/pyairtable-stack-postgres-backup-$(date +%Y%m%d)

# Check backup PVC
kubectl describe pvc pyairtable-stack-postgres-backup-pvc

# Manual backup test
./scripts/postgres-ops.sh backup test-backup
```

#### Replication Issues
```bash
# Check replication status
kubectl exec pyairtable-stack-postgres-0 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Check replica logs
kubectl logs pyairtable-stack-postgres-replica-0

# Verify network connectivity
kubectl exec pyairtable-stack-postgres-replica-0 -- ping postgres
```

### Recovery Procedures

#### Pod Recovery
```bash
# Delete and recreate pod (data preserved in PVC)
kubectl delete pod pyairtable-stack-postgres-0

# Verify data integrity after restart
./scripts/postgres-ops.sh status
```

#### Corruption Recovery
```bash
# Check for corruption
kubectl exec pyairtable-stack-postgres-0 -- pg_checksums -D /var/lib/postgresql/data/pgdata

# Restore from backup if corruption found
./scripts/postgres-ops.sh restore /path/to/good/backup.sql.gz
```

## Security Considerations

### Data Encryption
- **At Rest**: Storage classes configured with encryption
- **In Transit**: TLS connections (configurable)
- **Backups**: Encrypted backup storage

### Access Control
- **RBAC**: Kubernetes role-based access control
- **Service Accounts**: Dedicated service accounts for operations
- **Network Policies**: Optional network segmentation
- **Secret Management**: Kubernetes secrets with rotation

### Compliance
- **Data Retention**: Configurable backup retention policies
- **Audit Logging**: PostgreSQL audit trail
- **Monitoring**: Comprehensive logging and alerting
- **Recovery Testing**: Regular disaster recovery drills

## Performance Optimization

### Storage Performance
- **Storage Class Selection**: Match workload requirements
- **IOPS Configuration**: Provision adequate IOPS for production
- **Multi-zone**: Regional persistent disks for availability

### Database Tuning
- **Memory Settings**: Optimized shared_buffers and work_mem
- **Checkpoint Tuning**: Balanced checkpoint frequency
- **WAL Configuration**: Appropriate WAL settings for replication

### Monitoring Optimization
- **Metric Collection**: Efficient metric scraping
- **Alert Tuning**: Appropriate thresholds to avoid noise
- **Dashboard Performance**: Optimized Grafana queries

## Cost Optimization

### Storage Costs
- **Environment-specific Classes**: Different storage for dev/staging/prod
- **Backup Retention**: Appropriate retention periods
- **Snapshot Management**: Automated cleanup of old snapshots

### Compute Costs
- **Resource Requests**: Right-sized resource allocation
- **Replica Management**: Scale replicas based on load
- **Backup Scheduling**: Off-peak backup execution

This comprehensive guide provides all necessary information for managing PostgreSQL persistent storage in Kubernetes, ensuring data durability, performance, and operational excellence.