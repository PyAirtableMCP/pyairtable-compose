-- SAGA Orchestrator Event Store Schema
-- This script creates the necessary tables for the SAGA event store

-- Create event_store table if it doesn't exist
CREATE TABLE IF NOT EXISTS event_store (
    id VARCHAR(255) PRIMARY KEY,
    stream_id VARCHAR(255) NOT NULL,
    version INTEGER NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    event_data JSONB NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    correlation_id VARCHAR(255)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_event_store_stream_id ON event_store(stream_id);
CREATE INDEX IF NOT EXISTS idx_event_store_version ON event_store(stream_id, version);
CREATE INDEX IF NOT EXISTS idx_event_store_correlation_id ON event_store(correlation_id);
CREATE INDEX IF NOT EXISTS idx_event_store_event_type ON event_store(event_type);
CREATE INDEX IF NOT EXISTS idx_event_store_created_at ON event_store(created_at);

-- Create unique constraint on stream_id and version to prevent duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_event_store_stream_version_unique ON event_store(stream_id, version);

-- Create SAGA state table for quick queries (optional read model)
CREATE TABLE IF NOT EXISTS saga_instances (
    id VARCHAR(255) PRIMARY KEY,
    saga_type VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL,
    current_step INTEGER DEFAULT 0,
    total_steps INTEGER NOT NULL,
    input_data JSONB DEFAULT '{}',
    output_data JSONB DEFAULT '{}',
    error_message TEXT,
    correlation_id VARCHAR(255),
    tenant_id VARCHAR(255),
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for SAGA instances
CREATE INDEX IF NOT EXISTS idx_saga_instances_status ON saga_instances(status);
CREATE INDEX IF NOT EXISTS idx_saga_instances_type ON saga_instances(saga_type);
CREATE INDEX IF NOT EXISTS idx_saga_instances_correlation_id ON saga_instances(correlation_id);
CREATE INDEX IF NOT EXISTS idx_saga_instances_tenant_id ON saga_instances(tenant_id);
CREATE INDEX IF NOT EXISTS idx_saga_instances_started_at ON saga_instances(started_at);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_saga_instances_updated_at 
    BEFORE UPDATE ON saga_instances 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Grant necessary permissions (adjust as needed for your setup)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON event_store TO saga_orchestrator_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON saga_instances TO saga_orchestrator_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO saga_orchestrator_user;