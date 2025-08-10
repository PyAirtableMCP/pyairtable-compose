# Claude Memory System - Context Preservation Framework

**Version:** 1.0  
**Created:** August 9, 2025  
**Purpose:** Sustainable context management for PyAirtable ecosystem development

---

## 🧠 SYSTEM PURPOSE

This document implements Anthropic's recommended practices for large project context management, preventing the context loss that has been plaguing PyAirtable development. It serves as the **single source of truth** for architectural decisions and development state.

**Research Foundation:** Based on Claude Code best practices from Anthropic engineering team, developer community patterns, and production usage insights from 2024-2025.

---

## 📋 CONTEXT PRESERVATION STRATEGIES

### 1. Primary Context Files

#### 1.1 Master Documents (Repository Root)
- **`CLAUDE_MEMORY_SYSTEM.md`** (this file) - Context preservation framework
- **`REPOSITORY_CATALOG.md`** - Complete repository index with purposes
- **`SERVICE_ARCHITECTURE_ACTUAL.md`** - Real current state (not aspirational)  
- **`KANBAN_BOARD.md`** - Prioritized task management
- **`QUICK_WINS.md`** - Immediately actionable improvements

#### 1.2 Service-Level Context Files
Each service directory must contain:
- **`claude.md`** - Service-specific context, current status, key commands
- **`README.md`** - User-facing documentation
- **`DEPLOYMENT_STATUS.md`** - Current deployment state and health

#### 1.3 Session Artifacts
- **Meeting notes** - Architectural decisions and rationale
- **Task completion reports** - What was accomplished per session
- **Test execution summaries** - Verification of implementations

### 2. Session Management Protocol

#### 2.1 Session Start Checklist
1. **Read master context** - Review `CLAUDE_MEMORY_SYSTEM.md`
2. **Check current task** - Review `KANBAN_BOARD.md`
3. **Verify service status** - Run health checks
4. **Load service context** - Read relevant `claude.md` files

#### 2.2 Session End Checklist
1. **Update completion status** - Mark tasks completed in KANBAN_BOARD.md
2. **Document decisions** - Update relevant context files
3. **Create session summary** - Brief accomplishments and next steps
4. **Update service status** - Refresh claude.md files

#### 2.3 Context Clearing Strategy
- Use `/clear` command between major tasks
- Start fresh sessions for different architectural domains
- Keep conversations focused on single objectives

### 3. Multi-Agent Development Pattern

Based on the "3 Amigo Agents" pattern from production usage:

#### 3.1 Agent Roles
- **Architecture Agent** - High-level design, system integration, documentation
- **Implementation Agent** - Code development, service creation, testing
- **Validation Agent** - Quality assurance, end-to-end testing, monitoring

#### 3.2 Agent Handoff Protocol
Each agent creates a **handoff document** containing:
- Current system state
- Completed work summary
- Next agent's task definition
- Success criteria
- Relevant file locations

---

## 🗂️ REPOSITORY ORGANIZATION

### Current Repository Structure (ACTUAL)
```
/Users/kg/IdeaProjects/pyairtable-compose/
├── CLAUDE_MEMORY_SYSTEM.md         # Master context (this file)
├── REPOSITORY_CATALOG.md           # Repository index
├── SERVICE_ARCHITECTURE_ACTUAL.md  # Current state documentation
├── KANBAN_BOARD.md                 # Task management
├── QUICK_WINS.md                   # Immediate improvements
├── docker-compose*.yml             # Service orchestration
├── go-services/                    # Go microservices (aspirational)
├── frontend-services/              # Next.js applications  
├── python-services/                # Python microservices (missing)
├── k8s/                           # Kubernetes manifests
├── monitoring/                     # Observability stack
├── infrastructure/                 # Terraform and deployment
└── tests/                         # Testing frameworks
```

### Service Catalog (CURRENT REALITY)

