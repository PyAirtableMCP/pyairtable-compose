#!/bin/bash
set -e

echo "🎭 Running visual tests with Playwright..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if frontend services exist
FRONTEND_DIR="/Users/kg/IdeaProjects/pyairtable-compose/frontend-services/tenant-dashboard"

if [ ! -d "$FRONTEND_DIR" ]; then
    echo "❌ Frontend services directory not found: $FRONTEND_DIR"
    echo "🔍 Available frontend services:"
    ls -la /Users/kg/IdeaProjects/pyairtable-compose/frontend-services/ 2>/dev/null || echo "   No frontend services directory found"
    exit 1
fi

echo "📁 Navigating to frontend service directory..."
cd "$FRONTEND_DIR"

# Check if Playwright is installed
if [ ! -f "package.json" ]; then
    echo "❌ package.json not found in $FRONTEND_DIR"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing frontend dependencies..."
    npm install
fi

# Check if Playwright is configured
if grep -q "@playwright/test" package.json; then
    echo "🎬 Running Playwright visual tests..."
    
    # Install Playwright browsers if needed
    if [ ! -d "node_modules/@playwright/test" ]; then
        echo "🌐 Installing Playwright browsers..."
        npx playwright install
    fi
    
    # Run the tests
    if npm run test:visual &>/dev/null; then
        npm run test:visual
    elif npx playwright test &>/dev/null; then
        npx playwright test
    else
        echo "⚠️  Playwright test script not configured. Running default playwright test..."
        npx playwright test --reporter=html
    fi
    
    # Show results
    echo "📊 Test results available at: file://$(pwd)/playwright-report/index.html"
    
else
    echo "⚠️  Playwright not configured in this frontend service."
    echo "💡 To set up Playwright:"
    echo "   npm install --save-dev @playwright/test"
    echo "   npx playwright install"
fi

cd - > /dev/null
echo "✅ Visual tests completed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"