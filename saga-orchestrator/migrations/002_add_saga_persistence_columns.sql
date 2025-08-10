-- Add additional columns to saga_instances table for enhanced persistence
-- This migration adds columns needed for transaction API endpoints

-- Add steps_data column to store serialized step information
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='steps_data'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN steps_data JSONB DEFAULT '[]';
        CREATE INDEX IF NOT EXISTS idx_saga_instances_steps_data ON saga_instances USING GIN (steps_data);
    END IF;
END $$;

-- Add metadata column for pattern-specific data and configurations
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='metadata'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN metadata JSONB DEFAULT '{}';
        CREATE INDEX IF NOT EXISTS idx_saga_instances_metadata ON saga_instances USING GIN (metadata);
    END IF;
END $$;

-- Add pattern column to distinguish between orchestration and choreography
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='pattern'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN pattern VARCHAR(50) DEFAULT 'orchestration';
        CREATE INDEX IF NOT EXISTS idx_saga_instances_pattern ON saga_instances(pattern);
    END IF;
END $$;

-- Add retry information columns
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='retry_count'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN retry_count INTEGER DEFAULT 0;
    END IF;
END $$;

DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='max_retries'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN max_retries INTEGER DEFAULT 3;
    END IF;
END $$;

-- Add timeout information for orchestration pattern
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name='saga_instances' AND column_name='timeout_seconds'
    ) THEN
        ALTER TABLE saga_instances ADD COLUMN timeout_seconds INTEGER;
    END IF;
END $$;

-- Create compound indexes for common query patterns
CREATE INDEX IF NOT EXISTS idx_saga_instances_status_type ON saga_instances(status, saga_type);
CREATE INDEX IF NOT EXISTS idx_saga_instances_tenant_status ON saga_instances(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_saga_instances_pattern_status ON saga_instances(pattern, status);

-- Create partial indexes for active sagas (better performance for monitoring)
CREATE INDEX IF NOT EXISTS idx_saga_instances_active ON saga_instances(started_at, current_step) 
WHERE status IN ('PENDING', 'RUNNING', 'COMPENSATING');

-- Add constraint to ensure valid status values
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT constraint_name 
        FROM information_schema.check_constraints 
        WHERE constraint_name='saga_instances_status_check'
    ) THEN
        ALTER TABLE saga_instances 
        ADD CONSTRAINT saga_instances_status_check 
        CHECK (status IN ('PENDING', 'RUNNING', 'COMPLETED', 'COMPENSATING', 'COMPENSATED', 'FAILED'));
    END IF;
END $$;

-- Add constraint to ensure valid pattern values
DO $$ 
BEGIN 
    IF NOT EXISTS (
        SELECT constraint_name 
        FROM information_schema.check_constraints 
        WHERE constraint_name='saga_instances_pattern_check'
    ) THEN
        ALTER TABLE saga_instances 
        ADD CONSTRAINT saga_instances_pattern_check 
        CHECK (pattern IN ('orchestration', 'choreography', 'hybrid'));
    END IF;
END $$;

-- Create view for SAGA transaction API compatibility
CREATE OR REPLACE VIEW saga_transactions AS
SELECT 
    id as transaction_id,
    saga_type as transaction_type,
    status,
    current_step,
    total_steps,
    input_data,
    output_data,
    error_message,
    correlation_id,
    tenant_id,
    started_at,
    completed_at,
    pattern,
    retry_count,
    max_retries,
    metadata,
    steps_data,
    (completed_at - started_at) as duration,
    CASE 
        WHEN status = 'COMPLETED' THEN 'SUCCESS'
        WHEN status = 'COMPENSATED' THEN 'ROLLED_BACK' 
        WHEN status = 'FAILED' THEN 'FAILED'
        ELSE 'IN_PROGRESS'
    END as transaction_status
FROM saga_instances;

-- Create function to get SAGA health metrics
CREATE OR REPLACE FUNCTION get_saga_health_metrics()
RETURNS TABLE (
    metric_name TEXT,
    metric_value BIGINT,
    metric_timestamp TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'total_sagas'::TEXT, COUNT(*)::BIGINT, NOW()
    FROM saga_instances
    UNION ALL
    SELECT 'active_sagas'::TEXT, COUNT(*)::BIGINT, NOW()
    FROM saga_instances 
    WHERE status IN ('PENDING', 'RUNNING', 'COMPENSATING')
    UNION ALL
    SELECT 'completed_sagas'::TEXT, COUNT(*)::BIGINT, NOW()
    FROM saga_instances 
    WHERE status = 'COMPLETED'
    UNION ALL
    SELECT 'failed_sagas'::TEXT, COUNT(*)::BIGINT, NOW()
    FROM saga_instances 
    WHERE status IN ('FAILED', 'COMPENSATED')
    UNION ALL
    SELECT 'sagas_last_24h'::TEXT, COUNT(*)::BIGINT, NOW()
    FROM saga_instances 
    WHERE started_at >= NOW() - INTERVAL '24 hours';
END;
$$ LANGUAGE plpgsql;

-- Grant permissions for the view and function
GRANT SELECT ON saga_transactions TO PUBLIC;
GRANT EXECUTE ON FUNCTION get_saga_health_metrics() TO PUBLIC;

-- Add comment to document the changes
COMMENT ON TABLE saga_instances IS 'Enhanced SAGA instances table supporting both orchestration and choreography patterns with transaction API compatibility';
COMMENT ON COLUMN saga_instances.steps_data IS 'Serialized step information including status, results, and timing';
COMMENT ON COLUMN saga_instances.metadata IS 'Pattern-specific metadata and configuration data';
COMMENT ON COLUMN saga_instances.pattern IS 'SAGA pattern type: orchestration, choreography, or hybrid';
COMMENT ON VIEW saga_transactions IS 'API-compatible view of SAGA instances as transactions';