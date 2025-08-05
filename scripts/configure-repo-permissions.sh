#!/bin/bash
# PyAirtable Repository Permissions Configuration Script
# Sets up proper team permissions for all repositories

set -e

echo "🔐 PyAirtable Repository Permissions Configuration"
echo "================================================="
echo ""

# Check if organization exists
ORG_NAME=$(gh api /orgs/pyairtable-org 2>/dev/null | jq -r '.login' || echo "")
if [ -z "$ORG_NAME" ]; then
    echo "❌ Organization 'pyairtable-org' not found!"
    exit 1
fi

# Get team IDs
echo "📋 Fetching team information..."
ADMIN_TEAM_ID=$(gh api /orgs/pyairtable-org/teams/pyairtable-admins 2>/dev/null | jq -r '.id' || echo "")
CORE_TEAM_ID=$(gh api /orgs/pyairtable-org/teams/pyairtable-core 2>/dev/null | jq -r '.id' || echo "")
DEV_TEAM_ID=$(gh api /orgs/pyairtable-org/teams/pyairtable-developers 2>/dev/null | jq -r '.id' || echo "")
DOCS_TEAM_ID=$(gh api /orgs/pyairtable-org/teams/pyairtable-docs 2>/dev/null | jq -r '.id' || echo "")

# Define repository permissions
declare -A REPO_PERMISSIONS=(
    # Core Infrastructure - Admin team has admin, Core team has write
    ["pyairtable-compose"]="admin:$ADMIN_TEAM_ID,push:$CORE_TEAM_ID"
    ["pyairtable-infra"]="admin:$ADMIN_TEAM_ID,push:$CORE_TEAM_ID"
    ["pyairtable-common"]="admin:$ADMIN_TEAM_ID,push:$CORE_TEAM_ID,pull:$DEV_TEAM_ID"
    
    # Core Services - Core team has write, Dev team has write
    ["pyairtable-frontend"]="push:$CORE_TEAM_ID,push:$DEV_TEAM_ID"
    ["pyairtable-auth"]="push:$CORE_TEAM_ID,push:$DEV_TEAM_ID"
    ["pyairtable-gateway"]="push:$CORE_TEAM_ID,push:$DEV_TEAM_ID"
    ["pyairtable-platform-services"]="push:$CORE_TEAM_ID,push:$DEV_TEAM_ID"
    
    # Business Services - Dev team has write
    ["pyairtable-automation-services"]="push:$DEV_TEAM_ID,pull:$CORE_TEAM_ID"
    ["pyairtable-ai"]="push:$DEV_TEAM_ID,pull:$CORE_TEAM_ID"
    ["pyairtable-airtable"]="push:$DEV_TEAM_ID,pull:$CORE_TEAM_ID"
    ["pyairtable-tenant-service-go"]="push:$DEV_TEAM_ID,pull:$CORE_TEAM_ID"
    
    # Documentation - Docs team has write, everyone else has read
    ["pyairtable-docs"]="push:$DOCS_TEAM_ID,pull:$CORE_TEAM_ID,pull:$DEV_TEAM_ID"
)

# Function to set repository permissions
set_repo_permissions() {
    local repo=$1
    local permissions=$2
    
    echo "🔧 Configuring permissions for $repo..."
    
    # Check if repo exists in org
    if ! gh api "/repos/pyairtable-org/$repo" &>/dev/null; then
        echo "  ⚠️  Repository not found in organization, skipping..."
        return
    fi
    
    # Parse and apply permissions
    IFS=',' read -ra PERMS <<< "$permissions"
    for perm in "${PERMS[@]}"; do
        IFS=':' read -ra PARTS <<< "$perm"
        local permission="${PARTS[0]}"
        local team_id="${PARTS[1]}"
        
        if [ -n "$team_id" ]; then
            echo "  📝 Granting $permission access to team $team_id"
            gh api --method PUT "/orgs/pyairtable-org/teams/$team_id/repos/pyairtable-org/$repo" \
                -f permission="$permission" 2>/dev/null || echo "  ⚠️  Failed to set permission"
        fi
    done
    
    # Configure branch protection for main branch
    echo "  🛡️  Setting branch protection rules..."
    gh api --method PUT "/repos/pyairtable-org/$repo/branches/main/protection" \
        -F required_status_checks='{"strict":true,"contexts":["continuous-integration"]}' \
        -F enforce_admins=false \
        -F required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
        -F restrictions=null \
        -F allow_force_pushes=false \
        -F allow_deletions=false 2>/dev/null || echo "  ⚠️  Branch protection may need manual configuration"
}

# Apply permissions to all repositories
echo ""
echo "📋 Applying repository permissions..."
echo "====================================="
for repo in "${!REPO_PERMISSIONS[@]}"; do
    set_repo_permissions "$repo" "${REPO_PERMISSIONS[$repo]}"
    echo ""
done

# Create organization-wide settings
echo "📋 Configuring organization-wide settings..."
echo "==========================================="

# Set up organization secrets (placeholders - values need to be added manually)
echo "🔐 Creating organization secrets (values must be added manually)..."

declare -a ORG_SECRETS=(
    "AIRTABLE_TOKEN"
    "GEMINI_API_KEY"
    "API_KEY"
    "JWT_SECRET"
    "POSTGRES_PASSWORD"
    "REDIS_PASSWORD"
    "DOCKER_REGISTRY_TOKEN"
)

for secret in "${ORG_SECRETS[@]}"; do
    echo "  📝 Secret: $secret - Add value at: https://github.com/organizations/pyairtable-org/settings/secrets/actions/new"
done

echo ""
echo "✅ Repository permissions configuration complete!"
echo ""
echo "📋 Manual Steps Required:"
echo "1. Add secret values at: https://github.com/organizations/pyairtable-org/settings/secrets/actions"
echo "2. Invite team members at: https://github.com/orgs/pyairtable-org/people"
echo "3. Review branch protection at: https://github.com/orgs/pyairtable-org/settings/rules"
echo "4. Configure GitHub Actions at: https://github.com/organizations/pyairtable-org/settings/actions"
echo ""
echo "Organization URL: https://github.com/pyairtable-org"