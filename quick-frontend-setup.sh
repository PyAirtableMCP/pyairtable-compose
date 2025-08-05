#!/bin/bash

# PyAirtable Quick Frontend Setup Script
# For customer deployment validation

set -e

echo "🚀 PyAirtable Frontend Validation Setup"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "docker-compose.frontend-test.yml" ]; then
    echo -e "${RED}❌ Error: Must be run from pyairtable-compose directory${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Step 1: Environment Setup${NC}"

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️ Creating default .env file...${NC}"
    cat > .env << EOF
# PyAirtable Frontend Test Configuration
# Replace these with customer's actual credentials

# Airtable Configuration (REQUIRED)
AIRTABLE_TOKEN=pat1234567890abcdef
AIRTABLE_BASE=appVLUAubH5cFWhMV

# API Keys
API_KEY=test-api-key

# LLM Configuration (REQUIRED for chat features)
GEMINI_API_KEY=dummy-key

# Database Configuration
POSTGRES_DB=pyairtable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres123

# Redis Configuration
REDIS_PASSWORD=password123

# Logging
LOG_LEVEL=info

# Environment
ENVIRONMENT=development
EOF
    echo -e "${GREEN}✅ Created .env file with defaults${NC}"
    echo -e "${YELLOW}⚠️ IMPORTANT: Update AIRTABLE_TOKEN and GEMINI_API_KEY with real values${NC}"
else
    echo -e "${GREEN}✅ .env file already exists${NC}"
fi

echo -e "${BLUE}📋 Step 2: Backend Services${NC}"

# Stop any existing services
echo "🛑 Stopping existing services..."
docker-compose down &>/dev/null || true

# Start essential backend services
echo "🚀 Starting backend services..."
docker-compose -f docker-compose.frontend-test.yml up -d

echo "⏳ Waiting for services to start..."
sleep 10

# Check service health
echo -e "${BLUE}🏥 Health Check${NC}"
./quick-health-check.sh

echo -e "${BLUE}📋 Step 3: Frontend Setup${NC}"

# Navigate to frontend directory
cd ../pyairtable-frontend

# Install dependencies if node_modules doesn't exist
if [ ! -d "node_modules" ]; then
    echo "📦 Installing frontend dependencies..."
    npm install --legacy-peer-deps
    echo -e "${GREEN}✅ Dependencies installed${NC}"
else
    echo -e "${GREEN}✅ Dependencies already installed${NC}"
fi

# Copy service worker if it doesn't exist
if [ ! -f "public/sw.js" ]; then
    echo "📋 Setting up PWA service worker..."
    mkdir -p public
    cp ../pyairtable-compose/frontend-optimization/public/sw.js public/
    echo -e "${GREEN}✅ Service worker installed${NC}"
fi

echo -e "${BLUE}📋 Step 4: Connectivity Tests${NC}"

# Start frontend in background
echo "🚀 Starting frontend..."
npm run dev > /dev/null 2>&1 &
FRONTEND_PID=$!

# Wait for frontend to start
echo "⏳ Waiting for frontend to start..."
sleep 5

# Test connectivity
echo "🔗 Testing API connectivity..."

# Test API Gateway
if curl -s "http://localhost:3000/api/gateway/health" > /dev/null; then
    echo -e "${GREEN}✅ API Gateway connection: OK${NC}"
else
    echo -e "${RED}❌ API Gateway connection: FAILED${NC}"
fi

# Test LLM Orchestrator
if curl -s "http://localhost:3000/api/llm/health" > /dev/null; then
    echo -e "${GREEN}✅ LLM Orchestrator connection: OK${NC}"
else
    echo -e "${RED}❌ LLM Orchestrator connection: FAILED${NC}"
fi

# Test Airtable Gateway
if curl -s "http://localhost:3000/api/airtable/health" > /dev/null; then
    echo -e "${GREEN}✅ Airtable Gateway connection: OK${NC}"
else
    echo -e "${RED}❌ Airtable Gateway connection: FAILED${NC}"
fi

echo -e "${BLUE}📋 Step 5: Frontend Access${NC}"
echo -e "${GREEN}🎉 Setup Complete!${NC}"
echo ""
echo "Frontend is running at: http://localhost:3000"
echo "Backend API Gateway: http://localhost:8000"
echo ""
echo -e "${YELLOW}📝 Next Steps for Customer:${NC}"
echo "1. Update .env file with real Airtable credentials"
echo "2. Set GEMINI_API_KEY for chat functionality"
echo "3. Access the application at http://localhost:3000"
echo ""
echo -e "${BLUE}🛠️ Available Commands:${NC}"
echo "- Stop services: docker-compose -f docker-compose.frontend-test.yml down"
echo "- View logs: docker-compose -f docker-compose.frontend-test.yml logs -f [service]"
echo "- Restart frontend: npm run dev (in pyairtable-frontend directory)"
echo ""
echo -e "${YELLOW}⚠️ Important Notes:${NC}"
echo "- Frontend process ID: $FRONTEND_PID (kill with: kill $FRONTEND_PID)"
echo "- This is a development setup - not for production use"
echo "- Authentication is in placeholder mode"
echo ""

# Keep the script running to show the frontend is active
echo -e "${BLUE}🔄 Frontend is running... Press Ctrl+C to stop${NC}"
wait $FRONTEND_PID