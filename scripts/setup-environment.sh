#!/bin/bash

# PyAirtable Platform Environment Setup Script
# Automates environment configuration for deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV_FILE=".env"
ENV_EXAMPLE=".env.example"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "success")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "error")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "info")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Function to generate secure random string
generate_secret() {
    local length=${1:-32}
    python3 -c "import secrets; print(secrets.token_urlsafe($length))" 2>/dev/null || \
    openssl rand -base64 $length 2>/dev/null | tr -d "=+/" | cut -c1-$length || \
    head -c $length /dev/urandom | base64 | tr -d "=+/" | cut -c1-$length
}

# Function to prompt for input with default
prompt_with_default() {
    local prompt=$1
    local default=$2
    local secret=${3:-false}
    local result
    
    if [ "$secret" = true ]; then
        read -s -p "$prompt [$default]: " result
        echo ""
    else
        read -p "$prompt [$default]: " result
    fi
    
    echo "${result:-$default}"
}

# Function to validate email format
validate_email() {
    local email=$1
    if [[ $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate URL format
validate_url() {
    local url=$1
    if [[ $url =~ ^https?://.*$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if required tools are installed
check_dependencies() {
    print_status "info" "Checking dependencies..."
    
    local missing_deps=()
    
    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        print_status "success" "All dependencies are installed"
        return 0
    else
        print_status "error" "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install the missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                "python3")
                    echo "  - Python 3: https://python.org/downloads/"
                    ;;
                "docker")
                    echo "  - Docker: https://docs.docker.com/get-docker/"
                    ;;
                "docker-compose")
                    echo "  - Docker Compose: https://docs.docker.com/compose/install/"
                    ;;
                "jq")
                    echo "  - jq: https://stedolan.github.io/jq/download/"
                    ;;
                "curl")
                    echo "  - curl: Usually pre-installed, check your package manager"
                    ;;
            esac
        done
        return 1
    fi
}

# Function to create environment file
create_environment_file() {
    print_status "info" "Setting up environment configuration..."
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Check if .env already exists
    if [ -f "$ENV_FILE" ]; then
        print_status "warning" "Environment file already exists"
        read -p "Do you want to overwrite it? (y/N): " overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            print_status "info" "Keeping existing environment file"
            return 0
        fi
    fi
    
    # Copy from example if it exists
    if [ -f "$ENV_EXAMPLE" ]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        print_status "success" "Created $ENV_FILE from template"
    else
        print_status "warning" "No .env.example found, creating from scratch"
        touch "$ENV_FILE"
    fi
    
    # Interactive configuration
    echo ""
    echo "🔧 Environment Configuration"
    echo "============================"
    echo ""
    
    # Security configuration
    echo "Security Configuration:"
    echo "----------------------"
    
    # Generate API key
    local api_key=$(generate_secret 48)
    echo "API_KEY=$api_key" >> "$ENV_FILE"
    print_status "success" "Generated API key"
    
    # Generate JWT secret
    local jwt_secret=$(generate_secret 64)
    echo "JWT_SECRET=$jwt_secret" >> "$ENV_FILE"
    print_status "success" "Generated JWT secret"
    
    # Generate database passwords
    local postgres_password=$(generate_secret 32)
    echo "POSTGRES_PASSWORD=$postgres_password" >> "$ENV_FILE"
    print_status "success" "Generated PostgreSQL password"
    
    local redis_password=$(generate_secret 32)
    echo "REDIS_PASSWORD=$redis_password" >> "$ENV_FILE"
    print_status "success" "Generated Redis password"
    
    echo ""
    
    # External API configuration
    echo "External API Configuration:"
    echo "--------------------------"
    
    # Airtable Token
    local airtable_token=""
    while [ -z "$airtable_token" ]; do
        airtable_token=$(prompt_with_default "Airtable Personal Access Token" "" true)
        if [ -z "$airtable_token" ]; then
            print_status "error" "Airtable token is required"
        fi
    done
    echo "AIRTABLE_TOKEN=$airtable_token" >> "$ENV_FILE"
    
    # Gemini API Key
    local gemini_key=""
    while [ -z "$gemini_key" ]; do
        gemini_key=$(prompt_with_default "Google Gemini API Key" "" true)
        if [ -z "$gemini_key" ]; then
            print_status "error" "Gemini API key is required"
        fi
    done
    echo "GEMINI_API_KEY=$gemini_key" >> "$ENV_FILE"
    
    echo ""
    
    # Environment configuration
    echo "Environment Configuration:"
    echo "-------------------------"
    
    local environment=$(prompt_with_default "Environment (development/staging/production)" "development")
    echo "ENVIRONMENT=$environment" >> "$ENV_FILE"
    
    local log_level=$(prompt_with_default "Log Level (DEBUG/INFO/WARNING/ERROR)" "INFO")
    echo "LOG_LEVEL=$log_level" >> "$ENV_FILE"
    
    echo ""
    
    # Database configuration
    echo "Database Configuration:"
    echo "----------------------"
    
    local postgres_db=$(prompt_with_default "PostgreSQL Database Name" "pyairtable")
    echo "POSTGRES_DB=$postgres_db" >> "$ENV_FILE"
    
    local postgres_user=$(prompt_with_default "PostgreSQL Username" "postgres")
    echo "POSTGRES_USER=$postgres_user" >> "$ENV_FILE"
    
    echo ""
    
    # CORS configuration
    echo "CORS Configuration:"
    echo "------------------"
    
    if [ "$environment" = "production" ]; then
        local cors_origins=""
        while [ -z "$cors_origins" ]; do
            cors_origins=$(prompt_with_default "Allowed CORS Origins (comma-separated URLs)" "")
            if [ -z "$cors_origins" ]; then
                print_status "error" "CORS origins are required for production"
            fi
        done
        echo "CORS_ORIGINS=$cors_origins" >> "$ENV_FILE"
    else
        local cors_origins=$(prompt_with_default "Allowed CORS Origins" "http://localhost:3000,http://localhost:8080")
        echo "CORS_ORIGINS=$cors_origins" >> "$ENV_FILE"
    fi
    
    # Optional configuration
    echo ""
    echo "Optional Configuration:"
    echo "----------------------"
    
    local airtable_base=$(prompt_with_default "Airtable Base ID (optional)" "")
    if [ -n "$airtable_base" ]; then
        echo "AIRTABLE_BASE=$airtable_base" >> "$ENV_FILE"
    fi
    
    local thinking_budget=$(prompt_with_default "LLM Thinking Budget (tokens)" "50000")
    echo "THINKING_BUDGET=$thinking_budget" >> "$ENV_FILE"
    
    # NextAuth configuration for frontend
    local nextauth_secret=$(generate_secret 32)
    echo "NEXTAUTH_SECRET=$nextauth_secret" >> "$ENV_FILE"
    
    local nextauth_url=$(prompt_with_default "NextAuth URL" "http://localhost:3000")
    echo "NEXTAUTH_URL=$nextauth_url" >> "$ENV_FILE"
    
    print_status "success" "Environment file configured successfully"
}

# Function to validate environment file
validate_environment() {
    print_status "info" "Validating environment configuration..."
    
    cd "$PROJECT_ROOT"
    
    if [ ! -f "$ENV_FILE" ]; then
        print_status "error" "Environment file not found"
        return 1
    fi
    
    # Source the environment file
    set -a
    source "$ENV_FILE"
    set +a
    
    local errors=()
    
    # Check required variables
    local required_vars=(
        "API_KEY"
        "JWT_SECRET"
        "AIRTABLE_TOKEN"
        "GEMINI_API_KEY"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "ENVIRONMENT"
        "LOG_LEVEL"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            errors+=("Missing required variable: $var")
        fi
    done
    
    # Validate specific formats
    if [ -n "$CORS_ORIGINS" ] && [[ "$CORS_ORIGINS" != "*" ]]; then
        IFS=',' read -ra ORIGINS <<< "$CORS_ORIGINS"
        for origin in "${ORIGINS[@]}"; do
            origin=$(echo "$origin" | xargs) # trim whitespace
            if ! validate_url "$origin"; then
                errors+=("Invalid CORS origin URL: $origin")
            fi
        done
    fi
    
    # Check environment value
    if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
        errors+=("Invalid environment: $ENVIRONMENT (must be development, staging, or production)")
    fi
    
    # Check log level
    if [[ ! "$LOG_LEVEL" =~ ^(DEBUG|INFO|WARNING|ERROR)$ ]]; then
        errors+=("Invalid log level: $LOG_LEVEL (must be DEBUG, INFO, WARNING, or ERROR)")
    fi
    
    # Security checks
    if [ ${#API_KEY} -lt 32 ]; then
        errors+=("API_KEY should be at least 32 characters long")
    fi
    
    if [ ${#JWT_SECRET} -lt 32 ]; then
        errors+=("JWT_SECRET should be at least 32 characters long")
    fi
    
    # Production-specific checks
    if [ "$ENVIRONMENT" = "production" ]; then
        if [ "$CORS_ORIGINS" = "*" ]; then
            errors+=("CORS_ORIGINS should not be '*' in production")
        fi
        
        if [ "$LOG_LEVEL" = "DEBUG" ]; then
            errors+=("LOG_LEVEL should not be DEBUG in production")
        fi
    fi
    
    if [ ${#errors[@]} -eq 0 ]; then
        print_status "success" "Environment configuration is valid"
        return 0
    else
        print_status "error" "Environment validation failed:"
        for error in "${errors[@]}"; do
            echo "  - $error"
        done
        return 1
    fi
}

# Function to show environment summary
show_environment_summary() {
    echo ""
    echo "📋 Environment Summary"
    echo "====================="
    
    # Source the environment file
    cd "$PROJECT_ROOT"
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
    
    echo "Environment: ${ENVIRONMENT:-not set}"
    echo "Log Level: ${LOG_LEVEL:-not set}"
    echo "Database: ${POSTGRES_DB:-not set}"
    echo "CORS Origins: ${CORS_ORIGINS:-not set}"
    echo ""
    echo "Security:"
    echo "  - API Key: ${API_KEY:0:8}... (${#API_KEY} chars)"
    echo "  - JWT Secret: ${JWT_SECRET:0:8}... (${#JWT_SECRET} chars)"
    echo "  - PostgreSQL Password: *** (${#POSTGRES_PASSWORD} chars)"
    echo "  - Redis Password: *** (${#REDIS_PASSWORD} chars)"
    echo ""
    echo "External APIs:"
    echo "  - Airtable Token: ${AIRTABLE_TOKEN:0:8}... (${#AIRTABLE_TOKEN} chars)"
    echo "  - Gemini API Key: ${GEMINI_API_KEY:0:8}... (${#GEMINI_API_KEY} chars)"
    
    if [ -n "$AIRTABLE_BASE" ]; then
        echo "  - Airtable Base: $AIRTABLE_BASE"
    fi
}

# Function to create docker-compose override for development
create_dev_override() {
    print_status "info" "Creating development docker-compose override..."
    
    cd "$PROJECT_ROOT"
    
    cat > docker-compose.override.yml << 'EOF'
version: '3.8'

# Development overrides for PyAirtable Platform
# This file is automatically generated by setup-environment.sh

services:
  # Expose database ports for development access
  postgres:
    ports:
      - "5432:5432"
  
  redis:
    ports:
      - "6379:6379"
  
  # Enable hot reloading for frontend
  frontend:
    volumes:
      - ./frontend:/app
      - /app/node_modules
      - /app/.next
    environment:
      - NODE_ENV=development
  
  # Add development debugging
  api-gateway:
    environment:
      - LOG_LEVEL=DEBUG
    ports:
      - "8080:8080"
  
  # Expose service ports for direct access during development
  auth-service:
    ports:
      - "8001:8001"
  
  user-service:
    ports:
      - "8002:8002"
  
  workspace-service:
    ports:
      - "8004:8004"
EOF
    
    print_status "success" "Created development docker-compose override"
}

# Main setup function
main() {
    echo -e "${BLUE}🚀 PyAirtable Platform Environment Setup${NC}"
    echo "========================================"
    echo ""
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    echo ""
    
    # Create environment file
    create_environment_file
    
    echo ""
    
    # Validate environment
    if ! validate_environment; then
        exit 1
    fi
    
    # Show summary
    show_environment_summary
    
    # Create development override if in development
    set -a
    source "$PROJECT_ROOT/$ENV_FILE" 2>/dev/null || true
    set +a
    
    if [ "$ENVIRONMENT" = "development" ]; then
        echo ""
        create_dev_override
    fi
    
    echo ""
    print_status "success" "Environment setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Review the generated .env file"
    echo "2. Run: docker-compose up -d"
    echo "3. Run: ./scripts/health-check.sh"
    echo "4. Run: ./scripts/smoke-test.sh"
}

# Show usage if help requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "PyAirtable Platform Environment Setup"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  --validate-only     Only validate existing environment"
    echo "  --non-interactive   Use defaults for all prompts"
    echo ""
    echo "This script helps you set up the environment configuration"
    echo "for the PyAirtable platform deployment."
    exit 0
fi

# Validate only mode
if [[ "$1" == "--validate-only" ]]; then
    cd "$PROJECT_ROOT"
    if validate_environment; then
        show_environment_summary
        exit 0
    else
        exit 1
    fi
fi

# Non-interactive mode
if [[ "$1" == "--non-interactive" ]]; then
    print_status "error" "Non-interactive mode not yet implemented"
    print_status "info" "Please run without --non-interactive to configure interactively"
    exit 1
fi

# Run main function
main