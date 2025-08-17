#!/bin/bash
# Database Migration Runner for PyAirtable Performance Optimization
# Created: 2025-08-11
# Purpose: Apply all database performance optimizations safely

set -euo pipefail

# Configuration
DB_HOST=${POSTGRES_HOST:-localhost}
DB_PORT=${POSTGRES_PORT:-5432}
DB_NAME=${POSTGRES_DB:-pyairtable}
DB_USER=${POSTGRES_USER:-postgres}
DB_PASSWORD=${POSTGRES_PASSWORD}
MIGRATION_DIR="/docker-entrypoint-initdb.d/migrations"

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to wait for database
wait_for_db() {
    log_info "Waiting for PostgreSQL to be ready..."
    local retries=30
    local count=0
    
    while [ $count -lt $retries ]; do
        if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; then
            log_success "PostgreSQL is ready!"
            return 0
        fi
        
        count=$((count + 1))
        log_info "Attempt $count/$retries - waiting 2 seconds..."
        sleep 2
    done
    
    log_error "PostgreSQL did not become ready within $((retries * 2)) seconds"
    return 1
}

# Function to create migration log table
create_migration_table() {
    log_info "Creating migration tracking table..."
    PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        CREATE TABLE IF NOT EXISTS migration_history (
            id SERIAL PRIMARY KEY,
            migration_name VARCHAR(255) UNIQUE NOT NULL,
            applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            checksum VARCHAR(64),
            execution_time_ms INTEGER,
            success BOOLEAN DEFAULT TRUE
        );
        CREATE INDEX IF NOT EXISTS idx_migration_history_name ON migration_history(migration_name);
    " >/dev/null
    log_success "Migration tracking table ready"
}

# Function to calculate file checksum
calculate_checksum() {
    local file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        md5sum "$file" | cut -d' ' -f1
    fi
}

# Function to check if migration was already applied
is_migration_applied() {
    local migration_name=$1
    local checksum=$2
    
    local result=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM migration_history 
        WHERE migration_name = '$migration_name' AND checksum = '$checksum' AND success = TRUE;
    " 2>/dev/null | xargs)
    
    [ "$result" = "1" ]
}

# Function to apply a migration
apply_migration() {
    local migration_file=$1
    local migration_name=$(basename "$migration_file")
    local checksum=$(calculate_checksum "$migration_file")
    local start_time=$(date +%s%3N)
    
    log_info "Applying migration: $migration_name"
    
    # Check if already applied
    if is_migration_applied "$migration_name" "$checksum"; then
        log_success "Migration $migration_name already applied (checksum matches)"
        return 0
    fi
    
    # Apply migration with transaction
    if PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$migration_file" -v ON_ERROR_STOP=1 >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        local execution_time=$((end_time - start_time))
        
        # Record successful migration
        PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            INSERT INTO migration_history (migration_name, checksum, execution_time_ms, success)
            VALUES ('$migration_name', '$checksum', $execution_time, TRUE)
            ON CONFLICT (migration_name) DO UPDATE SET
                checksum = EXCLUDED.checksum,
                applied_at = CURRENT_TIMESTAMP,
                execution_time_ms = EXCLUDED.execution_time_ms,
                success = EXCLUDED.success;
        " >/dev/null
        
        log_success "Migration $migration_name applied successfully (${execution_time}ms)"
        return 0
    else
        # Record failed migration
        PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            INSERT INTO migration_history (migration_name, checksum, success)
            VALUES ('$migration_name', '$checksum', FALSE)
            ON CONFLICT (migration_name) DO UPDATE SET
                checksum = EXCLUDED.checksum,
                applied_at = CURRENT_TIMESTAMP,
                success = EXCLUDED.success;
        " >/dev/null 2>&1 || true
        
        log_error "Migration $migration_name failed"
        return 1
    fi
}

