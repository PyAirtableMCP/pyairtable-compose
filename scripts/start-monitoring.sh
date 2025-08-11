#!/bin/bash

# Emergency Stabilization Day 5: Master Monitoring Startup Script
# Starts all monitoring components for PyAirtable services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Starting PyAirtable Monitoring System"
echo "========================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    print_error "Python 3 is required but not installed"
    exit 1
fi

# Check if required Python packages are available
print_status "Checking Python dependencies..."

python3 -c "import aiohttp, asyncio" 2>/dev/null || {
    print_warning "Missing required Python packages. Installing aiohttp..."
    pip3 install aiohttp
}

# Create necessary directories
mkdir -p /tmp/monitoring-logs

print_success "Python dependencies OK"

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to start a background process
start_process() {
    local name=$1
    local script=$2
    local args=${3:-""}
    local log_file="/tmp/monitoring-logs/${name}.log"
    
    print_status "Starting $name..."
    
    # Start the process in the background
    nohup python3 "$SCRIPT_DIR/$script" $args > "$log_file" 2>&1 &
    local pid=$!
    
    # Wait a moment for the process to start
    sleep 2
    
    # Check if the process is still running
    if kill -0 $pid 2>/dev/null; then
        print_success "$name started (PID: $pid, Log: $log_file)"
        echo $pid > "/tmp/monitoring-logs/${name}.pid"
        return 0
    else
        print_error "$name failed to start"
        return 1
    fi
}

# Trap to cleanup background processes on exit
cleanup() {
    print_status "Cleaning up monitoring processes..."
    
    for pid_file in /tmp/monitoring-logs/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            if kill -0 $pid 2>/dev/null; then
                print_status "Stopping process $pid..."
                kill -TERM $pid 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    done
    
    print_success "Monitoring system stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Check if monitoring dashboard port is available
dashboard_port=9999
if check_port $dashboard_port; then
    print_warning "Port $dashboard_port is already in use. Dashboard may not start properly."
fi

print_status "Starting monitoring components..."

# Start health check monitoring (continuous mode)
start_process "health-checker" "health-check.py" "--continuous --interval 30"

# Give health checker time to generate initial data
print_status "Waiting for initial health data..."
sleep 10

# Start alert manager
start_process "alert-manager" "alert-manager.py" "--monitor --interval 10"

# Start monitoring dashboard
start_process "dashboard" "monitor-dashboard.py" "--port 9999 --interval 30"

print_success "All monitoring components started!"
echo ""
echo "📊 Monitoring Dashboard: http://localhost:9999"
echo "📋 Health API: http://localhost:9999/health"
echo "📝 Log files: /tmp/monitoring-logs/"
echo "📈 Health status: /tmp/health-status.json"
echo "🚨 Alerts: /tmp/alerts.log"
echo ""
echo "Press Ctrl+C to stop all monitoring processes"

# Show current status
print_status "Current process status:"
for pid_file in /tmp/monitoring-logs/*.pid; do
    if [ -f "$pid_file" ]; then
        name=$(basename "$pid_file" .pid)
        pid=$(cat "$pid_file")
        if kill -0 $pid 2>/dev/null; then
            echo "  ✅ $name (PID: $pid)"
        else
            echo "  ❌ $name (not running)"
        fi
    fi
done

echo ""
print_status "Monitoring system is running..."
print_status "You can view logs with: tail -f /tmp/monitoring-logs/*.log"

# Wait indefinitely (until interrupted)
while true; do
    sleep 60
    
    # Check if all processes are still running
    all_running=true
    for pid_file in /tmp/monitoring-logs/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            if ! kill -0 $pid 2>/dev/null; then
                name=$(basename "$pid_file" .pid)
                print_warning "$name process has stopped unexpectedly"
                all_running=false
            fi
        fi
    done
    
    if [ "$all_running" = false ]; then
        print_error "Some monitoring processes have stopped. Check logs for details."
    fi
done