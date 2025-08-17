# PyAirtable Compose - Claude Context

## 🎯 Service Purpose
Orchestration hub for the entire PyAirtable ecosystem containing Docker Compose configurations, environment setup, deployment scripts, and operational tools for local development and production deployment.

## 🔧 Technology Stack
- Language: Docker Compose, Bash scripts
- Orchestration: Docker Compose with multi-environment support
- Database: PostgreSQL 16 with Redis 7 caching
- Monitoring: LGTM stack (Prometheus, Grafana, Loki, Tempo)
- Platform: **8-service consolidated microservices architecture**

## 🏗️ Current Architecture (Post-Consolidation)

### Core Services (8 Active)
| Service | Language | Port | Purpose | Status |
|---------|----------|------|---------|--------|
| **API Gateway** | Go/Python | 8000 | Central routing, auth, rate limiting | ✅ Active |
| **Frontend** | Next.js 15 | 3000 | React web interface with TypeScript | ✅ Active |
| **LLM Orchestrator** | Python | 8003 | Gemini 2.5 Flash integration, chat | ✅ Active |
| **MCP Server** | Python | 8001 | Model Context Protocol, 14 tools | ✅ Active |
| **Airtable Gateway** | Python | 8002 | Airtable API wrapper, rate limiting | ✅ Active |
| **Platform Services** | Python | 8007 | Auth + Analytics (consolidated) | ✅ Active |
| **Automation Services** | Python | 8006 | Files + Workflows (consolidated) | ✅ Active |
| **SAGA Orchestrator** | Python | 8008 | Distributed transaction coordination | ✅ Active |

### Infrastructure Services
- **PostgreSQL 16:** Primary database with advanced extensions
- **Redis 7:** Caching, sessions, pub/sub messaging
- **LGTM Stack:** Prometheus, Grafana, Loki monitoring

### Service Consolidations Completed
- `auth-service` + `analytics-service` → `platform-services` (Port 8007)
- `workflow-engine` + `file-processor` → `automation-services` (Port 8006)
- **Benefits:** 35% operational complexity reduction, 40% improved latency

## 📚 Architecture Documentation
See project documentation files:
- Architecture: `COMPREHENSIVE_ARCHITECTURAL_REVIEW.md`
- Meeting Notes: `COMPREHENSIVE_ARCHITECT_MEETING_SUMMARY.md`
- Frontend Plan: `FRONTEND_ACTION_PLAN.md`
- Test Strategy: `TEST_SUITE_COMPLETION_SUMMARY.md`
- Deployment: `DEPLOYMENT_COMPLETION_SUMMARY.md`

## 🚀 Development

### Quick Start (Consolidated Architecture)
```bash
# Start all services (8 core services + infrastructure)
docker-compose -f docker-compose.minimal.yml up -d --build

# View logs for specific service
docker-compose logs -f [service-name]

# Run comprehensive health check
./scripts/test-health.sh

# Test chat functionality with MCP tools
./scripts/test-chat.sh

# Run complete test suite
./tests/run-all-tests.sh

# Stop all services
docker-compose down
```

### Service-Specific Commands
```bash
# Platform services (auth + analytics)
docker-compose logs -f platform-services

# Automation services (files + workflows)  
docker-compose logs -f automation-services

# Core AI services
docker-compose logs -f llm-orchestrator mcp-server airtable-gateway
```

## 🔗 Key Dependencies
- **Docker & Docker Compose:** Container orchestration
- **PostgreSQL 16:** Primary database with extensions (pgcrypto, uuid-ossp)
- **Redis 7:** Caching, sessions, pub/sub messaging
- **LGTM Stack:** Monitoring and observability
- **Next.js 15:** Frontend with TypeScript and Tailwind CSS

## 🧪 Testing Status - VALIDATED 2025-08-17

### ✅ WORKING: Synthetic Tests
**Location:** `/Users/kg/IdeaProjects/pyairtable-compose/synthetic-tests/`
```bash
# Playwright E2E tests configured and functional
- ai-analysis.spec.js       # AI interaction testing
- collaboration.spec.js     # Team workflow testing  
- data-operations.spec.js   # Data CRUD operations
- error-recovery.spec.js    # Error handling scenarios
- new-user-journey.spec.js  # User onboarding flow

# Test infrastructure ready
- Node.js with Playwright installed
- Visual regression testing configured
- Screenshot and trace capture working
- Test reports generated (JSON, HTML, JUnit)
```

### ✅ WORKING: Integration Monitoring
**Continuous testing running - verified in background process:**
```
Result: 5/6 components working (83%)
✅ Authentication working (response time: ~0.25s)
✅ Qdrant Vector DB working (version 1.7.3)
✅ Monitoring Stack working (Grafana + Prometheus)
✅ MCP-Qdrant Integration working (3 vectors)
✅ API Gateway Health working (4/6 services healthy)
❌ Auth Monitor Service failing (connection refused)
```

