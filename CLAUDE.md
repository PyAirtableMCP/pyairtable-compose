# PyAirtable Compose - Claude Context

## 🎯 Service Purpose
Orchestration hub for the entire PyAirtable ecosystem containing Docker Compose configurations, environment setup, deployment scripts, and operational tools for local development and production deployment.

## 🔧 Technology Stack
- Language: Docker Compose, Bash scripts
- Orchestration: Docker Compose with multi-environment support
- Database: PostgreSQL 16 with Redis 7 caching
- Monitoring: LGTM stack (Prometheus, Grafana, Loki, Tempo)
- Platform: **8-service consolidated microservices architecture**

## 🏗️ Current Architecture (Post-Sprint 4 Completion)

### Core Services (8 Active - Sprint 4 Status)
| Service | Language | Port | Purpose | Status |
|---------|----------|------|---------|--------|
| **LLM Orchestrator** | Python | 8003 | Gemini 2.5 Flash integration, chat | ✅ Active |
| **MCP Server** | Python | 8001 | Model Context Protocol, 14 tools | ✅ Active |
| **Airtable Gateway** | Python | 8002 | Airtable API wrapper, rate limiting | ✅ Active |
| **Auth Service** | Go | 8004 | Authentication and user management | ✅ Active |
| **User Service** | Go | 8005 | User profile and workspace mgmt | ✅ Active |
| **Workspace Service** | Go | 8006 | Multi-tenant workspace management | ✅ Active |
| **SAGA Orchestrator** | Python | 8008 | Distributed transaction coordination | ✅ Active |
| **API Gateway** | Go | 8000 | Central routing and load balancing | ⚠️ In Development |

### Infrastructure Services
- **PostgreSQL 16:** Primary database with advanced extensions
- **Redis 7:** Caching, sessions, pub/sub messaging
- **LGTM Stack:** Prometheus, Grafana, Loki monitoring

### Sprint 4 Accomplishments
- **10/10 Sprint Tasks Completed** - All major milestones achieved
- **8/12 Services Operational** - 67% of microservices architecture functional
- **Comprehensive E2E Test Suite** - Full integration testing framework
- **82,000 lines of duplicate code removed** - Major technical debt cleanup
- **Service Health Monitoring** - All operational services monitored and healthy

## 📚 Architecture Documentation
See project documentation files:
- Architecture: `COMPREHENSIVE_ARCHITECTURAL_REVIEW.md`
- Meeting Notes: `COMPREHENSIVE_ARCHITECT_MEETING_SUMMARY.md`
- Frontend Plan: `FRONTEND_ACTION_PLAN.md`
- Test Strategy: `TEST_SUITE_COMPLETION_SUMMARY.md`
- Deployment: `DEPLOYMENT_COMPLETION_SUMMARY.md`

## 🚀 Development

### Quick Start (Sprint 4 Architecture)
```bash
# Start minimal working stack (Sprint 4 validated)
docker-compose -f docker-compose.minimal.yml up -d --build

# Start all services including Go microservices
docker-compose -f docker-compose.yml up -d --build

# Run Sprint 4 E2E integration tests
python tests/integration/test_pyairtable_e2e_integration.py

# Run comprehensive health check
./scripts/test-health.sh

# Test core chat functionality
curl -X POST http://localhost:8003/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "List tables in my base", "session_id": "test"}'

# Stop all services
docker-compose down
```

### Service-Specific Commands
```bash
# Core AI services (Sprint 4 validated)
docker-compose logs -f llm-orchestrator mcp-server airtable-gateway

# Go microservices
docker-compose logs -f auth-service user-service workspace-service

# Infrastructure services
docker-compose logs -f postgres redis

# Check service health individually
curl http://localhost:8001/health  # MCP Server
curl http://localhost:8002/health  # Airtable Gateway  
curl http://localhost:8003/health  # LLM Orchestrator
```

## 🔗 Key Dependencies
- **Docker & Docker Compose:** Container orchestration
- **PostgreSQL 16:** Primary database with extensions (pgcrypto, uuid-ossp)
- **Redis 7:** Caching, sessions, pub/sub messaging
- **LGTM Stack:** Monitoring and observability
- **Next.js 15:** Frontend with TypeScript and Tailwind CSS

