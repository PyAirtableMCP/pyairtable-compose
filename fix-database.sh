#!/bin/bash

# Fix database schema issues for PyAirtable
set -e

echo "🔧 Fixing PyAirtable Database Schema Issues"
echo "=========================================="

# Get database credentials from .env
source .env

# Create all required tables
echo "Creating missing tables..."

# Create the SQL for all missing tables
cat > /tmp/fix-schema.sql << 'EOF'
-- Create workflows table for automation-services
CREATE TABLE IF NOT EXISTS workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    tenant_id UUID NOT NULL,
    is_active BOOLEAN DEFAULT true,
    schedule_config JSONB,
    workflow_definition JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    last_run_at TIMESTAMP,
    next_run_at TIMESTAMP,
    run_count INTEGER DEFAULT 0
);

-- Create workflow_runs table
CREATE TABLE IF NOT EXISTS workflow_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id UUID REFERENCES workflows(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    result JSONB,
    execution_time_ms INTEGER
);

-- Create users table for platform-services
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    is_active BOOLEAN DEFAULT true,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create tenants table
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL,
    plan VARCHAR(50) DEFAULT 'free',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create tenant_users junction table
CREATE TABLE IF NOT EXISTS tenant_users (
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'member',
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, user_id)
);

-- Create sessions table for auth
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(500) UNIQUE NOT NULL,
    refresh_token VARCHAR(500),
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create api_keys table
CREATE TABLE IF NOT EXISTS api_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) UNIQUE NOT NULL,
    last_used_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

-- Create airtable_connections table
CREATE TABLE IF NOT EXISTS airtable_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    base_id VARCHAR(255) NOT NULL,
    api_key_encrypted TEXT,
    name VARCHAR(255),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_workflows_tenant_id ON workflows(tenant_id);
CREATE INDEX IF NOT EXISTS idx_workflows_next_run ON workflows(next_run_at) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow ON workflow_runs(workflow_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_tenants_slug ON tenants(slug);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON api_keys(key_hash);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${POSTGRES_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${POSTGRES_USER};

-- Create a test user and tenant for development
INSERT INTO tenants (id, name, slug, plan) 
VALUES ('550e8400-e29b-41d4-a716-446655440000', 'Test Company', 'test-company', 'pro')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO users (id, email, password_hash, first_name, last_name, is_verified) 
VALUES ('550e8400-e29b-41d4-a716-446655440001', 'admin@test.com', 
        -- password: 'admin123' (bcrypt hash)
        '$2b$10$YKpDqQxPqGGvmE7lYV8FKe3Kj5TcMh3h4dH8YwQ5PqwqIqFqZqZqO',
        'Test', 'Admin', true)
ON CONFLICT (email) DO NOTHING;

INSERT INTO tenant_users (tenant_id, user_id, role) 
VALUES ('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'owner')
ON CONFLICT DO NOTHING;

-- Show summary
SELECT 'Database schema fixed successfully!' as message;
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
EOF

# Execute the SQL
echo "Connecting to database and applying schema..."
docker-compose exec -T postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} < /tmp/fix-schema.sql

echo ""
echo "✅ Database schema has been fixed!"
echo ""
echo "Created tables:"
echo "  - workflows (for automation-services)"
echo "  - workflow_runs"
echo "  - users (for platform-services)"
echo "  - tenants"
echo "  - tenant_users"
echo "  - sessions (for auth)"
echo "  - api_keys"
echo "  - airtable_connections"
echo ""
echo "Test credentials:"
echo "  Email: admin@test.com"
echo "  Password: admin123"
echo ""

# Restart affected services
echo "Restarting services to apply changes..."
docker-compose restart automation-services platform-services

echo "✅ Services restarted successfully!"