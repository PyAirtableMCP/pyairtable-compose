#!/bin/bash

# PyAirtable Database Initialization Script
# Comprehensive database setup with migrations, seed data, and schema management
# Supports both fresh installation and migration from existing data

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly NAMESPACE="pyairtable"
readonly POSTGRES_POD=""
readonly MIGRATIONS_DIR="$PROJECT_ROOT/migrations"
readonly BACKUP_DIR="$PROJECT_ROOT/backups"

# Database configuration
readonly DB_NAME="pyairtable"  
readonly DB_USER="postgres"
readonly DB_PASSWORD=""  # Will be retrieved from secrets
readonly DB_HOST="postgres"
readonly DB_PORT="5432"

# Migration tracking
declare -A APPLIED_MIGRATIONS
declare -A AVAILABLE_MIGRATIONS

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

print_progress() {
    echo -e "${PURPLE}🔄 $1${NC}"
}

# Get database password from secrets
get_db_password() {
    kubectl get secret pyairtable-secrets -n "$NAMESPACE" -o jsonpath='{.data.postgres-password}' | base64 -d 2>/dev/null || echo "postgres"
}

# Get PostgreSQL pod name
get_postgres_pod() {
    kubectl get pods -l app=postgres -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

# Execute SQL command in PostgreSQL
execute_sql() {
    local sql_command="$1"
    local database="${2:-$DB_NAME}"
    local pod_name
    pod_name=$(get_postgres_pod)
    
    if [[ -z "$pod_name" ]]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi
    
    kubectl exec -n "$NAMESPACE" "$pod_name" -- psql -U "$DB_USER" -d "$database" -c "$sql_command"
}

# Execute SQL file in PostgreSQL
execute_sql_file() {
    local sql_file="$1"
    local database="${2:-$DB_NAME}"
    local pod_name
    pod_name=$(get_postgres_pod)
    
    if [[ -z "$pod_name" ]]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi
    
    if [[ ! -f "$sql_file" ]]; then
        print_error "SQL file not found: $sql_file"
        return 1
    fi
    
    kubectl exec -i -n "$NAMESPACE" "$pod_name" -- psql -U "$DB_USER" -d "$database" < "$sql_file"
}

# Check if PostgreSQL is ready
check_postgres_ready() {
    local pod_name
    pod_name=$(get_postgres_pod)
    
    if [[ -z "$pod_name" ]]; then
        return 1
    fi
    
    kubectl exec -n "$NAMESPACE" "$pod_name" -- pg_isready -U "$DB_USER" -d "$DB_NAME" &>/dev/null
}

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    print_progress "Waiting for PostgreSQL to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if check_postgres_ready; then
            print_success "PostgreSQL is ready"
            return 0
        fi
        
        print_info "Attempt $attempt/$max_attempts - PostgreSQL not ready yet..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_error "PostgreSQL failed to become ready after $max_attempts attempts"
    return 1
}

# Create database if it doesn't exist
create_database() {
    print_header "Database Creation"
    
    # Check if database exists
    local db_exists
    db_exists=$(execute_sql "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" postgres | grep -c "1" || echo "0")
    
    if [[ "$db_exists" == "0" ]]; then
        print_progress "Creating database: $DB_NAME"
        execute_sql "CREATE DATABASE $DB_NAME;" postgres
        print_success "Database created: $DB_NAME"
    else
        print_info "Database already exists: $DB_NAME"
    fi
}

# Create extensions
create_extensions() {
    print_header "Database Extensions"
    
    local extensions=(
        "uuid-ossp"
        "pg_stat_statements"
        "pg_trgm"
        "btree_gin"
        "btree_gist"
        "pgcrypto"
    )
    
    for extension in "${extensions[@]}"; do
        print_progress "Creating extension: $extension"
        execute_sql "CREATE EXTENSION IF NOT EXISTS \"$extension\";" || {
            print_warning "Failed to create extension: $extension (may not be available)"
        }
    done
    
    print_success "Extensions configured"
}

# Create schemas
create_schemas() {
    print_header "Database Schemas"
    
    local schemas=(
        "auth"
        "analytics"  
        "workflows"
        "files"
        "saga"
        "integrations"
        "monitoring"
    )
    
    for schema in "${schemas[@]}"; do
        print_progress "Creating schema: $schema"
        execute_sql "CREATE SCHEMA IF NOT EXISTS $schema;"
    done
    
    print_success "Schemas created"
}

