# PyAirtableMCP Organization Cleanup - Parallel Claude Sessions Plan

## 🔍 Current Reality Check

### What We Found:
- **Only 5 repositories exist** in PyAirtableMCP org (not 14 as thought)
- **9 core services are MISSING** from the organization
- **pyairtable-compose cleanup** is on local branch `cleanup-massive-mess-20250810` (NOT merged)
- **Massive gaps** in repository organization

### The 5 Existing Repos:
1. `pyairtable-compose` - Docker orchestration (CLEANED locally, not pushed)
2. `pyairtable-common` - Shared Python library
3. `pyairtable-frontend` - Next.js frontend
4. `pyairtable-tenant-service-go` - Go tenant service
5. `pyairtable-docs` - Documentation (private)

### The 9 MISSING Core Services:
These exist as folders in pyairtable-compose but need extraction:
1. API Gateway
2. Authentication Service
3. Airtable Gateway
4. LLM Orchestrator
5. MCP Server
6. Platform Services
7. Automation Services
8. SAGA Orchestrator
9. Tenant Dashboard

## 🚀 Parallel Claude Sessions Strategy

### Session 0: Push Current Cleanup (Do First!)
**1 Claude Session - IMMEDIATE**
```bash
# In pyairtable-compose repo
git push origin cleanup-massive-mess-20250810
# Create PR and merge the 6.4GB → 716MB cleanup
```

### Wave 1: Core Service Extraction (3 Parallel Sessions)
Start these **simultaneously** after Session 0:

**Session 1: API & Auth Services**
- Extract `api-gateway` → new repo
- Extract `auth-service` → new repo
- Story Points: 16
- Duration: ~3 hours

**Session 2: Airtable & MCP Services**
- Extract `airtable-gateway` → new repo
- Extract `mcp-server` → new repo
- Story Points: 21
- Duration: ~4 hours

**Session 3: LLM & Platform Services**
- Extract `llm-orchestrator` → new repo
- Extract `platform-services` → new repo
- Story Points: 26
- Duration: ~4 hours

### Wave 2: Secondary Services (2 Parallel Sessions)
Start after Wave 1 completes:

**Session 4: Automation & SAGA**
- Extract `automation-services` → new repo
- Extract `saga-orchestrator` → new repo
- Story Points: 16
- Duration: ~3 hours

**Session 5: Frontend Consolidation**
- Merge `pyairtable-frontend` with `tenant-dashboard`
- Clean admin dashboard
- Story Points: 21
- Duration: ~4 hours

### Wave 3: Documentation & Standardization (2 Parallel Sessions)

**Session 6: Documentation Migration**
- Move 129 docs from `docs-to-migrate/` to `pyairtable-docs`
- Create architecture documentation
- Story Points: 13
- Duration: ~2 hours

**Session 7: Naming & Standards**
- Rename repositories to consistent naming
- Update all docker-compose references
- Create repository standards
- Story Points: 8
- Duration: ~2 hours

## 📊 Total Resource Requirements

| Metric | Value |
|--------|-------|
| **Total Claude Sessions** | 8 sessions (1 immediate + 7 cleanup) |
| **Can Run in Parallel** | Wave 1: 3 sessions, Wave 2: 2 sessions, Wave 3: 2 sessions |
| **Minimum Time (with parallel)** | ~8 hours |
| **Sequential Time (no parallel)** | ~24 hours |
| **Story Points Total** | 105 points |

## 🎯 Execution Plan

### Day 1 (Today):
1. **Session 0** (30 min): Push and merge current cleanup
2. **Wave 1** (4 hours): Start 3 parallel sessions for core services

### Day 2:
3. **Wave 2** (4 hours): Start 2 parallel sessions for secondary services
4. **Wave 3** (2 hours): Start 2 parallel sessions for docs/standards

## ⚠️ Critical Actions Before Starting

1. **MERGE THE CURRENT CLEANUP FIRST**
   ```bash
   cd /Users/kg/IdeaProjects/pyairtable-compose
   git push origin cleanup-massive-mess-20250810
   # Create PR on GitHub
   # Merge to main
   ```

2. **Create GitHub repos for the 9 missing services**:
   - pyairtable-api-gateway
   - pyairtable-auth-service
   - pyairtable-airtable-gateway
   - pyairtable-llm-orchestrator
   - pyairtable-mcp-server
   - pyairtable-platform-services
   - pyairtable-automation-services
   - pyairtable-saga-orchestrator
   - pyairtable-tenant-dashboard

3. **Give all Claude sessions this context**:
   - Link to this plan
   - Access to pyairtable-compose repo
   - GitHub org credentials

## 🏁 Success Criteria

After all sessions complete:
- ✅ 14 properly organized repositories (from current 5)
- ✅ No service code in pyairtable-compose (only docker configs)
- ✅ All documentation in pyairtable-docs
- ✅ Consistent naming: `pyairtable-[service-name]`
- ✅ Each service has own CI/CD pipeline
- ✅ Docker-compose references updated repos

## 💡 Pro Tips for Parallel Sessions

1. **Use different branch names** in each session to avoid conflicts
2. **Focus each session** on its specific services only
3. **Document dependencies** between services clearly
4. **Test extraction** by building Docker images from new repos
5. **Update docker-compose** only after all extractions complete

## 🔴 IMPORTANT: Start with Session 0!

The current cleanup (6.4GB → 716MB) is sitting on a local branch and needs to be pushed and merged BEFORE starting the parallel extraction sessions. This is critical as all other work depends on the cleaned structure.