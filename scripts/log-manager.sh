#!/bin/bash

# PyAirtable Log Management System
# Centralized log aggregation, viewing, and analysis for Minikube deployment
# Author: Claude Deployment Engineer

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOGS_DIR="${PROJECT_ROOT}/.logs"
readonly AGGREGATED_LOGS_DIR="${LOGS_DIR}/aggregated"
readonly PARSED_LOGS_DIR="${LOGS_DIR}/parsed"
readonly ARCHIVE_DIR="${LOGS_DIR}/archive"
readonly NAMESPACE="${NAMESPACE:-pyairtable}"

# Log configuration
readonly LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
readonly MAX_LOG_SIZE="${MAX_LOG_SIZE:-100M}"
readonly LOG_BUFFER_SIZE="${LOG_BUFFER_SIZE:-1000}"
readonly TAIL_LINES="${TAIL_LINES:-100}"
readonly FOLLOW_TIMEOUT="${FOLLOW_TIMEOUT:-300}"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m'

# Log level colors
declare -A LOG_LEVEL_COLORS=(
    ["ERROR"]="$RED"
    ["WARN"]="$YELLOW"
    ["WARNING"]="$YELLOW"
    ["INFO"]="$BLUE"
    ["DEBUG"]="$GRAY"
    ["TRACE"]="$GRAY"
    ["FATAL"]="$RED"
    ["PANIC"]="$RED"
)

# Service definitions
declare -A SERVICES=(
    ["api-gateway"]="critical"
    ["frontend"]="high"
    ["airtable-gateway"]="critical"
    ["llm-orchestrator"]="high"
    ["mcp-server"]="high"
    ["platform-services"]="critical"
    ["automation-services"]="medium"
    ["postgres"]="critical"
    ["redis"]="critical"
)

