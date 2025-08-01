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
    
    # Activate virtual environment and start service
    cd "$full_path"
    
    if [ ! -d "venv" ]; then
        print_error "Virtual environment not found for $service_name"
        print_info "Please run ./setup.sh first"
        return 1
    fi
    
    source venv/bin/activate
    
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
    esac
    
    local pid=$!
    echo $pid > "$LOG_DIR/${service_name}.pid"
    
    deactivate
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
    
    local health_url="http://localhost:$port/health"
    
    print_info "Checking health of $service_name..."
    
    # Wait up to 30 seconds for service to be healthy
    for i in {1..30}; do
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
    echo "• LLM Orchestrator: http://localhost:8003"
    echo "• LLM Orchestrator Health: http://localhost:8003/health"
    echo "• MCP Server: http://localhost:8001"
    echo "• MCP Server Tools: http://localhost:8001/tools"
    echo "• Airtable Gateway: http://localhost:8002"
    echo "• Airtable Gateway Health: http://localhost:8002/health"
    
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
    
    # 1. Start Airtable Gateway first (no dependencies)
    start_service "airtable-gateway" "8002" "airtable-gateway-py"
    
    # 2. Start MCP Server (depends on Airtable Gateway)
    start_service "mcp-server" "8001" "mcp-server-py"
    
    # 3. Start LLM Orchestrator (depends on MCP Server)
    start_service "llm-orchestrator" "8003" "llm-orchestrator-py"
    
    echo ""
    print_info "Waiting for services to fully initialize..."
    sleep 5
    
    # Health checks
    echo ""
    print_info "Running health checks..."
    check_health "airtable-gateway" "8002"
    check_health "mcp-server" "8001"
    check_health "llm-orchestrator" "8003"
    
    # Show final status
    show_status
    
    echo ""
    echo -e "${GREEN}🎉 All services started successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Quick Test Commands:${NC}"
    echo "curl http://localhost:8003/health"
    echo "curl http://localhost:8001/tools"
    echo "curl http://localhost:8002/health"
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
        echo "Services: airtable-gateway, mcp-server, llm-orchestrator"
        exit 1
        ;;
esac