#!/bin/bash

# Kafka Backup and Disaster Recovery Script for PyAirtable
# This script provides comprehensive backup and restoration capabilities

set -e

# Configuration
KAFKA_HOME=${KAFKA_HOME:-/opt/kafka}
BACKUP_DIR=${BACKUP_DIR:-/var/kafka-backups}
S3_BUCKET=${S3_BUCKET:-pyairtable-kafka-backups}
KAFKA_BROKERS=${KAFKA_BROKERS:-kafka-1:29092,kafka-2:29095,kafka-3:29098}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
LOG_FILE=${LOG_FILE:-/var/log/kafka-backup.log}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

info() {
    log "INFO" "${GREEN}$*${NC}"
}

warn() {
    log "WARN" "${YELLOW}$*${NC}"
}

error() {
    log "ERROR" "${RED}$*${NC}"
    exit 1
}

# Function to check dependencies
check_dependencies() {
    info "Checking dependencies..."
    
    local deps=("kafka-console-consumer" "kafka-topics" "kafka-consumer-groups" "aws" "jq")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' is not installed"
        fi
    done
    
    # Check if backup directory exists
    mkdir -p "$BACKUP_DIR"
    
    info "All dependencies satisfied"
}

# Function to get list of PyAirtable topics
get_pyairtable_topics() {
    info "Discovering PyAirtable topics..."
    
    kafka-topics --bootstrap-server "$KAFKA_BROKERS" --list | grep "^pyairtable\." || true
}

# Function to backup topic metadata
backup_topic_metadata() {
    local topic=$1
    local backup_path=$2
    
    info "Backing up metadata for topic: $topic"
    
    # Get topic configuration
    kafka-topics --bootstrap-server "$KAFKA_BROKERS" --describe --topic "$topic" > "$backup_path/$topic-metadata.txt"
    
    # Get consumer group information
    kafka-consumer-groups --bootstrap-server "$KAFKA_BROKERS" --list | grep -E "(pyairtable|$topic)" > "$backup_path/$topic-consumer-groups.txt" || true
    
    # Get topic partitions and replicas info
    kafka-topics --bootstrap-server "$KAFKA_BROKERS" --describe --topic "$topic" --topics-with-overrides > "$backup_path/$topic-config.txt" || true
}

# Function to backup topic data using Kafka Connect
backup_topic_data() {
    local topic=$1
    local backup_path=$2
    
    info "Backing up data for topic: $topic"
    
    # Create connector configuration for backup
    local connector_config=$(cat <<EOF
{
  "name": "backup-$topic-$(date +%s)",
  "config": {
    "connector.class": "io.confluent.connect.s3.S3SinkConnector",
    "tasks.max": "3",
    "topics": "$topic",
    "s3.bucket.name": "$S3_BUCKET",
    "s3.part.size": 5242880,
    "flush.size": 1000,
    "storage.class": "io.confluent.connect.s3.storage.S3Storage",
    "format.class": "io.confluent.connect.s3.format.avro.AvroFormat",
    "schema.generator.class": "io.confluent.connect.storage.hive.schema.DefaultSchemaGenerator",
    "partitioner.class": "io.confluent.connect.storage.partitioner.DefaultPartitioner",
    "schema.compatibility": "NONE",
    "s3.region": "us-west-2"
  }
}
EOF
    )
    
    # Submit connector to Kafka Connect
    curl -X POST \
        -H "Content-Type: application/json" \
        --data "$connector_config" \
        http://kafka-connect:8083/connectors
    
    info "Backup connector created for topic: $topic"
}

# Function to export topic data to local files (fallback method)
export_topic_data() {
    local topic=$1
    local backup_path=$2
    local max_messages=${3:-100000}
    
    info "Exporting data for topic: $topic (max $max_messages messages)"
    
    # Get earliest and latest offsets
    local earliest_offset=$(kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list "$KAFKA_BROKERS" \
        --topic "$topic" \
        --time -2 | head -1 | cut -d: -f3)
    
    local latest_offset=$(kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list "$KAFKA_BROKERS" \
        --topic "$topic" \
        --time -1 | head -1 | cut -d: -f3)
    
    info "Topic $topic: earliest offset=$earliest_offset, latest offset=$latest_offset"
    
    # Export messages to file
    timeout 300 kafka-console-consumer \
        --bootstrap-server "$KAFKA_BROKERS" \
        --topic "$topic" \
        --from-beginning \
        --max-messages "$max_messages" \
        --property print.timestamp=true \
        --property print.key=true \
        --property print.partition=true \
        --property print.offset=true > "$backup_path/$topic-data.jsonl" || true
    
    # Compress the data file
    gzip "$backup_path/$topic-data.jsonl"
    
    info "Topic data exported and compressed: $backup_path/$topic-data.jsonl.gz"
}

