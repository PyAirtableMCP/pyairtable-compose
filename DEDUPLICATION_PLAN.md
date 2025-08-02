# PyAirtable Deduplication and Repository Organization Plan

## 🚨 CRITICAL DUPLICATES FOUND

### 1. API Gateway - TRIPLE IMPLEMENTATION
- `./pyairtable-infrastructure/pyairtable-api-gateway-go/` (existing)
- `./go-services/cmd/api-gateway/` (new)
- `./go-services/api-gateway/` (new template)

**Resolution**: Keep `go-services/api-gateway/` as it's the most complete

### 2. Auth Service - DUPLICATE IMPLEMENTATION
- `./pyairtable-infrastructure/pyairtable-auth-service-go/` (existing, comprehensive)
- `./go-services/auth-service/` (new template)

**Resolution**: Keep existing `pyairtable-auth-service-go` as it has OAuth, audit, and full implementation

### 3. Multiple Docker Compose Files (25+ files!)
- `docker-compose.yml` (main)
- `docker-compose.all-services.yml` (new complete)
- Individual service docker-compose files

**Resolution**: Consolidate to 3 files: main, dev, and test

### 4. Documentation Scattered (12+ architecture docs)
- Multiple migration plans
- Conflicting architecture decisions
- Duplicate runbooks

**Resolution**: Move ALL to new `pyairtable-docs` repository

## 📁 NEW REPOSITORY STRUCTURE

### Phase 1: Create Core Repositories (Week 1)

```bash
# 1. Documentation Repository
pyairtable-docs/
├── architecture/
├── migration/
├── runbooks/
├── api-specs/
└── progress/

# 2. Shared Libraries Repository  
pyairtable-shared/
├── go-shared/
├── python-shared/
└── proto/

# 3. Infrastructure Repository
pyairtable-infra/
├── kubernetes/
├── terraform/
├── docker/
└── scripts/
```

### Phase 2: Service Repositories (Week 2-3)

```bash
# Core Services (Keep existing, working code)
pyairtable-api-gateway/     # From pyairtable-infrastructure
pyairtable-auth-service/    # From pyairtable-infrastructure (has OAuth)
pyairtable-airtable-gateway/# From python-services
pyairtable-ai-services/     # Combine LLM + MCP
pyairtable-platform/        # User, workspace, tenant services
```

## 🗂️ FILE ORGANIZATION PLAN

### Immediate Actions (Do First!)

1. **Create pyairtable-docs repository**
   ```bash
   mkdir pyairtable-docs
   cd pyairtable-docs
   git init
   
   # Move all documentation
   mv ../*.md ./
   mv ../infrastructure/*.md ./migration/
   mv ../team-organization ./
   ```

2. **Deduplicate Services**
   ```bash
   # Remove duplicate API Gateway implementations
   rm -rf go-services/cmd/api-gateway
   
   # Use existing auth service
   rm -rf go-services/auth-service
   ```

3. **Consolidate Docker Compose**
   ```bash
   # Keep only these
   docker-compose.yml          # Production
   docker-compose.dev.yml      # Development
   docker-compose.test.yml     # Testing
   
   # Remove all others
   rm docker-compose.all-services.yml
   rm docker-compose.test-new.yml
   # ... remove individual service docker-compose files
   ```

## 📋 COMMIT STRATEGY

### Repository 1: pyairtable-docs (Commit First)
```bash
# Files to move and commit:
- All *.md files from root
- infrastructure/MIGRATION_RUNBOOK.md
- infrastructure/CLOUD_ARCHITECTURE_RECOMMENDATIONS.md  
- team-organization/
- All architecture diagrams
```

### Repository 2: pyairtable-infra
```bash
# Files to move and commit:
- k8s/ directory (all Kubernetes files)
- infrastructure/ (Terraform files)
- scripts/ (deployment scripts)
- Docker compose files (consolidated)
```

### Repository 3: pyairtable-shared
```bash
# Extract and commit:
- go-services/pkg/ → go-shared/
- Common Python base classes → python-shared/
- Proto definitions → proto/
```

### Repository 4-N: Individual Services
```bash
# For each service, create repository with:
- Service code only
- Service-specific Dockerfile
- Service-specific tests
- README.md
```

## ⚠️ CONFLICTS TO RESOLVE

1. **API Gateway Router Logic**
   - Current: Uses Gin framework
   - New: Uses Fiber framework
   - **Decision**: Keep Fiber (newer, better performance)

2. **Authentication Implementation**
   - Current: Full OAuth + JWT in pyairtable-auth-service-go
   - New: Basic JWT in go-services/auth-service
   - **Decision**: Keep current (more complete)

3. **Service Naming**
   - Some use kebab-case, some use camelCase
   - **Decision**: Standardize on kebab-case

## 🔄 MIGRATION SEQUENCE

### Day 1: Documentation & Infrastructure
1. Create pyairtable-docs repo
2. Move all documentation
3. Create pyairtable-infra repo  
4. Move k8s/, terraform/, scripts/

### Day 2: Shared Libraries
1. Create pyairtable-shared repo
2. Extract common code
3. Update import paths

### Day 3-5: Service Migration
1. Start with working services (API Gateway, Auth)
2. Create individual repos
3. Update CI/CD pipelines
4. Test integrations

### Day 6-7: Cleanup
1. Remove duplicates from main repo
2. Archive old implementations
3. Update all documentation

## 🚀 COMMANDS TO EXECUTE

```bash
# Step 1: Create documentation repository
cd /Users/kg/IdeaProjects
mkdir pyairtable-docs && cd pyairtable-docs
git init
mv ../pyairtable-compose/*.md .
mv ../pyairtable-compose/team-organization .
git add .
git commit -m "Initial documentation consolidation"
git remote add origin git@github.com:YOUR_ORG/pyairtable-docs.git
git push -u origin main

# Step 2: Create infrastructure repository  
cd /Users/kg/IdeaProjects
mkdir pyairtable-infra && cd pyairtable-infra
git init
mv ../pyairtable-compose/k8s .
mv ../pyairtable-compose/infrastructure/terraform .
git add .
git commit -m "Initial infrastructure code"
git remote add origin git@github.com:YOUR_ORG/pyairtable-infra.git
git push -u origin main

# Step 3: Clean up main repository
cd /Users/kg/IdeaProjects/pyairtable-compose
rm -rf go-services/cmd/api-gateway  # Remove duplicate
rm docker-compose.all-services.yml  # Remove duplicate compose files
# ... continue cleanup
```

## ✅ SUCCESS CRITERIA

1. No duplicate service implementations
2. Each repository has single responsibility
3. Clear import paths between services
4. All documentation in one place
5. No conflicting configurations
6. Clean git history in each repo

This plan will transform your 150+ uncommitted files into a well-organized, professional microservices architecture with no duplicates and clear boundaries.