# Create migration tracking table
create_migration_table() {
    print_progress "Creating migration tracking table..."
    
    execute_sql "
    CREATE TABLE IF NOT EXISTS public.schema_migrations (
        id SERIAL PRIMARY KEY,
        version VARCHAR(255) UNIQUE NOT NULL,
        description TEXT,
        applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        checksum VARCHAR(64),
        execution_time_ms INTEGER
    );"
    
    print_success "Migration tracking table created"
}

# Get applied migrations
get_applied_migrations() {
    local migrations
    migrations=$(execute_sql "SELECT version FROM public.schema_migrations ORDER BY applied_at;" 2>/dev/null || echo "")
    
    APPLIED_MIGRATIONS=()
    while IFS= read -r migration; do
        if [[ -n "$migration" ]]; then
            APPLIED_MIGRATIONS["$migration"]=1
        fi
    done <<< "$migrations"
}

# Get available migrations
get_available_migrations() {
    AVAILABLE_MIGRATIONS=()
    
    if [[ -d "$MIGRATIONS_DIR" ]]; then
        for migration_file in "$MIGRATIONS_DIR"/*.sql; do
            if [[ -f "$migration_file" ]]; then
                local filename
                filename=$(basename "$migration_file" .sql)
                AVAILABLE_MIGRATIONS["$filename"]="$migration_file"
            fi
        done
    fi
}

# Calculate file checksum
calculate_checksum() {
    local file_path="$1"
    
    if [[ -f "$file_path" ]]; then
        shasum -a 256 "$file_path" | cut -d' ' -f1
    else
        echo ""
    fi
}

# Apply single migration
apply_migration() {
    local migration_version="$1"
    local migration_file="$2"
    
    print_progress "Applying migration: $migration_version"
    
    local start_time
    start_time=$(date +%s%3N)
    
    # Read migration file
    local migration_content
    if ! migration_content=$(cat "$migration_file"); then
        print_error "Failed to read migration file: $migration_file"
        return 1
    fi
    
    # Extract description from migration file
    local description
    description=$(grep -m 1 "^-- Description:" "$migration_file" | sed 's/^-- Description: //' || echo "No description")
    
    # Calculate checksum
    local checksum
    checksum=$(calculate_checksum "$migration_file")
    
    # Apply migration
    if execute_sql_file "$migration_file"; then
        local end_time
        end_time=$(date +%s%3N)
        local execution_time=$((end_time - start_time))
        
        # Record migration
        execute_sql "
        INSERT INTO public.schema_migrations (version, description, checksum, execution_time_ms) 
        VALUES ('$migration_version', '$description', '$checksum', $execution_time);"
        
        print_success "Applied migration: $migration_version ($execution_time ms)"
        return 0
    else
        print_error "Failed to apply migration: $migration_version"
        return 1
    fi
}

# Run database migrations
run_migrations() {
    print_header "Database Migrations"
    
    # Get current state
    get_applied_migrations
    get_available_migrations
    
    if [[ ${#AVAILABLE_MIGRATIONS[@]} -eq 0 ]]; then
        print_warning "No migration files found in: $MIGRATIONS_DIR"
        return 0
    fi
    
    # Sort migration versions
    local sorted_migrations
    mapfile -t sorted_migrations < <(printf '%s\n' "${!AVAILABLE_MIGRATIONS[@]}" | sort)
    
    local applied_count=0
    local skipped_count=0
    
    for migration_version in "${sorted_migrations[@]}"; do
        if [[ -n "${APPLIED_MIGRATIONS[$migration_version]:-}" ]]; then
            print_info "Skipping already applied migration: $migration_version"
            skipped_count=$((skipped_count + 1))
        else
            local migration_file="${AVAILABLE_MIGRATIONS[$migration_version]}"
            
            if apply_migration "$migration_version" "$migration_file"; then
                applied_count=$((applied_count + 1))
            else
                print_error "Migration failed, stopping at: $migration_version"
                return 1
            fi
        fi
    done
    
    print_success "Migrations completed: $applied_count applied, $skipped_count skipped"
}

# Create core tables
create_core_tables() {
    print_header "Core Tables Creation"
    
    # Auth tables
    print_progress "Creating auth tables..."
    execute_sql "
    CREATE TABLE IF NOT EXISTS auth.users (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        first_name VARCHAR(100),
        last_name VARCHAR(100),
        is_active BOOLEAN DEFAULT true,
        is_verified BOOLEAN DEFAULT false,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        last_login_at TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS auth.user_sessions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        session_token VARCHAR(255) UNIQUE NOT NULL,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        ip_address INET,
        user_agent TEXT
    );
    
    CREATE TABLE IF NOT EXISTS auth.user_permissions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
        permission VARCHAR(100) NOT NULL,
        resource VARCHAR(100),
        granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        granted_by UUID REFERENCES auth.users(id),
        UNIQUE(user_id, permission, resource)
    );"
    
    # Analytics tables
    print_progress "Creating analytics tables..."  
    execute_sql "
    CREATE TABLE IF NOT EXISTS analytics.events (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        event_type VARCHAR(100) NOT NULL,
        user_id UUID REFERENCES auth.users(id),
        session_id UUID,
        data JSONB,
        metadata JSONB,
        ip_address INET,
        user_agent TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS analytics.metrics (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        metric_name VARCHAR(100) NOT NULL,
        metric_value NUMERIC NOT NULL,
        tags JSONB,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );"
    
    # Workflow tables
    print_progress "Creating workflow tables..."
    execute_sql "
    CREATE TABLE IF NOT EXISTS workflows.workflows (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        name VARCHAR(255) NOT NULL,
        description TEXT,
        definition JSONB NOT NULL,
        version INTEGER DEFAULT 1,
        is_active BOOLEAN DEFAULT true,
        created_by UUID REFERENCES auth.users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS workflows.workflow_executions (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        workflow_id UUID NOT NULL REFERENCES workflows.workflows(id),
        status VARCHAR(50) DEFAULT 'PENDING',
        input_data JSONB,
        output_data JSONB,
        error_message TEXT,
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        completed_at TIMESTAMP,
        executed_by UUID REFERENCES auth.users(id)
    );"
    
    # File management tables
    print_progress "Creating file management tables..."
    execute_sql "
    CREATE TABLE IF NOT EXISTS files.uploaded_files (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        original_name VARCHAR(255) NOT NULL,
        stored_name VARCHAR(255) NOT NULL,  
        file_path TEXT NOT NULL,
        file_size BIGINT NOT NULL,
        mime_type VARCHAR(100),
        file_hash VARCHAR(64),
        uploaded_by UUID REFERENCES auth.users(id),
        uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        processed_at TIMESTAMP,
        processing_status VARCHAR(50) DEFAULT 'PENDING'
    );
    
    CREATE TABLE IF NOT EXISTS files.file_processing_results (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        file_id UUID NOT NULL REFERENCES files.uploaded_files(id) ON DELETE CASCADE,
        processor_type VARCHAR(100) NOT NULL,
        result_data JSONB,
        error_message TEXT,
        processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );"
    
    # SAGA tables
    print_progress "Creating SAGA orchestration tables..."
    execute_sql "
    CREATE TABLE IF NOT EXISTS saga.sagas (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        saga_type VARCHAR(100) NOT NULL,
        status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
        current_step INTEGER DEFAULT 0,
        total_steps INTEGER NOT NULL,
        input_data JSONB,
        context_data JSONB,
        error_message TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        completed_at TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS saga.saga_steps (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        saga_id UUID NOT NULL REFERENCES saga.sagas(id) ON DELETE CASCADE,
        step_number INTEGER NOT NULL,
        step_name VARCHAR(100) NOT NULL,
        status VARCHAR(50) DEFAULT 'PENDING',
        input_data JSONB,
        output_data JSONB,
        error_message TEXT,
        started_at TIMESTAMP,
        completed_at TIMESTAMP,
        retry_count INTEGER DEFAULT 0,
        UNIQUE(saga_id, step_number)
    );"
    
    # Integration tables
    print_progress "Creating integration tables..."
    execute_sql "
    CREATE TABLE IF NOT EXISTS integrations.airtable_connections (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES auth.users(id),
        base_id VARCHAR(255) NOT NULL,
        api_key_hash VARCHAR(255) NOT NULL,
        base_name VARCHAR(255),
        is_active BOOLEAN DEFAULT true,
        last_sync_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE TABLE IF NOT EXISTS integrations.sync_jobs (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        connection_id UUID NOT NULL REFERENCES integrations.airtable_connections(id),
        job_type VARCHAR(100) NOT NULL,
        status VARCHAR(50) DEFAULT 'PENDING',
        progress JSONB,
        result_data JSONB,  
        error_message TEXT,
        started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        completed_at TIMESTAMP
    );"
    
    print_success "Core tables created"
}

# Create indexes for performance
create_indexes() {
    print_header "Database Indexes"
    
    print_progress "Creating performance indexes..."
    
    # Auth indexes
    execute_sql "
    CREATE INDEX IF NOT EXISTS idx_users_email ON auth.users(email);
    CREATE INDEX IF NOT EXISTS idx_users_active ON auth.users(is_active) WHERE is_active = true;
    CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON auth.user_sessions(session_token);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON auth.user_sessions(expires_at);
    CREATE INDEX IF NOT EXISTS idx_user_permissions_user ON auth.user_permissions(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_permissions_permission ON auth.user_permissions(permission);"
    
    # Analytics indexes
    execute_sql "
    CREATE INDEX IF NOT EXISTS idx_events_type_created ON analytics.events(event_type, created_at);
    CREATE INDEX IF NOT EXISTS idx_events_user_created ON analytics.events(user_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_events_created ON analytics.events(created_at);
    CREATE INDEX IF NOT EXISTS idx_metrics_name_timestamp ON analytics.metrics(metric_name, timestamp);
    CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON analytics.metrics(timestamp);"
    
    # Workflow indexes
    execute_sql "
    CREATE INDEX IF NOT EXISTS idx_workflows_active ON workflows.workflows(is_active) WHERE is_active = true;
    CREATE INDEX IF NOT EXISTS idx_workflow_executions_workflow ON workflows.workflow_executions(workflow_id);
    CREATE INDEX IF NOT EXISTS idx_workflow_executions_status ON workflows.workflow_executions(status);
    CREATE INDEX IF NOT EXISTS idx_workflow_executions_started ON workflows.workflow_executions(started_at);"
    
    # File indexes
    execute_sql "
    CREATE INDEX IF NOT EXISTS idx_files_uploaded_by ON files.uploaded_files(uploaded_by);
    CREATE INDEX IF NOT EXISTS idx_files_processing_status ON files.uploaded_files(processing_status);
    CREATE INDEX IF NOT EXISTS idx_files_uploaded_at ON files.uploaded_files(uploaded_at);
    CREATE INDEX IF NOT EXISTS idx_file_results_file ON files.file_processing_results(file_id);"
    
    # SAGA indexes
    execute_sql "
    CREATE INDEX IF NOT EXISTS idx_sagas_type_status ON saga.sagas(saga_type, status);
    CREATE INDEX IF NOT EXISTS idx_sagas_status ON saga.sagas(status);
    CREATE INDEX IF NOT EXISTS idx_sagas_created ON saga.sagas(created_at);
    CREATE INDEX IF NOT EXISTS idx_saga_steps_saga ON saga.saga_steps(saga_id);
    CREATE INDEX IF NOT EXISTS idx_saga_steps_status ON saga.saga_steps(status);"
    
    # Integration indexes  
    execute_sql "
    CREATE INDEX IF NOT EXISTS idx_airtable_connections_user ON integrations.airtable_connections(user_id);
    CREATE INDEX IF NOT EXISTS idx_airtable_connections_active ON integrations.airtable_connections(is_active) WHERE is_active = true;
    CREATE INDEX IF NOT EXISTS idx_sync_jobs_connection ON integrations.sync_jobs(connection_id);
    CREATE INDEX IF NOT EXISTS idx_sync_jobs_status ON integrations.sync_jobs(status);"
    
    print_success "Indexes created"
}

# Insert seed data
insert_seed_data() {
    print_header "Seed Data Insertion"
    
    print_progress "Inserting test users..."
    execute_sql "
    INSERT INTO auth.users (email, password_hash, first_name, last_name, is_verified) VALUES 
        ('admin@pyairtable.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LWFAzFuBqFm.7BaXG', 'Admin', 'User', true),
        ('test@pyairtable.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LWFAzFuBqFm.7BaXG', 'Test', 'User', true),
        ('demo@pyairtable.com', '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LWFAzFuBqFm.7BaXG', 'Demo', 'User', true)
    ON CONFLICT (email) DO NOTHING;"
    
    print_progress "Inserting user permissions..."
    execute_sql "
    INSERT INTO auth.user_permissions (user_id, permission, resource) 
    SELECT u.id, 'admin', '*' FROM auth.users u WHERE u.email = 'admin@pyairtable.com'
    ON CONFLICT (user_id, permission, resource) DO NOTHING;
    
    INSERT INTO auth.user_permissions (user_id, permission, resource) 
    SELECT u.id, 'read', 'files' FROM auth.users u WHERE u.email IN ('test@pyairtable.com', 'demo@pyairtable.com')
    ON CONFLICT (user_id, permission, resource) DO NOTHING;
    
    INSERT INTO auth.user_permissions (user_id, permission, resource) 
    SELECT u.id, 'write', 'workflows' FROM auth.users u WHERE u.email IN ('test@pyairtable.com', 'demo@pyairtable.com')
    ON CONFLICT (user_id, permission, resource) DO NOTHING;"
    
    print_progress "Inserting sample workflows..."
    execute_sql "
    INSERT INTO workflows.workflows (name, description, definition, created_by) 
    SELECT 
        'File Processing Workflow',
        'Automatically process uploaded files',
        '{\"steps\": [{\"name\": \"validate\", \"type\": \"validation\"}, {\"name\": \"process\", \"type\": \"processing\"}, {\"name\": \"notify\", \"type\": \"notification\"}]}',
        u.id
    FROM auth.users u WHERE u.email = 'admin@pyairtable.com'
    ON CONFLICT DO NOTHING;"
    
    print_success "Seed data inserted"
}

# Verify database setup
verify_database_setup() {
    print_header "Database Verification"
    
    # Check tables exist
    local table_count
    table_count=$(execute_sql "
    SELECT COUNT(*) 
    FROM information_schema.tables 
    WHERE table_schema IN ('auth', 'analytics', 'workflows', 'files', 'saga', 'integrations');" | grep -o '[0-9]*' | head -1)
    
    print_info "Found $table_count tables across all schemas"
    
    # Check extensions
    local extension_count
    extension_count=$(execute_sql "SELECT COUNT(*) FROM pg_extension;" | grep -o '[0-9]*' | head -1)
    print_info "Found $extension_count extensions installed"
    
    # Check users
    local user_count
    user_count=$(execute_sql "SELECT COUNT(*) FROM auth.users;" | grep -o '[0-9]*' | head -1)
    print_info "Found $user_count users in database"
    
    # Check migrations
    local migration_count
    migration_count=$(execute_sql "SELECT COUNT(*) FROM public.schema_migrations;" | grep -o '[0-9]*' | head -1)
    print_info "Found $migration_count applied migrations"
    
    print_success "Database verification completed"
}

# Create database backup
create_backup() {
    print_header "Database Backup"
    
    local backup_timestamp
    backup_timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/pyairtable_backup_$backup_timestamp.sql"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    local pod_name
    pod_name=$(get_postgres_pod)
    
    if [[ -z "$pod_name" ]]; then
        print_error "PostgreSQL pod not found"
        return 1
    fi
    
    print_progress "Creating database backup: $backup_file"
    
    # Create backup
    kubectl exec -n "$NAMESPACE" "$pod_name" -- pg_dump -U "$DB_USER" "$DB_NAME" > "$backup_file"
    
    if [[ -f "$backup_file" ]]; then
        local backup_size
        backup_size=$(du -h "$backup_file" | cut -f1)
        print_success "Backup created: $backup_file ($backup_size)"
    else
        print_error "Backup creation failed"
        return 1
    fi
}

# Main function
main() {
    print_header "PyAirtable Database Initialization"
    
    local command=${1:-"init"}
    
    case $command in
        "init"|"setup")
            wait_for_postgres
            create_database
            create_extensions
            create_schemas
            create_migration_table
            run_migrations
            create_core_tables
            create_indexes
            insert_seed_data
            verify_database_setup
            print_success "Database initialization completed"
            ;;
        "migrate")
            wait_for_postgres
            create_migration_table
            run_migrations
            verify_database_setup
            print_success "Database migration completed"
            ;;
        "backup")
            wait_for_postgres
            create_backup
            ;;
        "verify")
            wait_for_postgres
            verify_database_setup
            ;;
        "reset")
            print_warning "This will destroy all data in the database!"
            read -p "Are you sure? (type 'yes' to confirm): " -r
            if [[ $REPLY == "yes" ]]; then
                execute_sql "DROP DATABASE IF EXISTS $DB_NAME;" postgres
                print_success "Database reset completed"
                # Re-initialize after reset
                main "init"
            else
                print_info "Database reset cancelled"
            fi
            ;;
        "help"|"-h"|"--help")
            echo "PyAirtable Database Initialization"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  init, setup      Complete database initialization (default)"
            echo "  migrate          Run pending migrations only"
            echo "  backup           Create database backup"
            echo "  verify           Verify database setup"
            echo "  reset            Reset database (WARNING: destroys all data)"
            echo "  help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 init"
            echo "  $0 migrate"
            echo "  $0 backup"
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"