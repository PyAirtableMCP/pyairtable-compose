#!/bin/bash

# PyAirtable Log Aggregation and Monitoring Script
# Centralized logging with real-time monitoring for local development
# Provides unified log viewing, searching, and alerting capabilities

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly NAMESPACE="pyairtable"
readonly LOG_DIR="$PROJECT_ROOT/logs"
readonly MONITORING_DIR="$PROJECT_ROOT/monitoring"

# Services to monitor
readonly SERVICES=(
    "api-gateway"
    "llm-orchestrator" 
    "mcp-server"
    "airtable-gateway"
    "platform-services"
    "automation-services"
    "saga-orchestrator"
    "frontend"
    "postgres"
    "redis"
)

# Log levels and their colors
declare -A LOG_COLORS=(
    ["ERROR"]="$RED"
    ["WARN"]="$YELLOW"
    ["INFO"]="$BLUE"
    ["DEBUG"]="$CYAN"
    ["TRACE"]="$PURPLE"
)

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_progress() {
    echo -e "${PURPLE}🔄 $1${NC}"
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Setup log directories
setup_log_directories() {
    print_header "Setting Up Log Directories"
    
    mkdir -p "$LOG_DIR"/{aggregated,services,alerts,archive}
    mkdir -p "$MONITORING_DIR"/{dashboards,config,data}
    
    # Create log files for each service
    for service in "${SERVICES[@]}"; do
        mkdir -p "$LOG_DIR/services/$service"
        touch "$LOG_DIR/services/$service/current.log"
        touch "$LOG_DIR/services/$service/error.log"
    done
    
    # Create aggregated log files
    touch "$LOG_DIR/aggregated/all.log"
    touch "$LOG_DIR/aggregated/errors.log"
    touch "$LOG_DIR/aggregated/warnings.log"
    touch "$LOG_DIR/alerts/system.log"
    
    print_success "Log directories created"
}

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info &>/dev/null; then
        print_error "kubectl is not configured or cluster is not accessible"
        return 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
    
    return 0
}

