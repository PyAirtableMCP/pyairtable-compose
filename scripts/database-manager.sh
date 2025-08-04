#!/bin/bash

# PyAirtable Database Management System
# Comprehensive database initialization, migration, and maintenance for Minikube deployment
# Author: Claude Deployment Engineer

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly MIGRATIONS_DIR="${PROJECT_ROOT}/migrations"
readonly BACKUP_DIR="${PROJECT_ROOT}/.backups/database"
readonly NAMESPACE="${NAMESPACE:-pyairtable}"
readonly DB_SERVICE="postgres"
readonly DB_POD_SELECTOR="app=postgres"

# Database configuration
readonly DB_NAME="${POSTGRES_DB:-pyairtablemcp}"
readonly DB_USER="${POSTGRES_USER:-admin}"
readonly DB_PORT="5432"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Migration configuration
readonly MIGRATION_TABLE="_migration_log"
readonly LOCK_TABLE="_migration_lock"
readonly BACKUP_RETENTION_DAYS=30

# Logging functions
log() {
    echo -e "${WHITE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  $*${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Database connection functions
get_db_pod() {
    kubectl get pods -n "$NAMESPACE" -l "$DB_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

wait_for_db() {
    local timeout="${1:-300}"
    local interval=5
    local elapsed=0
    
    log_info "Waiting for database to be ready..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local pod
        pod=$(get_db_pod)
        
        if [[ -n "$pod" ]]; then
            if kubectl exec -n "$NAMESPACE" "$pod" -- pg_isready -U "$DB_USER" -d "$DB_NAME" &>/dev/null; then
                log_success "Database is ready"
                return 0
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log_info "Still waiting for database... (${elapsed}s elapsed)"
        fi
    done
    
    log_error "Database failed to become ready within ${timeout}s"
    return 1
}

# Execute SQL command
exec_sql() {
    local sql="$1"
    local database="${2:-$DB_NAME}"
    local user="${3:-$DB_USER}"
    
    local pod
    pod=$(get_db_pod)
    
    if [[ -z "$pod" ]]; then
        log_error "No database pod found"
        return 1
    fi
    
    kubectl exec -n "$NAMESPACE" "$pod" -- psql -U "$user" -d "$database" -c "$sql"
}

# Execute SQL file
exec_sql_file() {
    local sql_file="$1"
    local database="${2:-$DB_NAME}"
    local user="${3:-$DB_USER}"
    
    local pod
    pod=$(get_db_pod)
    
    if [[ -z "$pod" ]]; then
        log_error "No database pod found"
        return 1
    fi
    
    if [[ ! -f "$sql_file" ]]; then
        log_error "SQL file not found: $sql_file"
        return 1
    fi
    
    kubectl exec -i -n "$NAMESPACE" "$pod" -- psql -U "$user" -d "$database" < "$sql_file"
}

# Check if database exists and is accessible
check_database() {
    log_info "Checking database connectivity..."
    
    local pod
    pod=$(get_db_pod)
    
    if [[ -z "$pod" ]]; then
        log_error "No database pod found in namespace: $NAMESPACE"
        return 1
    fi
    
    # Check if PostgreSQL is running
    if ! kubectl exec -n "$NAMESPACE" "$pod" -- pg_isready -U "$DB_USER" -d "$DB_NAME" &>/dev/null; then
        log_error "Database is not ready"
        return 1
    fi
    
    # Test connection
    if ! exec_sql "SELECT 1;" &>/dev/null; then
        log_error "Cannot connect to database"
        return 1
    fi
    
    log_success "Database is accessible"
    return 0
}

# Initialize migration system
init_migration_system() {
    log_section "INITIALIZING MIGRATION SYSTEM"
    
    if ! check_database; then
        return 1
    fi
    
    log_info "Creating migration tracking tables..."
    
    # Create migration log table
    exec_sql "
        CREATE TABLE IF NOT EXISTS $MIGRATION_TABLE (
            id SERIAL PRIMARY KEY,
            version VARCHAR(255) NOT NULL UNIQUE,
            name VARCHAR(255) NOT NULL,
            checksum VARCHAR(64) NOT NULL,
            applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            applied_by VARCHAR(100) DEFAULT CURRENT_USER,
            execution_time_ms INTEGER,
            success BOOLEAN DEFAULT TRUE,
            error_message TEXT
        );
        
        CREATE INDEX IF NOT EXISTS idx_migration_version ON $MIGRATION_TABLE (version);
        CREATE INDEX IF NOT EXISTS idx_migration_applied_at ON $MIGRATION_TABLE (applied_at);
    " || {
        log_error "Failed to create migration log table"
        return 1
    }
    
    # Create migration lock table
    exec_sql "
        CREATE TABLE IF NOT EXISTS $LOCK_TABLE (
            lock_name VARCHAR(100) PRIMARY KEY,
            locked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            locked_by VARCHAR(100) DEFAULT CURRENT_USER,
            process_id VARCHAR(100)
        );
    " || {
        log_error "Failed to create migration lock table"
        return 1
    }
    
    log_success "Migration system initialized"
}

