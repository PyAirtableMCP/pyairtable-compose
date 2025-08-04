-- Conflict Resolution Scripts for PostgreSQL Multi-Region Setup
-- These scripts help handle conflicts and maintain data consistency across regions

-- Create schema for conflict resolution
CREATE SCHEMA IF NOT EXISTS conflict_resolution;

-- Create table to track regional data modifications
CREATE TABLE IF NOT EXISTS conflict_resolution.region_modifications (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    record_id VARCHAR(255) NOT NULL,
    region VARCHAR(50) NOT NULL,
    operation VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    data_hash VARCHAR(64),
    created_by VARCHAR(255),
    INDEX idx_region_modifications_table_record (table_name, record_id),
    INDEX idx_region_modifications_timestamp (timestamp),
    INDEX idx_region_modifications_region (region)
);

-- Create table for conflict resolution rules
CREATE TABLE IF NOT EXISTS conflict_resolution.resolution_rules (
    id SERIAL PRIMARY KEY,
    table_name VARCHAR(255) NOT NULL,
    conflict_type VARCHAR(50) NOT NULL, -- timestamp, region_priority, manual
    resolution_strategy TEXT NOT NULL,
    priority INTEGER DEFAULT 100,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default conflict resolution rules
INSERT INTO conflict_resolution.resolution_rules (table_name, conflict_type, resolution_strategy, priority) 
VALUES 
    ('*', 'timestamp', 'latest_timestamp_wins', 100),
    ('users', 'region_priority', 'us_east_priority', 90),
    ('workspaces', 'region_priority', 'owner_region_priority', 95),
    ('audit_logs', 'timestamp', 'preserve_all', 80)
ON CONFLICT DO NOTHING;

-- Function to detect potential conflicts
CREATE OR REPLACE FUNCTION conflict_resolution.detect_conflicts(
    p_table_name VARCHAR(255),
    p_record_id VARCHAR(255),
    p_time_window INTERVAL DEFAULT '5 minutes'::INTERVAL
)
RETURNS TABLE(
    conflict_id INTEGER,
    regions TEXT[],
    operations TEXT[],
    timestamps TIMESTAMP WITH TIME ZONE[]
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        MIN(rm.id) as conflict_id,
        ARRAY_AGG(DISTINCT rm.region) as regions,
        ARRAY_AGG(DISTINCT rm.operation) as operations,
        ARRAY_AGG(rm.timestamp ORDER BY rm.timestamp) as timestamps
    FROM conflict_resolution.region_modifications rm
    WHERE rm.table_name = p_table_name
      AND rm.record_id = p_record_id
      AND rm.timestamp >= NOW() - p_time_window
    GROUP BY rm.table_name, rm.record_id
    HAVING COUNT(DISTINCT rm.region) > 1;
END;
$$ LANGUAGE plpgsql;

-- Function to resolve conflicts based on rules
CREATE OR REPLACE FUNCTION conflict_resolution.resolve_conflict(
    p_table_name VARCHAR(255),
    p_record_id VARCHAR(255),
    p_conflict_type VARCHAR(50) DEFAULT 'timestamp'
)
RETURNS JSON AS $$
DECLARE
    v_rule conflict_resolution.resolution_rules%ROWTYPE;
    v_result JSON;
    v_winning_region VARCHAR(50);
    v_winning_timestamp TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Get the appropriate resolution rule
    SELECT * INTO v_rule
    FROM conflict_resolution.resolution_rules
    WHERE (table_name = p_table_name OR table_name = '*')
      AND conflict_type = p_conflict_type
      AND active = TRUE
    ORDER BY 
        CASE WHEN table_name = p_table_name THEN 1 ELSE 2 END,
        priority ASC
    LIMIT 1;

    IF NOT FOUND THEN
        -- Default to timestamp-based resolution
        v_rule.resolution_strategy := 'latest_timestamp_wins';
    END IF;

    -- Apply resolution strategy
    CASE v_rule.resolution_strategy
        WHEN 'latest_timestamp_wins' THEN
            SELECT region, timestamp INTO v_winning_region, v_winning_timestamp
            FROM conflict_resolution.region_modifications
            WHERE table_name = p_table_name
              AND record_id = p_record_id
            ORDER BY timestamp DESC
            LIMIT 1;

        WHEN 'us_east_priority' THEN
            SELECT region, timestamp INTO v_winning_region, v_winning_timestamp
            FROM conflict_resolution.region_modifications
            WHERE table_name = p_table_name
              AND record_id = p_record_id
            ORDER BY 
                CASE region 
                    WHEN 'us-east-1' THEN 1
                    WHEN 'eu-west-1' THEN 2
                    WHEN 'ap-southeast-1' THEN 3
                    ELSE 4
                END,
                timestamp DESC
            LIMIT 1;

        WHEN 'preserve_all' THEN
            -- Don't resolve, keep all versions
            v_winning_region := 'multiple';
            v_winning_timestamp := NOW();

        ELSE
            -- Default fallback
            SELECT region, timestamp INTO v_winning_region, v_winning_timestamp
            FROM conflict_resolution.region_modifications
            WHERE table_name = p_table_name
              AND record_id = p_record_id
            ORDER BY timestamp DESC
            LIMIT 1;
    END CASE;

    -- Build result JSON
    v_result := json_build_object(
        'table_name', p_table_name,
        'record_id', p_record_id,
        'winning_region', v_winning_region,
        'winning_timestamp', v_winning_timestamp,
        'resolution_strategy', v_rule.resolution_strategy,
        'resolved_at', NOW()
    );

    -- Log the resolution
    INSERT INTO conflict_resolution.region_modifications 
    (table_name, record_id, region, operation, timestamp, created_by)
    VALUES 
    (p_table_name, p_record_id, 'conflict_resolver', 'RESOLVE', NOW(), 'system');

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Function to track modifications (trigger function)
CREATE OR REPLACE FUNCTION conflict_resolution.track_modification()
RETURNS TRIGGER AS $$
DECLARE
    v_region VARCHAR(50);
    v_record_id VARCHAR(255);
    v_data_hash VARCHAR(64);
BEGIN
    -- Get current region (from environment variable or config)
    v_region := COALESCE(
        current_setting('app.current_region', true),
        'unknown'
    );

    -- Determine record ID (assumes 'id' column exists)
    IF TG_OP = 'DELETE' THEN
        v_record_id := OLD.id::TEXT;
        v_data_hash := md5(OLD::TEXT);
    ELSE
        v_record_id := NEW.id::TEXT;
        v_data_hash := md5(NEW::TEXT);
    END IF;

    -- Track the modification
    INSERT INTO conflict_resolution.region_modifications 
    (table_name, record_id, region, operation, data_hash, created_by)
    VALUES 
    (TG_TABLE_NAME, v_record_id, v_region, TG_OP, v_data_hash, session_user);

    -- Return appropriate record
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to create tracking triggers for a table
CREATE OR REPLACE FUNCTION conflict_resolution.enable_tracking(p_table_name VARCHAR(255))
RETURNS VOID AS $$
DECLARE
    v_trigger_name VARCHAR(255);
BEGIN
    v_trigger_name := 'track_modifications_' || replace(p_table_name, '.', '_');
    
    EXECUTE format('
        CREATE TRIGGER %I
        AFTER INSERT OR UPDATE OR DELETE ON %I
        FOR EACH ROW
        EXECUTE FUNCTION conflict_resolution.track_modification()
    ', v_trigger_name, p_table_name);
END;
$$ LANGUAGE plpgsql;

-- Function to disable tracking for a table
CREATE OR REPLACE FUNCTION conflict_resolution.disable_tracking(p_table_name VARCHAR(255))
RETURNS VOID AS $$
DECLARE
    v_trigger_name VARCHAR(255);
BEGIN
    v_trigger_name := 'track_modifications_' || replace(p_table_name, '.', '_');
    
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', v_trigger_name, p_table_name);
END;
$$ LANGUAGE plpgsql;

-- Function to get conflict resolution statistics
CREATE OR REPLACE FUNCTION conflict_resolution.get_conflict_stats(
    p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '24 hours',
    p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE(
    table_name VARCHAR(255),
    total_modifications BIGINT,
    unique_records BIGINT,
    regions_involved TEXT[],
    potential_conflicts BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH stats AS (
        SELECT 
            rm.table_name,
            COUNT(*) as total_modifications,
            COUNT(DISTINCT rm.record_id) as unique_records,
            array_agg(DISTINCT rm.region) as regions_involved
        FROM conflict_resolution.region_modifications rm
        WHERE rm.timestamp BETWEEN p_start_date AND p_end_date
          AND rm.operation != 'RESOLVE'
        GROUP BY rm.table_name
    ),
    conflicts AS (
        SELECT 
            rm.table_name,
            COUNT(DISTINCT rm.record_id) as potential_conflicts
        FROM conflict_resolution.region_modifications rm
        WHERE rm.timestamp BETWEEN p_start_date AND p_end_date
          AND rm.operation != 'RESOLVE'
        GROUP BY rm.table_name, rm.record_id
        HAVING COUNT(DISTINCT rm.region) > 1
        GROUP BY rm.table_name
    )
    SELECT 
        s.table_name,
        s.total_modifications,
        s.unique_records,
        s.regions_involved,
        COALESCE(c.potential_conflicts, 0) as potential_conflicts
    FROM stats s
    LEFT JOIN conflicts c ON s.table_name = c.table_name
    ORDER BY s.total_modifications DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old tracking data
CREATE OR REPLACE FUNCTION conflict_resolution.cleanup_old_data(
    p_retention_days INTEGER DEFAULT 30
)
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM conflict_resolution.region_modifications
    WHERE timestamp < NOW() - (p_retention_days || ' days')::INTERVAL;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_region_modifications_composite 
ON conflict_resolution.region_modifications (table_name, record_id, region, timestamp);

CREATE INDEX IF NOT EXISTS idx_region_modifications_cleanup 
ON conflict_resolution.region_modifications (timestamp) WHERE operation != 'RESOLVE';

-- Grant permissions to application users
GRANT USAGE ON SCHEMA conflict_resolution TO PUBLIC;
GRANT SELECT, INSERT ON conflict_resolution.region_modifications TO PUBLIC;
GRANT SELECT ON conflict_resolution.resolution_rules TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA conflict_resolution TO PUBLIC;

-- Example usage:
-- Enable tracking for important tables
-- SELECT conflict_resolution.enable_tracking('users');
-- SELECT conflict_resolution.enable_tracking('workspaces');
-- SELECT conflict_resolution.enable_tracking('airtable_records');

-- Check for conflicts
-- SELECT * FROM conflict_resolution.detect_conflicts('users', '123');

-- Resolve conflicts
-- SELECT conflict_resolution.resolve_conflict('users', '123', 'timestamp');

-- Get statistics
-- SELECT * FROM conflict_resolution.get_conflict_stats();

-- Cleanup old data (can be run via cron job)
-- SELECT conflict_resolution.cleanup_old_data(30);

COMMENT ON SCHEMA conflict_resolution IS 'Schema for managing cross-region data conflicts';
COMMENT ON TABLE conflict_resolution.region_modifications IS 'Tracks all modifications across regions for conflict detection';
COMMENT ON TABLE conflict_resolution.resolution_rules IS 'Defines how conflicts should be resolved for different tables';
COMMENT ON FUNCTION conflict_resolution.detect_conflicts IS 'Detects potential conflicts for a specific record';
COMMENT ON FUNCTION conflict_resolution.resolve_conflict IS 'Resolves conflicts based on configured rules';
COMMENT ON FUNCTION conflict_resolution.track_modification IS 'Trigger function to track table modifications';