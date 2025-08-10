#!/bin/bash

# =============================================================================
# PyAirtable Secure Environment Generator
# =============================================================================
# 
# SECURITY NOTICE: This script generates secure random credentials for local 
# development. For production environments, use a proper secrets management 
# system like AWS Secrets Manager, Azure Key Vault, or HashiCorp Vault.
#
# DESCRIPTION:
#   - Generates cryptographically secure passwords using OpenSSL
#   - Creates placeholder values for external API credentials
#   - Sets restrictive file permissions (600) on generated .env file
#   - Backs up existing .env files with timestamps
#
# USAGE: ./generate-secure-env.sh
#
# OWASP COMPLIANCE: 
#   - A02:2021 – Cryptographic Failures (secure random generation)
#   - A05:2021 – Security Misconfiguration (secure defaults)
#   - A07:2021 – Identification and Authentication Failures (strong secrets)
#
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

echo "🔐 Generating secure environment configuration..."

# Check if .env already exists
if [ -f .env ]; then
    echo "⚠️  .env file already exists. Backing up to .env.backup.$(date +%Y%m%d_%H%M%S)"
    mv .env .env.backup.$(date +%Y%m%d_%H%M%S)
fi

# =============================================================================
# SECURE RANDOM GENERATION FUNCTIONS
# =============================================================================

# Generate secure password (32 characters, alphanumeric)
# Uses OpenSSL for cryptographically secure random generation
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Generate secure API key (64 characters hex)
# Format: 256-bit entropy in hexadecimal
generate_api_key() {
    echo "pya_$(openssl rand -hex 32)"
}

# Generate secure JWT secret (base64 encoded, 512-bit for production security)
# OWASP recommendation: Minimum 256 bits, 512 bits for high-security environments
generate_jwt_secret() {
    openssl rand -base64 64
}

# Generate JWT refresh token secret (separate from access token secret)
generate_jwt_refresh_secret() {
    openssl rand -base64 64
}

# Generate secure session secret for additional security layer
generate_session_secret() {
    openssl rand -base64 32
}

# Validate OpenSSL availability
if ! command -v openssl &> /dev/null; then
    echo "❌ ERROR: OpenSSL is required but not installed."
    echo "   Install OpenSSL and try again."
    exit 1
fi

# =============================================================================
# GENERATE SECURE CREDENTIALS
# =============================================================================

echo "🔐 Generating cryptographically secure credentials..."

POSTGRES_PASSWORD=$(generate_password)
REDIS_PASSWORD=$(generate_password)  
JWT_SECRET=$(generate_jwt_secret)
JWT_REFRESH_SECRET=$(generate_jwt_refresh_secret)
SESSION_SECRET=$(generate_session_secret)
API_KEY=$(generate_api_key)

echo "   ✅ Generated secure database passwords"
echo "   ✅ Generated secure JWT secrets (512-bit)" 
echo "   ✅ Generated secure session secret"
echo "   ✅ Generated secure API key"

# Create .env file
cat > .env << EOF
# PyAirtable Environment Configuration
# Generated: $(date)
# IMPORTANT: Keep this file secure and never commit to version control

# Database Configuration
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=pyairtable
POSTGRES_USER=pyairtable
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Redis Configuration
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# Authentication - Enhanced JWT Security
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_ACCESS_TOKEN_EXPIRATION=900
JWT_REFRESH_TOKEN_EXPIRATION=604800
SESSION_SECRET=${SESSION_SECRET}
API_KEY=${API_KEY}

# JWT Security Configuration
JWT_ALGORITHM=HS256
JWT_ISSUER=pyairtable-platform
JWT_AUDIENCE=pyairtable-api
JWT_LEEWAY=30

# Token Rotation Policy
JWT_ROTATION_ENABLED=true
JWT_ROTATION_THRESHOLD=300
JWT_BLACKLIST_ENABLED=true

# Airtable Integration
# IMPORTANT: Replace these with your actual Airtable credentials
AIRTABLE_TOKEN=patYOUR_TOKEN_HERE.YOUR_FULL_TOKEN_GOES_HERE
AIRTABLE_BASE=appYOUR_BASE_ID

