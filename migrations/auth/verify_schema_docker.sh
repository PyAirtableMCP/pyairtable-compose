#!/bin/bash

# Docker-based Database Schema Verification Script
# Usage: ./verify_schema_docker.sh [--detailed]

set -e

# Docker Compose configuration
COMPOSE_FILE="${COMPOSE_FILE:-../docker-compose.minimal.yml}"
POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_CONTAINER=""

# Database connection parameters
DB_NAME="${POSTGRES_DB:-pyairtable}"
DB_USER="${POSTGRES_USER:-postgres}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
DETAILED=false
if [[ "$1" == "--detailed" ]]; then
    DETAILED=true
fi

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

print_check() {
    local status="$1"
    local message="$2"
    
    if [ "$status" = "OK" ]; then
        echo -e "  ${GREEN}✓${NC} $message"
    elif [ "$status" = "WARNING" ]; then
        echo -e "  ${YELLOW}⚠${NC} $message"
    else
        echo -e "  ${RED}✗${NC} $message"
    fi
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
        print_error "PostgreSQL container not found"
        return 1
    fi
    
    if ! docker ps -q -f name="$container" > /dev/null; then
        print_error "PostgreSQL container '$container' is not running"
        return 1
    fi
    
    print_success "Connected to PostgreSQL container: $container"
    POSTGRES_CONTAINER="$container"
    return 0
}

# Function to execute SQL in PostgreSQL container
exec_sql() {
    local sql="$1"
    local container="$POSTGRES_CONTAINER"
    
    docker exec -i "$container" psql -U "$DB_USER" -d "$DB_NAME" -t -c "$sql" 2>/dev/null | xargs
}

# Function to check if table exists
table_exists() {
    local table_name="$1"
    local count=$(exec_sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table_name';")
    [ "$count" = "1" ]
}

# Function to check if column exists
column_exists() {
    local table_name="$1"
    local column_name="$2"
    local count=$(exec_sql "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = '$table_name' AND column_name = '$column_name';")
    [ "$count" = "1" ]
}

# Function to get table row count
get_row_count() {
    local table_name="$1"
    if table_exists "$table_name"; then
        exec_sql "SELECT COUNT(*) FROM $table_name;"
    else
        echo "0"
    fi
}

# Function to verify users table
verify_users_table() {
    echo
    print_status "Verifying users table..."
    
    if table_exists "users"; then
        print_check "OK" "Table 'users' exists"
        
        # Check required columns
        local columns=(
            "id" "email" "password_hash" "first_name" "last_name" "role"
            "tenant_id" "is_active" "email_verified" "created_at" "updated_at"
            "last_login" "failed_login_attempts" "account_locked_until" "password_changed_at"
        )
        
        for col in "${columns[@]}"; do
            if column_exists "users" "$col"; then
                print_check "OK" "Column 'users.$col' exists"
            else
                print_check "ERROR" "Column 'users.$col' missing"
            fi
        done
        
        local row_count=$(get_row_count "users")
        print_check "OK" "Users table has $row_count records"
        
    else
        print_check "ERROR" "Table 'users' does not exist"
    fi
}

# Function to verify user_sessions table
verify_sessions_table() {
    echo
    print_status "Verifying user_sessions table..."
    
    if table_exists "user_sessions"; then
        print_check "OK" "Table 'user_sessions' exists"
        
        local row_count=$(get_row_count "user_sessions")
        print_check "OK" "User sessions table has $row_count records"
        
    else
        print_check "ERROR" "Table 'user_sessions' does not exist"
    fi
}

# Function to verify password_reset_tokens table
verify_password_reset_table() {
    echo
    print_status "Verifying password_reset_tokens table..."
    
    if table_exists "password_reset_tokens"; then
        print_check "OK" "Table 'password_reset_tokens' exists"
        
        local row_count=$(get_row_count "password_reset_tokens")
        print_check "OK" "Password reset tokens table has $row_count records"
        
    else
        print_check "ERROR" "Table 'password_reset_tokens' does not exist"
    fi
}

# Function to verify audit_logs table
verify_audit_logs_table() {
    echo
    print_status "Verifying audit_logs table..."
    
    if table_exists "audit_logs"; then
        print_check "OK" "Table 'audit_logs' exists"
        
        local row_count=$(get_row_count "audit_logs")
        print_check "OK" "Audit logs table has $row_count records"
        
    else
        print_check "ERROR" "Table 'audit_logs' does not exist"
    fi
}

# Function to check migration status
check_migration_status() {
    echo
    print_status "Checking migration status..."
    
    if table_exists "migration_log"; then
        print_check "OK" "Migration log table exists"
        
        local applied_migrations=$(exec_sql "SELECT string_agg(version, ', ' ORDER BY version) FROM migration_log;")
        
        if [ -n "$applied_migrations" ] && [ "$applied_migrations" != "" ]; then
            print_check "OK" "Applied migrations: $applied_migrations"
        else
            print_check "WARNING" "No migrations have been applied"
        fi
    else
        print_check "WARNING" "Migration log table does not exist"
    fi
}

# Function to perform security checks
perform_security_checks() {
    echo
    print_status "Performing security checks..."
    
    # Check for admin users
    if table_exists "users"; then
        local admin_count=$(exec_sql "SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = true;" || echo "0")
        
        if [ "$admin_count" -gt "0" ]; then
            print_check "OK" "$admin_count active admin users found"
        else
            print_check "WARNING" "No active admin users found - consider creating an admin user"
        fi
        
        # Check total user count
        local total_users=$(get_row_count "users")
        print_check "OK" "Total users in database: $total_users"
    fi
    
    # Check for active sessions
    if table_exists "user_sessions"; then
        local active_sessions=$(exec_sql "SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP;" || echo "0")
        print_check "OK" "$active_sessions active user sessions"
    fi
    
    # Check for recent security events
    if table_exists "audit_logs"; then
        local recent_events=$(exec_sql "SELECT COUNT(*) FROM audit_logs WHERE occurred_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours';" || echo "0")
        print_check "OK" "$recent_events audit events in last 24 hours"
    fi
}

# Function to generate summary report
generate_summary() {
    echo
    print_status "Schema Verification Summary:"
    echo
    
    local tables=("users" "user_sessions" "password_reset_tokens" "audit_logs" "migration_log")
    local table_count=0
    
    for table in "${tables[@]}"; do
        if table_exists "$table"; then
            ((table_count++))
        fi
    done
    
    echo "Database: $DB_NAME in container: $POSTGRES_CONTAINER"
    echo "Tables: $table_count/5 authentication tables exist"
    
    if [ "$table_count" = "5" ]; then
        print_success "Authentication schema appears to be complete"
        echo
        echo "Next steps:"
        echo "1. Create initial admin user for testing"
        echo "2. Test authentication flows"
        echo "3. Set up monitoring for security events"
    elif [ "$table_count" -gt "0" ]; then
        print_warning "Authentication schema is partially complete"
        echo
        echo "Run migrations to complete setup:"
        echo "  ./run_migrations_docker.sh up"
    else
        print_error "Authentication schema not found"
        echo
        echo "Run migrations to create schema:"
        echo "  ./run_migrations_docker.sh up"
    fi
}

# Main function
main() {
    echo "PyAirtable Authentication Schema Verification (Docker)"
    echo "===================================================="
    
    if ! check_postgres_container; then
        exit 1
    fi
    
    check_migration_status
    verify_users_table
    verify_sessions_table
    verify_password_reset_table
    verify_audit_logs_table
    perform_security_checks
    generate_summary
}

# Run main function
main "$@"