| Service | Technology | Status | Port | Location | Context File |
|---------|------------|--------|------|----------|--------------|
| **PostgreSQL** | PostgreSQL 16 | ✅ RUNNING | 5433 | Docker | N/A |
| **Redis** | Redis 7 | ✅ RUNNING | 6380 | Docker | N/A |
| **Airtable Gateway** | Python/FastAPI | ❌ UNHEALTHY | 7002 | Docker | Missing |
| **Platform Services** | Python/FastAPI | ❌ UNHEALTHY | 7007 | Docker | Missing |
| **API Gateway** | Go/Python | ❌ NOT RUNNING | 8000 | Not deployed | Missing |
| **Frontend** | Next.js 15 | ❌ NOT RUNNING | 3000 | Not deployed | Missing |
| **LLM Orchestrator** | Python | ❌ NOT RUNNING | 8003 | Not deployed | Missing |
| **MCP Server** | Python | ❌ NOT RUNNING | 8001 | Not deployed | Missing |

**SERVICE AVAILABILITY: 25% (2/8 services operational)**

---

## 📊 CURRENT SYSTEM STATE

### Infrastructure Status
- **Database:** PostgreSQL 16 - HEALTHY
- **Cache:** Redis 7 - HEALTHY  
- **Container Runtime:** Docker Compose - ACTIVE
- **Orchestration:** Local development environment

### Service Health (VERIFIED August 9, 2025)
```bash
# Infrastructure Services
✅ postgres:16-alpine     - Port 5433 (HEALTHY)
✅ redis:7-alpine         - Port 6380 (HEALTHY)

# Application Services  
❌ airtable-gateway       - Port 7002 (UNHEALTHY - API key issues)
❌ platform-services      - Port 7007 (UNHEALTHY - service errors)
❌ api-gateway           - NOT RUNNING
❌ frontend              - NOT RUNNING  
❌ llm-orchestrator      - NOT RUNNING
❌ mcp-server           - NOT RUNNING
```

### Integration Points
- **Database Connections:** 2 services configured, 0 healthy
- **Service Mesh:** Not implemented
- **API Gateway:** Not running
- **Load Balancing:** Not configured
- **Health Monitoring:** Basic Docker health checks only

---

## 🎯 TASK ATOMICITY FRAMEWORK

### Task Definition Template
```markdown
## Task: [CLEAR SINGLE OBJECTIVE]

**Scope:** [Specific service or component]
**Technology:** [Primary tech stack]
**Duration Estimate:** [1-4 hours max]
**Prerequisites:** [Required completed tasks]

### Success Criteria
1. [Specific measurable outcome 1]
2. [Specific measurable outcome 2]  
3. [Specific measurable outcome 3]

### Files to Modify
- [Exact file paths]

### Test Commands
- [Commands to verify success]

### Handoff to Next Session
- [What the next agent needs to know]
```

### Task Categories
1. **Infrastructure Tasks** - Docker, networking, databases
2. **Service Implementation** - Individual microservice development
3. **Integration Tasks** - Service-to-service communication
4. **Frontend Tasks** - User interface development
5. **Testing Tasks** - Validation and quality assurance

---

## 🔄 SESSION WORKFLOW

### 1. Session Initialization
```bash
# Read current system state
cat CLAUDE_MEMORY_SYSTEM.md
cat KANBAN_BOARD.md

# Check service status
docker-compose ps
curl http://localhost:8000/health || echo "API Gateway not running"
```

### 2. Task Execution
- Focus on single atomic task from KANBAN_BOARD.md
- Update progress in real-time
- Document any architectural decisions made
- Create or update service claude.md files

### 3. Session Completion
```bash
# Update task status
# Document completion in session summary
# Update service health status  
# Create handoff for next session
```

---

## 🚀 QUICK COMMANDS REFERENCE

### Health Check Commands
```bash
# Overall system status
docker-compose ps

# Service-specific health
curl http://localhost:8000/health  # API Gateway
curl http://localhost:8001/health  # MCP Server  
curl http://localhost:8002/health  # Airtable Gateway
curl http://localhost:8003/health  # LLM Orchestrator

# Database connectivity
docker-compose exec postgres psql -U pyairtable -d pyairtable -c "SELECT version();"

# Redis connectivity  
docker-compose exec redis redis-cli ping
```

