#!/bin/bash

# PyAirtable Full-Stack Development Script
# Starts backend services + frontend with hot reloading

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

FRONTEND_DIR="../frontend"
COMPOSE_DIR="$(pwd)"

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo -e "${BLUE}🚀 Starting PyAirtable Full-Stack Development Environment${NC}"
echo "================================================================"

# 1. Start backend services
print_info "Starting backend microservices..."
./start.sh

# Wait for services to be ready
print_info "Waiting for services to initialize..."
sleep 5

# Check if services are healthy
if curl -s http://localhost:8000/api/health > /dev/null; then
    print_status "Backend services are healthy"
else
    print_warning "Backend services may still be starting up"
fi

# 2. Start frontend if it exists
if [ -d "$FRONTEND_DIR" ]; then
    print_info "Starting frontend development server..."
    cd "$FRONTEND_DIR"
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        print_info "Installing frontend dependencies..."
        npm install
    fi
    
    # Start frontend in background
    npm run dev &
    FRONTEND_PID=$!
    
    cd "$COMPOSE_DIR"
    print_status "Frontend development server started (PID: $FRONTEND_PID)"
else
    print_warning "Frontend directory not found at $FRONTEND_DIR"
    print_info "Create frontend app with: npx create-next-app@latest ../frontend"
fi

echo ""
echo -e "${GREEN}🎉 Full-Stack Development Environment Ready!${NC}"
echo ""
echo -e "${BLUE}Available Services:${NC}"
echo "• API Gateway: http://localhost:8000"
echo "• Frontend: http://localhost:3000"
echo "• LLM Orchestrator: http://localhost:8003"
echo "• MCP Server: http://localhost:8001"
echo "• Airtable Gateway: http://localhost:8002"
echo ""
echo -e "${YELLOW}Development Tips:${NC}"
echo "• Backend changes auto-reload via Docker volumes"
echo "• Frontend has hot module reloading"
echo "• API gateway proxies all backend requests"
echo "• Use ./stop-fullstack.sh to stop everything"
echo ""
echo "Press Ctrl+C to stop frontend, then run ./stop.sh for backend"

# Keep script running to handle Ctrl+C
if [ ! -z "$FRONTEND_PID" ]; then
    trap "kill $FRONTEND_PID 2>/dev/null; exit" INT TERM
    wait $FRONTEND_PID
fi