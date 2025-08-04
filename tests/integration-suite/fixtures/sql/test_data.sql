-- PyAirtable Integration Test Suite - Base Test Data
-- This file contains the foundational test data for integration testing

-- Clear existing test data
DELETE FROM permissions WHERE user_id LIKE '660e8400%';
DELETE FROM bases WHERE id LIKE '990e8400%';
DELETE FROM projects WHERE id LIKE '880e8400%';
DELETE FROM workspaces WHERE id LIKE '770e8400%';
DELETE FROM users WHERE id LIKE '660e8400%';
DELETE FROM tenants WHERE id LIKE '550e8400%';

-- Insert Test Tenants
INSERT INTO tenants (id, name, domain, status, plan_type, billing_cycle, created_at, updated_at, settings) VALUES
-- Alpha Tenant (Active Enterprise)
('550e8400-e29b-41d4-a716-446655440001', 'Alpha Test Tenant', 'alpha.test.pyairtable.com', 'active', 'enterprise', 'annual', 
 '2024-01-01 00:00:00'::timestamp, '2024-01-01 00:00:00'::timestamp,
 '{"timezone": "UTC", "date_format": "MM/DD/YYYY", "currency": "USD", "max_workspaces": 50, "max_users": 1000, "api_access": true}'::jsonb),

-- Beta Tenant (Active Pro)
('550e8400-e29b-41d4-a716-446655440002', 'Beta Test Tenant', 'beta.test.pyairtable.com', 'active', 'pro', 'monthly',
 '2024-01-15 00:00:00'::timestamp, '2024-01-15 00:00:00'::timestamp,
 '{"timezone": "EST", "date_format": "DD/MM/YYYY", "currency": "EUR", "max_workspaces": 20, "max_users": 100, "api_access": true}'::jsonb),

-- Gamma Tenant (Suspended Free)
('550e8400-e29b-41d4-a716-446655440003', 'Gamma Test Tenant', 'gamma.test.pyairtable.com', 'suspended', 'free', 'monthly',
 '2024-02-01 00:00:00'::timestamp, '2024-02-01 00:00:00'::timestamp,
 '{"timezone": "PST", "date_format": "YYYY-MM-DD", "currency": "USD", "max_workspaces": 5, "max_users": 10, "api_access": false}'::jsonb);