# Logging functions
log() {
    echo -e "${WHITE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_section() {
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  $*${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# Initialize log management system
init_log_system() {
    log_info "Initializing log management system..."
    
    # Create directory structure
    mkdir -p "$LOGS_DIR" "$AGGREGATED_LOGS_DIR" "$PARSED_LOGS_DIR" "$ARCHIVE_DIR"
    chmod 755 "$LOGS_DIR" "$AGGREGATED_LOGS_DIR" "$PARSED_LOGS_DIR" "$ARCHIVE_DIR"
    
    # Create log configuration
    cat > "${LOGS_DIR}/config.json" << EOF
{
    "log_management": {
        "namespace": "$NAMESPACE",
        "retention_days": $LOG_RETENTION_DAYS,
        "max_log_size": "$MAX_LOG_SIZE",
        "buffer_size": $LOG_BUFFER_SIZE,
        "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    },
    "services": $(echo "${!SERVICES[@]}" | tr ' ' '\n' | sort | jq -R . | jq -s .),
    "log_levels": ["ERROR", "WARN", "INFO", "DEBUG", "TRACE"],
    "aggregation": {
        "enabled": true,
        "interval_minutes": 5,
        "compression": true
    }
}
EOF
    
    # Create log patterns file for parsing
    cat > "${LOGS_DIR}/patterns.txt" << 'EOF'
# Log parsing patterns for different services
# Format: SERVICE_NAME:PATTERN:DESCRIPTION

# API Gateway (Go/Fiber)
api-gateway:^\[([A-Z]+)\]\s+(\d{4}\/\d{2}\/\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$:Fiber log format
api-gateway:^time="([^"]+)"\s+level=([a-z]+)\s+msg="([^"]+)":Logrus format

# Python services (standard logging)
*:^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}),\d+\s+-\s+([A-Z]+)\s+-\s+(.+)$:Python logging format
*:^\[([A-Z]+)\]\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.+)$:Custom Python format

# PostgreSQL
postgres:^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+[A-Z]+\s+\[[0-9]+\]\s+(.+)$:PostgreSQL format

# Redis
redis:^(\d+:[A-Z])\s+(\d{2}\s+[A-Z][a-z]+\s+\d{4}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+(.+)$:Redis format

# Generic JSON logs
*:^\{.*"timestamp".*"level".*"message".*\}$:JSON structured logs
EOF
    
    log_success "Log management system initialized"
}

# Get all pods for a service
get_service_pods() {
    local service="$1"
    kubectl get pods -n "$NAMESPACE" -l "app=$service" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""
}

# Check if service exists
service_exists() {
    local service="$1"
    kubectl get service "$service" -n "$NAMESPACE" &>/dev/null
}

# Collect logs from a single service
collect_service_logs() {
    local service="$1"
    local lines="${2:-$TAIL_LINES}"
    local output_file="${3:-}"
    
    log_info "Collecting logs for $service (last $lines lines)..."
    
    if ! service_exists "$service"; then
        log_warning "Service $service not found"
        return 1
    fi
    
    local pods
    pods=$(get_service_pods "$service")
    
    if [[ -z "$pods" ]]; then
        log_warning "No pods found for service $service"
        return 1
    fi
    
    local log_content=""
    local pod_count=0
    
    # Collect logs from all pods
    for pod in $pods; do
        ((pod_count++))
        log_info "  Collecting from pod: $pod"
        
        local pod_logs
        pod_logs=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" 2>/dev/null || echo "")
        
        if [[ -n "$pod_logs" ]]; then
            # Add pod information to logs
            log_content+="=== POD: $pod ===\n"
            log_content+="$pod_logs\n"
            log_content+="=== END POD: $pod ===\n\n"
        fi
    done
    
    # Output to file or stdout
    if [[ -n "$output_file" ]]; then
        echo -e "$log_content" > "$output_file"
        log_success "Logs saved to $output_file ($pod_count pods)"
    else
        echo -e "$log_content"
    fi
    
    return 0
}

# Collect logs from all services
collect_all_logs() {
    local lines="${1:-$TAIL_LINES}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    log_section "COLLECTING LOGS FROM ALL SERVICES"
    
    init_log_system
    
    local collected_services=0
    local failed_services=0
    
    for service in "${!SERVICES[@]}"; do
        local output_file="${AGGREGATED_LOGS_DIR}/${service}_${timestamp}.log"
        
        if collect_service_logs "$service" "$lines" "$output_file"; then
            ((collected_services++))
        else
            ((failed_services++))
        fi
    done
    
    # Create master log file with all services
    local master_file="${AGGREGATED_LOGS_DIR}/all_services_${timestamp}.log"
    log_info "Creating master log file: $master_file"
    
    {
        echo "# PyAirtable Complete Log Collection"
        echo "# Generated: $(date)"
        echo "# Namespace: $NAMESPACE"
        echo "# Services: $collected_services collected, $failed_services failed"
        echo "# Lines per service: $lines"
        echo ""
        
        for service in $(printf '%s\n' "${!SERVICES[@]}" | sort); do
            local service_file="${AGGREGATED_LOGS_DIR}/${service}_${timestamp}.log"
            if [[ -f "$service_file" ]]; then
                echo "################################################################################"
                echo "# SERVICE: $service"
                echo "################################################################################"
                cat "$service_file"
                echo ""
            fi
        done
    } > "$master_file"
    
    # Compress the master file
    gzip "$master_file"
    local compressed_file="${master_file}.gz"
    local file_size
    file_size=$(ls -lh "$compressed_file" | awk '{print $5}')
    
    log_success "Master log file created: $(basename "$compressed_file") ($file_size)"
    log_success "Log collection completed: $collected_services services, $failed_services failures"
}

# Parse and colorize log lines
colorize_log_line() {
    local line="$1"
    local service="${2:-unknown}"
    
    # Extract log level from line
    local log_level=""
    
    # Try different log level patterns
    if [[ "$line" =~ \[(ERROR|FATAL|PANIC)\] ]]; then
        log_level="ERROR"
    elif [[ "$line" =~ \[(WARN|WARNING)\] ]]; then
        log_level="WARN"
    elif [[ "$line" =~ \[INFO\] ]]; then
        log_level="INFO"
    elif [[ "$line" =~ \[(DEBUG|TRACE)\] ]]; then
        log_level="DEBUG"
    elif [[ "$line" =~ level=(error|fatal|panic) ]]; then
        log_level="ERROR"
    elif [[ "$line" =~ level=(warn|warning) ]]; then
        log_level="WARN"
    elif [[ "$line" =~ level=info ]]; then
        log_level="INFO"
    elif [[ "$line" =~ level=(debug|trace) ]]; then
        log_level="DEBUG"
    elif [[ "$line" =~ ERROR|FATAL|PANIC ]]; then
        log_level="ERROR"
    elif [[ "$line" =~ WARN ]]; then
        log_level="WARN"
    elif [[ "$line" =~ INFO ]]; then
        log_level="INFO"
    fi
    
    # Apply coloring
    local color="${LOG_LEVEL_COLORS[$log_level]:-$NC}"
    local service_color="${CYAN}"
    
    # Format: [SERVICE] [LEVEL] line content
    if [[ -n "$log_level" ]]; then
        echo -e "${service_color}[$service]${NC} ${color}[$log_level]${NC} ${line}"
    else
        echo -e "${service_color}[$service]${NC} ${line}"
    fi
}

# View logs with filtering and coloring
view_logs() {
    local service="${1:-all}"
    local lines="${2:-$TAIL_LINES}"
    local level_filter="${3:-}"
    local search_pattern="${4:-}"
    
    log_section "VIEWING LOGS"
    
    if [[ "$service" == "all" ]]; then
        log_info "Viewing logs from all services (last $lines lines per service)"
        
        for svc in $(printf '%s\n' "${!SERVICES[@]}" | sort); do
            echo -e "\n${PURPLE}━━━ $svc ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            
            local pods
            pods=$(get_service_pods "$svc")
            
            if [[ -z "$pods" ]]; then
                echo -e "${YELLOW}No pods found for $svc${NC}"
                continue
            fi
            
            for pod in $pods; do
                echo -e "${GRAY}--- Pod: $pod ---${NC}"
                
                # Get logs and apply filtering
                local log_output
                log_output=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" 2>/dev/null || echo "No logs available")
                
                # Apply level filter if specified
                if [[ -n "$level_filter" ]]; then
                    log_output=$(echo "$log_output" | grep -i "$level_filter" || echo "No logs matching level: $level_filter")
                fi
                
                # Apply search pattern if specified
                if [[ -n "$search_pattern" ]]; then
                    log_output=$(echo "$log_output" | grep -i "$search_pattern" || echo "No logs matching pattern: $search_pattern")
                fi
                
                # Colorize and display
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        colorize_log_line "$line" "$svc"
                    fi
                done <<< "$log_output"
            done
        done
    else
        log_info "Viewing logs for service: $service"
        
        if ! service_exists "$service"; then
            log_error "Service $service not found"
            return 1
        fi
        
        local pods
        pods=$(get_service_pods "$service")
        
        if [[ -z "$pods" ]]; then
            log_error "No pods found for service $service"
            return 1
        fi
        
        for pod in $pods; do
            echo -e "${GRAY}--- Pod: $pod ---${NC}"
            
            # Get logs and apply filtering
            local log_output
            log_output=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" 2>/dev/null || echo "No logs available")
            
            # Apply level filter if specified
            if [[ -n "$level_filter" ]]; then
                log_output=$(echo "$log_output" | grep -i "$level_filter" || echo "No logs matching level: $level_filter")
            fi
            
            # Apply search pattern if specified
            if [[ -n "$search_pattern" ]]; then
                log_output=$(echo "$log_output" | grep -i "$search_pattern" || echo "No logs matching pattern: $search_pattern")
            fi
            
            # Colorize and display
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    colorize_log_line "$line" "$service"
                fi
            done <<< "$log_output"
        done
    fi
}

# Follow logs in real-time
follow_logs() {
    local service="${1:-all}"
    local level_filter="${2:-}"
    
    log_section "FOLLOWING LOGS (Press Ctrl+C to stop)"
    
    if [[ "$service" == "all" ]]; then
        log_info "Following logs from all services..."
        
        # Create background processes for each service
        local pids=()
        
        for svc in "${!SERVICES[@]}"; do
            if service_exists "$svc"; then
                local pods
                pods=$(get_service_pods "$svc")
                
                for pod in $pods; do
                    {
                        kubectl logs -n "$NAMESPACE" "$pod" -f 2>/dev/null | while IFS= read -r line; do
                            # Apply level filter if specified
                            if [[ -n "$level_filter" && ! "$line" =~ $level_filter ]]; then
                                continue
                            fi
                            
                            colorize_log_line "$line" "$svc"
                        done
                    } &
                    pids+=($!)
                done
            fi
        done
        
        # Wait for interrupt
        trap 'log_info "Stopping log following..."; kill ${pids[@]} 2>/dev/null; exit 0' INT TERM
        wait
        
    else
        log_info "Following logs for service: $service"
        
        if ! service_exists "$service"; then
            log_error "Service $service not found"
            return 1
        fi
        
        local pods
        pods=$(get_service_pods "$service")
        
        if [[ -z "$pods" ]]; then
            log_error "No pods found for service $service"
            return 1
        fi
        
        # Create background processes for each pod
        local pids=()
        
        for pod in $pods; do
            {
                kubectl logs -n "$NAMESPACE" "$pod" -f 2>/dev/null | while IFS= read -r line; do
                    # Apply level filter if specified
                    if [[ -n "$level_filter" && ! "$line" =~ $level_filter ]]; then
                        continue
                    fi
                    
                    colorize_log_line "$line" "$service"
                done
            } &
            pids+=($!)
        done
        
        # Wait for interrupt
        trap 'log_info "Stopping log following..."; kill ${pids[@]} 2>/dev/null; exit 0' INT TERM
        wait
    fi
}

# Search logs across all services
search_logs() {
    local pattern="$1"
    local service="${2:-all}"
    local lines="${3:-$TAIL_LINES}"
    local case_sensitive="${4:-false}"
    
    log_section "SEARCHING LOGS"
    
    if [[ -z "$pattern" ]]; then
        log_error "Search pattern is required"
        return 1
    fi
    
    log_info "Searching for pattern: '$pattern'"
    
    local grep_flags="-n"
    if [[ "$case_sensitive" != "true" ]]; then
        grep_flags+="i"
    fi
    
    local services_to_search=()
    if [[ "$service" == "all" ]]; then
        services_to_search=($(printf '%s\n' "${!SERVICES[@]}" | sort))
    else
        if [[ -n "${SERVICES[$service]:-}" ]]; then
            services_to_search=("$service")
        else
            log_error "Service $service not found"
            return 1
        fi
    fi
    
    local total_matches=0
    
    for svc in "${services_to_search[@]}"; do
        echo -e "\n${PURPLE}━━━ Searching in $svc ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        local pods
        pods=$(get_service_pods "$svc")
        
        if [[ -z "$pods" ]]; then
            echo -e "${YELLOW}No pods found for $svc${NC}"
            continue
        fi
        
        local service_matches=0
        
        for pod in $pods; do
            local log_output
            log_output=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" 2>/dev/null || echo "")
            
            if [[ -n "$log_output" ]]; then
                local matches
                matches=$(echo "$log_output" | grep $grep_flags "$pattern" || true)
                
                if [[ -n "$matches" ]]; then
                    echo -e "${GRAY}--- Pod: $pod ---${NC}"
                    
                    local match_count=0
                    while IFS= read -r line; do
                        if [[ -n "$line" ]]; then
                            # Extract line number and content
                            local line_num="${line%%:*}"
                            local content="${line#*:}"
                            
                            # Highlight the pattern in the content
                            if [[ "$case_sensitive" == "true" ]]; then
                                content=$(echo "$content" | sed "s/${pattern}/${RED}${pattern}${NC}/g")
                            else
                                content=$(echo "$content" | sed "s/${pattern}/${RED}${pattern}${NC}/gi")
                            fi
                            
                            echo -e "${CYAN}${line_num}:${NC} ${content}"
                            ((match_count++))
                            ((total_matches++))
                        fi
                    done <<< "$matches"
                    
                    echo -e "${GREEN}Found $match_count matches in $pod${NC}"
                    ((service_matches += match_count))
                fi
            fi
        done
        
        if [[ $service_matches -gt 0 ]]; then
            echo -e "${GREEN}Total matches in $svc: $service_matches${NC}"
        else
            echo -e "${YELLOW}No matches found in $svc${NC}"
        fi
    done
    
    echo -e "\n${GREEN}Search completed: $total_matches total matches found${NC}"
}

# Export logs for analysis
export_logs() {
    local service="${1:-all}"
    local format="${2:-text}"
    local lines="${3:-$TAIL_LINES}"
    local output_file="${4:-}"
    
    log_section "EXPORTING LOGS"
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [[ -z "$output_file" ]]; then
        case "$format" in
            "json")
                output_file="logs_${service}_${timestamp}.json"
                ;;
            "csv")
                output_file="logs_${service}_${timestamp}.csv"
                ;;
            *)
                output_file="logs_${service}_${timestamp}.txt"
                ;;
        esac
    fi
    
    log_info "Exporting logs to: $output_file (format: $format)"
    
    case "$format" in
        "json")
            export_logs_json "$service" "$lines" "$output_file"
            ;;
        "csv")
            export_logs_csv "$service" "$lines" "$output_file"
            ;;
        *)
            export_logs_text "$service" "$lines" "$output_file"
            ;;
    esac
    
    if [[ -f "$output_file" ]]; then
        local file_size
        file_size=$(ls -lh "$output_file" | awk '{print $5}')
        log_success "Logs exported: $output_file ($file_size)"
    else
        log_error "Failed to export logs"
        return 1
    fi
}

