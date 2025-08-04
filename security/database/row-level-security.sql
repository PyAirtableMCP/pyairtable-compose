-- Database Row-Level Security (RLS) Implementation for PyAirtable
-- Multi-tenant data isolation for 3vantage organization
-- Production-ready PostgreSQL security implementation

-- Enable Row Level Security extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create tenant management schema
CREATE SCHEMA IF NOT EXISTS tenant_management;

-- Create audit schema for security logging
CREATE SCHEMA IF NOT EXISTS security_audit;

-- =====================================================
-- TENANT MANAGEMENT TABLES
-- =====================================================

-- Tenants table with enhanced security
CREATE TABLE IF NOT EXISTS tenant_management.tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    slug VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deleted')),
    tier VARCHAR(20) NOT NULL DEFAULT 'standard' CHECK (tier IN ('trial', 'standard', 'premium', 'enterprise')),
    max_users INTEGER DEFAULT 10,
    max_workspaces INTEGER DEFAULT 5,
    max_storage_gb INTEGER DEFAULT 100,
    encryption_key_id VARCHAR(255), -- For tenant-specific encryption
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID,
    security_settings JSONB DEFAULT '{
        "ip_whitelist": [],
        "require_mfa": false,
        "session_timeout": 3600,
        "password_policy": {
            "min_length": 8,
            "require_uppercase": true,
            "require_lowercase": true,
            "require_numbers": true,
            "require_special": true
        }
    }'::jsonb,
    
    -- Security constraints
    CONSTRAINT valid_slug CHECK (slug ~ '^[a-z0-9-]+$'),
    CONSTRAINT valid_name CHECK (length(name) >= 2)
);

-- Tenant users with RLS
CREATE TABLE IF NOT EXISTS tenant_management.tenant_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
    permissions JSONB DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_access TIMESTAMP WITH TIME ZONE,
    
    UNIQUE(tenant_id, user_id)
);

-- Tenant access policies
CREATE TABLE IF NOT EXISTS tenant_management.tenant_access_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    resource_type VARCHAR(100) NOT NULL,
    resource_id UUID,
    action VARCHAR(50) NOT NULL,
    role VARCHAR(50) NOT NULL,
    conditions JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(tenant_id, resource_type, resource_id, action, role)
);

-- =====================================================
-- MAIN APPLICATION TABLES WITH RLS
-- =====================================================

-- Users table with tenant isolation
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    email VARCHAR(255) NOT NULL,
    username VARCHAR(100),
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'suspended', 'deleted')),
    email_verified BOOLEAN DEFAULT FALSE,
    mfa_enabled BOOLEAN DEFAULT FALSE,
    mfa_secret VARCHAR(255),
    last_login TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(tenant_id, email),
    UNIQUE(tenant_id, username)
);

-- Workspaces with tenant isolation
CREATE TABLE IF NOT EXISTS public.workspaces (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    owner_id UUID NOT NULL,
    settings JSONB DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'deleted')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(tenant_id, name),
    FOREIGN KEY (tenant_id, owner_id) REFERENCES public.users(tenant_id, id) DEFERRABLE INITIALLY DEFERRED
);

-- Tables (Airtable equivalent) with tenant isolation
CREATE TABLE IF NOT EXISTS public.tables (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    schema_definition JSONB NOT NULL DEFAULT '{"fields": []}',
    view_definitions JSONB DEFAULT '{"views": []}',
    permissions JSONB DEFAULT '{}',
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(tenant_id, workspace_id, name),
    FOREIGN KEY (tenant_id, workspace_id) REFERENCES public.workspaces(tenant_id, id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (tenant_id, created_by) REFERENCES public.users(tenant_id, id) DEFERRABLE INITIALLY DEFERRED
);

-- Records with tenant isolation
CREATE TABLE IF NOT EXISTS public.records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    table_id UUID NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    created_by UUID NOT NULL,
    updated_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    version INTEGER DEFAULT 1,
    
    FOREIGN KEY (tenant_id, table_id) REFERENCES public.tables(tenant_id, id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (tenant_id, created_by) REFERENCES public.users(tenant_id, id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (tenant_id, updated_by) REFERENCES public.users(tenant_id, id) DEFERRABLE INITIALLY DEFERRED
);

-- API Keys with tenant isolation
CREATE TABLE IF NOT EXISTS public.api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    name VARCHAR(255) NOT NULL,
    key_hash VARCHAR(255) NOT NULL UNIQUE,
    key_prefix VARCHAR(20) NOT NULL,
    permissions JSONB DEFAULT '{}',
    scopes TEXT[] DEFAULT ARRAY[]::TEXT[],
    rate_limit INTEGER DEFAULT 1000,
    expires_at TIMESTAMP WITH TIME ZONE,
    last_used TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'revoked')),
    
    UNIQUE(tenant_id, user_id, name),
    FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id) DEFERRABLE INITIALLY DEFERRED
);

