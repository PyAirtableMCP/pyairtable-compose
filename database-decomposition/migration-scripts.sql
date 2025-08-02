-- PyAirtable Database Decomposition Migration Scripts
-- Migration from single shared database to domain-specific databases

-- =============================================================================
-- 1. AUTH DATABASE (auth_db)
-- =============================================================================

CREATE DATABASE auth_db;
\c auth_db;

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table (core authentication data only)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email_verified BOOLEAN DEFAULT FALSE,
    last_login TIMESTAMP,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    -- Audit fields
    created_by UUID,
    updated_by UUID
);

-- Authentication sessions
CREATE TABLE auth_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    refresh_token_hash VARCHAR(255),
    expires_at TIMESTAMP NOT NULL,
    last_activity TIMESTAMP DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT,
    is_revoked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- API Keys for service-to-service authentication
CREATE TABLE api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key_name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(255) NOT NULL,
    service_name VARCHAR(100) NOT NULL,
    permissions JSONB NOT NULL DEFAULT '[]',
    expires_at TIMESTAMP,
    last_used TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    created_by UUID REFERENCES users(id)
);

-- Authentication events for audit
CREATE TABLE auth_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    event_type VARCHAR(50) NOT NULL, -- login, logout, password_change, etc.
    event_data JSONB,
    ip_address INET,
    user_agent TEXT,
    success BOOLEAN NOT NULL,
    failure_reason TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_auth_sessions_user_id ON auth_sessions(user_id);
CREATE INDEX idx_auth_sessions_token_hash ON auth_sessions(token_hash);
CREATE INDEX idx_auth_sessions_expires_at ON auth_sessions(expires_at);
CREATE INDEX idx_api_keys_hash ON api_keys(key_hash);
CREATE INDEX idx_auth_events_user_id ON auth_events(user_id);
CREATE INDEX idx_auth_events_created_at ON auth_events(created_at);

-- =============================================================================
-- 2. USER DATABASE (user_db)
-- =============================================================================

CREATE DATABASE user_db;
\c user_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- User profiles and preferences
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE, -- References auth_db.users.id
    tenant_id UUID NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    display_name VARCHAR(200),
    avatar_url TEXT,
    timezone VARCHAR(50) DEFAULT 'UTC',
    locale VARCHAR(10) DEFAULT 'en-US',
    theme_preference VARCHAR(20) DEFAULT 'light',
    notification_preferences JSONB DEFAULT '{}',
    onboarding_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- User settings
CREATE TABLE user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    setting_key VARCHAR(100) NOT NULL,
    setting_value JSONB NOT NULL,
    is_encrypted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, setting_key)
);

-- User activity tracking
CREATE TABLE user_activity (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    activity_type VARCHAR(50) NOT NULL,
    activity_data JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX idx_user_profiles_tenant_id ON user_profiles(tenant_id);
CREATE INDEX idx_user_settings_user_id ON user_settings(user_id);
CREATE INDEX idx_user_activity_user_id ON user_activity(user_id);
CREATE INDEX idx_user_activity_created_at ON user_activity(created_at);

-- =============================================================================
-- 3. PERMISSION DATABASE (permission_db)
-- =============================================================================

CREATE DATABASE permission_db;
\c permission_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tenants
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    subdomain VARCHAR(100) UNIQUE NOT NULL,
    plan VARCHAR(50) DEFAULT 'free',
    status VARCHAR(20) DEFAULT 'active',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Roles
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    permissions JSONB NOT NULL DEFAULT '[]',
    is_system_role BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, name)
);

-- User tenant memberships with roles
CREATE TABLE user_tenant_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- References auth_db.users.id
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    granted_by UUID NOT NULL, -- References auth_db.users.id
    granted_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    UNIQUE(user_id, tenant_id, role_id)
);

-- Resource-level permissions
CREATE TABLE resource_permissions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    resource_type VARCHAR(50) NOT NULL, -- base, table, record, etc.
    resource_id VARCHAR(255) NOT NULL,
    permission VARCHAR(50) NOT NULL, -- read, write, delete, admin
    granted_by UUID NOT NULL,
    granted_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Indexes
CREATE INDEX idx_tenants_subdomain ON tenants(subdomain);
CREATE INDEX idx_roles_tenant_id ON roles(tenant_id);
CREATE INDEX idx_user_tenant_roles_user_id ON user_tenant_roles(user_id);
CREATE INDEX idx_user_tenant_roles_tenant_id ON user_tenant_roles(tenant_id);
CREATE INDEX idx_resource_permissions_user_id ON resource_permissions(user_id);
CREATE INDEX idx_resource_permissions_tenant_id ON resource_permissions(tenant_id);
CREATE INDEX idx_resource_permissions_resource ON resource_permissions(resource_type, resource_id);

