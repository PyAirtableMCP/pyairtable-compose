#!/bin/bash

# PyAirtable Microservices - Stop Script
# Stops all services gracefully

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOG_DIR="/tmp/pyairtable-logs"

# Service ports
PORTS=(8001 8002 8003 3000)
SERVICE_NAMES=("mcp-server" "airtable-gateway" "llm-orchestrator" "frontend")

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

# Function to stop service by port
stop_service_by_port() {
    local port=$1
    local service_name=$2
    
    if check_port $port; then
        print_info "Stopping $service_name on port $port..."
        
        # Get PID
        local pid=$(lsof -ti:$port)
        
        if [ ! -z "$pid" ]; then
            # Try graceful shutdown first
            kill -TERM $pid 2>/dev/null || true
            
            # Wait up to 10 seconds for graceful shutdown
            for i in {1..10}; do
                if ! kill -0 $pid 2>/dev/null; then
                    print_status "$service_name stopped gracefully"
                    return 0
                fi
                sleep 1
            done
            
            # Force kill if still running
            print_warning "Force killing $service_name (PID: $pid)..."
            kill -9 $pid 2>/dev/null || true
            sleep 1
            
            if ! kill -0 $pid 2>/dev/null; then
                print_status "$service_name force stopped"
            else
                print_error "Failed to stop $service_name"
                return 1
            fi
        fi
    else
        print_info "$service_name is not running on port $port"
    fi
}

# Function to stop service by PID file
stop_service_by_pid() {
    local service_name=$1
    local pid_file="$LOG_DIR/${service_name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        
        if kill -0 $pid 2>/dev/null; then
            print_info "Stopping $service_name (PID: $pid)..."
            
            # Try graceful shutdown
            kill -TERM $pid 2>/dev/null || true
            
            # Wait for graceful shutdown
            for i in {1..10}; do
                if ! kill -0 $pid 2>/dev/null; then
                    print_status "$service_name stopped gracefully"
                    rm -f "$pid_file"
                    return 0
                fi
                sleep 1
            done
            
            # Force kill
            print_warning "Force killing $service_name..."
            kill -9 $pid 2>/dev/null || true
            sleep 1
            
            if ! kill -0 $pid 2>/dev/null; then
                print_status "$service_name force stopped"
                rm -f "$pid_file"
            else
                print_error "Failed to stop $service_name"
                return 1
            fi
        else
            print_info "Removing stale PID file for $service_name"
            rm -f "$pid_file"
        fi
    fi
}

# Function to clean up processes
cleanup_processes() {
    print_info "Looking for Python processes running microservices..."
    
    # Find and kill Python processes running our services
    local killed=0
    
    # Look for specific service processes (Python services)
    for process in $(pgrep -f "python.*main.py" 2>/dev/null || true); do
        local cmd=$(ps -p $process -o command= 2>/dev/null || echo "")
        
        # Check if it's one of our Python services
        if [[ "$cmd" == *"airtable-gateway"* ]] || [[ "$cmd" == *"mcp-server"* ]] || [[ "$cmd" == *"llm-orchestrator"* ]]; then
            print_info "Killing Python process: $process ($cmd)"
            kill -9 $process 2>/dev/null || true
            killed=$((killed + 1))
        fi
    done
    
    # Look for Node.js frontend processes
    for process in $(pgrep -f "node.*next" 2>/dev/null || true); do
        local cmd=$(ps -p $process -o command= 2>/dev/null || echo "")
        
        # Check if it's our frontend service
        if [[ "$cmd" == *"next"* ]] || [[ "$cmd" == *"pyairtable-frontend"* ]]; then
            print_info "Killing Node.js process: $process ($cmd)"
            kill -9 $process 2>/dev/null || true
            killed=$((killed + 1))
        fi
    done
    
    # Look for npm/yarn dev processes
    for process in $(pgrep -f "npm.*dev\|yarn.*dev" 2>/dev/null || true); do
        local cmd=$(ps -p $process -o command= 2>/dev/null || echo "")
        print_info "Killing dev process: $process ($cmd)"
        kill -9 $process 2>/dev/null || true
        killed=$((killed + 1))
    done
    
    if [ $killed -gt 0 ]; then
        print_status "Cleaned up $killed processes"
    else
        print_info "No cleanup needed"
    fi
}

# Function to show final status
show_status() {
    echo ""
    echo -e "${BLUE}📊 Final Status${NC}"
    echo "================"
    
    local all_stopped=true
    
    for i in "${!PORTS[@]}"; do
        local port=${PORTS[$i]}
        local service_name=${SERVICE_NAMES[$i]}
        
        if check_port $port; then
            print_error "$service_name: Still running on port $port"
            all_stopped=false
        else
            print_status "$service_name: Stopped"
        fi
    done
    
    echo ""
    if [ "$all_stopped" = true ]; then
        echo -e "${GREEN}🎉 All services stopped successfully!${NC}"
    else
        echo -e "${YELLOW}⚠️  Some services may still be running${NC}"
        echo "You may need to manually kill remaining processes."
    fi
}

# Main function
main() {
    echo -e "${BLUE}🛑 Stopping PyAirtable Microservices${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo ""
    
    # Stop services by PID files first (cleaner)
    print_info "Stopping services using PID files..."
    for service_name in "${SERVICE_NAMES[@]}"; do
        stop_service_by_pid "$service_name"
    done
    
    echo ""
    
    # Stop services by port (fallback)
    print_info "Stopping any remaining services by port..."
    for i in "${!PORTS[@]}"; do
        local port=${PORTS[$i]}
        local service_name=${SERVICE_NAMES[$i]}
        stop_service_by_port $port "$service_name"
    done
    
    echo ""
    
    # Additional cleanup
    cleanup_processes
    
    # Clean up log directory
    if [ -d "$LOG_DIR" ]; then
        print_info "Cleaning up PID files..."
        rm -f "$LOG_DIR"/*.pid
        print_status "PID files cleaned"
    fi
    
    # Show final status
    show_status
    
    echo ""
    echo -e "${BLUE}ℹ️  Logs are preserved at: $LOG_DIR${NC}"
    echo -e "${BLUE}ℹ️  To restart services: ./start.sh${NC}"
}

# Handle command line arguments
case "${1:-}" in
    "force")
        print_warning "Force stopping all service processes..."
        killall python3 2>/dev/null || true
        killall python 2>/dev/null || true
        killall node 2>/dev/null || true
        killall npm 2>/dev/null || true
        killall yarn 2>/dev/null || true
        sleep 2
        show_status
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [force]"
        echo ""
        echo "Commands:"
        echo "  (default)      Stop services gracefully"
        echo "  force          Force kill all Python processes"
        exit 1
        ;;
esac