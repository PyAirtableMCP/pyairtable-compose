# Consolidated Services Update

## Date: August 10, 2025

## Summary
Updated Docker Compose configuration to use the new consolidated service repositories from GitHub Container Registry.

## Changes Made

### New docker-compose.consolidated.yml
Created a new Docker Compose file that references the consolidated services:

1. **pyairtable-auth-consolidated** (Port 8004)
   - JWT authentication, user management
   - GitHub Container Registry image

2. **pyairtable-gateway-consolidated** (Port 8000)
   - API gateway, routing, load balancing
   - GitHub Container Registry image

3. **pyairtable-data-consolidated** (Port 8002)
   - Airtable integration, data sync
   - GitHub Container Registry image

4. **pyairtable-ai-consolidated** (Port 8003)
   - LLM orchestration, AI services
   - GitHub Container Registry image

5. **pyairtable-automation-consolidated** (Port 8006)
   - Workflow automation, scheduling
   - GitHub Container Registry image

6. **pyairtable-tenant-consolidated** (Port 8009)
   - Multi-tenant management
   - GitHub Container Registry image

## Usage

To use the consolidated services:

```bash
# Start all services with consolidated images
docker-compose -f docker-compose.consolidated.yml up -d

# View logs
docker-compose -f docker-compose.consolidated.yml logs -f

# Stop services
docker-compose -f docker-compose.consolidated.yml down
```

## Environment Variables Required

```bash
# Database
POSTGRES_PASSWORD=your-secure-password
REDIS_PASSWORD=your-redis-password

# Authentication
JWT_SECRET=your-jwt-secret
API_KEY=your-api-key

# External Services
AIRTABLE_TOKEN=your-airtable-token
AIRTABLE_BASE=your-base-id
OPENAI_API_KEY=your-openai-key
ANTHROPIC_API_KEY=your-anthropic-key
GEMINI_API_KEY=your-gemini-key
```

## Migration Notes

The consolidated services are built and published to GitHub Container Registry. Each service:
- Has its own repository in the PyAirtableMCP organization
- Is automatically built and published on commits to main
- Includes health check endpoints
- Has proper dependency management

## Next Steps

1. Build and publish each consolidated service image
2. Test the complete stack with consolidated services
3. Update CI/CD pipelines to use consolidated images
4. Deprecate old service references