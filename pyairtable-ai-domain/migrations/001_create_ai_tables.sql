-- AI Domain Service Database Schema
-- Migration: 001_create_ai_tables.sql

BEGIN;

-- Sessions table for chat session management
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id VARCHAR(255) UNIQUE NOT NULL,
    user_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    message_count INTEGER DEFAULT 0,
    token_count INTEGER DEFAULT 0,
    total_cost DECIMAL(10, 6) DEFAULT 0.0,
    model VARCHAR(255),
    provider VARCHAR(255),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- LLM usage tracking table
CREATE TABLE IF NOT EXISTS llm_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id VARCHAR(255),
    user_id VARCHAR(255),
    provider VARCHAR(255) NOT NULL,
    model VARCHAR(255) NOT NULL,
    prompt_tokens INTEGER NOT NULL DEFAULT 0,
    completion_tokens INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER NOT NULL DEFAULT 0,
    cost DECIMAL(10, 6) NOT NULL DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    request_id VARCHAR(255),
    response_time_ms INTEGER,
    success BOOLEAN DEFAULT true,
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Tool execution tracking table
CREATE TABLE IF NOT EXISTS tool_executions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tool_name VARCHAR(255) NOT NULL,
    call_id VARCHAR(255) NOT NULL,
    user_id VARCHAR(255),
    session_id VARCHAR(255),
    arguments JSONB NOT NULL,
    result JSONB,
    error_message TEXT,
    execution_time_ms INTEGER,
    success BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Model cache tracking table
CREATE TABLE IF NOT EXISTS model_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name VARCHAR(255) NOT NULL,
    model_type VARCHAR(255) NOT NULL,
    cache_key VARCHAR(255) UNIQUE NOT NULL,
    loaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_accessed TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    access_count INTEGER DEFAULT 0,
    memory_usage_mb INTEGER DEFAULT 0,
    load_time_ms INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Embeddings table for vector storage (if not using external vector DB)
CREATE TABLE IF NOT EXISTS embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    text_hash VARCHAR(64) NOT NULL,
    text TEXT NOT NULL,
    embedding vector(1536), -- Assuming 1536 dimensions, adjust as needed
    model VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Cost tracking aggregation table
CREATE TABLE IF NOT EXISTS cost_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255),
    provider VARCHAR(255) NOT NULL,
    model VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    total_requests INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    total_cost DECIMAL(10, 6) DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, provider, model, date)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sessions_session_id ON sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions(expires_at);

CREATE INDEX IF NOT EXISTS idx_llm_usage_user_id ON llm_usage(user_id);
CREATE INDEX IF NOT EXISTS idx_llm_usage_provider ON llm_usage(provider);
CREATE INDEX IF NOT EXISTS idx_llm_usage_model ON llm_usage(model);
CREATE INDEX IF NOT EXISTS idx_llm_usage_created_at ON llm_usage(created_at);
CREATE INDEX IF NOT EXISTS idx_llm_usage_session_id ON llm_usage(session_id);

CREATE INDEX IF NOT EXISTS idx_tool_executions_tool_name ON tool_executions(tool_name);
CREATE INDEX IF NOT EXISTS idx_tool_executions_user_id ON tool_executions(user_id);
CREATE INDEX IF NOT EXISTS idx_tool_executions_created_at ON tool_executions(created_at);
CREATE INDEX IF NOT EXISTS idx_tool_executions_session_id ON tool_executions(session_id);

CREATE INDEX IF NOT EXISTS idx_model_cache_cache_key ON model_cache(cache_key);
CREATE INDEX IF NOT EXISTS idx_model_cache_model_name ON model_cache(model_name);
CREATE INDEX IF NOT EXISTS idx_model_cache_last_accessed ON model_cache(last_accessed);

CREATE INDEX IF NOT EXISTS idx_embeddings_text_hash ON embeddings(text_hash);
CREATE INDEX IF NOT EXISTS idx_embeddings_model ON embeddings(model);
CREATE INDEX IF NOT EXISTS idx_embeddings_created_at ON embeddings(created_at);

CREATE INDEX IF NOT EXISTS idx_cost_tracking_user_provider_date ON cost_tracking(user_id, provider, date);
CREATE INDEX IF NOT EXISTS idx_cost_tracking_date ON cost_tracking(date);

-- Create trigger for updating timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_sessions_updated_at 
    BEFORE UPDATE ON sessions 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cost_tracking_updated_at 
    BEFORE UPDATE ON cost_tracking 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Insert initial data or configuration if needed
INSERT INTO cost_tracking (user_id, provider, model, date, total_requests, total_tokens, total_cost)
VALUES ('system', 'system', 'initialization', CURRENT_DATE, 0, 0, 0.0)
ON CONFLICT DO NOTHING;

COMMIT;

-- Notes:
-- 1. This schema assumes PostgreSQL with pgvector extension for vector storage
-- 2. Adjust vector dimensions based on your embedding model
-- 3. Consider partitioning large tables (llm_usage, tool_executions) by date
-- 4. Add additional indexes based on query patterns
-- 5. Consider adding data retention policies for log tables