-- Initialize PyAirtable database schema

-- Sessions table for conversation history
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(255) PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_id VARCHAR(255),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Conversation history
CREATE TABLE IF NOT EXISTS conversation_history (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(255) REFERENCES sessions(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL, -- 'user' or 'assistant'
    message TEXT NOT NULL,
    tools_used JSONB DEFAULT '[]'::jsonb,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Tool execution logs
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

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_conversation_history_session_id ON conversation_history(session_id);
CREATE INDEX IF NOT EXISTS idx_conversation_history_timestamp ON conversation_history(timestamp);
CREATE INDEX IF NOT EXISTS idx_tool_executions_session_id ON tool_executions(session_id);
CREATE INDEX IF NOT EXISTS idx_tool_executions_timestamp ON tool_executions(timestamp);
CREATE INDEX IF NOT EXISTS idx_sessions_last_activity ON sessions(last_activity);

-- Insert default data
INSERT INTO sessions (id, user_id, metadata) 
VALUES ('default-session', 'default-user', '{"description": "Default session for testing"}')
ON CONFLICT (id) DO NOTHING;