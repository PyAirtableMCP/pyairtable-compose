-- Initialize PyAirtable database schema
-- Updated: 2025-08-02 - Added permissions database setup

-- Create separate database for permissions service
CREATE DATABASE pyairtable_permissions OWNER postgres;

-- Import the new session management schema
\i /docker-entrypoint-initdb.d/migrations/001_create_session_tables.sql

-- Legacy tables (kept for backward compatibility during migration)
-- These will be deprecated in favor of the new conversation_sessions and conversation_messages tables

-- Sessions table for conversation history (LEGACY - to be deprecated)
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(255) PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id VARCHAR(255),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Conversation history (LEGACY - to be deprecated)
CREATE TABLE IF NOT EXISTS conversation_history (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) REFERENCES sessions(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL, -- 'user' or 'assistant'
    message TEXT NOT NULL,
    tools_used JSONB DEFAULT '[]'::jsonb,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Tool execution logs (LEGACY - to be deprecated)
CREATE TABLE IF NOT EXISTS tool_executions (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) REFERENCES sessions(id) ON DELETE CASCADE,
    tool_name VARCHAR(255) NOT NULL,
    arguments JSONB NOT NULL,
    result JSONB,
    success BOOLEAN DEFAULT FALSE,
    execution_time_ms INTEGER,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Airtable base metadata cache
CREATE TABLE IF NOT EXISTS airtable_bases (
    base_id VARCHAR(255) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    permission_level VARCHAR(50),
    schema_cache JSONB,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance (legacy tables)
CREATE INDEX IF NOT EXISTS idx_conversation_history_session_id ON conversation_history(session_id);
CREATE INDEX IF NOT EXISTS idx_conversation_history_timestamp ON conversation_history(timestamp);
CREATE INDEX IF NOT EXISTS idx_tool_executions_session_id ON tool_executions(session_id);
CREATE INDEX IF NOT EXISTS idx_tool_executions_timestamp ON tool_executions(timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_last_activity ON sessions(last_activity);

-- Insert default data
INSERT INTO sessions (id, user_id, metadata) 
VALUES ('default-session', 'default-user', '{"description": "Default session for testing"}')
ON CONFLICT (id) DO NOTHING;