# AI Services (add your actual API keys)
# OPENAI_API_KEY=sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ANTHROPIC_API_KEY=sk-ant-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
GEMINI_API_KEY=AIzaSyYOUR_GEMINI_API_KEY_HERE

# Service URLs (for docker-compose networking)
AUTH_SERVICE_URL=http://auth-service:8004
DATA_SERVICE_URL=http://data-service:8002
AI_SERVICE_URL=http://ai-service:8003
AUTOMATION_SERVICE_URL=http://automation-service:8006
TENANT_SERVICE_URL=http://tenant-service:8009
GATEWAY_URL=http://gateway:8000

# Frontend Configuration
NEXT_PUBLIC_API_URL=http://localhost:8000
NEXT_PUBLIC_AUTH_URL=http://localhost:8004

# Environment
ENVIRONMENT=development
LOG_LEVEL=INFO
DEBUG=false

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_RPM=60
RATE_LIMIT_RPH=1000

# Security Configuration
CORS_ORIGINS=http://localhost:3000,http://localhost:8000
HTTPS_ENABLED=${HTTPS_ENABLED:-false}
SECURE_COOKIES=${SECURE_COOKIES:-false}

# SSL/TLS Configuration
SSL_CERT_PATH=/etc/ssl/certs/pyairtable.crt
SSL_KEY_PATH=/etc/ssl/private/pyairtable.key
SSL_CA_PATH=/etc/ssl/certs/ca-certificates.crt
TLS_MIN_VERSION=1.2
TLS_MAX_VERSION=1.3

# Security Headers
HSTS_MAX_AGE=31536000
CSP_ENABLED=true
FRAME_OPTIONS=DENY
CONTENT_TYPE_OPTIONS=nosniff
XSS_PROTECTION=1

# Rate Limiting Enhanced
RATE_LIMIT_ENABLED=true
RATE_LIMIT_RPM=60
RATE_LIMIT_RPH=1000
RATE_LIMIT_BURST=20
RATE_LIMIT_WINDOW=300

# IP Whitelist for Admin Operations
ADMIN_IP_WHITELIST=127.0.0.1,::1
EOF

# Set restrictive permissions
chmod 600 .env

echo "✅ Secure .env file created successfully!"
echo ""
echo "📋 Generated secure credentials:"
echo "   - PostgreSQL Password: [SECURE - 32 chars]"
echo "   - Redis Password: [SECURE - 32 chars]"
echo "   - JWT Access Secret: [SECURE - 64 chars, 512-bit]"
echo "   - JWT Refresh Secret: [SECURE - 64 chars, 512-bit]"
echo "   - Session Secret: [SECURE - 32 chars]"
echo "   - API Key: [SECURE - 64 chars hex]"
echo ""
echo "⚠️  IMPORTANT: You must update these placeholder values:"
echo "   1. AIRTABLE_TOKEN - Get from https://airtable.com/developers/web/api/authentication"
echo "   2. AIRTABLE_BASE - Your Airtable base ID (starts with 'app')"
echo "   3. GEMINI_API_KEY - Get from Google Cloud Console"
echo ""
echo "🔒 SECURITY RECOMMENDATIONS:"
echo "   - .env file has restrictive permissions (600) - only owner can read/write"
echo "   - Never commit .env to version control (already in .gitignore)"
echo "   - Rotate credentials regularly (recommend monthly minimum)"
echo "   - Use a secrets management system in production (AWS Secrets Manager, etc.)"
echo "   - Enable audit logging for credential access in production"
echo ""
echo "🛡️  OWASP COMPLIANCE:"
echo "   - A02:2021: Using cryptographically secure random generation"
echo "   - A05:2021: Secure file permissions and configuration"  
echo "   - A07:2021: Strong authentication secrets generated"
echo ""
echo "📖 NEXT STEPS:"
echo "   1. Run the application: docker-compose up -d"
echo "   2. Replace placeholder API keys with your actual credentials"
echo "   3. Test the application endpoints"
echo "   4. Set up proper secrets management for production deployment"