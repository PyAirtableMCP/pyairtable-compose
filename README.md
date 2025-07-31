# pyairtable-compose

Docker Compose configuration for PyAirtable microservices infrastructure

## Overview

This repository contains Docker Compose configurations to run the complete PyAirtable microservices stack locally. It orchestrates:

- **airtable-gateway-py** (Port 8002) - Airtable API wrapper
- **mcp-server-py** (Port 8001) - MCP protocol server
- **llm-orchestrator-py** (Port 8003) - Gemini 2.5 Flash integration
- **pyairtable-api-gateway** (Port 8000) - API gateway and routing
- **redis** (Port 6379) - Caching and session storage
- **postgres** (Port 5432) - Database for sessions and metadata

## Quick Start

```bash
# Clone the repository
git clone https://github.com/Reg-Kris/pyairtable-compose.git
cd pyairtable-compose

# Set up environment
cp .env.example .env
# Edit .env with your API keys

# Start all services
docker-compose up -d

# Check service health
curl http://localhost:8000/api/health

# Test the chat endpoint
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: simple-api-key" \
  -d '{
    "message": "List all tables in my base",
    "session_id": "test-user",
    "base_id": "appXXXXXXXXXXXXXX"
  }'
```

## Development Mode

For development with live code reloading:

```bash
# Start with development configuration
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up

# View logs
docker-compose logs -f

# Restart specific service
docker-compose restart llm-orchestrator
```

## Services Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User/Client   │    │                 │    │                 │
│                 │────▶│  API Gateway    │    │  LLM Orchestr.  │
│                 │    │  (Port 8000)    │────▶│  (Port 8003)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                        │
                                │                        ▼
                                │               ┌─────────────────┐
                                │               │   MCP Server    │
                                │               │  (Port 8001)    │
                                │               └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │ Airtable Gateway│    │     Redis       │
                       │  (Port 8002)    │    │  (Port 6379)    │
                       └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   PostgreSQL    │
                       │  (Port 5432)    │
                       └─────────────────┘
```

## Environment Variables

Required in `.env`:

```env
# Airtable Configuration
AIRTABLE_TOKEN=your_personal_access_token
AIRTABLE_BASE=your_default_base_id

# Gemini Configuration
GEMINI_API_KEY=your_gemini_api_key

# Service Configuration
API_KEY=simple-api-key
THINKING_BUDGET=5

# Database Configuration
POSTGRES_DB=pyairtablemcp
POSTGRES_USER=admin
POSTGRES_PASSWORD=changeme

# Redis Configuration
REDIS_PASSWORD=changeme
```

## Service URLs

When all services are running:

- **API Gateway**: http://localhost:8000
- **Health Check**: http://localhost:8000/api/health
- **Airtable Gateway**: http://localhost:8002
- **LLM Orchestrator**: http://localhost:8003
- **Redis**: localhost:6379
- **PostgreSQL**: localhost:5432

## Useful Commands

```bash
# Start all services
docker-compose up -d

# View service logs
docker-compose logs -f [service-name]

# Restart a specific service
docker-compose restart [service-name]

# Rebuild and restart
docker-compose up -d --build

# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v

# Scale a service (if needed)
docker-compose up -d --scale llm-orchestrator=2
```

## Testing

```bash
# Test health check
./scripts/test-health.sh

# Test chat functionality
./scripts/test-chat.sh

# Run integration tests
./scripts/integration-test.sh
```

## Monitoring

Service logs are available via:

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api-gateway
docker-compose logs -f llm-orchestrator
docker-compose logs -f airtable-gateway
docker-compose logs -f mcp-server
```

## Troubleshooting

### Common Issues

1. **Services not starting**: Check `.env` file has all required variables
2. **Connection refused**: Ensure all services are running with `docker-compose ps`
3. **API key errors**: Verify `AIRTABLE_TOKEN` and `GEMINI_API_KEY` are set correctly
4. **Port conflicts**: Stop other services using ports 8000-8003, 5432, 6379

### Health Check

The API Gateway provides a comprehensive health check:

```bash
curl http://localhost:8000/api/health
```

This will show the status of all microservices.

## Production Deployment

For production deployment:

1. Use `docker-compose.prod.yml`
2. Set up proper secrets management
3. Configure reverse proxy (nginx/traefik)
4. Set up monitoring and logging
5. Use external databases and Redis

```bash
# Production deployment
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```