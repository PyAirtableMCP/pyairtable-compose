#!/bin/bash

# PyAirtable Comprehensive Secret Management System
# Secure generation, rotation, backup, and management of secrets for Minikube deployment
# Author: Claude Deployment Engineer - Enhanced with enterprise security features

set -eo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly SECRETS_DIR="${PROJECT_ROOT}/.secrets"
readonly BACKUP_DIR="${SECRETS_DIR}/backups"
readonly NAMESPACE="${NAMESPACE:-pyairtable}"
readonly SECRET_NAME="${SECRET_NAME:-pyairtable-secrets}"
readonly ENV_FILE="${PROJECT_ROOT}/.env"
readonly ENV_TEMPLATE="${PROJECT_ROOT}/.env.example"

# Security settings
readonly MIN_PASSWORD_LENGTH=32
readonly JWT_SECRET_LENGTH=64
readonly API_KEY_LENGTH=48
readonly ENCRYPTION_KEY_LENGTH=32

# Secret categories and their keys
declare -A CRITICAL_SECRETS=(
    ["API_KEY"]="Internal service-to-service authentication"
    ["GEMINI_API_KEY"]="Google Gemini API access"
    ["AIRTABLE_TOKEN"]="Airtable Personal Access Token"
    ["JWT_SECRET"]="JWT token signing secret"
    ["NEXTAUTH_SECRET"]="NextAuth session secret"
    ["POSTGRES_PASSWORD"]="PostgreSQL database password"
    ["REDIS_PASSWORD"]="Redis authentication password"
)

declare -A OPTIONAL_SECRETS=(
    ["AIRTABLE_BASE"]="Default Airtable Base ID"
    ["THINKING_BUDGET"]="LLM thinking budget limit"
    ["CORS_ORIGINS"]="Allowed CORS origins"
    ["MAX_FILE_SIZE"]="Maximum upload file size"
    ["ALLOWED_EXTENSIONS"]="Allowed file extensions"
)

declare -A DATABASE_SECRETS=(
    ["POSTGRES_DB"]="PostgreSQL database name"
    ["POSTGRES_USER"]="PostgreSQL username"
    ["POSTGRES_REPLICATION_PASSWORD"]="PostgreSQL replication password"
)

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Generate secure password
generate_password() {
    local length="${1:-32}"
    local use_special="${2:-true}"
    
    if command -v openssl >/dev/null; then
        if [ "$use_special" = "true" ]; then
            openssl rand -base64 $((length * 3 / 4)) | tr -d "=+/" | cut -c1-${length}
        else
            openssl rand -hex $((length / 2))
        fi
    elif command -v python3 >/dev/null; then
        python3 -c "import secrets, string; chars = string.ascii_letters + string.digits + ('!@#$%^&*()_+-=' if '$use_special' == 'true' else ''); print(''.join(secrets.choice(chars) for _ in range($length)))"
    else
        # Fallback to /dev/urandom
        tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c $length
    fi
}

# Generate API key
generate_api_key() {
    local length="${1:-48}"
    if command -v python3 >/dev/null; then
        python3 -c "import secrets; print(secrets.token_urlsafe($length))"
    else
        generate_password $length false
    fi
}

