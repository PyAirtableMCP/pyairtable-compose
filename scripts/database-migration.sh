#!/bin/bash

# PyAirtable Database Migration Manager
# Handles database schema migrations with rollback capabilities
# Supports both development and production migration strategies

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="pyairtable"
POSTGRES_POD=""
DATABASE_NAME="pyairtable"
DATABASE_USER="postgres"
MIGRATION_DIR="/docker-entrypoint-initdb.d/migrations"
BACKUP_DIR="/tmp/db-backups"
MAX_PARALLEL_MIGRATIONS=3

# Migration metadata
MIGRATION_TABLE="migration_log"
MIGRATION_LOCK_TABLE="migration_lock"

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Get PostgreSQL pod name
get_postgres_pod() {
    POSTGRES_POD=$(kubectl get pods -l app.kubernetes.io/name=postgres -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$POSTGRES_POD" ]; then
        print_error "PostgreSQL pod not found in namespace $NAMESPACE"
        return 1
    fi
    
    print_info "Using PostgreSQL pod: $POSTGRES_POD"
    return 0
}

# Execute SQL command
execute_sql() {
    local sql_command="$1"
    local database="${2:-$DATABASE_NAME}"
    
    kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U "$DATABASE_USER" -d "$database" -c "$sql_command"
}

# Execute SQL file
execute_sql_file() {
    local sql_file="$1"
    local database="${2:-$DATABASE_NAME}"
    
    kubectl exec -i "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U "$DATABASE_USER" -d "$database" < "$sql_file"
}

# Check if database exists
database_exists() {
    local db_name="$1"
    local result
    result=$(kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U "$DATABASE_USER" -d postgres -t -c "SELECT 1 FROM pg_database WHERE datname='$db_name';" 2>/dev/null | xargs || echo "")
    [ "$result" = "1" ]
}

# Create database if it doesn't exist
create_database() {
    local db_name="$1"
    
    if database_exists "$db_name"; then
        print_info "Database $db_name already exists"
        return 0
    fi
    
    print_info "Creating database: $db_name"
    kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U "$DATABASE_USER" -d postgres -c "CREATE DATABASE $db_name;"
    
    print_success "Database $db_name created"
}

# Initialize migration system
init_migration_system() {
    print_header "Initializing Migration System"
    
    # Create migration log table
    local migration_table_sql="
    CREATE TABLE IF NOT EXISTS $MIGRATION_TABLE (
        id SERIAL PRIMARY KEY,
        migration_name VARCHAR(255) UNIQUE NOT NULL,
        applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        rollback_sql TEXT,
        checksum VARCHAR(64),
        execution_time_ms INTEGER,
        status VARCHAR(20) DEFAULT 'applied',
        error_message TEXT,
        applied_by VARCHAR(100) DEFAULT 'migration-script'
    );
    
    CREATE INDEX IF NOT EXISTS idx_migration_log_name ON $MIGRATION_TABLE (migration_name);
    CREATE INDEX IF NOT EXISTS idx_migration_log_applied_at ON $MIGRATION_TABLE (applied_at);
    "
    
    # Create migration lock table for concurrent protection
    local lock_table_sql="
    CREATE TABLE IF NOT EXISTS $MIGRATION_LOCK_TABLE (
        lock_name VARCHAR(255) PRIMARY KEY,
        locked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        locked_by VARCHAR(100),
        expires_at TIMESTAMP
    );
    "
    
    if execute_sql "$migration_table_sql" && execute_sql "$lock_table_sql"; then
        print_success "Migration system initialized"
        return 0
    else
        print_error "Failed to initialize migration system"
        return 1
    fi
}

# Acquire migration lock
acquire_lock() {
    local lock_name="${1:-default}"
    local lock_duration="${2:-3600}"  # 1 hour default
    local locked_by="${3:-migration-script}"
    
    print_info "Acquiring migration lock: $lock_name"
    
    # Clean up expired locks first
    execute_sql "DELETE FROM $MIGRATION_LOCK_TABLE WHERE expires_at < NOW();" >/dev/null
    
    # Try to acquire lock
    local lock_sql="
    INSERT INTO $MIGRATION_LOCK_TABLE (lock_name, locked_by, expires_at)
    VALUES ('$lock_name', '$locked_by', NOW() + INTERVAL '$lock_duration seconds')
    ON CONFLICT (lock_name) DO NOTHING;
    "
    
    local rows_affected
    rows_affected=$(execute_sql "$lock_sql" | grep "INSERT" | cut -d' ' -f3 || echo "0")
    
    if [ "$rows_affected" = "1" ]; then
        print_success "Migration lock acquired: $lock_name"
        return 0
    else
        print_error "Failed to acquire migration lock (another migration may be running)"
        return 1
    fi
}

# Release migration lock
release_lock() {
    local lock_name="${1:-default}"
    
    print_info "Releasing migration lock: $lock_name"
    execute_sql "DELETE FROM $MIGRATION_LOCK_TABLE WHERE lock_name = '$lock_name';" >/dev/null
    print_success "Migration lock released: $lock_name"
}

# Calculate file checksum
calculate_checksum() {
    local file_path="$1"
    if command -v sha256sum >/dev/null; then
        sha256sum "$file_path" | cut -d' ' -f1
    elif command -v shasum >/dev/null; then
        shasum -a 256 "$file_path" | cut -d' ' -f1
    else
        # Fallback to a simple hash
        wc -c < "$file_path"
    fi
}

# Check if migration has been applied
is_migration_applied() {
    local migration_name="$1"
    local result
    result=$(execute_sql "SELECT COUNT(*) FROM $MIGRATION_TABLE WHERE migration_name = '$migration_name' AND status = 'applied';" | tail -1 | xargs)
    [ "$result" -gt 0 ]
}

# Get migration info
get_migration_info() {
    local migration_name="$1"
    execute_sql "SELECT migration_name, applied_at, status, error_message FROM $MIGRATION_TABLE WHERE migration_name = '$migration_name';"
}

# Apply single migration
apply_migration() {
    local migration_file="$1"
    local migration_name
    migration_name=$(basename "$migration_file" .sql)
    
    print_info "Applying migration: $migration_name"
    
    # Check if already applied
    if is_migration_applied "$migration_name"; then
        print_info "Migration $migration_name already applied, skipping"
        return 0
    fi
    
    # Calculate checksum
    local checksum
    checksum=$(calculate_checksum "$migration_file")
    
    # Record start time
    local start_time=$(date +%s%3N)
    
    # Apply migration with error handling
    local migration_status="applied"
    local error_message=""
    
    if ! execute_sql_file "$migration_file"; then
        migration_status="failed"
        error_message="Migration execution failed"
        print_error "Failed to apply migration: $migration_name"
    else
        print_success "Migration applied: $migration_name"
    fi
    
    # Record end time and calculate duration
    local end_time=$(date +%s%3N)
    local execution_time=$((end_time - start_time))
    
    # Log migration
    local log_sql="
    INSERT INTO $MIGRATION_TABLE (migration_name, checksum, execution_time_ms, status, error_message)
    VALUES ('$migration_name', '$checksum', $execution_time, '$migration_status', '$error_message')
    ON CONFLICT (migration_name) DO UPDATE SET
        checksum = EXCLUDED.checksum,
        execution_time_ms = EXCLUDED.execution_time_ms,
        status = EXCLUDED.status,
        error_message = EXCLUDED.error_message,
        applied_at = CURRENT_TIMESTAMP;
    "
    
    execute_sql "$log_sql" >/dev/null
    
    if [ "$migration_status" = "failed" ]; then
        return 1
    fi
    
    return 0
}

# Create database backup
create_backup() {
    local backup_name="${1:-migration-backup-$(date +%Y%m%d-%H%M%S)}"
    local backup_file="$BACKUP_DIR/$backup_name.sql"
    
    print_info "Creating database backup: $backup_name"
    
    # Create backup directory in pod
    kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- mkdir -p "$BACKUP_DIR"
    
    # Create backup
    if kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        pg_dump -U "$DATABASE_USER" -d "$DATABASE_NAME" -f "$backup_file"; then
        print_success "Backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        print_error "Failed to create backup"
        return 1
    fi
}

# Restore from backup
restore_backup() {
    local backup_file="$1"
    
    print_warning "Restoring from backup: $backup_file"
    print_warning "This will DROP and recreate the database!"
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Restore cancelled"
        return 0
    fi
    
    # Drop and recreate database
    kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U "$DATABASE_USER" -d postgres -c "DROP DATABASE IF EXISTS $DATABASE_NAME;"
    
    create_database "$DATABASE_NAME"
    
    # Restore from backup
    if kubectl exec "$POSTGRES_POD" -n "$NAMESPACE" -- \
        psql -U "$DATABASE_USER" -d "$DATABASE_NAME" -f "$backup_file"; then
        print_success "Database restored from backup"
        return 0
    else
        print_error "Failed to restore from backup"
        return 1
    fi
}

# Run migrations
run_migrations() {
    local migration_pattern="${1:-*.sql}"
    local dry_run="${2:-false}"
    
    print_header "Running Database Migrations"
    
    if [ "$dry_run" = "true" ]; then
        print_info "DRY RUN MODE - No changes will be made"
    fi
    
    # Find migration files
    local migration_files=()
    if [ -d "../migrations" ]; then
        while IFS= read -r -d '' file; do
            migration_files+=("$file")
        done < <(find "../migrations" -name "$migration_pattern" -type f -print0 | sort -z)
    fi
    
    if [ ${#migration_files[@]} -eq 0 ]; then
        print_warning "No migration files found matching pattern: $migration_pattern"
        return 0
    fi
    
    print_info "Found ${#migration_files[@]} migration files"
    
    # Create backup before migrations
    local backup_file=""
    if [ "$dry_run" = "false" ]; then
        backup_file=$(create_backup "pre-migration-$(date +%Y%m%d-%H%M%S)")
        if [ $? -ne 0 ]; then
            print_error "Failed to create backup, aborting migrations"
            return 1
        fi
    fi
    
    # Apply migrations
    local applied_count=0
    local failed_count=0
    
    for migration_file in "${migration_files[@]}"; do
        local migration_name
        migration_name=$(basename "$migration_file" .sql)
        
        if [ "$dry_run" = "true" ]; then
            if is_migration_applied "$migration_name"; then
                print_info "DRY RUN: $migration_name (already applied)"
            else
                print_info "DRY RUN: $migration_name (would be applied)"
                ((applied_count++))
            fi
        else
            if apply_migration "$migration_file"; then
                ((applied_count++))
            else
                ((failed_count++))
                break  # Stop on first failure
            fi
        fi
    done
    
    # Report results
    print_header "Migration Results"
    echo "Applied: $applied_count"
    echo "Failed: $failed_count"
    echo "Total: ${#migration_files[@]}"
    
    if [ $failed_count -gt 0 ]; then
        print_error "Migrations failed!"
        if [ -n "$backup_file" ]; then
            print_info "Backup available at: $backup_file"
            print_info "To restore: $0 --restore-backup $backup_file"
        fi
        return 1
    else
        print_success "All migrations completed successfully!"
        return 0
    fi
}

# Show migration status
show_status() {
    print_header "Migration Status"
    
    # Show applied migrations
    echo "Applied Migrations:"
    echo "=================="
    execute_sql "
    SELECT 
        migration_name,
        applied_at,
        execution_time_ms || 'ms' as duration,
        status
    FROM $MIGRATION_TABLE 
    ORDER BY applied_at DESC 
    LIMIT 20;
    "
    
    echo ""
    
    # Show pending migrations
    echo "Available Migration Files:"
    echo "========================="
    if [ -d "../migrations" ]; then
        find "../migrations" -name "*.sql" -type f | sort | while read -r file; do
            local migration_name
            migration_name=$(basename "$file" .sql)
            local status="PENDING"
            
            if is_migration_applied "$migration_name"; then
                status="APPLIED"
            fi
            
            echo "$migration_name: $status"
        done
    else
        echo "No migrations directory found"
    fi
}

# Rollback migration (if rollback SQL is available)
rollback_migration() {
    local migration_name="$1"
    
    print_header "Rolling Back Migration: $migration_name"
    
    if ! is_migration_applied "$migration_name"; then
        print_error "Migration $migration_name is not applied"
        return 1
    fi
    
    # Get rollback SQL
    local rollback_sql
    rollback_sql=$(execute_sql "SELECT rollback_sql FROM $MIGRATION_TABLE WHERE migration_name = '$migration_name';" | tail -1)
    
    if [ -z "$rollback_sql" ] || [ "$rollback_sql" = "(null)" ]; then
        print_error "No rollback SQL available for migration: $migration_name"
        return 1
    fi
    
    print_warning "This will execute rollback SQL for: $migration_name"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Rollback cancelled"
        return 0
    fi
    
    # Execute rollback
    if execute_sql "$rollback_sql"; then
        # Mark as rolled back
        execute_sql "UPDATE $MIGRATION_TABLE SET status = 'rolled_back' WHERE migration_name = '$migration_name';" >/dev/null
        print_success "Migration rolled back: $migration_name"
        return 0
    else
        print_error "Failed to rollback migration: $migration_name"
        return 1
    fi
}

# Validate database state
validate_database() {
    print_header "Database Validation"
    
    local checks_passed=0
    local total_checks=0
    
    # Check 1: Database connectivity
    ((total_checks++))
    if execute_sql "SELECT 1;" >/dev/null 2>&1; then
        print_success "Database connectivity OK"
        ((checks_passed++))
    else
        print_error "Database connectivity failed"
    fi
    
    # Check 2: Migration system tables exist
    ((total_checks++))
    if execute_sql "SELECT 1 FROM $MIGRATION_TABLE LIMIT 1;" >/dev/null 2>&1; then
        print_success "Migration system tables exist"
        ((checks_passed++))
    else
        print_error "Migration system tables missing"
    fi
    
    # Check 3: No failed migrations
    ((total_checks++))
    local failed_migrations
    failed_migrations=$(execute_sql "SELECT COUNT(*) FROM $MIGRATION_TABLE WHERE status = 'failed';" | tail -1 | xargs)
    if [ "$failed_migrations" -eq 0 ]; then
        print_success "No failed migrations"
        ((checks_passed++))
    else
        print_error "$failed_migrations failed migrations found"
    fi
    
    # Check 4: Database schema integrity
    ((total_checks++))
    if execute_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" >/dev/null 2>&1; then
        print_success "Database schema accessible"
        ((checks_passed++))
    else
        print_error "Database schema integrity issues"
    fi
    
    echo ""
    echo "Validation Results: $checks_passed/$total_checks checks passed"
    
    if [ $checks_passed -eq $total_checks ]; then
        print_success "Database validation passed"
        return 0
    else
        print_error "Database validation failed"
        return 1
    fi
}

# Main function
main() {
    local action="run"
    local migration_pattern="*.sql"
    local dry_run=false
    local backup_file=""
    local migration_name=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --run-migrations)
                action="run"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --validate)
                action="validate"
                shift
                ;;
            --init)
                action="init"
                shift
                ;;
            --backup)
                action="backup"
                shift
                ;;
            --restore-backup)
                action="restore"
                backup_file="$2"
                shift 2
                ;;
            --rollback)
                action="rollback"
                migration_name="$2"
                shift 2
                ;;
            --pattern)
                migration_pattern="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --namespace|-n)
                NAMESPACE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [ACTION]"
                echo ""
                echo "Actions:"
                echo "  --run-migrations   Run pending migrations (default)"
                echo "  --status          Show migration status"
                echo "  --validate        Validate database state"
                echo "  --init            Initialize migration system"
                echo "  --backup          Create database backup"
                echo "  --restore-backup  Restore from backup file"
                echo "  --rollback        Rollback specific migration"
                echo ""
                echo "Options:"
                echo "  --pattern PATTERN  Migration file pattern (default: *.sql)"
                echo "  --dry-run         Show what would be done without executing"
                echo "  --namespace, -n   Target namespace (default: pyairtable)"
                echo "  --help, -h        Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Get PostgreSQL pod
    if ! get_postgres_pod; then
        exit 1
    fi
    
    # Ensure database exists
    create_database "$DATABASE_NAME"
    
    # Execute action
    case $action in
        "init")
            init_migration_system
            ;;
        "run")
            if ! init_migration_system; then
                exit 1
            fi
            
            if acquire_lock "migration" 1800; then  # 30 minute lock
                run_migrations "$migration_pattern" "$dry_run"
                local result=$?
                release_lock "migration"
                exit $result
            else
                exit 1
            fi
            ;;
        "status")
            init_migration_system >/dev/null 2>&1 || true
            show_status
            ;;
        "validate")
            validate_database
            ;;
        "backup")
            create_backup
            ;;
        "restore")
            if [ -z "$backup_file" ]; then
                print_error "Backup file path required for restore"
                exit 1
            fi
            restore_backup "$backup_file"
            ;;
        "rollback")
            if [ -z "$migration_name" ]; then
                print_error "Migration name required for rollback"
                exit 1
            fi
            rollback_migration "$migration_name"
            ;;
        *)
            print_error "Unknown action: $action"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'print_error "Interrupted by user"; release_lock "migration" 2>/dev/null || true; exit 130' INT TERM

# Execute main function
main "$@"