# Export logs in JSON format
export_logs_json() {
    local service="$1"
    local lines="$2"
    local output_file="$3"
    
    local services_to_export=()
    if [[ "$service" == "all" ]]; then
        services_to_export=($(printf '%s\n' "${!SERVICES[@]}" | sort))
    else
        services_to_export=("$service")
    fi
    
    {
        echo "{"
        echo "  \"export_info\": {"
        echo "    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "    \"namespace\": \"$NAMESPACE\","
        echo "    \"service\": \"$service\","
        echo "    \"lines\": $lines"
        echo "  },"
        echo "  \"logs\": ["
        
        local first_service=true
        for svc in "${services_to_export[@]}"; do
            if [[ "$first_service" == "true" ]]; then
                first_service=false
            else
                echo ","
            fi
            
            echo "    {"
            echo "      \"service\": \"$svc\","
            echo "      \"pods\": ["
            
            local pods
            pods=$(get_service_pods "$svc")
            
            if [[ -n "$pods" ]]; then
                local first_pod=true
                for pod in $pods; do
                    if [[ "$first_pod" == "true" ]]; then
                        first_pod=false
                    else
                        echo ","
                    fi
                    
                    echo "        {"
                    echo "          \"pod_name\": \"$pod\","
                    echo "          \"log_entries\": ["
                    
                    local log_output
                    log_output=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" 2>/dev/null || echo "")
                    
                    if [[ -n "$log_output" ]]; then
                        local first_line=true
                        while IFS= read -r line; do
                            if [[ -n "$line" ]]; then
                                if [[ "$first_line" == "true" ]]; then
                                    first_line=false
                                else
                                    echo ","
                                fi
                                
                                # Escape JSON special characters
                                line=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$//')
                                echo -n "            \"$line\""
                            fi
                        done <<< "$log_output"
                    fi
                    
                    echo ""
                    echo "          ]"
                    echo -n "        }"
                done
            fi
            
            echo ""
            echo "      ]"
            echo -n "    }"
        done
        
        echo ""
        echo "  ]"
        echo "}"
    } > "$output_file"
}

