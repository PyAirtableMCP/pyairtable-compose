# SPRINT 3: MONOREPO CLEANUP & CONSOLIDATION PLAN

**Sprint Duration**: 2 weeks  
**Sprint Goal**: Clean up the monorepo mess and consolidate to 16 working core services  
**Reality Check**: We have 36 service directories but only 5 services actually running

---

## CURRENT STATE ANALYSIS

### What We Actually Have
- **1 monorepo** with everything in `/Users/kg/IdeaProjects/pyairtable-compose`
- **36 service directories** scattered across go-services/, python-services/, frontend-services/
- **5 services running** in Docker (api-gateway, platform-services, llm-orchestrator, mcp-server, airtable-gateway)
- **Archived-experiments directory** with 36+ failed experiments
- **Massive duplication** (3 AI services, 2 file services, etc.)

### Sprint 3 Focus Areas
1. **CLEANUP**: Delete dead code and failed experiments
2. **CONSOLIDATION**: Merge duplicate services
3. **STANDARDIZATION**: Make remaining services consistent
4. **DOCUMENTATION**: Align docs with reality

---

## SPRINT 3 BACKLOG

### Epic 1: Repository Cleanup (Week 1)
**Goal**: Remove 20+ unnecessary directories and failed experiments

#### Story 1.1: Delete Archived Experiments
- **Task**: Remove `/archived-experiments/` directory entirely
- **Impact**: Free up space, reduce confusion
- **Estimate**: 1 day
- **Assignee**: DevOps Agent
- **Acceptance Criteria**: 
  - Directory deleted from repo
  - No references in docker-compose files
  - Git history preserved

#### Story 1.2: Remove Empty/Broken Service Directories
- **Task**: Delete non-functional services from go-services/
- **Services to Remove**:
  - mobile-bff (empty)
  - web-bff (empty) 
  - plugin-service (not needed)
  - pyairtable-platform (failed)
  - frontend-integration (empty)
  - graphql-gateway (unused)
- **Estimate**: 2 days
- **Assignee**: Backend Agent

#### Story 1.3: Remove Duplicate Python Services
- **Task**: Delete redundant python services
- **Services to Remove**:
  - formula-engine (not needed)
  - schema-service (empty)
- **Estimate**: 1 day
- **Assignee**: Python Agent

#### Story 1.4: Clean Frontend Services
- **Task**: Remove unused frontend directories
- **Services to Remove**:
  - mobile-app (empty)
  - developer-portal (empty)
- **Keep**: tenant-dashboard, admin-portal
- **Estimate**: 1 day
- **Assignee**: Frontend Agent

### Epic 2: Service Consolidation (Week 1-2)
**Goal**: Merge duplicate functionality into core services

#### Story 2.1: Consolidate File Services
- **Task**: Merge file-processing-service into file-service
- **Rationale**: Both handle file operations
- **Actions**:
  - Move processing logic to file-service
  - Update docker-compose references
  - Test merged functionality
- **Estimate**: 3 days
- **Assignee**: Backend Agent

#### Story 2.2: Consolidate AI Services
- **Task**: Merge ai-service, embedding-service, semantic-search into llm-orchestrator
- **Rationale**: All AI-related, reduce complexity
- **Actions**:
  - Move embedding logic to llm-orchestrator
  - Consolidate semantic search
  - Update API endpoints
  - Test AI workflows end-to-end
- **Estimate**: 4 days
- **Assignee**: AI Agent

#### Story 2.3: Consolidate Communication Services
- **Task**: Merge chat-service into workflow-engine
- **Rationale**: Chat is part of workflow collaboration
- **Actions**:
  - Move chat handlers to workflow-engine
  - Update WebSocket connections
  - Test real-time features
- **Estimate**: 3 days
- **Assignee**: Python Agent

### Epic 3: Service Standardization (Week 2)
**Goal**: Make remaining 16 services consistent and functional

#### Story 3.1: Standardize Go Services Structure
- **Task**: Ensure all 8 Go services follow same structure
- **Services**: api-gateway, auth-service, user-service, workspace-service, file-service, notification-service, webhook-service, permission-service
- **Standard Structure**:
  ```
  service-name/
  ├── cmd/main.go
  ├── internal/
  ├── pkg/
  ├── Dockerfile
  ├── Makefile
  ├── README.md
  └── docker-compose.yml
  ```
- **Estimate**: 4 days
- **Assignee**: Backend Agent

#### Story 3.2: Standardize Python Services Structure
- **Task**: Ensure all 6 Python services follow same structure
- **Services**: airtable-gateway, llm-orchestrator, mcp-server, workflow-engine, analytics-service, audit-service
- **Standard Structure**:
  ```
  service-name/
  ├── src/
  ├── tests/
  ├── requirements.txt
  ├── Dockerfile
  ├── README.md
  └── docker-compose.yml
  ```
