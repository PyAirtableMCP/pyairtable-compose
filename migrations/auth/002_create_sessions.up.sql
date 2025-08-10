-- Migration: 002_create_sessions.up.sql
-- Description: Create user sessions table for JWT refresh token management
-- Based on: AUTHENTICATION_ARCHITECTURE.md Session Management requirements
-- PostgreSQL: PyAirtable Sprint 1 - Session Management Schema

-- Create user_sessions table for tracking active sessions
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    last_used_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Additional session metadata
    session_type VARCHAR(20) DEFAULT 'web',
    device_info JSONB DEFAULT '{}',
    location_info JSONB DEFAULT '{}',
    
    -- Constraints
    CONSTRAINT valid_expiry CHECK (expires_at > created_at),
    CONSTRAINT valid_revocation CHECK (revoked_at IS NULL OR revoked_at >= created_at),
    CONSTRAINT valid_session_type CHECK (session_type IN ('web', 'mobile', 'api', 'cli')),
    CONSTRAINT token_hash_format CHECK (length(token_hash) = 64)
);

-- Create indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON user_sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_user_sessions_created_at ON user_sessions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_sessions_revoked_at ON user_sessions(revoked_at) WHERE revoked_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON user_sessions(user_id, expires_at) 
    WHERE revoked_at IS NULL AND expires_at > CURRENT_TIMESTAMP;
CREATE INDEX IF NOT EXISTS idx_user_sessions_ip ON user_sessions(ip_address) WHERE ip_address IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_used ON user_sessions(last_used_at DESC);

-- Create foreign key constraint to users table
ALTER TABLE user_sessions 
ADD CONSTRAINT fk_user_sessions_user_id 
FOREIGN KEY (user_id) REFERENCES users(id) 
ON DELETE CASCADE ON UPDATE CASCADE;

-- Create trigger to update last_used_at on token validation
CREATE OR REPLACE FUNCTION update_session_last_used()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_used_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_session_last_used_trigger
    BEFORE UPDATE ON user_sessions
    FOR EACH ROW
    WHEN (OLD.last_used_at IS DISTINCT FROM NEW.last_used_at OR OLD.token_hash = NEW.token_hash)
    EXECUTE FUNCTION update_session_last_used();

