#!/bin/bash
# PyAirtable Repository Transfer Script
# Transfers repositories to the new organization following the migration plan

set -e

echo "🚀 PyAirtable Repository Transfer Script"
echo "========================================"
echo ""

# Check if organization exists
ORG_NAME=$(gh api /orgs/pyairtable-org 2>/dev/null | jq -r '.login' || echo "")
if [ -z "$ORG_NAME" ]; then
    echo "❌ Organization 'pyairtable-org' not found!"
    echo "Please run ./create-github-org.sh first"
    exit 1
fi

echo "✅ Organization found: $ORG_NAME"
echo ""

# Define repositories to transfer (in order of priority)
declare -a TIER1_REPOS=(
    "pyairtable-compose"
    "pyairtable-infra"
    "pyairtable-common"
)

declare -a TIER2_REPOS=(
    "pyairtable-frontend"
    "pyairtable-auth"
    "pyairtable-gateway"
    "pyairtable-platform-services"
)

declare -a TIER3_REPOS=(
    "pyairtable-automation-services"
    "pyairtable-ai"
    "pyairtable-airtable"
    "pyairtable-tenant-service-go"
)

declare -a TIER4_REPOS=(
    "pyairtable-docs"
)

# Function to check if repo exists
check_repo_exists() {
    local repo=$1
    local owner=$2
    
    gh api "/repos/$owner/$repo" &>/dev/null
}

# Function to transfer repository
transfer_repo() {
    local repo=$1
    local from_owner="Reg-Kris"  # Update if different
    local to_org="pyairtable-org"
    
    echo "📦 Transferring $repo..."
    
    # Check if repo exists in source
    if ! check_repo_exists "$repo" "$from_owner"; then
        echo "  ⚠️  Repository $from_owner/$repo not found, skipping..."
        return
    fi
    
    # Check if already in organization
    if check_repo_exists "$repo" "$to_org"; then
        echo "  ✅ Repository already in organization"
        return
    fi
    
    echo "  🔄 Initiating transfer from $from_owner/$repo to $to_org/$repo"
    
    # Perform the transfer
    gh api --method POST "/repos/$from_owner/$repo/transfer" \
        -f new_owner="$to_org" \
        -F team_ids=[] || {
        echo "  ❌ Transfer failed - may require manual action"
        echo "     Visit: https://github.com/$from_owner/$repo/settings"
        return
    }
    
    echo "  ✅ Transfer complete!"
    
    # Wait a moment for GitHub to process
    sleep 2
    
    # Update repository settings
    echo "  🔧 Updating repository settings..."
    gh api --method PATCH "/repos/$to_org/$repo" \
        -F has_issues=true \
        -F has_projects=true \
        -F has_wiki=false \
        -F allow_squash_merge=true \
        -F allow_merge_commit=true \
        -F allow_rebase_merge=true \
        -F delete_branch_on_merge=true \
        -F allow_auto_merge=false 2>/dev/null || echo "  ⚠️  Some settings may need manual configuration"
}

# Process repositories by tier
echo "📋 Phase 1: Core Infrastructure (Tier 1)"
echo "========================================="
for repo in "${TIER1_REPOS[@]}"; do
    transfer_repo "$repo"
    echo ""
done

echo ""
echo "📋 Phase 2: Core Services (Tier 2)"
echo "=================================="
for repo in "${TIER2_REPOS[@]}"; do
    transfer_repo "$repo"
    echo ""
done

echo ""
echo "📋 Phase 3: Business Services (Tier 3)"
echo "======================================"
for repo in "${TIER3_REPOS[@]}"; do
    transfer_repo "$repo"
    echo ""
done

echo ""
echo "📋 Phase 4: Documentation (Tier 4)"
echo "=================================="
for repo in "${TIER4_REPOS[@]}"; do
    transfer_repo "$repo"
    echo ""
done

# Summary
echo ""
echo "✅ Repository transfer process complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Verify all repositories at: https://github.com/pyairtable-org"
echo "2. Update CI/CD configurations"
echo "3. Update documentation links"
echo "4. Configure branch protection rules"
echo "5. Add team permissions to repositories"
echo ""
echo "Run ./configure-repo-permissions.sh to set up team permissions"