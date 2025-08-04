#!/bin/bash

# PyAirtable Secrets Management Script
# Secure handling of secrets for local development with easy configuration
# Supports multiple environments and secure secret rotation

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly NAMESPACE="pyairtable"
readonly SECRETS_NAME="pyairtable-secrets"
readonly CONFIG_NAME="pyairtable-config"

# Environment templates
readonly ENVIRONMENTS=("development" "staging" "production")
readonly SECRETS_TEMPLATE_FILE="$PROJECT_ROOT/.env.template"
readonly LOCAL_SECRETS_FILE="$PROJECT_ROOT/.env.local"
readonly VAULT_SECRETS_FILE="$PROJECT_ROOT/.secrets.vault"

# Secret categories and their properties
declare -A SECRET_CATEGORIES=(
    ["auth"]="API_KEY JWT_SECRET NEXTAUTH_SECRET"
    ["database"]="POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD"
    ["cache"]="REDIS_PASSWORD"
    ["external"]="GEMINI_API_KEY AIRTABLE_TOKEN AIRTABLE_BASE"
    ["security"]="ENCRYPTION_KEY WEBHOOK_SECRET"
    ["config"]="THINKING_BUDGET CORS_ORIGINS MAX_FILE_SIZE ALLOWED_EXTENSIONS"
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

print_progress() {
    echo -e "${PURPLE}🔄 $1${NC}"
}

# Generate secure random string
generate_secure_string() {
    local length=${1:-32}
    openssl rand -hex "$length"
}

# Generate JWT secret (base64 encoded)
generate_jwt_secret() {
    openssl rand -base64 32
}

# Generate API key
generate_api_key() {
    echo "pya_$(openssl rand -hex 20)"
}

# Generate database password
generate_db_password() {
    # Generate alphanumeric password
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | fold -w 16 | head -n 1
}

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info &>/dev/null; then
        print_error "kubectl is not configured or cluster is not accessible"
        return 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
    
    return 0
}

# Create secrets template
create_secrets_template() {
    print_header "Creating Secrets Template"
    
    cat > "$SECRETS_TEMPLATE_FILE" <<EOF
# PyAirtable Environment Configuration Template
# Copy this file to .env.local and fill in your actual values
# DO NOT commit actual secrets to version control

# Environment Configuration
ENVIRONMENT=development
LOG_LEVEL=debug
NODE_ENV=development

# Authentication & Security
API_KEY=                    # Main API key for service authentication
JWT_SECRET=                 # JWT signing secret (base64)
NEXTAUTH_SECRET=           # NextAuth.js secret
ENCRYPTION_KEY=            # Data encryption key
WEBHOOK_SECRET=            # Webhook signature secret

# Database Configuration
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=         # PostgreSQL password

# Cache Configuration
REDIS_PASSWORD=            # Redis password

# External API Keys
GEMINI_API_KEY=           # Google Gemini API key
AIRTABLE_TOKEN=           # Airtable API token
AIRTABLE_BASE=            # Airtable base ID

# Application Configuration
THINKING_BUDGET=2000
CORS_ORIGINS=*
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx,json,yaml

# Development Features
ENABLE_DEBUG=true
ENABLE_METRICS=true
ENABLE_TRACING=true
SHOW_COST_TRACKING=true

# Service URLs (automatically configured in Kubernetes)
AIRTABLE_GATEWAY_URL=http://airtable-gateway:8002
MCP_SERVER_URL=http://mcp-server:8001
LLM_ORCHESTRATOR_URL=http://llm-orchestrator:8003
PLATFORM_SERVICES_URL=http://platform-services:8007
AUTOMATION_SERVICES_URL=http://automation-services:8006
SAGA_ORCHESTRATOR_URL=http://saga-orchestrator:8008
API_GATEWAY_URL=http://api-gateway:8000
FRONTEND_URL=http://frontend:3000

# Development Database URLs
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6379

# NextAuth Configuration
NEXTAUTH_URL=http://localhost:3000

# File Processing Configuration
UPLOAD_DIR=/tmp/uploads
DEFAULT_WORKFLOW_TIMEOUT=300
MAX_WORKFLOW_RETRIES=3
SCHEDULER_CHECK_INTERVAL=30

# Analytics Configuration
ANALYTICS_RETENTION_DAYS=90
METRICS_BATCH_SIZE=100

# Security Configuration
PASSWORD_MIN_LENGTH=8
PASSWORD_HASH_ROUNDS=12
REQUIRE_API_KEY=true

# SAGA Configuration
SAGA_TIMEOUT_SECONDS=3600
SAGA_RETRY_ATTEMPTS=3
SAGA_STEP_TIMEOUT_SECONDS=300
USE_REDIS_EVENT_BUS=true

# Monitoring Configuration
ENABLE_METRICS=true
METRICS_PORT=9090
EOF
    
    print_success "Template created: $SECRETS_TEMPLATE_FILE"
}