-- Insert Test Users
INSERT INTO users (id, tenant_id, email, username, first_name, last_name, role, status, password_hash, created_at, updated_at, last_login, profile) VALUES
-- Alpha Tenant Users
('660e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'admin@alpha.test.com', 'alpha_admin', 'Alpha', 'Admin', 'tenant_admin', 'active', 
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-01 01:00:00'::timestamp, '2024-01-01 01:00:00'::timestamp, '2024-12-01 10:00:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/alpha_admin.jpg", "bio": "Alpha tenant administrator", "phone": "+1-555-0101", "preferences": {"theme": "dark", "language": "en", "notifications": true}}'::jsonb),

('660e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', 'user1@alpha.test.com', 'alpha_user1', 'Alice', 'Anderson', 'workspace_admin', 'active',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-02 09:00:00'::timestamp, '2024-01-02 09:00:00'::timestamp, '2024-12-01 09:30:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/alice.jpg", "bio": "Workspace administrator", "phone": "+1-555-0102", "company": "Alpha Corp", "job_title": "Project Manager", "preferences": {"theme": "light", "language": "en", "notifications": true}}'::jsonb),

('660e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', 'user2@alpha.test.com', 'alpha_user2', 'Bob', 'Brown', 'editor', 'active',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-03 10:00:00'::timestamp, '2024-01-03 10:00:00'::timestamp, '2024-12-01 08:15:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/bob.jpg", "bio": "Content editor and collaborator", "phone": "+1-555-0103", "company": "Alpha Corp", "job_title": "Content Manager", "preferences": {"theme": "auto", "language": "en", "notifications": false}}'::jsonb),

('660e8400-e29b-41d4-a716-446655440004', '550e8400-e29b-41d4-a716-446655440001', 'user3@alpha.test.com', 'alpha_user3', 'Carol', 'Clark', 'viewer', 'active',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-04 11:00:00'::timestamp, '2024-01-04 11:00:00'::timestamp, '2024-11-30 16:45:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/carol.jpg", "bio": "Viewer and analyst", "phone": "+1-555-0104", "company": "Alpha Corp", "job_title": "Data Analyst", "preferences": {"theme": "light", "language": "en", "notifications": true}}'::jsonb),

-- Beta Tenant Users
('660e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440002', 'admin@beta.test.com', 'beta_admin', 'Beta', 'Admin', 'tenant_admin', 'active',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-15 12:00:00'::timestamp, '2024-01-15 12:00:00'::timestamp, '2024-12-01 11:20:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/beta_admin.jpg", "bio": "Beta tenant administrator", "phone": "+33-1-23-45-67-89", "preferences": {"theme": "dark", "language": "fr", "notifications": true}}'::jsonb),

('660e8400-e29b-41d4-a716-446655440006', '550e8400-e29b-41d4-a716-446655440002', 'user1@beta.test.com', 'beta_user1', 'David', 'Davis', 'workspace_admin', 'active',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-16 13:00:00'::timestamp, '2024-01-16 13:00:00'::timestamp, '2024-12-01 14:10:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/david.jpg", "bio": "Beta workspace admin", "phone": "+33-1-23-45-67-90", "company": "Beta SAS", "job_title": "Operations Manager", "preferences": {"theme": "light", "language": "fr", "notifications": true}}'::jsonb),

('660e8400-e29b-41d4-a716-446655440007', '550e8400-e29b-41d4-a716-446655440002', 'user2@beta.test.com', 'beta_user2', 'Eve', 'Evans', 'editor', 'active',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-01-17 14:00:00'::timestamp, '2024-01-17 14:00:00'::timestamp, '2024-11-29 15:30:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/eve.jpg", "bio": "Marketing specialist", "phone": "+33-1-23-45-67-91", "company": "Beta SAS", "job_title": "Marketing Manager", "preferences": {"theme": "auto", "language": "fr", "notifications": false}}'::jsonb),

-- Gamma Tenant Users (Suspended)
('660e8400-e29b-41d4-a716-446655440008', '550e8400-e29b-41d4-a716-446655440003', 'admin@gamma.test.com', 'gamma_admin', 'Gamma', 'Admin', 'tenant_admin', 'inactive',
 '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewIr7R0MlZ5dKHMO', '2024-02-01 15:00:00'::timestamp, '2024-02-01 15:00:00'::timestamp, '2024-02-15 10:00:00'::timestamp,
 '{"avatar_url": "https://example.com/avatars/gamma_admin.jpg", "bio": "Suspended tenant admin", "phone": "+1-555-0999", "preferences": {"theme": "light", "language": "en", "notifications": false}}'::jsonb);

-- Insert Test Workspaces
INSERT INTO workspaces (id, tenant_id, name, description, created_by, status, created_at, updated_at, settings) VALUES
-- Alpha Tenant Workspaces
('770e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'Alpha Main Workspace', 'Primary workspace for Alpha tenant with comprehensive project management', '660e8400-e29b-41d4-a716-446655440001',
 'active', '2024-01-02 10:00:00'::timestamp, '2024-01-02 10:00:00'::timestamp,
 '{"visibility": "team", "collaboration": true, "version_control": true, "backup_enabled": true, "max_projects": 50, "integrations": ["slack", "zapier"], "templates": {"enabled": true, "custom_allowed": true}}'::jsonb),

('770e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', 'Alpha Analytics Workspace', 'Dedicated workspace for analytics and reporting', '660e8400-e29b-41d4-a716-446655440002',
 'active', '2024-01-05 11:00:00'::timestamp, '2024-01-05 11:00:00'::timestamp,
 '{"visibility": "private", "collaboration": true, "version_control": false, "backup_enabled": true, "max_projects": 20, "integrations": ["teams"], "templates": {"enabled": true, "custom_allowed": false}}'::jsonb),

-- Beta Tenant Workspaces
('770e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440002', 'Beta Marketing Hub', 'Central hub for all marketing activities and campaigns', '660e8400-e29b-41d4-a716-446655440005',
 'active', '2024-01-20 12:00:00'::timestamp, '2024-01-20 12:00:00'::timestamp,
 '{"visibility": "public", "collaboration": true, "version_control": true, "backup_enabled": true, "max_projects": 30, "integrations": ["discord", "automate"], "templates": {"enabled": true, "custom_allowed": true}}'::jsonb);

-- Insert Test Projects
INSERT INTO projects (id, workspace_id, name, description, created_by, status, created_at, updated_at) VALUES
-- Alpha Main Workspace Projects
('880e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440001', 'Customer Relationship Management', 'Comprehensive CRM system for managing customer interactions and sales pipeline', '660e8400-e29b-41d4-a716-446655440002',
 'active', '2024-01-03 09:00:00'::timestamp, '2024-01-03 09:00:00'::timestamp),

('880e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440001', 'Product Development Tracker', 'Tracking system for product development lifecycle and feature roadmap', '660e8400-e29b-41d4-a716-446655440002',
 'active', '2024-01-04 10:00:00'::timestamp, '2024-01-04 10:00:00'::timestamp),

-- Alpha Analytics Workspace Projects
('880e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440002', 'Business Intelligence Dashboard', 'Centralized dashboard for business metrics and KPIs', '660e8400-e29b-41d4-a716-446655440003',
 'active', '2024-01-06 11:00:00'::timestamp, '2024-01-06 11:00:00'::timestamp),

-- Beta Marketing Hub Projects
('880e8400-e29b-41d4-a716-446655440004', '770e8400-e29b-41d4-a716-446655440003', 'Campaign Management System', 'System for planning, executing, and tracking marketing campaigns', '660e8400-e29b-41d4-a716-446655440006',
 'active', '2024-01-21 13:00:00'::timestamp, '2024-01-21 13:00:00'::timestamp);

-- Insert Test Bases
INSERT INTO bases (id, project_id, name, type, schema, created_by, status, created_at, updated_at) VALUES
-- CRM Project Bases
('990e8400-e29b-41d4-a716-446655440001', '880e8400-e29b-41d4-a716-446655440001', 'Customer Contacts', 'crm',
 '{"tables": [{"name": "Contacts", "fields": [{"name": "Name", "type": "singleLineText"}, {"name": "Email", "type": "email"}, {"name": "Phone", "type": "phoneNumber"}, {"name": "Company", "type": "singleLineText"}, {"name": "Status", "type": "singleSelect", "options": ["Lead", "Prospect", "Customer", "Inactive"]}]}, {"name": "Companies", "fields": [{"name": "Name", "type": "singleLineText"}, {"name": "Industry", "type": "singleSelect"}, {"name": "Size", "type": "number"}]}]}'::jsonb,
 '660e8400-e29b-41d4-a716-446655440002', 'active', '2024-01-03 10:00:00'::timestamp, '2024-01-03 10:00:00'::timestamp),

('990e8400-e29b-41d4-a716-446655440002', '880e8400-e29b-41d4-a716-446655440001', 'Sales Pipeline', 'crm',
 '{"tables": [{"name": "Opportunities", "fields": [{"name": "Name", "type": "singleLineText"}, {"name": "Value", "type": "currency"}, {"name": "Stage", "type": "singleSelect", "options": ["Prospecting", "Qualification", "Proposal", "Negotiation", "Closed Won", "Closed Lost"]}, {"name": "Close Date", "type": "date"}, {"name": "Probability", "type": "percent"}]}]}'::jsonb,
 '660e8400-e29b-41d4-a716-446655440002', 'active', '2024-01-03 11:00:00'::timestamp, '2024-01-03 11:00:00'::timestamp),

-- Product Development Project Base
('990e8400-e29b-41d4-a716-446655440003', '880e8400-e29b-41d4-a716-446655440002', 'Feature Roadmap', 'project_management',
 '{"tables": [{"name": "Features", "fields": [{"name": "Name", "type": "singleLineText"}, {"name": "Description", "type": "longText"}, {"name": "Priority", "type": "singleSelect", "options": ["High", "Medium", "Low"]}, {"name": "Status", "type": "singleSelect", "options": ["Backlog", "In Progress", "Testing", "Complete"]}, {"name": "Release", "type": "singleSelect"}, {"name": "Effort", "type": "number"}]}]}'::jsonb,
 '660e8400-e29b-41d4-a716-446655440002', 'active', '2024-01-04 11:00:00'::timestamp, '2024-01-04 11:00:00'::timestamp),

-- Campaign Management Project Base
('990e8400-e29b-41d4-a716-446655440004', '880e8400-e29b-41d4-a716-446655440004', 'Marketing Campaigns', 'marketing',
 '{"tables": [{"name": "Campaigns", "fields": [{"name": "Name", "type": "singleLineText"}, {"name": "Type", "type": "singleSelect", "options": ["Email", "Social", "PPC", "Content", "Event"]}, {"name": "Status", "type": "singleSelect", "options": ["Planning", "Active", "Paused", "Completed"]}, {"name": "Budget", "type": "currency"}, {"name": "Start Date", "type": "date"}, {"name": "End Date", "type": "date"}, {"name": "ROI", "type": "percent"}]}]}'::jsonb,
 '660e8400-e29b-41d4-a716-446655440006', 'active', '2024-01-21 14:00:00'::timestamp, '2024-01-21 14:00:00'::timestamp);

-- Insert Test Permissions
INSERT INTO permissions (id, user_id, resource_id, resource_type, permission, granted_by, granted_at, expires_at) VALUES
-- Alpha Tenant Permissions
-- Tenant Admin has admin access to everything
('aa0e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', 'tenant', 'admin', '660e8400-e29b-41d4-a716-446655440001', '2024-01-01 01:00:00'::timestamp, NULL),

-- Workspace Admin permissions for Alpha Main Workspace
('aa0e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440001', 'workspace', 'admin', '660e8400-e29b-41d4-a716-446655440001', '2024-01-02 10:00:00'::timestamp, NULL),
('aa0e8400-e29b-41d4-a716-446655440003', '660e8400-e29b-41d4-a716-446655440002', '880e8400-e29b-41d4-a716-446655440001', 'project', 'admin', '660e8400-e29b-41d4-a716-446655440001', '2024-01-03 09:00:00'::timestamp, NULL),
('aa0e8400-e29b-41d4-a716-446655440004', '660e8400-e29b-41d4-a716-446655440002', '880e8400-e29b-41d4-a716-446655440002', 'project', 'admin', '660e8400-e29b-41d4-a716-446655440001', '2024-01-04 10:00:00'::timestamp, NULL),

-- Editor permissions for Alpha user2
('aa0e8400-e29b-41d4-a716-446655440005', '660e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440001', 'workspace', 'editor', '660e8400-e29b-41d4-a716-446655440002', '2024-01-05 09:00:00'::timestamp, NULL),
('aa0e8400-e29b-41d4-a716-446655440006', '660e8400-e29b-41d4-a716-446655440003', '880e8400-e29b-41d4-a716-446655440001', 'project', 'editor', '660e8400-e29b-41d4-a716-446655440002', '2024-01-05 09:30:00'::timestamp, NULL),

-- Viewer permissions for Alpha user3
('aa0e8400-e29b-41d4-a716-446655440007', '660e8400-e29b-41d4-a716-446655440004', '770e8400-e29b-41d4-a716-446655440001', 'workspace', 'viewer', '660e8400-e29b-41d4-a716-446655440002', '2024-01-06 09:00:00'::timestamp, NULL),
('aa0e8400-e29b-41d4-a716-446655440008', '660e8400-e29b-41d4-a716-446655440004', '770e8400-e29b-41d4-a716-446655440002', 'workspace', 'viewer', '660e8400-e29b-41d4-a716-446655440001', '2024-01-06 09:15:00'::timestamp, NULL),

-- Analytics Workspace Admin permissions
('aa0e8400-e29b-41d4-a716-446655440009', '660e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440002', 'workspace', 'admin', '660e8400-e29b-41d4-a716-446655440001', '2024-01-05 11:00:00'::timestamp, NULL),

-- Beta Tenant Permissions
-- Tenant Admin has admin access to everything
('aa0e8400-e29b-41d4-a716-446655440010', '660e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440002', 'tenant', 'admin', '660e8400-e29b-41d4-a716-446655440005', '2024-01-15 12:00:00'::timestamp, NULL),

-- Beta Marketing Hub permissions
('aa0e8400-e29b-41d4-a716-446655440011', '660e8400-e29b-41d4-a716-446655440006', '770e8400-e29b-41d4-a716-446655440003', 'workspace', 'admin', '660e8400-e29b-41d4-a716-446655440005', '2024-01-20 12:00:00'::timestamp, NULL),
('aa0e8400-e29b-41d4-a716-446655440012', '660e8400-e29b-41d4-a716-446655440007', '770e8400-e29b-41d4-a716-446655440003', 'workspace', 'editor', '660e8400-e29b-41d4-a716-446655440006', '2024-01-20 13:00:00'::timestamp, NULL),

-- Campaign Management Project permissions
('aa0e8400-e29b-41d4-a716-446655440013', '660e8400-e29b-41d4-a716-446655440006', '880e8400-e29b-41d4-a716-446655440004', 'project', 'admin', '660e8400-e29b-41d4-a716-446655440005', '2024-01-21 13:00:00'::timestamp, NULL),
('aa0e8400-e29b-41d4-a716-446655440014', '660e8400-e29b-41d4-a716-446655440007', '880e8400-e29b-41d4-a716-446655440004', 'project', 'editor', '660e8400-e29b-41d4-a716-446655440006', '2024-01-21 14:00:00'::timestamp, NULL),

-- Base-level permissions
('aa0e8400-e29b-41d4-a716-446655440015', '660e8400-e29b-41d4-a716-446655440007', '990e8400-e29b-41d4-a716-446655440004', 'base', 'admin', '660e8400-e29b-41d4-a716-446655440006', '2024-01-21 15:00:00'::timestamp, NULL);

-- Insert API Keys for testing
INSERT INTO api_keys (id, tenant_id, user_id, key_hash, name, permissions, status, created_at, expires_at) VALUES
('bb0e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', 
 'test-api-key-12345', 'Test API Key Alpha', '["read", "write"]'::jsonb, 'active', '2024-01-01 01:00:00'::timestamp, '2025-01-01 01:00:00'::timestamp),

('bb0e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440005',
 'test-api-key-67890', 'Test API Key Beta', '["read"]'::jsonb, 'active', '2024-01-15 12:00:00'::timestamp, '2025-01-15 12:00:00'::timestamp),

('bb0e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440002',
 'expired-api-key-67890', 'Expired Test API Key', '["read"]'::jsonb, 'expired', '2024-01-01 01:00:00'::timestamp, '2024-06-01 01:00:00'::timestamp);

-- Insert audit logs for testing
INSERT INTO audit_logs (id, tenant_id, user_id, action, resource_type, resource_id, details, ip_address, user_agent, created_at) VALUES
('cc0e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001',
 'user_login', 'user', '660e8400-e29b-41d4-a716-446655440001', '{"login_method": "email_password", "success": true}'::jsonb,
 '192.168.1.100', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', '2024-12-01 10:00:00'::timestamp),

('cc0e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440002',
 'workspace_created', 'workspace', '770e8400-e29b-41d4-a716-446655440001', '{"workspace_name": "Alpha Main Workspace", "initial_settings": {"visibility": "team"}}'::jsonb,
 '192.168.1.101', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', '2024-01-02 10:00:00'::timestamp),

('cc0e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440002',
 'permission_granted', 'permission', 'aa0e8400-e29b-41d4-a716-446655440005', '{"permission": "editor", "resource_type": "workspace", "granted_to": "660e8400-e29b-41d4-a716-446655440003"}'::jsonb,
 '192.168.1.101', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', '2024-01-05 09:00:00'::timestamp);

-- Insert test sessions for authentication testing
INSERT INTO user_sessions (id, user_id, session_token, refresh_token, ip_address, user_agent, created_at, expires_at, last_used_at) VALUES
('dd0e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', 
 'session_token_alpha_admin_123', 'refresh_token_alpha_admin_123', '192.168.1.100',
 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36', '2024-12-01 10:00:00'::timestamp, '2024-12-01 18:00:00'::timestamp, '2024-12-01 10:00:00'::timestamp),

('dd0e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440002',
 'session_token_alice_456', 'refresh_token_alice_456', '192.168.1.101',
 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36', '2024-12-01 09:30:00'::timestamp, '2024-12-01 17:30:00'::timestamp, '2024-12-01 09:30:00'::timestamp);

-- Create indexes for better performance during testing
CREATE INDEX IF NOT EXISTS idx_test_users_tenant_email ON users(tenant_id, email);
CREATE INDEX IF NOT EXISTS idx_test_workspaces_tenant ON workspaces(tenant_id);
CREATE INDEX IF NOT EXISTS idx_test_projects_workspace ON projects(workspace_id);
CREATE INDEX IF NOT EXISTS idx_test_bases_project ON bases(project_id);
CREATE INDEX IF NOT EXISTS idx_test_permissions_user_resource ON permissions(user_id, resource_id, resource_type);
CREATE INDEX IF NOT EXISTS idx_test_audit_logs_tenant_created ON audit_logs(tenant_id, created_at);

-- Update statistics for query planning
ANALYZE tenants;
ANALYZE users;
ANALYZE workspaces;
ANALYZE projects;
ANALYZE bases;
ANALYZE permissions;
ANALYZE api_keys;
ANALYZE audit_logs;
ANALYZE user_sessions;

-- Display summary of inserted test data
SELECT 
    'Test Data Summary' as info,
    (SELECT COUNT(*) FROM tenants WHERE id LIKE '550e8400%') as tenants,
    (SELECT COUNT(*) FROM users WHERE id LIKE '660e8400%') as users,
    (SELECT COUNT(*) FROM workspaces WHERE id LIKE '770e8400%') as workspaces,
    (SELECT COUNT(*) FROM projects WHERE id LIKE '880e8400%') as projects,
    (SELECT COUNT(*) FROM bases WHERE id LIKE '990e8400%') as bases,
    (SELECT COUNT(*) FROM permissions WHERE id LIKE 'aa0e8400%') as permissions;