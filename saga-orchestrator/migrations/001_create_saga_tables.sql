-- Migration 001: Create SAGA Orchestrator Tables
-- Create saga_instances table for persistent SAGA state

-- Create saga_instances table
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'saga_instances') THEN
        CREATE TABLE saga_instances (
            id VARCHAR(255) PRIMARY KEY,
            saga_type VARCHAR(100) NOT NULL,
            status VARCHAR(50) NOT NULL DEFAULT 'pending',
            current_step INTEGER NOT NULL DEFAULT 0,
            total_steps INTEGER NOT NULL DEFAULT 0,
            input_data JSONB DEFAULT '{}',
            output_data JSONB DEFAULT '{}',
            error_message TEXT,
            correlation_id VARCHAR(255),
            tenant_id VARCHAR(255),
            started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            completed_at TIMESTAMP WITH TIME ZONE,
            steps_data JSONB DEFAULT '[]',
            metadata JSONB DEFAULT '{}',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        -- Create indexes for performance
        CREATE INDEX idx_saga_instances_status ON saga_instances(status);
        CREATE INDEX idx_saga_instances_type ON saga_instances(saga_type);
        CREATE INDEX idx_saga_instances_tenant ON saga_instances(tenant_id);
        CREATE INDEX idx_saga_instances_correlation ON saga_instances(correlation_id);
        CREATE INDEX idx_saga_instances_started ON saga_instances(started_at);
        CREATE INDEX idx_saga_instances_steps_data ON saga_instances USING GIN (steps_data);
        CREATE INDEX idx_saga_instances_metadata ON saga_instances USING GIN (metadata);
        
        -- Add updated_at trigger
        CREATE OR REPLACE FUNCTION update_saga_instances_updated_at()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        
        CREATE TRIGGER saga_instances_updated_at
            BEFORE UPDATE ON saga_instances
            FOR EACH ROW EXECUTE PROCEDURE update_saga_instances_updated_at();
            
        RAISE NOTICE 'Created saga_instances table with indexes and triggers';
    ELSE
        RAISE NOTICE 'saga_instances table already exists, skipping creation';
    END IF;
END $$;

-- Create event_store table for event sourcing (if not exists)
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'event_store') THEN
        CREATE TABLE event_store (
            id VARCHAR(255) PRIMARY KEY,
            stream_id VARCHAR(255) NOT NULL,
            version INTEGER NOT NULL,
            event_type VARCHAR(100) NOT NULL,
            event_data JSONB NOT NULL,
            event_metadata JSONB DEFAULT '{}',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            correlation_id VARCHAR(255),
            UNIQUE(stream_id, version)
        );
        
        -- Create indexes for event store
        CREATE INDEX idx_event_store_stream ON event_store(stream_id);
        CREATE INDEX idx_event_store_type ON event_store(event_type);
        CREATE INDEX idx_event_store_correlation ON event_store(correlation_id);
        CREATE INDEX idx_event_store_created ON event_store(created_at);
        CREATE INDEX idx_event_store_data ON event_store USING GIN (event_data);
        
        RAISE NOTICE 'Created event_store table with indexes';
    ELSE
        RAISE NOTICE 'event_store table already exists, skipping creation';
    END IF;
END $$;

-- Create saga_metrics table for monitoring
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'saga_metrics') THEN
        CREATE TABLE saga_metrics (
            id SERIAL PRIMARY KEY,
            saga_id VARCHAR(255) NOT NULL,
            metric_name VARCHAR(100) NOT NULL,
            metric_value NUMERIC,
            metric_labels JSONB DEFAULT '{}',
            recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        -- Create indexes for metrics
        CREATE INDEX idx_saga_metrics_saga_id ON saga_metrics(saga_id);
        CREATE INDEX idx_saga_metrics_name ON saga_metrics(metric_name);
        CREATE INDEX idx_saga_metrics_recorded ON saga_metrics(recorded_at);
        CREATE INDEX idx_saga_metrics_labels ON saga_metrics USING GIN (metric_labels);
        
        RAISE NOTICE 'Created saga_metrics table with indexes';
    ELSE
        RAISE NOTICE 'saga_metrics table already exists, skipping creation';
    END IF;
END $$;

-- Create saga_locks table for distributed locking
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'saga_locks') THEN
        CREATE TABLE saga_locks (
            lock_key VARCHAR(255) PRIMARY KEY,
            locked_by VARCHAR(255) NOT NULL,
            locked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
            metadata JSONB DEFAULT '{}'
        );
        
        -- Create indexes for locks
        CREATE INDEX idx_saga_locks_expires ON saga_locks(expires_at);
        CREATE INDEX idx_saga_locks_locked_by ON saga_locks(locked_by);
        
        RAISE NOTICE 'Created saga_locks table with indexes';
    ELSE
        RAISE NOTICE 'saga_locks table already exists, skipping creation';
    END IF;
END $$;

-- Grant necessary permissions (adjust for your specific user)
DO $$
DECLARE
    db_user TEXT;
BEGIN
    -- Get current user
    SELECT current_user INTO db_user;
    
    -- Grant permissions on tables
    EXECUTE format('GRANT ALL ON saga_instances TO %I', db_user);
    EXECUTE format('GRANT ALL ON event_store TO %I', db_user);
    EXECUTE format('GRANT ALL ON saga_metrics TO %I', db_user);
    EXECUTE format('GRANT ALL ON saga_locks TO %I', db_user);
    EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE saga_metrics_id_seq TO %I', db_user);
    
    RAISE NOTICE 'Granted permissions to user: %', db_user;
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Failed to grant permissions: %', SQLERRM;
END $$;

-- Insert migration record
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'schema_migrations') THEN
        CREATE TABLE schema_migrations (
            version VARCHAR(255) PRIMARY KEY,
            applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        RAISE NOTICE 'Created schema_migrations table';
    END IF;
    
    INSERT INTO schema_migrations (version) VALUES ('001_create_saga_tables')
    ON CONFLICT (version) DO NOTHING;
    
    RAISE NOTICE 'Migration 001_create_saga_tables completed successfully';
END $$;