-- Function to create a new session
CREATE OR REPLACE FUNCTION create_user_session(
    p_user_id UUID,
    p_token_hash VARCHAR(64),
    p_expires_at TIMESTAMP WITH TIME ZONE,
    p_ip_address INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_session_type VARCHAR(20) DEFAULT 'web',
    p_device_info JSONB DEFAULT '{}',
    p_location_info JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
    session_id UUID;
    max_sessions_per_user INTEGER := 10;
BEGIN
    -- Clean up expired sessions for this user first
    DELETE FROM user_sessions 
    WHERE user_id = p_user_id 
      AND (expires_at <= CURRENT_TIMESTAMP OR revoked_at IS NOT NULL);
    
    -- Limit concurrent sessions per user
    DELETE FROM user_sessions 
    WHERE user_id = p_user_id 
      AND id NOT IN (
          SELECT id FROM user_sessions 
          WHERE user_id = p_user_id 
            AND revoked_at IS NULL 
            AND expires_at > CURRENT_TIMESTAMP
          ORDER BY created_at DESC 
          LIMIT max_sessions_per_user - 1
      );
    
    -- Insert new session
    INSERT INTO user_sessions (
        user_id, token_hash, expires_at, ip_address, user_agent, 
        session_type, device_info, location_info
    ) VALUES (
        p_user_id, p_token_hash, p_expires_at, p_ip_address, p_user_agent,
        p_session_type, p_device_info, p_location_info
    ) RETURNING id INTO session_id;
    
    RETURN session_id;
END;
$$ LANGUAGE plpgsql;

-- Function to validate and refresh a session
CREATE OR REPLACE FUNCTION validate_session(p_token_hash VARCHAR(64))
RETURNS TABLE(
    session_id UUID,
    user_id UUID,
    is_valid BOOLEAN,
    expires_at TIMESTAMP WITH TIME ZONE,
    user_email VARCHAR(255),
    user_role VARCHAR(50)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        us.id,
        us.user_id,
        CASE 
            WHEN us.revoked_at IS NOT NULL THEN FALSE
            WHEN us.expires_at <= CURRENT_TIMESTAMP THEN FALSE
            WHEN NOT u.is_active THEN FALSE
            ELSE TRUE
        END as is_valid,
        us.expires_at,
        u.email,
        u.role
    FROM user_sessions us
    JOIN users u ON us.user_id = u.id
    WHERE us.token_hash = p_token_hash;
    
    -- Update last_used_at if session is valid
    UPDATE user_sessions 
    SET last_used_at = CURRENT_TIMESTAMP 
    WHERE token_hash = p_token_hash 
      AND revoked_at IS NULL 
      AND expires_at > CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Function to revoke a session
CREATE OR REPLACE FUNCTION revoke_session(p_token_hash VARCHAR(64))
RETURNS BOOLEAN AS $$
DECLARE
    rows_affected INTEGER;
BEGIN
    UPDATE user_sessions 
    SET revoked_at = CURRENT_TIMESTAMP 
    WHERE token_hash = p_token_hash 
      AND revoked_at IS NULL;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    RETURN rows_affected > 0;
END;
$$ LANGUAGE plpgsql;

-- Function to revoke all sessions for a user
CREATE OR REPLACE FUNCTION revoke_all_user_sessions(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    rows_affected INTEGER;
BEGIN
    UPDATE user_sessions 
    SET revoked_at = CURRENT_TIMESTAMP 
    WHERE user_id = p_user_id 
      AND revoked_at IS NULL;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    RETURN rows_affected;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup expired sessions (run periodically)
CREATE OR REPLACE FUNCTION cleanup_expired_sessions()
RETURNS INTEGER AS $$
DECLARE
    rows_deleted INTEGER;
    cleanup_threshold INTERVAL := '30 days';
BEGIN
    DELETE FROM user_sessions 
    WHERE expires_at <= CURRENT_TIMESTAMP - cleanup_threshold
       OR (revoked_at IS NOT NULL AND revoked_at <= CURRENT_TIMESTAMP - cleanup_threshold);
    
    GET DIAGNOSTICS rows_deleted = ROW_COUNT;
    RETURN rows_deleted;
END;
$$ LANGUAGE plpgsql;

-- Create a view for active sessions
CREATE OR REPLACE VIEW active_user_sessions AS
SELECT 
    us.id,
    us.user_id,
    u.email,
    u.first_name,
    u.last_name,
    us.created_at,
    us.last_used_at,
    us.expires_at,
    us.ip_address,
    us.session_type,
    us.device_info,
    us.location_info,
    EXTRACT(EPOCH FROM (us.expires_at - CURRENT_TIMESTAMP)) as seconds_until_expiry
FROM user_sessions us
JOIN users u ON us.user_id = u.id
WHERE us.revoked_at IS NULL 
  AND us.expires_at > CURRENT_TIMESTAMP
  AND u.is_active = true
ORDER BY us.last_used_at DESC;

-- Comments for documentation
COMMENT ON TABLE user_sessions IS 'User authentication sessions with JWT refresh token tracking';
COMMENT ON COLUMN user_sessions.id IS 'Unique session identifier';
COMMENT ON COLUMN user_sessions.user_id IS 'Reference to users table';
COMMENT ON COLUMN user_sessions.token_hash IS 'SHA256 hash of refresh token (64 chars)';
COMMENT ON COLUMN user_sessions.ip_address IS 'Client IP address for security tracking';
COMMENT ON COLUMN user_sessions.user_agent IS 'Client user agent string';
COMMENT ON COLUMN user_sessions.created_at IS 'Session creation timestamp';
COMMENT ON COLUMN user_sessions.expires_at IS 'Session expiration timestamp';
COMMENT ON COLUMN user_sessions.revoked_at IS 'Session revocation timestamp (null if active)';
COMMENT ON COLUMN user_sessions.last_used_at IS 'Last session activity timestamp';
COMMENT ON COLUMN user_sessions.session_type IS 'Type of session: web, mobile, api, cli';
COMMENT ON COLUMN user_sessions.device_info IS 'JSON metadata about client device';
COMMENT ON COLUMN user_sessions.location_info IS 'JSON metadata about client location';

COMMENT ON FUNCTION create_user_session IS 'Create new user session with automatic cleanup';
COMMENT ON FUNCTION validate_session IS 'Validate session token and return user info';
COMMENT ON FUNCTION revoke_session IS 'Revoke a specific session by token hash';
COMMENT ON FUNCTION revoke_all_user_sessions IS 'Revoke all active sessions for a user';
COMMENT ON FUNCTION cleanup_expired_sessions IS 'Remove old expired and revoked sessions';

COMMENT ON VIEW active_user_sessions IS 'View of currently active user sessions';

-- Grant permissions (adjust as needed)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON user_sessions TO pyairtable_app;
-- GRANT SELECT ON active_user_sessions TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION create_user_session TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION validate_session TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION revoke_session TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION revoke_all_user_sessions TO pyairtable_app;

-- Migration completed
INSERT INTO migration_log (version, description, applied_at) 
VALUES ('002', 'Create user sessions table for JWT refresh token management', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;