-- Migration: TimescaleDB Implementation
-- Created: 2025-08-01
-- Description: Install TimescaleDB and convert time-series tables to hypertables

-- Install TimescaleDB extension
-- Note: This requires TimescaleDB to be installed in the PostgreSQL instance
-- Add to Dockerfile: RUN apt-get install -y timescaledb-2-postgresql-16
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Convert api_usage_logs to hypertable for better time-series performance
-- Chunk by day for optimal query performance and data retention
SELECT create_hypertable(
    'api_usage_logs', 
    'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- Convert conversation_messages to hypertable
-- Chunk by week since messages are less frequent than API calls
SELECT create_hypertable(
    'conversation_messages', 
    'timestamp',
    chunk_time_interval => INTERVAL '1 week',
    if_not_exists => TRUE
);

-- Add compression policy for older data (compress data older than 7 days)
SELECT add_compression_policy(
    'api_usage_logs', 
    INTERVAL '7 days',
    if_not_exists => TRUE
);

SELECT add_compression_policy(
    'conversation_messages', 
    INTERVAL '30 days',
    if_not_exists => TRUE
);

-- Add data retention policy (remove data older than 1 year)
SELECT add_retention_policy(
    'api_usage_logs', 
    INTERVAL '1 year',
    if_not_exists => TRUE
);

SELECT add_retention_policy(
    'conversation_messages', 
    INTERVAL '2 years',
    if_not_exists => TRUE
);

-- Create time-bucketed continuous aggregates for common queries

-- Hourly API usage statistics
CREATE MATERIALIZED VIEW IF NOT EXISTS api_usage_hourly
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', timestamp) AS hour,
    service_name,
    COUNT(*) as total_requests,
    SUM(input_tokens) as total_input_tokens,
    SUM(output_tokens) as total_output_tokens,
    SUM(total_tokens) as total_tokens,
    SUM(CAST(cost AS DECIMAL(10,6))) as total_cost,
    AVG(response_time_ms) as avg_response_time,
    COUNT(CASE WHEN success = true THEN 1 END) as successful_requests,
    COUNT(CASE WHEN success = false THEN 1 END) as failed_requests,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY response_time_ms) as p95_response_time
FROM api_usage_logs
GROUP BY hour, service_name
WITH NO DATA;

-- Daily API usage statistics  
CREATE MATERIALIZED VIEW IF NOT EXISTS api_usage_daily
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 day', timestamp) AS day,
    service_name,
    COUNT(*) as total_requests,
    SUM(input_tokens) as total_input_tokens,
    SUM(output_tokens) as total_output_tokens,
    SUM(total_tokens) as total_tokens,
    SUM(CAST(cost AS DECIMAL(10,6))) as total_cost,
    AVG(response_time_ms) as avg_response_time,
    COUNT(CASE WHEN success = true THEN 1 END) as successful_requests,
    COUNT(CASE WHEN success = false THEN 1 END) as failed_requests,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY response_time_ms) as p95_response_time
FROM api_usage_logs
GROUP BY day, service_name
WITH NO DATA;

-- Hourly conversation activity
CREATE MATERIALIZED VIEW IF NOT EXISTS conversation_activity_hourly
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', timestamp) AS hour,
    role,
    COUNT(*) as message_count,
    AVG(token_count) as avg_tokens,
    SUM(token_count) as total_tokens,
    AVG(CAST(cost AS DECIMAL(10,6))) as avg_cost,
    SUM(CAST(cost AS DECIMAL(10,6))) as total_cost,
    AVG(response_time_ms) as avg_response_time,
    COUNT(DISTINCT session_id) as unique_sessions
FROM conversation_messages
GROUP BY hour, role
WITH NO DATA;

