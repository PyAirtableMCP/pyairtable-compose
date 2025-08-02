-- Migration: JSONB Performance Optimization
-- Created: 2025-08-01
-- Description: Add GIN indexes for JSONB columns and implement JSONB search functions

-- Add GIN indexes for JSONB columns to improve query performance
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversation_sessions_metadata_gin 
ON conversation_sessions USING GIN (metadata);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversation_messages_tools_used_gin 
ON conversation_messages USING GIN (tools_used);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversation_messages_metadata_gin 
ON conversation_messages USING GIN (metadata);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_api_usage_logs_metadata_gin 
ON api_usage_logs USING GIN (metadata);

-- Add GIN indexes for specific JSONB keys that are frequently queried
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_metadata_base_id 
ON conversation_sessions USING GIN ((metadata->>'base_id'));

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_metadata_model 
ON conversation_messages USING GIN ((metadata->>'model'));

-- Create utility functions for JSONB operations

-- Function to search for specific keys in JSONB metadata
CREATE OR REPLACE FUNCTION search_metadata_key(
    table_name TEXT,
    key_path TEXT,
    search_value TEXT
) RETURNS TABLE(record_id UUID, metadata_value TEXT) AS $$
DECLARE
    query_text TEXT;
BEGIN
    query_text := format('
        SELECT id, metadata->>%L as metadata_value
        FROM %I 
        WHERE metadata->>%L = %L
    ', key_path, table_name, key_path, search_value);
    
    RETURN QUERY EXECUTE query_text;
END;
$$ LANGUAGE plpgsql;

-- Function to update JSONB metadata efficiently
CREATE OR REPLACE FUNCTION update_metadata_field(
    table_name TEXT,
    record_id UUID,
    key_path TEXT,
    new_value TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    query_text TEXT;
    rows_updated INTEGER;
BEGIN
    query_text := format('
        UPDATE %I 
        SET metadata = jsonb_set(metadata, %L, %L, true),
            updated_at = NOW()
        WHERE id = %L
    ', table_name, ARRAY[key_path], to_jsonb(new_value), record_id);
    
    EXECUTE query_text;
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    
    RETURN rows_updated > 0;
END;
$$ LANGUAGE plpgsql;

-- Function to merge JSONB data
CREATE OR REPLACE FUNCTION merge_metadata(
    table_name TEXT,
    record_id UUID,
    new_metadata JSONB
) RETURNS BOOLEAN AS $$
DECLARE
    query_text TEXT;
    rows_updated INTEGER;
BEGIN
    query_text := format('
        UPDATE %I 
        SET metadata = metadata || %L,
            updated_at = NOW()
        WHERE id = %L
    ', table_name, new_metadata, record_id);
    
    EXECUTE query_text;
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    
    RETURN rows_updated > 0;
END;
$$ LANGUAGE plpgsql;

-- Create analytics views using JSONB functions

-- View for session metadata analysis
CREATE OR REPLACE VIEW session_metadata_stats AS
SELECT 
    metadata->>'base_id' as base_id,
    metadata->>'thinking_budget' as thinking_budget,
    metadata->>'temperature' as temperature,
    COUNT(*) as session_count,
    AVG(total_tokens_used) as avg_tokens_used,
    AVG(CAST(total_cost AS DECIMAL(10,6))) as avg_cost
FROM conversation_sessions 
WHERE metadata IS NOT NULL
GROUP BY metadata->>'base_id', metadata->>'thinking_budget', metadata->>'temperature'
ORDER BY session_count DESC;

-- View for message tool usage analysis
CREATE OR REPLACE VIEW tool_usage_stats AS
SELECT 
    tool_name,
    COUNT(*) as usage_count,
    AVG(token_count) as avg_tokens,
    AVG(response_time_ms) as avg_response_time
FROM (
    SELECT 
        jsonb_array_elements_text(tools_used) as tool_name,
        token_count,
        response_time_ms
    FROM conversation_messages 
    WHERE tools_used IS NOT NULL AND tools_used != 'null'::jsonb
) tool_data
GROUP BY tool_name
ORDER BY usage_count DESC;

-- Performance monitoring for JSONB operations
CREATE OR REPLACE VIEW jsonb_performance_stats AS
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE indexname LIKE '%_gin'
ORDER BY idx_scan DESC;

-- Grant permissions
GRANT SELECT ON session_metadata_stats TO PUBLIC;
GRANT SELECT ON tool_usage_stats TO PUBLIC;
GRANT SELECT ON jsonb_performance_stats TO PUBLIC;
GRANT EXECUTE ON FUNCTION search_metadata_key(TEXT, TEXT, TEXT) TO application_user;
GRANT EXECUTE ON FUNCTION update_metadata_field(TEXT, UUID, TEXT, TEXT) TO application_user;
GRANT EXECUTE ON FUNCTION merge_metadata(TEXT, UUID, JSONB) TO application_user;

-- Log completion
INSERT INTO migration_log (migration_name, executed_at, description) 
VALUES ('003_implement_jsonb_optimization', NOW(), 'Added GIN indexes and utility functions for JSONB optimization')
ON CONFLICT DO NOTHING;