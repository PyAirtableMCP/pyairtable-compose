# PyAirtable Environment Configuration Guide

## Overview

This guide addresses critical environment configuration issues that were preventing services from connecting properly. The PyAirtable system uses Docker Compose with multiple microservices that need to communicate with each other using proper internal networking.

## Key Issues Fixed

### 1. Inconsistent Database Connection Strings
**Problem**: Some services were using `localhost` instead of container names for database connections.

**Solution**: All services now use container names for internal Docker networking:
```bash
# ❌ Wrong (localhost)
DATABASE_URL=postgresql://user:pass@localhost:5432/db

# ✅ Correct (container name)
DATABASE_URL=postgresql://user:pass@postgres:5432/db
```

### 2. Redis Connection Inconsistencies
**Problem**: Mixed Redis connection formats across services.

**Solution**: Standardized Redis URLs with password authentication:
```bash
# ✅ Correct format
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
```

### 3. Service-to-Service URL Mismatches
**Problem**: Services couldn't find each other due to incorrect internal URLs.

**Solution**: All internal service URLs now use container names:
```bash
AIRTABLE_GATEWAY_URL=http://airtable-gateway:8002
MCP_SERVER_URL=http://mcp-server:8001
LLM_ORCHESTRATOR_URL=http://llm-orchestrator:8003
```

### 4. CORS Configuration Issues
**Problem**: Frontend couldn't communicate with backend services.

**Solution**: Properly configured CORS origins:
```bash
CORS_ORIGINS=http://localhost:3000,http://localhost:8000,http://localhost:8080
```

### 5. Missing Environment Variables
**Problem**: Many required environment variables were undefined or had placeholder values.

**Solution**: Created comprehensive environment templates and validation scripts.

## Environment Files Structure

```
pyairtable-compose/
├── .env.template          # Master template with all variables
├── .env                   # Local development (auto-generated)
├── .env.production        # Production configuration
├── .env.staging           # Staging configuration
├── .env.local            # Local overrides (optional)
└── .env.development      # Development-specific settings
```

## Quick Setup

### 1. Generate Secure Environment
```bash
# Generate .env with secure random secrets
./generate-secure-env.sh

# Generate all environment files (dev, staging, production)
./generate-secure-env.sh --all
```

### 2. Configure External API Credentials
Edit `.env` and replace these placeholder values with your actual credentials:

```bash
# Airtable Configuration
AIRTABLE_TOKEN=your_actual_airtable_token_here
AIRTABLE_BASE=your_actual_base_id_here

# Google Gemini API Key  
GEMINI_API_KEY=your_actual_gemini_api_key_here
```

### 3. Validate Configuration
```bash
# Validate all environment variables
./validate-environment.sh
```

### 4. Start Services
```bash
# Start all services
docker-compose up -d

# Check service health
docker-compose ps
```

## Environment Variables Reference

### External API Credentials (Required)
```bash
AIRTABLE_TOKEN=patXXXXXXXXXXXXXX          # Airtable Personal Access Token
AIRTABLE_BASE=appXXXXXXXXXXXXXX           # Airtable Base ID
GEMINI_API_KEY=AIzaSyXXXXXXXXXXXXXXXX     # Google Gemini API Key
```

### Internal Security (Auto-generated)
```bash
API_KEY=pya_xxxxxxxxxxxxxxxxxxxxxxxx      # Internal service authentication
JWT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxx       # JWT token signing
NEXTAUTH_SECRET=xxxxxxxxxxxxxxxxxxxxxxxx  # NextAuth authentication
POSTGRES_PASSWORD=xxxxxxxxxxxxxxxx        # PostgreSQL password
REDIS_PASSWORD=xxxxxxxxxxxxxxxx           # Redis password
```

