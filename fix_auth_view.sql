-- Fix users view to support INSERT operations

BEGIN;

-- Drop the existing view
DROP VIEW IF EXISTS users;

-- Create an updatable view with INSTEAD OF triggers
CREATE OR REPLACE VIEW users AS
SELECT 
    COALESCE(uuid_id, gen_random_uuid()) as id,
    email,
    password_hash,
    COALESCE(first_name, '') as first_name,
    COALESCE(last_name, '') as last_name,
    role,
    COALESCE(tenant_id, gen_random_uuid()) as tenant_id,
    is_active,
    email_verified,
    created_at,
    updated_at,
    last_login_at
FROM platform_users;

-- Create INSTEAD OF INSERT trigger
CREATE OR REPLACE FUNCTION users_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO platform_users (
        uuid_id, email, password_hash, first_name, last_name, 
        role, tenant_id, is_active, email_verified, 
        created_at, updated_at, last_login_at
    )
    VALUES (
        NEW.id, NEW.email, NEW.password_hash, NEW.first_name, NEW.last_name,
        NEW.role, NEW.tenant_id, NEW.is_active, NEW.email_verified,
        NEW.created_at, NEW.updated_at, NEW.last_login_at
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_insert_instead_trigger
    INSTEAD OF INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION users_insert_trigger();

-- Create INSTEAD OF UPDATE trigger
CREATE OR REPLACE FUNCTION users_update_trigger()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE platform_users SET
        email = NEW.email,
        password_hash = NEW.password_hash,
        first_name = NEW.first_name,
        last_name = NEW.last_name,
        role = NEW.role,
        tenant_id = NEW.tenant_id,
        is_active = NEW.is_active,
        email_verified = NEW.email_verified,
        created_at = NEW.created_at,
        updated_at = NEW.updated_at,
        last_login_at = NEW.last_login_at
    WHERE uuid_id = NEW.id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_update_instead_trigger
    INSTEAD OF UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION users_update_trigger();

-- Create INSTEAD OF DELETE trigger
CREATE OR REPLACE FUNCTION users_delete_trigger()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM platform_users WHERE uuid_id = OLD.id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_delete_instead_trigger
    INSTEAD OF DELETE ON users
    FOR EACH ROW
    EXECUTE FUNCTION users_delete_trigger();

COMMIT;

-- Verify the changes
SELECT 'View updated successfully' as status;