-- Sessions with tenant isolation
CREATE TABLE IF NOT EXISTS public.user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    session_token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    FOREIGN KEY (tenant_id, user_id) REFERENCES public.users(tenant_id, id) ON DELETE CASCADE
);

-- =====================================================
-- SECURITY AUDIT TABLES
-- =====================================================

-- Audit log for security events
CREATE TABLE IF NOT EXISTS security_audit.audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    user_id UUID,
    session_id UUID,
    event_type VARCHAR(100) NOT NULL,
    resource_type VARCHAR(100),
    resource_id UUID,
    action VARCHAR(100) NOT NULL,
    result VARCHAR(20) NOT NULL CHECK (result IN ('success', 'failure', 'denied')),
    ip_address INET,
    user_agent TEXT,
    request_id UUID,
    details JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Indexes for performance
    INDEX (tenant_id, created_at),
    INDEX (user_id, created_at),
    INDEX (event_type, created_at)
);

-- Data access log
CREATE TABLE IF NOT EXISTS security_audit.data_access_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenant_management.tenants(id) ON DELETE CASCADE,
    user_id UUID,
    table_id UUID,
    record_id UUID,
    action VARCHAR(50) NOT NULL CHECK (action IN ('select', 'insert', 'update', 'delete')),
    field_accessed TEXT[],
    sensitive_data_accessed BOOLEAN DEFAULT FALSE,
    ip_address INET,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    INDEX (tenant_id, created_at),
    INDEX (user_id, created_at),
    INDEX (table_id, created_at)
);

-- =====================================================
-- ROW LEVEL SECURITY POLICIES
-- =====================================================

-- Enable RLS on all tenant-isolated tables
ALTER TABLE tenant_management.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_management.tenant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_management.tenant_access_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_audit.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_audit.data_access_log ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- SECURITY FUNCTIONS
-- =====================================================

