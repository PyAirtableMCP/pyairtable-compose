#!/bin/bash
# PyAirtable GitHub Organization Setup Script
# This script prepares everything needed for the GitHub organization migration

set -e

echo "🚀 PyAirtable GitHub Organization Setup"
echo "======================================="
echo ""
echo "📋 MANUAL STEP REQUIRED:"
echo "1. Visit: https://github.com/organizations/plan"
echo "2. Create organization with name: pyairtable-org"
echo "3. Select the FREE plan (can upgrade later)"
echo "4. Set organization details:"
echo "   - Display Name: PyAirtable"
echo "   - Description: Enterprise-grade AI-powered Airtable automation platform"
echo "   - Email: Use your preferred contact email"
echo ""
echo "Press Enter after creating the organization to continue..."
read

# Verify organization exists
echo "✅ Verifying organization exists..."
ORG_NAME=$(gh api /orgs/pyairtable-org 2>/dev/null | jq -r '.login' || echo "")

if [ -z "$ORG_NAME" ]; then
    echo "❌ Organization 'pyairtable-org' not found!"
    echo "Please create it at: https://github.com/organizations/plan"
    exit 1
fi

echo "✅ Organization found: $ORG_NAME"

# Create teams
echo ""
echo "📋 Creating team structure..."

# Create admin team
echo "Creating pyairtable-admins team..."
gh api --method POST /orgs/pyairtable-org/teams \
  -f name="pyairtable-admins" \
  -f description="Organization administrators with full access" \
  -f privacy="closed" \
  -f permission="admin" 2>/dev/null || echo "Team may already exist"

# Create core team
echo "Creating pyairtable-core team..."
gh api --method POST /orgs/pyairtable-org/teams \
  -f name="pyairtable-core" \
  -f description="Core infrastructure and platform team" \
  -f privacy="closed" \
  -f permission="push" 2>/dev/null || echo "Team may already exist"

# Create developers team
echo "Creating pyairtable-developers team..."
gh api --method POST /orgs/pyairtable-org/teams \
  -f name="pyairtable-developers" \
  -f description="Frontend, backend, and feature developers" \
  -f privacy="closed" \
  -f permission="push" 2>/dev/null || echo "Team may already exist"

# Create docs team
echo "Creating pyairtable-docs team..."
gh api --method POST /orgs/pyairtable-org/teams \
  -f name="pyairtable-docs" \
  -f description="Documentation and technical writing team" \
  -f privacy="closed" \
  -f permission="push" 2>/dev/null || echo "Team may already exist"

echo ""
echo "✅ Team structure created!"

# Configure organization settings
echo ""
echo "📋 Configuring organization settings..."

# Update organization settings
gh api --method PATCH /orgs/pyairtable-org \
  -f default_repository_permission="read" \
  -f members_can_create_repositories=false \
  -f members_can_create_public_repositories=false \
  -f members_can_create_private_repositories=false \
  -f members_can_create_internal_repositories=false \
  -f members_can_create_pages=false \
  -f members_can_fork_private_repositories=false \
  -f web_commit_signoff_required=false 2>/dev/null || echo "Some settings may require manual configuration"

echo ""
echo "✅ Organization configuration complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Run ./transfer-repositories.sh to migrate repositories"
echo "2. Add team members to appropriate teams"
echo "3. Configure branch protection rules"
echo "4. Set up organization secrets for CI/CD"
echo ""
echo "Organization URL: https://github.com/pyairtable-org"