# Validate secret strength
validate_secret_strength() {
    local secret_name="$1"
    local secret_value="$2"
    local min_length="${3:-16}"
    
    # Check minimum length
    if [ ${#secret_value} -lt $min_length ]; then
        print_warning "$secret_name is shorter than recommended ($min_length characters)"
        return 1
    fi
    
    # Check for common weak passwords
    local weak_patterns=("password" "123456" "admin" "secret" "default" "changeme")
    for pattern in "${weak_patterns[@]}"; do
        if [[ "${secret_value,,}" == *"${pattern}"* ]]; then
            print_warning "$secret_name contains common weak pattern: $pattern"
            return 1
        fi
    done
    
    return 0
}

# Check if kubectl is available and connected
check_kubectl() {
    if ! command -v kubectl >/dev/null; then
        print_error "kubectl is not installed or not in PATH"
        return 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    return 0
}

# Check if namespace exists
ensure_namespace() {
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        print_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi
}

# Load environment file
load_env_file() {
    local env_file="${1:-$ENV_FILE}"
    
    if [ ! -f "$env_file" ]; then
        print_error "Environment file not found: $env_file"
        return 1
    fi
    
    print_info "Loading environment from: $env_file"
    
    # Export variables from env file safely (excluding comments and empty lines)
    while IFS='=' read -r key value; do
        if [[ $key && $value && ! $key =~ ^# ]]; then
            export "$key"="$value"
        fi
    done < <(grep -v '^#' "$env_file" | grep -v '^$')
    
    return 0
}

# Create environment template
create_env_template() {
    local template_file="${1:-$ENV_TEMPLATE}"
    
    print_header "Creating Environment Template"
    
    cat > "$template_file" << 'EOF'
# PyAirtable Local Development Environment Configuration
# Copy this file to .env and update with your actual values

# =============================================================================
# CRITICAL SECRETS - MUST BE SET
# =============================================================================

# Internal API Key for service-to-service communication
# Generate with: python -c "import secrets; print(secrets.token_urlsafe(48))"
API_KEY=

# Google Gemini API Key
# Get from: https://cloud.google.com/ai-platform/generative-ai/docs/api-key
GEMINI_API_KEY=

# Airtable Personal Access Token
# Get from: https://airtable.com/developers/web/api/authentication
AIRTABLE_TOKEN=

# JWT Secret for token signing
# Generate with: python -c "import secrets; print(secrets.token_urlsafe(64))"
JWT_SECRET=

# NextAuth Secret for session management
# Generate with: python -c "import secrets; print(secrets.token_urlsafe(64))"
NEXTAUTH_SECRET=

# Database Passwords
POSTGRES_PASSWORD=
REDIS_PASSWORD=

# =============================================================================
# OPTIONAL CONFIGURATION
# =============================================================================

# Airtable Base ID (format: appXXXXXXXXXXXXXX)
AIRTABLE_BASE=

# LLM Configuration
THINKING_BUDGET=2000

# CORS Configuration
CORS_ORIGINS=*

# File Upload Configuration
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

POSTGRES_DB=pyairtable
POSTGRES_USER=postgres
POSTGRES_REPLICATION_PASSWORD=

# =============================================================================
# DEVELOPMENT SETTINGS
# =============================================================================

ENVIRONMENT=development
LOG_LEVEL=debug
NODE_ENV=development
EOF
    
    print_success "Environment template created: $template_file"
    print_info "Copy this file to .env and update with your actual values"
}

# Generate development secrets
generate_dev_secrets() {
    print_header "Generating Development Secrets"
    
    local env_file="${1:-$ENV_FILE}"
    local backup_file="${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Backup existing file if it exists
    if [ -f "$env_file" ]; then
        print_info "Backing up existing environment file to: $backup_file"
        cp "$env_file" "$backup_file"
    fi
    
    # Load existing values if available
    declare -A existing_values=()
    if [ -f "$env_file" ]; then
        while IFS='=' read -r key value; do
            if [[ $key && $value && ! $key =~ ^# ]]; then
                existing_values["$key"]="$value"
            fi
        done < "$env_file"
    fi
    
    # Generate or preserve secrets
    local secrets_generated=0
    
    print_info "Generating secure secrets..."
    
    # Critical secrets
    for secret_name in "${!CRITICAL_SECRETS[@]}"; do
        local current_value="${existing_values[$secret_name]:-}"
        local new_value=""
        
        if [ -z "$current_value" ] || [ "$current_value" = "your-${secret_name,,}-here" ]; then
            case $secret_name in
                "API_KEY")
                    new_value=$(generate_api_key 48)
                    ;;
                "JWT_SECRET"|"NEXTAUTH_SECRET")
                    new_value=$(generate_api_key 64)
                    ;;
                "POSTGRES_PASSWORD"|"REDIS_PASSWORD")
                    new_value=$(generate_password 32 false)
                    ;;
                *)
                    new_value=$(generate_password 32)
                    ;;
            esac
            
            existing_values["$secret_name"]="$new_value"
            print_success "Generated $secret_name"
            ((secrets_generated++))
            
        else
            print_info "$secret_name already set, keeping existing value"
        fi
    done
    
    # Set default values for optional secrets
    for secret_name in "${!OPTIONAL_SECRETS[@]}"; do
        if [ -z "${existing_values[$secret_name]:-}" ]; then
            case $secret_name in
                "THINKING_BUDGET")
                    existing_values["$secret_name"]="2000"
                    ;;
                "CORS_ORIGINS")
                    existing_values["$secret_name"]="*"
                    ;;
                "MAX_FILE_SIZE")
                    existing_values["$secret_name"]="10MB"
                    ;;
                "ALLOWED_EXTENSIONS")
                    existing_values["$secret_name"]="pdf,doc,docx,txt,csv,xlsx"
                    ;;
            esac
        fi
    done
    
    # Set database defaults
    for secret_name in "${!DATABASE_SECRETS[@]}"; do
        if [ -z "${existing_values[$secret_name]:-}" ]; then
            case $secret_name in
                "POSTGRES_DB")
                    existing_values["$secret_name"]="pyairtable"
                    ;;
                "POSTGRES_USER")
                    existing_values["$secret_name"]="postgres"
                    ;;
                "POSTGRES_REPLICATION_PASSWORD")
                    existing_values["$secret_name"]=$(generate_password 32 false)
                    ((secrets_generated++))
                    ;;
            esac
        fi
    done
    
    # Write updated environment file
    cat > "$env_file" << 'EOF'
