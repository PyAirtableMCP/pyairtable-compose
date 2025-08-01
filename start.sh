#!/bin/bash

# PyAirtable Microservices - Start Script
# Starts all services for local development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SERVICES_DIR="/Users/kg/IdeaProjects"
LOG_DIR="/tmp/pyairtable-logs"

# Service definitions (service_name:port:directory)
declare -A SERVICES=(
    ["airtable-gateway"]="8002:airtable-gateway-py"
    ["mcp-server"]="8001:mcp-server-py" 
    ["llm-orchestrator"]="8003:llm-orchestrator-py"
    ["auth-service"]="8007:pyairtable-auth-service"
    ["workflow-engine"]="8004:pyairtable-workflow-engine"
    ["analytics-service"]="8005:pyairtable-analytics-service"
    ["file-processor"]="8006:pyairtable-file-processor"
    ["frontend"]="3000:pyairtable-frontend"
)

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to check if port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to kill process on port
kill_port() {
    local port=$1
    local pid=$(lsof -ti:$port)
    if [ ! -z "$pid" ]; then
        print_info "Killing process on port $port (PID: $pid)"
        kill -9 $pid 2>/dev/null || true
        sleep 1
    fi
}

# Function to start a service
start_service() {
    local service_name=$1
    local port=$2
    local service_dir=$3
    local full_path="$SERVICES_DIR/$service_dir"
    
    print_info "Starting $service_name on port $port..."
    
    # Check if directory exists
    if [ ! -d "$full_path" ]; then
        print_error "Service directory not found: $full_path"
        return 1
    fi
    
    # Kill existing process on port
    if check_port $port; then
        print_warning "Port $port is already in use, killing existing process..."
        kill_port $port
    fi
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Activate appropriate environment and start service
    cd "$full_path"
    
    # Handle Python services
    if [[ "$service_name" != "frontend" ]]; then
        if [ ! -d "venv" ]; then
            print_error "Virtual environment not found for $service_name"
            print_info "Please run ./setup.sh first"
            return 1
        fi
        source venv/bin/activate
    else
        # Handle Node.js frontend
        if [ ! -f "package.json" ]; then
            print_error "package.json not found for $service_name"
            print_info "Please run ./setup.sh first"
            return 1
        fi
        
        if [ ! -d "node_modules" ]; then
            print_error "Node modules not found for $service_name"
            print_info "Please run ./setup.sh first"
            return 1
        fi
    fi
    
    # Start service based on type
    case $service_name in
        "airtable-gateway")
            nohup python src/main.py > "$LOG_DIR/${service_name}.log" 2>&1 &
            ;;
        "mcp-server")
            nohup python -m src.server --http > "$LOG_DIR/${service_name}.log" 2>&1 &
            ;;
        "llm-orchestrator")
            nohup python src/main.py > "$LOG_DIR/${service_name}.log" 2>&1 &
            ;;
        "auth-service"|"workflow-engine"|"analytics-service"|"file-processor")
            # Phase 3 Python services
            nohup python src/main.py > "$LOG_DIR/${service_name}.log" 2>&1 &
            ;;
        "frontend")
            # Check if we should use yarn or npm
            if [ -f "yarn.lock" ]; then
                nohup yarn dev > "$LOG_DIR/${service_name}.log" 2>&1 &
            else
                nohup npm run dev > "$LOG_DIR/${service_name}.log" 2>&1 &
            fi
            ;;
    esac
    
    local pid=$!
    echo $pid > "$LOG_DIR/${service_name}.pid"
    
    # Deactivate Python virtual environment if it was activated
    if [[ "$service_name" != "frontend" ]]; then
        deactivate
    fi
    cd - > /dev/null
    
    # Wait a moment and check if service started
    sleep 2
    if check_port $port; then
        print_status "$service_name started successfully on port $port (PID: $pid)"
    else
        print_error "$service_name failed to start"
        print_info "Check logs: tail -f $LOG_DIR/${service_name}.log"
        return 1
    fi
}

# Function to check service health
check_health() {
    local service_name=$1
    local port=$2
    
    # Different health check endpoints for different services
    local health_url
    case $service_name in
        "frontend")
            health_url="http://localhost:$port/api/health"
            ;;
        *)
            health_url="http://localhost:$port/health"
            ;;
    esac
    
    print_info "Checking health of $service_name..."
    
    # Frontend needs more time to start up
    local max_attempts=30
    if [[ "$service_name" == "frontend" ]]; then
        max_attempts=60
    fi
    
    # Wait for service to be healthy
    for i in $(seq 1 $max_attempts); do
        if curl -s -f "$health_url" > /dev/null 2>&1; then
            print_status "$service_name is healthy"
            return 0
        fi
        sleep 1
    done
    
    print_warning "$service_name health check failed"
    return 1
}

