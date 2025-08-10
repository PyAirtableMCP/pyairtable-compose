-- Migration: 004_create_audit_logs.up.sql
-- Description: Create audit logs table for security events and user activity tracking
-- Based on: AUTHENTICATION_ARCHITECTURE.md security requirements
-- PostgreSQL: PyAirtable Sprint 1 - Security Audit Schema

-- Create audit_logs table for comprehensive security event tracking
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,  -- nullable for system events or anonymous events
    session_id UUID,  -- nullable, references user_sessions.id
    event_type VARCHAR(50) NOT NULL,
    event_category VARCHAR(30) NOT NULL,
    event_description TEXT NOT NULL,
    resource_type VARCHAR(50),
    resource_id VARCHAR(255),
    
    -- Request/Response details
    ip_address INET,
    user_agent TEXT,
    request_method VARCHAR(10),
    request_path VARCHAR(500),
    request_id VARCHAR(36),
    
    -- Event outcome and metadata
    success BOOLEAN DEFAULT true,
    error_code VARCHAR(50),
    error_message TEXT,
    metadata JSONB DEFAULT '{}',
    
    -- Timing and location
    occurred_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Risk assessment
    risk_level VARCHAR(10) DEFAULT 'low',
    anomaly_score DECIMAL(5,2) DEFAULT 0.0,
    
    -- Constraints
    CONSTRAINT valid_event_category CHECK (event_category IN (
        'authentication', 'authorization', 'data_access', 'data_modification',
        'admin_action', 'security_event', 'system_event', 'user_action'
    )),
    CONSTRAINT valid_risk_level CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    CONSTRAINT valid_anomaly_score CHECK (anomaly_score >= 0.0 AND anomaly_score <= 100.0),
    CONSTRAINT valid_processing_time CHECK (processed_at >= occurred_at)
);

