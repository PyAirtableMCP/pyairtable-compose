# PyAirtable Port Configuration

This document outlines the port mapping changes implemented to avoid conflicts with other projects (particularly the Aquascene project).

## Port Mapping Overview

All PyAirtable services have been reconfigured to use non-default ports in the 5xxx and 7xxx ranges to prevent conflicts with other local development environments.

## Service Port Mappings

### Frontend Services
| Service | Original Port | New Port | Purpose |
|---------|---------------|----------|---------|
| Frontend (Next.js) | 3000 | 5173 | Web interface (Vite's default) |

### Core Backend Services  
| Service | Original Port | New Port | Purpose |
|---------|---------------|----------|---------|
| API Gateway | 8000 | 7000 | Central routing, authentication |
| MCP Server | 8001 | 7001 | Model Context Protocol |
| Airtable Gateway | 8002 | 7002 | Airtable API wrapper |
| LLM Orchestrator | 8003 | 7003 | Gemini integration |
| Automation Services | 8006 | 7006 | File processing, workflows |
| Platform Services | 8007 | 7007 | Auth + Analytics |
| SAGA Orchestrator | 8008 | 7008 | Distributed transactions |

### Infrastructure Services
| Service | Original Port | New Port | Purpose |
|---------|---------------|----------|---------|
| PostgreSQL | 5432 | 5433 | Primary database (exposed port) |
| Redis | 6379 | 6380 | Caching, sessions (exposed port) |

### Monitoring Services
| Service | Original Port | New Port | Purpose |
|---------|---------------|----------|---------|
| Grafana | 3003 | 7500 | Monitoring dashboards |
| Prometheus | 9090 | 7501 | Metrics collection |
| Loki | 3100 | 7502 | Log aggregation |

### Development Services
| Service | Original Port | New Port | Purpose |
|---------|---------------|----------|---------|
| Mock Auth Service | 8009 | 7009 | Development authentication |

## Updated URLs

### External Access (Browser/Client)
- **Frontend**: http://localhost:5173
- **API Gateway**: http://localhost:7000
- **Database**: localhost:5433
- **Redis**: localhost:6380

### Internal Service Communication (Docker)
All internal service URLs use container names with new ports:
- `http://api-gateway:7000`
- `http://mcp-server:7001`
- `http://airtable-gateway:7002`
- `http://llm-orchestrator:7003`
- `http://automation-services:7006`
- `http://platform-services:7007`
- `http://saga-orchestrator:7008`

## Files Updated

The following files have been updated with the new port configurations:

### Docker Compose
- `docker-compose.yml` - Main orchestration file
- `docker-compose.minimal.yml` - Minimal deployment configuration

### Environment Files
- `.env` - Main environment configuration
- `.env.example` - Template for environment setup
- `frontend-services/tenant-dashboard/.env.local` - Frontend environment
- `frontend-services/tenant-dashboard/.env.example` - Frontend template

### Documentation
- `CLAUDE.md` - Service documentation and architecture overview
- `PORT_MAPPING.md` - This file

## Service Health Check URLs

After starting services, verify they're running on the new ports:

```bash
# Core Services
curl http://localhost:7000/health  # API Gateway
curl http://localhost:7001/health  # MCP Server
curl http://localhost:7002/health  # Airtable Gateway
curl http://localhost:7003/health  # LLM Orchestrator
curl http://localhost:7006/health  # Automation Services
curl http://localhost:7007/health  # Platform Services
curl http://localhost:7008/health  # SAGA Orchestrator

# Frontend
curl http://localhost:5173/api/health  # Next.js Frontend
```

## Migration Notes

### For Developers
1. Update any local bookmarks from port 3000 → 5173
2. Update API endpoint references from 8000 → 7000
3. Update database connections from 5432 → 5433
4. Update Redis connections from 6379 → 6380

### For CI/CD Pipelines
Ensure any automated tests or deployment scripts reference the new port numbers.

### For Monitoring
Update any external monitoring systems to check the new port endpoints.

## Compatibility

This change maintains full backward compatibility within the container network, as services communicate using container names. Only external access ports have changed.

The internal Docker network routes remain unchanged, ensuring no application code modifications are required.

## Rollback Instructions

To revert to original ports if needed:
1. Restore the original docker-compose.yml file
2. Update .env files to use original ports
3. Restart all services

However, this would re-introduce conflicts with other projects using default ports.