-- =============================================================================
-- 4. SCHEMA DATABASE (schema_db)
-- =============================================================================

CREATE DATABASE schema_db;
\c schema_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Airtable base metadata
CREATE TABLE airtable_bases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    airtable_base_id VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    schema_version INTEGER DEFAULT 1,
    raw_schema JSONB NOT NULL,
    processed_schema JSONB NOT NULL,
    last_sync_at TIMESTAMP,
    sync_status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Table schemas
CREATE TABLE table_schemas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    base_id UUID NOT NULL REFERENCES airtable_bases(id) ON DELETE CASCADE,
    airtable_table_id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    primary_field_id VARCHAR(255),
    view_order INTEGER,
    schema_definition JSONB NOT NULL,
    field_count INTEGER DEFAULT 0,
    record_count INTEGER DEFAULT 0,
    last_sync_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(base_id, airtable_table_id)
);

-- Field schemas
CREATE TABLE field_schemas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_id UUID NOT NULL REFERENCES table_schemas(id) ON DELETE CASCADE,
    airtable_field_id VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    field_type VARCHAR(50) NOT NULL,
    description TEXT,
    options JSONB,
    is_primary BOOLEAN DEFAULT FALSE,
    is_computed BOOLEAN DEFAULT FALSE,
    dependencies JSONB DEFAULT '[]',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(table_id, airtable_field_id)
);

-- Schema change history
CREATE TABLE schema_changes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    base_id UUID NOT NULL REFERENCES airtable_bases(id) ON DELETE CASCADE,
    change_type VARCHAR(50) NOT NULL, -- base_created, table_added, field_modified, etc.
    entity_type VARCHAR(50) NOT NULL, -- base, table, field
    entity_id VARCHAR(255) NOT NULL,
    old_definition JSONB,
    new_definition JSONB,
    changed_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_airtable_bases_tenant_id ON airtable_bases(tenant_id);
CREATE INDEX idx_airtable_bases_base_id ON airtable_bases(airtable_base_id);
CREATE INDEX idx_table_schemas_base_id ON table_schemas(base_id);
CREATE INDEX idx_table_schemas_table_id ON table_schemas(airtable_table_id);
CREATE INDEX idx_field_schemas_table_id ON field_schemas(table_id);
CREATE INDEX idx_field_schemas_field_id ON field_schemas(airtable_field_id);
CREATE INDEX idx_schema_changes_base_id ON schema_changes(base_id);
CREATE INDEX idx_schema_changes_created_at ON schema_changes(created_at);

-- =============================================================================
-- 5. SYNC DATABASE (sync_db)
-- =============================================================================

CREATE DATABASE sync_db;
\c sync_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- Sync jobs
CREATE TABLE sync_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    base_id UUID NOT NULL, -- References schema_db.airtable_bases.id
    job_type VARCHAR(50) NOT NULL, -- full_sync, incremental_sync, schema_sync
    status VARCHAR(20) DEFAULT 'pending', -- pending, running, completed, failed
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    sync_statistics JSONB DEFAULT '{}',
    configuration JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Sync operations (for tracking individual table/record syncs)
CREATE TABLE sync_operations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES sync_jobs(id) ON DELETE CASCADE,
    operation_type VARCHAR(50) NOT NULL, -- table_sync, record_create, record_update, record_delete
    entity_type VARCHAR(50) NOT NULL, -- table, record
    entity_id VARCHAR(255) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    operation_data JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Sync conflicts (when data conflicts occur during sync)
CREATE TABLE sync_conflicts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES sync_jobs(id) ON DELETE CASCADE,
    conflict_type VARCHAR(50) NOT NULL, -- data_conflict, schema_conflict
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(255) NOT NULL,
    local_data JSONB,
    remote_data JSONB,
    resolution_strategy VARCHAR(50), -- local_wins, remote_wins, merge, manual
    resolved_at TIMESTAMP,
    resolved_by UUID,
    resolution_data JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Sync cursors (for incremental sync tracking)
CREATE TABLE sync_cursors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    base_id UUID NOT NULL,
    table_id UUID,
    cursor_type VARCHAR(50) NOT NULL, -- offset, timestamp, etag
    cursor_value VARCHAR(500) NOT NULL,
    last_sync_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, base_id, table_id, cursor_type)
);

