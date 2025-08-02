-- Migration: Install Core PostgreSQL Extensions
-- Created: 2025-08-01
-- Description: Install essential extensions for performance monitoring, audit logging, and search capabilities

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Verify extensions are installed
SELECT name, default_version, installed_version, comment 
FROM pg_available_extensions 
WHERE name IN ('pg_stat_statements', 'pg_trgm', 'pgaudit')
ORDER BY name;

-- Configure pg_stat_statements
-- Note: This requires postgresql.conf changes:
-- shared_preload_libraries = 'pg_stat_statements'
-- pg_stat_statements.track = all
-- pg_stat_statements.max = 10000

-- Configure pgaudit
-- Note: This requires postgresql.conf changes:
-- pgaudit.log = 'write,ddl'
-- pgaudit.log_parameter = on
-- pgaudit.log_statement_once = on

-- Create monitoring views for pg_stat_statements
CREATE OR REPLACE VIEW slow_queries AS
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time,
    stddev_exec_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
ORDER BY mean_exec_time DESC;

-- Create view for most frequent queries
CREATE OR REPLACE VIEW frequent_queries AS
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
ORDER BY calls DESC;

-- Create function to reset pg_stat_statements
CREATE OR REPLACE FUNCTION reset_query_stats()
RETURNS VOID AS $$
BEGIN
    PERFORM pg_stat_statements_reset();
    RAISE NOTICE 'Query statistics have been reset';
END;
$$ LANGUAGE plpgsql;

-- Grant necessary permissions
GRANT SELECT ON slow_queries TO PUBLIC;
GRANT SELECT ON frequent_queries TO PUBLIC;
GRANT EXECUTE ON FUNCTION reset_query_stats() TO postgres;

-- Log completion
INSERT INTO migration_log (migration_name, executed_at, description) 
VALUES ('002_install_core_extensions', NOW(), 'Installed pg_stat_statements, pg_trgm, and pgaudit extensions')
ON CONFLICT DO NOTHING;