## 🧪 Testing

### Sprint 4 Test Suite
```bash
# Run Sprint 4 E2E integration tests (comprehensive)
python tests/integration/test_pyairtable_e2e_integration.py

# Run all available tests  
./tests/run-all-tests.sh

# Service health validation
python tests/utils/api_client.py --health-check

# Smoke tests (infrastructure validation)
./tests/smoke/basic-connectivity.sh
./tests/smoke/service-health.sh
./tests/smoke/database-connectivity.sh

# Integration tests (service communication)
./tests/integration/service-communication.sh
```

### Health Monitoring (Sprint 4 Services)
```bash
# Core AI services (Sprint 4 validated)
curl http://localhost:8001/health  # MCP Server
curl http://localhost:8002/health  # Airtable Gateway
curl http://localhost:8003/health  # LLM Orchestrator

# Go microservices
curl http://localhost:8004/health  # Auth Service
curl http://localhost:8005/health  # User Service
curl http://localhost:8006/health  # Workspace Service
curl http://localhost:8008/health  # SAGA Orchestrator

# Run comprehensive health check script
./scripts/health-check.sh
```

## 🔒 Environment Variables

### Core Configuration
```bash
# Airtable Integration
AIRTABLE_TOKEN=pat_xxx          # Airtable Personal Access Token
AIRTABLE_BASE=appXXXXXXXXX      # Default Airtable Base ID

# AI Services
GEMINI_API_KEY=xxx              # Google Gemini API key

# Database & Cache
POSTGRES_PASSWORD=xxx           # Strong database password
REDIS_PASSWORD=xxx              # Strong cache password

# Service Authentication
API_KEY=xxx                     # Internal service authentication
JWT_SECRET=xxx                  # JWT token signing secret

# Monitoring
ENABLE_METRICS=true             # Enable Prometheus metrics
LOG_LEVEL=INFO                  # Application log level
```

### Production Variables
```bash
# Security
HTTPS_ENABLED=true              # Force HTTPS
CORS_ORIGINS=https://yourdomain.com

# Performance
DB_POOL_SIZE=20                 # Database connection pool
REDIS_POOL_SIZE=10              # Redis connection pool
RATE_LIMIT_RPM=1000            # API rate limit per minute

# Observability
TRACING_ENABLED=true            # Distributed tracing
SENTRY_DSN=xxx                  # Error tracking
```

## 🚨 Sprint 4 Completion Status

### ✅ Sprint 4 Completed (10/10 Tasks)
- **End-to-End Integration Testing** - Comprehensive test suite implemented
- **8/12 Services Operational** - Core functionality verified and working
- **Technical Debt Cleanup** - 82,000 lines of duplicate code removed
- **Service Health Monitoring** - All services monitored with health checks
- **Go Microservices Architecture** - Auth, User, Workspace services operational
- **AI Pipeline Validation** - LLM + MCP + Airtable integration working
- **Database Integration** - PostgreSQL + Redis integration complete
- **Documentation Updates** - Architecture docs reflect current state

### 🚧 Next Sprint Priorities
- **API Gateway Completion** - Finish Go-based gateway implementation
- **Frontend Integration** - Connect UI with microservices architecture
- **Production Deployment** - Move from development to production environment
- **Monitoring Enhancement** - Complete LGTM stack integration

### ⚠️ Known Limitations
- **API Gateway:** In development, direct service access required
- **4/12 Services Inactive:** Some services still being developed
- **Frontend Authentication:** Needs integration with Go auth service

### 📋 Immediate Next Steps
1. Complete API Gateway Go implementation
2. Enable remaining 4 inactive services
3. Implement frontend authentication integration
4. Production deployment preparation

## 📊 Sprint 4 Performance Metrics
- **Sprint Completion:** 10/10 tasks completed (100%)
- **Service Operational Rate:** 8/12 services active (67%)
- **Code Cleanup:** 82,000 lines of duplicate code removed
- **Test Coverage:** Comprehensive E2E integration tests implemented
- **Service Health:** 8/8 active services operational and monitored
- **Architecture Stability:** Microservices communication validated
- **AI Pipeline:** LLM → MCP → Airtable flow working end-to-end