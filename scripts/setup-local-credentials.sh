#!/bin/bash

# PyAirtable - Automated Local Credential Setup using GitHub CLI
# This script fetches credentials from GitHub Secrets for local development

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get GitHub secret
get_github_secret() {
    local secret_name="$1"
    local fallback_message="$2"
    
    if command_exists gh; then
        local secret_value
        secret_value=$(gh secret list --json name,value | jq -r ".[] | select(.name==\"$secret_name\") | .value" 2>/dev/null)
        
        if [ -n "$secret_value" ] && [ "$secret_value" != "null" ]; then
            echo "$secret_value"
            return 0
        fi
    fi
    
    echo "$fallback_message"
    return 1
}

# Function to generate secure credential
generate_secure_credential() {
    local length="$1"
    python3 -c "import secrets; print(secrets.token_urlsafe($length))"
}

# Function to setup environment file
setup_environment_file() {
    print_info "Setting up local environment file with GitHub Secrets integration..."
    
    # Backup existing .env if it exists
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"
        print_info "Backed up existing .env file"
    fi
    
    # Create new .env file with GitHub Secrets integration
    cat > "$ENV_FILE" << 'EOF'
# PyAirtable Services Environment Configuration
# Generated automatically with GitHub Secrets integration
# Generated on: $(date)

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

# Internal API Key for service-to-service communication
# Auto-generated or fetched from GitHub Secrets
API_KEY=${PYAIRTABLE_API_KEY}

# Airtable Personal Access Token
# Fetched from GitHub Secrets
AIRTABLE_TOKEN=${AIRTABLE_TOKEN}

# Airtable Base ID for testing
# Fetched from GitHub Secrets
AIRTABLE_BASE=${AIRTABLE_BASE}

# Google Gemini API Key
# Fetched from GitHub Secrets
GEMINI_API_KEY=${GEMINI_API_KEY}

# JWT Secret for token signing
# Auto-generated or fetched from GitHub Secrets
JWT_SECRET=${JWT_SECRET}

# NextAuth Secret for session management
# Auto-generated or fetched from GitHub Secrets
NEXTAUTH_SECRET=${NEXTAUTH_SECRET}

# Database passwords
# Auto-generated or fetched from GitHub Secrets
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

# =============================================================================
# SERVICE CONFIGURATION
# =============================================================================

# Environment
ENVIRONMENT=development

# Service URLs (for inter-service communication)
AIRTABLE_GATEWAY_URL=http://airtable-gateway:8002
MCP_SERVER_URL=http://mcp-server:8001
LLM_ORCHESTRATOR_URL=http://llm-orchestrator:8003
API_GATEWAY_URL=http://api-gateway:8000

# =============================================================================
# CORS CONFIGURATION
# =============================================================================

# Allowed origins for CORS
CORS_ORIGINS=http://localhost:3000,http://localhost:8000,http://localhost:8080

# Additional CORS settings
CORS_METHODS=GET,POST,PUT,DELETE,PATCH,OPTIONS
CORS_HEADERS=Content-Type,Authorization,X-API-Key,X-Request-ID
CORS_CREDENTIALS=true
CORS_MAX_AGE=86400

# =============================================================================
# SECURITY HARDENING
# =============================================================================

# Require HTTPS
REQUIRE_HTTPS=false

# Rate limiting
DEFAULT_RATE_LIMIT=60/minute
BURST_RATE_LIMIT=120/minute

# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

# PostgreSQL connection
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=pyairtable
POSTGRES_USER=pyairtable

# Redis connection
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_DB=0

# =============================================================================
# MONITORING & LOGGING
# =============================================================================

# Log level
LOG_LEVEL=INFO

# Log format
LOG_FORMAT=json

# Metrics
METRICS_ENABLED=true
METRICS_PORT=9090

# =============================================================================
# SERVICE-SPECIFIC CONFIGURATION
# =============================================================================

# MCP Server
MCP_SERVER_NAME=airtable-mcp
MCP_SERVER_VERSION=1.0.0
MCP_SERVER_MODE=http
MCP_SERVER_PORT=8001

# Airtable Gateway
AIRTABLE_GATEWAY_PORT=8002

# LLM Orchestrator
LLM_ORCHESTRATOR_PORT=8003
THINKING_BUDGET=50000

# API Gateway
API_GATEWAY_PORT=8000

# API Key requirement
REQUIRE_API_KEY=false

# =============================================================================
# DEVELOPMENT ONLY
# =============================================================================

# Frontend configuration
NODE_ENV=development
ENABLE_DEBUG=true
SHOW_COST_TRACKING=true

# File processing
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx
UPLOAD_DIR=/tmp/uploads

# Workflow settings
DEFAULT_WORKFLOW_TIMEOUT=300
MAX_WORKFLOW_RETRIES=3
SCHEDULER_CHECK_INTERVAL=30

# Auth settings
PASSWORD_MIN_LENGTH=8
PASSWORD_HASH_ROUNDS=12

# Analytics settings
ANALYTICS_RETENTION_DAYS=90
METRICS_BATCH_SIZE=100
EOF

    print_status "Environment template created"
}