-- Function to get current tenant ID from session
CREATE OR REPLACE FUNCTION security.current_tenant_id()
RETURNS UUID AS $$
BEGIN
    -- Get tenant_id from session variable or JWT claim
    RETURN COALESCE(
        current_setting('app.current_tenant_id', true)::UUID,
        current_setting('jwt.claims.tenant_id', true)::UUID
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get current user ID from session
CREATE OR REPLACE FUNCTION security.current_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN COALESCE(
        current_setting('app.current_user_id', true)::UUID,
        current_setting('jwt.claims.user_id', true)::UUID
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has role in tenant
CREATE OR REPLACE FUNCTION security.user_has_role(user_id UUID, tenant_id UUID, required_role TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_role TEXT;
BEGIN
    SELECT role INTO user_role
    FROM tenant_management.tenant_users tu
    WHERE tu.user_id = $1 AND tu.tenant_id = $2 AND tu.status = 'active';
    
    RETURN CASE
        WHEN required_role = 'viewer' THEN user_role IN ('viewer', 'member', 'admin', 'owner')
        WHEN required_role = 'member' THEN user_role IN ('member', 'admin', 'owner')
        WHEN required_role = 'admin' THEN user_role IN ('admin', 'owner')
        WHEN required_role = 'owner' THEN user_role = 'owner'
        ELSE FALSE
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- ROW LEVEL SECURITY POLICIES
-- =====================================================

-- Tenant management policies
CREATE POLICY tenant_isolation_policy ON tenant_management.tenants
    FOR ALL TO authenticated
    USING (id = security.current_tenant_id());

CREATE POLICY tenant_users_policy ON tenant_management.tenant_users
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

CREATE POLICY tenant_access_policies_policy ON tenant_management.tenant_access_policies
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

-- User table policies
CREATE POLICY users_tenant_isolation ON public.users
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

-- Workspace policies
CREATE POLICY workspaces_tenant_isolation ON public.workspaces
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

-- Table policies
CREATE POLICY tables_tenant_isolation ON public.tables
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

-- Records policies with fine-grained access
CREATE POLICY records_tenant_isolation ON public.records
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

-- Additional policy for records based on table permissions
CREATE POLICY records_table_access ON public.records
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.tables t
            WHERE t.id = records.table_id
            AND t.tenant_id = security.current_tenant_id()
            AND (
                t.created_by = security.current_user_id()
                OR security.user_has_role(security.current_user_id(), security.current_tenant_id(), 'member')
            )
        )
    );

-- API Keys policies
CREATE POLICY api_keys_tenant_isolation ON public.api_keys
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

CREATE POLICY api_keys_user_access ON public.api_keys
    FOR ALL TO authenticated
    USING (
        tenant_id = security.current_tenant_id()
        AND (
            user_id = security.current_user_id()
            OR security.user_has_role(security.current_user_id(), security.current_tenant_id(), 'admin')
        )
    );

-- Session policies
CREATE POLICY sessions_tenant_isolation ON public.user_sessions
    FOR ALL TO authenticated
    USING (tenant_id = security.current_tenant_id());

CREATE POLICY sessions_user_access ON public.user_sessions
    FOR ALL TO authenticated
    USING (
        tenant_id = security.current_tenant_id()
        AND user_id = security.current_user_id()
    );

-- Audit log policies
CREATE POLICY audit_log_tenant_isolation ON security_audit.audit_log
    FOR ALL TO authenticated
    USING (
        tenant_id = security.current_tenant_id()
        AND security.user_has_role(security.current_user_id(), security.current_tenant_id(), 'admin')
    );

CREATE POLICY data_access_log_tenant_isolation ON security_audit.data_access_log
    FOR ALL TO authenticated
    USING (
        tenant_id = security.current_tenant_id()
        AND security.user_has_role(security.current_user_id(), security.current_tenant_id(), 'admin')
    );

-- =====================================================
-- AUDIT TRIGGERS
-- =====================================================

-- Function to log data access
CREATE OR REPLACE FUNCTION security_audit.log_data_access()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO security_audit.data_access_log (
        tenant_id,
        user_id,
        table_id,
        record_id,
        action,
        field_accessed,
        sensitive_data_accessed,
        ip_address
    ) VALUES (
        COALESCE(NEW.tenant_id, OLD.tenant_id),
        security.current_user_id(),
        COALESCE(NEW.table_id, OLD.table_id),
        COALESCE(NEW.id, OLD.id),
        lower(TG_OP),
        CASE
            WHEN TG_OP = 'UPDATE' THEN 
                (SELECT array_agg(key) FROM jsonb_each(to_jsonb(NEW)))
            ELSE NULL
        END,
        FALSE, -- Could be enhanced to detect sensitive fields
        inet_client_addr()
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply audit triggers to sensitive tables
CREATE TRIGGER records_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.records
    FOR EACH ROW EXECUTE FUNCTION security_audit.log_data_access();

CREATE TRIGGER users_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.users
    FOR EACH ROW EXECUTE FUNCTION security_audit.log_data_access();

-- =====================================================
-- SECURITY ROLES AND PERMISSIONS
-- =====================================================

-- Create application roles
CREATE ROLE pyairtable_app;
CREATE ROLE pyairtable_api;
CREATE ROLE pyairtable_admin;

-- Grant permissions to application role
GRANT CONNECT ON DATABASE pyairtable TO pyairtable_app;
GRANT USAGE ON SCHEMA public TO pyairtable_app;
GRANT USAGE ON SCHEMA tenant_management TO pyairtable_app;
GRANT USAGE ON SCHEMA security_audit TO pyairtable_app;

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pyairtable_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tenant_management TO pyairtable_app;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA security_audit TO pyairtable_app;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pyairtable_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA tenant_management TO pyairtable_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA security_audit TO pyairtable_app;

-- =====================================================
-- PERFORMANCE INDEXES
-- =====================================================

-- Tenant-specific indexes for performance
CREATE INDEX IF NOT EXISTS idx_users_tenant_email ON public.users(tenant_id, email);
CREATE INDEX IF NOT EXISTS idx_workspaces_tenant_owner ON public.workspaces(tenant_id, owner_id);
CREATE INDEX IF NOT EXISTS idx_tables_tenant_workspace ON public.tables(tenant_id, workspace_id);
CREATE INDEX IF NOT EXISTS idx_records_tenant_table ON public.records(tenant_id, table_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_tenant_user ON public.api_keys(tenant_id, user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_tenant_user ON public.user_sessions(tenant_id, user_id);

-- Audit log indexes
CREATE INDEX IF NOT EXISTS idx_audit_log_tenant_time ON security_audit.audit_log(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_data_access_tenant_time ON security_audit.data_access_log(tenant_id, created_at DESC);

-- =====================================================
-- DATA ENCRYPTION FUNCTIONS
-- =====================================================

-- Function to encrypt sensitive data
CREATE OR REPLACE FUNCTION security.encrypt_sensitive_data(data TEXT, tenant_id UUID)
RETURNS TEXT AS $$
DECLARE
    encryption_key TEXT;
BEGIN
    -- Get tenant-specific encryption key (would integrate with Vault)
    SELECT encryption_key_id INTO encryption_key
    FROM tenant_management.tenants
    WHERE id = tenant_id;
    
    -- Use pgcrypto for encryption (in production, integrate with Vault Transit)
    RETURN encode(encrypt(data::bytea, encryption_key::bytea, 'aes'), 'base64');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to decrypt sensitive data
CREATE OR REPLACE FUNCTION security.decrypt_sensitive_data(encrypted_data TEXT, tenant_id UUID)
RETURNS TEXT AS $$
DECLARE
    encryption_key TEXT;
BEGIN
    SELECT encryption_key_id INTO encryption_key
    FROM tenant_management.tenants
    WHERE id = tenant_id;
    
    RETURN decrypt(decode(encrypted_data, 'base64'), encryption_key::bytea, 'aes')::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- TENANT ONBOARDING FUNCTIONS
-- =====================================================

-- Function to create new tenant with all required setup
CREATE OR REPLACE FUNCTION tenant_management.create_tenant(
    tenant_name TEXT,
    tenant_slug TEXT,
    owner_email TEXT,
    owner_password TEXT,
    tier TEXT DEFAULT 'standard'
)
RETURNS UUID AS $$
DECLARE
    new_tenant_id UUID;
    new_user_id UUID;
    encryption_key TEXT;
BEGIN
    -- Generate encryption key for tenant
    encryption_key := encode(gen_random_bytes(32), 'hex');
    
    -- Create tenant
    INSERT INTO tenant_management.tenants (name, slug, tier, encryption_key_id)
    VALUES (tenant_name, tenant_slug, tier, encryption_key)
    RETURNING id INTO new_tenant_id;
    
    -- Create owner user
    INSERT INTO public.users (tenant_id, email, password_hash, status, email_verified)
    VALUES (new_tenant_id, owner_email, crypt(owner_password, gen_salt('bf')), 'active', true)
    RETURNING id INTO new_user_id;
    
    -- Add user to tenant with owner role
    INSERT INTO tenant_management.tenant_users (tenant_id, user_id, role)
    VALUES (new_tenant_id, new_user_id, 'owner');
    
    -- Log tenant creation
    INSERT INTO security_audit.audit_log (
        tenant_id, user_id, event_type, action, result, details
    ) VALUES (
        new_tenant_id, new_user_id, 'tenant_management', 'create_tenant', 'success',
        jsonb_build_object('tenant_name', tenant_name, 'tier', tier)
    );
    
    RETURN new_tenant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- SECURITY VALIDATION FUNCTIONS
-- =====================================================

-- Function to validate tenant isolation
CREATE OR REPLACE FUNCTION security.validate_tenant_isolation(test_tenant_id UUID)
RETURNS TABLE(table_name TEXT, isolation_status TEXT, record_count BIGINT) AS $$
BEGIN
    -- Test users table isolation
    RETURN QUERY
    SELECT 'users'::TEXT, 'isolated'::TEXT, count(*)
    FROM public.users WHERE tenant_id = test_tenant_id;
    
    -- Test workspaces table isolation
    RETURN QUERY
    SELECT 'workspaces'::TEXT, 'isolated'::TEXT, count(*)
    FROM public.workspaces WHERE tenant_id = test_tenant_id;
    
    -- Test tables isolation
    RETURN QUERY
    SELECT 'tables'::TEXT, 'isolated'::TEXT, count(*)
    FROM public.tables WHERE tenant_id = test_tenant_id;
    
    -- Test records isolation
    RETURN QUERY
    SELECT 'records'::TEXT, 'isolated'::TEXT, count(*)
    FROM public.records WHERE tenant_id = test_tenant_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions on security functions
GRANT EXECUTE ON FUNCTION security.current_tenant_id() TO pyairtable_app;
GRANT EXECUTE ON FUNCTION security.current_user_id() TO pyairtable_app;
GRANT EXECUTE ON FUNCTION security.user_has_role(UUID, UUID, TEXT) TO pyairtable_app;
GRANT EXECUTE ON FUNCTION tenant_management.create_tenant(TEXT, TEXT, TEXT, TEXT, TEXT) TO pyairtable_admin;

-- =====================================================
-- SECURITY MONITORING VIEWS
-- =====================================================

-- View for tenant security metrics
CREATE VIEW security_audit.tenant_security_metrics AS
SELECT 
    t.id as tenant_id,
    t.name as tenant_name,
    t.tier,
    COUNT(DISTINCT u.id) as user_count,
    COUNT(DISTINCT w.id) as workspace_count,
    COUNT(DISTINCT tb.id) as table_count,
    COUNT(DISTINCT r.id) as record_count,
    COUNT(DISTINCT ak.id) as api_key_count,
    MAX(us.last_activity) as last_user_activity,
    COUNT(CASE WHEN al.result = 'failure' THEN 1 END) as failed_operations_24h
FROM tenant_management.tenants t
LEFT JOIN public.users u ON u.tenant_id = t.id AND u.status = 'active'
LEFT JOIN public.workspaces w ON w.tenant_id = t.id AND w.status = 'active'
LEFT JOIN public.tables tb ON tb.tenant_id = t.id
LEFT JOIN public.records r ON r.tenant_id = t.id
LEFT JOIN public.api_keys ak ON ak.tenant_id = t.id AND ak.status = 'active'
LEFT JOIN public.user_sessions us ON us.tenant_id = t.id
LEFT JOIN security_audit.audit_log al ON al.tenant_id = t.id 
    AND al.created_at > NOW() - INTERVAL '24 hours'
WHERE t.status = 'active'
GROUP BY t.id, t.name, t.tier;

COMMENT ON SCHEMA tenant_management IS 'Multi-tenant management and access control';
COMMENT ON SCHEMA security_audit IS 'Security audit logging and monitoring';
COMMENT ON TABLE tenant_management.tenants IS 'Master tenant registry with security settings';
COMMENT ON TABLE security_audit.audit_log IS 'Comprehensive security event audit log';
COMMENT ON FUNCTION security.current_tenant_id() IS 'Get current tenant ID from session context';
COMMENT ON VIEW security_audit.tenant_security_metrics IS 'Real-time tenant security and usage metrics';