# Get pod name for service
get_pod_name() {
    local service=$1
    kubectl get pods -l "app=$service" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

# Get service logs
get_service_logs() {
    local service=$1
    local lines=${2:-100}
    local follow=${3:-false}
    
    local pod_name
    pod_name=$(get_pod_name "$service")
    
    if [[ -z "$pod_name" ]]; then
        print_error "Pod not found for service: $service"
        return 1
    fi
    
    if [[ "$follow" == "true" ]]; then
        kubectl logs -f "$pod_name" -n "$NAMESPACE" --tail="$lines"
    else
        kubectl logs "$pod_name" -n "$NAMESPACE" --tail="$lines"
    fi
}

# Colorize log output
colorize_log_line() {
    local line="$1"
    
    # Extract log level if present
    local level=""
    for log_level in "${!LOG_COLORS[@]}"; do
        if echo "$line" | grep -qi "$log_level"; then
            level="$log_level"
            break
        fi
    done
    
    if [[ -n "$level" ]]; then
        echo -e "${LOG_COLORS[$level]}$line${NC}"
    else
        echo "$line"
    fi
}

# Stream logs from single service
stream_service_logs() {
    local service=$1
    local output_file="$LOG_DIR/services/$service/current.log"
    local error_file="$LOG_DIR/services/$service/error.log"
    
    print_info "Streaming logs for $service..."
    
    get_service_logs "$service" 0 true | while IFS= read -r line; do
        local timestamp
        timestamp=$(get_timestamp)
        local formatted_line="[$timestamp] [$service] $line"
        
        # Write to service-specific log
        echo "$formatted_line" >> "$output_file"
        
        # Write to aggregated log
        echo "$formatted_line" >> "$LOG_DIR/aggregated/all.log"
        
        # Check for errors and warnings
        if echo "$line" | grep -qi "error"; then
            echo "$formatted_line" >> "$error_file"
            echo "$formatted_line" >> "$LOG_DIR/aggregated/errors.log"
            
            # Generate alert for errors
            generate_alert "ERROR" "$service" "$line"
        elif echo "$line" | grep -qi "warn"; then
            echo "$formatted_line" >> "$LOG_DIR/aggregated/warnings.log"
            
            # Generate alert for warnings
            generate_alert "WARN" "$service" "$line"
        fi
        
        # Display colored output
        colorize_log_line "$formatted_line"
    done
}

# Stream logs from all services
stream_all_logs() {
    print_header "Starting Log Aggregation"
    
    # Start log streaming for each service in background
    local pids=()
    
    for service in "${SERVICES[@]}"; do
        if kubectl get pods -l "app=$service" -n "$NAMESPACE" &>/dev/null; then
            print_info "Starting log stream for $service"
            stream_service_logs "$service" &
            pids+=($!)
        else
            print_warning "Service $service not running, skipping"
        fi
    done
    
    print_success "Log aggregation started for ${#pids[@]} services"
    print_info "Press Ctrl+C to stop log aggregation"
    
    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

# Generate alert
generate_alert() {
    local level=$1
    local service=$2
    local message=$3
    local timestamp
    timestamp=$(get_timestamp)
    
    local alert_message="[$timestamp] [$level] [$service] $message"
    echo "$alert_message" >> "$LOG_DIR/alerts/system.log"
    
    # Display alert with appropriate color
    case $level in
        "ERROR")
            echo -e "${RED}🚨 ALERT: $alert_message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARNING: $alert_message${NC}"
            ;;
    esac
}

# Search logs
search_logs() {
    local query="$1"
    local service="${2:-all}"
    local lines="${3:-50}"
    
    print_header "Searching Logs: '$query'"
    
    local search_files=()
    
    if [[ "$service" == "all" ]]; then
        search_files+=("$LOG_DIR/aggregated/all.log")
    else
        if [[ -f "$LOG_DIR/services/$service/current.log" ]]; then
            search_files+=("$LOG_DIR/services/$service/current.log")
        else
            print_error "Service log not found: $service"
            return 1
        fi
    fi
    
    for file in "${search_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_info "Searching in: $(basename "$file")"
            grep -i "$query" "$file" | tail -n "$lines" | while IFS= read -r line; do
                colorize_log_line "$line"
            done
        fi
    done
}

# Display log statistics
show_log_stats() {
    print_header "Log Statistics"
    
    # Overall statistics
    local total_logs
    total_logs=$(wc -l < "$LOG_DIR/aggregated/all.log" 2>/dev/null || echo "0")
    local error_logs
    error_logs=$(wc -l < "$LOG_DIR/aggregated/errors.log" 2>/dev/null || echo "0")
    local warning_logs
    warning_logs=$(wc -l < "$LOG_DIR/aggregated/warnings.log" 2>/dev/null || echo "0")
    
    echo "Overall Statistics:"
    echo "  Total log entries: $total_logs"
    echo "  Error entries: $error_logs"
    echo "  Warning entries: $warning_logs"
    echo ""
    
    # Service statistics
    echo "Service Statistics:"
    printf "%-20s %-10s %-10s %-10s\n" "Service" "Total" "Errors" "Warnings"
    printf "%-20s %-10s %-10s %-10s\n" "-------" "-----" "------" "--------"
    
    for service in "${SERVICES[@]}"; do
        local service_log="$LOG_DIR/services/$service/current.log"
        local error_log="$LOG_DIR/services/$service/error.log"
        
        if [[ -f "$service_log" ]]; then
            local total
            total=$(wc -l < "$service_log" 2>/dev/null || echo "0")
            local errors
            errors=$(wc -l < "$error_log" 2>/dev/null || echo "0")
            local warnings
            warnings=$(grep -c -i "warn" "$service_log" 2>/dev/null || echo "0")
            
            printf "%-20s %-10s %-10s %-10s\n" "$service" "$total" "$errors" "$warnings"
        fi
    done
    
    echo ""
    
    # Recent activity
    echo "Recent Activity (last 10 minutes):"
    local ten_minutes_ago
    ten_minutes_ago=$(date -d '10 minutes ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v-10M '+%Y-%m-%d %H:%M:%S')
    
    if [[ -f "$LOG_DIR/aggregated/all.log" ]]; then
        local recent_logs
        recent_logs=$(awk -v since="$ten_minutes_ago" '$0 >= since' "$LOG_DIR/aggregated/all.log" | wc -l)
        echo "  Log entries in last 10 minutes: $recent_logs"
    fi
}

# Tail logs with live updates
tail_logs() {
    local service="${1:-all}"
    local lines="${2:-50}"
    
    print_header "Tailing Logs: $service"
    
    if [[ "$service" == "all" ]]; then
        if [[ -f "$LOG_DIR/aggregated/all.log" ]]; then
            tail -n "$lines" -f "$LOG_DIR/aggregated/all.log" | while IFS= read -r line; do
                colorize_log_line "$line"
            done
        else
            print_warning "Aggregated log file not found. Starting log aggregation..."
            stream_all_logs
        fi
    else
        local service_log="$LOG_DIR/services/$service/current.log"
        if [[ -f "$service_log" ]]; then
            tail -n "$lines" -f "$service_log" | while IFS= read -r line; do
                colorize_log_line "$line"
            done
        else
            # If local log doesn't exist, stream directly from Kubernetes
            print_info "Local log not found, streaming directly from Kubernetes..."
            get_service_logs "$service" "$lines" true | while IFS= read -r line; do
                colorize_log_line "$(get_timestamp) [$service] $line"
            done
        fi
    fi
}

# Export logs
export_logs() {
    local service="${1:-all}"
    local format="${2:-text}"
    local output_file="${3:-}"
    
    print_header "Exporting Logs"
    
    local source_file=""
    local default_filename=""
    
    if [[ "$service" == "all" ]]; then
        source_file="$LOG_DIR/aggregated/all.log"
        default_filename="pyairtable_all_logs_$(date +%Y%m%d_%H%M%S)"
    else
        source_file="$LOG_DIR/services/$service/current.log"
        default_filename="pyairtable_${service}_logs_$(date +%Y%m%d_%H%M%S)"
    fi
    
    if [[ ! -f "$source_file" ]]; then
        print_error "Log file not found: $source_file"
        return 1
    fi
    
    if [[ -z "$output_file" ]]; then
        output_file="$LOG_DIR/archive/${default_filename}.${format}"
    fi
    
    case $format in
        "text")
            cp "$source_file" "$output_file"
            ;;
        "json")
            {
                echo "{"
                echo "  \"export_timestamp\": \"$(date -Iseconds)\","
                echo "  \"service\": \"$service\","
                echo "  \"logs\": ["
                
                local first=true
                while IFS= read -r line; do
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        echo ","
                    fi
                    echo -n "    \"$(echo "$line" | sed 's/"/\\"/g')\""
                done < "$source_file"
                
                echo ""
                echo "  ]"
                echo "}"
            } > "$output_file"
            ;;
        "csv")
            {
                echo "timestamp,service,level,message"
                while IFS= read -r line; do
                    # Basic parsing - in production you'd want more sophisticated parsing
                    local timestamp=$(echo "$line" | grep -o '\[.*\]' | head -1 | tr -d '[]')
                    local service_name=$(echo "$line" | grep -o '\[.*\]' | sed -n '2p' | tr -d '[]')
                    local level="INFO"  # Default level
                    local message=$(echo "$line" | sed 's/\[.*\] \[.*\] //')
                    
                    # Extract log level if present
                    for log_level in "${!LOG_COLORS[@]}"; do
                        if echo "$message" | grep -qi "$log_level"; then
                            level="$log_level"
                            break
                        fi
                    done
                    
                    echo "\"$timestamp\",\"$service_name\",\"$level\",\"$message\""
                done < "$source_file"
            } > "$output_file"
            ;;
        *)
            print_error "Unknown format: $format"
            print_info "Available formats: text, json, csv"
            return 1
            ;;
    esac
    
    print_success "Logs exported to: $output_file"
}

