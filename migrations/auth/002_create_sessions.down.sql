-- Migration: 002_create_sessions.down.sql
-- Description: Rollback user sessions table and related functions
-- WARNING: This will permanently delete all session data

-- Drop view
DROP VIEW IF EXISTS active_user_sessions;

-- Drop functions
DROP FUNCTION IF EXISTS create_user_session(UUID, VARCHAR, TIMESTAMP WITH TIME ZONE, INET, TEXT, VARCHAR, JSONB, JSONB);
DROP FUNCTION IF EXISTS validate_session(VARCHAR);
DROP FUNCTION IF EXISTS revoke_session(VARCHAR);
DROP FUNCTION IF EXISTS revoke_all_user_sessions(UUID);
DROP FUNCTION IF EXISTS cleanup_expired_sessions();

-- Drop trigger
DROP TRIGGER IF EXISTS update_session_last_used_trigger ON user_sessions;
DROP FUNCTION IF EXISTS update_session_last_used();

-- Drop table (this will permanently delete all session data)
DROP TABLE IF EXISTS user_sessions CASCADE;

-- Remove migration log entry
DELETE FROM migration_log WHERE version = '002';

-- Comments
-- COMMENT: This rollback removes all session management functionality
-- COMMENT: All active user sessions will be lost