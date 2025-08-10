#!/bin/bash

# =============================================================================
# PyAirtable Secure Environment Generator
# =============================================================================
# This script generates secure environment variables for PyAirtable services
# It creates strong random passwords and API keys for all services
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are available
check_dependencies() {
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 is required but not installed"
        exit 1
    fi
}

# Generate secure random string (256-bit minimum)
generate_secure_string() {
    local length="$1"
    if [ "$length" -lt 32 ]; then
        log_warning "String length $length is below recommended 256-bit (32 bytes). Using 32 bytes."
        length=32
    fi
    openssl rand -hex "$length"
}

# Generate base64 encoded secret (256-bit minimum)
generate_base64_secret() {
    local length="$1"
    if [ "$length" -lt 32 ]; then
        log_warning "Secret length $length is below recommended 256-bit (32 bytes). Using 32 bytes."
        length=32
    fi
    openssl rand -base64 "$length"
}

# Generate API key with prefix (256-bit)
generate_api_key() {
    local prefix="$1"
    local key=$(openssl rand -hex 32)  # 256-bit key
    echo "${prefix}_${key}"
}

# Backup existing .env file
backup_env_file() {
    if [ -f .env ]; then
        local backup_name=".env.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing .env file to $backup_name"
        cp .env "$backup_name"
    fi
}

# Create .env file from template with generated secrets
generate_env_file() {
    log_info "Generating secure environment variables..."
    
    # Generate secure secrets (all 256-bit or higher)
    local api_key=$(generate_api_key "pya")
    local jwt_secret=$(generate_base64_secret 32)
    local nextauth_secret=$(generate_secure_string 32)
    local postgres_password=$(generate_secure_string 32)  # 256-bit
    local redis_password=$(generate_secure_string 16)     # 128-bit (Redis recommendation)
    
    # Current timestamp for documentation
    local timestamp=$(date '+%a %b %d %H:%M:%S %Z %Y')
    
    # Create .env file from template
    cat > .env << EOF
# PyAirtable Compose - Local Development Environment
# Generated on $timestamp
# 
# IMPORTANT: Replace AIRTABLE_TOKEN, AIRTABLE_BASE, and GEMINI_API_KEY with your actual credentials

# =============================================================================
# EXTERNAL API CREDENTIALS (REPLACE WITH YOUR ACTUAL CREDENTIALS)
# =============================================================================

# Airtable Configuration
# Get your Personal Access Token from: https://airtable.com/developers/web/api/authentication
AIRTABLE_TOKEN=your_actual_airtable_token_here
# Get your Base ID from your Airtable base URL or API documentation
AIRTABLE_BASE=your_actual_base_id_here

# Google Gemini API Key
# Get your API key from: https://makersuite.google.com/app/apikey
GEMINI_API_KEY=your_actual_gemini_api_key_here

# =============================================================================
# SECURE GENERATED SECRETS (AUTOMATICALLY GENERATED - DO NOT MODIFY)
# =============================================================================

# Internal API Key for service-to-service communication
API_KEY=$api_key

# JWT Secret for token signing (base64 encoded)
JWT_SECRET=$jwt_secret

# NextAuth Secret for authentication
NEXTAUTH_SECRET=$nextauth_secret

# Database passwords (generated securely)
POSTGRES_PASSWORD=$postgres_password
REDIS_PASSWORD=$redis_password

# =============================================================================
# ENVIRONMENT CONFIGURATION
# =============================================================================

# Environment (development|staging|production)
ENVIRONMENT=development
LOG_LEVEL=DEBUG
NODE_ENV=development

# Database configuration
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres

# Application settings
THINKING_BUDGET=50000
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx,json,yaml

# CORS Configuration
CORS_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:5174,http://localhost:7000,http://localhost:8000,http://localhost:8080
CORS_METHODS=GET,POST,PUT,DELETE,OPTIONS
CORS_HEADERS=Content-Type,Authorization,X-API-Key
CORS_CREDENTIALS=true
CORS_MAX_AGE=86400

# Development features
ENABLE_DEBUG=true
ENABLE_METRICS=true
SHOW_COST_TRACKING=true

# Security settings
REQUIRE_API_KEY=true
REQUIRE_HTTPS=false

# =============================================================================
# SERVICE URLs (INTERNAL DOCKER NETWORKING - USE CONTAINER NAMES)
# =============================================================================

# Core Service URLs (internal networking)
AIRTABLE_GATEWAY_URL=http://airtable-gateway:8002
MCP_SERVER_URL=http://mcp-server:8001
LLM_ORCHESTRATOR_URL=http://llm-orchestrator:8003
API_GATEWAY_URL=http://api-gateway:8000
FRONTEND_URL=http://frontend:3000

# Platform Services
PLATFORM_SERVICES_URL=http://platform-services:8007
AUTOMATION_SERVICES_URL=http://automation-services:8006
SAGA_ORCHESTRATOR_URL=http://saga-orchestrator:8008

# Service-specific URLs for internal communication
AUTH_SERVICE_URL=http://platform-services:8007
USER_SERVICE_URL=http://platform-services:8007
PERMISSION_SERVICE_URL=http://platform-services:8007
NOTIFICATION_SERVICE_URL=http://automation-services:8006
WEBHOOK_SERVICE_URL=http://automation-services:8006
DATA_SYNC_SERVICE_URL=http://automation-services:8006
SCHEMA_SERVICE_URL=http://platform-services:8007
AIRTABLE_CONNECTOR_URL=http://airtable-gateway:8002

# External URLs (for frontend and browser access)
NEXT_PUBLIC_API_URL=http://localhost:7000
NEXT_PUBLIC_API_GATEWAY_URL=http://localhost:7000
NEXT_PUBLIC_WS_URL=ws://localhost:7000/ws

# =============================================================================
# DATABASE CONNECTION STRINGS (INTERNAL DOCKER NETWORKING)
# =============================================================================

# PostgreSQL (use container name 'postgres' for internal networking)
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}