# Generate development secrets
generate_dev_secrets() {
    print_header "Generating Development Secrets"
    
    local env_file="$LOCAL_SECRETS_FILE"
    
    print_progress "Generating secure development secrets..."
    
    # Copy template if local file doesn't exist
    if [[ ! -f "$env_file" ]]; then
        cp "$SECRETS_TEMPLATE_FILE" "$env_file"
    fi
    
    # Generate secrets
    local api_key
    api_key=$(generate_api_key)
    local jwt_secret
    jwt_secret=$(generate_jwt_secret)
    local nextauth_secret
    nextauth_secret=$(generate_secure_string 32)
    local encryption_key
    encryption_key=$(generate_secure_string 32)
    local webhook_secret
    webhook_secret=$(generate_secure_string 24)
    local postgres_password
    postgres_password=$(generate_db_password)
    local redis_password
    redis_password=$(generate_db_password)
    
    # Update env file with generated secrets
    sed -i.backup \
        -e "s|^API_KEY=.*|API_KEY=$api_key|" \
        -e "s|^JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" \
        -e "s|^NEXTAUTH_SECRET=.*|NEXTAUTH_SECRET=$nextauth_secret|" \
        -e "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$encryption_key|" \
        -e "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$webhook_secret|" \
        -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$postgres_password|" \
        -e "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$redis_password|" \
        "$env_file"
    
    # Remove backup file
    rm -f "$env_file.backup"
    
    print_success "Development secrets generated: $env_file"
    print_warning "Remember to set GEMINI_API_KEY and AIRTABLE_TOKEN manually"
}

# Load secrets from file
load_secrets_from_file() {
    local env_file=${1:-"$LOCAL_SECRETS_FILE"}
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Secrets file not found: $env_file"
        return 1
    fi
    
    # Load environment variables
    set -a
    source "$env_file"
    set +a
    
    print_success "Loaded secrets from: $env_file"
}

# Create Kubernetes secret
create_k8s_secret() {
    print_header "Creating Kubernetes Secret"
    
    if ! check_kubectl; then
        return 1
    fi
    
    local env_file=${1:-"$LOCAL_SECRETS_FILE"}
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Secrets file not found: $env_file"
        return 1
    fi
    
    # Load secrets
    load_secrets_from_file "$env_file"
    
    # Delete existing secret if it exists
    if kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" &>/dev/null; then
        print_info "Deleting existing secret: $SECRETS_NAME"
        kubectl delete secret "$SECRETS_NAME" -n "$NAMESPACE"
    fi
    
    print_progress "Creating Kubernetes secret: $SECRETS_NAME"
    
    # Create secret with all required values
    kubectl create secret generic "$SECRETS_NAME" \
        --namespace="$NAMESPACE" \
        --from-literal=api-key="${API_KEY:-}" \
        --from-literal=jwt-secret="${JWT_SECRET:-}" \
        --from-literal=nextauth-secret="${NEXTAUTH_SECRET:-}" \
        --from-literal=encryption-key="${ENCRYPTION_KEY:-}" \
        --from-literal=webhook-secret="${WEBHOOK_SECRET:-}" \
        --from-literal=postgres-db="${POSTGRES_DB:-pyairtable}" \
        --from-literal=postgres-user="${POSTGRES_USER:-postgres}" \
        --from-literal=postgres-password="${POSTGRES_PASSWORD:-}" \
        --from-literal=redis-password="${REDIS_PASSWORD:-}" \
        --from-literal=gemini-api-key="${GEMINI_API_KEY:-}" \
        --from-literal=airtable-token="${AIRTABLE_TOKEN:-}" \
        --from-literal=airtable-base="${AIRTABLE_BASE:-}" \
        --from-literal=thinking-budget="${THINKING_BUDGET:-2000}" \
        --from-literal=cors-origins="${CORS_ORIGINS:-*}" \
        --from-literal=max-file-size="${MAX_FILE_SIZE:-10MB}" \
        --from-literal=allowed-extensions="${ALLOWED_EXTENSIONS:-pdf,doc,docx,txt,csv,xlsx,json,yaml}"
    
    print_success "Kubernetes secret created: $SECRETS_NAME"
}