- **Estimate**: 3 days
- **Assignee**: Python Agent

#### Story 3.3: Fix Docker Compose Configuration
- **Task**: Update docker-compose.yml to reflect 16 core services only
- **Actions**:
  - Remove references to deleted services
  - Ensure all 16 services can start
  - Test service connectivity
  - Document port assignments
- **Estimate**: 2 days
- **Assignee**: DevOps Agent

### Epic 4: Documentation Alignment (Week 2)
**Goal**: Make documentation match monorepo reality

#### Story 4.1: Update Service Documentation
- **Task**: Rewrite README files to reflect monorepo architecture
- **Actions**:
  - Update main README.md
  - Rewrite service-specific READMEs
  - Remove microservice fiction
  - Document actual deployment process
- **Estimate**: 2 days
- **Assignee**: Documentation Agent

#### Story 4.2: Create Accurate Architecture Diagrams
- **Task**: Create diagrams showing actual monorepo structure
- **Deliverables**:
  - Service dependency diagram
  - Data flow diagrams
  - Deployment architecture
- **Estimate**: 2 days
- **Assignee**: Product Manager

---

## FINAL 16-SERVICE ARCHITECTURE

### Go Services (8)
1. **api-gateway** - Main API entry point
2. **auth-service** - Authentication & JWT
3. **user-service** - User management
4. **workspace-service** - Tenant/workspace management
5. **file-service** - File uploads & processing (consolidated)
6. **notification-service** - Email/SMS/push notifications
7. **webhook-service** - External webhook handling
8. **permission-service** - Authorization & RBAC

### Python Services (6)
1. **airtable-gateway** - Airtable API integration
2. **llm-orchestrator** - AI coordination (consolidated with embeddings & search)
3. **mcp-server** - Model Context Protocol
4. **workflow-engine** - Business workflows (consolidated with chat)
5. **analytics-service** - Analytics & reporting
6. **audit-service** - Audit logging & compliance

### Frontend Services (2)
1. **tenant-dashboard** - Main user interface
2. **admin-portal** - Administrative interface

---

## DEFINITION OF DONE

### Sprint Success Criteria
- [ ] Repository reduced from 36 to 16 service directories
- [ ] All 5 currently running services still work
- [ ] Docker Compose starts all 16 core services
- [ ] No broken references in codebase
- [ ] Documentation reflects actual architecture
- [ ] End-to-end test suite passes

### Technical Acceptance Criteria
- [ ] `docker-compose up` starts cleanly
- [ ] API Gateway routes to all services
- [ ] Health checks pass for all services
- [ ] Database migrations work
- [ ] No dead code or broken imports
- [ ] All services follow standardized structure

---

## RISK MITIGATION

### High Risks
1. **Service Dependencies**: Breaking existing integrations during consolidation
   - **Mitigation**: Test each consolidation step thoroughly
   - **Rollback Plan**: Keep feature branches for each merge

2. **Data Loss**: Accidentally deleting important code
   - **Mitigation**: Create backup branches before major deletions
   - **Validation**: Code review all deletion PRs

3. **Docker Complexity**: Services not starting after changes
   - **Mitigation**: Test docker-compose after each change
   - **Monitoring**: Set up health check automation

### Medium Risks
1. **Documentation Gaps**: Missing important setup steps
   - **Mitigation**: Test documentation with fresh environment
   - **Validation**: Have team members follow updated docs

---

## TEAM ASSIGNMENTS

### Week 1 Focus: Cleanup
- **Backend Agent**: Remove go-services directories, test core services
- **Python Agent**: Remove python-services directories, test AI workflows  
- **DevOps Agent**: Archive experiments, update Docker configs
- **Frontend Agent**: Clean frontend services, test UI connectivity

### Week 2 Focus: Consolidation & Standardization
- **Backend Agent**: Standardize Go services, merge file services
- **Python Agent**: Consolidate AI services, standardize Python structure
- **DevOps Agent**: Fix Docker Compose, test all services together
- **Product Manager**: Update documentation, create architecture diagrams

---

## SUCCESS METRICS

### Quantitative Goals
- **Reduce** service directories from 36 to 16 (56% reduction)
- **Increase** running services from 5 to 16 (220% improvement)
- **Eliminate** 100% of duplicate functionality
- **Achieve** 100% Docker startup success rate

### Qualitative Goals
- **Clarity**: Team understands actual architecture
- **Maintainability**: Consistent service structure
- **Honesty**: Documentation matches reality
- **Focus**: Clear path to production deployment

---

## POST-SPRINT OUTCOMES

### Immediate Benefits
- Clean, maintainable monorepo
- 16 consistently structured services
- Accurate documentation
- Faster development cycles

### Foundation for Sprint 4
- Service-to-service communication
- API standardization
- Production deployment
- Monitoring & observability

---

**This is a realistic plan based on our actual monorepo structure. No microservice fantasy, just honest cleanup and consolidation work.**