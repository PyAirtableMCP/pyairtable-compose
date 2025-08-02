#!/bin/bash

# PostgreSQL Operations Script for Kubernetes
# This script provides operational commands for PostgreSQL management in Kubernetes

set -euo pipefail

# Configuration
NAMESPACE="${POSTGRES_NAMESPACE:-pyairtable}"
RELEASE_NAME="${HELM_RELEASE:-pyairtable-stack}"
POSTGRES_POD="${POSTGRES_POD:-${RELEASE_NAME}-postgres-0}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
BACKUP_DIR="${BACKUP_DIR:-/tmp/postgres-backups}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl is required but not installed"; exit 1; }
    command -v helm >/dev/null 2>&1 || { log_error "helm is required but not installed"; exit 1; }
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get PostgreSQL status
postgres_status() {
    log_info "Checking PostgreSQL status..."
    
    echo "=== Pod Status ==="
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=postgres
    
    echo -e "\n=== Service Status ==="
    kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/component=postgres
    
    echo -e "\n=== PVC Status ==="
    kubectl get pvc -n "$NAMESPACE" -l app.kubernetes.io/component=postgres
    
    echo -e "\n=== PostgreSQL Version ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -c "SELECT version();" 2>/dev/null || log_warn "Could not connect to PostgreSQL"
    
    echo -e "\n=== Database Size ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('pyairtable'));" 2>/dev/null || log_warn "Could not get database size"
    
    echo -e "\n=== Connection Count ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -c "SELECT count(*) as active_connections FROM pg_stat_activity;" 2>/dev/null || log_warn "Could not get connection count"
}

# Create backup
create_backup() {
    local backup_name="${1:-manual_$(date +%Y%m%d_%H%M%S)}"
    
    log_info "Creating backup: $backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    # Create backup using pg_dump
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- pg_dump -U postgres -d pyairtable --format=custom --compress=9 > "${BACKUP_DIR}/${backup_name}.sql"
    
    # Compress backup
    gzip "${BACKUP_DIR}/${backup_name}.sql"
    
    local backup_size=$(du -h "${BACKUP_DIR}/${backup_name}.sql.gz" | cut -f1)
    log_success "Backup created: ${BACKUP_DIR}/${backup_name}.sql.gz (${backup_size})"
}

# List backups
list_backups() {
    log_info "Available backups:"
    
    if [ -d "$BACKUP_DIR" ]; then
        ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null || log_warn "No backups found in $BACKUP_DIR"
    else
        log_warn "Backup directory $BACKUP_DIR does not exist"
    fi
    
    echo -e "\n=== Kubernetes Backup Jobs ==="
    kubectl get jobs -n "$NAMESPACE" -l app.kubernetes.io/component=postgres-backup
    
    echo -e "\n=== Volume Snapshots ==="
    kubectl get volumesnapshots -n "$NAMESPACE" -l app.kubernetes.io/component=postgres-snapshots
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        log_error "Usage: $0 restore <backup_file>"
        exit 1
    fi
    
    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_warn "This will restore the database from backup. This operation is destructive!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
    
    log_info "Restoring from backup: $backup_file"
    
    # Copy backup to pod
    kubectl cp "$backup_file" "$NAMESPACE/$POSTGRES_POD:/tmp/restore.sql.gz"
    
    # Restore database
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c "
        gunzip -c /tmp/restore.sql.gz | pg_restore -U postgres -d pyairtable --clean --if-exists --verbose
        rm -f /tmp/restore.sql.gz
    "
    
    log_success "Database restored from $backup_file"
}

# Scale PostgreSQL
scale_postgres() {
    local replicas="$1"
    
    if [ -z "$replicas" ]; then
        log_error "Usage: $0 scale <replicas>"
        exit 1
    fi
    
    log_info "Scaling PostgreSQL to $replicas replicas"
    
    kubectl patch statefulset -n "$NAMESPACE" "${RELEASE_NAME}-postgres" -p "{\"spec\":{\"replicas\":$replicas}}"
    
    log_info "Waiting for scaling to complete..."
    kubectl rollout status statefulset -n "$NAMESPACE" "${RELEASE_NAME}-postgres" --timeout=300s
    
    log_success "PostgreSQL scaled to $replicas replicas"
}

# Get PostgreSQL logs
get_logs() {
    local lines="${1:-50}"
    
    log_info "Getting PostgreSQL logs (last $lines lines)"
    kubectl logs -n "$NAMESPACE" "$POSTGRES_POD" --tail="$lines" -f
}

# Connect to PostgreSQL
connect() {
    log_info "Connecting to PostgreSQL..."
    kubectl exec -it -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable
}

# Run PostgreSQL command
run_sql() {
    local sql="$1"
    
    if [ -z "$sql" ]; then
        log_error "Usage: $0 sql '<SQL_COMMAND>'"
        exit 1
    fi
    
    log_info "Executing SQL: $sql"
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "$sql"
}

