#!/bin/bash

# Create Initial Admin User for PyAirtable Authentication System
# Usage: ./create_admin_user.sh [email] [password] [first_name] [last_name]

set -e

# Docker Compose configuration
COMPOSE_FILE="${COMPOSE_FILE:-../docker-compose.minimal.yml}"
POSTGRES_CONTAINER=""

# Database connection parameters
DB_NAME="${POSTGRES_DB:-pyairtable}"
DB_USER="${POSTGRES_USER:-postgres}"

# Default admin user details
DEFAULT_EMAIL="admin@pyairtable.local"
DEFAULT_PASSWORD="PyAirtable2025!"
DEFAULT_FIRST_NAME="System"
DEFAULT_LAST_NAME="Administrator"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get PostgreSQL container name
get_postgres_container() {
    if [ -z "$POSTGRES_CONTAINER" ]; then
        POSTGRES_CONTAINER=$(docker ps --format "table {{.Names}}" | grep postgres | head -1 || echo "")
        
        if [ -z "$POSTGRES_CONTAINER" ]; then
            # Try with compose project name
            local compose_dir=$(dirname "$COMPOSE_FILE")
            local project_name=$(basename "$compose_dir")
            POSTGRES_CONTAINER="${project_name}-postgres-1"
            
            # Check if this container exists
            if ! docker ps -q -f name="$POSTGRES_CONTAINER" > /dev/null; then
                POSTGRES_CONTAINER=""
            fi
        fi
    fi
    
    echo "$POSTGRES_CONTAINER"
}

# Function to check PostgreSQL container is running
check_postgres_container() {
    local container=$(get_postgres_container)
    
    if [ -z "$container" ]; then
        print_error "PostgreSQL container not found"
        return 1
    fi
    
    if ! docker ps -q -f name="$container" > /dev/null; then
        print_error "PostgreSQL container '$container' is not running"
        return 1
    fi
    
    POSTGRES_CONTAINER="$container"
    return 0
}

# Function to execute SQL in PostgreSQL container
exec_sql() {
    local sql="$1"
    local container="$POSTGRES_CONTAINER"
    
    docker exec -i "$container" psql -U "$DB_USER" -d "$DB_NAME" -c "$sql"
}

