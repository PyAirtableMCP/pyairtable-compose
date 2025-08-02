-- Migration: Row Level Security Implementation
-- Created: 2025-08-01
-- Description: Implement multi-tenant data isolation using PostgreSQL Row Level Security

-- Create application roles for RLS
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'application_user') THEN
        CREATE ROLE application_user;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_user') THEN
        CREATE ROLE admin_user;
    END IF;
END
$$;

-- Enable Row Level Security on user-specific tables
ALTER TABLE conversation_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE files ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflow_executions ENABLE ROW LEVEL SECURITY;

-- Create security context management functions

-- Function to set user context (called by application)
CREATE OR REPLACE FUNCTION set_user_context(
    p_user_id TEXT,
    p_session_id TEXT DEFAULT NULL,
    p_correlation_id TEXT DEFAULT NULL,
    p_client_ip TEXT DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id, true);
    
    IF p_session_id IS NOT NULL THEN
        PERFORM set_config('app.current_session_id', p_session_id, true);
    END IF;
    
    IF p_correlation_id IS NOT NULL THEN
        PERFORM set_config('app.correlation_id', p_correlation_id, true);
    END IF;
    
    IF p_client_ip IS NOT NULL THEN
        PERFORM set_config('app.client_ip', p_client_ip, true);
    END IF;
    
    IF p_user_agent IS NOT NULL THEN
        PERFORM set_config('app.user_agent', p_user_agent, true);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get current user context
CREATE OR REPLACE FUNCTION get_current_user_id() 
RETURNS TEXT AS $$
BEGIN
    RETURN current_setting('app.current_user_id', true);
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION is_admin_user() 
RETURNS BOOLEAN AS $$
BEGIN
    RETURN current_setting('app.current_user_id', true) IN (
        SELECT admin_user_id FROM admin_users WHERE is_active = true
    );
EXCEPTION
    WHEN others THEN
        RETURN false;
END;
$$ LANGUAGE plpgsql STABLE;