# Create Kubernetes configmap
create_k8s_configmap() {
    print_header "Creating Kubernetes ConfigMap"
    
    if ! check_kubectl; then
        return 1
    fi
    
    local env_file=${1:-"$LOCAL_SECRETS_FILE"}
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Secrets file not found: $env_file"
        return 1
    fi
    
    # Load configuration
    load_secrets_from_file "$env_file"
    
    # Delete existing configmap if it exists  
    if kubectl get configmap "$CONFIG_NAME" -n "$NAMESPACE" &>/dev/null; then
        print_info "Deleting existing configmap: $CONFIG_NAME"
        kubectl delete configmap "$CONFIG_NAME" -n "$NAMESPACE"
    fi
    
    print_progress "Creating Kubernetes configmap: $CONFIG_NAME"
    
    # Create configmap with non-secret configuration
    kubectl create configmap "$CONFIG_NAME" \
        --namespace="$NAMESPACE" \
        --from-literal=environment="${ENVIRONMENT:-development}" \
        --from-literal=log-level="${LOG_LEVEL:-debug}" \
        --from-literal=node-env="${NODE_ENV:-development}" \
        --from-literal=enable-debug="${ENABLE_DEBUG:-true}" \
        --from-literal=enable-metrics="${ENABLE_METRICS:-true}" \
        --from-literal=enable-tracing="${ENABLE_TRACING:-true}" \
        --from-literal=show-cost-tracking="${SHOW_COST_TRACKING:-true}" \
        --from-literal=upload-dir="${UPLOAD_DIR:-/tmp/uploads}" \
        --from-literal=default-workflow-timeout="${DEFAULT_WORKFLOW_TIMEOUT:-300}" \
        --from-literal=max-workflow-retries="${MAX_WORKFLOW_RETRIES:-3}" \
        --from-literal=scheduler-check-interval="${SCHEDULER_CHECK_INTERVAL:-30}" \
        --from-literal=analytics-retention-days="${ANALYTICS_RETENTION_DAYS:-90}" \
        --from-literal=metrics-batch-size="${METRICS_BATCH_SIZE:-100}" \
        --from-literal=password-min-length="${PASSWORD_MIN_LENGTH:-8}" \
        --from-literal=password-hash-rounds="${PASSWORD_HASH_ROUNDS:-12}" \
        --from-literal=require-api-key="${REQUIRE_API_KEY:-true}" \
        --from-literal=saga-timeout-seconds="${SAGA_TIMEOUT_SECONDS:-3600}" \
        --from-literal=saga-retry-attempts="${SAGA_RETRY_ATTEMPTS:-3}" \
        --from-literal=saga-step-timeout-seconds="${SAGA_STEP_TIMEOUT_SECONDS:-300}" \
        --from-literal=use-redis-event-bus="${USE_REDIS_EVENT_BUS:-true}" \
        --from-literal=metrics-port="${METRICS_PORT:-9090}"
    
    print_success "Kubernetes configmap created: $CONFIG_NAME"
}

# List secrets in Kubernetes
list_k8s_secrets() {
    print_header "Kubernetes Secrets Status"
    
    if ! check_kubectl; then
        return 1
    fi
    
    echo "Secrets in namespace: $NAMESPACE"
    kubectl get secrets -n "$NAMESPACE" -o wide
    
    echo ""
    echo "ConfigMaps in namespace: $NAMESPACE"  
    kubectl get configmaps -n "$NAMESPACE" -o wide
    
    if kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo ""
        echo "Secret keys in $SECRETS_NAME:"
        kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' | sort
    fi
}