# Function to show service status
show_status() {
    echo ""
    echo -e "${BLUE}📊 Service Status${NC}"
    echo "=================="
    
    for service_name in "${!SERVICES[@]}"; do
        IFS=':' read -r port service_dir <<< "${SERVICES[$service_name]}"
        
        if check_port $port; then
            print_status "$service_name: Running on port $port"
        else
            print_error "$service_name: Not running"
        fi
    done
    
    echo ""
    echo -e "${BLUE}📋 Service URLs${NC}"
    echo "================"
    echo "• Frontend: http://localhost:3000"
    echo "• Frontend Health: http://localhost:3000/api/health"
    echo "• API Gateway: http://localhost:8000"
    echo "• LLM Orchestrator: http://localhost:8003"
    echo "• LLM Orchestrator Health: http://localhost:8003/health"
    echo "• MCP Server: http://localhost:8001"
    echo "• MCP Server Tools: http://localhost:8001/tools"
    echo "• Airtable Gateway: http://localhost:8002"
    echo "• Airtable Gateway Health: http://localhost:8002/health"
    echo "• Auth Service: http://localhost:8007"
    echo "• Auth Service Health: http://localhost:8007/health"
    echo "• Workflow Engine: http://localhost:8004"
    echo "• Workflow Engine Health: http://localhost:8004/health"
    echo "• Analytics Service: http://localhost:8005"
    echo "• Analytics Service Health: http://localhost:8005/health"
    echo "• File Processor: http://localhost:8006"
    echo "• File Processor Health: http://localhost:8006/health"
    
    echo ""
    echo -e "${BLUE}📝 Logs Location${NC}"
    echo "=================="
    echo "• Log directory: $LOG_DIR"
    echo "• View all logs: tail -f $LOG_DIR/*.log"
    echo "• View specific service: tail -f $LOG_DIR/[service-name].log"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if .env files exist
    for service_name in "${!SERVICES[@]}"; do
        IFS=':' read -r port service_dir <<< "${SERVICES[$service_name]}"
        local env_file="$SERVICES_DIR/$service_dir/.env"
        
        if [ ! -f "$env_file" ]; then
            print_error "Missing .env file for $service_name: $env_file"
            print_info "Please run ./setup.sh first"
            exit 1
        fi
    done
    
    # Check if PostgreSQL is running
    if ! pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
        print_error "PostgreSQL is not running"
        print_info "Start PostgreSQL: brew services start postgresql (macOS)"
        exit 1
    fi
    print_status "PostgreSQL is running"
    
    # Check if Redis is running
    if ! redis-cli ping >/dev/null 2>&1; then
        print_error "Redis is not running" 
        print_info "Start Redis: brew services start redis (macOS)"
        exit 1
    fi
    print_status "Redis is running"
    
    print_status "Prerequisites check passed"
}

# Main function
main() {
    echo -e "${BLUE}🚀 Starting PyAirtable Microservices${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Start services in dependency order
    print_info "Starting services in dependency order..."
    echo ""
    
    # Phase 1: Core services (no dependencies beyond infrastructure)
    # 1. Start Airtable Gateway first (depends only on Redis/PostgreSQL)
    start_service "airtable-gateway" "8002" "airtable-gateway-py"
    
    # 2. Start Auth Service (depends only on Redis/PostgreSQL) - standalone
    start_service "auth-service" "8007" "pyairtable-auth-service"
    
    # Phase 2: Services with single dependencies
    # 3. Start MCP Server (depends on Airtable Gateway)
    start_service "mcp-server" "8001" "mcp-server-py"
    
    # 4. Start Analytics Service (depends on Auth Service)
    start_service "analytics-service" "8005" "pyairtable-analytics-service"
    
    # 5. Start File Processor (depends on Auth Service)
    start_service "file-processor" "8006" "pyairtable-file-processor"
    
    # Phase 3: Services with multiple dependencies
    # 6. Start LLM Orchestrator (depends on MCP Server)
    start_service "llm-orchestrator" "8003" "llm-orchestrator-py"
    
    # 7. Start Workflow Engine (depends on MCP Server and Auth Service)
    start_service "workflow-engine" "8004" "pyairtable-workflow-engine"
    
    # Phase 4: Frontend (depends on all backend services)
    # 8. Start Frontend (depends on all backend services)
    start_service "frontend" "3000" "pyairtable-frontend"
    
    echo ""
    print_info "Waiting for services to fully initialize..."
    sleep 5
    
    # Health checks
    echo ""
    print_info "Running health checks..."
    check_health "airtable-gateway" "8002"
    check_health "auth-service" "8007"
    check_health "mcp-server" "8001"
    check_health "analytics-service" "8005"
    check_health "file-processor" "8006"
    check_health "llm-orchestrator" "8003"
    check_health "workflow-engine" "8004"
    check_health "frontend" "3000"
    
    # Show final status
    show_status
    
    echo ""
    echo -e "${GREEN}🎉 All services started successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Quick Test Commands:${NC}"
    echo "curl http://localhost:3000/api/health"
    echo "curl http://localhost:8003/health"
    echo "curl http://localhost:8001/tools"
    echo "curl http://localhost:8002/health"
    echo "curl http://localhost:8007/health"
    echo "curl http://localhost:8004/health" 
    echo "curl http://localhost:8005/health"
    echo "curl http://localhost:8006/health"
    echo ""
    echo -e "${YELLOW}To stop services:${NC}"
    echo "./stop.sh"
    echo ""
    echo -e "${YELLOW}To view logs:${NC}"
    echo "tail -f $LOG_DIR/*.log"
}

# Handle command line arguments
case "${1:-start}" in
    "start")
        main
        ;;
    "status")
        show_status
        ;;
    "logs")
        if [ -n "$2" ]; then
            tail -f "$LOG_DIR/$2.log"
        else
            tail -f "$LOG_DIR"/*.log
        fi
        ;;
    *)
        echo "Usage: $0 [start|status|logs [service-name]]"
        echo ""
        echo "Commands:"
        echo "  start          Start all services (default)"
        echo "  status         Show service status"
        echo "  logs           Show all logs"
        echo "  logs SERVICE   Show logs for specific service"
        echo ""
        echo "Services: airtable-gateway, auth-service, mcp-server, analytics-service, file-processor, llm-orchestrator, workflow-engine, frontend"
        exit 1
        ;;
esac