# Redis (use container name 'redis' for internal networking)
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6379
REDIS_URL_NO_AUTH=redis://redis:6379

# Service-specific database configurations
MCP_SERVER_HTTP_URL=http://mcp-server:8001
USE_HTTP_MCP=true
USE_REDIS_SESSIONS=true

# =============================================================================
# SAGA ORCHESTRATOR CONFIGURATION
# =============================================================================
SAGA_TIMEOUT_SECONDS=3600
SAGA_RETRY_ATTEMPTS=3
SAGA_STEP_TIMEOUT_SECONDS=300

# =============================================================================
# AUTOMATION SERVICES CONFIGURATION
# =============================================================================
DEFAULT_WORKFLOW_TIMEOUT=300
MAX_WORKFLOW_RETRIES=3
SCHEDULER_CHECK_INTERVAL=30
UPLOAD_DIR=/tmp/uploads

# =============================================================================
# ANALYTICS & MONITORING
# =============================================================================
ANALYTICS_RETENTION_DAYS=90
METRICS_BATCH_SIZE=100
PASSWORD_MIN_LENGTH=8
PASSWORD_HASH_ROUNDS=12
JWT_ALGORITHM=HS256
JWT_EXPIRES_IN=24h
SESSION_TIMEOUT=86400
USE_REDIS_SESSIONS=true
REDIS_SESSION_TIMEOUT=86400
ENABLE_AUDIT_LOGGING=true

# Sentry Configuration (optional - for error monitoring)
NEXT_PUBLIC_SENTRY_DSN=https://your_sentry_dsn_here@sentry.io/project_id
NEXT_PUBLIC_APP_ENV=development
NEXT_PUBLIC_APP_VERSION=1.0.0

EOF

    log_success "Generated .env file with secure secrets"
    
    # Show generated secrets (masked for security)
    echo ""
    log_info "Generated secure secrets:"
    echo "  API_KEY: ${api_key:0:10}..."
    echo "  JWT_SECRET: ${jwt_secret:0:10}..."
    echo "  NEXTAUTH_SECRET: ${nextauth_secret:0:10}..."
    echo "  POSTGRES_PASSWORD: ${postgres_password:0:8}..."
    echo "  REDIS_PASSWORD: ${redis_password:0:8}..."
    
    echo ""
    log_warning "IMPORTANT: You still need to configure external API credentials:"
    log_warning "  1. Set AIRTABLE_TOKEN with your Airtable Personal Access Token"
    log_warning "  2. Set AIRTABLE_BASE with your Airtable Base ID"
    log_warning "  3. Set GEMINI_API_KEY with your Google Gemini API key"
}