# Export logs in CSV format
export_logs_csv() {
    local service="$1"
    local lines="$2"
    local output_file="$3"
    
    local services_to_export=()
    if [[ "$service" == "all" ]]; then
        services_to_export=($(printf '%s\n' "${!SERVICES[@]}" | sort))
    else
        services_to_export=("$service")
    fi
    
    {
        echo "timestamp,service,pod,level,message"
        
        for svc in "${services_to_export[@]}"; do
            local pods
            pods=$(get_service_pods "$svc")
            
            if [[ -n "$pods" ]]; then
                for pod in $pods; do
                    local log_output
                    log_output=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" --timestamps=true 2>/dev/null || echo "")
                    
                    if [[ -n "$log_output" ]]; then
                        while IFS= read -r line; do
                            if [[ -n "$line" ]]; then
                                # Extract timestamp if present
                                local timestamp=""
                                local content="$line"
                                
                                if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z)\s+(.*)$ ]]; then
                                    timestamp="${BASH_REMATCH[1]}"
                                    content="${BASH_REMATCH[2]}"
                                fi
                                
                                # Extract log level
                                local level=""
                                if [[ "$content" =~ \[(ERROR|FATAL|PANIC|WARN|WARNING|INFO|DEBUG|TRACE)\] ]]; then
                                    level="${BASH_REMATCH[1]}"
                                fi
                                
                                # Escape CSV special characters
                                content=$(echo "$content" | sed 's/"//""/g')
                                
                                echo "\"$timestamp\",\"$svc\",\"$pod\",\"$level\",\"$content\""
                            fi
                        done <<< "$log_output"
                    fi
                done
            fi
        done
    } > "$output_file"
}

