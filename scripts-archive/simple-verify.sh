#!/bin/bash

# Simple PyAirtable Microservices Verification Script

set -e

# Configuration
ORG="Reg-Kris"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Repository list
REPOS=(
    "pyairtable-api-gateway-go"
    "pyairtable-auth-service-go"
    "pyairtable-user-service-go"
    "pyairtable-tenant-service-go"
    "pyairtable-workspace-service-go"
    "pyairtable-permission-service-go"
    "pyairtable-webhook-service-go"
    "pyairtable-notification-service-go"
    "pyairtable-file-service-go"
    "pyairtable-go-shared"
    "pyairtable-python-shared"
    "pyairtable-microservices"
)

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo ""
echo "🎉 PyAirtable Microservices Deployment Verification"
echo "=================================================="
echo ""

log_info "Checking repository accessibility..."
echo ""

successful=0
total=${#REPOS[@]}

for repo in "${REPOS[@]}"; do
    echo -n "🔍 $repo: "
    if gh repo view "$ORG/$repo" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ accessible${NC}"
        ((successful++))
    else
        echo -e "${RED}❌ not accessible${NC}"
    fi
done

echo ""
echo "=================================================="
echo "📊 VERIFICATION SUMMARY:"
echo "   Total repositories: $total"
echo "   ✅ Accessible: $successful"
echo "   ❌ Failed: $((total - successful))"
echo ""

if [ $successful -eq $total ]; then
    log_success "🎉 ALL REPOSITORIES ARE SUCCESSFULLY DEPLOYED!"
    echo ""
    echo "🔗 Repository Links:"
    for repo in "${REPOS[@]}"; do
        echo "   📦 https://github.com/$ORG/$repo"
    done
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Clone all repositories: ./manage-repos.sh clone"
    echo "   2. Set up CI/CD pipelines: ./manage-repos.sh settings"
    echo "   3. Add GitHub Actions: ./manage-repos.sh workflows <service-path>"
    echo "   4. Start development!"
    echo ""
else
    echo -e "${RED}⚠️  Some repositories are not accessible${NC}"
    echo "   Please check GitHub permissions and repository status"
fi

echo "=================================================="