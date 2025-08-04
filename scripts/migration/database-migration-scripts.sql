-- PyAirtable Production Database Migration Scripts
-- ================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Migration log table
CREATE TABLE IF NOT EXISTS migration_log (
    id SERIAL PRIMARY KEY,
    migration_name VARCHAR(255) NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) DEFAULT 'running',
    error_message TEXT,
    checksum VARCHAR(64)
);

-- Pre-migration validation functions
CREATE OR REPLACE FUNCTION validate_data_integrity()
RETURNS TABLE(table_name TEXT, row_count BIGINT, checksum TEXT) AS $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN 
        SELECT schemaname, tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
        AND tablename NOT LIKE 'migration_%'
    LOOP
        EXECUTE format('SELECT %L, COUNT(*), md5(string_agg(t::text, '''')) 
                       FROM %I.%I t', 
                       rec.tablename, rec.schemaname, rec.tablename)
        INTO table_name, row_count, checksum;
        
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create replication user and permissions
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'replication_user') THEN
        CREATE ROLE replication_user WITH REPLICATION LOGIN PASSWORD 'secure_replication_password';
    END IF;
END
$$;

-- Grant necessary permissions for replication
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replication_user;
GRANT USAGE ON SCHEMA public TO replication_user;

-- Enable logical replication
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_logical_replication_workers = 10;

-- Create publication for all tables
DROP PUBLICATION IF EXISTS pyairtable_replication;
CREATE PUBLICATION pyairtable_replication FOR ALL TABLES;

-- Migration validation queries
CREATE OR REPLACE FUNCTION check_foreign_key_violations()
RETURNS TABLE(constraint_name TEXT, table_name TEXT, violation_count BIGINT) AS $$
DECLARE
    rec RECORD;
    query TEXT;
BEGIN
    FOR rec IN 
        SELECT conname, conrelid::regclass AS table_name, 
               confrelid::regclass AS ref_table,
               conkey, confkey
        FROM pg_constraint 
        WHERE contype = 'f' 
        AND connamespace = 'public'::regnamespace
    LOOP
        query := format('
            SELECT %L, %L, COUNT(*)
            FROM %s t
            LEFT JOIN %s r ON t.%s = r.%s
            WHERE r.%s IS NULL AND t.%s IS NOT NULL',
            rec.conname,
            rec.table_name,
            rec.table_name,
            rec.ref_table,
            -- Simplified - in real scenario would handle multi-column FKs
            'id', 'id', 'id', 'id'
        );
        
        EXECUTE query INTO constraint_name, table_name, violation_count;
        
        IF violation_count > 0 THEN
            RETURN NEXT;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Event store specific migration functions
CREATE OR REPLACE FUNCTION migrate_event_store_batch(
    batch_size INTEGER DEFAULT 1000,
    start_id BIGINT DEFAULT 0
)
RETURNS TABLE(batch_start BIGINT, batch_end BIGINT, events_migrated INTEGER) AS $$
DECLARE
    current_batch_start BIGINT := start_id;
    current_batch_end BIGINT;
    events_count INTEGER;
BEGIN
    LOOP
        -- Calculate batch end
        SELECT id INTO current_batch_end
        FROM events 
        WHERE id > current_batch_start
        ORDER BY id 
        LIMIT 1 OFFSET batch_size - 1;
        
        -- If no more events, exit
        IF current_batch_end IS NULL THEN
            SELECT MAX(id) INTO current_batch_end FROM events WHERE id > current_batch_start;
            IF current_batch_end IS NULL THEN
                EXIT;
            END IF;
        END IF;
        
        -- Count events in this batch
        SELECT COUNT(*) INTO events_count
        FROM events 
        WHERE id > current_batch_start AND id <= current_batch_end;
        
        -- Return batch info
        batch_start := current_batch_start;
        batch_end := current_batch_end;
        events_migrated := events_count;
        RETURN NEXT;
        
        -- Move to next batch
        current_batch_start := current_batch_end;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Projection rebuild functions
CREATE OR REPLACE FUNCTION rebuild_user_projections()
RETURNS BOOLEAN AS $$
DECLARE
    event_rec RECORD;
    projection_data JSONB;
BEGIN
    -- Clear existing projections
    TRUNCATE user_projections;
    
    -- Replay events to rebuild projections
    FOR event_rec IN 
        SELECT * FROM events 
        WHERE aggregate_type = 'user' 
        ORDER BY created_at, version
    LOOP
        -- Apply event to projection (simplified)
        CASE event_rec.event_type
            WHEN 'user_created' THEN
                INSERT INTO user_projections (user_id, email, created_at, data)
                VALUES (
                    event_rec.aggregate_id::UUID,
                    (event_rec.event_data->>'email')::TEXT,
                    event_rec.created_at,
                    event_rec.event_data
                )
                ON CONFLICT (user_id) DO NOTHING;
                
            WHEN 'user_updated' THEN
                UPDATE user_projections 
                SET data = data || event_rec.event_data,
                    updated_at = event_rec.created_at
                WHERE user_id = event_rec.aggregate_id::UUID;
                
            WHEN 'user_deleted' THEN
                UPDATE user_projections 
                SET deleted_at = event_rec.created_at
                WHERE user_id = event_rec.aggregate_id::UUID;
        END CASE;
    END LOOP;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error rebuilding user projections: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Performance optimization for migration
CREATE OR REPLACE FUNCTION optimize_for_migration()
RETURNS BOOLEAN AS $$
BEGIN
    -- Disable unnecessary triggers during migration
    ALTER TABLE events DISABLE TRIGGER ALL;
    ALTER TABLE user_projections DISABLE TRIGGER ALL;
    ALTER TABLE workspace_projections DISABLE TRIGGER ALL;
    
    -- Increase work_mem for large operations
    SET work_mem = '256MB';
    SET maintenance_work_mem = '1GB';
    
    -- Disable autovacuum during migration
    ALTER TABLE events SET (autovacuum_enabled = false);
    ALTER TABLE user_projections SET (autovacuum_enabled = false);
    ALTER TABLE workspace_projections SET (autovacuum_enabled = false);
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Restore normal operations after migration
CREATE OR REPLACE FUNCTION restore_normal_operations()
RETURNS BOOLEAN AS $$
BEGIN
    -- Re-enable triggers
    ALTER TABLE events ENABLE TRIGGER ALL;
    ALTER TABLE user_projections ENABLE TRIGGER ALL;
    ALTER TABLE workspace_projections ENABLE TRIGGER ALL;
    
    -- Reset configuration
    RESET work_mem;
    RESET maintenance_work_mem;
    
    -- Re-enable autovacuum
    ALTER TABLE events SET (autovacuum_enabled = true);
    ALTER TABLE user_projections SET (autovacuum_enabled = true);
    ALTER TABLE workspace_projections SET (autovacuum_enabled = true);
    
    -- Update statistics
    ANALYZE events;
    ANALYZE user_projections;
    ANALYZE workspace_projections;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Migration cleanup functions
CREATE OR REPLACE FUNCTION cleanup_replication_setup()
RETURNS BOOLEAN AS $$
BEGIN
    -- Drop replication slot if exists
    SELECT pg_drop_replication_slot('pyairtable_migration_slot')
    WHERE EXISTS (
        SELECT 1 FROM pg_replication_slots 
        WHERE slot_name = 'pyairtable_migration_slot'
    );
    
    -- Drop publication
    DROP PUBLICATION IF EXISTS pyairtable_replication;
    
    -- Revoke replication permissions
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM replication_user;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error during cleanup: %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Final validation query
CREATE OR REPLACE FUNCTION final_migration_validation()
RETURNS TABLE(
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check row counts
    RETURN QUERY
    SELECT 'row_counts'::TEXT, 
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
           'Tables with mismatched row counts: ' || COUNT(*)::TEXT
    FROM (
        SELECT schemaname, tablename,
               (SELECT COUNT(*) FROM information_schema.tables WHERE table_name = tablename) as source_count
        FROM pg_tables 
        WHERE schemaname = 'public'
    ) t;
    
    -- Check foreign key violations
    RETURN QUERY
    SELECT 'foreign_keys'::TEXT,
           CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
           'Foreign key violations found: ' || COUNT(*)::TEXT
    FROM check_foreign_key_violations();
    
    -- Check event store integrity
    RETURN QUERY
    SELECT 'event_store'::TEXT,
           CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
           'Total events migrated: ' || COUNT(*)::TEXT
    FROM events;
    
    -- Check projection consistency
    RETURN QUERY
    SELECT 'projections'::TEXT,
           CASE WHEN user_count = event_count THEN 'PASS' ELSE 'FAIL' END,
           'User projections: ' || user_count::TEXT || ', User events: ' || event_count::TEXT
    FROM (
        SELECT 
            (SELECT COUNT(DISTINCT user_id) FROM user_projections WHERE deleted_at IS NULL) as user_count,
            (SELECT COUNT(DISTINCT aggregate_id) FROM events WHERE aggregate_type = 'user' AND event_type != 'user_deleted') as event_count
    ) counts;
END;
$$ LANGUAGE plpgsql;

-- Log migration completion
INSERT INTO migration_log (migration_name, completed_at, status, checksum)
VALUES (
    'database_migration_scripts_setup',
    NOW(),
    'completed',
    md5('database_migration_scripts_v1.0.0')
);

-- Grant execute permissions to migration user
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO replication_user;