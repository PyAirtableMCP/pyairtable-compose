-- Migration: 005_fix_audit_trigger.up.sql
-- Description: Fix audit trigger to work with existing users table schema
-- The existing users table doesn't have 'role' column, so we need to adapt

-- Drop the existing problematic trigger
DROP TRIGGER IF EXISTS audit_user_changes ON users;

-- Create updated trigger function that works with the existing schema
CREATE OR REPLACE FUNCTION log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM log_security_event(
            NEW.id::UUID,
            NULL,
            'user_created',
            'user_action',
            'New user account created: ' || NEW.email,
            'user',
            NEW.id,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            true,
            NULL,
            NULL,
            jsonb_build_object('name', NEW.name, 'email_verified', NEW.email_verified IS NOT NULL),
            'low'
        );
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Log password changes (comparing password field instead of password_hash)
        IF OLD.password IS DISTINCT FROM NEW.password THEN
            PERFORM log_security_event(
                NEW.id::UUID,
                NULL,
                'password_changed',
                'security_event',
                'User password changed: ' || NEW.email,
                'user',
                NEW.id,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('old_password_changed_at', OLD.password_changed_at),
                'medium'
            );
        END IF;
        
        -- Log email changes
        IF OLD.email != NEW.email THEN
            PERFORM log_security_event(
                NEW.id::UUID,
                NULL,
                'email_changed',
                'security_event',
                'User email changed from ' || OLD.email || ' to ' || NEW.email,
                'user',
                NEW.id,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('old_email', OLD.email, 'new_email', NEW.email),
                'medium'
            );
        END IF;
        
        -- Log two-factor authentication changes
        IF OLD.two_factor_enabled != NEW.two_factor_enabled THEN
            PERFORM log_security_event(
                NEW.id::UUID,
                NULL,
                CASE WHEN NEW.two_factor_enabled THEN 'two_factor_enabled' ELSE 'two_factor_disabled' END,
                'security_event',
                'Two-factor authentication ' || 
                CASE WHEN NEW.two_factor_enabled THEN 'enabled' ELSE 'disabled' END || 
                ' for user: ' || NEW.email,
                'user',
                NEW.id,
                NULL,
                NULL,
                NULL,
                NULL,
                NULL,
                true,
                NULL,
                NULL,
                jsonb_build_object('two_factor_enabled', NEW.two_factor_enabled),
                'medium'
            );
        END IF;
        
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM log_security_event(
            OLD.id::UUID,
            NULL,
            'user_deleted',
            'admin_action',
            'User account deleted: ' || OLD.email,
            'user',
            OLD.id,
            NULL,
            NULL,
            NULL,
            NULL,
            NULL,
            true,
            NULL,
            NULL,
            jsonb_build_object('email', OLD.email, 'name', OLD.name),
            'high'
        );
        RETURN OLD;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Recreate trigger for user changes
CREATE TRIGGER audit_user_changes
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION log_user_changes();

-- Migration completed
INSERT INTO migration_log (version, description, applied_at) 
VALUES ('005', 'Fix audit trigger for existing users table schema', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;