# PyAirtable Local Development Environment Configuration
# Generated secrets for local development

# =============================================================================
# CRITICAL SECRETS
# =============================================================================

EOF
    
    # Write critical secrets
    for secret_name in "${!CRITICAL_SECRETS[@]}"; do
        echo "# ${CRITICAL_SECRETS[$secret_name]}" >> "$env_file"
        echo "${secret_name}=${existing_values[$secret_name]:-}" >> "$env_file"
        echo "" >> "$env_file"
    done
    
    # Write optional configuration
    cat >> "$env_file" << 'EOF'
# =============================================================================
# OPTIONAL CONFIGURATION
# =============================================================================

EOF
    
    for secret_name in "${!OPTIONAL_SECRETS[@]}"; do
        echo "# ${OPTIONAL_SECRETS[$secret_name]}" >> "$env_file"
        echo "${secret_name}=${existing_values[$secret_name]:-}" >> "$env_file"
        echo "" >> "$env_file"
    done
    
    # Write database configuration
    cat >> "$env_file" << 'EOF'
# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

EOF
    
    for secret_name in "${!DATABASE_SECRETS[@]}"; do
        echo "# ${DATABASE_SECRETS[$secret_name]}" >> "$env_file"
        echo "${secret_name}=${existing_values[$secret_name]:-}" >> "$env_file"
        echo "" >> "$env_file"
    done
    
    # Write development settings
    cat >> "$env_file" << 'EOF'
# =============================================================================
# DEVELOPMENT SETTINGS
# =============================================================================

ENVIRONMENT=development
LOG_LEVEL=debug
NODE_ENV=development
EOF
    
    print_success "Environment file generated: $env_file"
    print_info "Generated $secrets_generated new secrets"
    
    if [ $secrets_generated -gt 0 ]; then
        print_warning "New secrets generated. You may need to:"
        print_warning "1. Set GEMINI_API_KEY with your actual API key"
        print_warning "2. Set AIRTABLE_TOKEN with your Airtable token"
        print_warning "3. Set AIRTABLE_BASE with your base ID"
    fi
}

# Create Kubernetes secret from environment file
create_k8s_secret() {
    local env_file="${1:-$ENV_FILE}"
    local secret_name="${2:-$SECRET_NAME}"
    local namespace="${3:-$NAMESPACE}"
    
    print_header "Creating Kubernetes Secret"
    
    if [ ! -f "$env_file" ]; then
        print_error "Environment file not found: $env_file"
        return 1
    fi
    
    ensure_namespace
    
    # Delete existing secret if it exists
    if kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        print_info "Deleting existing secret: $secret_name"
        kubectl delete secret "$secret_name" -n "$namespace"
    fi
    
    # Create secret from env file
    print_info "Creating secret from environment file: $env_file"
    kubectl create secret generic "$secret_name" \
        --from-env-file="$env_file" \
        --namespace="$namespace"
    
    # Add labels and annotations
    kubectl label secret "$secret_name" \
        app.kubernetes.io/name=pyairtable \
        app.kubernetes.io/component=secrets \
        app.kubernetes.io/managed-by=secret-manager \
        -n "$namespace"
    
    kubectl annotate secret "$secret_name" \
        created-by="secret-manager.sh" \
        created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        -n "$namespace"
    
    print_success "Kubernetes secret created: $secret_name"
}

# Update existing Kubernetes secret
update_k8s_secret() {
    local env_file="${1:-$ENV_FILE}"
    local secret_name="${2:-$SECRET_NAME}"
    local namespace="${3:-$NAMESPACE}"
    
    print_header "Updating Kubernetes Secret"
    
    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        print_info "Secret doesn't exist, creating new one"
        create_k8s_secret "$env_file" "$secret_name" "$namespace"
        return
    fi
    
    # Create new secret and replace
    create_k8s_secret "$env_file" "$secret_name" "$namespace"
    
    print_success "Kubernetes secret updated: $secret_name"
}

