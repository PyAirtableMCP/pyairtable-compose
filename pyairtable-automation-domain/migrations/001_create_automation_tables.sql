-- Initial automation domain database schema
-- This script creates the core tables for the automation domain service

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create enum types
CREATE TYPE workflow_status AS ENUM ('active', 'inactive', 'archived');
CREATE TYPE execution_status AS ENUM ('pending', 'running', 'completed', 'failed', 'cancelled');
CREATE TYPE notification_status AS ENUM ('pending', 'sent', 'failed', 'retrying');
CREATE TYPE webhook_status AS ENUM ('pending', 'delivered', 'failed', 'retrying');
CREATE TYPE trigger_type AS ENUM ('manual', 'scheduled', 'webhook', 'event');
CREATE TYPE notification_type AS ENUM ('email', 'sms', 'push');

-- Workflows table
CREATE TABLE workflows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    trigger_type trigger_type NOT NULL,
    trigger_config JSONB NOT NULL DEFAULT '{}',
    steps JSONB NOT NULL DEFAULT '[]',
    enabled BOOLEAN NOT NULL DEFAULT true,
    status workflow_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_by UUID
);

-- Workflow executions table
CREATE TABLE workflow_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    workflow_id UUID NOT NULL REFERENCES workflows(id) ON DELETE CASCADE,
    status execution_status NOT NULL DEFAULT 'pending',
    input_data JSONB NOT NULL DEFAULT '{}',
    output_data JSONB NOT NULL DEFAULT '{}',
    context JSONB NOT NULL DEFAULT '{}',
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_ms INTEGER,
    created_by UUID
);

-- Workflow execution steps table
CREATE TABLE workflow_execution_steps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    execution_id UUID NOT NULL REFERENCES workflow_executions(id) ON DELETE CASCADE,
    step_index INTEGER NOT NULL,
    step_id VARCHAR(255) NOT NULL,
    step_type VARCHAR(100) NOT NULL,
    status execution_status NOT NULL DEFAULT 'pending',
    input_data JSONB NOT NULL DEFAULT '{}',
    output_data JSONB NOT NULL DEFAULT '{}',
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_ms INTEGER
);

-- Notification templates table
CREATE TABLE notification_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    type notification_type NOT NULL,
    subject VARCHAR(500), -- For email templates
    body TEXT NOT NULL,
    html_body TEXT, -- For email templates
    variables JSONB NOT NULL DEFAULT '[]',
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_by UUID
);

-- Notifications table
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type notification_type NOT NULL,
    status notification_status NOT NULL DEFAULT 'pending',
    recipient JSONB NOT NULL, -- Array of recipients (emails, phone numbers, etc.)
    subject VARCHAR(500), -- For email notifications
    body TEXT NOT NULL,
    html_body TEXT, -- For email notifications
    template_id UUID REFERENCES notification_templates(id),
    template_data JSONB,
    metadata JSONB NOT NULL DEFAULT '{}',
    error_message TEXT,
    sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    task_id VARCHAR(255) -- Celery task ID
);

-- Webhook endpoints table
CREATE TABLE webhook_endpoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    url TEXT NOT NULL,
    description TEXT,
    events JSONB NOT NULL DEFAULT '[]', -- Array of event types
    secret VARCHAR(255), -- For signature verification
    enabled BOOLEAN NOT NULL DEFAULT true,
    headers JSONB NOT NULL DEFAULT '{}',
    retry_policy JSONB NOT NULL DEFAULT '{}',
    last_delivery_at TIMESTAMP WITH TIME ZONE,
    delivery_count INTEGER NOT NULL DEFAULT 0,
    success_count INTEGER NOT NULL DEFAULT 0,
    failure_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_by UUID
);

-- Webhook deliveries table
CREATE TABLE webhook_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    endpoint_id UUID NOT NULL REFERENCES webhook_endpoints(id) ON DELETE CASCADE,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    status webhook_status NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    response_code INTEGER,
    response_body TEXT,
    error_message TEXT,
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_attempt_at TIMESTAMP WITH TIME ZONE,
    next_retry_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    task_id VARCHAR(255) -- Celery task ID
);

-- Automation rules table
CREATE TABLE automation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    trigger JSONB NOT NULL,
    conditions JSONB NOT NULL DEFAULT '[]',
    actions JSONB NOT NULL DEFAULT '[]',
    enabled BOOLEAN NOT NULL DEFAULT true,
    priority INTEGER NOT NULL DEFAULT 1,
    execution_count INTEGER NOT NULL DEFAULT 0,
    success_count INTEGER NOT NULL DEFAULT 0,
    failure_count INTEGER NOT NULL DEFAULT 0,
    last_execution_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_by UUID
);