# Generate production environment
generate_production_env() {
    log_info "Generating production environment configuration..."
    
    # Generate secure secrets for production (all 256-bit or higher)
    local api_key=$(generate_api_key "pya")
    local jwt_secret=$(generate_base64_secret 32)
    local nextauth_secret=$(generate_secure_string 32)
    local postgres_password=$(generate_secure_string 32)  # 256-bit
    local redis_password=$(generate_secure_string 16)     # 128-bit
    
    cat > .env.production << EOF
# PyAirtable Production Environment Configuration
# CRITICAL: This file contains production credentials - handle with extreme care

# =============================================================================
# EXTERNAL API CREDENTIALS (PRODUCTION)
# =============================================================================

# Airtable Production Credentials
AIRTABLE_TOKEN=your_actual_production_airtable_token_here
AIRTABLE_BASE=your_actual_production_base_id_here

# Google Gemini API Key (Production)
GEMINI_API_KEY=your_actual_production_gemini_api_key_here

# =============================================================================
# PRODUCTION SECURE SECRETS
# =============================================================================

# Internal API Key for service-to-service communication
API_KEY=$api_key

# JWT Secret for token signing (base64 encoded)
JWT_SECRET=$jwt_secret

# NextAuth Secret for authentication
NEXTAUTH_SECRET=$nextauth_secret

# Database passwords (production secure)
POSTGRES_PASSWORD=$postgres_password
REDIS_PASSWORD=$redis_password

# =============================================================================
# PRODUCTION CONFIGURATION
# =============================================================================

# Environment
ENVIRONMENT=production
LOG_LEVEL=INFO
NODE_ENV=production

# Database configuration
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres

# Application settings
THINKING_BUDGET=50000
CORS_ORIGINS=https://yourdomain.com,https://api.yourdomain.com
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx,json,yaml

# Production features
ENABLE_DEBUG=false
ENABLE_METRICS=true
SHOW_COST_TRACKING=true

# Security settings (production hardened)
REQUIRE_API_KEY=true
REQUIRE_HTTPS=true

# Service URLs (production)
AIRTABLE_GATEWAY_URL=https://airtable-gateway.yourdomain.com
MCP_SERVER_URL=https://mcp-server.yourdomain.com
LLM_ORCHESTRATOR_URL=https://llm-orchestrator.yourdomain.com
API_GATEWAY_URL=https://api.yourdomain.com
FRONTEND_URL=https://yourdomain.com

# Database connection strings (production - SSL required)
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}?sslmode=require&connect_timeout=30
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6380/0

# Additional security settings
USE_REDIS_SESSIONS=true
REDIS_SESSION_TIMEOUT=3600
ENABLE_AUDIT_LOGGING=true
ANALYTICS_RETENTION_DAYS=365
METRICS_BATCH_SIZE=1000
PASSWORD_HASH_ROUNDS=14
JWT_ALGORITHM=HS256
JWT_EXPIRES_IN=1h
SESSION_TIMEOUT=3600

EOF

    log_success "Generated .env.production with secure secrets"
}

