#!/bin/bash

# Database Schema Verification Script for PyAirtable Authentication
# This script checks the current state of the authentication schema
# Usage: ./verify_schema.sh [--detailed]

set -e

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

# Function to check database connectivity
check_db_connection() {
    print_status "Checking database connection..."
    
    if ! command -v psql &> /dev/null; then
        print_error "psql client not found. Please install PostgreSQL client tools."
        exit 1
    fi
    
    export PGPASSWORD="$DB_PASSWORD"
    
    if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" > /dev/null 2>&1; then
        local version=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT version();" | xargs)
        print_success "Connected to: $version"
        return 0
    else
        print_error "Cannot connect to database"
        return 1
    fi
}

# Function to check if table exists
table_exists() {
    local table_name="$1"
    export PGPASSWORD="$DB_PASSWORD"
    
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) 
        FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = '$table_name';
    " 2>/dev/null | xargs)
    
    [ "$count" = "1" ]
}

# Function to check if column exists
column_exists() {
    local table_name="$1"
    local column_name="$2"
    export PGPASSWORD="$DB_PASSWORD"
    
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) 
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = '$table_name' AND column_name = '$column_name';
    " 2>/dev/null | xargs)
    
    [ "$count" = "1" ]
}

# Function to check if index exists
index_exists() {
    local index_name="$1"
    export PGPASSWORD="$DB_PASSWORD"
    
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) 
        FROM pg_indexes 
        WHERE schemaname = 'public' AND indexname = '$index_name';
    " 2>/dev/null | xargs)
    
    [ "$count" = "1" ]
}

# Function to check if function exists
function_exists() {
    local function_name="$1"
    export PGPASSWORD="$DB_PASSWORD"
    
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) 
        FROM information_schema.routines 
        WHERE routine_schema = 'public' AND routine_name = '$function_name';
    " 2>/dev/null | xargs)
    
    [ "$count" -gt "0" ]
}

# Function to check if constraint exists
constraint_exists() {
    local table_name="$1"
    local constraint_name="$2"
    export PGPASSWORD="$DB_PASSWORD"
    
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) 
        FROM information_schema.table_constraints 
        WHERE table_schema = 'public' AND table_name = '$table_name' AND constraint_name = '$constraint_name';
    " 2>/dev/null | xargs)
    
    [ "$count" = "1" ]
}

# Function to get table row count
get_row_count() {
    local table_name="$1"
    export PGPASSWORD="$DB_PASSWORD"
    
    if table_exists "$table_name"; then
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table_name;" 2>/dev/null | xargs
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
        
        # Check constraints
        local constraints=("email_format" "password_not_empty" "valid_role" "failed_attempts_positive")
        for constraint in "${constraints[@]}"; do
            if constraint_exists "users" "$constraint"; then
                print_check "OK" "Constraint '$constraint' exists"
            else
                print_check "WARNING" "Constraint '$constraint' missing"
            fi
        done
        
        # Check indexes
        local indexes=("idx_users_email" "idx_users_is_active" "idx_users_failed_attempts")
        for idx in "${indexes[@]}"; do
            if index_exists "$idx"; then
                print_check "OK" "Index '$idx' exists"
            else
                print_check "WARNING" "Index '$idx' missing"
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
        
        # Check required columns
        local columns=(
            "id" "user_id" "token_hash" "ip_address" "user_agent"
            "created_at" "expires_at" "revoked_at" "last_used_at"
            "session_type" "device_info" "location_info"
        )
        
        for col in "${columns[@]}"; do
            if column_exists "user_sessions" "$col"; then
                print_check "OK" "Column 'user_sessions.$col' exists"
            else
                print_check "ERROR" "Column 'user_sessions.$col' missing"
            fi
        done
        
        # Check foreign key
        if constraint_exists "user_sessions" "fk_user_sessions_user_id"; then
            print_check "OK" "Foreign key constraint exists"
        else
            print_check "WARNING" "Foreign key constraint missing"
        fi
        
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
        
        # Check required columns
        local columns=(
            "id" "user_id" "token_hash" "created_at" "expires_at"
            "used_at" "ip_address" "user_agent" "attempts_count" "max_attempts"
        )
        
        for col in "${columns[@]}"; do
            if column_exists "password_reset_tokens" "$col"; then
                print_check "OK" "Column 'password_reset_tokens.$col' exists"
            else
                print_check "ERROR" "Column 'password_reset_tokens.$col' missing"
            fi
        done
        
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
        
        # Check required columns
        local columns=(
            "id" "user_id" "session_id" "event_type" "event_category"
            "event_description" "resource_type" "resource_id" "ip_address"
            "user_agent" "occurred_at" "success" "risk_level" "metadata"
        )
        
        for col in "${columns[@]}"; do
            if column_exists "audit_logs" "$col"; then
                print_check "OK" "Column 'audit_logs.$col' exists"
            else
                print_check "ERROR" "Column 'audit_logs.$col' missing"
            fi
        done
        
        local row_count=$(get_row_count "audit_logs")
        print_check "OK" "Audit logs table has $row_count records"
        
    else
        print_check "ERROR" "Table 'audit_logs' does not exist"
    fi
}

# Function to verify functions
verify_functions() {
    echo
    print_status "Verifying stored functions..."
    
    local functions=(
        "handle_failed_login" "reset_failed_login_attempts" "is_account_locked"
        "create_user_session" "validate_session" "revoke_session"
        "create_password_reset_token" "validate_password_reset_token" "use_password_reset_token"
        "log_security_event" "get_user_security_events" "detect_suspicious_activity"
    )
    
    for func in "${functions[@]}"; do
        if function_exists "$func"; then
            print_check "OK" "Function '$func' exists"
        else
            print_check "WARNING" "Function '$func' missing"
        fi
    done
}