# Update specific secret
update_secret() {
    local secret_key="$1"
    local secret_value="$2"
    
    print_header "Updating Secret: $secret_key"
    
    if ! check_kubectl; then
        return 1
    fi
    
    if ! kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" &>/dev/null; then
        print_error "Secret $SECRETS_NAME does not exist"
        return 1
    fi
    
    # Update the secret
    kubectl patch secret "$SECRETS_NAME" -n "$NAMESPACE" \
        -p='{"data":{"'"$secret_key"'":"'"$(echo -n "$secret_value" | base64)"'"}}'
    
    print_success "Updated secret: $secret_key"
}

# Rotate secrets
rotate_secrets() {
    print_header "Rotating Secrets"
    
    local category=${1:-"all"}
    local backup_suffix
    backup_suffix=$(date +"%Y%m%d_%H%M%S")
    
    # Backup current secrets
    if [[ -f "$LOCAL_SECRETS_FILE" ]]; then
        cp "$LOCAL_SECRETS_FILE" "$LOCAL_SECRETS_FILE.backup.$backup_suffix"
        print_info "Backed up current secrets to: $LOCAL_SECRETS_FILE.backup.$backup_suffix"
    fi
    
    case $category in
        "auth")
            print_progress "Rotating authentication secrets..."
            update_secret "api-key" "$(generate_api_key)"
            update_secret "jwt-secret" "$(generate_jwt_secret)"
            update_secret "nextauth-secret" "$(generate_secure_string 32)"
            ;;
        "database")
            print_progress "Rotating database secrets..."
            update_secret "postgres-password" "$(generate_db_password)"
            update_secret "redis-password" "$(generate_db_password)"
            ;;
        "security")
            print_progress "Rotating security secrets..."
            update_secret "encryption-key" "$(generate_secure_string 32)"
            update_secret "webhook-secret" "$(generate_secure_string 24)"
            ;;
        "all")
            print_progress "Rotating all secrets..."
            rotate_secrets "auth"
            rotate_secrets "database"
            rotate_secrets "security"
            ;;
        *)
            print_error "Unknown category: $category"
            print_info "Available categories: auth, database, security, all"
            return 1
            ;;
    esac
    
    print_success "Secret rotation completed for: $category"
    print_warning "Services may need to be restarted to pick up new secrets"
}