# Clean up old logs
cleanup_logs() {
    local days="${1:-7}"
    
    print_header "Cleaning Up Old Logs"
    
    print_info "Removing logs older than $days days..."
    
    # Archive current logs before cleanup
    local archive_date
    archive_date=$(date +%Y%m%d_%H%M%S)
    
    for service in "${SERVICES[@]}"; do
        local service_log="$LOG_DIR/services/$service/current.log"
        
        if [[ -f "$service_log" && -s "$service_log" ]]; then
            local archive_file="$LOG_DIR/archive/${service}_${archive_date}.log"
            cp "$service_log" "$archive_file"
            > "$service_log"  # Truncate current log
            print_info "Archived $service logs to: $archive_file"
        fi
    done
    
    # Clean up old archive files
    find "$LOG_DIR/archive" -name "*.log" -mtime "+$days" -delete 2>/dev/null || true
    
    # Truncate aggregated logs
    > "$LOG_DIR/aggregated/all.log"
    > "$LOG_DIR/aggregated/errors.log"
    > "$LOG_DIR/aggregated/warnings.log"
    > "$LOG_DIR/alerts/system.log"
    
    print_success "Log cleanup completed"
}

# Show real-time dashboard
show_dashboard() {
    print_header "PyAirtable Log Dashboard"
    
    while true; do
        clear
        
        # Header
        echo -e "${BLUE}PyAirtable Log Dashboard - $(get_timestamp)${NC}"
        echo "=================================="
        echo ""
        
        # Service status
        echo -e "${PURPLE}Service Status:${NC}"
        for service in "${SERVICES[@]}"; do
            local pod_name
            pod_name=$(get_pod_name "$service")
            
            if [[ -n "$pod_name" ]]; then
                local status
                status=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                
                case $status in
                    "Running")
                        echo -e "  ${GREEN}🟢 $service${NC} - Running"
                        ;;
                    "Pending")
                        echo -e "  ${YELLOW}🟡 $service${NC} - Pending"
                        ;;
                    *)
                        echo -e "  ${RED}🔴 $service${NC} - $status"
                        ;;
                esac
            else
                echo -e "  ${RED}🔴 $service${NC} - Not Found"
            fi
        done
        
        echo ""
        
        # Recent log activity
        echo -e "${PURPLE}Recent Activity (last 5 lines):${NC}"
        if [[ -f "$LOG_DIR/aggregated/all.log" ]]; then
            tail -n 5 "$LOG_DIR/aggregated/all.log" | while IFS= read -r line; do
                colorize_log_line "  $line"
            done
        else
            echo "  No logs available"
        fi
        
        echo ""
        
        # Alert summary
        echo -e "${PURPLE}Recent Alerts:${NC}"
        if [[ -f "$LOG_DIR/alerts/system.log" ]]; then
            tail -n 3 "$LOG_DIR/alerts/system.log" | while IFS= read -r line; do
                if echo "$line" | grep -qi "error"; then
                    echo -e "  ${RED}$line${NC}"
                elif echo "$line" | grep -qi "warn"; then
                    echo -e "  ${YELLOW}$line${NC}"
                else
                    echo "  $line"
                fi
            done
        else
            echo "  No alerts"
        fi
        
        echo ""
        echo "Press Ctrl+C to exit dashboard"
        
        sleep 5
    done
}

