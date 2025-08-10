-- Create missing SAGA tables for Go platform services
-- Based on analysis of go-services/pyairtable-platform/internal/saga/store.go

-- Create saga_timeouts table
CREATE TABLE IF NOT EXISTS saga_timeouts (
    id SERIAL PRIMARY KEY,
    saga_id UUID NOT NULL,
    step_id VARCHAR(255),
    timeout_at TIMESTAMP WITH TIME ZONE NOT NULL,
    timeout_type VARCHAR(50) NOT NULL DEFAULT 'execution',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create unique constraint for saga_timeouts
CREATE UNIQUE INDEX IF NOT EXISTS idx_saga_timeouts_unique ON saga_timeouts(saga_id, COALESCE(step_id, ''));

-- Create saga_compensations table
CREATE TABLE IF NOT EXISTS saga_compensations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id UUID NOT NULL,
    step_id VARCHAR(255) NOT NULL,
    command JSONB NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    result JSONB,
    correlation_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create saga_snapshots table
CREATE TABLE IF NOT EXISTS saga_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id UUID NOT NULL,
    version INTEGER NOT NULL,
    status VARCHAR(50) NOT NULL,
    current_step INTEGER NOT NULL,
    data JSONB NOT NULL,
    checksum VARCHAR(64),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Update the saga_instances table to match the Go service expectations
ALTER TABLE saga_instances 
ADD COLUMN IF NOT EXISTS type VARCHAR(255),
ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1,
ADD COLUMN IF NOT EXISTS steps JSONB DEFAULT '[]',
ADD COLUMN IF NOT EXISTS current_step INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS completed_steps JSONB DEFAULT '[]',
ADD COLUMN IF NOT EXISTS input_data JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS output_data JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS context JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS error_message TEXT,
ADD COLUMN IF NOT EXISTS started_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS timeout_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS correlation_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS tenant_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS user_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS parent_saga_id UUID,
ADD COLUMN IF NOT EXISTS child_saga_ids JSONB DEFAULT '[]',
ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Create performance indexes for saga_timeouts
CREATE INDEX IF NOT EXISTS idx_saga_timeouts_timeout_at ON saga_timeouts(timeout_at);
CREATE INDEX IF NOT EXISTS idx_saga_timeouts_saga_id ON saga_timeouts(saga_id);
CREATE INDEX IF NOT EXISTS idx_saga_timeouts_type ON saga_timeouts(timeout_type);

-- Create performance indexes for saga_compensations  
CREATE INDEX IF NOT EXISTS idx_saga_compensations_saga_id ON saga_compensations(saga_id);
CREATE INDEX IF NOT EXISTS idx_saga_compensations_status ON saga_compensations(status);
CREATE INDEX IF NOT EXISTS idx_saga_compensations_step_id ON saga_compensations(step_id);
CREATE INDEX IF NOT EXISTS idx_saga_compensations_created_at ON saga_compensations(created_at);
CREATE INDEX IF NOT EXISTS idx_saga_compensations_correlation_id ON saga_compensations(correlation_id);

-- Create performance indexes for saga_snapshots
CREATE INDEX IF NOT EXISTS idx_saga_snapshots_saga_id ON saga_snapshots(saga_id);
CREATE INDEX IF NOT EXISTS idx_saga_snapshots_version ON saga_snapshots(saga_id, version);
CREATE INDEX IF NOT EXISTS idx_saga_snapshots_status ON saga_snapshots(status);
CREATE INDEX IF NOT EXISTS idx_saga_snapshots_created_at ON saga_snapshots(created_at);

-- Add more indexes to saga_instances for the new columns
CREATE INDEX IF NOT EXISTS idx_saga_instances_type ON saga_instances(type);
CREATE INDEX IF NOT EXISTS idx_saga_instances_version ON saga_instances(version);
CREATE INDEX IF NOT EXISTS idx_saga_instances_current_step ON saga_instances(current_step);
CREATE INDEX IF NOT EXISTS idx_saga_instances_user_id ON saga_instances(user_id);
CREATE INDEX IF NOT EXISTS idx_saga_instances_parent_saga_id ON saga_instances(parent_saga_id);
CREATE INDEX IF NOT EXISTS idx_saga_instances_timeout_at ON saga_instances(timeout_at);
CREATE INDEX IF NOT EXISTS idx_saga_instances_created_at ON saga_instances(created_at);

-- Create triggers for updated_at timestamps
CREATE TRIGGER IF NOT EXISTS update_saga_compensations_updated_at 
    BEFORE UPDATE ON saga_compensations 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Grant permissions for all saga tables
-- GRANT SELECT, INSERT, UPDATE, DELETE ON saga_timeouts TO saga_orchestrator_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON saga_compensations TO saga_orchestrator_user;  
-- GRANT SELECT, INSERT, UPDATE, DELETE ON saga_snapshots TO saga_orchestrator_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO saga_orchestrator_user;