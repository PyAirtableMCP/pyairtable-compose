# PyAirtable Cleanup Execution Guide

## Overview

This guide provides step-by-step instructions for executing the comprehensive cleanup plan for the PyAirtableMCP organization.

## ⚠️ Before You Begin

### Prerequisites
1. **Full repository backup**: Ensure you have a complete backup
2. **Git working directory clean**: Commit or stash any pending changes  
3. **Team notification**: Notify team members of cleanup activities
4. **Time allocation**: Reserve 2-4 hours for complete execution

### Safety Checks
```bash
# Verify git status is clean
git status

# Create safety backup
git tag cleanup-backup-$(date +%Y%m%d-%H%M%S)

# Ensure you're on main branch
git checkout main
```

## Execution Phases

### Phase 1: Critical Separation (30 minutes)
**Risk Level**: 🟢 LOW - Removes unrelated content

```bash
# Execute Phase 1
./cleanup-implementation-scripts/phase1-critical-separation.sh

# Review results
cat cleanup-temp/PHASE1_CLEANUP_SUMMARY.md

# Validate (optional)
git log --oneline -5
ls -la | wc -l  # Should show significant reduction
```

**Expected Results**:
- Aquascene content removed (~40% size reduction)
- Documentation cataloged for migration
- Repository structure analyzed

**Stop here if**: You see any unexpected errors or missing critical files

---

### Phase 2: Service Consolidation (45 minutes) 
**Risk Level**: 🟡 MEDIUM - Modifies services and configurations

```bash
# Execute Phase 2  
./cleanup-implementation-scripts/phase2-service-consolidation.sh

# Review results
cat cleanup-temp/phase2/PHASE2_CONSOLIDATION_SUMMARY.md

# Test core services (CRITICAL)
docker-compose config  # Validate compose files
# Test individual services if needed
```

**Expected Results**:
- Services reduced from ~30 to 8 core services
- Docker Compose files reduced from 74 to 4  
- Standard service structure applied

**Stop here if**: Docker Compose validation fails or critical services missing

---

### Phase 3: Documentation Migration (30 minutes)
**Risk Level**: 🟢 LOW - Only affects documentation  

```bash
# Execute Phase 3
./cleanup-implementation-scripts/phase3-documentation-migration.sh

# Review results  
cat cleanup-temp/PHASE3_DOCUMENTATION_MIGRATION_SUMMARY.md

# Validate documentation repository
ls -la ../pyairtable-docs/
cat README.md  # Should be clean and professional
```

**Expected Results**:
- pyairtable-docs repository created with professional structure
- 2,964+ documentation files migrated and categorized
- Main repository README updated

**Stop here if**: Documentation repository creation fails

---

### Phase 4: Final Optimization (30 minutes)
**Risk Level**: 🟢 LOW - Final cleanup and optimization

```bash
# Execute Phase 4
./cleanup-implementation-scripts/phase4-final-optimization.sh

# Review comprehensive results
cat cleanup-temp/COMPREHENSIVE_CLEANUP_FINAL_REPORT.md

# Validate final structure
ls -la  # Should show clean, organized structure
cat REPOSITORY_STRUCTURE.md
```

**Expected Results**:
- Infrastructure consolidated
- Testing framework standardized  
- Security policies centralized
- Repository optimized for production

---

## Post-Cleanup Validation

### 1. Repository Health Check
```bash
# Check repository size
du -sh .
find . -name "*.md" | wc -l  # Should be minimal

# Validate core files exist
test -f docker-compose.yml && echo "✅ Core compose file exists"
test -f .env.example && echo "✅ Environment template exists"
test -f README.md && echo "✅ README exists"
```

### 2. Service Validation  
```bash
# Validate Docker Compose configuration
docker-compose config

# Test service startup (optional but recommended)
docker-compose up -d postgres redis
docker-compose ps
docker-compose down
```

### 3. Documentation Validation
```bash
# Check documentation repository
ls -la ../pyairtable-docs/
test -d ../pyairtable-docs/architecture && echo "✅ Architecture docs migrated"
test -d ../pyairtable-docs/deployment && echo "✅ Deployment docs migrated"
```

## Rollback Procedures

### Emergency Rollback (if needed)
```bash
# Stop any running processes
git checkout main

# Rollback to backup tag
git tag  # Find your backup tag
git reset --hard cleanup-backup-YYYYMMDD-HHMMSS

# Clean up failed state
rm -rf cleanup-temp/
git clean -fd
```

### Partial Rollback (specific phase)
```bash
# Rollback to specific phase
git checkout cleanup-phase1-backup  # Or phase2, phase3 backup branches
git checkout -b rollback-investigation
```

## Success Validation Checklist

After completing all phases, verify:

- ✅ **Repository size reduced by ~85%**
- ✅ **Core services present and functional** 
  - go-services/api-gateway/
  - go-services/auth-service/  
  - pyairtable-airtable-domain/
  - frontend-services/tenant-dashboard/
- ✅ **Essential files present**
  - docker-compose.yml
  - docker-compose.dev.yml
  - .env.example
  - README.md (clean and professional)
- ✅ **Documentation repository created** (../pyairtable-docs/)
- ✅ **No aquascene references**
- ✅ **Clean git history** with descriptive commits

## Troubleshooting

### Common Issues

**Issue**: "Phase script fails with permission denied"
```bash
chmod +x cleanup-implementation-scripts/*.sh
```

**Issue**: "Docker Compose validation fails"
```bash  
# Check for syntax errors in compose files
docker-compose -f docker-compose.yml config
# Review and fix any YAML syntax issues
```

**Issue**: "Documentation migration incomplete"
```bash
# Manually check for remaining doc files
find . -name "*.md" -maxdepth 1 | grep -v README.md | grep -v REPOSITORY_STRUCTURE.md
# Move any critical docs manually
```

**Issue**: "Services missing after consolidation"
```bash
# Check the service inventory
cat cleanup-temp/phase2/core-services.txt
# Verify expected services are listed
```

### Emergency Contacts

If you encounter critical issues:
1. **Stop execution immediately**
2. **Document the error state**  
3. **Use rollback procedures**
4. **Review logs in cleanup-temp/**

## Final Steps

Once cleanup is complete and validated:

1. **Merge cleanup branches**:
   ```bash
   git checkout main
   git merge cleanup-phase4-work
   ```

2. **Update team**:
   - Share new repository structure
   - Update development workflows
   - Share pyairtable-docs repository location

3. **Archive cleanup artifacts**:
   ```bash
   git tag cleanup-complete-$(date +%Y%m%d)
   # Optional: Remove cleanup-temp/ after validation
   ```

4. **Begin next phase**:
   - Test end-to-end workflows
   - Deploy to staging environment
   - Plan production migration

## Time Estimates

- **Phase 1**: 30 minutes (low risk)
- **Phase 2**: 45 minutes (medium risk - requires validation)
- **Phase 3**: 30 minutes (low risk)  
- **Phase 4**: 30 minutes (low risk)
- **Validation**: 15 minutes
- **Total**: ~2.5 hours

## Expected Outcomes

After successful completion:

- **Lean repository**: 85% size reduction
- **Professional structure**: Enterprise-ready organization
- **Clear service boundaries**: 8 core services
- **Centralized documentation**: Professional docs repository
- **Production readiness**: Deployment-ready architecture
- **AI-friendly**: Optimized for Claude navigation
- **Maintainable**: Sustainable long-term structure

---

**Ready to begin?** Start with Phase 1 and proceed step by step. Stop at any phase if you encounter issues and use the rollback procedures.