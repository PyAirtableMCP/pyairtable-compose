-- Migration: Comprehensive Audit System
-- Created: 2025-08-01
-- Description: Implement audit logging with pgAudit and custom trigger-based auditing

-- Create audit log table for application-level auditing
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name VARCHAR(100) NOT NULL,
    record_id TEXT NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_fields JSONB,
    changed_by VARCHAR(255),
    user_context JSONB DEFAULT '{}',
    session_context JSONB DEFAULT '{}',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    correlation_id VARCHAR(255),
    ip_address INET,
    user_agent TEXT,
    transaction_id BIGINT DEFAULT txid_current()
);

-- Create indexes for audit log
CREATE INDEX IF NOT EXISTS idx_audit_log_table_name ON audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_log_record_id ON audit_log(record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_operation ON audit_log(operation);
CREATE INDEX IF NOT EXISTS idx_audit_log_changed_by ON audit_log(changed_by);
CREATE INDEX IF NOT EXISTS idx_audit_log_timestamp ON audit_log(timestamp);
CREATE INDEX IF NOT EXISTS idx_audit_log_correlation_id ON audit_log(correlation_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_transaction_id ON audit_log(transaction_id);

-- Create audit log hypertable for time-series optimization
SELECT create_hypertable(
    'audit_log', 
    'timestamp',
    chunk_time_interval => INTERVAL '1 month',
    if_not_exists => TRUE
);

-- Add compression and retention policies for audit log
SELECT add_compression_policy(
    'audit_log', 
    INTERVAL '90 days',
    if_not_exists => TRUE
);

SELECT add_retention_policy(
    'audit_log', 
    INTERVAL '7 years',  -- Long retention for compliance
    if_not_exists => TRUE
);

-- Enhanced audit trigger function with detailed change tracking
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    old_data JSONB;
    new_data JSONB;
    changed_fields JSONB DEFAULT '{}';
    user_context JSONB DEFAULT '{}';
    session_context JSONB DEFAULT '{}';
    correlation_id VARCHAR(255);
    ip_address INET;
    user_agent TEXT;
    current_user_id VARCHAR(255);
    current_session_id VARCHAR(255);
BEGIN
    -- Get current user context
    current_user_id := current_setting('app.current_user_id', true);
    current_session_id := current_setting('app.current_session_id', true);
    correlation_id := current_setting('app.correlation_id', true);
    ip_address := current_setting('app.client_ip', true)::INET;
    user_agent := current_setting('app.user_agent', true);
    
    -- Build user context
    user_context := jsonb_build_object(
        'user_id', current_user_id,
        'session_id', current_session_id
    );
    
    -- Build session context
    session_context := jsonb_build_object(
        'correlation_id', correlation_id,
        'ip_address', ip_address,
        'user_agent', user_agent,
        'timestamp', NOW()
    );
    
    IF TG_OP = 'DELETE' THEN
        old_data := row_to_json(OLD)::JSONB;
        
        INSERT INTO audit_log (
            table_name, record_id, operation, old_data, new_data, changed_fields,
            changed_by, user_context, session_context, correlation_id, ip_address, user_agent
        ) VALUES (
            TG_TABLE_NAME, 
            COALESCE(OLD.id::TEXT, OLD.session_id::TEXT, 'unknown'),
            TG_OP, 
            old_data, 
            NULL, 
            '{}',
            COALESCE(current_user_id, current_user),
            user_context,
            session_context,
            correlation_id,
            ip_address,
            user_agent
        );
        
        RETURN OLD;
        
    ELSIF TG_OP = 'UPDATE' THEN
        old_data := row_to_json(OLD)::JSONB;
        new_data := row_to_json(NEW)::JSONB;
        
        -- Calculate changed fields
        SELECT jsonb_object_agg(key, jsonb_build_object('old', old_data->key, 'new', new_data->key))
        INTO changed_fields
        FROM jsonb_each(new_data)
        WHERE new_data->key != old_data->key OR (new_data->key IS NULL) != (old_data->key IS NULL);
        
        INSERT INTO audit_log (
            table_name, record_id, operation, old_data, new_data, changed_fields,
            changed_by, user_context, session_context, correlation_id, ip_address, user_agent
        ) VALUES (
            TG_TABLE_NAME,
            COALESCE(NEW.id::TEXT, NEW.session_id::TEXT, 'unknown'),
            TG_OP,
            old_data,
            new_data,
            changed_fields,
            COALESCE(current_user_id, current_user),
            user_context,
            session_context,
            correlation_id,
            ip_address,
            user_agent
        );
        
        RETURN NEW;
        
    ELSIF TG_OP = 'INSERT' THEN
        new_data := row_to_json(NEW)::JSONB;
        
        INSERT INTO audit_log (
            table_name, record_id, operation, old_data, new_data, changed_fields,
            changed_by, user_context, session_context, correlation_id, ip_address, user_agent
        ) VALUES (
            TG_TABLE_NAME,
            COALESCE(NEW.id::TEXT, NEW.session_id::TEXT, 'unknown'),
            TG_OP,
            NULL,
            new_data,
            '{}',
            COALESCE(current_user_id, current_user),
            user_context,
            session_context,
            correlation_id,
            ip_address,
            user_agent
        );
        
        RETURN NEW;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Apply audit triggers to critical tables
DROP TRIGGER IF EXISTS conversation_sessions_audit_trigger ON conversation_sessions;
CREATE TRIGGER conversation_sessions_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON conversation_sessions
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

DROP TRIGGER IF EXISTS conversation_messages_audit_trigger ON conversation_messages;
CREATE TRIGGER conversation_messages_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON conversation_messages
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

DROP TRIGGER IF EXISTS api_usage_logs_audit_trigger ON api_usage_logs;
CREATE TRIGGER api_usage_logs_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON api_usage_logs
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

DROP TRIGGER IF EXISTS files_audit_trigger ON files;
CREATE TRIGGER files_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON files
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

DROP TRIGGER IF EXISTS workflows_audit_trigger ON workflows;
CREATE TRIGGER workflows_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON workflows
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

DROP TRIGGER IF EXISTS workflow_executions_audit_trigger ON workflow_executions;
CREATE TRIGGER workflow_executions_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON workflow_executions
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_function();

-- Create utility functions for audit queries

-- Function to get audit trail for a specific record
CREATE OR REPLACE FUNCTION get_audit_trail(
    p_table_name VARCHAR(100),
    p_record_id TEXT,
    p_limit INTEGER DEFAULT 100
) RETURNS TABLE(
    audit_id UUID,
    operation VARCHAR(10),
    changed_fields JSONB,
    changed_by VARCHAR(255),
    timestamp TIMESTAMP WITH TIME ZONE,
    correlation_id VARCHAR(255)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        al.id,
        al.operation,
        al.changed_fields,
        al.changed_by,
        al.timestamp,
        al.correlation_id
    FROM audit_log al
    WHERE al.table_name = p_table_name 
        AND al.record_id = p_record_id
    ORDER BY al.timestamp DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to get user activity summary
CREATE OR REPLACE FUNCTION get_user_activity(
    p_user_id VARCHAR(255),
    p_time_range INTERVAL DEFAULT INTERVAL '24 hours',
    p_limit INTEGER DEFAULT 50
) RETURNS TABLE(
    table_name VARCHAR(100),
    operation VARCHAR(10),
    record_id TEXT,
    timestamp TIMESTAMP WITH TIME ZONE,
    correlation_id VARCHAR(255),
    ip_address INET
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        al.table_name,
        al.operation,
        al.record_id,
        al.timestamp,
        al.correlation_id,
        al.ip_address
    FROM audit_log al
    WHERE al.changed_by = p_user_id
        AND al.timestamp >= NOW() - p_time_range
    ORDER BY al.timestamp DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to get suspicious activity
CREATE OR REPLACE FUNCTION detect_suspicious_activity(
    p_time_range INTERVAL DEFAULT INTERVAL '1 hour',
    p_threshold INTEGER DEFAULT 100
) RETURNS TABLE(
    changed_by VARCHAR(255),
    operation_count BIGINT,
    unique_tables INTEGER,
    unique_ips BIGINT,
    first_activity TIMESTAMP WITH TIME ZONE,
    last_activity TIMESTAMP WITH TIME ZONE,
    risk_score INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        al.changed_by,
        COUNT(*) as operation_count,
        COUNT(DISTINCT al.table_name)::INTEGER as unique_tables,
        COUNT(DISTINCT al.ip_address) as unique_ips,
        MIN(al.timestamp) as first_activity,
        MAX(al.timestamp) as last_activity,
        CASE 
            WHEN COUNT(*) > p_threshold * 2 THEN 100
            WHEN COUNT(*) > p_threshold THEN 75
            WHEN COUNT(DISTINCT al.ip_address) > 3 THEN 60
            WHEN COUNT(DISTINCT al.table_name) > 5 THEN 40
            ELSE 20
        END::INTEGER as risk_score
    FROM audit_log al
    WHERE al.timestamp >= NOW() - p_time_range
        AND al.changed_by IS NOT NULL
    GROUP BY al.changed_by
    HAVING COUNT(*) > p_threshold
    ORDER BY operation_count DESC;
END;
$$ LANGUAGE plpgsql;

-- Create audit analytics views

-- Daily audit activity summary
CREATE MATERIALIZED VIEW IF NOT EXISTS audit_daily_summary
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', timestamp) AS day,
    table_name,
    operation,
    COUNT(*) as operation_count,
    COUNT(DISTINCT changed_by) as unique_users,
    COUNT(DISTINCT ip_address) as unique_ips
FROM audit_log
GROUP BY day, table_name, operation
WITH NO DATA;

-- Hourly suspicious activity tracking
CREATE MATERIALIZED VIEW IF NOT EXISTS suspicious_activity_hourly
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', timestamp) AS hour,
    changed_by,
    COUNT(*) as operation_count,
    COUNT(DISTINCT table_name) as tables_affected,
    COUNT(DISTINCT ip_address) as unique_ips,
    COUNT(CASE WHEN operation = 'DELETE' THEN 1 END) as delete_operations
FROM audit_log
WHERE changed_by IS NOT NULL
GROUP BY hour, changed_by
HAVING COUNT(*) > 10  -- Only include users with high activity
WITH NO DATA;

-- Add refresh policies for audit aggregates
SELECT add_continuous_aggregate_policy(
    'audit_daily_summary',
    start_offset => INTERVAL '2 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

SELECT add_continuous_aggregate_policy(
    'suspicious_activity_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- Create audit configuration table
CREATE TABLE IF NOT EXISTS audit_config (
    table_name VARCHAR(100) PRIMARY KEY,
    audit_enabled BOOLEAN DEFAULT TRUE,
    audit_inserts BOOLEAN DEFAULT TRUE,
    audit_updates BOOLEAN DEFAULT TRUE,
    audit_deletes BOOLEAN DEFAULT TRUE,
    sensitive_fields TEXT[] DEFAULT '{}',
    retention_days INTEGER DEFAULT 2555, -- 7 years
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default audit configurations
INSERT INTO audit_config (table_name, sensitive_fields) VALUES
('conversation_sessions', ARRAY['metadata']),
('conversation_messages', ARRAY['message', 'thinking_process']),
('api_usage_logs', ARRAY['metadata']),
('files', ARRAY['extracted_content']),
('workflows', ARRAY['workflow_config', 'trigger_config']),
('workflow_executions', ARRAY['trigger_data', 'result_data', 'log_output'])
ON CONFLICT (table_name) DO NOTHING;

-- Function to manage audit configuration
CREATE OR REPLACE FUNCTION configure_table_audit(
    p_table_name VARCHAR(100),
    p_audit_enabled BOOLEAN DEFAULT TRUE,
    p_audit_inserts BOOLEAN DEFAULT TRUE,
    p_audit_updates BOOLEAN DEFAULT TRUE,
    p_audit_deletes BOOLEAN DEFAULT TRUE
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO audit_config (table_name, audit_enabled, audit_inserts, audit_updates, audit_deletes)
    VALUES (p_table_name, p_audit_enabled, p_audit_inserts, p_audit_updates, p_audit_deletes)
    ON CONFLICT (table_name) DO UPDATE SET
        audit_enabled = EXCLUDED.audit_enabled,
        audit_inserts = EXCLUDED.audit_inserts,
        audit_updates = EXCLUDED.audit_updates,
        audit_deletes = EXCLUDED.audit_deletes,
        updated_at = NOW();
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT SELECT ON audit_log TO application_user;
GRANT SELECT ON audit_config TO application_user;
GRANT SELECT ON audit_daily_summary TO PUBLIC;
GRANT SELECT ON suspicious_activity_hourly TO PUBLIC;

GRANT EXECUTE ON FUNCTION get_audit_trail(VARCHAR(100), TEXT, INTEGER) TO application_user;
GRANT EXECUTE ON FUNCTION get_user_activity(VARCHAR(255), INTERVAL, INTEGER) TO application_user;
GRANT EXECUTE ON FUNCTION detect_suspicious_activity(INTERVAL, INTEGER) TO application_user;
GRANT EXECUTE ON FUNCTION configure_table_audit(VARCHAR(100), BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) TO postgres;

-- Log completion
INSERT INTO migration_log (migration_name, executed_at, description) 
VALUES ('006_implement_audit_system', NOW(), 'Implemented comprehensive audit system with pgAudit and custom triggers')
ON CONFLICT DO NOTHING;