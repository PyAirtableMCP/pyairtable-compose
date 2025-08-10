-- Migration: 004_create_audit_logs.down.sql
-- Description: Rollback audit logs table and related functions
-- WARNING: This will permanently delete all audit log data

-- Drop trigger
DROP TRIGGER IF EXISTS audit_user_changes ON users;

-- Drop views
DROP VIEW IF EXISTS security_events_summary;
DROP VIEW IF EXISTS high_risk_events;
DROP VIEW IF EXISTS user_activity_summary;

-- Drop functions
DROP FUNCTION IF EXISTS log_user_changes();
DROP FUNCTION IF EXISTS log_security_event(UUID, UUID, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR, INET, TEXT, VARCHAR, VARCHAR, VARCHAR, BOOLEAN, VARCHAR, TEXT, JSONB, VARCHAR, DECIMAL);
DROP FUNCTION IF EXISTS get_user_security_events(UUID, INTEGER, INTEGER, VARCHAR);
DROP FUNCTION IF EXISTS detect_suspicious_activity(INTERVAL, INTEGER);
DROP FUNCTION IF EXISTS cleanup_old_audit_logs(INTERVAL, INTEGER);

-- Drop table (this will permanently delete all audit log data)
DROP TABLE IF EXISTS audit_logs CASCADE;

-- Remove migration log entry
DELETE FROM migration_log WHERE version = '004';

-- Comments
-- COMMENT: This rollback removes all audit logging functionality
-- COMMENT: All security event history will be lost
-- COMMENT: User change tracking will be disabled