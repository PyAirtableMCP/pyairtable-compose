#!/bin/bash

# Migration Runner Script for PyAirtable Authentication Schema
# This script applies database migrations to PostgreSQL on port 5433
# Usage: ./run_migrations.sh [up|down] [migration_number]

set -e  # Exit on any error

# Database connection parameters
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5433}"
DB_NAME="${DB_NAME:-pyairtable}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check database connectivity
check_db_connection() {
    print_status "Checking database connection..."
    
    if ! command -v psql &> /dev/null; then
        print_error "psql client not found. Please install PostgreSQL client tools."
        exit 1
    fi
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
        print_success "Database connection successful"
    else
        print_error "Cannot connect to database. Please check connection parameters:"
        echo "  Host: $DB_HOST"
        echo "  Port: $DB_PORT"
        echo "  Database: $DB_NAME"
        echo "  User: $DB_USER"
        exit 1
    fi
}

# Function to create migration log table if it doesn't exist
create_migration_log_table() {
    print_status "Creating migration log table if not exists..."
    
    export PGPASSWORD="$DB_PASSWORD"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        CREATE TABLE IF NOT EXISTS migration_log (
            version VARCHAR(10) PRIMARY KEY,
            description TEXT NOT NULL,
            applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE INDEX IF NOT EXISTS idx_migration_log_applied_at ON migration_log(applied_at DESC);
        
        COMMENT ON TABLE migration_log IS 'Track applied database migrations';
    " > /dev/null
    
    print_success "Migration log table ready"
}

# Function to check if migration has been applied
is_migration_applied() {
    local version="$1"
    export PGPASSWORD="$DB_PASSWORD"
    
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM migration_log WHERE version = '$version';
    " 2>/dev/null | xargs)
    
    [ "$count" = "1" ]
}

# Function to apply a single migration
apply_migration() {
    local direction="$1"  # up or down
    local version="$2"    # migration number (e.g., 001)
    
    local migration_file="${SCRIPT_DIR}/${version}_*.${direction}.sql"
    local actual_file=$(ls $migration_file 2>/dev/null | head -1)
    
    if [ ! -f "$actual_file" ]; then
        print_error "Migration file not found: $migration_file"
        return 1
    fi
    
    local filename=$(basename "$actual_file")
    
    if [ "$direction" = "up" ]; then
        if is_migration_applied "$version"; then
            print_warning "Migration $version already applied, skipping"
            return 0
        fi
        print_status "Applying migration: $filename"
    else
        if ! is_migration_applied "$version"; then
            print_warning "Migration $version not applied, skipping rollback"
            return 0
        fi
        print_status "Rolling back migration: $filename"
    fi
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Execute migration with better error handling
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$actual_file" > /tmp/migration_output.log 2>&1; then
        if [ "$direction" = "up" ]; then
            print_success "Applied migration: $filename"
        else
            print_success "Rolled back migration: $filename"
        fi
        
        # Show any notices or warnings from the output
        if grep -i "warning\|notice" /tmp/migration_output.log > /dev/null 2>&1; then
            print_warning "Migration notices/warnings:"
            grep -i "warning\|notice" /tmp/migration_output.log || true
        fi
    else
        print_error "Failed to apply migration: $filename"
        echo "Error details:"
        cat /tmp/migration_output.log
        return 1
    fi
    
    rm -f /tmp/migration_output.log
    return 0
}

# Function to list available migrations
list_migrations() {
    print_status "Available migrations in $SCRIPT_DIR:"
    echo
    
    for file in "$SCRIPT_DIR"/*.up.sql; do
        if [ -f "$file" ]; then
            local basename=$(basename "$file" .up.sql)
            local version=$(echo "$basename" | cut -d'_' -f1)
            local description=$(echo "$basename" | cut -d'_' -f2- | tr '_' ' ')
            
            if is_migration_applied "$version"; then
                echo "  ✓ $version - $description (applied)"
            else
                echo "  ⭘ $version - $description (pending)"
            fi
        fi
    done
    echo
}

# Function to show migration status
show_status() {
    print_status "Migration Status:"
    echo
    
    export PGPASSWORD="$DB_PASSWORD"
    
    echo "Applied migrations:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            version,
            description,
            applied_at
        FROM migration_log 
        ORDER BY version;
    " 2>/dev/null || print_warning "No migrations applied yet"
    
    echo
    list_migrations
}

# Function to apply all pending migrations
apply_all_migrations() {
    local direction="${1:-up}"
    
    if [ "$direction" = "down" ]; then
        print_warning "Rolling back all migrations - this will destroy data!"
        read -p "Are you sure? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_status "Rollback cancelled"
            exit 0
        fi
        
        # Rollback in reverse order
        for version in 004 003 002 001; do
            if is_migration_applied "$version"; then
                apply_migration "down" "$version"
            fi
        done
    else
        # Apply in order
        for version in 001 002 003 004; do
            apply_migration "up" "$version"
        done
    fi
}

# Function to show help
show_help() {
    echo "PyAirtable Authentication Migration Runner"
    echo
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  up [VERSION]     Apply migration(s) - all if no version specified"
    echo "  down [VERSION]   Rollback migration(s) - all if no version specified"
    echo "  status           Show migration status"
    echo "  list             List available migrations"
    echo "  help             Show this help message"
    echo
    echo "Environment Variables:"
    echo "  DB_HOST          Database host (default: localhost)"
    echo "  DB_PORT          Database port (default: 5433)"
    echo "  DB_NAME          Database name (default: pyairtable)"
    echo "  DB_USER          Database user (default: postgres)"
    echo "  DB_PASSWORD      Database password (default: postgres)"
    echo
    echo "Examples:"
    echo "  $0 up            # Apply all pending migrations"
    echo "  $0 up 001        # Apply specific migration"
    echo "  $0 down 002      # Rollback specific migration"
    echo "  $0 status        # Show migration status"
    echo
    echo "Database Connection:"
    echo "  Host: $DB_HOST"
    echo "  Port: $DB_PORT"
    echo "  Database: $DB_NAME"
    echo "  User: $DB_USER"
}

# Main script logic
main() {
    local command="${1:-help}"
    local version="${2:-}"
    
    case "$command" in
        "up")
            check_db_connection
            create_migration_log_table
            
            if [ -n "$version" ]; then
                apply_migration "up" "$version"
            else
                apply_all_migrations "up"
            fi
            
            print_success "Migration operation completed"
            show_status
            ;;
            
        "down")
            check_db_connection
            create_migration_log_table
            
            if [ -n "$version" ]; then
                apply_migration "down" "$version"
            else
                apply_all_migrations "down"
            fi
            
            print_success "Rollback operation completed"
            show_status
            ;;
            
        "status")
            check_db_connection
            create_migration_log_table
            show_status
            ;;
            
        "list")
            list_migrations
            ;;
            
        "help"|"-h"|"--help")
            show_help
            ;;
            
        *)
            print_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"