### Service URLs (Internal Docker Networking)
```bash
# Core Services
AIRTABLE_GATEWAY_URL=http://airtable-gateway:8002
MCP_SERVER_URL=http://mcp-server:8001
LLM_ORCHESTRATOR_URL=http://llm-orchestrator:8003
API_GATEWAY_URL=http://api-gateway:8000
FRONTEND_URL=http://frontend:3000

# Platform Services
PLATFORM_SERVICES_URL=http://platform-services:8007
AUTOMATION_SERVICES_URL=http://automation-services:8006
SAGA_ORCHESTRATOR_URL=http://saga-orchestrator:8008
```

### Database Connections
```bash
# PostgreSQL (internal networking)
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}

# Redis (internal networking)  
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
```

## Docker Networking

All services are configured to use the `pyairtable-network` Docker network:

```yaml
networks:
  pyairtable-network:
    driver: bridge
```

### Service Ports
- **API Gateway**: 8000 (external entry point)
- **MCP Server**: 8001
- **Airtable Gateway**: 8002  
- **LLM Orchestrator**: 8003
- **Automation Services**: 8006
- **Platform Services**: 8007
- **SAGA Orchestrator**: 8008
- **Frontend**: 3000
- **PostgreSQL**: 5432 (internal only)
- **Redis**: 6379 (internal only)

## Security Best Practices

### 1. Database Security
- PostgreSQL and Redis ports are not exposed externally
- Strong randomly generated passwords
- Connection strings use internal container names

### 2. API Security
- Internal API key for service-to-service communication
- JWT secrets for token authentication
- CORS properly configured for frontend access

### 3. Credential Management
```bash
# ✅ Do
- Use environment variables for all secrets
- Generate secure random passwords
- Keep .env files out of version control
- Use different credentials for each environment

# ❌ Don't  
- Hardcode credentials in source code
- Use weak or default passwords
- Commit .env files to Git
- Share production credentials
```

## Troubleshooting

### Service Connection Issues
```bash
# Check if services can reach each other
docker-compose exec api-gateway curl http://airtable-gateway:8002/health
docker-compose exec llm-orchestrator curl http://mcp-server:8001/health
```

### Database Connection Issues
```bash
# Test PostgreSQL connection
docker-compose exec postgres psql -U postgres -d pyairtable -c "SELECT 1;"

# Test Redis connection
docker-compose exec redis redis-cli -a ${REDIS_PASSWORD} ping
```

### Environment Variable Issues
```bash
# Check environment variables in a service
docker-compose exec api-gateway env | grep -E "(DATABASE_URL|REDIS_URL|API_KEY)"

# Validate environment configuration
./validate-environment.sh
```

### CORS Issues
```bash
# Check CORS configuration
curl -H "Origin: http://localhost:3000" \
     -H "Access-Control-Request-Method: POST" \
     -H "Access-Control-Request-Headers: X-Requested-With" \
     -X OPTIONS \
     http://localhost:8000/api/health
```

## Development vs Production

### Development Environment
- Uses `localhost` URLs for external frontend access
- Debug logging enabled
- HTTPS not required
- Relaxed CORS settings

### Production Environment  
- Uses HTTPS URLs
- Info-level logging
- HTTPS required
- Strict CORS settings
- SSL database connections

## Migration from Old Configuration

If migrating from an existing setup:

1. **Backup current configuration**:
   ```bash
   cp .env .env.backup.$(date +%Y%m%d_%H%M%S)
   ```

2. **Generate new secure configuration**:
   ```bash
   ./generate-secure-env.sh
   ```

3. **Migrate external API credentials**:
   ```bash
   # Copy your actual credentials from backup to new .env
   ```

4. **Validate and test**:
   ```bash
   ./validate-environment.sh
   docker-compose up -d
   ```

## Support

For additional help:
1. Run the validation script: `./validate-environment.sh`
2. Check service logs: `docker-compose logs [service-name]`
3. Verify network connectivity between services
4. Ensure all required external API credentials are configured

---

**Important**: Never commit actual credentials to version control. Always use environment variables and keep `.env` files in your `.gitignore`.