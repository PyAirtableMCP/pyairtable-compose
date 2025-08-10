# Repository Catalog - PyAirtable Ecosystem

**Last Updated:** August 9, 2025  
**Purpose:** Complete index of all repositories, their purposes, and current status

---

## 📁 LOCAL DIRECTORY STRUCTURE

**Primary Repository:** `/Users/kg/IdeaProjects/pyairtable-compose/`

This appears to be a consolidated **orchestration repository** containing multiple service implementations, infrastructure configurations, and deployment scripts rather than individual service repositories.

---

## 🏗️ ARCHITECTURAL ORGANIZATION

### Core Service Directories

| Directory | Purpose | Technology | Status | Notes |
|-----------|---------|------------|--------|-------|
| `go-services/` | Go microservices implementation | Go, gRPC, Fiber | 🚧 Development | 20+ service templates, not deployed |
| `frontend-services/` | Web interface applications | Next.js 15, TypeScript | 🚧 Partial | 4 separate applications, not unified |
| `python-services/` | Python microservices | FastAPI, Python | ❌ Missing | Referenced in docs but directory not found |
| `k8s/` | Kubernetes deployment manifests | YAML, Kubernetes | 📚 Ready | Complete k8s setup, not in use |
| `infrastructure/` | Terraform and cloud resources | Terraform, AWS | 📚 Ready | Multi-cloud setup, not deployed |
| `monitoring/` | Observability stack | Prometheus, Grafana | 🚧 Partial | LGTM stack configured |

### Support Directories

| Directory | Purpose | Status | Notes |
|-----------|---------|--------|-------|
| `tests/` | Testing frameworks and suites | ✅ Active | Comprehensive test coverage |
| `scripts/` | Automation and helper scripts | ✅ Active | Deployment, health checks |
| `docs/` | Architecture documentation | ✅ Active | Extensive documentation |
| `configs/` | Configuration templates | ✅ Active | Service configurations |
| `migrations/` | Database schema management | ✅ Active | SQL migration scripts |

---

## 🚢 SERVICE IMPLEMENTATIONS

### 1. Go Services (`go-services/`)

**Status:** Aspirational - Extensive codebase exists but not integrated into main deployment

| Service | Purpose | Implementation | Status |
|---------|---------|---------------|--------|
| `api-gateway/` | Central routing, authentication | Go, Fiber, JWT | ✅ Complete |
| `auth-service/` | User authentication | Go, PostgreSQL | ✅ Complete |
| `file-processing-service/` | File upload handling | Go, S3 integration | ✅ Complete |
| `permission-service/` | RBAC implementation | Go, gRPC | ✅ Complete |
| `user-service/` | User management | Go, GraphQL | ✅ Complete |
| `workspace-service/` | Workspace operations | Go, DDD patterns | ✅ Complete |
| `notification-service/` | Event notifications | Go, pub/sub | ✅ Complete |
| `webhook-service/` | Webhook management | Go, event-driven | ✅ Complete |
| `pyairtable-platform/` | Consolidated platform | Go, CQRS/ES | ✅ Complete |

**Key Finding:** Extensive Go implementation exists with advanced patterns (CQRS, Event Sourcing, DDD) but is completely disconnected from current deployment.

### 2. Frontend Services (`frontend-services/`)

| Service | Purpose | Technology | Status |
|---------|---------|------------|--------|
| `tenant-dashboard/` | Main user interface | Next.js 15, TypeScript | 🚧 Partial |
| `admin-dashboard/` | Administrative interface | Next.js 15, TypeScript | 🚧 Partial |
| `auth-frontend/` | Authentication UI | Next.js, React | 🚧 Partial |
| `event-sourcing-ui/` | Event system interface | Next.js, TypeScript | 🚧 Partial |

**Key Finding:** Multiple frontend applications exist but no unified deployment or integration strategy.

### 3. Python Services (Current Docker Compose)

**Status:** Documented but mostly non-functional

| Service | Image | Port | Status | Health |
|---------|-------|------|--------|--------|
| Airtable Gateway | `ghcr.io/reg-kris/airtable-gateway-py:latest` | 7002 | ❌ Unhealthy | API key issues |
| Platform Services | `pyairtable-compose-platform-services` | 7007 | ❌ Unhealthy | Service errors |
| LLM Orchestrator | `llm-orchestrator-test:latest` | 8003 | ❌ Not running | Not in compose |
| MCP Server | `mcp-server-test:latest` | 8001 | ❌ Not running | Not in compose |

---

## 🗂️ INFRASTRUCTURE REPOSITORIES

### Deployment Configurations

| File/Directory | Purpose | Status | Notes |
|---------------|---------|--------|-------|
| `docker-compose.yml` | Main service orchestration | 🚧 Partial | Only 4/8 services defined |
| `docker-compose.dev.yml` | Development overrides | ✅ Ready | Development configuration |
| `docker-compose.production.yml` | Production deployment | ✅ Ready | Production-ready setup |
| `docker-compose.monitoring.yml` | Observability stack | ✅ Ready | LGTM monitoring |

### Container Orchestration

| Technology | Configuration | Status | Usage |
|-----------|---------------|--------|--------|
| **Docker Compose** | Multiple compose files | ✅ Active | Primary orchestration |
| **Kubernetes** | Complete manifests | 📚 Ready | Not deployed locally |
| **Minikube** | Local k8s setup | 📚 Ready | Available but unused |

### Cloud Infrastructure

| Provider | Configuration | Status | Purpose |
|----------|---------------|--------|---------|
| **AWS EKS** | Terraform modules | 📚 Ready | Production Kubernetes |
| **Multi-region** | Disaster recovery | 📚 Ready | Geographic redundancy |
| **Cost optimization** | FinOps automation | 📚 Ready | Resource efficiency |