# Generate staging environment
generate_staging_env() {
    log_info "Generating staging environment configuration..."
    
    # Generate secure secrets for staging (all 256-bit or higher)
    local api_key=$(generate_api_key "pya")
    local jwt_secret=$(generate_base64_secret 32)
    local nextauth_secret=$(generate_secure_string 32)
    local postgres_password=$(generate_secure_string 32)  # 256-bit
    local redis_password=$(generate_secure_string 16)     # 128-bit
    
    cat > .env.staging << EOF
# PyAirtable Staging Environment Configuration

# =============================================================================
# EXTERNAL API CREDENTIALS (STAGING)
# =============================================================================

# Airtable Staging Credentials
AIRTABLE_TOKEN=your_actual_staging_airtable_token_here
AIRTABLE_BASE=your_actual_staging_base_id_here

# Google Gemini API Key (Staging)
GEMINI_API_KEY=your_actual_staging_gemini_api_key_here

# =============================================================================
# STAGING SECURE SECRETS
# =============================================================================

# Internal API Key for service-to-service communication
API_KEY=$api_key

# JWT Secret for token signing (base64 encoded)
JWT_SECRET=$jwt_secret

# NextAuth Secret for authentication
NEXTAUTH_SECRET=$nextauth_secret

# Database passwords (staging secure)
POSTGRES_PASSWORD=$postgres_password
REDIS_PASSWORD=$redis_password

# =============================================================================
# STAGING CONFIGURATION
# =============================================================================

# Environment
ENVIRONMENT=staging
LOG_LEVEL=DEBUG
NODE_ENV=production

# Database configuration
POSTGRES_DB=pyairtable_staging
POSTGRES_USER=postgres

# Application settings
THINKING_BUDGET=50000
CORS_ORIGINS=https://staging.yourdomain.com,https://staging-api.yourdomain.com
MAX_FILE_SIZE=10MB
ALLOWED_EXTENSIONS=pdf,doc,docx,txt,csv,xlsx,json,yaml

# Staging features
ENABLE_DEBUG=true
ENABLE_METRICS=true
SHOW_COST_TRACKING=true

# Security settings (staging)
REQUIRE_API_KEY=true
REQUIRE_HTTPS=true

# Service URLs (staging)
AIRTABLE_GATEWAY_URL=https://staging-airtable-gateway.yourdomain.com
MCP_SERVER_URL=https://staging-mcp-server.yourdomain.com
LLM_ORCHESTRATOR_URL=https://staging-llm-orchestrator.yourdomain.com
API_GATEWAY_URL=https://staging-api.yourdomain.com
FRONTEND_URL=https://staging.yourdomain.com

# Database connection strings (staging - SSL preferred)
DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}?sslmode=prefer&connect_timeout=30
REDIS_URL=redis://:\${REDIS_PASSWORD}@redis:6380/1

# Additional security settings
USE_REDIS_SESSIONS=true
REDIS_SESSION_TIMEOUT=7200
ENABLE_AUDIT_LOGGING=true
ANALYTICS_RETENTION_DAYS=180
METRICS_BATCH_SIZE=500
PASSWORD_HASH_ROUNDS=12
JWT_ALGORITHM=HS256
JWT_EXPIRES_IN=2h
SESSION_TIMEOUT=7200

EOF

    log_success "Generated .env.staging with secure secrets"
}

# Main function
main() {
    echo "============================================================================="
    echo "PyAirtable Secure Environment Generator"
    echo "============================================================================="
    
    check_dependencies
    
    # Change to project directory if script is run from elsewhere
    cd "$(dirname "$0")"
    
    # Backup existing .env file
    backup_env_file
    
    # Generate environment files
    generate_env_file
    
    if [ "${1:-}" == "--all" ]; then
        generate_production_env
        generate_staging_env
        log_info "Generated all environment files: .env, .env.production, .env.staging"
    fi
    
    echo ""
    echo "============================================================================="
    echo "Next Steps"
    echo "============================================================================="
    
    log_info "1. Edit .env and replace placeholder values with your actual API credentials:"
    log_info "   - AIRTABLE_TOKEN: Get from https://airtable.com/developers/web/api/authentication"
    log_info "   - AIRTABLE_BASE: Get from your Airtable base URL"
    log_info "   - GEMINI_API_KEY: Get from https://makersuite.google.com/app/apikey"
    echo ""
    log_info "2. Validate your environment configuration:"
    log_info "   ./validate-environment.sh"
    echo ""
    log_info "3. Start the services:"
    log_info "   docker-compose up -d"
    echo ""
    log_warning "SECURITY: Never commit actual credentials to version control!"
    log_warning "Add .env files to your .gitignore if not already present"
    
    echo ""
    log_success "Environment generation completed!"
}

# Run main function
main "$@"