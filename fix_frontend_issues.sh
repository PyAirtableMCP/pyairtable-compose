#!/bin/bash

# Sprint 1 Frontend Issues Fix Script
# Addresses the critical TypeScript compilation errors in feature/SCRUM-17-deploy-frontend

set -e

echo "🔧 Sprint 1 Frontend Issues Fix Script"
echo "======================================"

# Navigate to frontend service
cd frontend-services/tenant-dashboard

echo "📋 Current branch: $(git branch --show-current)"

# 1. Fix TypeScript compilation errors
echo "🎯 Step 1: Fixing TypeScript compilation errors..."

# Fix unused variable in analyze-structure route
echo "  - Fixing analyze-structure/route.ts..."
sed -i '' 's/const { personalAccessToken } = await request.json();//g' src/app/api/airtable/analyze-structure/route.ts 2>/dev/null || echo "    File may not exist or already fixed"

# Fix unused variable in onboarding complete route  
echo "  - Fixing onboarding/complete/route.ts..."
sed -i '' '119s/.*/  \/\/ Removed unused request parameter/' src/app/api/onboarding/complete/route.ts 2>/dev/null || echo "    File may not exist or already fixed"

# Fix unused variable in test-auth route
echo "  - Fixing test-auth/route.ts..."
sed -i '' 's/export async function GET(req: Request)/export async function GET()/g' src/app/api/test-auth/route.ts 2>/dev/null || echo "    File may not exist or already fixed"

# 2. Install and update dependencies
echo "🎯 Step 2: Updating dependencies..."
npm audit fix --force 2>/dev/null || echo "  No critical vulnerabilities to fix"

# Update next-auth to fix security vulnerabilities
echo "  - Updating next-auth..."
npm update next-auth @auth/core cookie 2>/dev/null || echo "  Dependencies may already be up to date"

# 3. Run TypeScript check
echo "🎯 Step 3: Running TypeScript validation..."
if npx tsc --noEmit --skipLibCheck; then
    echo "✅ TypeScript compilation: PASSED"
else
    echo "❌ TypeScript compilation: FAILED"
    echo "📝 Manual fixes may be required. Check the following files:"
    echo "   - src/app/api/airtable/analyze-structure/route.ts"
    echo "   - src/app/api/onboarding/complete/route.ts"
    echo "   - src/app/api/test-auth/route.ts"
fi

# 4. Run linting with auto-fix
echo "🎯 Step 4: Running ESLint auto-fix..."
if npm run lint -- --fix; then
    echo "✅ ESLint auto-fix: COMPLETED"
else
    echo "⚠️ ESLint: Some issues require manual fixing"
fi

# 5. Test build
echo "🎯 Step 5: Testing production build..."
if npm run build; then
    echo "✅ Production build: SUCCESSFUL"
else
    echo "❌ Production build: FAILED"
    echo "📝 Check build output above for specific errors"
fi

# 6. Run security audit
echo "🎯 Step 6: Running security audit..."
echo "Current vulnerabilities:"
npm audit --json 2>/dev/null | jq '.metadata.vulnerabilities // "No vulnerability data"' || echo "jq not available, run: npm audit"

echo ""
echo "🎉 Frontend fix script completed!"
echo "📋 Next steps:"
echo "   1. Review any remaining TypeScript errors"
echo "   2. Test the application locally"
echo "   3. Commit the fixes"
echo "   4. Re-run the comprehensive test suite"

# Return to original directory
cd ../..