# Function to backup consumer group offsets
backup_consumer_offsets() {
    local consumer_group=$1
    local backup_path=$2
    
    info "Backing up consumer group offsets: $consumer_group"
    
    kafka-consumer-groups --bootstrap-server "$KAFKA_BROKERS" \
        --describe --group "$consumer_group" \
        --verbose > "$backup_path/$consumer_group-offsets.txt"
}

# Function to create full backup
create_full_backup() {
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/full_backup_$backup_date"
    
    info "Creating full backup: $backup_path"
    mkdir -p "$backup_path"
    
    # Get list of PyAirtable topics
    local topics=($(get_pyairtable_topics))
    
    if [ ${#topics[@]} -eq 0 ]; then
        warn "No PyAirtable topics found"
        return
    fi
    
    info "Found ${#topics[@]} PyAirtable topics to backup"
    
    # Backup each topic
    for topic in "${topics[@]}"; do
        info "Processing topic: $topic"
        
        local topic_backup_path="$backup_path/$topic"
        mkdir -p "$topic_backup_path"
        
        # Backup metadata
        backup_topic_metadata "$topic" "$topic_backup_path"
        
        # Backup data (using export method)
        export_topic_data "$topic" "$topic_backup_path"
    done
    
    # Backup consumer groups
    info "Backing up consumer groups..."
    local consumer_groups=($(kafka-consumer-groups --bootstrap-server "$KAFKA_BROKERS" --list | grep -E "pyairtable" || true))
    
    for group in "${consumer_groups[@]}"; do
        backup_consumer_offsets "$group" "$backup_path"
    done
    
    # Create backup manifest
    cat > "$backup_path/backup-manifest.json" <<EOF
{
  "backup_date": "$backup_date",
  "backup_type": "full",
  "kafka_brokers": "$KAFKA_BROKERS",
  "topics_count": ${#topics[@]},
  "topics": $(printf '%s\n' "${topics[@]}" | jq -R . | jq -s .),
  "consumer_groups_count": ${#consumer_groups[@]},
  "consumer_groups": $(printf '%s\n' "${consumer_groups[@]}" | jq -R . | jq -s .),
  "backup_size_bytes": $(du -sb "$backup_path" | cut -f1)
}
EOF
    
    # Compress the entire backup
    tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "full_backup_$backup_date"
    rm -rf "$backup_path"
    
    info "Full backup completed: $backup_path.tar.gz"
    
    # Upload to S3 if configured
    if [ -n "$S3_BUCKET" ]; then
        info "Uploading backup to S3..."
        aws s3 cp "$backup_path.tar.gz" "s3://$S3_BUCKET/full-backups/"
        info "Backup uploaded to S3: s3://$S3_BUCKET/full-backups/$(basename "$backup_path.tar.gz")"
    fi
}

# Function to create incremental backup
create_incremental_backup() {
    local backup_date=$(date +%Y%m%d_%H%M%S)
    local backup_path="$BACKUP_DIR/incremental_backup_$backup_date"
    local since_timestamp=${1:-$(date -d '1 hour ago' +%s)000}
    
    info "Creating incremental backup since timestamp: $since_timestamp"
    mkdir -p "$backup_path"
    
    # Get list of PyAirtable topics
    local topics=($(get_pyairtable_topics))
    
    # Backup recent messages from each topic
    for topic in "${topics[@]}"; do
        info "Processing incremental backup for topic: $topic"
        
        local topic_backup_path="$backup_path/$topic"
        mkdir -p "$topic_backup_path"
        
        # Export recent messages only
        timeout 120 kafka-console-consumer \
            --bootstrap-server "$KAFKA_BROKERS" \
            --topic "$topic" \
            --property print.timestamp=true \
            --property print.key=true \
            --property print.partition=true \
            --property print.offset=true \
            --from-beginning \
            --max-messages 10000 | \
            awk -v since="$since_timestamp" '$1 > since' > "$topic_backup_path/$topic-incremental.jsonl" || true
        
        # Compress if file has content
        if [ -s "$topic_backup_path/$topic-incremental.jsonl" ]; then
            gzip "$topic_backup_path/$topic-incremental.jsonl"
        else
            rm -f "$topic_backup_path/$topic-incremental.jsonl"
            rmdir "$topic_backup_path" 2>/dev/null || true
        fi
    done
    
    # Create incremental backup manifest
    cat > "$backup_path/incremental-manifest.json" <<EOF
{
  "backup_date": "$backup_date",
  "backup_type": "incremental",
  "since_timestamp": $since_timestamp,
  "kafka_brokers": "$KAFKA_BROKERS",
  "backup_size_bytes": $(du -sb "$backup_path" | cut -f1)
}
EOF
    
    # Compress and upload
    tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "incremental_backup_$backup_date"
    rm -rf "$backup_path"
    
    info "Incremental backup completed: $backup_path.tar.gz"
    
    if [ -n "$S3_BUCKET" ]; then
        aws s3 cp "$backup_path.tar.gz" "s3://$S3_BUCKET/incremental-backups/"
    fi
}

# Function to restore from backup
restore_from_backup() {
    local backup_file=$1
    local restore_type=${2:-metadata}  # metadata, data, or full
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
    fi
    
    info "Restoring from backup: $backup_file (type: $restore_type)"
    
    local restore_dir="$BACKUP_DIR/restore_$(date +%s)"
    mkdir -p "$restore_dir"
    
    # Extract backup
    tar -xzf "$backup_file" -C "$restore_dir"
    
    local extracted_dir=$(find "$restore_dir" -maxdepth 1 -type d -name "*backup*" | head -1)
    
    if [ -z "$extracted_dir" ]; then
        error "Could not find extracted backup directory"
    fi
    
    # Read manifest
    local manifest_file="$extracted_dir/backup-manifest.json"
    if [ ! -f "$manifest_file" ]; then
        manifest_file="$extracted_dir/incremental-manifest.json"
    fi
    
    if [ -f "$manifest_file" ]; then
        info "Backup manifest:"
        jq . "$manifest_file"
    fi
    
    case "$restore_type" in
        "metadata")
            restore_topic_metadata "$extracted_dir"
            ;;
        "data")
            restore_topic_data "$extracted_dir"
            ;;
        "full")
            restore_topic_metadata "$extracted_dir"
            restore_topic_data "$extracted_dir"
            restore_consumer_offsets "$extracted_dir"
            ;;
        *)
            error "Invalid restore type: $restore_type. Use metadata, data, or full"
            ;;
    esac
    
    # Cleanup
    rm -rf "$restore_dir"
    
    info "Restore completed successfully"
}