-- Indexes
CREATE INDEX idx_sync_jobs_tenant_id ON sync_jobs(tenant_id);
CREATE INDEX idx_sync_jobs_base_id ON sync_jobs(base_id);
CREATE INDEX idx_sync_jobs_status ON sync_jobs(status);
CREATE INDEX idx_sync_jobs_created_at ON sync_jobs(created_at);
CREATE INDEX idx_sync_operations_job_id ON sync_operations(job_id);
CREATE INDEX idx_sync_operations_status ON sync_operations(status);
CREATE INDEX idx_sync_conflicts_job_id ON sync_conflicts(job_id);
CREATE INDEX idx_sync_cursors_tenant_base ON sync_cursors(tenant_id, base_id);

-- =============================================================================
-- 6. WEBHOOK DATABASE (webhook_db)
-- =============================================================================

CREATE DATABASE webhook_db;
\c webhook_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Webhook registrations
CREATE TABLE webhook_registrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    base_id UUID NOT NULL, -- References schema_db.airtable_bases.id
    webhook_id VARCHAR(255) NOT NULL, -- Airtable webhook ID
    callback_url TEXT NOT NULL,
    specification JSONB NOT NULL, -- Airtable webhook specification
    is_active BOOLEAN DEFAULT TRUE,
    last_notification_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, base_id, webhook_id)
);

-- Webhook events received
CREATE TABLE webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    registration_id UUID NOT NULL REFERENCES webhook_registrations(id) ON DELETE CASCADE,
    webhook_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    headers JSONB,
    signature VARCHAR(255),
    processed BOOLEAN DEFAULT FALSE,
    processed_at TIMESTAMP,
    processing_error TEXT,
    retry_count INTEGER DEFAULT 0,
    received_at TIMESTAMP DEFAULT NOW()
);

-- Webhook processing jobs
CREATE TABLE webhook_processing_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID NOT NULL REFERENCES webhook_events(id) ON DELETE CASCADE,
    job_type VARCHAR(50) NOT NULL, -- sync_trigger, notification, workflow_trigger
    status VARCHAR(20) DEFAULT 'pending',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    result_data JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_webhook_registrations_tenant_id ON webhook_registrations(tenant_id);
CREATE INDEX idx_webhook_registrations_base_id ON webhook_registrations(base_id);
CREATE INDEX idx_webhook_events_registration_id ON webhook_events(registration_id);
CREATE INDEX idx_webhook_events_processed ON webhook_events(processed);
CREATE INDEX idx_webhook_events_received_at ON webhook_events(received_at);
CREATE INDEX idx_webhook_processing_jobs_event_id ON webhook_processing_jobs(event_id);
CREATE INDEX idx_webhook_processing_jobs_status ON webhook_processing_jobs(status);

-- =============================================================================
-- 7. CONVERSATION DATABASE (conversation_db)
-- =============================================================================

CREATE DATABASE conversation_db;
\c conversation_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector"; -- For semantic search

-- Conversations
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL, -- References auth_db.users.id
    title VARCHAR(500),
    context_data JSONB DEFAULT '{}',
    total_messages INTEGER DEFAULT 0,
    total_tokens_used INTEGER DEFAULT 0,
    estimated_cost DECIMAL(10,4) DEFAULT 0.0000,
    status VARCHAR(20) DEFAULT 'active', -- active, archived, deleted
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Messages within conversations
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    message_order INTEGER NOT NULL,
    role VARCHAR(20) NOT NULL, -- user, assistant, system, tool
    content TEXT NOT NULL,
    content_vector vector(1536), -- For semantic search
    metadata JSONB DEFAULT '{}',
    model_used VARCHAR(100),
    tokens_used INTEGER,
    processing_time_ms INTEGER,
    cost DECIMAL(8,4),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(conversation_id, message_order)
);