# Export logs in text format
export_logs_text() {
    local service="$1"
    local lines="$2"
    local output_file="$3"
    
    collect_service_logs "$service" "$lines" "$output_file"
}

# Analyze logs for patterns
analyze_logs() {
    local service="${1:-all}"
    local lines="${2:-$TAIL_LINES}"
    
    log_section "LOG ANALYSIS"
    
    log_info "Analyzing logs for patterns and issues..."
    
    local analysis_file="${PARSED_LOGS_DIR}/analysis_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# PyAirtable Log Analysis Report"
        echo "# Generated: $(date)"
        echo "# Service: $service"
        echo "# Lines analyzed: $lines"
        echo ""
        
        # Error analysis
        echo "## Error Analysis"
        echo "==================="
        
        local services_to_analyze=()
        if [[ "$service" == "all" ]]; then
            services_to_analyze=($(printf '%s\n' "${!SERVICES[@]}" | sort))
        else
            services_to_analyze=("$service")
        fi
        
        local total_errors=0
        local total_warnings=0
        local total_lines=0
        
        for svc in "${services_to_analyze[@]}"; do
            echo ""
            echo "### Service: $svc"
            echo "-------------------"
            
            local pods
            pods=$(get_service_pods "$svc")
            
            if [[ -z "$pods" ]]; then
                echo "No pods found"
                continue
            fi
            
            local service_errors=0
            local service_warnings=0
            local service_lines=0
            
            for pod in $pods; do
                local log_output
                log_output=$(kubectl logs -n "$NAMESPACE" "$pod" --tail="$lines" 2>/dev/null || echo "")
                
                if [[ -n "$log_output" ]]; then
                    local pod_lines
                    pod_lines=$(echo "$log_output" | wc -l)
                    service_lines=$((service_lines + pod_lines))
                    
                    local pod_errors
                    pod_errors=$(echo "$log_output" | grep -ci "error\|fatal\|panic" || echo "0")
                    service_errors=$((service_errors + pod_errors))
                    
                    local pod_warnings
                    pod_warnings=$(echo "$log_output" | grep -ci "warn" || echo "0")
                    service_warnings=$((service_warnings + pod_warnings))
                    
                    echo "Pod $pod: $pod_lines lines, $pod_errors errors, $pod_warnings warnings"
                    
                    # Show sample errors
                    local sample_errors
                    sample_errors=$(echo "$log_output" | grep -i "error\|fatal\|panic" | head -3)
                    if [[ -n "$sample_errors" ]]; then
                        echo "Sample errors:"
                        while IFS= read -r error_line; do
                            echo "  - $error_line"
                        done <<< "$sample_errors"
                    fi
                fi
            done
            
            echo "Service totals: $service_lines lines, $service_errors errors, $service_warnings warnings"
            
            total_errors=$((total_errors + service_errors))
            total_warnings=$((total_warnings + service_warnings))
            total_lines=$((total_lines + service_lines))
        done
        
        echo ""
        echo "## Summary"
        echo "=========="
        echo "Total lines analyzed: $total_lines"
        echo "Total errors found: $total_errors"
        echo "Total warnings found: $total_warnings"
        
        if [[ $total_lines -gt 0 ]]; then
            local error_rate
            error_rate=$(echo "scale=2; $total_errors * 100 / $total_lines" | bc 2>/dev/null || echo "0")
            echo "Error rate: ${error_rate}%"
        fi
        
        echo ""
        echo "## Recommendations"
        echo "=================="
        
        if [[ $total_errors -gt 10 ]]; then
            echo "- High error count detected ($total_errors). Investigate immediately."
        elif [[ $total_errors -gt 5 ]]; then
            echo "- Moderate error count detected ($total_errors). Monitor closely."
        else
            echo "- Error count is acceptable ($total_errors)."
        fi
        
        if [[ $total_warnings -gt 20 ]]; then
            echo "- High warning count detected ($total_warnings). Review and address."
        elif [[ $total_warnings -gt 10 ]]; then
            echo "- Moderate warning count detected ($total_warnings). Monitor."
        else
            echo "- Warning count is acceptable ($total_warnings)."
        fi
        
    } > "$analysis_file"
    
    # Display analysis
    cat "$analysis_file"
    
    local file_size
    file_size=$(ls -lh "$analysis_file" | awk '{print $5}')
    log_success "Analysis saved to: $(basename "$analysis_file") ($file_size)"
}