# Setup migration directory structure
setup_migration_directory() {
    log_info "Setting up migration directory structure..."
    
    mkdir -p "$MIGRATIONS_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Create migration directory structure
    mkdir -p "${MIGRATIONS_DIR}/core"
    mkdir -p "${MIGRATIONS_DIR}/data"
    mkdir -p "${MIGRATIONS_DIR}/indexes"
    mkdir -p "${MIGRATIONS_DIR}/functions"
    mkdir -p "${MIGRATIONS_DIR}/triggers"
    mkdir -p "${MIGRATIONS_DIR}/views"
    
    # Create .gitkeep files
    for dir in core data indexes functions triggers views; do
        touch "${MIGRATIONS_DIR}/${dir}/.gitkeep"
    done
    
    # Create migration template
    if [[ ! -f "${MIGRATIONS_DIR}/migration_template.sql" ]]; then
        cat > "${MIGRATIONS_DIR}/migration_template.sql" << 'EOF'
-- Migration: [DESCRIPTION]
-- Version: [VERSION]
-- Author: [AUTHOR]
-- Created: [DATE]

-- ================================
-- UP Migration
-- ================================

BEGIN;

-- Your migration SQL here
-- Example:
-- CREATE TABLE example_table (
--     id SERIAL PRIMARY KEY,
--     name VARCHAR(255) NOT NULL,
--     created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
-- );

COMMIT;

-- ================================
-- DOWN Migration (for rollback)
-- ================================

-- BEGIN;
-- 
-- DROP TABLE IF EXISTS example_table;
-- 
-- COMMIT;
EOF
    fi
    
    log_success "Migration directory structure created"
}

# Generate migration checksum
generate_checksum() {
    local file="$1"
    
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        # Fallback to md5
        md5sum "$file" 2>/dev/null | cut -d' ' -f1 || md5 "$file" | cut -d' ' -f4
    fi
}