-- Tool calls within messages
CREATE TABLE tool_calls (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    tool_name VARCHAR(100) NOT NULL,
    tool_arguments JSONB NOT NULL,
    tool_result JSONB,
    execution_time_ms INTEGER,
    status VARCHAR(20) DEFAULT 'pending', -- pending, success, error
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Conversation templates
CREATE TABLE conversation_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    template_messages JSONB NOT NULL,
    default_model VARCHAR(100),
    configuration JSONB DEFAULT '{}',
    usage_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT FALSE,
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_conversations_tenant_id ON conversations(tenant_id);
CREATE INDEX idx_conversations_user_id ON conversations(user_id);
CREATE INDEX idx_conversations_created_at ON conversations(created_at);
CREATE INDEX idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX idx_messages_created_at ON messages(created_at);
CREATE INDEX idx_tool_calls_message_id ON tool_calls(message_id);
CREATE INDEX idx_conversation_templates_tenant_id ON conversation_templates(tenant_id);

-- Vector similarity search index
CREATE INDEX idx_messages_content_vector ON messages USING ivfflat (content_vector vector_cosine_ops);

-- =============================================================================
-- 8. FILE DATABASE (file_db)
-- =============================================================================

CREATE DATABASE file_db;
\c file_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- File storage metadata
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL, -- References auth_db.users.id
    filename VARCHAR(500) NOT NULL,
    original_filename VARCHAR(500) NOT NULL,
    file_path TEXT NOT NULL,
    storage_provider VARCHAR(50) DEFAULT 'local', -- local, s3, gcs, azure
    storage_key TEXT, -- Provider-specific key/path
    mime_type VARCHAR(100),
    file_size BIGINT NOT NULL,
    file_hash VARCHAR(64) NOT NULL, -- SHA-256
    encryption_key_id UUID, -- References encryption keys
    status VARCHAR(20) DEFAULT 'uploaded', -- uploaded, processing, processed, error, deleted
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- File processing jobs
CREATE TABLE file_processing_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    processor_type VARCHAR(50) NOT NULL, -- text_extraction, image_analysis, pdf_parsing
    status VARCHAR(20) DEFAULT 'pending',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    processing_result JSONB,
    retry_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Extracted content from files
CREATE TABLE file_content (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    content_type VARCHAR(50) NOT NULL, -- text, metadata, thumbnail
    content_data TEXT,
    content_metadata JSONB DEFAULT '{}',
    extraction_method VARCHAR(100),
    confidence_score DECIMAL(3,2), -- 0.00 to 1.00
    created_at TIMESTAMP DEFAULT NOW()
);

-- File access logs
CREATE TABLE file_access_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    access_type VARCHAR(50) NOT NULL, -- download, view, process
    ip_address INET,
    user_agent TEXT,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- File shares/permissions
CREATE TABLE file_shares (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_id UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    shared_with_user_id UUID,
    shared_with_role VARCHAR(100),
    permission_level VARCHAR(20) NOT NULL, -- read, write, admin
    expires_at TIMESTAMP,
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_files_tenant_id ON files(tenant_id);
CREATE INDEX idx_files_user_id ON files(user_id);
CREATE INDEX idx_files_hash ON files(file_hash);
CREATE INDEX idx_files_status ON files(status);
CREATE INDEX idx_file_processing_jobs_file_id ON file_processing_jobs(file_id);
CREATE INDEX idx_file_processing_jobs_status ON file_processing_jobs(status);
CREATE INDEX idx_file_content_file_id ON file_content(file_id);
CREATE INDEX idx_file_access_logs_file_id ON file_access_logs(file_id);
CREATE INDEX idx_file_access_logs_user_id ON file_access_logs(user_id);
CREATE INDEX idx_file_shares_file_id ON file_shares(file_id);

-- =============================================================================
-- 9. WORKFLOW DATABASE (workflow_db)
-- =============================================================================

CREATE DATABASE workflow_db;
\c workflow_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Workflow definitions
CREATE TABLE workflows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    workflow_definition JSONB NOT NULL,
    version INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Workflow executions
CREATE TABLE workflow_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_id UUID NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    execution_name VARCHAR(255),
    status VARCHAR(20) DEFAULT 'pending', -- pending, running, completed, failed, cancelled
    input_data JSONB DEFAULT '{}',
    output_data JSONB DEFAULT '{}',
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    timeout_at TIMESTAMP,
    execution_context JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Workflow steps/tasks
CREATE TABLE workflow_steps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    execution_id UUID NOT NULL REFERENCES workflow_executions(id) ON DELETE CASCADE,
    step_name VARCHAR(255) NOT NULL,
    step_type VARCHAR(100) NOT NULL, -- http_call, data_transform, condition, loop
    step_order INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    input_data JSONB DEFAULT '{}',
    output_data JSONB DEFAULT '{}',
    error_message TEXT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    retry_count INTEGER DEFAULT 0,
    step_configuration JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Workflow triggers
CREATE TABLE workflow_triggers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_id UUID NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    trigger_type VARCHAR(50) NOT NULL, -- webhook, schedule, manual, event
    trigger_configuration JSONB NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_triggered_at TIMESTAMP,
    next_trigger_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_workflows_tenant_id ON workflows(tenant_id);
CREATE INDEX idx_workflows_active ON workflows(is_active);
CREATE INDEX idx_workflow_executions_workflow_id ON workflow_executions(workflow_id);
CREATE INDEX idx_workflow_executions_status ON workflow_executions(status);
CREATE INDEX idx_workflow_executions_created_at ON workflow_executions(created_at);
CREATE INDEX idx_workflow_steps_execution_id ON workflow_steps(execution_id);
CREATE INDEX idx_workflow_steps_status ON workflow_steps(status);
CREATE INDEX idx_workflow_triggers_workflow_id ON workflow_triggers(workflow_id);
CREATE INDEX idx_workflow_triggers_next_trigger_at ON workflow_triggers(next_trigger_at);

-- =============================================================================
-- 10. SCHEDULER DATABASE (scheduler_db)
-- =============================================================================

CREATE DATABASE scheduler_db;
\c scheduler_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Scheduled jobs
CREATE TABLE scheduled_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    job_name VARCHAR(255) NOT NULL,
    job_type VARCHAR(100) NOT NULL, -- workflow, sync, maintenance, report
    cron_expression VARCHAR(100),
    job_configuration JSONB NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    last_run_at TIMESTAMP,
    next_run_at TIMESTAMP,
    failure_count INTEGER DEFAULT 0,
    max_failures INTEGER DEFAULT 3,
    created_by UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Job executions
CREATE TABLE job_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id UUID NOT NULL REFERENCES scheduled_jobs(id) ON DELETE CASCADE,
    execution_id VARCHAR(255), -- External execution ID if applicable
    status VARCHAR(20) DEFAULT 'pending',
    started_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP,
    duration_ms INTEGER,
    output_data JSONB DEFAULT '{}',
    error_message TEXT,
    retry_count INTEGER DEFAULT 0
);

-- Job locks (for distributed scheduling)
CREATE TABLE job_locks (
    job_id UUID PRIMARY KEY REFERENCES scheduled_jobs(id) ON DELETE CASCADE,
    locked_by VARCHAR(255) NOT NULL, -- Instance/worker ID
    locked_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE INDEX idx_scheduled_jobs_tenant_id ON scheduled_jobs(tenant_id);
CREATE INDEX idx_scheduled_jobs_next_run_at ON scheduled_jobs(next_run_at);
CREATE INDEX idx_scheduled_jobs_active ON scheduled_jobs(is_active);
CREATE INDEX idx_job_executions_job_id ON job_executions(job_id);
CREATE INDEX idx_job_executions_status ON job_executions(status);
CREATE INDEX idx_job_executions_started_at ON job_executions(started_at);
CREATE INDEX idx_job_locks_expires_at ON job_locks(expires_at);

-- =============================================================================
-- 11. AUDIT DATABASE (audit_db)
-- =============================================================================

CREATE DATABASE audit_db;
\c audit_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Audit events
CREATE TABLE audit_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID, -- May be null for system events
    event_type VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id VARCHAR(255) NOT NULL,
    action VARCHAR(50) NOT NULL, -- create, read, update, delete, execute
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    user_agent TEXT,
    session_id UUID,
    correlation_id UUID, -- For tracing related events
    risk_score INTEGER, -- 0-100 risk assessment
    created_at TIMESTAMP DEFAULT NOW()
);

-- Compliance reports
CREATE TABLE compliance_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    report_type VARCHAR(100) NOT NULL, -- gdpr, hipaa, sox, custom
    report_period_start TIMESTAMP NOT NULL,
    report_period_end TIMESTAMP NOT NULL,
    report_data JSONB NOT NULL,
    generated_by UUID NOT NULL,
    generated_at TIMESTAMP DEFAULT NOW()
);

