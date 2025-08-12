#!/bin/bash

# Expert-Approved PyAirtable Reorganization Script
# Incorporates feedback from Backend Architect, Cloud Architect, DevOps Guardian, and Go Expert

set -euo pipefail  # Enhanced error handling

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BASE_DIR="/Users/kg/IdeaProjects"
BACKUP_DIR="${BASE_DIR}/pyairtable-backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${BASE_DIR}/reorganization-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "${RED}ERROR: $1${NC}"
    log "${YELLOW}Check log file: $LOG_FILE${NC}"
    exit 1
}

# Validate prerequisites
validate_prerequisites() {
    log "${BLUE}=== Validating Prerequisites ===${NC}"
    
    # Check git status
    if ! git status &>/dev/null; then
        error_exit "Not in a git repository"
    fi
    
    # Check for uncommitted changes
    if [[ $(git status --porcelain | wc -l) -eq 0 ]]; then
        error_exit "No uncommitted changes found. Expected 150+ files."
    fi
    
    # Check kubectl access
    if ! kubectl get pods -n pyairtable &>/dev/null; then
        log "${YELLOW}Warning: Cannot access Kubernetes cluster${NC}"
    fi
    
    # Check disk space (need at least 5GB) - macOS compatible
    if [[ "$OSTYPE" == "darwin"* ]]; then
        available_space=$(df -g "$BASE_DIR" | awk 'NR==2 {print $4}')
    else
        available_space=$(df -BG "$BASE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    if [[ $available_space -lt 5 ]]; then
        error_exit "Insufficient disk space. Need at least 5GB free."
    fi
    
    log "${GREEN}✓ Prerequisites validated${NC}"
}

# Create comprehensive backup
create_backup() {
    log "${BLUE}=== Creating Comprehensive Backup ===${NC}"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup current state
    log "Backing up to: $BACKUP_DIR"
    cp -r . "$BACKUP_DIR/" || error_exit "Backup failed"
    
    # Create backup manifest
    cat > "$BACKUP_DIR/backup-manifest.txt" << EOF
Backup created: $(date)
Total files: $(find . -type f | wc -l)
Uncommitted files: $(git status --porcelain | wc -l)
Running services: $(kubectl get pods -n pyairtable --no-headers 2>/dev/null | wc -l || echo "N/A")
EOF
    
    # Backup Kubernetes state if accessible
    if kubectl get pods -n pyairtable &>/dev/null; then
        kubectl get all -n pyairtable -o yaml > "$BACKUP_DIR/k8s-state.yaml"
    fi
    
    log "${GREEN}✓ Backup completed${NC}"
}

# Create repository with proper structure
create_repository() {
    local repo_name=$1
    local repo_type=$2
    local repo_path="${BASE_DIR}/${repo_name}"
    
    if [[ -d "$repo_path" ]]; then
        log "${YELLOW}Repository $repo_name already exists, skipping${NC}"
        return 0
    fi
    
    log "${BLUE}Creating repository: $repo_name${NC}"
    
    # Create repository
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init
    
    # Create standard files
    cat > README.md << EOF
# $repo_name

$repo_type repository for PyAirtable platform.

## Overview
See [pyairtable-docs](https://github.com/YOUR_ORG/pyairtable-docs) for complete documentation.

## Quick Start
\`\`\`bash
# Development
make dev

# Testing
make test

# Production
make deploy
\`\`\`
EOF

    # Create CLAUDE.md for AI assistance
    cat > CLAUDE.md << EOF
# $repo_name - Claude Context

## Repository Purpose
$repo_type repository for PyAirtable platform.

## Key Files
- README.md - Basic overview
- Makefile - Build commands
- See pyairtable-docs for architecture

## Development Workflow
1. All changes must be documented in pyairtable-docs first
2. Update this repository only after docs approval
3. Follow the established patterns
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Binaries
*.exe
*.dll
*.so
*.dylib

# Test binary
*.test

# Output
*.out

# Go
vendor/
go.sum

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Env
.env
.env.local

# Logs
*.log
EOF

    # Initial commit
    git add .
    git commit -m "Initial repository structure" || error_exit "Failed to create initial commit"
    
    cd - > /dev/null
    log "${GREEN}✓ Repository $repo_name created${NC}"
}

# Organize documentation with expert-approved structure
organize_documentation() {
    log "${BLUE}=== Organizing Documentation Repository ===${NC}"
    
    local docs_repo="${BASE_DIR}/pyairtable-docs"
    create_repository "pyairtable-docs" "Documentation"
    
    # Create expert-approved directory structure
    cd "$docs_repo"
    mkdir -p architecture/{decisions,diagrams,services}
    mkdir -p migration/{runbooks,checklists,history}
    mkdir -p progress/{completed,in-progress,roadmap}
    mkdir -p guides/{user,developer,operations}
    mkdir -p api/{specs,schemas,examples}
    mkdir -p security/{policies,audits,compliance}
    
    # Create architecture decision record template
    cat > architecture/decisions/template-adr.md << 'EOF'
# ADR-XXX: Title

Date: YYYY-MM-DD

## Status
Proposed | Accepted | Deprecated | Superseded

## Context
What is the issue that we're seeing that is motivating this decision?

## Decision
What is the change that we're proposing and/or doing?

## Consequences
What becomes easier or more difficult to do because of this change?
EOF

    # Move documentation files
    log "Moving documentation files..."
    
    # Architecture documents
    for file in "$BASE_DIR/pyairtable-compose/"*ARCHITECT*.md; do
        [[ -f "$file" ]] && cp "$file" "$docs_repo/architecture/" && log "  - Moved $(basename "$file")"
    done
    
    # Migration documents
    for file in "$BASE_DIR/pyairtable-compose/"*MIGRATION*.md "$BASE_DIR/pyairtable-compose/"*PLAN*.md; do
        [[ -f "$file" ]] && cp "$file" "$docs_repo/migration/" && log "  - Moved $(basename "$file")"
    done
    
    # Status documents
    for file in "$BASE_DIR/pyairtable-compose/"*STATUS*.md; do
        [[ -f "$file" ]] && cp "$file" "$docs_repo/progress/" && log "  - Moved $(basename "$file")"
    done
    
    # Create main documentation index
    cat > README.md << 'EOF'
# PyAirtable Documentation Hub

This is the single source of truth for all PyAirtable platform documentation.

## 📋 Documentation Structure

### Architecture
- [Decisions](./architecture/decisions/) - Architecture Decision Records (ADRs)
- [Diagrams](./architecture/diagrams/) - System architecture diagrams
- [Services](./architecture/services/) - Individual service documentation

### Migration
- [Runbooks](./migration/runbooks/) - Step-by-step migration guides
- [Checklists](./migration/checklists/) - Migration verification checklists
- [History](./migration/history/) - Migration history and lessons learned

### Progress
- [Completed](./progress/completed/) - Completed milestones
- [In Progress](./progress/in-progress/) - Current work
- [Roadmap](./progress/roadmap/) - Future plans

### Guides
- [User Guide](./guides/user/) - End-user documentation
- [Developer Guide](./guides/developer/) - Development documentation
- [Operations Guide](./guides/operations/) - DevOps and operational guides

## 🚀 Process

All architectural changes MUST follow this process:
1. Create/update documentation in this repository
2. Get approval through PR review
3. Update infrastructure repository if needed
4. Update shared libraries if needed
5. Finally, implement in service repositories

## 🔗 Repository Links

- [pyairtable-infra](https://github.com/YOUR_ORG/pyairtable-infra) - Infrastructure code
- [pyairtable-shared](https://github.com/YOUR_ORG/pyairtable-shared) - Shared libraries
- [pyairtable-gateway](https://github.com/YOUR_ORG/pyairtable-gateway) - API Gateway
- [pyairtable-auth](https://github.com/YOUR_ORG/pyairtable-auth) - Authentication Service
EOF

    git add .
    git commit -m "Organize documentation structure" || log "${YELLOW}No new documentation to commit${NC}"
    
    cd - > /dev/null
    log "${GREEN}✓ Documentation repository organized${NC}"
}

# Create infrastructure repository with DevOps best practices
organize_infrastructure() {
    log "${BLUE}=== Creating Infrastructure Repository ===${NC}"
    
    local infra_repo="${BASE_DIR}/pyairtable-infra"
    create_repository "pyairtable-infra" "Infrastructure"
    
    cd "$infra_repo"
    
    # Create directory structure
    mkdir -p kubernetes/{base,overlays,scripts}
    mkdir -p terraform/{modules,environments}
    mkdir -p docker/{images,compose}
    mkdir -p scripts/{deployment,monitoring,backup}
    mkdir -p ci-cd/{workflows,templates}
    
    # Move Kubernetes files
    if [[ -d "$BASE_DIR/pyairtable-compose/k8s" ]]; then
        cp -r "$BASE_DIR/pyairtable-compose/k8s/"* "$infra_repo/kubernetes/base/"
        log "  - Moved Kubernetes manifests"
    fi
    
    # Move Terraform files
    if [[ -d "$BASE_DIR/pyairtable-compose/infrastructure" ]]; then
        cp -r "$BASE_DIR/pyairtable-compose/infrastructure/"* "$infra_repo/terraform/"
        log "  - Moved Terraform configurations"
    fi
    
    # Create Makefile for infrastructure operations
    cat > Makefile << 'EOF'
# PyAirtable Infrastructure Makefile

.PHONY: help
help:
	@echo "PyAirtable Infrastructure Commands:"
	@echo "  make k8s-validate    - Validate Kubernetes manifests"
	@echo "  make k8s-deploy      - Deploy to Kubernetes"
	@echo "  make tf-plan         - Terraform plan"
	@echo "  make tf-apply        - Terraform apply"
	@echo "  make backup          - Backup production data"

.PHONY: k8s-validate
k8s-validate:
	@echo "Validating Kubernetes manifests..."
	@kubectl apply --dry-run=client -f kubernetes/base/

.PHONY: k8s-deploy
k8s-deploy: k8s-validate
	@echo "Deploying to Kubernetes..."
	@kubectl apply -f kubernetes/base/

.PHONY: tf-plan
tf-plan:
	@cd terraform && terraform plan

.PHONY: tf-apply
tf-apply:
	@cd terraform && terraform apply

.PHONY: backup
backup:
	@scripts/backup/backup-production.sh
EOF

    git add .
    git commit -m "Create infrastructure repository structure" || log "${YELLOW}No infrastructure files to commit${NC}"
    
    cd - > /dev/null
    log "${GREEN}✓ Infrastructure repository created${NC}"
}

# Create shared libraries repository based on Go expert recommendations
organize_shared_libraries() {
    log "${BLUE}=== Creating Shared Libraries Repository ===${NC}"
    
    local shared_repo="${BASE_DIR}/pyairtable-shared"
    create_repository "pyairtable-shared" "Shared Libraries"
    
    cd "$shared_repo"
    
    # Create Go shared library structure (from Go expert)
    mkdir -p go-shared/{config,database,cache,middleware,errors,logger,metrics,health,utils,models,testing}
    
    # Copy existing pyairtable-go-shared if it exists
    if [[ -d "$BASE_DIR/pyairtable-compose/pyairtable-infrastructure/pyairtable-go-shared" ]]; then
        cp -r "$BASE_DIR/pyairtable-compose/pyairtable-infrastructure/pyairtable-go-shared/"* "$shared_repo/go-shared/"
        log "  - Copied existing Go shared library"
    fi
    
    # Create Python shared library structure
    mkdir -p python-shared/{base,utils,middleware,models,testing}
    
    # Create shared library documentation
    cat > go-shared/README.md << 'EOF'
# PyAirtable Go Shared Library

Production-ready shared components for all Go microservices.

## Components
- **config** - Viper-based configuration management
- **database** - GORM with connection pooling
- **cache** - Redis with circuit breaker
- **middleware** - Auth, logging, metrics, rate limiting
- **errors** - Standardized error handling
- **logger** - Zap structured logging
- **metrics** - Prometheus integration
- **health** - Comprehensive health checks
- **utils** - Common utilities
- **models** - Shared DTOs
- **testing** - Test utilities

## Usage
```go
import "github.com/pyairtable/pyairtable-shared/go-shared/config"
```
EOF

    git add .
    git commit -m "Create shared libraries structure" || log "${YELLOW}No shared library files to commit${NC}"
    
    cd - > /dev/null
    log "${GREEN}✓ Shared libraries repository created${NC}"
}

# Create service mapping based on expert recommendations
create_service_mapping() {
    log "${BLUE}=== Creating Service Repository Mapping ===${NC}"
    
    cat > "${BASE_DIR}/SERVICE_MAPPING_EXPERT_APPROVED.md" << 'EOF'
# Expert-Approved Service Repository Mapping

Based on Backend Architect, Cloud Architect, DevOps Guardian, and Go Expert review.

## Repository Creation Priority

### Phase 1: Core Services (Keep Existing Working Code)
1. **pyairtable-gateway**
   - Source: `pyairtable-infrastructure/pyairtable-api-gateway-go/`
   - Reason: Advanced implementation with circuit breakers, WebSocket support
   - Status: Currently running in production

2. **pyairtable-auth**
   - Source: `pyairtable-infrastructure/pyairtable-auth-service-go/`
   - Reason: Full OAuth, 2FA, RBAC, audit logging
   - Status: Currently running in production

3. **pyairtable-airtable**
   - Source: `python-services/airtable-gateway/`
   - Reason: Working implementation with caching
   - Status: Currently running in production

### Phase 2: AI Services (Combine and Optimize)
4. **pyairtable-ai**
   - Source: Combine `python-services/llm-orchestrator/` + `python-services/mcp-server/`
   - Reason: Shared dependencies and functionality
   - Language: Python (for ML libraries)

### Phase 3: Platform Services (Consolidate from go-services)
5. **pyairtable-platform**
   - Source: Consolidate from `go-services/`
   - Services: user-service, workspace-service, tenant-service, notification-service
   - Language: Go (for performance)

### Phase 4: Analytics and Data Services
6. **pyairtable-analytics**
   - Source: `python-services/analytics-service/`
   - Language: Python (for data science libraries)

7. **pyairtable-workflow**
   - Source: `python-services/workflow-engine/`
   - Language: Python (for flexibility)

## Services to Discard (Duplicates)
- `go-services/api-gateway/` - Use pyairtable-infrastructure version
- `go-services/auth-service/` - Use pyairtable-infrastructure version
- `go-services/pkg/` - Replace with pyairtable-go-shared

## Technology Stack by Repository
| Repository | Language | Framework | Database | Cache |
|------------|----------|-----------|----------|-------|
| pyairtable-gateway | Go | Fiber v3 | - | Redis |
| pyairtable-auth | Go | Fiber v3 | PostgreSQL | Redis |
| pyairtable-airtable | Python | FastAPI | - | Redis |
| pyairtable-ai | Python | FastAPI | PostgreSQL | Redis |
| pyairtable-platform | Go | Fiber v3 | PostgreSQL | Redis |
| pyairtable-analytics | Python | FastAPI | PostgreSQL | - |
| pyairtable-workflow | Python | FastAPI | PostgreSQL | Redis |

## Migration Order (Zero Downtime)
1. Week 1: Documentation and shared libraries
2. Week 2: Extract working services (gateway, auth, airtable)
3. Week 3: Consolidate AI services
4. Week 4: Platform services migration
5. Week 5: Analytics and workflow services
6. Week 6: Cleanup and optimization
EOF

    log "${GREEN}✓ Expert-approved service mapping created${NC}"
}

# Main execution
main() {
    log "${BLUE}=====================================${NC}"
    log "${BLUE}PyAirtable Expert-Approved Reorganization${NC}"
    log "${BLUE}=====================================${NC}"
    log "Started at: $(date)"
    
    # Phase 1: Validation and Backup
    validate_prerequisites
    create_backup
    
    # Phase 2: Create Core Repositories
    organize_documentation
    organize_infrastructure
    organize_shared_libraries
    
    # Phase 3: Create Service Mapping
    create_service_mapping
    
    # Summary
    log "${BLUE}=====================================${NC}"
    log "${BLUE}Reorganization Complete${NC}"
    log "${BLUE}=====================================${NC}"
    
    log "${GREEN}✓ Created backup at: $BACKUP_DIR${NC}"
    log "${GREEN}✓ Created pyairtable-docs repository${NC}"
    log "${GREEN}✓ Created pyairtable-infra repository${NC}"
    log "${GREEN}✓ Created pyairtable-shared repository${NC}"
    log "${GREEN}✓ Created expert-approved service mapping${NC}"
    
    log "\n${YELLOW}Next Steps:${NC}"
    log "1. Review the created repositories"
    log "2. Commit changes in each repository"
    log "3. Push to GitHub with proper organization"
    log "4. Create individual service repositories following the mapping"
    log "5. Update CI/CD pipelines"
    
    log "\n${BLUE}Repository Locations:${NC}"
    log "  - Documentation: ${BASE_DIR}/pyairtable-docs"
    log "  - Infrastructure: ${BASE_DIR}/pyairtable-infra"
    log "  - Shared Libraries: ${BASE_DIR}/pyairtable-shared"
    
    log "\n${BLUE}To push repositories:${NC}"
    log "  cd ${BASE_DIR}/pyairtable-docs"
    log "  git remote add origin git@github.com:YOUR_ORG/pyairtable-docs.git"
    log "  git push -u origin main"
    
    log "\nLog file: $LOG_FILE"
}

# Run main function
main "$@"