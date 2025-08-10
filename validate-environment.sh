#!/bin/bash

# =============================================================================
# PyAirtable Environment Validation Script
# =============================================================================
# This script validates that all required environment variables are properly set
# Run before starting services to catch configuration issues early
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((VALIDATION_WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((VALIDATION_ERRORS++))
}

# Load environment variables
load_env() {
    if [ -f .env ]; then
        log_info "Loading environment from .env file"
        set -o allexport
        source .env
        set +o allexport
    else
        log_error ".env file not found! Copy .env.template to .env and configure it."
        exit 1
    fi
}

# Validate required variable
check_required() {
    local var_name="$1"
    local description="$2"
    local example_value="$3"
    
    if [ -z "${!var_name:-}" ]; then
        log_error "Missing required variable: $var_name ($description)"
        log_error "  Example: $var_name=$example_value"
        return 1
    fi
    
    # Check for placeholder values
    case "${!var_name}" in
        "your_actual_"*|"generate_secure_"*|"change_in_production"*|"replace_with_actual"*)
            log_error "Variable $var_name contains placeholder value: ${!var_name}"
            log_error "  Please replace with actual value"
            return 1
            ;;
    esac
    
    log_success "✓ $var_name is set"
    return 0
}

# Validate optional variable with warning
check_optional() {
    local var_name="$1"
    local description="$2"
    
    if [ -z "${!var_name:-}" ]; then
        log_warning "Optional variable not set: $var_name ($description)"
        return 1
    fi
    
    log_success "✓ $var_name is set"
    return 0
}

