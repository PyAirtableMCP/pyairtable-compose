-- Migration: 001_create_users.up.sql
-- Description: Create/enhance users table for authentication system
-- Based on: AUTHENTICATION_ARCHITECTURE.md requirements
-- PostgreSQL: PyAirtable Sprint 1 - User Authentication Schema

-- Enable UUID extension if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create users table with comprehensive authentication fields
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'user',
    tenant_id UUID,
    is_active BOOLEAN DEFAULT true,
    email_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    
    -- New authentication security fields
    failed_login_attempts INTEGER DEFAULT 0,
    account_locked_until TIMESTAMP WITH TIME ZONE,
    password_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT password_not_empty CHECK (length(password_hash) > 0),
    CONSTRAINT name_not_empty CHECK (length(first_name) > 0 AND length(last_name) > 0),
    CONSTRAINT valid_role CHECK (role IN ('user', 'admin', 'moderator', 'readonly')),
    CONSTRAINT failed_attempts_positive CHECK (failed_login_attempts >= 0),
    CONSTRAINT account_lock_future CHECK (account_locked_until IS NULL OR account_locked_until > CURRENT_TIMESTAMP)
);

-- Add missing columns to existing users table if they don't exist
-- This handles the case where users table already exists
DO $$ 
BEGIN
    -- Check and add failed_login_attempts column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='users' AND column_name='failed_login_attempts') THEN
        ALTER TABLE users ADD COLUMN failed_login_attempts INTEGER DEFAULT 0;
    END IF;
    
    -- Check and add account_locked_until column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='users' AND column_name='account_locked_until') THEN
        ALTER TABLE users ADD COLUMN account_locked_until TIMESTAMP WITH TIME ZONE;
    END IF;
    
    -- Check and add password_changed_at column
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name='users' AND column_name='password_changed_at') THEN
        ALTER TABLE users ADD COLUMN password_changed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
    END IF;
    
    -- Update existing records to set password_changed_at to created_at if null
    UPDATE users SET password_changed_at = created_at WHERE password_changed_at IS NULL;
END $$;

-- Create indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users(tenant_id) WHERE tenant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);
CREATE INDEX IF NOT EXISTS idx_users_email_verified ON users(email_verified);
CREATE INDEX IF NOT EXISTS idx_users_last_login ON users(last_login_at DESC) WHERE last_login_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_failed_attempts ON users(failed_login_attempts) WHERE failed_login_attempts > 0;
CREATE INDEX IF NOT EXISTS idx_users_locked_until ON users(account_locked_until) WHERE account_locked_until IS NOT NULL;

-- Create or replace updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for updated_at
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Create function to handle failed login attempts
CREATE OR REPLACE FUNCTION handle_failed_login(user_email VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    current_attempts INTEGER;
    lock_threshold INTEGER := 5;
    lock_duration INTERVAL := '15 minutes';
BEGIN
    -- Get current failed attempts
    SELECT failed_login_attempts INTO current_attempts 
    FROM users 
    WHERE email = user_email AND is_active = true;
    
    IF current_attempts IS NULL THEN
        -- User doesn't exist
        RETURN FALSE;
    END IF;
    
    -- Increment failed attempts
    current_attempts := current_attempts + 1;
    
    -- Check if account should be locked
    IF current_attempts >= lock_threshold THEN
        UPDATE users 
        SET failed_login_attempts = current_attempts,
            account_locked_until = CURRENT_TIMESTAMP + lock_duration,
            updated_at = CURRENT_TIMESTAMP
        WHERE email = user_email;
        RETURN FALSE; -- Account locked
    ELSE
        UPDATE users 
        SET failed_login_attempts = current_attempts,
            updated_at = CURRENT_TIMESTAMP
        WHERE email = user_email;
        RETURN TRUE; -- Account not locked yet
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create function to reset failed login attempts on successful login
CREATE OR REPLACE FUNCTION reset_failed_login_attempts(user_email VARCHAR)
RETURNS VOID AS $$
BEGIN
    UPDATE users 
    SET failed_login_attempts = 0,
        account_locked_until = NULL,
        last_login_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE email = user_email;
END;
$$ LANGUAGE plpgsql;

-- Create function to check if account is locked
CREATE OR REPLACE FUNCTION is_account_locked(user_email VARCHAR)
RETURNS BOOLEAN AS $$
DECLARE
    lock_until TIMESTAMP WITH TIME ZONE;
BEGIN
    SELECT account_locked_until INTO lock_until 
    FROM users 
    WHERE email = user_email AND is_active = true;
    
    IF lock_until IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Check if lock has expired
    IF lock_until <= CURRENT_TIMESTAMP THEN
        -- Reset the lock
        UPDATE users 
        SET account_locked_until = NULL,
            failed_login_attempts = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE email = user_email;
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Comments for documentation
COMMENT ON TABLE users IS 'User accounts for authentication system with security features';
COMMENT ON COLUMN users.id IS 'Unique user identifier (UUID)';
COMMENT ON COLUMN users.email IS 'User email address (unique, validated format)';
COMMENT ON COLUMN users.password_hash IS 'Bcrypt hashed password (cost factor 12)';
COMMENT ON COLUMN users.first_name IS 'User first name (required)';
COMMENT ON COLUMN users.last_name IS 'User last name (required)';
COMMENT ON COLUMN users.role IS 'User role: user, admin, moderator, readonly';
COMMENT ON COLUMN users.tenant_id IS 'Associated tenant/organization (nullable)';
COMMENT ON COLUMN users.is_active IS 'Account active status';
COMMENT ON COLUMN users.email_verified IS 'Email verification status';
COMMENT ON COLUMN users.created_at IS 'Account creation timestamp';
COMMENT ON COLUMN users.updated_at IS 'Last modification timestamp (auto-updated)';
COMMENT ON COLUMN users.last_login_at IS 'Last successful login timestamp';
COMMENT ON COLUMN users.failed_login_attempts IS 'Number of consecutive failed login attempts';
COMMENT ON COLUMN users.account_locked_until IS 'Account lock expiration timestamp';
COMMENT ON COLUMN users.password_changed_at IS 'Last password change timestamp';

-- Grant basic permissions (adjust as needed for your application user)
-- GRANT SELECT, INSERT, UPDATE ON users TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION handle_failed_login TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION reset_failed_login_attempts TO pyairtable_app;
-- GRANT EXECUTE ON FUNCTION is_account_locked TO pyairtable_app;

-- Migration completed
INSERT INTO migration_log (version, description, applied_at) 
VALUES ('001', 'Create/enhance users table for authentication', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;