# Function to fetch and set credentials
fetch_and_set_credentials() {
    print_info "Fetching credentials from GitHub Secrets..."
    
    # Prepare environment variables
    declare -A credentials
    
    # Try to fetch from GitHub Secrets, generate if not available
    if command_exists gh && gh auth status &>/dev/null; then
        print_info "GitHub CLI authenticated, fetching secrets..."
        
        # Fetch existing secrets
        credentials[PYAIRTABLE_API_KEY]=$(get_github_secret "PYAIRTABLE_API_KEY" "")
        credentials[AIRTABLE_TOKEN]=$(get_github_secret "AIRTABLE_TOKEN" "")
        credentials[AIRTABLE_BASE]=$(get_github_secret "AIRTABLE_BASE" "")
        credentials[GEMINI_API_KEY]=$(get_github_secret "GEMINI_API_KEY" "")
        credentials[JWT_SECRET]=$(get_github_secret "JWT_SECRET" "")
        credentials[NEXTAUTH_SECRET]=$(get_github_secret "NEXTAUTH_SECRET" "")
        credentials[POSTGRES_PASSWORD]=$(get_github_secret "POSTGRES_PASSWORD" "")
        credentials[REDIS_PASSWORD]=$(get_github_secret "REDIS_PASSWORD" "")
        
    else
        print_warning "GitHub CLI not available or not authenticated"
        print_info "Installing GitHub CLI: https://cli.github.com/"
    fi
    
    # Generate missing credentials
    if [ -z "${credentials[PYAIRTABLE_API_KEY]}" ]; then
        credentials[PYAIRTABLE_API_KEY]=$(generate_secure_credential 48)
        print_info "Generated secure API key"
    fi
    
    if [ -z "${credentials[JWT_SECRET]}" ]; then
        credentials[JWT_SECRET]=$(generate_secure_credential 64)
        print_info "Generated secure JWT secret"
    fi
    
    if [ -z "${credentials[NEXTAUTH_SECRET]}" ]; then
        credentials[NEXTAUTH_SECRET]=$(generate_secure_credential 64)
        print_info "Generated secure NextAuth secret"
    fi
    
    if [ -z "${credentials[POSTGRES_PASSWORD]}" ]; then
        credentials[POSTGRES_PASSWORD]=$(generate_secure_credential 32)
        print_info "Generated secure PostgreSQL password"
    fi
    
    if [ -z "${credentials[REDIS_PASSWORD]}" ]; then
        credentials[REDIS_PASSWORD]=$(generate_secure_credential 32)
        print_info "Generated secure Redis password"
    fi
    
    # Export environment variables for current session
    for key in "${!credentials[@]}"; do
        if [ -n "${credentials[$key]}" ]; then
            export "$key"="${credentials[$key]}"
        fi
    done
    
    # Create a local environment file with actual values
    envsubst < "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
    
    print_status "Credentials configured successfully"
}

# Function to validate setup
validate_setup() {
    print_info "Validating credential setup..."
    
    local missing_credentials=()
    
    # Check for missing external API credentials
    if ! grep -q "^AIRTABLE_TOKEN=" "$ENV_FILE" || grep -q "REPLACE_WITH" "$ENV_FILE"; then
        missing_credentials+=("AIRTABLE_TOKEN")
    fi
    
    if ! grep -q "^GEMINI_API_KEY=" "$ENV_FILE" || grep -q "REPLACE_WITH" "$ENV_FILE"; then
        missing_credentials+=("GEMINI_API_KEY")
    fi
    
    if ! grep -q "^AIRTABLE_BASE=" "$ENV_FILE" || grep -q "REPLACE_WITH" "$ENV_FILE"; then
        missing_credentials+=("AIRTABLE_BASE")
    fi
    
    if [ ${#missing_credentials[@]} -gt 0 ]; then
        print_warning "Missing external API credentials:"
        for cred in "${missing_credentials[@]}"; do
            echo "  - $cred"
        done
        echo ""
        echo "Please set these as GitHub repository secrets or manually in .env file"
        echo "See CREDENTIALS_GUIDE.md for detailed instructions"
        return 1
    fi
    
    print_status "All credentials configured"
    return 0
}

# Function to show setup summary
show_setup_summary() {
    echo ""
    echo -e "${GREEN}🎉 Credential Setup Complete!${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Verify credentials in .env file"
    echo "2. Start services with: ./start.sh"
    echo "3. Test the system with: ./test.sh"
    echo ""
    echo -e "${BLUE}Files Created/Updated:${NC}"
    echo "• $ENV_FILE"
    if [ -f "$ENV_FILE.backup.*" ]; then
        echo "• $ENV_FILE.backup.* (backup of previous version)"
    fi
    echo ""
    echo -e "${YELLOW}Security Notes:${NC}"
    echo "• Generated credentials are cryptographically secure"
    echo "• External API keys must be obtained manually"
    echo "• Never commit actual credentials to version control"
    echo "• Use GitHub Secrets for CI/CD pipelines"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}🔐 PyAirtable Credential Setup${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo ""
    
    # Check prerequisites
    if ! command_exists python3; then
        print_error "Python 3 is required for credential generation"
        exit 1
    fi
    
    if command_exists gh; then
        if gh auth status &>/dev/null; then
            print_status "GitHub CLI authenticated"
        else
            print_warning "GitHub CLI not authenticated"
            print_info "Run: gh auth login"
        fi
    else
        print_warning "GitHub CLI not installed"
        print_info "Install with: brew install gh (macOS) or https://cli.github.com/"
    fi
    
    # Setup environment
    setup_environment_file
    fetch_and_set_credentials
    
    # Validate setup
    if validate_setup; then
        show_setup_summary
        exit 0
    else
        print_error "Setup completed with warnings - manual configuration required"
        show_setup_summary
        exit 1
    fi
}

# Run main function
main "$@"