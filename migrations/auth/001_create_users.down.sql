-- Migration: 001_create_users.down.sql
-- Description: Rollback users table authentication enhancements
-- WARNING: This will remove security-related columns and functions
-- Only run if you need to completely rollback the authentication system

-- Drop helper functions
DROP FUNCTION IF EXISTS handle_failed_login(VARCHAR);
DROP FUNCTION IF EXISTS reset_failed_login_attempts(VARCHAR);
DROP FUNCTION IF EXISTS is_account_locked(VARCHAR);

-- Drop trigger
DROP TRIGGER IF EXISTS update_users_updated_at ON users;

-- Drop indexes (only the new ones we added)
DROP INDEX IF EXISTS idx_users_failed_attempts;
DROP INDEX IF EXISTS idx_users_locked_until;

-- Remove authentication-specific columns
-- WARNING: This will permanently delete security data
ALTER TABLE users DROP COLUMN IF EXISTS failed_login_attempts;
ALTER TABLE users DROP COLUMN IF EXISTS account_locked_until;
ALTER TABLE users DROP COLUMN IF EXISTS password_changed_at;

-- Note: We don't drop the entire users table as it may contain important data
-- and may be referenced by other tables

-- If you really need to drop the entire users table (DANGEROUS):
-- DROP TABLE IF EXISTS users CASCADE;

-- Remove migration log entry
DELETE FROM migration_log WHERE version = '001';

-- Comments
-- COMMENT: This rollback removes authentication security features
-- COMMENT: Consider backing up data before running this rollback