# Archive old logs
archive_logs() {
    local days="${1:-$LOG_RETENTION_DAYS}"
    
    log_section "ARCHIVING OLD LOGS"
    
    log_info "Archiving logs older than $days days..."
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local archive_file="${ARCHIVE_DIR}/archived_logs_${timestamp}.tar.gz"
    
    # Find old log files
    local old_files=()
    if [[ -d "$AGGREGATED_LOGS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            old_files+=("$file")
        done < <(find "$AGGREGATED_LOGS_DIR" -name "*.log*" -mtime +$days -print0 2>/dev/null)
    fi
    
    if [[ ${#old_files[@]} -eq 0 ]]; then
        log_info "No old log files found to archive"
        return 0
    fi
    
    log_info "Found ${#old_files[@]} old log files"
    
    # Create archive
    tar -czf "$archive_file" "${old_files[@]}" 2>/dev/null
    
    if [[ -f "$archive_file" ]]; then
        local file_size
        file_size=$(ls -lh "$archive_file" | awk '{print $5}')
        log_success "Archive created: $(basename "$archive_file") ($file_size)"
        
        # Remove archived files
        for file in "${old_files[@]}"; do
            rm -f "$file"
        done
        
        log_success "Removed ${#old_files[@]} archived log files"
    else
        log_error "Failed to create archive"
        return 1
    fi
}

# Cleanup old log data
cleanup_logs() {
    local days="${1:-$LOG_RETENTION_DAYS}"
    
    log_section "CLEANING UP OLD LOGS"
    
    log_info "Removing log data older than $days days..."
    
    local removed_count=0
    
    # Clean aggregated logs
    if [[ -d "$AGGREGATED_LOGS_DIR" ]]; then
        local aggregated_removed
        aggregated_removed=$(find "$AGGREGATED_LOGS_DIR" -name "*.log*" -mtime +$days -delete -print 2>/dev/null | wc -l)
        removed_count=$((removed_count + aggregated_removed))
        log_info "Removed $aggregated_removed aggregated log files"
    fi
    
    # Clean parsed logs
    if [[ -d "$PARSED_LOGS_DIR" ]]; then
        local parsed_removed
        parsed_removed=$(find "$PARSED_LOGS_DIR" -name "*.txt" -mtime +$days -delete -print 2>/dev/null | wc -l)
        removed_count=$((removed_count + parsed_removed))
        log_info "Removed $parsed_removed parsed log files"
    fi
    
    # Clean old archives (keep archives longer)
    if [[ -d "$ARCHIVE_DIR" ]]; then
        local archive_retention=$((days * 3))  # Keep archives 3x longer
        local archived_removed
        archived_removed=$(find "$ARCHIVE_DIR" -name "*.tar.gz" -mtime +$archive_retention -delete -print 2>/dev/null | wc -l)
        removed_count=$((removed_count + archived_removed))
        log_info "Removed $archived_removed old archive files"
    fi
    
    log_success "Cleanup completed: $removed_count files removed"
}

# Show log statistics
show_log_stats() {
    log_section "LOG STATISTICS"
    
    init_log_system
    
    echo -e "${CYAN}📊 Log Management Statistics${NC}"
    echo -e "${CYAN}═══════════════════════════${NC}"
    
    # Directory sizes
    if [[ -d "$LOGS_DIR" ]]; then
        local total_size
        total_size=$(du -sh "$LOGS_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
        echo -e "  📁 Total log data: $total_size"
    fi
    
    # File counts
    local aggregated_count=0
    local parsed_count=0
    local archive_count=0
    
    if [[ -d "$AGGREGATED_LOGS_DIR" ]]; then
        aggregated_count=$(find "$AGGREGATED_LOGS_DIR" -name "*.log*" 2>/dev/null | wc -l)
    fi
    
    if [[ -d "$PARSED_LOGS_DIR" ]]; then
        parsed_count=$(find "$PARSED_LOGS_DIR" -name "*.txt" 2>/dev/null | wc -l)
    fi
    
    if [[ -d "$ARCHIVE_DIR" ]]; then
        archive_count=$(find "$ARCHIVE_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
    fi
    
    echo -e "  📋 Aggregated logs: $aggregated_count files"
    echo -e "  🔍 Parsed logs: $parsed_count files"
    echo -e "  📦 Archived logs: $archive_count files"
    
    echo
    echo -e "${CYAN}🔍 Service Status${NC}"
    echo -e "${CYAN}═══════════════════${NC}"
    
    # Service pod counts
    for service in $(printf '%s\n' "${!SERVICES[@]}" | sort); do
        local priority="${SERVICES[$service]}"
        local pods
        pods=$(get_service_pods "$service")
        local pod_count=0
        
        if [[ -n "$pods" ]]; then
            pod_count=$(echo "$pods" | wc -w)
        fi
        
        local priority_color="${BLUE}"
        case "$priority" in
            "critical") priority_color="${RED}" ;;
            "high") priority_color="${YELLOW}" ;;
            "medium") priority_color="${BLUE}" ;;
            "low") priority_color="${GREEN}" ;;
        esac
        
        printf "  %-20s %s%-8s%s %d pods\n" "$service" "$priority_color" "$priority" "$NC" "$pod_count"
    done
    
    echo
    echo -e "${CYAN}⚙️  Configuration${NC}"
    echo -e "${CYAN}═════════════════${NC}"
    echo -e "  🕒 Retention: $LOG_RETENTION_DAYS days"
    echo -e "  📏 Max size: $MAX_LOG_SIZE"
    echo -e "  📄 Default lines: $TAIL_LINES"
    echo -e "  🗂️  Buffer size: $LOG_BUFFER_SIZE"
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "collect")
            collect_all_logs "$@"
            ;;
        "view")
            view_logs "$@"
            ;;
        "follow"|"tail")
            follow_logs "$@"
            ;;
        "search")
            if [[ $# -eq 0 ]]; then
                log_error "Search pattern is required"
                exit 1
            fi
            search_logs "$@"
            ;;
        "export")
            export_logs "$@"
            ;;
        "analyze")
            analyze_logs "$@"
            ;;
        "archive")
            archive_logs "$@"
            ;;
        "cleanup")
            cleanup_logs "$@"
            ;;
        "stats")
            show_log_stats
            ;;
        "init")
            init_log_system
            ;;
        "help"|"-h"|"--help")
            cat << EOF