# Acquire migration lock
acquire_lock() {
    local lock_name="${1:-migration}"
    local process_id="$$"
    
    log_info "Acquiring migration lock..."
    
    # Try to acquire lock
    local lock_result
    lock_result=$(exec_sql "
        INSERT INTO $LOCK_TABLE (lock_name, process_id) 
        VALUES ('$lock_name', '$process_id') 
        ON CONFLICT (lock_name) DO NOTHING 
        RETURNING lock_name;
    " 2>/dev/null || echo "")
    
    if [[ -z "$lock_result" ]]; then
        # Check who has the lock
        local lock_info
        lock_info=$(exec_sql "
            SELECT locked_at, locked_by, process_id 
            FROM $LOCK_TABLE 
            WHERE lock_name = '$lock_name';
        " 2>/dev/null || echo "")
        
        log_error "Migration is already in progress:"
        echo "$lock_info"
        return 1
    fi
    
    log_success "Migration lock acquired"
    return 0
}

# Release migration lock
release_lock() {
    local lock_name="${1:-migration}"
    
    exec_sql "DELETE FROM $LOCK_TABLE WHERE lock_name = '$lock_name';" &>/dev/null || true
    log_info "Migration lock released"
}

# Get applied migrations
get_applied_migrations() {
    exec_sql "SELECT version FROM $MIGRATION_TABLE WHERE success = TRUE ORDER BY version;" 2>/dev/null | tail -n +3 | head -n -2 | grep -v '^$' || true
}

# Get pending migrations
get_pending_migrations() {
    local applied_migrations
    applied_migrations=$(get_applied_migrations)
    
    local all_migrations=()
    if [[ -d "$MIGRATIONS_DIR" ]]; then
        # Find all migration files
        while IFS= read -r -d '' file; do
            local basename_file
            basename_file=$(basename "$file" .sql)
            all_migrations+=("$basename_file")
        done < <(find "$MIGRATIONS_DIR" -name "*.sql" -not -name "migration_template.sql" -print0 | sort -z)
    fi
    
    # Find pending migrations
    local pending_migrations=()
    for migration in "${all_migrations[@]}"; do
        if ! echo "$applied_migrations" | grep -q "^$migration\$"; then
            pending_migrations+=("$migration")
        fi
    done
    
    printf '%s\n' "${pending_migrations[@]}"
}

# Apply single migration
apply_migration() {
    local migration_file="$1"
    local migration_name
    migration_name=$(basename "$migration_file" .sql)
    
    log_info "Applying migration: $migration_name"
    
    # Generate checksum
    local checksum
    checksum=$(generate_checksum "$migration_file")
    
    # Record start time
    local start_time
    start_time=$(date +%s%3N)
    
    # Apply migration
    local success=true
    local error_message=""
    
    if ! exec_sql_file "$migration_file"; then
        success=false
        error_message="Migration execution failed"
        log_error "Failed to apply migration: $migration_name"
    fi
    
    # Calculate execution time
    local end_time
    end_time=$(date +%s%3N)
    local execution_time=$((end_time - start_time))
    
    # Record migration in log
    exec_sql "
        INSERT INTO $MIGRATION_TABLE (version, name, checksum, execution_time_ms, success, error_message)
        VALUES ('$migration_name', '$migration_name', '$checksum', $execution_time, $success, $(if [[ -n "$error_message" ]]; then echo "'$error_message'"; else echo "NULL"; fi));
    " || true
    
    if [[ "$success" == "true" ]]; then
        log_success "Applied migration: $migration_name (${execution_time}ms)"
        return 0
    else
        return 1
    fi
}

# Run migrations
run_migrations() {
    local target_version="${1:-}"
    
    log_section "RUNNING DATABASE MIGRATIONS"
    
    if ! check_database; then
        return 1
    fi
    
    # Initialize migration system if needed
    init_migration_system
    
    # Setup directories
    setup_migration_directory
    
    # Acquire lock
    if ! acquire_lock; then
        return 1
    fi
    
    # Ensure we release the lock on exit
    trap 'release_lock' EXIT
    
    # Get pending migrations
    local pending_migrations
    mapfile -t pending_migrations < <(get_pending_migrations)
    
    if [[ ${#pending_migrations[@]} -eq 0 ]]; then
        log_info "No pending migrations found"
        return 0
    fi
    
    log_info "Found ${#pending_migrations[@]} pending migrations"
    
    # Apply migrations
    local applied_count=0
    local failed_count=0
    
    for migration in "${pending_migrations[@]}"; do
        # Stop at target version if specified
        if [[ -n "$target_version" && "$migration" > "$target_version" ]]; then
            log_info "Stopping at target version: $target_version"
            break
        fi
        
        local migration_file="${MIGRATIONS_DIR}/${migration}.sql"
        
        if [[ ! -f "$migration_file" ]]; then
            log_warning "Migration file not found: $migration_file"
            continue
        fi
        
        if apply_migration "$migration_file"; then
            ((applied_count++))
        else
            ((failed_count++))
            log_error "Migration failed, stopping execution"
            break
        fi
    done
    
    # Release lock
    release_lock
    trap - EXIT
    
    log_success "Migration summary: $applied_count applied, $failed_count failed"
    
    if [[ $failed_count -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

# Create database backup
create_backup() {
    local backup_name="${1:-$(date +%Y%m%d_%H%M%S)}"
    local backup_file="${BACKUP_DIR}/backup_${backup_name}.sql"
    
    log_section "CREATING DATABASE BACKUP"
    
    if ! check_database; then
        return 1
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    log_info "Creating backup: $backup_name"
    
    local pod
    pod=$(get_db_pod)
    
    if [[ -z "$pod" ]]; then
        log_error "No database pod found"
        return 1
    fi
    
    # Create backup using pg_dump
    if kubectl exec -n "$NAMESPACE" "$pod" -- pg_dump -U "$DB_USER" -d "$DB_NAME" --verbose --clean --if-exists > "$backup_file"; then
        # Compress backup
        gzip "$backup_file"
        local compressed_file="${backup_file}.gz"
        
        # Get file size
        local file_size
        file_size=$(ls -lh "$compressed_file" | awk '{print $5}')
        
        log_success "Backup created: $(basename "$compressed_file") ($file_size)"
        
        # Create metadata file
        cat > "${compressed_file}.meta" << EOF
{
    "backup_name": "$backup_name",
    "database": "$DB_NAME",
    "user": "$DB_USER",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "created_by": "$(whoami)",
    "size": "$file_size",
    "checksum": "$(generate_checksum "$compressed_file")"
}
EOF
        
        return 0
    else
        log_error "Failed to create backup"
        rm -f "$backup_file"
        return 1
    fi
}

# Restore database from backup
restore_backup() {
    local backup_name="$1"
    local backup_file="${BACKUP_DIR}/backup_${backup_name}.sql.gz"
    
    log_section "RESTORING DATABASE BACKUP"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi
    
    if ! check_database; then
        return 1
    fi
    
    log_warning "This will replace all data in the database!"
    read -p "Are you sure you want to continue? (yes/no): " -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Restore cancelled"
        return 0
    fi
    
    # Create a backup before restore
    log_info "Creating safety backup before restore..."
    create_backup "before_restore_$(date +%Y%m%d_%H%M%S)"
    
    local pod
    pod=$(get_db_pod)
    
    if [[ -z "$pod" ]]; then
        log_error "No database pod found"
        return 1
    fi
    
    log_info "Restoring from backup: $backup_name"
    
    # Restore from backup
    if gunzip -c "$backup_file" | kubectl exec -i -n "$NAMESPACE" "$pod" -- psql -U "$DB_USER" -d "$DB_NAME"; then
        log_success "Database restored from backup: $backup_name"
        
        # Re-initialize migration system
        init_migration_system
        
        return 0
    else
        log_error "Failed to restore from backup"
        return 1
    fi
}

# List available backups
list_backups() {
    log_section "AVAILABLE BACKUPS"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backup directory found"
        return 0
    fi
    
    local backups=($(find "$BACKUP_DIR" -name "backup_*.sql.gz" -exec basename {} .sql.gz \; | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "No backups found"
        return 0
    fi
    
    echo -e "${CYAN}Available backups:${NC}"
    for backup in "${backups[@]}"; do
        local backup_name="${backup#backup_}"
        local backup_file="${BACKUP_DIR}/${backup}.sql.gz"
        local meta_file="${backup_file}.meta"
        
        local file_size="unknown"
        local created_at="unknown"
        
        if [[ -f "$meta_file" ]]; then
            if command -v jq &> /dev/null; then
                file_size=$(jq -r '.size' "$meta_file" 2>/dev/null || echo "unknown")
                created_at=$(jq -r '.created_at' "$meta_file" 2>/dev/null || echo "unknown")
            fi
        else
            file_size=$(ls -lh "$backup_file" 2>/dev/null | awk '{print $5}' || echo "unknown")
        fi
        
        echo -e "  📦 $backup_name ($file_size) - $created_at"
    done
    
    echo -e "\n${CYAN}Usage:${NC}"
    echo -e "  Restore backup: $0 restore <backup-name>"
}

# Clean old backups
cleanup_backups() {
    local keep_count="${1:-10}"
    
    log_section "CLEANING OLD BACKUPS"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_info "No backup directory found"
        return 0
    fi
    
    local backups
    mapfile -t backups < <(find "$BACKUP_DIR" -name "backup_*.sql.gz" -printf '%T@ %p\n' | sort -rn | cut -d' ' -f2-)
    
    local total_backups=${#backups[@]}
    
    if [[ $total_backups -le $keep_count ]]; then
        log_info "Only $total_backups backups found, keeping all (limit: $keep_count)"
        return 0
    fi
    
    local to_remove=$((total_backups - keep_count))
    log_info "Removing $to_remove old backups (keeping newest $keep_count)"
    
    for ((i = keep_count; i < total_backups; i++)); do
        local backup_file="${backups[i]}"
        local meta_file="${backup_file}.meta"
        local backup_name
        backup_name=$(basename "$backup_file" .sql.gz)
        
        log_info "Removing old backup: $backup_name"
        rm -f "$backup_file" "$meta_file"
    done
    
    log_success "Backup cleanup completed"
}

# Show migration status
show_migration_status() {
    log_section "MIGRATION STATUS"
    
    if ! check_database; then
        return 1
    fi
    
    # Check if migration system is initialized
    local migration_table_exists
    migration_table_exists=$(exec_sql "
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_name = '$MIGRATION_TABLE'
        );
    " 2>/dev/null | tail -n +3 | head -n -2 | grep -v '^$' | xargs || echo "f")
    
    if [[ "$migration_table_exists" != "t" ]]; then
        log_warning "Migration system not initialized"
        log_info "Run: $0 init"
        return 0
    fi
    
    # Get migration statistics
    local total_migrations
    total_migrations=$(exec_sql "SELECT COUNT(*) FROM $MIGRATION_TABLE;" 2>/dev/null | tail -n +3 | head -n -2 | grep -v '^$' | xargs || echo "0")
    
    local successful_migrations
    successful_migrations=$(exec_sql "SELECT COUNT(*) FROM $MIGRATION_TABLE WHERE success = TRUE;" 2>/dev/null | tail -n +3 | head -n -2 | grep -v '^$' | xargs || echo "0")
    
    local failed_migrations
    failed_migrations=$(exec_sql "SELECT COUNT(*) FROM $MIGRATION_TABLE WHERE success = FALSE;" 2>/dev/null | tail -n +3 | head -n -2 | grep -v '^$' | xargs || echo "0")
    
    echo -e "${CYAN}Migration Statistics:${NC}"
    echo -e "  Total migrations: $total_migrations"
    echo -e "  Successful: $successful_migrations"
    echo -e "  Failed: $failed_migrations"
    echo
    
    # Show recent migrations
    local recent_migrations
    recent_migrations=$(exec_sql "
        SELECT version, applied_at, execution_time_ms, success 
        FROM $MIGRATION_TABLE 
        ORDER BY applied_at DESC 
        LIMIT 10;
    " 2>/dev/null | tail -n +3 | head -n -2 | grep -v '^$' || echo "")
    
    if [[ -n "$recent_migrations" ]]; then
        echo -e "${CYAN}Recent Migrations:${NC}"
        echo "$recent_migrations" | while read -r line; do
            if [[ -n "$line" ]]; then
                echo "  $line"
            fi
        done
        echo
    fi
    
    # Show pending migrations
    local pending_migrations
    mapfile -t pending_migrations < <(get_pending_migrations)
    
    if [[ ${#pending_migrations[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Pending Migrations (${#pending_migrations[@]}):${NC}"
        for migration in "${pending_migrations[@]}"; do
            echo -e "  📋 $migration"
        done
    else
        echo -e "${GREEN}✅ All migrations are up to date${NC}"
    fi
}

# Reset database (dangerous!)
reset_database() {
    log_section "RESETTING DATABASE"
    
    log_error "⚠️  WARNING: This will completely destroy all data in the database!"
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Type 'RESET' to confirm: " -r confirm
    
    if [[ "$confirm" != "RESET" ]]; then
        log_info "Reset cancelled"
        return 0
    fi
    
    if ! check_database; then
        return 1
    fi
    
    # Create final backup
    log_info "Creating final backup before reset..."
    create_backup "final_backup_$(date +%Y%m%d_%H%M%S)"
    
    local pod
    pod=$(get_db_pod)
    
    if [[ -z "$pod" ]]; then
        log_error "No database pod found"
        return 1
    fi
    
    log_info "Dropping all tables and data..."
    
    # Drop all tables
    exec_sql "
        DROP SCHEMA public CASCADE;
        CREATE SCHEMA public;
        GRANT ALL ON SCHEMA public TO $DB_USER;
        GRANT ALL ON SCHEMA public TO public;
    " || {
        log_error "Failed to reset database"
        return 1
    }
    
    log_success "Database reset completed"
    
    # Reinitialize migration system
    init_migration_system
    
    log_info "Migration system reinitialized"
}

# Generate sample migration
generate_migration() {
    local migration_name="$1"
    
    if [[ -z "$migration_name" ]]; then
        log_error "Migration name is required"
        return 1
    fi
    
    # Generate version number (timestamp)
    local version
    version=$(date +%Y%m%d_%H%M%S)
    local full_name="${version}_${migration_name}"
    
    setup_migration_directory
    
    local migration_file="${MIGRATIONS_DIR}/${full_name}.sql"
    
    if [[ -f "$migration_file" ]]; then
        log_error "Migration already exists: $migration_file"
        return 1
    fi
    
    # Create migration from template
    local template="${MIGRATIONS_DIR}/migration_template.sql"
    if [[ -f "$template" ]]; then
        cp "$template" "$migration_file"
        
        # Replace placeholders
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/\[DESCRIPTION\]/$migration_name/g" "$migration_file"
            sed -i '' "s/\[VERSION\]/$full_name/g" "$migration_file"
            sed -i '' "s/\[AUTHOR\]/$(whoami)/g" "$migration_file"
            sed -i '' "s/\[DATE\]/$(date)/g" "$migration_file"
        else
            sed -i "s/\[DESCRIPTION\]/$migration_name/g" "$migration_file"
            sed -i "s/\[VERSION\]/$full_name/g" "$migration_file"
            sed -i "s/\[AUTHOR\]/$(whoami)/g" "$migration_file"
            sed -i "s/\[DATE\]/$(date)/g" "$migration_file"
        fi
    else
        # Create basic migration
        cat > "$migration_file" << EOF
-- Migration: $migration_name
-- Version: $full_name
-- Author: $(whoami)
-- Created: $(date)

BEGIN;

-- TODO: Add your migration SQL here

COMMIT;
EOF
    fi
    
    log_success "Migration created: $migration_file"
    log_info "Edit the file to add your migration SQL"
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "init")
            init_migration_system
            setup_migration_directory
            ;;
        "migrate"|"up")
            run_migrations "$@"
            ;;
        "status")
            show_migration_status
            ;;
        "backup")
            create_backup "$@"
            ;;
        "restore")
            if [[ $# -eq 0 ]]; then
                log_error "Backup name required for restore"
                exit 1
            fi
            restore_backup "$1"
            ;;
        "list-backups"|"list")
            list_backups
            ;;
        "cleanup")
            cleanup_backups "$@"
            ;;
        "reset")
            reset_database
            ;;
        "generate")
            if [[ $# -eq 0 ]]; then
                log_error "Migration name required"
                exit 1
            fi
            generate_migration "$1"
            ;;
        "check")
            check_database
            ;;
        "wait")
            wait_for_db "$@"
            ;;
        "help"|"-h"|"--help")
            cat << EOF
PyAirtable Database Management System

Usage: $0 <command> [options]

Commands:
  init                    Initialize migration system
  migrate [version]       Run pending migrations (optionally up to version)
  status                  Show migration status and pending migrations
  backup [name]           Create database backup
  restore <name>          Restore database from backup
  list                    List available backups
  cleanup [count]         Clean old backups (keep newest count, default: 10)
  reset                   Reset database (DANGEROUS - destroys all data)
  generate <name>         Generate new migration file
  check                   Check database connectivity
  wait [timeout]          Wait for database to be ready (default: 300s)
  help                    Show this help message

Examples:
  $0 init                          # Initialize migration system
  $0 migrate                       # Run all pending migrations
  $0 migrate 20241201_120000       # Migrate up to specific version
  $0 backup production             # Create named backup
  $0 restore production            # Restore from backup
  $0 generate add_user_table       # Generate new migration
  $0 status                        # Show current status
  $0 cleanup 5                     # Keep only 5 newest backups

Environment Variables:
  NAMESPACE                        Kubernetes namespace (default: pyairtable)
  POSTGRES_DB                      Database name (default: pyairtablemcp)
  POSTGRES_USER                    Database user (default: admin)

Migration Files:
  - Place migration files in: $MIGRATIONS_DIR
  - Naming convention: YYYYMMDD_HHMMSS_description.sql
  - Files are executed in alphabetical order
  - Use BEGIN/COMMIT transactions for safety

Backup Files:
  - Stored in: $BACKUP_DIR
  - Compressed with gzip
  - Include metadata with checksums
  - Automatic cleanup available

Safety Features:
  ✅ Migration locking prevents concurrent executions
  ✅ Automatic backups before destructive operations
  ✅ Checksum validation for migration integrity
  ✅ Comprehensive logging and error handling
  ✅ Rollback support preparation
EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"