---

## 🔍 EXTERNAL REPOSITORY REFERENCES

### GitHub Organization Analysis

Based on documentation references, the PyAirtable ecosystem includes:

| Repository | Status | Notes |
|-----------|---------|-------|
| `pyairtable-api-gateway` | 🗄️ Archived | Merged into this repo |
| `pyairtable-frontend` | ❓ Unknown | Referenced but not found |
| `llm-orchestrator-py` | ❓ Unknown | Images exist, source unclear |
| `mcp-server-py` | ❓ Unknown | Images exist, source unclear |
| `airtable-gateway-py` | ❓ Unknown | Has GitHub container registry |
| `pyairtable-platform-services` | ❓ Unknown | Built locally |
| `pyairtable-automation-services` | ❓ Unknown | Referenced in docs |
| `saga-orchestrator` | ❓ Unknown | Exists as subdirectory |

**Key Finding:** Many services are referenced as separate repositories but appear to be consolidated into this monorepo structure.

---

## 📊 TECHNOLOGY STACK INVENTORY

### Languages and Frameworks

| Technology | Usage | Maturity | Status |
|-----------|-------|----------|--------|
| **Go** | 20+ microservices | Production-ready | Not deployed |
| **Python** | 4 core services | Basic implementation | Partially working |
| **TypeScript** | 4 frontend apps | Modern framework | Not deployed |
| **SQL** | Database schemas | Production-ready | Active |

### Infrastructure Technologies

| Technology | Purpose | Configuration | Status |
|-----------|---------|---------------|--------|
| **PostgreSQL 16** | Primary database | Production config | ✅ Running |
| **Redis 7** | Caching/sessions | Cluster-ready | ✅ Running |
| **Docker** | Containerization | Multi-stage builds | ✅ Active |
| **Kubernetes** | Orchestration | Complete manifests | 📚 Ready |
| **Terraform** | Infrastructure | Multi-cloud | 📚 Ready |

### Observability Stack

| Component | Purpose | Status | Integration |
|-----------|---------|--------|-------------|
| **Prometheus** | Metrics collection | ✅ Configured | Ready |
| **Grafana** | Visualization | ✅ Configured | Ready |
| **Loki** | Log aggregation | ✅ Configured | Ready |
| **Tempo** | Distributed tracing | ✅ Configured | Ready |

---

## 🎯 SERVICE DEPLOYMENT STRATEGY

### Current Reality (August 9, 2025)
```
INFRASTRUCTURE: 2/2 services running (100%)
├── PostgreSQL 16 - Port 5433 ✅
└── Redis 7 - Port 6380 ✅

BUSINESS SERVICES: 0/6 services running (0%)
├── API Gateway - Not running ❌
├── Airtable Gateway - Unhealthy ❌  
├── Frontend - Not running ❌
├── LLM Orchestrator - Not running ❌
├── MCP Server - Not running ❌
└── Platform Services - Unhealthy ❌
```

### Target Architecture
```
FULL STACK: 8/8 services running (100%)
├── Infrastructure Layer (2/2)
│   ├── PostgreSQL 16 - Port 5433
│   └── Redis 7 - Port 6380
├── Gateway Layer (1/1)  
│   └── API Gateway - Port 8000
├── Core Services Layer (3/3)
│   ├── Airtable Gateway - Port 8002
│   ├── LLM Orchestrator - Port 8003
│   └── MCP Server - Port 8001
├── Platform Layer (2/2)
│   ├── Platform Services - Port 8007
│   └── Automation Services - Port 8006
└── Frontend Layer (1/1)
    └── Web Interface - Port 3000
```

---

## 🔄 REPOSITORY EVOLUTION

### Consolidation History
The current repository appears to be a consolidation of multiple separate repositories:

1. **Individual Service Repos** → **Monorepo Structure**
2. **Separate Frontend Repos** → **frontend-services/** directory  
3. **Infrastructure Repos** → **infrastructure/** directory
4. **Documentation Scattered** → **docs/** centralization

### Benefits of Current Structure
- ✅ **Unified deployment** - Single docker-compose orchestration
- ✅ **Consistent tooling** - Shared scripts and configurations  
- ✅ **Simplified development** - Single repository to clone
- ✅ **Atomic deployments** - Deploy entire stack together

### Challenges
- ❌ **Service isolation** - Changes affect multiple services
- ❌ **Technology conflicts** - Multiple language ecosystems
- ❌ **Repository size** - Large codebase with mixed concerns
- ❌ **Build complexity** - Multiple build systems

---

## 📈 RECOMMENDED REPOSITORY STRATEGY

### Short-term (Current State)
- **Maintain monorepo structure** for development simplicity  
- **Focus on service functionality** before architectural optimization
- **Use directory-based service separation** with clear boundaries
- **Implement service-specific claude.md files** for context

### Medium-term (Service Maturity)
- **Consider service extraction** for high-change/high-value services
- **Implement proper CI/CD pipelines** for multi-service builds
- **Add service versioning** and API contracts
- **Create service dependency management**

### Long-term (Production Scale)
- **Evaluate microrepo strategy** for team scalability
- **Implement service mesh** for inter-service communication
- **Add advanced deployment patterns** (blue/green, canary)
- **Consider polyrepo** for completely independent services

---

**Repository Status Summary:**
- **Structure:** Consolidated monorepo with service directories
- **Services:** 20+ implemented, 2 deployed, 0 fully operational  
- **Infrastructure:** Production-ready, partially deployed
- **Documentation:** Extensive but inconsistent with reality
- **Next Steps:** Focus on service deployment before architectural optimization

---

*This catalog will be updated as services are deployed and repository structure evolves.*