# Function to generate bcrypt hash (using Python in container if available)
generate_password_hash() {
    local password="$1"
    
    # Try to use Python to generate bcrypt hash
    if command -v python3 &> /dev/null; then
        python3 -c "
import bcrypt
import sys
password = sys.argv[1].encode('utf-8')
hash = bcrypt.hashpw(password, bcrypt.gensalt(rounds=12))
print(hash.decode('utf-8'))
" "$password" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Function to create admin user
create_admin_user() {
    local email="${1:-$DEFAULT_EMAIL}"
    local password="${2:-$DEFAULT_PASSWORD}"
    local first_name="${3:-$DEFAULT_FIRST_NAME}"
    local last_name="${4:-$DEFAULT_LAST_NAME}"
    
    print_status "Creating admin user: $email"
    
    # Check if user already exists
    local existing_user=$(docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT id FROM users WHERE email = '$email';
    " 2>/dev/null | xargs || echo "")
    
    if [ -n "$existing_user" ]; then
        print_warning "User with email $email already exists (ID: $existing_user)"
        
        # Ask if they want to update the existing user
        read -p "Do you want to update this user to admin? (y/n): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping user creation"
            return 0
        fi
        
        # Update existing user to admin
        exec_sql "
            UPDATE users 
            SET name = '$first_name $last_name',
                timezone = 'UTC',
                locale = 'en-US',
                theme = 'light',
                two_factor_enabled = false,
                is_active = true,
                updated_at = CURRENT_TIMESTAMP
            WHERE email = '$email';
        " > /dev/null
        
        print_success "Updated existing user to admin: $email"
        return 0
    fi
    
    # Generate password hash
    local password_hash=$(generate_password_hash "$password")
    
    if [ -z "$password_hash" ]; then
        print_warning "Could not generate bcrypt hash. Using plain password (NOT SECURE!)"
        password_hash="$password"
    else
        print_status "Generated secure bcrypt password hash"
    fi
    
    # Generate UUID for user ID
    local user_id=$(docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT gen_random_uuid();" 2>/dev/null | xargs)
    
    if [ -z "$user_id" ]; then
        # Fallback to a simple UUID-like string
        user_id="admin-$(date +%s)-$(shuf -i 1000-9999 -n 1)"
        print_warning "Using simple ID: $user_id"
    fi
    
    # Create the admin user
    exec_sql "
        INSERT INTO users (
            id, 
            name, 
            email, 
            email_verified,
            password, 
            timezone, 
            locale, 
            theme,
            two_factor_enabled,
            last_login_at,
            login_count,
            created_at,
            updated_at,
            failed_login_attempts,
            password_changed_at
        ) VALUES (
            '$user_id',
            '$first_name $last_name',
            '$email',
            CURRENT_TIMESTAMP,
            '$password_hash',
            'UTC',
            'en-US',
            'light',
            false,
            NULL,
            0,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP,
            0,
            CURRENT_TIMESTAMP
        );
    " > /dev/null
    
    print_success "Created admin user successfully!"
    
    # Verify the user was created
    local created_user=$(docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            id, 
            name, 
            email, 
            email_verified IS NOT NULL as email_verified,
            created_at
        FROM users 
        WHERE email = '$email';
    ")
    
    echo
    print_status "Admin User Details:"
    echo "$created_user"
    
    echo
    print_status "Login Credentials:"
    echo "  Email: $email"
    echo "  Password: $password"
    echo
    print_warning "IMPORTANT: Change the default password after first login!"
    
    # Log the admin user creation as a security event
    exec_sql "
        SELECT log_security_event(
            '$user_id'::UUID,
            NULL,
            'admin_user_created',
            'admin_action',
            'Initial admin user created: $email',
            'user',
            '$user_id',
            NULL,
            'create_admin_user.sh',
            NULL,
            NULL,
            NULL,
            true,
            NULL,
            NULL,
            '{\"method\": \"script\", \"initial_setup\": true}'::JSONB,
            'medium'
        );
    " > /dev/null
    
    print_success "Logged admin user creation event"
}

# Function to show current admin users
show_admin_users() {
    print_status "Current admin users in database:"
    
    docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
        SELECT 
            id, 
            name, 
            email, 
            email_verified IS NOT NULL as email_verified,
            last_login_at,
            login_count,
            created_at
        FROM users 
        WHERE email LIKE '%admin%' OR name LIKE '%Admin%'
        ORDER BY created_at DESC;
    "
}

# Function to show help
show_help() {
    echo "PyAirtable Admin User Creator"
    echo
    echo "Usage: $0 [email] [password] [first_name] [last_name]"
    echo
    echo "Arguments (all optional):"
    echo "  email        Admin email address (default: $DEFAULT_EMAIL)"
    echo "  password     Admin password (default: $DEFAULT_PASSWORD)"
    echo "  first_name   First name (default: $DEFAULT_FIRST_NAME)"
    echo "  last_name    Last name (default: $DEFAULT_LAST_NAME)"
    echo
    echo "Commands:"
    echo "  help         Show this help message"
    echo "  list         List current admin users"
    echo
    echo "Examples:"
    echo "  $0                                    # Create default admin user"
    echo "  $0 admin@company.com SecurePass123    # Create with custom email/password"
    echo "  $0 list                               # List existing admin users"
    echo
    echo "Security Notes:"
    echo "  - Password must be at least 8 characters"
    echo "  - Default password should be changed immediately"
    echo "  - User creation is logged in audit_logs table"
}

# Function to validate input
validate_input() {
    local email="$1"
    local password="$2"
    
    # Validate email format (basic)
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    
    # Validate password length
    if [ ${#password} -lt 8 ]; then
        print_error "Password must be at least 8 characters long"
        return 1
    fi
    
    return 0
}

# Main function
main() {
    local command="${1:-create}"
    
    case "$command" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
            
        "list")
            if ! check_postgres_container; then
                exit 1
            fi
            show_admin_users
            exit 0
            ;;
            
        *)
            # Treat as create command with arguments
            local email="${1:-$DEFAULT_EMAIL}"
            local password="${2:-$DEFAULT_PASSWORD}"
            local first_name="${3:-$DEFAULT_FIRST_NAME}"
            local last_name="${4:-$DEFAULT_LAST_NAME}"
            
            if ! check_postgres_container; then
                exit 1
            fi
            
            if ! validate_input "$email" "$password"; then
                exit 1
            fi
            
            create_admin_user "$email" "$password" "$first_name" "$last_name"
            
            echo
            print_status "Next steps:"
            echo "1. Test login with the admin credentials"
            echo "2. Change the default password"
            echo "3. Configure additional admin users if needed"
            echo "4. Review security settings and audit logs"
            ;;
    esac
}

# Run main function
main "$@"