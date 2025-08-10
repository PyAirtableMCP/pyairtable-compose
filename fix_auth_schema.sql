-- Fix authentication schema for PyAirtable
-- This script will migrate the existing platform_users table and create refresh_tokens table

BEGIN;

-- Step 1: Add missing columns to platform_users table
DO $$
BEGIN
    -- Add UUID id column (backup existing id as old_id)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='platform_users' AND column_name='uuid_id') THEN
        ALTER TABLE platform_users ADD COLUMN uuid_id UUID DEFAULT gen_random_uuid();
    END IF;
    
    -- Add missing columns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='platform_users' AND column_name='role') THEN
        ALTER TABLE platform_users ADD COLUMN role VARCHAR(50) NOT NULL DEFAULT 'user';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='platform_users' AND column_name='tenant_id') THEN
        ALTER TABLE platform_users ADD COLUMN tenant_id UUID DEFAULT gen_random_uuid();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='platform_users' AND column_name='email_verified') THEN
        ALTER TABLE platform_users ADD COLUMN email_verified BOOLEAN DEFAULT false;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='platform_users' AND column_name='last_login_at') THEN
        ALTER TABLE platform_users ADD COLUMN last_login_at TIMESTAMP WITH TIME ZONE;
    END IF;
END $$;

-- Step 2: Create users view that maps to our auth service expectations
CREATE OR REPLACE VIEW users AS
SELECT 
    COALESCE(uuid_id, gen_random_uuid()) as id,
    email,
    password_hash,
    COALESCE(first_name, '') as first_name,
    COALESCE(last_name, '') as last_name,
    role,
    COALESCE(tenant_id, gen_random_uuid()) as tenant_id,
    is_active,
    email_verified,
    created_at,
    updated_at,
    last_login_at
FROM platform_users;

-- Step 3: Create refresh_tokens table
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash VARCHAR(255) UNIQUE NOT NULL,
    user_id UUID NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMP WITH TIME ZONE
);

-- Indexes for refresh_tokens
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash ON refresh_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_active ON refresh_tokens(expires_at, revoked_at) 
    WHERE revoked_at IS NULL;

-- Step 4: Create function to cleanup expired tokens
CREATE OR REPLACE FUNCTION cleanup_expired_tokens() RETURNS void AS $$
BEGIN
    DELETE FROM refresh_tokens 
    WHERE expires_at < CURRENT_TIMESTAMP 
    OR revoked_at IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Create trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to platform_users if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_platform_users_updated_at') THEN
        CREATE TRIGGER update_platform_users_updated_at BEFORE UPDATE
            ON platform_users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- Step 6: Ensure UUIDs are populated for existing users
UPDATE platform_users 
SET uuid_id = gen_random_uuid() 
WHERE uuid_id IS NULL;

UPDATE platform_users 
SET tenant_id = gen_random_uuid() 
WHERE tenant_id IS NULL;

-- Step 7: Add constraints
ALTER TABLE platform_users ALTER COLUMN tenant_id SET NOT NULL;

-- Add email format check if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints 
                   WHERE table_name = 'platform_users' AND constraint_name = 'email_format') THEN
        ALTER TABLE platform_users ADD CONSTRAINT email_format 
        CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
    END IF;
END $$;

-- Step 8: Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_email ON platform_users(email);
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON platform_users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON platform_users(role);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON platform_users(created_at DESC);

COMMIT;

-- Verify the schema
SELECT 'Migration completed successfully' as status;