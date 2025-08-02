-- Migration: Full-Text Search Implementation
-- Created: 2025-08-01
-- Description: Add full-text search capabilities with tsvector columns and fuzzy search

-- Add tsvector columns for full-text search
ALTER TABLE conversation_messages 
ADD COLUMN IF NOT EXISTS message_search_vector tsvector;

ALTER TABLE files 
ADD COLUMN IF NOT EXISTS content_search_vector tsvector;

-- Create GIN indexes for full-text search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_search_vector 
ON conversation_messages USING GIN (message_search_vector);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_files_content_search_vector 
ON files USING GIN (content_search_vector);

-- Create trigram indexes for fuzzy search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_message_trgm 
ON conversation_messages USING GIN (message gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_files_filename_trgm 
ON files USING GIN (filename gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_files_original_filename_trgm 
ON files USING GIN (original_filename gin_trgm_ops);

-- Create functions to update search vectors

-- Function to update message search vector
CREATE OR REPLACE FUNCTION update_message_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.message_search_vector := 
        setweight(to_tsvector('english', COALESCE(NEW.message, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.thinking_process, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.role, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to update file content search vector
CREATE OR REPLACE FUNCTION update_file_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.content_search_vector := 
        setweight(to_tsvector('english', COALESCE(NEW.filename, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.original_filename, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.extracted_content, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.mime_type, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to automatically update search vectors
DROP TRIGGER IF EXISTS message_search_vector_update ON conversation_messages;
CREATE TRIGGER message_search_vector_update 
    BEFORE INSERT OR UPDATE ON conversation_messages
    FOR EACH ROW EXECUTE FUNCTION update_message_search_vector();

DROP TRIGGER IF EXISTS file_search_vector_update ON files;
CREATE TRIGGER file_search_vector_update 
    BEFORE INSERT OR UPDATE ON files
    FOR EACH ROW EXECUTE FUNCTION update_file_search_vector();

-- Update existing records with search vectors
UPDATE conversation_messages 
SET message_search_vector = 
    setweight(to_tsvector('english', COALESCE(message, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(thinking_process, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(role, '')), 'C')
WHERE message_search_vector IS NULL;

UPDATE files 
SET content_search_vector = 
    setweight(to_tsvector('english', COALESCE(filename, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(original_filename, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(extracted_content, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(mime_type, '')), 'C')
WHERE content_search_vector IS NULL;

-- Create search functions

-- Advanced message search function
CREATE OR REPLACE FUNCTION search_messages(
    search_query TEXT,
    user_context TEXT DEFAULT NULL,
    limit_results INTEGER DEFAULT 50
) RETURNS TABLE(
    message_id UUID,
    session_id VARCHAR(255),
    role VARCHAR(50),
    message TEXT,
    timestamp TIMESTAMP WITH TIME ZONE,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cm.id,
        cm.session_id,
        cm.role,
        cm.message,
        cm.timestamp,
        ts_rank(cm.message_search_vector, plainto_tsquery('english', search_query)) AS rank
    FROM conversation_messages cm
    WHERE cm.message_search_vector @@ plainto_tsquery('english', search_query)
        AND (user_context IS NULL OR cm.session_id IN (
            SELECT cs.session_id 
            FROM conversation_sessions cs 
            WHERE cs.user_id = user_context
        ))
    ORDER BY rank DESC, cm.timestamp DESC
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;

-- Fuzzy message search function
CREATE OR REPLACE FUNCTION fuzzy_search_messages(
    search_query TEXT,
    similarity_threshold REAL DEFAULT 0.3,
    limit_results INTEGER DEFAULT 20
) RETURNS TABLE(
    message_id UUID,
    session_id VARCHAR(255),
    message TEXT,
    similarity REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cm.id,
        cm.session_id,
        cm.message,
        similarity(cm.message, search_query) as sim
    FROM conversation_messages cm
    WHERE similarity(cm.message, search_query) > similarity_threshold
    ORDER BY sim DESC
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;

-- File search function
CREATE OR REPLACE FUNCTION search_files(
    search_query TEXT,
    file_type_filter TEXT DEFAULT NULL,
    limit_results INTEGER DEFAULT 50
) RETURNS TABLE(
    file_id INTEGER,
    filename VARCHAR(255),
    original_filename VARCHAR(255),
    mime_type VARCHAR(100),
    file_size BIGINT,
    created_at TIMESTAMP WITH TIME ZONE,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        f.id,
        f.filename,
        f.original_filename,
        f.mime_type,
        f.file_size,
        f.created_at,
        ts_rank(f.content_search_vector, plainto_tsquery('english', search_query)) AS rank
    FROM files f
    WHERE f.content_search_vector @@ plainto_tsquery('english', search_query)
        AND (file_type_filter IS NULL OR f.mime_type LIKE '%' || file_type_filter || '%')
        AND f.deleted_at IS NULL
    ORDER BY rank DESC, f.created_at DESC
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;

-- Combined search function for messages and files
CREATE OR REPLACE FUNCTION universal_search(
    search_query TEXT,
    user_context TEXT DEFAULT NULL,
    include_files BOOLEAN DEFAULT TRUE,
    limit_results INTEGER DEFAULT 30
) RETURNS TABLE(
    result_type VARCHAR(20),
    result_id TEXT,
    title TEXT,
    content TEXT,
    timestamp TIMESTAMP WITH TIME ZONE,
    rank REAL
) AS $$
BEGIN
    RETURN QUERY
    -- Search messages
    SELECT 
        'message'::VARCHAR(20) as result_type,
        cm.id::TEXT as result_id,
        ('Session: ' || cm.session_id)::TEXT as title,
        LEFT(cm.message, 200)::TEXT as content,
        cm.timestamp,
        ts_rank(cm.message_search_vector, plainto_tsquery('english', search_query)) AS rank
    FROM conversation_messages cm
    WHERE cm.message_search_vector @@ plainto_tsquery('english', search_query)
        AND (user_context IS NULL OR cm.session_id IN (
            SELECT cs.session_id 
            FROM conversation_sessions cs 
            WHERE cs.user_id = user_context
        ))
    
    UNION ALL
    
    -- Search files (if enabled)
    SELECT 
        'file'::VARCHAR(20) as result_type,
        f.id::TEXT as result_id,
        f.original_filename::TEXT as title,
        LEFT(COALESCE(f.extracted_content, ''), 200)::TEXT as content,
        f.created_at as timestamp,
        ts_rank(f.content_search_vector, plainto_tsquery('english', search_query)) AS rank
    FROM files f
    WHERE include_files = TRUE 
        AND f.content_search_vector @@ plainto_tsquery('english', search_query)
        AND f.deleted_at IS NULL
    
    ORDER BY rank DESC, timestamp DESC
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;

-- Create search statistics view
CREATE OR REPLACE VIEW search_performance_stats AS
SELECT 
    'message_search' as search_type,
    COUNT(*) as total_records,
    COUNT(message_search_vector) as indexed_records,
    AVG(LENGTH(message)) as avg_content_length
FROM conversation_messages
UNION ALL
SELECT 
    'file_search' as search_type,
    COUNT(*) as total_records,
    COUNT(content_search_vector) as indexed_records,
    AVG(LENGTH(COALESCE(extracted_content, ''))) as avg_content_length
FROM files;

-- Grant permissions
GRANT SELECT ON search_performance_stats TO PUBLIC;
GRANT EXECUTE ON FUNCTION search_messages(TEXT, TEXT, INTEGER) TO application_user;
GRANT EXECUTE ON FUNCTION fuzzy_search_messages(TEXT, REAL, INTEGER) TO application_user;
GRANT EXECUTE ON FUNCTION search_files(TEXT, TEXT, INTEGER) TO application_user;
GRANT EXECUTE ON FUNCTION universal_search(TEXT, TEXT, BOOLEAN, INTEGER) TO application_user;

-- Log completion
INSERT INTO migration_log (migration_name, executed_at, description) 
VALUES ('004_implement_full_text_search', NOW(), 'Implemented full-text search with tsvector columns and fuzzy search capabilities')
ON CONFLICT DO NOTHING;