# Function to restore topic metadata
restore_topic_metadata() {
    local backup_dir=$1
    
    info "Restoring topic metadata..."
    
    for topic_dir in "$backup_dir"/*; do
        if [ -d "$topic_dir" ]; then
            local topic=$(basename "$topic_dir")
            
            if [[ "$topic" == pyairtable.* ]]; then
                info "Restoring metadata for topic: $topic"
                
                # Check if topic exists
                if kafka-topics --bootstrap-server "$KAFKA_BROKERS" --list | grep -q "^$topic$"; then
                    warn "Topic $topic already exists, skipping creation"
                else
                    # Create topic from metadata
                    local metadata_file="$topic_dir/$topic-metadata.txt"
                    if [ -f "$metadata_file" ]; then
                        # Parse topic configuration and create topic
                        # This is a simplified version - in production, you'd parse the metadata more carefully
                        kafka-topics --bootstrap-server "$KAFKA_BROKERS" \
                            --create --topic "$topic" \
                            --partitions 12 --replication-factor 3
                        
                        info "Topic $topic recreated"
                    fi
                fi
            fi
        fi
    done
}

# Function to restore topic data
restore_topic_data() {
    local backup_dir=$1
    
    info "Restoring topic data..."
    
    for topic_dir in "$backup_dir"/*; do
        if [ -d "$topic_dir" ]; then
            local topic=$(basename "$topic_dir")
            
            if [[ "$topic" == pyairtable.* ]]; then
                local data_file="$topic_dir/$topic-data.jsonl.gz"
                local incremental_file="$topic_dir/$topic-incremental.jsonl.gz"
                
                # Choose the appropriate data file
                local restore_file=""
                if [ -f "$data_file" ]; then
                    restore_file="$data_file"
                elif [ -f "$incremental_file" ]; then
                    restore_file="$incremental_file"
                fi
                
                if [ -n "$restore_file" ]; then
                    info "Restoring data for topic: $topic from $restore_file"
                    
                    # Decompress and restore data using kafka-console-producer
                    zcat "$restore_file" | \
                    awk -F'\t' '{
                        # Parse the console consumer output format
                        # Format: CreateTime:timestamp partition:N offset:N key value
                        print $NF  # Print just the value
                    }' | \
                    kafka-console-producer --bootstrap-server "$KAFKA_BROKERS" --topic "$topic"
                    
                    info "Data restored for topic: $topic"
                else
                    warn "No data file found for topic: $topic"
                fi
            fi
        fi
    done
}

# Function to restore consumer group offsets
restore_consumer_offsets() {
    local backup_dir=$1
    
    info "Restoring consumer group offsets..."
    
    # This is a placeholder - in practice, you'd need to parse the offset files
    # and use kafka-consumer-groups --reset-offsets to restore them
    warn "Consumer offset restoration is not fully implemented in this script"
    warn "Manual intervention may be required to restore consumer group offsets"
}

# Function to cleanup old backups
cleanup_old_backups() {
    info "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
    
    # Local cleanup
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -delete
    
    # S3 cleanup
    if [ -n "$S3_BUCKET" ]; then
        local cutoff_date=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d)
        
        aws s3api list-objects-v2 --bucket "$S3_BUCKET" \
            --query "Contents[?LastModified<='$cutoff_date'].Key" \
            --output text | \
        xargs -r -n1 aws s3 rm "s3://$S3_BUCKET/"
    fi
    
    info "Cleanup completed"
}

# Function to verify backup integrity
verify_backup() {
    local backup_file=$1
    
    info "Verifying backup integrity: $backup_file"
    
    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
    fi
    
    # Check if tar file is valid
    if ! tar -tzf "$backup_file" >/dev/null; then
        error "Backup file is corrupted: $backup_file"
    fi
    
    # Extract and verify manifest
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    
    local manifest_file=$(find "$temp_dir" -name "*manifest.json" | head -1)
    
    if [ -f "$manifest_file" ]; then
        if ! jq . "$manifest_file" >/dev/null; then
            error "Backup manifest is invalid"
        fi
        
        info "Backup verification successful"
        jq . "$manifest_file"
    else
        warn "No manifest found in backup"
    fi
    
    rm -rf "$temp_dir"
}

# Function to list available backups
list_backups() {
    info "Available local backups:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No local backups found"
    
    if [ -n "$S3_BUCKET" ]; then
        info "Available S3 backups:"
        aws s3 ls "s3://$S3_BUCKET/" --recursive --human-readable
    fi
}

# Main function
main() {
    case "${1:-help}" in
        "full-backup")
            check_dependencies
            create_full_backup
            ;;
        "incremental-backup")
            check_dependencies
            create_incremental_backup "$2"
            ;;
        "restore")
            check_dependencies
            restore_from_backup "$2" "$3"
            ;;
        "verify")
            verify_backup "$2"
            ;;
        "cleanup")
            cleanup_old_backups
            ;;
        "list")
            list_backups
            ;;
        "help"|*)
            cat <<EOF
Kafka Backup and Disaster Recovery Script for PyAirtable

Usage: $0 <command> [options]

Commands:
  full-backup                    Create a full backup of all PyAirtable topics
  incremental-backup [since]     Create an incremental backup (since timestamp in ms)
  restore <backup-file> [type]   Restore from backup (type: metadata|data|full)
  verify <backup-file>           Verify backup file integrity
  cleanup                        Remove old backups (older than $BACKUP_RETENTION_DAYS days)
  list                          List available backups
  help                          Show this help message

Environment Variables:
  KAFKA_BROKERS                 Kafka broker list (default: kafka-1:29092,kafka-2:29095,kafka-3:29098)
  BACKUP_DIR                    Local backup directory (default: /var/kafka-backups)
  S3_BUCKET                     S3 bucket for backup storage (optional)
  BACKUP_RETENTION_DAYS         Backup retention period (default: 30)
  LOG_FILE                      Log file path (default: /var/log/kafka-backup.log)

Examples:
  $0 full-backup
  $0 incremental-backup 1640995200000
  $0 restore /var/kafka-backups/full_backup_20231201_120000.tar.gz full
  $0 verify /var/kafka-backups/full_backup_20231201_120000.tar.gz
  $0 cleanup
  $0 list

EOF
            ;;
    esac
}

# Run main function with all arguments
main "$@"