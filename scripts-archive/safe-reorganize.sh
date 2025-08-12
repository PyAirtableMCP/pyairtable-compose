#!/bin/bash

# Safe reorganization script for PyAirtable
# This script helps organize files without losing any work

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}PyAirtable Safe Reorganization Script${NC}"
echo -e "${BLUE}=====================================${NC}"

# Function to create repository
create_repo() {
    local repo_name=$1
    local repo_path="/Users/kg/IdeaProjects/$repo_name"
    
    if [ -d "$repo_path" ]; then
        echo -e "${YELLOW}Repository $repo_name already exists${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Creating repository: $repo_name${NC}"
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init
    echo "# $repo_name" > README.md
    git add README.md
    git commit -m "Initial commit"
    cd -
    return 0
}

# Function to safely move files
safe_move() {
    local source=$1
    local dest=$2
    
    if [ ! -e "$source" ]; then
        echo -e "${RED}Source not found: $source${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Moving: $source → $dest${NC}"
    mkdir -p "$(dirname "$dest")"
    cp -r "$source" "$dest"
    echo -e "${GREEN}✓ Copied successfully${NC}"
}

# Step 1: Create backup
echo -e "\n${YELLOW}Step 1: Creating backup of current state${NC}"
BACKUP_DIR="/Users/kg/IdeaProjects/pyairtable-backup-$(date +%Y%m%d-%H%M%S)"
echo "Backup location: $BACKUP_DIR"
cp -r . "$BACKUP_DIR"
echo -e "${GREEN}✓ Backup created${NC}"

# Step 2: Create pyairtable-docs repository
echo -e "\n${YELLOW}Step 2: Creating documentation repository${NC}"
if create_repo "pyairtable-docs"; then
    DOCS_REPO="/Users/kg/IdeaProjects/pyairtable-docs"
    
    # Move all documentation files
    echo "Moving documentation files..."
    for doc in *.md; do
        if [ -f "$doc" ] && [ "$doc" != "README.md" ] && [ "$doc" != "CLAUDE.md" ]; then
            safe_move "$doc" "$DOCS_REPO/$(basename "$doc")"
        fi
    done
    
    # Move team organization
    if [ -d "team-organization" ]; then
        safe_move "team-organization" "$DOCS_REPO/team-organization"
    fi
    
    # Create directory structure
    cd "$DOCS_REPO"
    mkdir -p architecture/decisions architecture/diagrams
    mkdir -p migration/runbooks migration/checklists
    mkdir -p progress/completed progress/in-progress
    mkdir -p guides/user guides/developer guides/operations
    
    # Organize documents
    mv -f ARCHITECT*.md architecture/ 2>/dev/null || true
    mv -f MIGRATION*.md migration/ 2>/dev/null || true
    mv -f *PLAN*.md migration/ 2>/dev/null || true
    mv -f *STATUS*.md progress/ 2>/dev/null || true
    
    echo -e "${GREEN}✓ Documentation repository created${NC}"
fi

# Step 3: Create pyairtable-infra repository
echo -e "\n${YELLOW}Step 3: Creating infrastructure repository${NC}"
if create_repo "pyairtable-infra"; then
    INFRA_REPO="/Users/kg/IdeaProjects/pyairtable-infra"
    
    # Move infrastructure files
    if [ -d "k8s" ]; then
        safe_move "k8s" "$INFRA_REPO/k8s"
    fi
    
    if [ -d "infrastructure" ]; then
        safe_move "infrastructure" "$INFRA_REPO/terraform"
    fi
    
    # Move deployment scripts
    for script in deploy*.sh setup*.sh start*.sh verify*.sh test*.sh; do
        if [ -f "$script" ]; then
            safe_move "$script" "$INFRA_REPO/scripts/$(basename "$script")"
        fi
    done
    
    # Move docker compose files (consolidated)
    safe_move "docker-compose.yml" "$INFRA_REPO/docker/docker-compose.yml"
    safe_move "docker-compose.dev.yml" "$INFRA_REPO/docker/docker-compose.dev.yml"
    
    echo -e "${GREEN}✓ Infrastructure repository created${NC}"
fi

# Step 4: Identify service duplicates
echo -e "\n${YELLOW}Step 4: Analyzing service duplicates${NC}"
echo -e "${BLUE}Duplicate services found:${NC}"
echo "1. API Gateway: Keep go-services/api-gateway (newer, Fiber-based)"
echo "2. Auth Service: Keep pyairtable-infrastructure/pyairtable-auth-service-go (more complete)"
echo "3. Multiple docker-compose files will be consolidated"

# Step 5: Create service mapping file
echo -e "\n${YELLOW}Step 5: Creating service mapping${NC}"
cat > SERVICE_MAPPING.md << 'EOF'
# Service Repository Mapping

## Services to Create as Separate Repositories

### From go-services/ (newer implementations):
- pyairtable-api-gateway ← go-services/api-gateway/
- pyairtable-user-service ← go-services/user-service/
- pyairtable-notification ← go-services/notification-service/
- pyairtable-workspace ← go-services/workspace-service/
- pyairtable-tenant ← go-services/tenant-service/

### From pyairtable-infrastructure/ (existing implementations):
- pyairtable-auth ← pyairtable-infrastructure/pyairtable-auth-service-go/

### From python-services/ (newer implementations):
- pyairtable-airtable ← python-services/airtable-gateway/
- pyairtable-ai ← Combine python-services/llm-orchestrator/ + mcp-server/
- pyairtable-analytics ← python-services/analytics-service/
- pyairtable-workflow ← python-services/workflow-engine/

## Shared Libraries Repository
- pyairtable-shared/
  - go-shared/ ← go-services/pkg/
  - python-shared/ ← Extract base classes
  - proto/ ← Proto definitions
EOF

echo -e "${GREEN}✓ Service mapping created${NC}"

# Step 6: Summary
echo -e "\n${BLUE}=====================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}=====================================${NC}"

echo -e "\n${GREEN}What we've done:${NC}"
echo "1. Created full backup at: $BACKUP_DIR"
echo "2. Created pyairtable-docs repository (if didn't exist)"
echo "3. Created pyairtable-infra repository (if didn't exist)"
echo "4. Identified duplicate services"
echo "5. Created SERVICE_MAPPING.md"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Review SERVICE_MAPPING.md"
echo "2. Commit changes in pyairtable-docs repository"
echo "3. Commit changes in pyairtable-infra repository"
echo "4. Create individual service repositories"
echo "5. Remove duplicates from main repository"

echo -e "\n${BLUE}To commit documentation repository:${NC}"
echo "cd /Users/kg/IdeaProjects/pyairtable-docs"
echo "git add ."
echo "git commit -m 'Consolidate all PyAirtable documentation'"
echo "git remote add origin git@github.com:YOUR_ORG/pyairtable-docs.git"
echo "git push -u origin main"

echo -e "\n${BLUE}To commit infrastructure repository:${NC}"
echo "cd /Users/kg/IdeaProjects/pyairtable-infra"
echo "git add ."
echo "git commit -m 'Consolidate infrastructure and deployment code'"
echo "git remote add origin git@github.com:YOUR_ORG/pyairtable-infra.git"
echo "git push -u origin main"

echo -e "\n${RED}Important:${NC} Original files are still in place. Only copies were made."
echo "Review the new repositories before deleting originals."