-- Add refresh policies for continuous aggregates
SELECT add_continuous_aggregate_policy(
    'api_usage_hourly',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

SELECT add_continuous_aggregate_policy(
    'api_usage_daily',
    start_offset => INTERVAL '2 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

SELECT add_continuous_aggregate_policy(
    'conversation_activity_hourly',
    start_offset => INTERVAL '6 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- Create optimized time-series analytics functions

-- Function to get API usage trends
CREATE OR REPLACE FUNCTION get_api_usage_trend(
    service_filter TEXT DEFAULT NULL,
    time_range INTERVAL DEFAULT INTERVAL '24 hours',
    bucket_size INTERVAL DEFAULT INTERVAL '1 hour'
) RETURNS TABLE(
    time_bucket TIMESTAMP WITH TIME ZONE,
    service_name VARCHAR(100),
    total_requests BIGINT,
    total_cost DECIMAL(12,6),
    avg_response_time DOUBLE PRECISION,
    success_rate DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        time_bucket(bucket_size, timestamp) as time_bucket,
        aul.service_name,
        COUNT(*)::BIGINT as total_requests,
        SUM(CAST(aul.cost AS DECIMAL(10,6)))::DECIMAL(12,6) as total_cost,
        AVG(aul.response_time_ms)::DOUBLE PRECISION as avg_response_time,
        (COUNT(CASE WHEN aul.success = true THEN 1 END)::DOUBLE PRECISION / COUNT(*)::DOUBLE PRECISION * 100)::DOUBLE PRECISION as success_rate
    FROM api_usage_logs aul
    WHERE timestamp >= NOW() - time_range
        AND (service_filter IS NULL OR aul.service_name = service_filter)
    GROUP BY time_bucket, aul.service_name
    ORDER BY time_bucket DESC, aul.service_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get conversation patterns
CREATE OR REPLACE FUNCTION get_conversation_patterns(
    time_range INTERVAL DEFAULT INTERVAL '7 days',
    bucket_size INTERVAL DEFAULT INTERVAL '1 hour'
) RETURNS TABLE(
    time_bucket TIMESTAMP WITH TIME ZONE,
    role VARCHAR(50),
    message_count BIGINT,
    avg_tokens DOUBLE PRECISION,
    unique_sessions BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        time_bucket(bucket_size, timestamp) as time_bucket,
        cm.role,
        COUNT(*)::BIGINT as message_count,
        AVG(cm.token_count)::DOUBLE PRECISION as avg_tokens,
        COUNT(DISTINCT cm.session_id)::BIGINT as unique_sessions
    FROM conversation_messages cm
    WHERE timestamp >= NOW() - time_range
    GROUP BY time_bucket, cm.role
    ORDER BY time_bucket DESC, cm.role;
END;
$$ LANGUAGE plpgsql;

-- Function to get cost analytics
CREATE OR REPLACE FUNCTION get_cost_breakdown(
    time_range INTERVAL DEFAULT INTERVAL '30 days',
    group_by_service BOOLEAN DEFAULT TRUE
) RETURNS TABLE(
    service_name VARCHAR(100),
    total_cost DECIMAL(12,6),
    total_tokens BIGINT,
    cost_per_token DECIMAL(10,8),
    request_count BIGINT,
    avg_cost_per_request DECIMAL(10,6)
) AS $$
BEGIN
    IF group_by_service THEN
        RETURN QUERY
        SELECT 
            aul.service_name,
            SUM(CAST(aul.cost AS DECIMAL(10,6)))::DECIMAL(12,6) as total_cost,
            SUM(aul.total_tokens)::BIGINT as total_tokens,
            (SUM(CAST(aul.cost AS DECIMAL(10,6))) / NULLIF(SUM(aul.total_tokens), 0))::DECIMAL(10,8) as cost_per_token,
            COUNT(*)::BIGINT as request_count,
            AVG(CAST(aul.cost AS DECIMAL(10,6)))::DECIMAL(10,6) as avg_cost_per_request
        FROM api_usage_logs aul
        WHERE timestamp >= NOW() - time_range
        GROUP BY aul.service_name
        ORDER BY total_cost DESC;
    ELSE
        RETURN QUERY
        SELECT 
            'TOTAL'::VARCHAR(100) as service_name,
            SUM(CAST(aul.cost AS DECIMAL(10,6)))::DECIMAL(12,6) as total_cost,
            SUM(aul.total_tokens)::BIGINT as total_tokens,
            (SUM(CAST(aul.cost AS DECIMAL(10,6))) / NULLIF(SUM(aul.total_tokens), 0))::DECIMAL(10,8) as cost_per_token,
            COUNT(*)::BIGINT as request_count,
            AVG(CAST(aul.cost AS DECIMAL(10,6)))::DECIMAL(10,6) as avg_cost_per_request
        FROM api_usage_logs aul
        WHERE timestamp >= NOW() - time_range;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create monitoring views for TimescaleDB
CREATE OR REPLACE VIEW timescaledb_info AS
SELECT 
    hypertable_schema,
    hypertable_name,
    num_chunks,
    compressed_chunks,
    uncompressed_chunks,
    compression_status
FROM timescaledb_information.hypertables h
LEFT JOIN (
    SELECT 
        hypertable_name,
        COUNT(*) as num_chunks,
        COUNT(CASE WHEN compressed_chunk_id IS NOT NULL THEN 1 END) as compressed_chunks,
        COUNT(CASE WHEN compressed_chunk_id IS NULL THEN 1 END) as uncompressed_chunks,
        ROUND(COUNT(CASE WHEN compressed_chunk_id IS NOT NULL THEN 1 END)::DECIMAL / COUNT(*)::DECIMAL * 100, 2) as compression_status
    FROM timescaledb_information.chunks
    GROUP BY hypertable_name
) chunk_stats ON h.hypertable_name = chunk_stats.hypertable_name;

-- Create compression monitoring view
CREATE OR REPLACE VIEW compression_stats AS
SELECT 
    chunk_schema,
    chunk_name,
    table_name,
    compression_status,
    before_compression_table_bytes,
    before_compression_index_bytes,
    before_compression_total_bytes,
    after_compression_table_bytes,
    after_compression_index_bytes,
    after_compression_total_bytes,
    ROUND(
        (before_compression_total_bytes - after_compression_total_bytes)::DECIMAL / 
        before_compression_total_bytes::DECIMAL * 100, 2
    ) as compression_ratio_percent
FROM timescaledb_information.compressed_chunk_stats
ORDER BY compression_ratio_percent DESC;

-- Grant permissions
GRANT SELECT ON api_usage_hourly TO PUBLIC;
GRANT SELECT ON api_usage_daily TO PUBLIC;
GRANT SELECT ON conversation_activity_hourly TO PUBLIC;
GRANT SELECT ON timescaledb_info TO PUBLIC;
GRANT SELECT ON compression_stats TO PUBLIC;

GRANT EXECUTE ON FUNCTION get_api_usage_trend(TEXT, INTERVAL, INTERVAL) TO application_user;
GRANT EXECUTE ON FUNCTION get_conversation_patterns(INTERVAL, INTERVAL) TO application_user;
GRANT EXECUTE ON FUNCTION get_cost_breakdown(INTERVAL, BOOLEAN) TO application_user;

-- Log completion
INSERT INTO migration_log (migration_name, executed_at, description) 
VALUES ('005_implement_timescaledb', NOW(), 'Implemented TimescaleDB with hypertables, compression, and continuous aggregates')
ON CONFLICT DO NOTHING;