PyAirtable Log Management System

Usage: $0 <command> [options]

Commands:
  collect [lines]                 Collect logs from all services
  view [service] [lines] [level] [pattern]  View logs with filtering
  follow [service] [level]        Follow logs in real-time
  search <pattern> [service] [lines] [case_sensitive]  Search logs
  export [service] [format] [lines] [file]  Export logs (text/json/csv)
  analyze [service] [lines]       Analyze logs for patterns and issues
  archive [days]                  Archive old logs
  cleanup [days]                  Clean up old log data
  stats                          Show log statistics
  init                           Initialize log management system
  help                           Show this help message

Examples:
  $0 collect 200                  # Collect last 200 lines from all services
  $0 view api-gateway 100         # View last 100 lines from api-gateway
  $0 view all 50 ERROR            # View last 50 lines, ERROR level only
  $0 follow postgres              # Follow PostgreSQL logs in real-time
  $0 search "connection error"    # Search for connection errors
  $0 search "timeout" postgres    # Search for timeout in postgres logs
  $0 export all json 500          # Export all logs to JSON format
  $0 analyze frontend             # Analyze frontend logs for issues
  $0 archive 7                    # Archive logs older than 7 days
  $0 cleanup 14                   # Clean logs older than 14 days

Log Viewing Features:
  ✅ Multi-service log aggregation
  ✅ Real-time log following
  ✅ Advanced search with patterns
  ✅ Log level filtering
  ✅ Colorized output
  ✅ Export to multiple formats
  ✅ Automated analysis
  ✅ Archive and cleanup

Supported Services:
$(printf "  • %-20s (%s)\n" $(for s in "${!SERVICES[@]}"; do echo "$s:${SERVICES[$s]}"; done | sort) | sed 's/:/ /')

Configuration:
  LOG_RETENTION_DAYS              Log retention period (default: 7)
  MAX_LOG_SIZE                    Maximum log file size (default: 100M)
  TAIL_LINES                      Default lines to show (default: 100)
  FOLLOW_TIMEOUT                  Follow timeout in seconds (default: 300)

Environment Variables:
  NAMESPACE                       Kubernetes namespace (default: pyairtable)
EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"