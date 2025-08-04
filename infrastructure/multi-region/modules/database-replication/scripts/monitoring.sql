-- Database Monitoring Scripts for PostgreSQL Multi-Region Setup
-- These scripts help monitor replication health, performance, and conflicts

-- Create schema for monitoring
CREATE SCHEMA IF NOT EXISTS monitoring;

-- Create table for monitoring metrics
CREATE TABLE IF NOT EXISTS monitoring.replication_metrics (
    id SERIAL PRIMARY KEY,
    metric_name VARCHAR(255) NOT NULL,
    metric_value NUMERIC,
    metric_unit VARCHAR(50),
    region VARCHAR(50) NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB,
    INDEX idx_replication_metrics_name_time (metric_name, timestamp),
    INDEX idx_replication_metrics_region (region)
);

-- Function to collect replication lag metrics
CREATE OR REPLACE FUNCTION monitoring.get_replication_lag()
RETURNS TABLE(
    application_name TEXT,
    client_addr INET,
    state TEXT,
    sent_lsn PG_LSN,
    write_lsn PG_LSN,
    flush_lsn PG_LSN,
    replay_lsn PG_LSN,
    write_lag INTERVAL,
    flush_lag INTERVAL,
    replay_lag INTERVAL,
    sync_state TEXT
) AS $$
BEGIN
    -- Only available on primary server
    IF pg_is_in_recovery() THEN
        RAISE NOTICE 'This function should be run on the primary server';
        RETURN;
    END IF;

    RETURN QUERY
    SELECT 
        sr.application_name,
        sr.client_addr,
        sr.state,
        sr.sent_lsn,
        sr.write_lsn,
        sr.flush_lsn,
        sr.replay_lsn,
        sr.write_lag,
        sr.flush_lag,
        sr.replay_lag,
        sr.sync_state
    FROM pg_stat_replication sr
    ORDER BY sr.application_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get WAL statistics
CREATE OR REPLACE FUNCTION monitoring.get_wal_stats()
RETURNS TABLE(
    current_wal_lsn PG_LSN,
    wal_records BIGINT,
    wal_fpi BIGINT,
    wal_bytes NUMERIC,
    wal_buffers_full BIGINT,
    wal_write_time DOUBLE PRECISION,
    wal_sync_time DOUBLE PRECISION
) AS $$
BEGIN
    IF pg_is_in_recovery() THEN
        -- Return replay information for replica
        RETURN QUERY
        SELECT 
            pg_last_wal_replay_lsn() as current_wal_lsn,
            NULL::BIGINT as wal_records,
            NULL::BIGINT as wal_fpi,
            NULL::NUMERIC as wal_bytes,
            NULL::BIGINT as wal_buffers_full,
            NULL::DOUBLE PRECISION as wal_write_time,
            NULL::DOUBLE PRECISION as wal_sync_time;
    ELSE
        -- Return WAL generation information for primary
        RETURN QUERY
        SELECT 
            pg_current_wal_lsn() as current_wal_lsn,
            wal_records,
            wal_fpi,
            wal_bytes,
            wal_buffers_full,
            wal_write_time,
            wal_sync_time
        FROM pg_stat_wal;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to check database connectivity and basic health
CREATE OR REPLACE FUNCTION monitoring.health_check()
RETURNS JSON AS $$
DECLARE
    v_result JSON;
    v_is_replica BOOLEAN;
    v_db_size BIGINT;
    v_connections INTEGER;
    v_max_connections INTEGER;
    v_uptime INTERVAL;
