-- Performance Optimization Migration
-- This migration adds performance-critical indexes, partitioning, and database optimizations

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Create performance monitoring view
CREATE OR REPLACE VIEW v_database_performance AS
SELECT 
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation,
    most_common_vals,
    most_common_freqs
FROM pg_stats 
WHERE schemaname = 'public'
ORDER BY tablename, attname;

-- Create index usage monitoring view
CREATE OR REPLACE VIEW v_index_usage AS
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes 
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Create slow query monitoring view
CREATE OR REPLACE VIEW v_slow_queries AS
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    stddev_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
WHERE mean_time > 100
ORDER BY mean_time DESC;

-- Optimize existing tables with better data types and constraints
-- Users table optimizations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email_hash ON users USING hash(email);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_created_at_desc ON users(created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_last_login ON users(last_login_at) WHERE last_login_at IS NOT NULL;

-- Sessions table optimizations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at) WHERE expires_at > NOW();
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_user_id_active ON sessions(user_id, expires_at) WHERE expires_at > NOW();

-- Workflow executions table optimizations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_workflow_executions_status_created ON workflow_executions(status, created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_workflow_executions_user_status ON workflow_executions(user_id, status) WHERE status IN ('running', 'pending', 'failed');

-- File uploads table optimizations
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_file_uploads_user_created ON file_uploads(user_id, created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_file_uploads_size ON file_uploads(file_size) WHERE file_size > 1048576; -- Files > 1MB

-- Analytics events table optimizations (prepare for partitioning)
-- First, create partitioned table structure
CREATE TABLE IF NOT EXISTS analytics_events_partitioned (
    id BIGSERIAL,
    user_id UUID REFERENCES users(id),
    event_type VARCHAR(100) NOT NULL,
    event_data JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Create monthly partitions for analytics events
CREATE TABLE IF NOT EXISTS analytics_events_y2024m01 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m02 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m03 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m04 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m05 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m06 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m07 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m08 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m09 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m10 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m11 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2024m12 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');

-- Create 2025 partitions
CREATE TABLE IF NOT EXISTS analytics_events_y2025m01 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m02 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m03 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m04 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-04-01') TO ('2025-05-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m05 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-05-01') TO ('2025-06-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m06 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-06-01') TO ('2025-07-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m07 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m08 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m09 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m10 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m11 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE IF NOT EXISTS analytics_events_y2025m12 PARTITION OF analytics_events_partitioned
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- Create indexes on partitioned table
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_analytics_events_part_user_event ON analytics_events_partitioned(user_id, event_type, created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_analytics_events_part_event_data ON analytics_events_partitioned USING gin(event_data);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_analytics_events_part_ip ON analytics_events_partitioned(ip_address) WHERE ip_address IS NOT NULL;

-- Create materialized view for analytics aggregations
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_daily_analytics AS
SELECT 
    DATE(created_at) as event_date,
    event_type,
    COUNT(*) as event_count,
    COUNT(DISTINCT user_id) as unique_users,
    COUNT(DISTINCT ip_address) as unique_ips
FROM analytics_events_partitioned
WHERE created_at >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY DATE(created_at), event_type
ORDER BY event_date DESC, event_count DESC;

-- Create unique index on materialized view
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_daily_analytics_unique ON mv_daily_analytics(event_date, event_type);

-- Create function to refresh materialized view
CREATE OR REPLACE FUNCTION refresh_analytics_mv()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_daily_analytics;
END;
$$ LANGUAGE plpgsql;

-- Create automatic partition management function
CREATE OR REPLACE FUNCTION create_monthly_partition(target_date DATE)
RETURNS void AS $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
BEGIN
    start_date := DATE_TRUNC('month', target_date);
    end_date := start_date + INTERVAL '1 month';
    partition_name := 'analytics_events_y' || TO_CHAR(start_date, 'YYYY') || 'm' || TO_CHAR(start_date, 'MM');
    
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF analytics_events_partitioned FOR VALUES FROM (%L) TO (%L)',
                   partition_name, start_date, end_date);
                   
    -- Create indexes on new partition
    EXECUTE format('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_%s_user_event ON %I(user_id, event_type, created_at DESC)',
                   partition_name, partition_name);
    EXECUTE format('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_%s_event_data ON %I USING gin(event_data)',
                   partition_name, partition_name);
END;
$$ LANGUAGE plpgsql;

-- Create function to drop old partitions
CREATE OR REPLACE FUNCTION drop_old_partitions(retention_months INTEGER DEFAULT 12)
RETURNS void AS $$
DECLARE
    partition_record RECORD;
    cutoff_date DATE;
BEGIN
    cutoff_date := CURRENT_DATE - (retention_months || ' months')::INTERVAL;
    
    FOR partition_record IN
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE tablename LIKE 'analytics_events_y%'
        AND schemaname = 'public'
    LOOP
        -- Extract date from partition name and check if it's old enough
        DECLARE
            partition_date DATE;
            year_part TEXT;
            month_part TEXT;
        BEGIN
            year_part := SUBSTRING(partition_record.tablename FROM 'y(\d{4})');
            month_part := SUBSTRING(partition_record.tablename FROM 'm(\d{2})');
            
            IF year_part IS NOT NULL AND month_part IS NOT NULL THEN
                partition_date := (year_part || '-' || month_part || '-01')::DATE;
                
                IF partition_date < cutoff_date THEN
                    EXECUTE format('DROP TABLE IF EXISTS %I.%I', partition_record.schemaname, partition_record.tablename);
                    RAISE NOTICE 'Dropped old partition: %', partition_record.tablename;
                END IF;
            END IF;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create query optimization hints table
CREATE TABLE IF NOT EXISTS query_hints (
    id SERIAL PRIMARY KEY,
    query_pattern TEXT NOT NULL,
    hint_type VARCHAR(50) NOT NULL,
    hint_value TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert common query optimization hints
INSERT INTO query_hints (query_pattern, hint_type, hint_value) VALUES
('SELECT.*FROM users WHERE email', 'use_index', 'idx_users_email_hash'),
('SELECT.*FROM sessions WHERE user_id', 'use_index', 'idx_sessions_user_id_active'),
('SELECT.*FROM analytics_events WHERE created_at', 'partition_pruning', 'enabled'),
('SELECT.*FROM workflow_executions WHERE status', 'use_index', 'idx_workflow_executions_status_created')
ON CONFLICT DO NOTHING;

-- Create connection pool monitoring table
CREATE TABLE IF NOT EXISTS connection_pool_stats (
    id SERIAL PRIMARY KEY,
    service_name VARCHAR(100) NOT NULL,
    max_connections INTEGER NOT NULL,
    active_connections INTEGER NOT NULL,
    idle_connections INTEGER NOT NULL,
    waiting_connections INTEGER NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index on connection pool stats
CREATE INDEX IF NOT EXISTS idx_connection_pool_stats_service_time ON connection_pool_stats(service_name, recorded_at DESC);

-- Create database maintenance function
CREATE OR REPLACE FUNCTION perform_maintenance()
RETURNS void AS $$
BEGIN
    -- Update table statistics
    ANALYZE;
    
    -- Refresh materialized views
    PERFORM refresh_analytics_mv();
    
    -- Clean up old connection pool stats (keep last 7 days)
    DELETE FROM connection_pool_stats WHERE recorded_at < NOW() - INTERVAL '7 days';
    
    -- Create next month's partition if needed
    PERFORM create_monthly_partition(CURRENT_DATE + INTERVAL '1 month');
    
    -- Drop partitions older than retention period
    PERFORM drop_old_partitions(12);
    
    -- Log maintenance completion
    INSERT INTO system_logs (level, message, created_at) 
    VALUES ('INFO', 'Database maintenance completed', NOW());
    
END;
$$ LANGUAGE plpgsql;

-- Create system logs table if it doesn't exist
CREATE TABLE IF NOT EXISTS system_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(20) NOT NULL,
    message TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create index on system logs
CREATE INDEX IF NOT EXISTS idx_system_logs_level_time ON system_logs(level, created_at DESC);

-- Set up automatic maintenance job (requires pg_cron extension in production)
-- This is commented out as pg_cron needs to be installed separately
-- SELECT cron.schedule('database-maintenance', '0 2 * * 0', 'SELECT perform_maintenance();');

-- Create performance baseline measurements
INSERT INTO system_logs (level, message, metadata) VALUES (
    'INFO', 
    'Performance optimization migration completed',
    jsonb_build_object(
        'migration_version', '009',
        'timestamp', NOW(),
        'tables_optimized', ARRAY['users', 'sessions', 'workflow_executions', 'file_uploads', 'analytics_events'],
        'partitions_created', 24,
        'indexes_created', 15,
        'views_created', 4,
        'functions_created', 5
    )
);

-- Grant necessary permissions
GRANT SELECT ON v_database_performance TO postgres;
GRANT SELECT ON v_index_usage TO postgres;
GRANT SELECT ON v_slow_queries TO postgres;
GRANT SELECT ON mv_daily_analytics TO postgres;

-- Create read-only user for monitoring
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'monitoring_user') THEN
        CREATE ROLE monitoring_user WITH LOGIN PASSWORD 'monitoring_password_change_me';
    END IF;
END
$$;

-- Grant monitoring permissions
GRANT CONNECT ON DATABASE postgres TO monitoring_user;
GRANT USAGE ON SCHEMA public TO monitoring_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO monitoring_user;
GRANT SELECT ON v_database_performance, v_index_usage, v_slow_queries, mv_daily_analytics TO monitoring_user;

-- Create database configuration recommendations
CREATE TABLE IF NOT EXISTS db_config_recommendations (
    id SERIAL PRIMARY KEY,
    parameter_name VARCHAR(100) NOT NULL,
    recommended_value TEXT NOT NULL,
    current_value TEXT,
    description TEXT,
    impact_level VARCHAR(20) DEFAULT 'medium',
    applied BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert performance tuning recommendations
INSERT INTO db_config_recommendations (parameter_name, recommended_value, description, impact_level) VALUES
('shared_buffers', '256MB', 'Amount of memory dedicated to PostgreSQL for caching data', 'high'),
('effective_cache_size', '1GB', 'Estimate of how much memory is available for disk caching', 'high'),
('work_mem', '32MB', 'Amount of memory to be used by internal sort operations', 'medium'),
('maintenance_work_mem', '256MB', 'Maximum amount of memory for maintenance operations', 'medium'),
('checkpoint_completion_target', '0.9', 'Target for checkpoint completion as fraction of checkpoint interval', 'medium'),
('wal_buffers', '16MB', 'Amount of shared memory used for WAL data', 'low'),
('default_statistics_target', '100', 'Default amount of information stored in pg_statistic', 'medium'),
('random_page_cost', '1.1', 'Cost of a non-sequentially-fetched disk page', 'medium'),
('max_connections', '100', 'Maximum number of concurrent connections', 'high'),
('shared_preload_libraries', 'pg_stat_statements', 'Libraries to preload into server', 'medium')
ON CONFLICT DO NOTHING;

COMMIT;