# Validate secrets
validate_secrets() {
    print_header "Validating Secrets"
    
    local env_file=${1:-"$LOCAL_SECRETS_FILE"}
    local validation_errors=0
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Secrets file not found: $env_file"
        return 1
    fi
    
    # Load secrets
    load_secrets_from_file "$env_file"
    
    # Required secrets
    local required_secrets=(
        "API_KEY:API key"
        "JWT_SECRET:JWT secret" 
        "NEXTAUTH_SECRET:NextAuth secret"
        "POSTGRES_PASSWORD:PostgreSQL password"
        "REDIS_PASSWORD:Redis password"
    )
    
    # Validate required secrets
    for secret_info in "${required_secrets[@]}"; do
        IFS=':' read -r var_name description <<< "$secret_info"
        
        local var_value="${!var_name:-}"
        
        if [[ -z "$var_value" ]]; then
            print_error "Missing required secret: $description ($var_name)"
            validation_errors=$((validation_errors + 1))
        else
            print_success "Valid: $description"
        fi
    done
    
    # Validate secret formats
    if [[ -n "${API_KEY:-}" ]] && [[ ! "${API_KEY}" =~ ^pya_ ]]; then
        print_warning "API_KEY does not follow expected format (should start with 'pya_')"
    fi
    
    if [[ -n "${JWT_SECRET:-}" ]] && [[ ${#JWT_SECRET} -lt 32 ]]; then
        print_warning "JWT_SECRET is shorter than recommended (32+ characters)"
    fi
    
    # Optional but recommended secrets
    local optional_secrets=(
        "GEMINI_API_KEY:Gemini API key"
        "AIRTABLE_TOKEN:Airtable token"
        "AIRTABLE_BASE:Airtable base ID"
    )
    
    for secret_info in "${optional_secrets[@]}"; do
        IFS=':' read -r var_name description <<< "$secret_info"
        
        local var_value="${!var_name:-}"
        
        if [[ -z "$var_value" ]]; then
            print_warning "Optional secret not set: $description ($var_name)"
        else
            print_success "Valid: $description"
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        print_success "All required secrets are valid"
        return 0
    else
        print_error "Found $validation_errors validation errors"
        return 1
    fi
}

# Export secrets for external use
export_secrets() {
    print_header "Exporting Secrets"
    
    local format=${1:-"env"}
    local output_file=${2:-"/dev/stdout"}
    
    if ! check_kubectl; then
        return 1
    fi
    
    if ! kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" &>/dev/null; then
        print_error "Secret $SECRETS_NAME does not exist"
        return 1
    fi
    
    case $format in
        "env")
            print_progress "Exporting as environment variables..."
            {
                echo "# PyAirtable Secrets Export - $(date)"
                echo "# Source this file to load secrets: source <filename>"
                echo ""
                kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" -o json | \
                    jq -r '.data | to_entries[] | "export " + (.key | gsub("-"; "_") | ascii_upcase) + "=\"" + (.value | @base64d) + "\""'
            } > "$output_file"
            ;;
        "json")
            print_progress "Exporting as JSON..."
            kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" -o json | \
                jq '.data | with_entries(.value |= @base64d)' > "$output_file"
            ;;
        "yaml")
            print_progress "Exporting as YAML..."
            kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" -o yaml > "$output_file"
            ;;
        *)
            print_error "Unknown format: $format"
            print_info "Available formats: env, json, yaml"
            return 1
            ;;
    esac
    
    if [[ "$output_file" != "/dev/stdout" ]]; then
        print_success "Secrets exported to: $output_file"
        print_warning "Keep exported secrets secure and delete when no longer needed"
    fi
}

# Main function  
main() {
    local command=${1:-"help"}
    
    case $command in
        "template")
            create_secrets_template
            ;;
        "generate")
            create_secrets_template
            generate_dev_secrets
            ;;
        "apply")
            local env_file=${2:-"$LOCAL_SECRETS_FILE"}
            create_k8s_secret "$env_file"
            create_k8s_configmap "$env_file"
            ;;
        "list")
            list_k8s_secrets
            ;;
        "update")
            local key=${2:-""}
            local value=${3:-""}
            
            if [[ -z "$key" || -z "$value" ]]; then
                print_error "Usage: $0 update <key> <value>"
                exit 1
            fi
            
            update_secret "$key" "$value"
            ;;
        "rotate")
            local category=${2:-"all"}
            rotate_secrets "$category"
            ;;
        "validate")
            local env_file=${2:-"$LOCAL_SECRETS_FILE"}
            validate_secrets "$env_file"
            ;;
        "export")
            local format=${2:-"env"}
            local output_file=${3:-"/dev/stdout"}
            export_secrets "$format" "$output_file"
            ;;
        "help"|"-h"|"--help")
            echo "PyAirtable Secrets Manager"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  template                 Create secrets template file"
            echo "  generate                 Generate development secrets"
            echo "  apply [FILE]            Apply secrets to Kubernetes (default: .env.local)"
            echo "  list                     List Kubernetes secrets status"
            echo "  update KEY VALUE        Update specific secret"
            echo "  rotate [CATEGORY]       Rotate secrets (auth|database|security|all)"
            echo "  validate [FILE]         Validate secrets file"
            echo "  export [FORMAT] [FILE]  Export secrets (env|json|yaml)"
            echo "  help                     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 generate              # Generate dev secrets"
            echo "  $0 apply                 # Apply secrets to k8s"
            echo "  $0 update api-key \$key   # Update API key"
            echo "  $0 rotate auth           # Rotate auth secrets"
            echo "  $0 export env secrets.env # Export as env file"
            echo ""
            echo "Files:"
            echo "  .env.template           # Template with all variables"
            echo "  .env.local              # Local development secrets"
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"