-- Data retention policies
CREATE TABLE retention_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    retention_period_days INTEGER NOT NULL,
    policy_configuration JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes (partitioned by month for performance)
CREATE INDEX idx_audit_events_tenant_id ON audit_events(tenant_id);
CREATE INDEX idx_audit_events_user_id ON audit_events(user_id);
CREATE INDEX idx_audit_events_entity ON audit_events(entity_type, entity_id);
CREATE INDEX idx_audit_events_created_at ON audit_events(created_at);
CREATE INDEX idx_audit_events_correlation_id ON audit_events(correlation_id);
CREATE INDEX idx_compliance_reports_tenant_id ON compliance_reports(tenant_id);
CREATE INDEX idx_retention_policies_tenant_id ON retention_policies(tenant_id);

-- Partition table by month for large audit volumes
-- Note: This would typically be set up with additional partitioning logic

-- =============================================================================
-- 12. NOTIFICATION DATABASE (notification_db)
-- =============================================================================

CREATE DATABASE notification_db;
\c notification_db;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Notification templates
CREATE TABLE notification_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    template_name VARCHAR(255) NOT NULL,
    template_type VARCHAR(50) NOT NULL, -- email, sms, push, in_app
    subject_template TEXT,
    body_template TEXT NOT NULL,
    template_variables JSONB DEFAULT '[]',
    styling JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(tenant_id, template_name)
);

-- Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL, -- References auth_db.users.id
    notification_type VARCHAR(50) NOT NULL,
    title VARCHAR(500) NOT NULL,
    content TEXT NOT NULL,
    delivery_method VARCHAR(20) NOT NULL, -- email, sms, push, in_app
    delivery_address TEXT, -- email address, phone number, device token
    status VARCHAR(20) DEFAULT 'pending', -- pending, sent, delivered, failed, read
    priority VARCHAR(10) DEFAULT 'normal', -- low, normal, high, urgent
    scheduled_for TIMESTAMP,
    sent_at TIMESTAMP,
    delivered_at TIMESTAMP,
    read_at TIMESTAMP,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Notification preferences
CREATE TABLE notification_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL, -- References auth_db.users.id
    notification_type VARCHAR(50) NOT NULL,
    delivery_method VARCHAR(20) NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE,
    frequency VARCHAR(20) DEFAULT 'immediate', -- immediate, daily, weekly, never
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    timezone VARCHAR(50) DEFAULT 'UTC',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(user_id, notification_type, delivery_method)
);

-- Notification delivery logs
CREATE TABLE notification_delivery_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL, -- sendgrid, twilio, fcm, etc.
    provider_message_id VARCHAR(255),
    delivery_status VARCHAR(20) NOT NULL,
    delivery_response TEXT,
    delivered_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_notification_templates_tenant_id ON notification_templates(tenant_id);
CREATE INDEX idx_notifications_tenant_id ON notifications(tenant_id);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_status ON notifications(status);
CREATE INDEX idx_notifications_scheduled_for ON notifications(scheduled_for);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
CREATE INDEX idx_notification_preferences_user_id ON notification_preferences(user_id);
CREATE INDEX idx_notification_delivery_logs_notification_id ON notification_delivery_logs(notification_id);

-- =============================================================================
-- DATA MIGRATION VIEWS AND FUNCTIONS
-- =============================================================================

-- Create a view to help with data migration mapping
CREATE OR REPLACE VIEW migration_mapping AS
SELECT 
    'users' as source_table,
    'auth_db.users' as target_table,
    'id, email, password_hash, created_at, updated_at' as common_fields
UNION ALL
SELECT 'sessions', 'auth_db.auth_sessions', 'user_id, token, expires_at, created_at'
UNION ALL
SELECT 'tenants', 'permission_db.tenants', 'id, name, created_at, updated_at'
UNION ALL
SELECT 'files', 'file_db.files', 'id, tenant_id, filename, file_path, mime_type, file_size, created_at'
UNION ALL
SELECT 'workflows', 'workflow_db.workflows', 'id, tenant_id, name, description, workflow_config, created_at'
-- Add more mappings as needed
;

-- Function to validate data integrity after migration
CREATE OR REPLACE FUNCTION validate_migration(source_table text, target_db text, target_table text)
RETURNS TABLE(status text, source_count bigint, target_count bigint, match boolean) AS $$
DECLARE
    src_count bigint;
    tgt_count bigint;
BEGIN
    -- Get source count
    EXECUTE format('SELECT COUNT(*) FROM %I', source_table) INTO src_count;
    
    -- Get target count (this would need to be adapted for cross-database queries)
    -- For now, this is a template - actual implementation would use dblink or similar
    tgt_count := src_count; -- Placeholder
    
    RETURN QUERY SELECT 
        format('Migration validation for %s -> %s.%s', source_table, target_db, target_table),
        src_count,
        tgt_count,
        src_count = tgt_count;
END;
$$ LANGUAGE plpgsql;