# Function to validate database performance
validate_performance() {
    log_info "Validating database performance optimizations..."
    
    # Check if extensions are loaded
    local extensions=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT string_agg(extname, ', ') FROM pg_extension WHERE extname IN ('uuid-ossp', 'pg_trgm', 'btree_gin', 'pg_stat_statements');
    " | xargs)
    
    if [[ "$extensions" =~ "uuid-ossp" ]] && [[ "$extensions" =~ "pg_trgm" ]] && [[ "$extensions" =~ "btree_gin" ]]; then
        log_success "Required extensions are loaded: $extensions"
    else
        log_warning "Some extensions may not be loaded: $extensions"
    fi
    
    # Check index count
    local index_count=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public';
    " | xargs)
    
    log_success "Created $index_count indexes for performance optimization"
    
    # Check if monitoring views exist
    local view_count=$(PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM information_schema.views 
        WHERE table_schema = 'public' 
        AND table_name IN ('slow_queries', 'table_stats', 'index_usage', 'user_activity_stats', 'user_dashboard', 'tenant_admin_dashboard', 'system_health_monitor');
    " | xargs)
    
    if [ "$view_count" -ge "7" ]; then
        log_success "Performance monitoring views are available ($view_count views created)"
    else
        log_warning "Some performance monitoring views may be missing ($view_count of 7 expected)"
    fi
}

# Function to run performance analysis
run_performance_analysis() {
    log_info "Running initial performance analysis..."
    
    # Get table sizes
    PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            schemaname,
            tablename,
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
            pg_total_relation_size(schemaname||'.'||tablename) as bytes
        FROM pg_stat_user_tables 
        ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC 
        LIMIT 10;
    " 2>/dev/null && log_success "Table size analysis complete" || log_warning "Could not analyze table sizes"
    
    # Check for slow queries (if pg_stat_statements is available)
    PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 'pg_stat_statements loaded' as status WHERE EXISTS (
            SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
        );
    " 2>/dev/null && log_success "pg_stat_statements is ready for query analysis" || log_warning "pg_stat_statements not available"
}

# Main migration execution
main() {
    log_info "Starting PyAirtable database performance optimization"
    log_info "Target: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
    
    # Wait for database
    if ! wait_for_db; then
        exit 1
    fi
    
    # Create migration tracking
    create_migration_table
    
    # Apply migrations in order
    local migration_files=(
        "$MIGRATION_DIR/001_create_session_tables.sql"
        "$MIGRATION_DIR/002_create_performance_indexes.sql"
        "$MIGRATION_DIR/003_performance_monitoring.sql"
        "$MIGRATION_DIR/004_create_workspace_tables.sql"
        "$MIGRATION_DIR/005_advanced_performance_optimization.sql"
        "$MIGRATION_DIR/006_advanced_views_and_functions.sql"
        "$MIGRATION_DIR/007_connection_pooling_and_monitoring.sql"
    )
    
    local total_migrations=${#migration_files[@]}
    local applied_count=0
    local failed_count=0
    
    for migration_file in "${migration_files[@]}"; do
        if [ -f "$migration_file" ]; then
            if apply_migration "$migration_file"; then
                applied_count=$((applied_count + 1))
            else
                failed_count=$((failed_count + 1))
                log_error "Migration failed: $(basename "$migration_file")"
                # Continue with other migrations instead of exiting
            fi
        else
            log_warning "Migration file not found: $migration_file"
        fi
    done
    
    # Validate and analyze
    validate_performance
    run_performance_analysis
    
    # Summary
    log_info "Migration Summary:"
    log_info "  Total migrations: $total_migrations"
    log_success "  Successfully applied: $applied_count"
    if [ $failed_count -gt 0 ]; then
        log_error "  Failed: $failed_count"
    fi
    
    if [ $failed_count -eq 0 ]; then
        log_success "All database performance optimizations applied successfully!"
        
        # Show optimization tips
        echo ""
        log_info "Performance Optimization Tips:"
        echo "  1. Monitor slow queries with: SELECT * FROM slow_queries;"
        echo "  2. Check table statistics with: SELECT * FROM table_stats;"
        echo "  3. Review index usage with: SELECT * FROM index_usage;"
        echo "  4. Monitor user activity with: SELECT * FROM user_dashboard LIMIT 10;"
        echo "  5. Check system health with: SELECT * FROM perform_health_check();"
        echo "  6. Monitor connections with: SELECT * FROM monitor_connection_pool();"
        echo "  7. Run cleanup with: SELECT * FROM cleanup_user_sessions();"
        echo "  8. Refresh analytics with: SELECT refresh_analytics_views();"
        echo "  9. Get health summary with: SELECT * FROM get_health_summary();"
        echo ""
        
        exit 0
    else
        log_error "Some migrations failed. Please check the logs and retry."
        exit 1
    fi
}

# Execute main function
main "$@"