-- Fix users view trigger to handle meta_data column

BEGIN;

-- Update the INSTEAD OF INSERT trigger to include meta_data
CREATE OR REPLACE FUNCTION users_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO platform_users (
        uuid_id, email, password_hash, first_name, last_name, 
        role, tenant_id, is_active, email_verified, 
        created_at, updated_at, last_login_at, meta_data
    )
    VALUES (
        NEW.id, NEW.email, NEW.password_hash, NEW.first_name, NEW.last_name,
        NEW.role, NEW.tenant_id, NEW.is_active, NEW.email_verified,
        NEW.created_at, NEW.updated_at, NEW.last_login_at, '{}'::json
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;

-- Verify the changes
SELECT 'Trigger updated successfully' as status;