-- Create indexes for performance and security analysis
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_session_id ON audit_logs(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_type ON audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_event_category ON audit_logs(event_category);
CREATE INDEX IF NOT EXISTS idx_audit_logs_occurred_at ON audit_logs(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_ip_address ON audit_logs(ip_address) WHERE ip_address IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_success ON audit_logs(success);
CREATE INDEX IF NOT EXISTS idx_audit_logs_risk_level ON audit_logs(risk_level) WHERE risk_level != 'low';
CREATE INDEX IF NOT EXISTS idx_audit_logs_anomaly_score ON audit_logs(anomaly_score) WHERE anomaly_score > 50.0;
CREATE INDEX IF NOT EXISTS idx_audit_logs_request_id ON audit_logs(request_id) WHERE request_id IS NOT NULL;

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_event_time ON audit_logs(user_id, event_type, occurred_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_ip_event_time ON audit_logs(ip_address, event_type, occurred_at DESC) WHERE ip_address IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_security_events ON audit_logs(event_category, risk_level, occurred_at DESC) 
    WHERE event_category IN ('security_event', 'authentication') AND risk_level != 'low';

-- Create foreign key constraints (optional, for referential integrity)
ALTER TABLE audit_logs 
ADD CONSTRAINT fk_audit_logs_user_id 
FOREIGN KEY (user_id) REFERENCES users(id) 
ON DELETE SET NULL ON UPDATE CASCADE;

-- Note: session_id FK will be added after user_sessions table exists
-- ALTER TABLE audit_logs 
-- ADD CONSTRAINT fk_audit_logs_session_id 
-- FOREIGN KEY (session_id) REFERENCES user_sessions(id) 
-- ON DELETE SET NULL ON UPDATE CASCADE;

-- Function to log security events
CREATE OR REPLACE FUNCTION log_security_event(
    p_user_id UUID DEFAULT NULL,
    p_session_id UUID DEFAULT NULL,
    p_event_type VARCHAR(50),
    p_event_category VARCHAR(30),
    p_event_description TEXT,
    p_resource_type VARCHAR(50) DEFAULT NULL,
    p_resource_id VARCHAR(255) DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_request_method VARCHAR(10) DEFAULT NULL,
    p_request_path VARCHAR(500) DEFAULT NULL,
    p_request_id VARCHAR(36) DEFAULT NULL,
    p_success BOOLEAN DEFAULT true,
    p_error_code VARCHAR(50) DEFAULT NULL,
    p_error_message TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}',
    p_risk_level VARCHAR(10) DEFAULT 'low',
    p_anomaly_score DECIMAL(5,2) DEFAULT 0.0
) RETURNS UUID AS $$
DECLARE
    log_id UUID;
BEGIN
    INSERT INTO audit_logs (
        user_id, session_id, event_type, event_category, event_description,
        resource_type, resource_id, ip_address, user_agent, request_method,
        request_path, request_id, success, error_code, error_message,
        metadata, risk_level, anomaly_score
    ) VALUES (
        p_user_id, p_session_id, p_event_type, p_event_category, p_event_description,
        p_resource_type, p_resource_id, p_ip_address, p_user_agent, p_request_method,
        p_request_path, p_request_id, p_success, p_error_code, p_error_message,
        p_metadata, p_risk_level, p_anomaly_score
    ) RETURNING id INTO log_id;
    
    RETURN log_id;
END;
$$ LANGUAGE plpgsql;

-- Function to get security events for a user
CREATE OR REPLACE FUNCTION get_user_security_events(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_event_category VARCHAR(30) DEFAULT NULL
) RETURNS TABLE(
    id UUID,
    event_type VARCHAR(50),
    event_category VARCHAR(30),
    event_description TEXT,
    occurred_at TIMESTAMP WITH TIME ZONE,
    ip_address INET,
    success BOOLEAN,
    risk_level VARCHAR(10),
    metadata JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        al.id,
        al.event_type,
        al.event_category,
        al.event_description,
        al.occurred_at,
        al.ip_address,
        al.success,
        al.risk_level,
        al.metadata
    FROM audit_logs al
    WHERE al.user_id = p_user_id
      AND (p_event_category IS NULL OR al.event_category = p_event_category)
    ORDER BY al.occurred_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- Function to detect suspicious activity patterns
CREATE OR REPLACE FUNCTION detect_suspicious_activity(
    p_time_window INTERVAL DEFAULT '1 hour',
    p_threshold INTEGER DEFAULT 5
) RETURNS TABLE(
    ip_address INET,
    user_id UUID,
    user_email VARCHAR(255),
    failed_attempts INTEGER,
    first_attempt TIMESTAMP WITH TIME ZONE,
    last_attempt TIMESTAMP WITH TIME ZONE,
    risk_assessment TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH suspicious_ips AS (
        SELECT 
            al.ip_address,
            al.user_id,
            COUNT(*) as failed_attempts,
            MIN(al.occurred_at) as first_attempt,
            MAX(al.occurred_at) as last_attempt
        FROM audit_logs al
        WHERE al.event_type IN ('login_failed', 'password_reset_failed', 'token_validation_failed')
          AND al.occurred_at >= CURRENT_TIMESTAMP - p_time_window
          AND al.success = false
        GROUP BY al.ip_address, al.user_id
        HAVING COUNT(*) >= p_threshold
    )
    SELECT 
        si.ip_address,
        si.user_id,
        COALESCE(u.email, 'unknown') as user_email,
        si.failed_attempts::INTEGER,
        si.first_attempt,
        si.last_attempt,
        CASE 
            WHEN si.failed_attempts >= p_threshold * 3 THEN 'CRITICAL - Possible brute force attack'
            WHEN si.failed_attempts >= p_threshold * 2 THEN 'HIGH - Multiple failed attempts'
            ELSE 'MEDIUM - Elevated failed attempts'
        END as risk_assessment
    FROM suspicious_ips si
    LEFT JOIN users u ON si.user_id = u.id
    ORDER BY si.failed_attempts DESC, si.last_attempt DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup old audit logs (run periodically)
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs(
    p_retention_period INTERVAL DEFAULT '365 days',
    p_batch_size INTEGER DEFAULT 10000
) RETURNS INTEGER AS $$
DECLARE
    total_deleted INTEGER := 0;
    batch_deleted INTEGER;
BEGIN
    LOOP
        DELETE FROM audit_logs 
        WHERE id IN (
            SELECT id FROM audit_logs 
            WHERE occurred_at <= CURRENT_TIMESTAMP - p_retention_period
              AND risk_level = 'low'  -- Keep high-risk events longer
            ORDER BY occurred_at 
            LIMIT p_batch_size
        );
        
        GET DIAGNOSTICS batch_deleted = ROW_COUNT;
        total_deleted := total_deleted + batch_deleted;
        
        EXIT WHEN batch_deleted = 0;
        
        -- Small delay between batches to avoid blocking
        PERFORM pg_sleep(0.1);
    END LOOP;
    
    RETURN total_deleted;
END;
$$ LANGUAGE plpgsql;

-- Create views for common audit queries
CREATE OR REPLACE VIEW security_events_summary AS
SELECT 
    DATE(occurred_at) as event_date,
    event_category,
    event_type,
    risk_level,
    COUNT(*) as event_count,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT ip_address) as unique_ips,
    COUNT(CASE WHEN success = false THEN 1 END) as failed_events,
    AVG(anomaly_score) as avg_anomaly_score
FROM audit_logs
WHERE occurred_at >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY DATE(occurred_at), event_category, event_type, risk_level
ORDER BY event_date DESC, event_count DESC;

CREATE OR REPLACE VIEW high_risk_events AS
SELECT 
    al.id,
    al.user_id,
    u.email,
    al.event_type,
    al.event_description,
    al.ip_address,
    al.occurred_at,
    al.risk_level,
    al.anomaly_score,
    al.metadata
FROM audit_logs al
LEFT JOIN users u ON al.user_id = u.id
WHERE al.risk_level IN ('high', 'critical') 
   OR al.anomaly_score > 75.0
   OR (al.success = false AND al.event_category = 'authentication')
ORDER BY al.occurred_at DESC;

CREATE OR REPLACE VIEW user_activity_summary AS
SELECT 
    u.id as user_id,
    u.email,
    u.first_name,
    u.last_name,
    COUNT(al.id) as total_events,
    COUNT(CASE WHEN al.success = false THEN 1 END) as failed_events,
    MAX(al.occurred_at) as last_activity,
    COUNT(DISTINCT al.ip_address) as unique_ips_used,
    AVG(al.anomaly_score) as avg_anomaly_score
FROM users u
LEFT JOIN audit_logs al ON u.id = al.user_id
WHERE al.occurred_at >= CURRENT_DATE - INTERVAL '30 days'
   OR al.occurred_at IS NULL
GROUP BY u.id, u.email, u.first_name, u.last_name
ORDER BY total_events DESC, last_activity DESC;

-- Create trigger to automatically log user table changes
CREATE OR REPLACE FUNCTION log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM log_security_event(
            NEW.id,
            NULL,
            'user_created',
            'user_action',
            'New user account created: ' || NEW.email,
            'user',
            NEW.id::text,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            true,
            NULL,
            NULL,
            jsonb_build_object('role', NEW.role, 'email_verified', NEW.email_verified),
            'low'
        );
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Log significant changes
        IF OLD.password_hash != NEW.password_hash THEN
            PERFORM log_security_event(
                NEW.id,
                NULL,
                'password_changed',
                'security_event',
                'User password changed: ' || NEW.email,
                'user',
                NEW.id::text,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('old_password_changed_at', OLD.password_changed_at),
                'medium'
            );
        END IF;
        
        IF OLD.email != NEW.email THEN
            PERFORM log_security_event(
                NEW.id,
                NULL,
                'email_changed',
                'security_event',
                'User email changed from ' || OLD.email || ' to ' || NEW.email,
                'user',
                NEW.id::text,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('old_email', OLD.email, 'new_email', NEW.email),
                'medium'
            );
        END IF;
        
        IF OLD.role != NEW.role THEN
            PERFORM log_security_event(
                NEW.id,
                NULL,
                'role_changed',
                'security_event',
                'User role changed from ' || OLD.role || ' to ' || NEW.role || ' for ' || NEW.email,
                'user',
                NEW.id::text,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('old_role', OLD.role, 'new_role', NEW.role),
                'high'
            );
        END IF;
        
        IF OLD.is_active != NEW.is_active THEN
            PERFORM log_security_event(
                NEW.id,
                NULL,
                CASE WHEN NEW.is_active THEN 'user_activated' ELSE 'user_deactivated' END,
                'admin_action',
                'User account ' || CASE WHEN NEW.is_active THEN 'activated' ELSE 'deactivated' END || ': ' || NEW.email,
                'user',
                NEW.id::text,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('was_active', OLD.is_active, 'now_active', NEW.is_active),
                'medium'
            );
        END IF;
        
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM log_security_event(
            OLD.id,
            NULL,
            'user_deleted',
            'admin_action',
            'User account deleted: ' || OLD.email,
            'user',
            OLD.id::text,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            true,
            NULL,
            NULL,
            jsonb_build_object('email', OLD.email, 'role', OLD.role),
            'high'
        );
        RETURN OLD;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for user changes
CREATE TRIGGER audit_user_changes
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION log_user_changes();

-- Comments for documentation
COMMENT ON TABLE audit_logs IS 'Comprehensive audit log for security events and user activities';
COMMENT ON COLUMN audit_logs.id IS 'Unique audit log entry identifier';
COMMENT ON COLUMN audit_logs.user_id IS 'User associated with event (nullable for system events)';
COMMENT ON COLUMN audit_logs.session_id IS 'Session associated with event (nullable)';
COMMENT ON COLUMN audit_logs.event_type IS 'Specific type of event (login_success, data_access, etc.)';
COMMENT ON COLUMN audit_logs.event_category IS 'Category of event (authentication, security_event, etc.)';
COMMENT ON COLUMN audit_logs.event_description IS 'Human-readable description of the event';
COMMENT ON COLUMN audit_logs.resource_type IS 'Type of resource accessed/modified';
COMMENT ON COLUMN audit_logs.resource_id IS 'ID of specific resource accessed/modified';
COMMENT ON COLUMN audit_logs.ip_address IS 'Client IP address';
COMMENT ON COLUMN audit_logs.user_agent IS 'Client user agent string';
COMMENT ON COLUMN audit_logs.request_method IS 'HTTP method (GET, POST, etc.)';
COMMENT ON COLUMN audit_logs.request_path IS 'Request path/endpoint';
COMMENT ON COLUMN audit_logs.request_id IS 'Unique request identifier for correlation';
COMMENT ON COLUMN audit_logs.success IS 'Whether the event/operation succeeded';
COMMENT ON COLUMN audit_logs.error_code IS 'Error code if operation failed';
COMMENT ON COLUMN audit_logs.error_message IS 'Error message if operation failed';
COMMENT ON COLUMN audit_logs.metadata IS 'Additional structured data about the event';
COMMENT ON COLUMN audit_logs.occurred_at IS 'When the event occurred';
COMMENT ON COLUMN audit_logs.processed_at IS 'When the audit log was created';
COMMENT ON COLUMN audit_logs.risk_level IS 'Assessed risk level: low, medium, high, critical';
COMMENT ON COLUMN audit_logs.anomaly_score IS 'Anomaly detection score (0-100)';

COMMENT ON FUNCTION log_security_event IS 'Log a security event with comprehensive metadata';
COMMENT ON FUNCTION get_user_security_events IS 'Get security events for a specific user';
COMMENT ON FUNCTION detect_suspicious_activity IS 'Detect suspicious activity patterns';
COMMENT ON FUNCTION cleanup_old_audit_logs IS 'Clean up old audit logs with retention policy';

COMMENT ON VIEW security_events_summary IS 'Daily summary of security events by type and risk level';
COMMENT ON VIEW high_risk_events IS 'View of high-risk security events requiring attention';
COMMENT ON VIEW user_activity_summary IS 'Summary of user activity and security metrics';

-- Grant permissions (adjust as needed)
-- GRANT SELECT, INSERT ON audit_logs TO pyairtable_app;
-- GRANT SELECT ON security_events_summary TO pyairtable_app;
-- GRANT SELECT ON high_risk_events TO pyairtable_admin;
-- GRANT SELECT ON user_activity_summary TO pyairtable_admin;
-- GRANT EXECUTE ON FUNCTION log_security_event TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION get_user_security_events TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION detect_suspicious_activity TO pyairtable_admin;

-- Migration completed
INSERT INTO migration_log (version, description, applied_at) 
VALUES ('004', 'Create audit logs table for security events', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;