# Validate secrets
validate_secrets() {
    local env_file="${1:-$ENV_FILE}"
    
    print_header "Validating Secrets"
    
    if [ ! -f "$env_file" ]; then
        print_error "Environment file not found: $env_file"
        return 1
    fi
    
    local validation_errors=0
    local validation_warnings=0
    
    # Load environment file
    load_env_file "$env_file"
    
    # Validate critical secrets
    print_info "Validating critical secrets..."
    for secret_name in "${!CRITICAL_SECRETS[@]}"; do
        local secret_value="${!secret_name:-}"
        
        if [ -z "$secret_value" ]; then
            print_error "$secret_name is not set"
            ((validation_errors++))
        else
            case $secret_name in
                "API_KEY"|"JWT_SECRET"|"NEXTAUTH_SECRET")
                    if ! validate_secret_strength "$secret_name" "$secret_value" 32; then
                        ((validation_warnings++))
                    fi
                    ;;
                "POSTGRES_PASSWORD"|"REDIS_PASSWORD")
                    if ! validate_secret_strength "$secret_name" "$secret_value" 16; then
                        ((validation_warnings++))
                    fi
                    ;;
                "GEMINI_API_KEY")
                    if [[ ! "$secret_value" =~ ^AI[a-zA-Z0-9_-]+$ ]]; then
                        print_warning "$secret_name doesn't match expected Gemini API key format"
                        ((validation_warnings++))
                    fi
                    ;;
                "AIRTABLE_TOKEN")
                    if [[ ! "$secret_value" =~ ^pat[a-zA-Z0-9_-]+$ ]] && [[ ! "$secret_value" =~ ^key[a-zA-Z0-9_-]+$ ]]; then
                        print_warning "$secret_name doesn't match expected Airtable token format"
                        ((validation_warnings++))
                    fi
                    ;;
            esac
        fi
    done
    
    # Check for development placeholders
    print_info "Checking for placeholder values..."
    local placeholder_patterns=("your-" "change-me" "replace-me" "TODO" "FIXME")
    for pattern in "${placeholder_patterns[@]}"; do
        if grep -qi "$pattern" "$env_file"; then
            print_warning "Found placeholder pattern '$pattern' in environment file"
            ((validation_warnings++))
        fi
    done
    
    # Report results
    echo ""
    echo "Validation Results:"
    echo "=================="
    echo "Errors: $validation_errors"
    echo "Warnings: $validation_warnings"
    
    if [ $validation_errors -eq 0 ]; then
        if [ $validation_warnings -eq 0 ]; then
            print_success "All secrets validated successfully!"
        else
            print_warning "Validation passed with warnings"
        fi
        return 0
    else
        print_error "Validation failed with $validation_errors errors"
        return 1
    fi
}

