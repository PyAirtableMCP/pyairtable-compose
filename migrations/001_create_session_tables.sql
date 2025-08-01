-- Migration: Create conversation session tables
-- Created: 2025-08-01
-- Description: Add PostgreSQL tables for conversation sessions, messages, and API usage tracking

-- Create conversation_sessions table
CREATE TABLE IF NOT EXISTS conversation_sessions (
    session_id VARCHAR(255) PRIMARY KEY,
    user_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,
    base_id VARCHAR(255),
    thinking_budget INTEGER DEFAULT 5,
    max_tokens INTEGER DEFAULT 4000,
    temperature VARCHAR(10) DEFAULT '0.1',
    is_active BOOLEAN DEFAULT TRUE,
    total_messages INTEGER DEFAULT 0,
    total_tokens_used INTEGER DEFAULT 0,
    total_cost VARCHAR(20) DEFAULT '0.00',
    metadata JSONB DEFAULT '{}'
);

-- Create indexes for conversation_sessions
CREATE INDEX IF NOT EXISTS ix_conversation_sessions_session_id ON conversation_sessions (session_id);
CREATE INDEX IF NOT EXISTS ix_conversation_sessions_user_id ON conversation_sessions (user_id);
CREATE INDEX IF NOT EXISTS ix_conversation_sessions_is_active ON conversation_sessions (is_active);
CREATE INDEX IF NOT EXISTS ix_conversation_sessions_expires_at ON conversation_sessions (expires_at);
CREATE INDEX IF NOT EXISTS ix_session_user_created ON conversation_sessions (user_id, created_at);
CREATE INDEX IF NOT EXISTS ix_session_activity_active ON conversation_sessions (last_activity, is_active);

-- Create conversation_messages table
CREATE TABLE IF NOT EXISTS conversation_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    tools_used JSONB DEFAULT '[]',
    token_count INTEGER DEFAULT 0,
    cost VARCHAR(20) DEFAULT '0.00',
    thinking_process TEXT,
    response_time_ms INTEGER,
    model_used VARCHAR(100),
    metadata JSONB DEFAULT '{}'
);

-- Create indexes for conversation_messages
CREATE INDEX IF NOT EXISTS ix_conversation_messages_id ON conversation_messages (id);
CREATE INDEX IF NOT EXISTS ix_conversation_messages_session_id ON conversation_messages (session_id);
CREATE INDEX IF NOT EXISTS ix_conversation_messages_role ON conversation_messages (role);
CREATE INDEX IF NOT EXISTS ix_message_session_timestamp ON conversation_messages (session_id, timestamp);
CREATE INDEX IF NOT EXISTS ix_message_role_timestamp ON conversation_messages (role, timestamp);
CREATE INDEX IF NOT EXISTS ix_message_session_role ON conversation_messages (session_id, role);

-- Create api_usage_logs table for cost tracking and analytics
CREATE TABLE IF NOT EXISTS api_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id VARCHAR(255),
    user_id VARCHAR(255),
    correlation_id VARCHAR(255),
    service_name VARCHAR(100) NOT NULL,
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    cost VARCHAR(20) DEFAULT '0.00',
    response_time_ms INTEGER,
    status_code INTEGER,
    success BOOLEAN DEFAULT TRUE,
    model_used VARCHAR(100),
    error_message TEXT,
    metadata JSONB DEFAULT '{}'
);

-- Create indexes for api_usage_logs
CREATE INDEX IF NOT EXISTS ix_api_usage_logs_id ON api_usage_logs (id);
CREATE INDEX IF NOT EXISTS ix_api_usage_logs_session_id ON api_usage_logs (session_id);
CREATE INDEX IF NOT EXISTS ix_api_usage_logs_user_id ON api_usage_logs (user_id);
CREATE INDEX IF NOT EXISTS ix_api_usage_logs_correlation_id ON api_usage_logs (correlation_id);
CREATE INDEX IF NOT EXISTS ix_api_usage_logs_service_name ON api_usage_logs (service_name);
CREATE INDEX IF NOT EXISTS ix_api_usage_logs_success ON api_usage_logs (success);
CREATE INDEX IF NOT EXISTS ix_usage_service_timestamp ON api_usage_logs (service_name, timestamp);
CREATE INDEX IF NOT EXISTS ix_usage_user_timestamp ON api_usage_logs (user_id, timestamp);
CREATE INDEX IF NOT EXISTS ix_usage_session_timestamp ON api_usage_logs (session_id, timestamp);
CREATE INDEX IF NOT EXISTS ix_usage_cost_timestamp ON api_usage_logs (cost, timestamp);
CREATE INDEX IF NOT EXISTS ix_usage_success_timestamp ON api_usage_logs (success, timestamp);

-- Add foreign key constraint (optional, for referential integrity)
-- ALTER TABLE conversation_messages 
-- ADD CONSTRAINT fk_messages_session 
-- FOREIGN KEY (session_id) REFERENCES conversation_sessions(session_id);

-- Create function to update last_activity automatically
CREATE OR REPLACE FUNCTION update_last_activity()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_activity = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update last_activity
CREATE TRIGGER trigger_update_last_activity
    BEFORE UPDATE ON conversation_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_last_activity();

-- Grant permissions (adjust as needed)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON conversation_sessions TO your_app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON conversation_messages TO your_app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON api_usage_logs TO your_app_user;

-- Useful views for analytics (optional)
CREATE OR REPLACE VIEW session_summary AS
SELECT 
    cs.session_id,
    cs.user_id,
    cs.created_at,
    cs.last_activity,
    cs.is_active,
    cs.total_messages,
    cs.total_tokens_used,
    cs.total_cost,
    COUNT(cm.id) as actual_message_count,
    MIN(cm.timestamp) as first_message_at,
    MAX(cm.timestamp) as last_message_at
FROM conversation_sessions cs
LEFT JOIN conversation_messages cm ON cs.session_id = cm.session_id
GROUP BY cs.session_id, cs.user_id, cs.created_at, cs.last_activity, 
         cs.is_active, cs.total_messages, cs.total_tokens_used, cs.total_cost;

-- View for daily usage analytics
CREATE OR REPLACE VIEW daily_usage_stats AS
SELECT 
    DATE(timestamp) as usage_date,
    service_name,
    COUNT(*) as total_requests,
    SUM(input_tokens) as total_input_tokens,
    SUM(output_tokens) as total_output_tokens,
    SUM(total_tokens) as total_tokens,
    SUM(CAST(cost AS DECIMAL(10,6))) as total_cost,
    AVG(response_time_ms) as avg_response_time_ms,
    COUNT(CASE WHEN success = true THEN 1 END) as successful_requests,
    COUNT(CASE WHEN success = false THEN 1 END) as failed_requests
FROM api_usage_logs
GROUP BY DATE(timestamp), service_name
ORDER BY usage_date DESC, service_name;