-- Automation executions table
CREATE TABLE automation_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rule_id UUID NOT NULL REFERENCES automation_rules(id) ON DELETE CASCADE,
    status execution_status NOT NULL DEFAULT 'pending',
    trigger_data JSONB NOT NULL DEFAULT '{}',
    context JSONB NOT NULL DEFAULT '{}',
    result JSONB NOT NULL DEFAULT '{}',
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    duration_ms INTEGER,
    task_id VARCHAR(255) -- Celery task ID
);

-- Create indexes for better performance
CREATE INDEX idx_workflows_status ON workflows(status);
CREATE INDEX idx_workflows_enabled ON workflows(enabled);
CREATE INDEX idx_workflows_trigger_type ON workflows(trigger_type);
CREATE INDEX idx_workflows_created_at ON workflows(created_at);

CREATE INDEX idx_workflow_executions_workflow_id ON workflow_executions(workflow_id);
CREATE INDEX idx_workflow_executions_status ON workflow_executions(status);
CREATE INDEX idx_workflow_executions_started_at ON workflow_executions(started_at);

CREATE INDEX idx_workflow_execution_steps_execution_id ON workflow_execution_steps(execution_id);
CREATE INDEX idx_workflow_execution_steps_step_index ON workflow_execution_steps(step_index);

CREATE INDEX idx_notification_templates_type ON notification_templates(type);
CREATE INDEX idx_notification_templates_enabled ON notification_templates(enabled);

CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_status ON notifications(status);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);
CREATE INDEX idx_notifications_template_id ON notifications(template_id);

CREATE INDEX idx_webhook_endpoints_enabled ON webhook_endpoints(enabled);
CREATE INDEX idx_webhook_endpoints_events ON webhook_endpoints USING GIN(events);

CREATE INDEX idx_webhook_deliveries_endpoint_id ON webhook_deliveries(endpoint_id);
CREATE INDEX idx_webhook_deliveries_status ON webhook_deliveries(status);
CREATE INDEX idx_webhook_deliveries_event_type ON webhook_deliveries(event_type);
CREATE INDEX idx_webhook_deliveries_scheduled_at ON webhook_deliveries(scheduled_at);
CREATE INDEX idx_webhook_deliveries_next_retry_at ON webhook_deliveries(next_retry_at);

CREATE INDEX idx_automation_rules_enabled ON automation_rules(enabled);
CREATE INDEX idx_automation_rules_trigger ON automation_rules USING GIN(trigger);
CREATE INDEX idx_automation_rules_priority ON automation_rules(priority);

CREATE INDEX idx_automation_executions_rule_id ON automation_executions(rule_id);
CREATE INDEX idx_automation_executions_status ON automation_executions(status);
CREATE INDEX idx_automation_executions_started_at ON automation_executions(started_at);

-- Create triggers for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_workflows_updated_at
    BEFORE UPDATE ON workflows
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notification_templates_updated_at
    BEFORE UPDATE ON notification_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_webhook_endpoints_updated_at
    BEFORE UPDATE ON webhook_endpoints
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_automation_rules_updated_at
    BEFORE UPDATE ON automation_rules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert some sample data for development
INSERT INTO notification_templates (name, type, subject, body, html_body, variables) VALUES
('welcome_email', 'email', 'Welcome to {{app_name}}!', 'Hello {{user_name}}, welcome to {{app_name}}!', '<h1>Hello {{user_name}}</h1><p>Welcome to {{app_name}}!</p>', '["app_name", "user_name"]'),
('notification_email', 'email', '{{subject}}', '{{message}}', '<p>{{message}}</p>', '["subject", "message"]'),
('welcome_sms', 'sms', NULL, 'Welcome to {{app_name}}, {{user_name}}!', NULL, '["app_name", "user_name"]'),
('alert_sms', 'sms', NULL, 'ALERT: {{message}}', NULL, '["message"]');

-- Create a sample webhook endpoint for testing
INSERT INTO webhook_endpoints (name, url, description, events, enabled) VALUES
('test_endpoint', 'https://httpbin.org/post', 'Test webhook endpoint', '["workflow.completed", "notification.sent"]', false);

-- Create a sample automation rule
INSERT INTO automation_rules (name, description, trigger, conditions, actions, enabled) VALUES
('welcome_automation', 'Send welcome email when user is created', 
 '{"type": "event", "event_type": "user.created"}',
 '[{"type": "field_check", "field": "user.email_verified", "operator": "equals", "value": true}]',
 '[{"type": "notification", "notification_type": "email", "template": "welcome_email", "to": "{{user.email}}", "data": {"app_name": "PyAirtable", "user_name": "{{user.name}}"}}]',
 false);

COMMIT;