# Show secret status
show_status() {
    print_header "Secret Status"
    
    # Check environment file
    if [ -f "$ENV_FILE" ]; then
        print_success "Environment file exists: $ENV_FILE"
        
        # Count configured secrets
        local configured_count=0
        local total_count=$((${#CRITICAL_SECRETS[@]} + ${#OPTIONAL_SECRETS[@]} + ${#DATABASE_SECRETS[@]}))
        
        for secret_name in "${!CRITICAL_SECRETS[@]}" "${!OPTIONAL_SECRETS[@]}" "${!DATABASE_SECRETS[@]}"; do
            if grep -q "^${secret_name}=" "$ENV_FILE" && ! grep -q "^${secret_name}=$" "$ENV_FILE"; then
                ((configured_count++))
            fi
        done
        
        echo "Configured secrets: $configured_count/$total_count"
    else
        print_warning "Environment file not found: $ENV_FILE"
    fi
    
    # Check Kubernetes secret
    if check_kubectl && kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
            print_success "Kubernetes secret exists: $SECRET_NAME"
            
            # Show secret keys
            echo ""
            echo "Secret keys:"
            kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | \
                python3 -c "import sys, json; data = json.load(sys.stdin); [print(f'  {k}') for k in sorted(data.keys())]" 2>/dev/null || \
                echo "  (unable to list keys)"
        else
            print_warning "Kubernetes secret not found: $SECRET_NAME"
        fi
    else
        print_info "Kubernetes cluster not accessible"
    fi
}

# Rotate secrets
rotate_secrets() {
    local secret_names=("$@")
    
    print_header "Rotating Secrets"
    
    if [ ${#secret_names[@]} -eq 0 ]; then
        # Rotate all generated secrets by default
        secret_names=("API_KEY" "JWT_SECRET" "NEXTAUTH_SECRET" "POSTGRES_PASSWORD" "REDIS_PASSWORD")
    fi
    
    local backup_file="${ENV_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$ENV_FILE" ]; then
        print_info "Backing up current environment to: $backup_file"
        cp "$ENV_FILE" "$backup_file"
        
        # Load current environment
        load_env_file "$ENV_FILE"
        
        # Rotate specified secrets
        for secret_name in "${secret_names[@]}"; do
            print_info "Rotating $secret_name..."
            
            local new_value=""
            case $secret_name in
                "API_KEY")
                    new_value=$(generate_api_key 48)
                    ;;
                "JWT_SECRET"|"NEXTAUTH_SECRET")
                    new_value=$(generate_api_key 64)
                    ;;
                "POSTGRES_PASSWORD"|"REDIS_PASSWORD")
                    new_value=$(generate_password 32 false)
                    ;;
                *)
                    new_value=$(generate_password 32)
                    ;;
            esac
            
            # Update in environment file
            if grep -q "^${secret_name}=" "$ENV_FILE"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s/^${secret_name}=.*/${secret_name}=${new_value}/" "$ENV_FILE"
                else
                    sed -i "s/^${secret_name}=.*/${secret_name}=${new_value}/" "$ENV_FILE"
                fi
                print_success "Rotated $secret_name"
            else
                print_warning "$secret_name not found in environment file"
            fi
        done
        
        print_success "Secret rotation completed"
        print_warning "You need to update the Kubernetes secret: $0 --update-k8s"
        
    else
        print_error "Environment file not found: $ENV_FILE"
        return 1
    fi
}

# Main function
main() {
    local action="status"
    local env_file="$ENV_FILE"
    local secret_names=()
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --generate)
                action="generate"
                shift
                ;;
            --create-template)
                action="create-template"
                shift
                ;;
            --create-k8s)
                action="create-k8s"
                shift
                ;;
            --update-k8s)
                action="update-k8s"
                shift
                ;;
            --validate)
                action="validate"
                shift
                ;;
            --status)
                action="status"
                shift
                ;;
            --rotate)
                action="rotate"
                shift
                # Collect secret names to rotate
                while [[ $# -gt 0 && ! $1 =~ ^-- ]]; do
                    secret_names+=("$1")
                    shift
                done
                ;;
            --env-file)
                env_file="$2"
                shift 2
                ;;
            --namespace|-n)
                NAMESPACE="$2"
                shift 2
                ;;
            --secret-name)
                SECRET_NAME="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [ACTION]"
                echo ""
                echo "Actions:"
                echo "  --generate          Generate development secrets"
                echo "  --create-template   Create environment template file"
                echo "  --create-k8s        Create Kubernetes secret from env file"
                echo "  --update-k8s        Update existing Kubernetes secret"
                echo "  --validate          Validate secrets in env file"
                echo "  --status            Show secret status (default)"
                echo "  --rotate [NAMES]    Rotate specified secrets (or common ones)"
                echo ""
                echo "Options:"
                echo "  --env-file FILE     Environment file path (default: .env)"
                echo "  --namespace, -n     Target namespace (default: pyairtable)"
                echo "  --secret-name       Kubernetes secret name (default: pyairtable-secrets)"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 --generate                    # Generate all development secrets"
                echo "  $0 --validate                    # Validate current secrets"
                echo "  $0 --create-k8s                  # Create Kubernetes secret"
                echo "  $0 --rotate API_KEY JWT_SECRET   # Rotate specific secrets"
                exit 0
                ;;
            *)
                print_error "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute action
    case $action in
        "generate")
            generate_dev_secrets "$env_file"
            ;;
        "create-template")
            create_env_template "$env_file"
            ;;
        "create-k8s")
            if check_kubectl; then
                create_k8s_secret "$env_file"
            fi
            ;;
        "update-k8s")
            if check_kubectl; then
                update_k8s_secret "$env_file"
            fi
            ;;
        "validate")
            validate_secrets "$env_file"
            ;;
        "status")
            show_status
            ;;
        "rotate")
            rotate_secrets "${secret_names[@]}"
            ;;
        *)
            print_error "Unknown action: $action"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"