# Validate URL format
validate_url() {
    local var_name="$1"
    local url="${!var_name}"
    
    if [[ ! "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        log_error "Invalid URL format for $var_name: $url"
        return 1
    fi
    
    log_success "✓ $var_name URL format is valid"
    return 0
}

# Validate database connection string
validate_database_url() {
    local db_url="${DATABASE_URL}"
    
    if [[ ! "$db_url" =~ ^postgresql://.*@postgres:5432/.* ]]; then
        log_error "DATABASE_URL should use container name 'postgres' for internal networking"
        log_error "  Current: $db_url"
        log_error "  Expected format: postgresql://user:pass@postgres:5432/dbname"
        return 1
    fi
    
    # Check for SSL mode in production
    if [[ "${ENVIRONMENT:-development}" == "production" ]]; then
        if [[ ! "$db_url" =~ sslmode=require ]]; then
            log_warning "Production DATABASE_URL should include sslmode=require"
        fi
    fi
    
    # Check for connection timeout
    if [[ ! "$db_url" =~ connect_timeout= ]]; then
        log_warning "DATABASE_URL should include connect_timeout parameter"
    fi
    
    log_success "✓ DATABASE_URL uses correct container name and format"
    return 0
}

# Validate Redis connection string
validate_redis_url() {
    local redis_url="${REDIS_URL}"
    
    # Check for secure port (6380) instead of default (6379)
    if [[ ! "$redis_url" =~ ^redis://.*@redis:6380.* ]] && [[ ! "$redis_url" =~ ^redis://redis:6380.* ]]; then
        log_warning "REDIS_URL should use secure port 6380 instead of default 6379"
        log_warning "  Current: $redis_url"
        log_warning "  Recommended format: redis://:password@redis:6380"
    fi
    
    # Check for password authentication
    if [[ ! "$redis_url" =~ redis://:.+@redis ]]; then
        log_error "REDIS_URL should include password authentication"
        log_error "  Current: $redis_url"
        log_error "  Expected format: redis://:password@redis:6380"
        return 1
    fi
    
    log_success "✓ REDIS_URL uses correct container name and authentication"
    return 0
}

# Check Docker network connectivity
check_docker_network() {
    log_info "Checking Docker network configuration..."
    
    # Check if docker-compose.yml uses consistent network name
    if grep -q "pyairtable-network" docker-compose.yml; then
        log_success "✓ Docker Compose uses consistent network name"
    else
        log_warning "Docker Compose may not use consistent network name"
    fi
    
    # Check Redis configuration for security
    if grep -q "redis-server --requirepass" docker-compose.yml; then
        log_success "✓ Redis is configured with password authentication"
    else
        log_warning "Redis may not be configured with password authentication"
    fi
    
    # Check PostgreSQL security configuration
    if grep -q "scram-sha-256" docker-compose.yml; then
        log_success "✓ PostgreSQL is configured with secure authentication"
    else
        log_warning "PostgreSQL may not be configured with secure authentication"
    fi
}

# Validate service ports
validate_service_ports() {
    log_info "Validating service port configuration..."
    
    # Expected ports for services (updated mapping)
    declare -A expected_ports=(
        ["api-gateway"]="7000"
        ["mcp-server"]="7001"
        ["airtable-gateway"]="7002"
        ["llm-orchestrator"]="7003"
        ["automation-services"]="7006"
        ["platform-services"]="7007"
        ["saga-orchestrator"]="7008"
        ["frontend"]="3000"
        ["chat-ui"]="5173"
    )
    
    for service in "${!expected_ports[@]}"; do
        port="${expected_ports[$service]}"
        if grep -q "${service}:${port}" docker-compose.yml; then
            log_success "✓ Service $service configured for port $port"
        else
            log_warning "Service $service may not be configured for expected port $port"
        fi
    done
}

# Main validation function
main() {
    echo "============================================================================="
    echo "PyAirtable Environment Validation"
    echo "============================================================================="
    
    # Load environment
    load_env
    
    echo ""
    log_info "Validating required external API credentials..."
    
    # Critical external API credentials
    check_required "AIRTABLE_TOKEN" "Airtable Personal Access Token" "patXXXXXXXXXXXXXX.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    check_required "AIRTABLE_BASE" "Airtable Base ID" "appXXXXXXXXXXXXXX"
    check_required "GEMINI_API_KEY" "Google Gemini API Key" "AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
    
    echo ""
    log_info "Validating secure secrets..."
    
    # Internal secrets (enhanced validation)
    check_required "API_KEY" "Internal API key for service communication" "pya_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    check_required "JWT_SECRET" "JWT signing secret" "base64-encoded-secret"
    check_required "NEXTAUTH_SECRET" "NextAuth secret" "32-char-hex-secret"
    check_required "POSTGRES_PASSWORD" "PostgreSQL password" "secure-random-password"
    check_required "REDIS_PASSWORD" "Redis password" "secure-random-password"
    
    # Validate secret strength
    if [ ! -z "${API_KEY:-}" ]; then
        if [ ${#API_KEY} -lt 64 ]; then
            log_warning "API_KEY length (${#API_KEY}) is below recommended 64 characters"
        else
            log_success "✓ API_KEY length meets security standards"
        fi
    fi
    
    if [ ! -z "${JWT_SECRET:-}" ]; then
        if [ ${#JWT_SECRET} -lt 32 ]; then
            log_warning "JWT_SECRET length (${#JWT_SECRET}) is below recommended 32 characters"
        else
            log_success "✓ JWT_SECRET length meets security standards"
        fi
    fi
    
    if [ ! -z "${POSTGRES_PASSWORD:-}" ]; then
        if [ ${#POSTGRES_PASSWORD} -lt 32 ]; then
            log_warning "POSTGRES_PASSWORD length (${#POSTGRES_PASSWORD}) is below recommended 32 characters for production"
        else
            log_success "✓ POSTGRES_PASSWORD length meets security standards"
        fi
    fi
    
    echo ""
    log_info "Validating environment configuration..."
    
    # Basic configuration
    check_required "ENVIRONMENT" "Environment name" "development"
    check_required "LOG_LEVEL" "Logging level" "DEBUG"
    check_required "POSTGRES_DB" "PostgreSQL database name" "pyairtable"
    check_required "POSTGRES_USER" "PostgreSQL username" "postgres"
    
    echo ""
    log_info "Validating service URLs..."
    
    # Service URLs (updated ports)
    check_required "AIRTABLE_GATEWAY_URL" "Airtable Gateway URL" "http://airtable-gateway:7002"
    check_required "MCP_SERVER_URL" "MCP Server URL" "http://mcp-server:7001"
    check_required "LLM_ORCHESTRATOR_URL" "LLM Orchestrator URL" "http://llm-orchestrator:7003"
    check_required "API_GATEWAY_URL" "API Gateway URL" "http://api-gateway:7000"
    
    # Validate URL formats for internal services
    for url_var in AIRTABLE_GATEWAY_URL MCP_SERVER_URL LLM_ORCHESTRATOR_URL API_GATEWAY_URL; do
        if [ ! -z "${!url_var:-}" ]; then
            validate_url "$url_var"
        fi
    done
    
    echo ""
    log_info "Validating database connections..."
    
    # Database connections
    check_required "DATABASE_URL" "PostgreSQL connection string" "postgresql://user:pass@postgres:5432/db"
    check_required "REDIS_URL" "Redis connection string" "redis://:pass@redis:6379"
    
    validate_database_url
    validate_redis_url
    
    echo ""
    log_info "Validating CORS configuration..."
    
    # CORS settings (enhanced validation)
    check_required "CORS_ORIGINS" "CORS allowed origins" "http://localhost:3000,http://localhost:7000"
    check_required "CORS_METHODS" "CORS allowed methods" "GET,POST,PUT,DELETE,OPTIONS"
    check_required "CORS_HEADERS" "CORS allowed headers" "Content-Type,Authorization,X-API-Key"
    check_optional "CORS_CREDENTIALS" "CORS credentials setting"
    check_optional "CORS_MAX_AGE" "CORS max age setting"
    
    echo ""
    log_info "Validating Docker configuration..."
    
    check_docker_network
    validate_service_ports
    
    echo ""
    log_info "Validating optional features..."
    
    # Security configuration validation
    check_optional "JWT_ALGORITHM" "JWT signing algorithm"
    check_optional "JWT_EXPIRES_IN" "JWT token expiration time"
    check_optional "SESSION_TIMEOUT" "Session timeout setting"
    check_optional "PASSWORD_HASH_ROUNDS" "Password hashing rounds"
    check_optional "USE_REDIS_SESSIONS" "Redis session storage"
    
    # Validate password security settings
    if [ ! -z "${PASSWORD_HASH_ROUNDS:-}" ]; then
        if [ "${PASSWORD_HASH_ROUNDS}" -lt 10 ]; then
            log_warning "PASSWORD_HASH_ROUNDS ($PASSWORD_HASH_ROUNDS) is below recommended minimum of 10"
        elif [ "${PASSWORD_HASH_ROUNDS}" -ge 10 ] && [ "${PASSWORD_HASH_ROUNDS}" -lt 12 ]; then
            log_info "PASSWORD_HASH_ROUNDS ($PASSWORD_HASH_ROUNDS) is acceptable but consider 12+ for production"
        else
            log_success "✓ PASSWORD_HASH_ROUNDS ($PASSWORD_HASH_ROUNDS) meets security standards"
        fi
    fi
    
    # Optional configuration
    check_optional "THINKING_BUDGET" "LLM thinking budget"
    check_optional "MAX_FILE_SIZE" "Maximum file upload size"
    check_optional "SENTRY_DSN" "Sentry error reporting DSN"
    
    echo ""
    echo "============================================================================="
    echo "Validation Summary"
    echo "============================================================================="
    
    if [ $VALIDATION_ERRORS -eq 0 ] && [ $VALIDATION_WARNINGS -eq 0 ]; then
        log_success "✅ All environment variables are properly configured!"
        log_info "You can now start the services with: docker-compose up -d"
    elif [ $VALIDATION_ERRORS -eq 0 ]; then
        log_success "✅ Required environment variables are configured"
        log_warning "⚠️  Found $VALIDATION_WARNINGS warnings - consider addressing them"
        log_info "You can start the services, but some features may not work optimally"
    else
        log_error "❌ Found $VALIDATION_ERRORS critical errors and $VALIDATION_WARNINGS warnings"
        log_error "Please fix all errors before starting services"
        echo ""
        log_info "Quick fixes:"
        log_info "1. Copy .env.template to .env: cp .env.template .env"
        log_info "2. Edit .env and replace placeholder values with your actual credentials"
        log_info "3. Generate secure secrets: ./generate-secure-env.sh"
        log_info "4. Re-run validation: ./validate-environment.sh"
        exit 1
    fi
    
    echo ""
    log_info "Environment validation completed!"
}

# Run main function
main "$@"