# ACTUAL SERVICE INVENTORY - PYAIRTABLE MONOREPO

**Date**: 2025-08-11  
**Status**: Post-Cleanup Inventory

## Truth About Our Architecture

**We are using a MONOREPO architecture** with service-level organization.  
This is the same pattern used by Google, Microsoft, and Facebook.

---

## Current Directory Structure (After Cleanup)

```
pyairtable-compose/
├── go-services/           # 22 Go service directories
├── python-services/       # 14 Python service directories  
├── frontend-services/     # 4 Frontend applications
├── infrastructure/        # Infrastructure configurations
├── shared/               # Shared code and protocols
├── deployments/          # K8s and Docker configs
├── monitoring/           # Observability stack
├── tests/               # Integration tests
└── archived-experiments/ # Failed experiments (to be deleted)
```

---

## Active Services Inventory

### Go Services (/go-services/)
| Service | Purpose | Status | Keep/Remove |
|---------|---------|--------|-------------|
| api-gateway | Main API entry point | Active | ✅ KEEP |
| auth-service | Authentication | Active | ✅ KEEP |
| user-service | User management | Active | ✅ KEEP |
| workspace-service | Workspace/tenant mgmt | Active | ✅ KEEP |
| file-service | File uploads | Partial | ✅ KEEP |
| notification-service | Notifications | Partial | ✅ KEEP |
| webhook-service | External webhooks | Partial | ✅ KEEP |
| permission-service | Authorization | Partial | ✅ KEEP |
| file-processing-service | File processing | Duplicate | ❌ MERGE into file-service |
| mobile-bff | Mobile backend | Empty | ❌ REMOVE |
| web-bff | Web backend | Empty | ❌ REMOVE |
| plugin-service | Plugins | Not needed | ❌ REMOVE |
| pyairtable-platform | Platform attempt | Failed | ❌ REMOVE |
| frontend-integration | Frontend bridge | Empty | ❌ REMOVE |
| graphql-gateway | GraphQL API | Not used | ❌ REMOVE |

### Python Services (/python-services/)
| Service | Purpose | Status | Keep/Remove |
|---------|---------|--------|-------------|
| airtable-gateway | Airtable API | Active | ✅ KEEP |
| llm-orchestrator | AI coordination | Active | ✅ KEEP |
| mcp-server | Model Context Protocol | Active | ✅ KEEP |
| workflow-engine | Business workflows | Partial | ✅ KEEP |
| analytics-service | Analytics | Partial | ✅ KEEP |
| audit-service | Audit logging | Partial | ✅ KEEP |
| chat-service | Real-time chat | Partial | ✅ KEEP |
| ai-service | AI operations | Duplicate | ❌ MERGE into llm-orchestrator |
| embedding-service | Embeddings | Duplicate | ❌ MERGE into llm-orchestrator |
| semantic-search | Search | Duplicate | ❌ MERGE into llm-orchestrator |
| formula-engine | Formulas | Not needed | ❌ REMOVE |
| schema-service | Schemas | Empty | ❌ REMOVE |

### Frontend Services (/frontend-services/)
| Service | Purpose | Status | Keep/Remove |
|---------|---------|--------|-------------|
| tenant-dashboard | Main user UI | Active | ✅ KEEP |
| admin-portal | Admin UI | Partial | ✅ KEEP |
| mobile-app | Mobile app | Empty | ❌ REMOVE |
| developer-portal | API docs | Empty | ❌ REMOVE |

---

## Services Running in Docker

```bash
# Currently running (docker ps):
- pyairtable-compose-api-gateway-1 (port 8000)
- pyairtable-compose-platform-services-1 (port 8007)
- pyairtable-compose-llm-orchestrator-1 (port 8003)
- pyairtable-compose-mcp-server-1 (port 8001)
- pyairtable-compose-airtable-gateway-1 (port 8002)
- pyairtable-compose-postgres-1
- pyairtable-compose-redis-1
```

---

## GitHub Organization Status

### Active Repositories (5)
1. **pyairtable-compose** - Main monorepo (THIS IS WHERE EVERYTHING IS)
2. **pyairtable-docs** - Documentation
3. **pyairtable-common** - Shared libraries
4. **pyairtable-frontend** - Frontend (EMPTY - code is in monorepo)
5. **pyairtable-infra** - Infrastructure (DUPLICATE of monorepo)

### Archived Repositories (9)
All service-specific repos have been archived as they were empty or duplicates.

---

## The Truth

### What We Claimed
- "18 microservice repositories"
- "Separate repos for each service"
- "6/18 services complete"

### What Actually Exists
- **1 monorepo** with everything
- **36 service directories** in the monorepo
- **5 services actually running** in Docker
- **Massive duplication** and confusion

---

## Recommended Final Architecture

### Core Services to Keep (16 total)

#### Go Services (8)
1. api-gateway
2. auth-service
3. user-service
4. workspace-service
5. file-service
6. notification-service
7. webhook-service
8. permission-service

#### Python Services (6)
1. airtable-gateway
2. llm-orchestrator
3. mcp-server
4. workflow-engine
5. analytics-service
6. audit-service

#### Frontend Services (2)
1. tenant-dashboard
2. admin-portal

---

## Next Steps

1. **Delete** archived-experiments directory
2. **Remove** 20+ unnecessary service directories
3. **Consolidate** duplicate functionality
4. **Standardize** remaining services
5. **Update** CI/CD for monorepo reality
6. **Document** actual architecture

---

## Conclusion

We have a monorepo with too many experimental directories. The path forward is to:
- **Keep the monorepo** (it's working)
- **Clean up the mess** (remove 20+ directories)
- **Focus on 16 core services**
- **Stop pretending** we have microservices in separate repos

This is honest, achievable, and will actually work.