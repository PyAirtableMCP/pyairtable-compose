-- Migration: Create Migration Log Table
-- Created: 2025-08-01
-- Description: Create table to track migration execution

-- Create migration log table
CREATE TABLE IF NOT EXISTS migration_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    migration_name VARCHAR(255) UNIQUE NOT NULL,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    execution_time_ms INTEGER,
    description TEXT,
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT,
    checksum VARCHAR(64)
);

-- Create index for migration log
CREATE INDEX IF NOT EXISTS idx_migration_log_name ON migration_log(migration_name);
CREATE INDEX IF NOT EXISTS idx_migration_log_executed_at ON migration_log(executed_at);

-- Insert initial migration log entry
INSERT INTO migration_log (migration_name, description) 
VALUES ('000_create_migration_log', 'Created migration tracking system')
ON CONFLICT (migration_name) DO NOTHING;