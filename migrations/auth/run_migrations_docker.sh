#!/bin/bash

# Docker-based Migration Runner Script for PyAirtable Authentication Schema
# This script applies database migrations to PostgreSQL via Docker Compose
# Usage: ./run_migrations_docker.sh [up|down] [migration_number]

set -e  # Exit on any error

# Docker Compose configuration
COMPOSE_FILE="${COMPOSE_FILE:-../docker-compose.minimal.yml}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_CONTAINER=""

# Database connection parameters (from docker-compose environment)
DB_NAME="${POSTGRES_DB:-pyairtable}"
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-postgres}"

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

# Function to get PostgreSQL container name
get_postgres_container() {
    if [ -z "$POSTGRES_CONTAINER" ]; then
        POSTGRES_CONTAINER=$(docker ps --format "table {{.Names}}" | grep postgres | head -1 || echo "")
        
        if [ -z "$POSTGRES_CONTAINER" ]; then
            # Try with compose project name
            local compose_dir=$(dirname "$COMPOSE_FILE")
            local project_name=$(basename "$compose_dir")
            POSTGRES_CONTAINER="${project_name}-postgres-1"
            
            # Check if this container exists
            if ! docker ps -q -f name="$POSTGRES_CONTAINER" > /dev/null; then
                POSTGRES_CONTAINER=""
            fi
        fi
    fi
    
    echo "$POSTGRES_CONTAINER"
}

# Function to check PostgreSQL container is running
check_postgres_container() {
    local container=$(get_postgres_container)
    
    if [ -z "$container" ]; then
        print_error "PostgreSQL container not found. Please start with:"
        echo "  docker-compose -f $COMPOSE_FILE up -d postgres"
        return 1
    fi
    
    if ! docker ps -q -f name="$container" > /dev/null; then
        print_error "PostgreSQL container '$container' is not running"
        return 1
    fi
    
    print_success "Found running PostgreSQL container: $container"
    POSTGRES_CONTAINER="$container"
    return 0
}

# Function to execute SQL in PostgreSQL container
exec_sql() {
    local sql="$1"
    local container="$POSTGRES_CONTAINER"
    
    docker exec -i "$container" psql -U "$DB_USER" -d "$DB_NAME" << EOF
$sql
EOF
}

# Function to execute SQL file in PostgreSQL container
exec_sql_file() {
    local file_path="$1"
    local container="$POSTGRES_CONTAINER"
    
    if [ ! -f "$file_path" ]; then
        print_error "SQL file not found: $file_path"
        return 1
    fi
    
    docker exec -i "$container" psql -U "$DB_USER" -d "$DB_NAME" < "$file_path"
}

# Function to create migration log table if it doesn't exist
create_migration_log_table() {
    print_status "Creating migration log table if not exists..."
    
    exec_sql "
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
    
    local count=$(exec_sql "SELECT COUNT(*) FROM migration_log WHERE version = '$version';" 2>/dev/null | tail -1 | xargs || echo "0")
    
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
    
    # Execute migration with better error handling
    if exec_sql_file "$actual_file" > /tmp/migration_output.log 2>&1; then
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
    
    echo "Applied migrations:"
    exec_sql "
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
    echo "PyAirtable Authentication Migration Runner (Docker)"
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
    echo "  COMPOSE_FILE     Docker Compose file (default: ../docker-compose.minimal.yml)"
    echo "  POSTGRES_SERVICE PostgreSQL service name (default: postgres)"
    echo "  POSTGRES_DB      Database name (default: pyairtable)"
    echo "  POSTGRES_USER    Database user (default: postgres)"
    echo "  POSTGRES_PASSWORD Database password (default: postgres)"
    echo
    echo "Examples:"
    echo "  $0 up            # Apply all pending migrations"
    echo "  $0 up 001        # Apply specific migration"
    echo "  $0 down 002      # Rollback specific migration"
    echo "  $0 status        # Show migration status"
    echo
    echo "Prerequisites:"
    echo "  Start PostgreSQL with: docker-compose -f $COMPOSE_FILE up -d postgres"
}

# Main script logic
main() {
    local command="${1:-help}"
    local version="${2:-}"
    
    case "$command" in
        "up")
            if ! check_postgres_container; then
                exit 1
            fi
            
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
            if ! check_postgres_container; then
                exit 1
            fi
            
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
            if ! check_postgres_container; then
                exit 1
            fi
            
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