BEGIN
    -- Basic health information
    SELECT pg_is_in_recovery() INTO v_is_replica;
    SELECT pg_database_size(current_database()) INTO v_db_size;
    SELECT count(*) FROM pg_stat_activity WHERE state = 'active' INTO v_connections;
    SELECT setting::INTEGER FROM pg_settings WHERE name = 'max_connections' INTO v_max_connections;
    SELECT now() - pg_postmaster_start_time() INTO v_uptime;

    v_result := json_build_object(
        'timestamp', now(),
        'is_replica', v_is_replica,
        'database_size_bytes', v_db_size,
        'database_size_mb', round(v_db_size / 1024.0 / 1024.0, 2),
        'active_connections', v_connections,
        'max_connections', v_max_connections,
        'connection_utilization_percent', round((v_connections::NUMERIC / v_max_connections * 100), 2),
        'uptime', v_uptime,
        'version', version()
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Function to get slow queries
CREATE OR REPLACE FUNCTION monitoring.get_slow_queries(
    p_min_duration_ms INTEGER DEFAULT 1000,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
    query_id BIGINT,
    query TEXT,
    calls BIGINT,
    total_time DOUBLE PRECISION,
    mean_time DOUBLE PRECISION,
    max_time DOUBLE PRECISION,
    min_time DOUBLE PRECISION,
    stddev_time DOUBLE PRECISION,
    rows BIGINT,
    shared_blks_hit BIGINT,
    shared_blks_read BIGINT
) AS $$
BEGIN
    -- Requires pg_stat_statements extension
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        RAISE EXCEPTION 'pg_stat_statements extension is not installed';
    END IF;

    RETURN QUERY
    SELECT 
        pss.queryid as query_id,
        pss.query,
        pss.calls,
        pss.total_exec_time as total_time,
        pss.mean_exec_time as mean_time,
        pss.max_exec_time as max_time,
        pss.min_exec_time as min_time,
        pss.stddev_exec_time as stddev_time,
        pss.rows,
        pss.shared_blks_hit,
        pss.shared_blks_read
    FROM pg_stat_statements pss
    WHERE pss.mean_exec_time >= p_min_duration_ms
    ORDER BY pss.total_exec_time DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to get table statistics
CREATE OR REPLACE FUNCTION monitoring.get_table_stats(p_schema_name TEXT DEFAULT 'public')
RETURNS TABLE(
    schema_name TEXT,
    table_name TEXT,
    row_count BIGINT,
    table_size_bytes BIGINT,
    table_size_mb NUMERIC,
    index_size_bytes BIGINT,
    index_size_mb NUMERIC,
    total_size_mb NUMERIC,
    seq_scans BIGINT,
    seq_tup_read BIGINT,
    idx_scans BIGINT,
    idx_tup_fetch BIGINT,
    n_tup_ins BIGINT,
    n_tup_upd BIGINT,
    n_tup_del BIGINT,
    n_tup_hot_upd BIGINT,
    vacuum_count BIGINT,
    autovacuum_count BIGINT,
    analyze_count BIGINT,
    autoanalyze_count BIGINT,
    last_vacuum TIMESTAMP WITH TIME ZONE,
    last_autovacuum TIMESTAMP WITH TIME ZONE,
    last_analyze TIMESTAMP WITH TIME ZONE,
    last_autoanalyze TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.schemaname::TEXT as schema_name,
        s.tablename::TEXT as table_name,
        s.n_tup_ins + s.n_tup_upd - s.n_tup_del as row_count,
        pg_table_size(c.oid) as table_size_bytes,
        round(pg_table_size(c.oid) / 1024.0 / 1024.0, 2) as table_size_mb,
        pg_indexes_size(c.oid) as index_size_bytes,
        round(pg_indexes_size(c.oid) / 1024.0 / 1024.0, 2) as index_size_mb,
        round(pg_total_relation_size(c.oid) / 1024.0 / 1024.0, 2) as total_size_mb,
        s.seq_scan as seq_scans,
        s.seq_tup_read,
        s.idx_scan as idx_scans,
        s.idx_tup_fetch,
        s.n_tup_ins,
        s.n_tup_upd,
        s.n_tup_del,
        s.n_tup_hot_upd,
        s.vacuum_count,
        s.autovacuum_count,
        s.analyze_count,
        s.autoanalyze_count,
        s.last_vacuum,
        s.last_autovacuum,
        s.last_analyze,
        s.last_autoanalyze
    FROM pg_stat_user_tables s
    JOIN pg_class c ON c.relname = s.tablename
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE s.schemaname = p_schema_name
    ORDER BY pg_total_relation_size(c.oid) DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to collect and store metrics
CREATE OR REPLACE FUNCTION monitoring.collect_metrics()
RETURNS INTEGER AS $$
DECLARE
    v_region VARCHAR(50);
    v_metrics_count INTEGER := 0;
    v_health JSON;
    v_wal_stats RECORD;
    v_repl_lag RECORD;
BEGIN
    -- Get current region
    v_region := COALESCE(
        current_setting('app.current_region', true),
        'unknown'
    );

    -- Collect health metrics
    SELECT monitoring.health_check() INTO v_health;
    
    INSERT INTO monitoring.replication_metrics 
    (metric_name, metric_value, metric_unit, region, metadata)
    VALUES 
    ('database_size_mb', (v_health->>'database_size_mb')::NUMERIC, 'MB', v_region, v_health),
    ('active_connections', (v_health->>'active_connections')::NUMERIC, 'count', v_region, v_health),
    ('connection_utilization_percent', (v_health->>'connection_utilization_percent')::NUMERIC, 'percent', v_region, v_health);
    
    v_metrics_count := v_metrics_count + 3;

    -- Collect WAL metrics
    SELECT * FROM monitoring.get_wal_stats() INTO v_wal_stats;
    
    IF v_wal_stats.wal_records IS NOT NULL THEN
        INSERT INTO monitoring.replication_metrics 
        (metric_name, metric_value, metric_unit, region, metadata)
        VALUES 
        ('wal_records', v_wal_stats.wal_records, 'count', v_region, row_to_json(v_wal_stats)),
        ('wal_bytes', v_wal_stats.wal_bytes, 'bytes', v_region, row_to_json(v_wal_stats)),
        ('wal_write_time', v_wal_stats.wal_write_time, 'milliseconds', v_region, row_to_json(v_wal_stats)),
        ('wal_sync_time', v_wal_stats.wal_sync_time, 'milliseconds', v_region, row_to_json(v_wal_stats));
        
        v_metrics_count := v_metrics_count + 4;
    END IF;

    -- Collect replication lag metrics (only on primary)
    IF NOT pg_is_in_recovery() THEN
        FOR v_repl_lag IN SELECT * FROM monitoring.get_replication_lag() LOOP
            INSERT INTO monitoring.replication_metrics 
            (metric_name, metric_value, metric_unit, region, metadata)
            VALUES 
            ('replication_write_lag_ms', 
             EXTRACT(EPOCH FROM v_repl_lag.write_lag) * 1000, 
             'milliseconds', 
             v_region, 
             row_to_json(v_repl_lag)),
            ('replication_flush_lag_ms', 
             EXTRACT(EPOCH FROM v_repl_lag.flush_lag) * 1000, 
             'milliseconds', 
             v_region, 
             row_to_json(v_repl_lag)),
            ('replication_replay_lag_ms', 
             EXTRACT(EPOCH FROM v_repl_lag.replay_lag) * 1000, 
             'milliseconds', 
             v_region, 
             row_to_json(v_repl_lag));
            
            v_metrics_count := v_metrics_count + 3;
        END LOOP;
    END IF;

    RETURN v_metrics_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get monitoring dashboard data
CREATE OR REPLACE FUNCTION monitoring.get_dashboard_data(
    p_hours_back INTEGER DEFAULT 24
)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
    v_health JSON;
    v_recent_metrics JSON;
    v_slow_queries JSON;
    v_table_stats JSON;
BEGIN
    -- Get current health
    SELECT monitoring.health_check() INTO v_health;
    
    -- Get recent metrics
    SELECT json_agg(
        json_build_object(
            'metric_name', metric_name,
            'metric_value', metric_value,
            'metric_unit', metric_unit,
            'region', region,
            'timestamp', timestamp
        )
    ) INTO v_recent_metrics
    FROM monitoring.replication_metrics
    WHERE timestamp >= NOW() - (p_hours_back || ' hours')::INTERVAL
    ORDER BY timestamp DESC;
    
    -- Get slow queries (if extension available)
    BEGIN
        SELECT json_agg(row_to_json(sq)) INTO v_slow_queries
        FROM (
            SELECT * FROM monitoring.get_slow_queries(1000, 10)
        ) sq;
    EXCEPTION
        WHEN OTHERS THEN
            v_slow_queries := json_build_array();
    END;
    
    -- Get table statistics
    SELECT json_agg(row_to_json(ts)) INTO v_table_stats
    FROM (
        SELECT * FROM monitoring.get_table_stats('public')
        ORDER BY total_size_mb DESC
        LIMIT 10
    ) ts;
    
    -- Build complete dashboard
    v_result := json_build_object(
        'timestamp', NOW(),
        'health', v_health,
        'recent_metrics', COALESCE(v_recent_metrics, json_build_array()),
        'slow_queries', COALESCE(v_slow_queries, json_build_array()),
        'top_tables', COALESCE(v_table_stats, json_build_array())
    );
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old metrics
CREATE OR REPLACE FUNCTION monitoring.cleanup_old_metrics(
    p_retention_days INTEGER DEFAULT 7
)
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM monitoring.replication_metrics
    WHERE timestamp < NOW() - (p_retention_days || ' days')::INTERVAL;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_replication_metrics_timestamp 
ON monitoring.replication_metrics (timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_replication_metrics_region_name 
ON monitoring.replication_metrics (region, metric_name);

-- Grant permissions
GRANT USAGE ON SCHEMA monitoring TO PUBLIC;
GRANT SELECT, INSERT ON monitoring.replication_metrics TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA monitoring TO PUBLIC;

-- Views for common monitoring queries
CREATE OR REPLACE VIEW monitoring.current_replication_status AS
SELECT 
    application_name,
    client_addr,
    state,
    EXTRACT(EPOCH FROM write_lag) * 1000 as write_lag_ms,
    EXTRACT(EPOCH FROM flush_lag) * 1000 as flush_lag_ms,
    EXTRACT(EPOCH FROM replay_lag) * 1000 as replay_lag_ms,
    sync_state
FROM monitoring.get_replication_lag();

CREATE OR REPLACE VIEW monitoring.recent_metrics AS
SELECT 
    metric_name,
    metric_value,
    metric_unit,
    region,
    timestamp
FROM monitoring.replication_metrics
WHERE timestamp >= NOW() - INTERVAL '1 hour'
ORDER BY timestamp DESC;

-- Example usage queries:
-- Get current health status
-- SELECT monitoring.health_check();

-- Get replication lag (run on primary)
-- SELECT * FROM monitoring.get_replication_lag();

-- Get recent slow queries
-- SELECT * FROM monitoring.get_slow_queries(5000, 5);

-- Get table statistics
-- SELECT * FROM monitoring.get_table_stats('public');

-- Collect current metrics
-- SELECT monitoring.collect_metrics();

-- Get dashboard data
-- SELECT monitoring.get_dashboard_data(24);

-- Clean up old data
-- SELECT monitoring.cleanup_old_metrics(7);

COMMENT ON SCHEMA monitoring IS 'Schema for database monitoring and health checks';
COMMENT ON TABLE monitoring.replication_metrics IS 'Stores monitoring metrics over time';
COMMENT ON FUNCTION monitoring.health_check IS 'Returns basic database health information';
COMMENT ON FUNCTION monitoring.get_replication_lag IS 'Returns replication lag information (primary only)';
COMMENT ON FUNCTION monitoring.collect_metrics IS 'Collects and stores current metrics';