### Service Management  
```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f [service-name]

# Restart specific service
docker-compose restart [service-name]

# Health check all services
./scripts/health-check.sh
```

### Development Workflow
```bash
# Start development session
./scripts/dev-start.sh

# Run tests
./tests/run-all-tests.sh

# Deploy changes
./scripts/deploy-local.sh
```

---

## 📈 SUCCESS METRICS

### Context Preservation Success
- ✅ **Consistency:** No contradictory documentation across sessions
- ✅ **Continuity:** Clear task progression without context loss
- ✅ **Clarity:** Single source of truth for all architectural decisions
- ✅ **Completeness:** All system state documented and current

### Technical Metrics
- **Current Service Availability:** 25% (2/8 services)
- **Target Service Availability:** 80% (6/8 services)
- **Infrastructure Reliability:** 100% (database + cache operational)
- **Integration Success Rate:** 0% (no services communicating)

### Development Velocity
- **Task Completion Rate:** Track in KANBAN_BOARD.md
- **Session Efficiency:** Measure against atomic task definitions
- **Context Switch Time:** Time to orient in new sessions
- **Documentation Currency:** How current the system state documentation is

---

## 🔧 TROUBLESHOOTING GUIDE

### Common Context Loss Scenarios
1. **Session starts without orientation** → Read CLAUDE_MEMORY_SYSTEM.md first
2. **Contradictory service information** → Update SERVICE_ARCHITECTURE_ACTUAL.md  
3. **Unclear next steps** → Review KANBAN_BOARD.md
4. **Service status unknown** → Run health check commands

### System Recovery Steps
1. **Full system restart:** `docker-compose down && docker-compose up -d`
2. **Context file regeneration:** Use health checks to update actual status
3. **Task queue reset:** Prioritize based on current system state
4. **Documentation sync:** Ensure all context files reflect reality

---

## 📝 MAINTENANCE PROTOCOL

### Daily Maintenance
- [ ] Update SERVICE_ARCHITECTURE_ACTUAL.md with current service status
- [ ] Review and prioritize KANBAN_BOARD.md
- [ ] Update service claude.md files with any changes

### Weekly Maintenance  
- [ ] Audit all context files for accuracy
- [ ] Review session summaries for pattern identification
- [ ] Update success metrics and progress tracking
- [ ] Archive completed tasks and create new priorities

### Emergency Procedures
- **Context Corruption:** Restore from meeting notes and session summaries
- **Service Failure Cascade:** Follow SERVICE_ARCHITECTURE_ACTUAL.md recovery procedures
- **Documentation Drift:** Run system health checks and update all files

---

## 🎯 IMPLEMENTATION ROADMAP

### Phase 1: Context System (Current Session)
- [x] Create CLAUDE_MEMORY_SYSTEM.md
- [ ] Create REPOSITORY_CATALOG.md  
- [ ] Create SERVICE_ARCHITECTURE_ACTUAL.md
- [ ] Create KANBAN_BOARD.md
- [ ] Create QUICK_WINS.md

### Phase 2: Infrastructure Stabilization (Next Session)
- [ ] Fix docker-compose service configurations
- [ ] Implement service health checks
- [ ] Standardize port mappings (8000-8008)
- [ ] Create service startup orchestration

### Phase 3: Service Implementation (Subsequent Sessions)
- [ ] Deploy API Gateway (Go)
- [ ] Fix Airtable Gateway integration  
- [ ] Deploy Frontend application
- [ ] Implement LLM Orchestrator
- [ ] Complete MCP Server integration

---

**Last Updated:** August 9, 2025  
**Next Review:** After infrastructure stabilization completion  
**Owner:** Solutions Architect (Claude Code sessions)  
**Status:** ACTIVE - Core context preservation system

---

*This document is the foundation of sustainable PyAirtable development. All architectural decisions, session planning, and progress tracking should reference and update this system.*