-- Create admin users table
CREATE TABLE IF NOT EXISTS admin_users (
    admin_user_id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    permissions JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default admin (replace with actual admin user ID)
INSERT INTO admin_users (admin_user_id, name, email, permissions) VALUES
('admin-001', 'System Administrator', 'admin@pyairtable.com', '{"can_view_all": true, "can_audit": true}')
ON CONFLICT (admin_user_id) DO NOTHING;

-- Create RLS policies for conversation_sessions
CREATE POLICY user_session_isolation_policy ON conversation_sessions
    FOR ALL TO application_user
    USING (
        user_id = get_current_user_id() 
        OR is_admin_user()
    );

-- Allow application_user to insert their own sessions
CREATE POLICY user_session_insert_policy ON conversation_sessions
    FOR INSERT TO application_user
    WITH CHECK (
        user_id = get_current_user_id()
        OR is_admin_user()
    );

-- Create RLS policies for conversation_messages
CREATE POLICY user_message_isolation_policy ON conversation_messages
    FOR ALL TO application_user
    USING (
        session_id IN (
            SELECT session_id FROM conversation_sessions 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Allow application_user to insert messages for their sessions
CREATE POLICY user_message_insert_policy ON conversation_messages
    FOR INSERT TO application_user
    WITH CHECK (
        session_id IN (
            SELECT session_id FROM conversation_sessions 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Create RLS policies for api_usage_logs
CREATE POLICY user_api_logs_isolation_policy ON api_usage_logs
    FOR ALL TO application_user
    USING (
        user_id = get_current_user_id()
        OR session_id IN (
            SELECT session_id FROM conversation_sessions 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Allow application_user to insert their own API usage logs
CREATE POLICY user_api_logs_insert_policy ON api_usage_logs
    FOR INSERT TO application_user
    WITH CHECK (
        user_id = get_current_user_id()
        OR session_id IN (
            SELECT session_id FROM conversation_sessions 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Create user_files junction table for file ownership
CREATE TABLE IF NOT EXISTS user_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255) NOT NULL,
    file_id INTEGER NOT NULL REFERENCES files(id),
    permission_level VARCHAR(20) DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, file_id)
);

-- Create index for user_files
CREATE INDEX IF NOT EXISTS idx_user_files_user_id ON user_files(user_id);
CREATE INDEX IF NOT EXISTS idx_user_files_file_id ON user_files(file_id);

-- Create RLS policies for files
CREATE POLICY user_files_isolation_policy ON files
    FOR ALL TO application_user
    USING (
        id IN (
            SELECT file_id FROM user_files 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Allow application_user to insert files (will be associated via trigger)
CREATE POLICY user_files_insert_policy ON files
    FOR INSERT TO application_user
    WITH CHECK (true);  -- Will be restricted by trigger

-- Create trigger to automatically associate files with users
CREATE OR REPLACE FUNCTION associate_file_with_user()
RETURNS TRIGGER AS $$
DECLARE
    current_user_id TEXT;
BEGIN
    current_user_id := get_current_user_id();
    
    IF current_user_id IS NOT NULL THEN
        INSERT INTO user_files (user_id, file_id, permission_level)
        VALUES (current_user_id, NEW.id, 'owner')
        ON CONFLICT (user_id, file_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS associate_file_trigger ON files;
CREATE TRIGGER associate_file_trigger
    AFTER INSERT ON files
    FOR EACH ROW EXECUTE FUNCTION associate_file_with_user();

-- Create user_workflows junction table for workflow ownership
CREATE TABLE IF NOT EXISTS user_workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255) NOT NULL,
    workflow_id INTEGER NOT NULL REFERENCES workflows(id),
    permission_level VARCHAR(20) DEFAULT 'owner',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, workflow_id)
);

-- Create index for user_workflows
CREATE INDEX IF NOT EXISTS idx_user_workflows_user_id ON user_workflows(user_id);
CREATE INDEX IF NOT EXISTS idx_user_workflows_workflow_id ON user_workflows(workflow_id);

-- Create RLS policies for workflows
CREATE POLICY user_workflows_isolation_policy ON workflows
    FOR ALL TO application_user
    USING (
        id IN (
            SELECT workflow_id FROM user_workflows 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Allow application_user to insert workflows
CREATE POLICY user_workflows_insert_policy ON workflows
    FOR INSERT TO application_user
    WITH CHECK (true);

-- Create trigger to automatically associate workflows with users
CREATE OR REPLACE FUNCTION associate_workflow_with_user()
RETURNS TRIGGER AS $$
DECLARE
    current_user_id TEXT;
BEGIN
    current_user_id := get_current_user_id();
    
    IF current_user_id IS NOT NULL THEN
        INSERT INTO user_workflows (user_id, workflow_id, permission_level)
        VALUES (current_user_id, NEW.id, 'owner')
        ON CONFLICT (user_id, workflow_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS associate_workflow_trigger ON workflows;
CREATE TRIGGER associate_workflow_trigger
    AFTER INSERT ON workflows
    FOR EACH ROW EXECUTE FUNCTION associate_workflow_with_user();

-- Create RLS policies for workflow_executions
CREATE POLICY user_workflow_executions_isolation_policy ON workflow_executions
    FOR ALL TO application_user
    USING (
        workflow_id IN (
            SELECT workflow_id FROM user_workflows 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Allow application_user to insert executions for their workflows
CREATE POLICY user_workflow_executions_insert_policy ON workflow_executions
    FOR INSERT TO application_user
    WITH CHECK (
        workflow_id IN (
            SELECT workflow_id FROM user_workflows 
            WHERE user_id = get_current_user_id()
        )
        OR is_admin_user()
    );

-- Create performance optimization indexes for RLS
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_user_id_rls 
ON conversation_sessions(user_id) WHERE user_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_logs_user_id_rls 
ON api_usage_logs(user_id) WHERE user_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_logs_session_id_rls 
ON api_usage_logs(session_id) WHERE session_id IS NOT NULL;

-- Create utility functions for RLS management

-- Function to grant file access to another user
CREATE OR REPLACE FUNCTION grant_file_access(
    p_file_id INTEGER,
    p_target_user_id VARCHAR(255),
    p_permission_level VARCHAR(20) DEFAULT 'read'
) RETURNS BOOLEAN AS $$
DECLARE
    current_user_id TEXT;
    is_owner BOOLEAN;
BEGIN
    current_user_id := get_current_user_id();
    
    -- Check if current user owns the file
    SELECT EXISTS(
        SELECT 1 FROM user_files 
        WHERE user_id = current_user_id 
            AND file_id = p_file_id 
            AND permission_level = 'owner'
    ) INTO is_owner;
    
    IF NOT is_owner AND NOT is_admin_user() THEN
        RAISE EXCEPTION 'Permission denied: You do not own this file';
    END IF;
    
    INSERT INTO user_files (user_id, file_id, permission_level)
    VALUES (p_target_user_id, p_file_id, p_permission_level)
    ON CONFLICT (user_id, file_id) DO UPDATE SET
        permission_level = EXCLUDED.permission_level;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to revoke file access
CREATE OR REPLACE FUNCTION revoke_file_access(
    p_file_id INTEGER,
    p_target_user_id VARCHAR(255)
) RETURNS BOOLEAN AS $$
DECLARE
    current_user_id TEXT;
    is_owner BOOLEAN;
BEGIN
    current_user_id := get_current_user_id();
    
    -- Check if current user owns the file
    SELECT EXISTS(
        SELECT 1 FROM user_files 
        WHERE user_id = current_user_id 
            AND file_id = p_file_id 
            AND permission_level = 'owner'
    ) INTO is_owner;
    
    IF NOT is_owner AND NOT is_admin_user() THEN
        RAISE EXCEPTION 'Permission denied: You do not own this file';
    END IF;
    
    -- Don't allow revoking owner access
    IF p_target_user_id = current_user_id THEN
        RAISE EXCEPTION 'Cannot revoke owner access';
    END IF;
    
    DELETE FROM user_files 
    WHERE user_id = p_target_user_id AND file_id = p_file_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Create RLS monitoring views

-- View to monitor RLS policy performance
CREATE OR REPLACE VIEW rls_performance_stats AS
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    ROUND(
        CASE 
            WHEN seq_scan + idx_scan > 0 
            THEN (idx_scan::DECIMAL / (seq_scan + idx_scan)) * 100 
            ELSE 0 
        END, 2
    ) as index_usage_percent
FROM pg_stat_user_tables 
WHERE tablename IN (
    'conversation_sessions', 'conversation_messages', 
    'api_usage_logs', 'files', 'workflows', 'workflow_executions'
)
ORDER BY seq_scan DESC;

-- View to monitor user access patterns
CREATE OR REPLACE VIEW user_access_patterns AS
SELECT 
    user_id,
    COUNT(DISTINCT session_id) as unique_sessions,
    COUNT(*) as total_sessions,
    MIN(created_at) as first_session,
    MAX(last_activity) as last_activity,
    AVG(total_messages) as avg_messages_per_session,
    SUM(CAST(total_cost AS DECIMAL(10,6))) as total_cost
FROM conversation_sessions
WHERE user_id IS NOT NULL
GROUP BY user_id
ORDER BY total_sessions DESC;

-- Grant appropriate permissions
GRANT USAGE ON SCHEMA public TO application_user;
GRANT USAGE ON SCHEMA public TO admin_user;

-- Grant table permissions to application_user
GRANT SELECT, INSERT, UPDATE, DELETE ON conversation_sessions TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON conversation_messages TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON api_usage_logs TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON files TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON workflows TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON workflow_executions TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_files TO application_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON user_workflows TO application_user;

-- Grant function permissions
GRANT EXECUTE ON FUNCTION set_user_context(TEXT, TEXT, TEXT, TEXT, TEXT) TO application_user;
GRANT EXECUTE ON FUNCTION get_current_user_id() TO application_user;
GRANT EXECUTE ON FUNCTION is_admin_user() TO application_user;
GRANT EXECUTE ON FUNCTION grant_file_access(INTEGER, VARCHAR(255), VARCHAR(20)) TO application_user;
GRANT EXECUTE ON FUNCTION revoke_file_access(INTEGER, VARCHAR(255)) TO application_user;

-- Grant admin permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO admin_user;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO admin_user;

-- Grant view permissions
GRANT SELECT ON rls_performance_stats TO PUBLIC;
GRANT SELECT ON user_access_patterns TO application_user;

-- Log completion
INSERT INTO migration_log (migration_name, executed_at, description) 
VALUES ('007_implement_row_level_security', NOW(), 'Implemented Row Level Security for multi-tenant data isolation')
ON CONFLICT DO NOTHING;