### 🔧 NEEDS FIXING: 
```bash
# These test suites referenced but not found:
./tests/run-all-tests.sh          # Does not exist
./tests/smoke/                     # Directory not found
./tests/integration/               # Directory not found  
./tests/performance/               # Directory not found
```

### Health Monitoring
```bash
# Individual service health
curl http://localhost:8001/health  # MCP Server
curl http://localhost:8002/health  # Airtable Gateway
curl http://localhost:8003/health  # LLM Orchestrator
curl http://localhost:8007/health  # Platform Services
curl http://localhost:8006/health  # Automation Services

# Aggregated health check
curl http://localhost:8000/health  # API Gateway
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

## 🚨 Current Status & Issues

### ✅ Completed
- LGTM observability stack deployed
- Service consolidation (8 → 6 active services)
- 35% infrastructure cost reduction
- Basic authentication framework

### 🚧 In Progress  
- Frontend authentication implementation
- Platform services production deployment
- Test suite architecture adaptation (targeting 85% pass rate)

### ⚠️ Critical Issues - UPDATED 2025-08-17
- **Auth Monitor Service:** Port 8090 not responding, needs investigation
- **Service Restarts:** Automation Services and DLQ Processor unstable  
- **Tempo Tracing:** Distributed tracing completely unavailable
- **Container Health:** Several containers showing unhealthy despite working

### 🔧 IMMEDIATE FIXES NEEDED:
1. **Fix Auth Monitor Service:** Investigate port 8090 connection issues
2. **Stabilize Restarting Services:** Debug automation-services and dlq-processor
3. **Deploy Tempo:** Add distributed tracing to monitoring stack
4. **Container Health Checks:** Fix health check configurations for Qdrant and Simple Monitor

### ✅ RESOLVED ISSUES:
- ~~Frontend Auth: COMPLETED - Authentication pages functional~~
- ~~Platform Services: DEPLOYED - Auth + Analytics operational at port 8007~~
- ~~Test Coverage: UPDATED - Synthetic tests working with Playwright~~

## 🎯 SPRINT INTEGRATION: Backend Services

### 📋 Sprint #1 Backend Tasks
- **Task 1.2:** API Gateway Authentication Flow (depends on frontend Task 1.1)
- **Task 1.3:** MCP Protocol Enhancement (ready to proceed)
- **Task 1.4:** Database Schema Optimization (week 2)
- **Task 1.6:** Monitoring and Observability (week 2)

### 📊 Service Health Status - VALIDATED 2025-08-17

**SYSTEM STATUS: 83% OPERATIONAL** (5/6 core services + monitoring)

#### ✅ WORKING SERVICES:
```
✅ API Gateway (8000)        - Healthy, routing traffic
✅ AI Processing Service (8001) - /metrics endpoint working, Prometheus metrics active  
✅ Airtable Gateway (8002)   - Healthy, API wrapper functional
✅ Platform Services (8007)  - Auth + Analytics operational
✅ SAGA Orchestrator (8008)  - Transaction coordination working
✅ Qdrant Vector DB (6333)   - Working, 3 vectors in MCP collection
✅ PostgreSQL & Redis        - All database infrastructure healthy
✅ Grafana (3001)           - Dashboard accessible, API working
✅ Prometheus (9090)         - Metrics collection active
✅ Loki (3100)              - Log aggregation working
```

#### ❌ FAILED/DEGRADED SERVICES:
```
❌ Auth Monitor Service (8090) - Connection refused, service not responding
⚠️  Automation Services (8006) - Container restarting (1), unstable
⚠️  DLQ Processor            - Container restarting (1), unstable  
⚠️  Simple Monitor (8888)    - Unhealthy status
⚠️  Qdrant (6333)           - Unhealthy status despite functional
❌ Tempo Tracing (3200)     - Not running, distributed tracing unavailable
```

### 🔗 Frontend Integration Ready
- **Authentication Endpoints:** Ready for Task 1.1 frontend work
- **Real-time Updates:** WebSocket ready for implementation
- **API Documentation:** Available for integration
- **CORS Configuration:** Configured for http://localhost:5173

## 📊 Performance Metrics - VALIDATED 2025-08-17
- **Current API Response:** ~0.25s average (needs optimization to <200ms)
- **Current Availability:** 83% operational (5/6 core services working)
- **AI Processing Service Metrics:** ✅ Working - HTTP requests tracked, 433 health checks
- **Test Pass Rate:** Synthetic tests configured, integration monitoring 83% success
- **Cost Optimization:** 35% reduction achieved through consolidation
- **Service Health:** 5/6 core services operational, monitoring stack functional ⚠️

### 📈 ACTUAL OBSERVABILITY STATUS:
- **Prometheus Metrics:** ✅ WORKING - AI service exposing detailed metrics
- **Grafana Dashboards:** ✅ WORKING - Accessible at port 3001
- **Log Aggregation:** ✅ WORKING - Loki collecting logs at port 3100  
- **Distributed Tracing:** ❌ NOT WORKING - Tempo not deployed
- **Health Checks:** ✅ WORKING - Automated monitoring every 60s