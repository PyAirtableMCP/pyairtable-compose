#!/bin/bash

# Database Connection Wait Script with Retry Logic
# Ensures database is ready before starting dependent services

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="wait-for-database"
readonly MAX_RETRIES=${MAX_RETRIES:-30}
readonly RETRY_INTERVAL=${RETRY_INTERVAL:-5}
readonly TIMEOUT=${TIMEOUT:-150}

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Database configuration from environment
readonly DB_HOST="${DATABASE_HOST:-postgres}"
readonly DB_PORT="${DATABASE_PORT:-5432}"
readonly DB_NAME="${POSTGRES_DB:-pyairtable}"
readonly DB_USER="${POSTGRES_USER:-admin}"
readonly DB_PASSWORD="${POSTGRES_PASSWORD}"

# Logging functions
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

# Check if required environment variables are set
check_environment() {
    local missing_vars=()
    
    if [[ -z "${DB_PASSWORD:-}" ]]; then
        missing_vars+=("POSTGRES_PASSWORD")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        exit 1
    fi
}

# Test PostgreSQL connection
test_postgres_connection() {
    PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -c "SELECT 1;" \
        -q \
        --set ON_ERROR_STOP=1 \
        > /dev/null 2>&1
}

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    log_info "Waiting for PostgreSQL at $DB_HOST:$DB_PORT..."
    log_info "Database: $DB_NAME, User: $DB_USER"
    
    local attempt=0
    local start_time=$(date +%s)
    
    while [[ $attempt -lt $MAX_RETRIES ]]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            log_error "Timeout ($TIMEOUT seconds) waiting for PostgreSQL"
            return 1
        fi
        
        attempt=$((attempt + 1))
        
        if test_postgres_connection; then
            local total_time=$(($(date +%s) - start_time))
            log_success "PostgreSQL is ready! (attempt $attempt, ${total_time}s total)"
            return 0
        else
            if [[ $((attempt % 5)) -eq 0 ]]; then
                log_info "Still waiting for PostgreSQL... (attempt $attempt/$MAX_RETRIES, ${elapsed}s elapsed)"
            fi
            sleep "$RETRY_INTERVAL"
        fi
    done
    
    log_error "Failed to connect to PostgreSQL after $MAX_RETRIES attempts"
    return 1
}

# Test database schema and tables
test_database_schema() {
    log_info "Checking database schema..."
    
    # Check if basic tables exist (this can be customized based on your schema)
    local tables_check
    if tables_check=$(PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null); then
        
        local table_count=$(echo "$tables_check" | xargs)
        log_info "Found $table_count tables in database"
        
        if [[ $table_count -gt 0 ]]; then
            log_success "Database schema validation passed"
            return 0
        else
            log_warning "Database is empty (no tables found)"
            return 0  # This might be expected for fresh installations
        fi
    else
        log_error "Failed to check database schema"
        return 1
    fi
}

# Run migration check (optional)
check_migrations() {
    log_info "Checking migration status..."
    
    # Check if migrations table exists
    local migration_table_exists
    if migration_table_exists=$(PGPASSWORD="$DB_PASSWORD" psql \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'migration_log');" 2>/dev/null); then
        
        migration_table_exists=$(echo "$migration_table_exists" | xargs)
        if [[ "$migration_table_exists" == "t" ]]; then
            # Get migration count
            local migration_count
            migration_count=$(PGPASSWORD="$DB_PASSWORD" psql \
                -h "$DB_HOST" \
                -p "$DB_PORT" \
                -U "$DB_USER" \
                -d "$DB_NAME" \
                -t -c "SELECT COUNT(*) FROM migration_log WHERE applied = true;" 2>/dev/null | xargs)
            
            log_info "Found $migration_count applied migrations"
        else
            log_info "Migration table not found (fresh installation)"
        fi
        
        return 0
    else
        log_warning "Could not check migration status"
        return 0  # Non-critical
    fi
}

# Main execution
main() {
    log_info "=== Database Connection Wait Script ==="
    log_info "Script: $SCRIPT_NAME"
    log_info "Max retries: $MAX_RETRIES"
    log_info "Retry interval: ${RETRY_INTERVAL}s"
    log_info "Timeout: ${TIMEOUT}s"
    echo
    
    # Check environment
    check_environment
    
    # Wait for database
    if wait_for_postgres; then
        # Additional checks
        test_database_schema
        check_migrations
        
        log_success "Database is ready for connections!"
        exit 0
    else
        log_error "Database connection failed"
        exit 1
    fi
}

# Handle signals
trap 'log_warning "Received interrupt signal, exiting..."; exit 130' INT TERM

# Run main function
main "$@"