#!/bin/bash
# Create multiple test databases for isolation
# This script is executed during PostgreSQL container initialization

set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create databases for different test types
    CREATE DATABASE unit_test_db;
    CREATE DATABASE integration_test_db;
    CREATE DATABASE e2e_test_db;
    
    -- Grant permissions
    GRANT ALL PRIVILEGES ON DATABASE unit_test_db TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE integration_test_db TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON DATABASE e2e_test_db TO $POSTGRES_USER;
EOSQL

# Create test schemas and tables in each database
for db in unit_test_db integration_test_db e2e_test_db; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
        -- Enable extensions
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";
        
        -- Create test tables
        CREATE TABLE IF NOT EXISTS test_users (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            email VARCHAR(255) UNIQUE NOT NULL,
            username VARCHAR(100) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            first_name VARCHAR(100),
            last_name VARCHAR(100),
            is_active BOOLEAN DEFAULT true,
            is_verified BOOLEAN DEFAULT false,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        CREATE TABLE IF NOT EXISTS test_workspaces (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            name VARCHAR(255) NOT NULL,
            description TEXT,
            owner_id UUID REFERENCES test_users(id) ON DELETE CASCADE,
            settings JSONB DEFAULT '{}',
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        CREATE TABLE IF NOT EXISTS test_sessions (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            user_id UUID REFERENCES test_users(id) ON DELETE CASCADE,
            session_token VARCHAR(255) UNIQUE NOT NULL,
            expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            last_accessed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        CREATE TABLE IF NOT EXISTS test_audit_logs (
            id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
            user_id UUID REFERENCES test_users(id),
            action VARCHAR(100) NOT NULL,
            resource_type VARCHAR(100),
            resource_id VARCHAR(255),
            details JSONB DEFAULT '{}',
            ip_address INET,
            user_agent TEXT,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
        
        -- Create indexes
        CREATE INDEX IF NOT EXISTS idx_test_users_email ON test_users(email);
        CREATE INDEX IF NOT EXISTS idx_test_users_username ON test_users(username);
        CREATE INDEX IF NOT EXISTS idx_test_workspaces_owner_id ON test_workspaces(owner_id);
        CREATE INDEX IF NOT EXISTS idx_test_sessions_user_id ON test_sessions(user_id);
        CREATE INDEX IF NOT EXISTS idx_test_sessions_token ON test_sessions(session_token);
        CREATE INDEX IF NOT EXISTS idx_test_sessions_expires ON test_sessions(expires_at);
        CREATE INDEX IF NOT EXISTS idx_test_audit_logs_user_id ON test_audit_logs(user_id);
        CREATE INDEX IF NOT EXISTS idx_test_audit_logs_created_at ON test_audit_logs(created_at);
        
        -- Create trigger for updated_at timestamps
        CREATE OR REPLACE FUNCTION update_updated_at_column()
        RETURNS TRIGGER AS \$\$
        BEGIN
            NEW.updated_at = NOW();
            RETURN NEW;
        END;
        \$\$ language 'plpgsql';
        
        CREATE TRIGGER update_test_users_updated_at BEFORE UPDATE ON test_users
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
            
        CREATE TRIGGER update_test_workspaces_updated_at BEFORE UPDATE ON test_workspaces
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
EOSQL
done

echo "Successfully created test databases and schemas"