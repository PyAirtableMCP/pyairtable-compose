-- Migration: 005_fix_audit_trigger.down.sql
-- Description: Rollback audit trigger fix

-- Drop the fixed trigger
DROP TRIGGER IF EXISTS audit_user_changes ON users;

-- Note: This rollback doesn't restore the original broken trigger
-- as it was incompatible with the schema. Manual intervention may be needed
-- if you want to restore the original trigger.

-- Remove migration log entry
DELETE FROM migration_log WHERE version = '005';