# Main function
main() {
    local command=${1:-"help"}
    
    # Ensure kubectl is available for most commands
    if [[ "$command" != "help" && "$command" != "setup" && "$command" != "export" && "$command" != "cleanup" ]]; then
        if ! check_kubectl; then
            return 1
        fi
    fi
    
    case $command in
        "setup")
            setup_log_directories
            ;;
        "stream")
            local service=${2:-"all"}
            setup_log_directories
            if [[ "$service" == "all" ]]; then
                stream_all_logs
            else
                stream_service_logs "$service"
            fi
            ;;
        "tail")
            local service=${2:-"all"}
            local lines=${3:-50}
            tail_logs "$service" "$lines"
            ;;
        "search")
            local query=${2:-""}
            local service=${3:-"all"}
            local lines=${4:-50}
            
            if [[ -z "$query" ]]; then
                print_error "Search query required"
                echo "Usage: $0 search <query> [service] [lines]"
                exit 1
            fi
            
            search_logs "$query" "$service" "$lines"
            ;;
        "stats")
            show_log_stats
            ;;
        "export")
            local service=${2:-"all"}
            local format=${3:-"text"}
            local output_file=${4:-""}
            export_logs "$service" "$format" "$output_file"
            ;;
        "cleanup")
            local days=${2:-7}
            cleanup_logs "$days"
            ;;
        "dashboard")
            show_dashboard
            ;;
        "help"|"-h"|"--help")
            echo "PyAirtable Log Aggregator and Monitor"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  setup                    Setup log directories"
            echo "  stream [SERVICE]         Stream logs from service or all services"
            echo "  tail [SERVICE] [LINES]   Tail logs with live updates (default: all, 50)"
            echo "  search QUERY [SERVICE] [LINES]  Search logs for query"
            echo "  stats                    Show log statistics"
            echo "  export [SERVICE] [FORMAT] [FILE]  Export logs (text|json|csv)"
            echo "  cleanup [DAYS]           Clean up logs older than N days (default: 7)"
            echo "  dashboard                Show real-time dashboard"
            echo "  help                     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 setup                 # Initialize log directories"
            echo "  $0 stream                # Stream all service logs"
            echo "  $0 tail api-gateway      # Tail API gateway logs"
            echo "  $0 search \"error\" postgres # Search for errors in postgres logs"
            echo "  $0 export all json       # Export all logs as JSON"
            echo "  $0 dashboard             # Show real-time dashboard"
            echo ""
            echo "Log Files:"
            echo "  $LOG_DIR/aggregated/all.log      # All service logs"
            echo "  $LOG_DIR/aggregated/errors.log   # Error logs only"
            echo "  $LOG_DIR/services/*/current.log  # Individual service logs"
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"