# Function to verify views
verify_views() {
    echo
    print_status "Verifying views..."
    
    export PGPASSWORD="$DB_PASSWORD"
    local views=(
        "active_user_sessions" "active_password_reset_tokens"
        "security_events_summary" "high_risk_events" "user_activity_summary"
    )
    
    for view in "${views[@]}"; do
        local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) 
            FROM information_schema.views 
            WHERE table_schema = 'public' AND table_name = '$view';
        " 2>/dev/null | xargs)
        
        if [ "$count" = "1" ]; then
            print_check "OK" "View '$view' exists"
        else
            print_check "WARNING" "View '$view' missing"
        fi
    done
}

# Function to check migration status
check_migration_status() {
    echo
    print_status "Checking migration status..."
    
    if table_exists "migration_log"; then
        print_check "OK" "Migration log table exists"
        
        export PGPASSWORD="$DB_PASSWORD"
        local applied_migrations=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT string_agg(version, ', ' ORDER BY version) FROM migration_log;
        " 2>/dev/null | xargs)
        
        if [ -n "$applied_migrations" ]; then
            print_check "OK" "Applied migrations: $applied_migrations"
        else
            print_check "WARNING" "No migrations have been applied"
        fi
    else
        print_check "WARNING" "Migration log table does not exist"
    fi
}

# Function to show detailed table information
show_detailed_info() {
    if [ "$DETAILED" = true ]; then
        echo
        print_status "Detailed schema information..."
        
        export PGPASSWORD="$DB_PASSWORD"
        
        # Show table sizes
        echo
        echo "Table sizes:"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            SELECT 
                schemaname,
                tablename,
                attname,
                n_distinct,
                correlation
            FROM pg_stats 
            WHERE schemaname = 'public' 
              AND tablename IN ('users', 'user_sessions', 'password_reset_tokens', 'audit_logs')
            ORDER BY tablename, attname;
        " 2>/dev/null || true
        
        # Show index usage
        echo
        echo "Index information:"
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
            SELECT 
                schemaname,
                tablename,
                indexname,
                indexdef
            FROM pg_indexes 
            WHERE schemaname = 'public' 
              AND tablename IN ('users', 'user_sessions', 'password_reset_tokens', 'audit_logs')
            ORDER BY tablename, indexname;
        " 2>/dev/null || true
    fi
}

# Function to perform security checks
perform_security_checks() {
    echo
    print_status "Performing security checks..."
    
    export PGPASSWORD="$DB_PASSWORD"
    
    # Check for users without passwords
    if table_exists "users"; then
        local empty_passwords=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) FROM users WHERE password_hash IS NULL OR length(password_hash) = 0;
        " 2>/dev/null | xargs)
        
        if [ "$empty_passwords" = "0" ]; then
            print_check "OK" "All users have password hashes"
        else
            print_check "WARNING" "$empty_passwords users without password hashes"
        fi
        
        # Check for locked accounts
        local locked_accounts=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) FROM users WHERE account_locked_until > CURRENT_TIMESTAMP;
        " 2>/dev/null | xargs)
        
        if [ "$locked_accounts" = "0" ]; then
            print_check "OK" "No accounts currently locked"
        else
            print_check "WARNING" "$locked_accounts accounts currently locked"
        fi
        
        # Check for admin users
        local admin_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) FROM users WHERE role = 'admin' AND is_active = true;
        " 2>/dev/null | xargs)
        
        if [ "$admin_count" -gt "0" ]; then
            print_check "OK" "$admin_count active admin users found"
        else
            print_check "WARNING" "No active admin users found"
        fi
    fi
    
    # Check for active sessions
    if table_exists "user_sessions"; then
        local active_sessions=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP;
        " 2>/dev/null | xargs)
        
        print_check "OK" "$active_sessions active user sessions"
    fi
    
    # Check for recent security events
    if table_exists "audit_logs"; then
        local recent_events=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) FROM audit_logs WHERE occurred_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours';
        " 2>/dev/null | xargs)
        
        print_check "OK" "$recent_events audit events in last 24 hours"
        
        local high_risk_events=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "
            SELECT COUNT(*) FROM audit_logs 
            WHERE occurred_at >= CURRENT_TIMESTAMP - INTERVAL '7 days' 
              AND risk_level IN ('high', 'critical');
        " 2>/dev/null | xargs)
        
        if [ "$high_risk_events" = "0" ]; then
            print_check "OK" "No high-risk security events in last 7 days"
        else
            print_check "WARNING" "$high_risk_events high-risk security events in last 7 days"
        fi
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
    
    echo "Database: $DB_NAME on $DB_HOST:$DB_PORT"
    echo "Tables: $table_count/5 authentication tables exist"
    
    if [ "$table_count" = "5" ]; then
        print_success "Authentication schema appears to be complete"
        echo
        echo "Next steps:"
        echo "1. Create initial admin user if none exists"
        echo "2. Test authentication flows"
        echo "3. Set up monitoring for security events"
    elif [ "$table_count" -gt "0" ]; then
        print_warning "Authentication schema is partially complete"
        echo
        echo "Run migrations to complete setup:"
        echo "  ./run_migrations.sh up"
    else
        print_error "Authentication schema not found"
        echo
        echo "Run migrations to create schema:"
        echo "  ./run_migrations.sh up"
    fi
}

# Main function
main() {
    echo "PyAirtable Authentication Schema Verification"
    echo "============================================"
    
    if ! check_db_connection; then
        exit 1
    fi
    
    check_migration_status
    verify_users_table
    verify_sessions_table
    verify_password_reset_table
    verify_audit_logs_table
    verify_functions
    verify_views
    perform_security_checks
    show_detailed_info
    generate_summary
}

# Run main function
main "$@"