# Performance monitoring
performance_monitor() {
    log_info "PostgreSQL Performance Monitoring"
    
    echo "=== Current Activity ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "
        SELECT pid, usename, application_name, client_addr, state, query_start, query 
        FROM pg_stat_activity 
        WHERE state != 'idle' AND query != '<IDLE>'
        ORDER BY query_start DESC;
    " 2>/dev/null || log_warn "Could not get activity information"
    
    echo -e "\n=== Lock Information ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "
        SELECT blocked_locks.pid AS blocked_pid,
               blocked_activity.usename AS blocked_user,
               blocking_locks.pid AS blocking_pid,
               blocking_activity.usename AS blocking_user,
               blocked_activity.query AS blocked_statement,
               blocking_activity.query AS current_statement_in_blocking_process
        FROM pg_catalog.pg_locks blocked_locks
        JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
        JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
        AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
        AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
        AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
        AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
        AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
        AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
        AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
        AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
        AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
        AND blocking_locks.pid != blocked_locks.pid
        JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
        WHERE NOT blocked_locks.GRANTED;
    " 2>/dev/null || log_warn "Could not get lock information"
    
    echo -e "\n=== Database Statistics ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "
        SELECT datname, numbackends, xact_commit, xact_rollback, 
               blks_read, blks_hit, 
               round(100.0 * blks_hit / (blks_hit + blks_read), 2) AS cache_hit_ratio
        FROM pg_stat_database 
        WHERE datname = 'pyairtable';
    " 2>/dev/null || log_warn "Could not get database statistics"
}

# Vacuum and maintenance
maintenance() {
    log_info "Running PostgreSQL maintenance tasks"
    
    echo "=== Running VACUUM ANALYZE ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "VACUUM ANALYZE;"
    
    echo -e "\n=== Updating Statistics ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "ANALYZE;"
    
    echo -e "\n=== Reindexing ==="
    kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U postgres -d pyairtable -c "REINDEX DATABASE pyairtable;"
    
    log_success "Maintenance tasks completed"
}

# Create volume snapshot
create_snapshot() {
    local snapshot_name="${1:-manual-snapshot-$(date +%Y%m%d-%H%M%S)}"
    
    log_info "Creating volume snapshot: $snapshot_name"
    
    cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $snapshot_name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: pyairtable-stack
    app.kubernetes.io/component: postgres-snapshots
    backup.type: volume-snapshot
    created.by: manual
spec:
  volumeSnapshotClassName: ${RELEASE_NAME}-postgres-snapshot-class
  source:
    persistentVolumeClaimName: postgres-storage-${POSTGRES_POD}
EOF
    
    log_info "Waiting for snapshot to be ready..."
    kubectl wait --for=condition=ReadyToUse volumesnapshot/$snapshot_name -n $NAMESPACE --timeout=300s
    
    log_success "Volume snapshot created: $snapshot_name"
}

# Show help
show_help() {
    cat <<EOF
PostgreSQL Operations Script for Kubernetes

Usage: $0 <command> [options]

Commands:
    status                      Show PostgreSQL status and health
    backup [name]              Create a backup (optional custom name)
    list-backups               List available backups and snapshots
    restore <backup_file>      Restore from backup file
    scale <replicas>           Scale PostgreSQL replicas
    logs [lines]               Show PostgreSQL logs (default: 50 lines)
    connect                    Connect to PostgreSQL interactive shell
    sql '<command>'            Execute SQL command
    monitor                    Show performance monitoring information
    maintenance                Run maintenance tasks (VACUUM, ANALYZE, REINDEX)
    snapshot [name]            Create volume snapshot
    help                       Show this help message

Environment Variables:
    POSTGRES_NAMESPACE         Kubernetes namespace (default: pyairtable)
    HELM_RELEASE              Helm release name (default: pyairtable-stack)
    POSTGRES_POD              PostgreSQL pod name (default: \$HELM_RELEASE-postgres-0)
    POSTGRES_SERVICE          PostgreSQL service name (default: postgres)
    POSTGRES_PORT             PostgreSQL port (default: 5432)
    BACKUP_DIR                Local backup directory (default: /tmp/postgres-backups)

Examples:
    $0 status                                    # Check PostgreSQL status
    $0 backup production-backup-20240101         # Create named backup
    $0 restore /path/to/backup.sql.gz           # Restore from backup
    $0 scale 2                                   # Scale to 2 replicas
    $0 sql 'SELECT COUNT(*) FROM sessions;'     # Execute SQL command
    $0 snapshot critical-point-snapshot         # Create volume snapshot

EOF
}

# Main script
main() {
    case "${1:-help}" in
        status)
            check_prerequisites
            postgres_status
            ;;
        backup)
            check_prerequisites
            create_backup "$2"
            ;;
        list-backups)
            list_backups
            ;;
        restore)
            check_prerequisites
            restore_backup "$2"
            ;;
        scale)
            check_prerequisites
            scale_postgres "$2"
            ;;
        logs)
            check_prerequisites
            get_logs "$2"
            ;;
        connect)
            check_prerequisites
            connect
            ;;
        sql)
            check_prerequisites
            run_sql "$2"
            ;;
        monitor)
            check_prerequisites
            performance_monitor
            ;;
        maintenance)
            check_prerequisites
            maintenance
            ;;
        snapshot)
            check_prerequisites
            create_snapshot "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"