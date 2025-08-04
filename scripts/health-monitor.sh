#!/bin/bash

# PyAirtable Service Health Monitoring System
# Comprehensive health monitoring, alerting, and performance tracking
# Author: Claude Deployment Engineer

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly MONITOR_DATA_DIR="${PROJECT_ROOT}/.monitoring"
readonly ALERTS_DIR="${MONITOR_DATA_DIR}/alerts"
readonly METRICS_DIR="${MONITOR_DATA_DIR}/metrics"
readonly LOGS_DIR="${MONITOR_DATA_DIR}/logs"
readonly NAMESPACE="${NAMESPACE:-pyairtable}"

# Monitoring configuration
readonly CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
readonly ALERT_THRESHOLD_ERROR="${ALERT_THRESHOLD_ERROR:-3}"
readonly ALERT_THRESHOLD_WARNING="${ALERT_THRESHOLD_WARNING:-5}"
readonly METRICS_RETENTION_HOURS="${METRICS_RETENTION_HOURS:-24}"
readonly HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Service definitions with health check configurations
declare -A SERVICES=(
    ["api-gateway"]="8000:/health:critical"
    ["frontend"]="3000:/api/health:high"
    ["airtable-gateway"]="8002:/health:critical"
    ["llm-orchestrator"]="8003:/health:high"
    ["mcp-server"]="8001:/health:high"
    ["platform-services"]="8007:/health:critical"
    ["automation-services"]="8006:/health:medium"
    ["postgres"]="5432:pg_isready:critical"
    ["redis"]="6379:ping:critical"
)

# Alert severity levels
declare -A SEVERITY_COLORS=(
    ["critical"]="$RED"
    ["high"]="$YELLOW"
    ["medium"]="$BLUE"
    ["low"]="$GREEN"
)

# Monitoring state
declare -A SERVICE_STATUS=()
declare -A SERVICE_ERRORS=()
declare -A SERVICE_RESPONSE_TIMES=()
declare -A ALERT_HISTORY=()

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

# Initialize monitoring directories
init_monitoring() {
    log_info "Initializing monitoring system..."
    
    mkdir -p "$MONITOR_DATA_DIR" "$ALERTS_DIR" "$METRICS_DIR" "$LOGS_DIR"
    chmod 755 "$MONITOR_DATA_DIR" "$ALERTS_DIR" "$METRICS_DIR" "$LOGS_DIR"
    
    # Create monitoring configuration
    cat > "${MONITOR_DATA_DIR}/config.json" << EOF
{
    "monitoring": {
        "namespace": "$NAMESPACE",
        "check_interval": $CHECK_INTERVAL,
        "alert_thresholds": {
            "error": $ALERT_THRESHOLD_ERROR,
            "warning": $ALERT_THRESHOLD_WARNING
        },
        "retention": {
            "metrics_hours": $METRICS_RETENTION_HOURS
        }
    },
    "services": $(echo "${!SERVICES[@]}" | tr ' ' '\n' | sort | jq -R . | jq -s .)
}
EOF
    
    log_success "Monitoring system initialized"
}

# Get service pod name
get_service_pod() {
    local service="$1"
    kubectl get pods -n "$NAMESPACE" -l "app=$service" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

# Check if service exists
service_exists() {
    local service="$1"
    kubectl get service "$service" -n "$NAMESPACE" &>/dev/null
}

# Perform HTTP health check
http_health_check() {
    local service="$1"
    local port="$2"
    local path="$3"
    local timeout="${4:-$HEALTH_CHECK_TIMEOUT}"
    
    local start_time response_time
    start_time=$(date +%s%3N)
    
    # Use kubectl run for health check
    local check_pod="health-check-$$-$(date +%s)"
    local result=0
    
    kubectl run "$check_pod" \
        --namespace="$NAMESPACE" \
        --image=curlimages/curl:latest \
        --rm --restart=Never \
        --timeout="${timeout}s" \
        --command -- \
        curl -sf "http://${service}.${NAMESPACE}.svc.cluster.local:${port}${path}" &>/dev/null || result=1
    
    local end_time
    end_time=$(date +%s%3N)
    response_time=$((end_time - start_time))
    
    SERVICE_RESPONSE_TIMES["$service"]="$response_time"
    return $result
}

# Perform database health check
db_health_check() {
    local service="$1"
    local command="$2"
    
    local pod
    pod=$(get_service_pod "$service")
    
    if [[ -z "$pod" ]]; then
        return 1
    fi
    
    local start_time end_time response_time
    start_time=$(date +%s%3N)
    
    case "$service" in
        "postgres")
            kubectl exec -n "$NAMESPACE" "$pod" -- pg_isready -U "${POSTGRES_USER:-admin}" -d "${POSTGRES_DB:-pyairtablemcp}" &>/dev/null
            ;;
        "redis")
            kubectl exec -n "$NAMESPACE" "$pod" -- redis-cli -a "${REDIS_PASSWORD:-changeme}" ping &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
    
    local exit_code=$?
    end_time=$(date +%s%3N)
    response_time=$((end_time - start_time))
    
    SERVICE_RESPONSE_TIMES["$service"]="$response_time"
    return $exit_code
}

# Check individual service health
check_service_health() {
    local service="$1"
    local config="${SERVICES[$service]}"
    
    # Parse service configuration
    IFS=':' read -r port path severity <<< "$config"
    
    # Check if service exists
    if ! service_exists "$service"; then
        SERVICE_STATUS["$service"]="not_found"
        return 1
    fi
    
    # Check if pods are running
    local running_pods ready_pods
    running_pods=$(kubectl get pods -n "$NAMESPACE" -l "app=$service" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
    ready_pods=$(kubectl get pods -n "$NAMESPACE" -l "app=$service" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l || echo "0")
    
    if [[ "$running_pods" -eq 0 ]]; then
        SERVICE_STATUS["$service"]="no_pods"
        return 1
    fi
    
    if [[ "$ready_pods" -eq 0 ]]; then
        SERVICE_STATUS["$service"]="not_ready"
        return 1
    fi
    
    # Perform health check based on service type
    local health_check_result
    if [[ "$path" == "pg_isready" || "$path" == "ping" ]]; then
        if db_health_check "$service" "$path"; then
            health_check_result=0
        else
            health_check_result=1
        fi
    else
        if http_health_check "$service" "$port" "$path"; then
            health_check_result=0
        else
            health_check_result=1
        fi
    fi
    
    # Update service status
    if [[ $health_check_result -eq 0 ]]; then
        SERVICE_STATUS["$service"]="healthy"
        SERVICE_ERRORS["$service"]=0
        return 0
    else
        SERVICE_STATUS["$service"]="unhealthy"
        SERVICE_ERRORS["$service"]=$((${SERVICE_ERRORS["$service"]:-0} + 1))
        return 1
    fi
}

# Record metrics
record_metrics() {
    local timestamp
    timestamp=$(date +%s)
    local metrics_file="${METRICS_DIR}/metrics_$(date +%Y%m%d).json"
    
    # Create metrics entry
    local metrics_entry="{\"timestamp\": $timestamp, \"services\": {"
    
    local first=true
    for service in "${!SERVICES[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            metrics_entry+=", "
        fi
        
        local status="${SERVICE_STATUS[$service]:-unknown}"
        local response_time="${SERVICE_RESPONSE_TIMES[$service]:-0}"
        local error_count="${SERVICE_ERRORS[$service]:-0}"
        
        metrics_entry+="\"$service\": {\"status\": \"$status\", \"response_time\": $response_time, \"error_count\": $error_count}"
    done
    
    metrics_entry+="}}"
    
    # Append to metrics file
    echo "$metrics_entry" >> "$metrics_file"
    
    # Clean old metrics
    find "$METRICS_DIR" -name "metrics_*.json" -mtime +1 -delete 2>/dev/null || true
}

# Generate alert
generate_alert() {
    local service="$1"
    local severity="$2"
    local message="$3"
    local timestamp
    timestamp=$(date +%s)
    
    local alert_file="${ALERTS_DIR}/alert_${timestamp}_${service}.json"
    
    cat > "$alert_file" << EOF
{
    "timestamp": $timestamp,
    "datetime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "service": "$service",
    "severity": "$severity",
    "message": "$message",
    "status": "${SERVICE_STATUS[$service]:-unknown}",
    "error_count": ${SERVICE_ERRORS[$service]:-0},
    "response_time": ${SERVICE_RESPONSE_TIMES[$service]:-0}
}
EOF
    
    # Track alert history
    ALERT_HISTORY["$service"]="$timestamp:$severity:$message"
    
    # Display alert
    local color="${SEVERITY_COLORS[$severity]}"
    echo -e "${color}🚨 ALERT [$severity] $service: $message${NC}"
    
    # Clean old alerts
    find "$ALERTS_DIR" -name "alert_*.json" -mtime +7 -delete 2>/dev/null || true
}

# Check for alerts
check_alerts() {
    for service in "${!SERVICES[@]}"; do
        local config="${SERVICES[$service]}"
        local severity="${config##*:}"
        local status="${SERVICE_STATUS[$service]:-unknown}"
        local error_count="${SERVICE_ERRORS[$service]:-0}"
        
        # Generate alerts based on status and error count
        case "$status" in
            "not_found")
                generate_alert "$service" "$severity" "Service not found in cluster"
                ;;
            "no_pods")
                generate_alert "$service" "$severity" "No running pods found"
                ;;
            "not_ready")
                generate_alert "$service" "$severity" "Pods not ready"
                ;;
            "unhealthy")
                if [[ "$severity" == "critical" && $error_count -ge $ALERT_THRESHOLD_ERROR ]]; then
                    generate_alert "$service" "critical" "Health check failing ($error_count consecutive failures)"
                elif [[ $error_count -ge $ALERT_THRESHOLD_WARNING ]]; then
                    generate_alert "$service" "high" "Health check degraded ($error_count consecutive failures)"
                fi
                ;;
        esac
        
        # Response time alerts
        local response_time="${SERVICE_RESPONSE_TIMES[$service]:-0}"
        if [[ $response_time -gt 5000 ]]; then  # 5 seconds
            generate_alert "$service" "medium" "High response time: ${response_time}ms"
        fi
    done
}

# Display health dashboard
display_dashboard() {
    clear
    
    # Header
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║                        PyAirtable Health Dashboard                            ║${NC}"
    echo -e "${PURPLE}║                          $(date +'%Y-%m-%d %H:%M:%S')                          ║${NC}"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Service status overview
    local healthy=0 unhealthy=0 unknown=0
    
    echo -e "${CYAN}📊 Service Status Overview${NC}"
    echo -e "${CYAN}─────────────────────────${NC}"
    
    # Calculate counts
    for service in "${!SERVICES[@]}"; do
        local status="${SERVICE_STATUS[$service]:-unknown}"
        case "$status" in
            "healthy") ((healthy++)) ;;
            "unhealthy"|"not_found"|"no_pods"|"not_ready") ((unhealthy++)) ;;
            *) ((unknown++)) ;;
        esac
    done
    
    local total=$((healthy + unhealthy + unknown))
    local health_percentage=0
    if [[ $total -gt 0 ]]; then
        health_percentage=$((healthy * 100 / total))
    fi
    
    echo -e "  ${GREEN}✅ Healthy: $healthy${NC}"
    echo -e "  ${RED}❌ Unhealthy: $unhealthy${NC}"
    echo -e "  ${YELLOW}❓ Unknown: $unknown${NC}"
    echo -e "  📈 Overall Health: ${health_percentage}%"
    echo
    
    # Detailed service status
    echo -e "${CYAN}🔍 Detailed Service Status${NC}"
    echo -e "${CYAN}──────────────────────────${NC}"
    printf "%-20s %-15s %-10s %-15s %-10s\n" "Service" "Status" "Response" "Errors" "Severity"
    echo "────────────────────────────────────────────────────────────────────────"
    
    for service in $(printf '%s\n' "${!SERVICES[@]}" | sort); do
        local config="${SERVICES[$service]}"
        local severity="${config##*:}"
        local status="${SERVICE_STATUS[$service]:-unknown}"
        local response_time="${SERVICE_RESPONSE_TIMES[$service]:-0}"
        local error_count="${SERVICE_ERRORS[$service]:-0}"
        
        # Format status with color
        local status_display=""
        case "$status" in
            "healthy")
                status_display="${GREEN}✅ Healthy${NC}"
                ;;
            "unhealthy")
                status_display="${RED}❌ Unhealthy${NC}"
                ;;
            "not_found")
                status_display="${RED}🚫 Not Found${NC}"
                ;;
            "no_pods")
                status_display="${YELLOW}📋 No Pods${NC}"
                ;;
            "not_ready")
                status_display="${YELLOW}⏳ Not Ready${NC}"
                ;;
            *)
                status_display="${YELLOW}❓ Unknown${NC}"
                ;;
        esac
        
        # Format response time
        local response_display="${response_time}ms"
        if [[ $response_time -gt 2000 ]]; then
            response_display="${RED}${response_time}ms${NC}"
        elif [[ $response_time -gt 1000 ]]; then
            response_display="${YELLOW}${response_time}ms${NC}"
        else
            response_display="${GREEN}${response_time}ms${NC}"
        fi
        
        # Format error count
        local error_display="$error_count"
        if [[ $error_count -gt 0 ]]; then
            error_display="${RED}$error_count${NC}"
        else
            error_display="${GREEN}$error_count${NC}"
        fi
        
        # Format severity
        local severity_color="${SEVERITY_COLORS[$severity]}"
        local severity_display="${severity_color}$severity${NC}"
        
        printf "%-20s %-25s %-20s %-20s %-15s\n" "$service" "$status_display" "$response_display" "$error_display" "$severity_display"
    done
    
    echo
    
    # Recent alerts
    local recent_alerts=($(find "$ALERTS_DIR" -name "alert_*.json" -mtime -1 2>/dev/null | head -5))
    
    if [[ ${#recent_alerts[@]} -gt 0 ]]; then
        echo -e "${CYAN}🚨 Recent Alerts${NC}"
        echo -e "${CYAN}───────────────${NC}"
        
        for alert_file in "${recent_alerts[@]}"; do
            if [[ -f "$alert_file" ]] && command -v jq &> /dev/null; then
                local alert_service alert_severity alert_message alert_datetime
                alert_service=$(jq -r '.service' "$alert_file" 2>/dev/null || echo "unknown")
                alert_severity=$(jq -r '.severity' "$alert_file" 2>/dev/null || echo "unknown")
                alert_message=$(jq -r '.message' "$alert_file" 2>/dev/null || echo "unknown")
                alert_datetime=$(jq -r '.datetime' "$alert_file" 2>/dev/null || echo "unknown")
                
                local color="${SEVERITY_COLORS[$alert_severity]:-$WHITE}"
                echo -e "  ${color}[$alert_severity]${NC} $alert_service: $alert_message ($alert_datetime)"
            fi
        done
        echo
    fi
    
    # System resources (if available)
    if command -v kubectl &> /dev/null; then
        echo -e "${CYAN}💻 Cluster Resources${NC}"
        echo -e "${CYAN}───────────────────${NC}"
        
        # Node information
        local node_info
        node_info=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        echo -e "  🖥️  Cluster Status: $node_info"
        
        # Namespace pod count
        local pod_count
        pod_count=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        echo -e "  📦 Total Pods: $pod_count"
        
        # Namespace services count
        local service_count
        service_count=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
        echo -e "  🌐 Total Services: $service_count"
        echo
    fi
    
    # Footer
    echo -e "${CYAN}Next update in ${CHECK_INTERVAL} seconds... Press Ctrl+C to stop${NC}"
}

# Run single health check
run_single_check() {
    log_section "RUNNING HEALTH CHECK"
    
    init_monitoring
    
    local all_healthy=true
    
    for service in "${!SERVICES[@]}"; do
        log_info "Checking $service..."
        
        if check_service_health "$service"; then
            local response_time="${SERVICE_RESPONSE_TIMES[$service]:-0}"
            log_success "$service is healthy (${response_time}ms)"
        else
            local status="${SERVICE_STATUS[$service]:-unknown}"
            log_error "$service is $status"
            all_healthy=false
        fi
    done
    
    # Record metrics
    record_metrics
    
    # Check for alerts
    check_alerts
    
    echo
    if [[ "$all_healthy" == "true" ]]; then
        log_success "All services are healthy!"
        return 0
    else
        log_warning "Some services are unhealthy"
        return 1
    fi
}

# Continuous monitoring mode
run_continuous_monitoring() {
    log_section "STARTING CONTINUOUS MONITORING"
    
    init_monitoring
    
    log_info "Monitoring interval: ${CHECK_INTERVAL}s"
    log_info "Press Ctrl+C to stop monitoring"
    
    # Trap for cleanup
    trap 'log_info "Monitoring stopped"; exit 0' INT TERM
    
    while true; do
        # Run health checks
        for service in "${!SERVICES[@]}"; do
            check_service_health "$service" &>/dev/null
        done
        
        # Record metrics
        record_metrics
        
        # Check for alerts
        check_alerts &>/dev/null
        
        # Display dashboard
        display_dashboard
        
        # Wait for next check
        sleep "$CHECK_INTERVAL"
    done
}

# Show metrics summary
show_metrics() {
    local hours="${1:-24}"
    
    log_section "METRICS SUMMARY (Last ${hours}h)"
    
    if [[ ! -d "$METRICS_DIR" ]]; then
        log_warning "No metrics data available"
        return 0
    fi
    
    # Find metrics files within the time range
    local metrics_files=($(find "$METRICS_DIR" -name "metrics_*.json" -mtime -1 2>/dev/null))
    
    if [[ ${#metrics_files[@]} -eq 0 ]]; then
        log_warning "No recent metrics data found"
        return 0
    fi
    
    echo -e "${CYAN}📊 Service Availability Summary${NC}"
    echo -e "${CYAN}─────────────────────────────────${NC}"
    
    # Calculate availability for each service
    for service in $(printf '%s\n' "${!SERVICES[@]}" | sort); do
        local total_checks=0
        local healthy_checks=0
        local total_response_time=0
        
        for metrics_file in "${metrics_files[@]}"; do
            if [[ -f "$metrics_file" ]] && command -v jq &> /dev/null; then
                # Count total checks for this service
                local service_entries
                service_entries=$(jq -r ".services[\"$service\"] // empty" "$metrics_file" 2>/dev/null | wc -l)
                
                if [[ $service_entries -gt 0 ]]; then
                    ((total_checks++))
                    
                    # Check if this entry was healthy
                    local status
                    status=$(jq -r ".services[\"$service\"].status // \"unknown\"" "$metrics_file" 2>/dev/null)
                    if [[ "$status" == "healthy" ]]; then
                        ((healthy_checks++))
                    fi
                    
                    # Add response time
                    local response_time
                    response_time=$(jq -r ".services[\"$service\"].response_time // 0" "$metrics_file" 2>/dev/null)
                    total_response_time=$((total_response_time + response_time))
                fi
            fi
        done
        
        if [[ $total_checks -gt 0 ]]; then
            local availability=$((healthy_checks * 100 / total_checks))
            local avg_response_time=$((total_response_time / total_checks))
            
            local availability_display
            if [[ $availability -ge 99 ]]; then
                availability_display="${GREEN}${availability}%${NC}"
            elif [[ $availability -ge 95 ]]; then
                availability_display="${YELLOW}${availability}%${NC}"
            else
                availability_display="${RED}${availability}%${NC}"
            fi
            
            printf "  %-20s %s (avg %dms, %d checks)\n" "$service" "$availability_display" "$avg_response_time" "$total_checks"
        else
            printf "  %-20s %s\n" "$service" "${YELLOW}No data${NC}"
        fi
    done
    
    echo
}

# Show recent alerts
show_alerts() {
    local hours="${1:-24}"
    
    log_section "RECENT ALERTS (Last ${hours}h)"
    
    if [[ ! -d "$ALERTS_DIR" ]]; then
        log_info "No alerts directory found"
        return 0
    fi
    
    local alert_files=($(find "$ALERTS_DIR" -name "alert_*.json" -mtime -1 2>/dev/null | sort -r))
    
    if [[ ${#alert_files[@]} -eq 0 ]]; then
        log_success "No recent alerts found"
        return 0
    fi
    
    echo -e "${CYAN}🚨 Alert History${NC}"
    echo -e "${CYAN}───────────────${NC}"
    
    for alert_file in "${alert_files[@]}"; do
        if [[ -f "$alert_file" ]] && command -v jq &> /dev/null; then
            local alert_service alert_severity alert_message alert_datetime
            alert_service=$(jq -r '.service' "$alert_file" 2>/dev/null || echo "unknown")
            alert_severity=$(jq -r '.severity' "$alert_file" 2>/dev/null || echo "unknown")
            alert_message=$(jq -r '.message' "$alert_file" 2>/dev/null || echo "unknown")
            alert_datetime=$(jq -r '.datetime' "$alert_file" 2>/dev/null || echo "unknown")
            
            local color="${SEVERITY_COLORS[$alert_severity]:-$WHITE}"
            echo -e "  ${color}[$alert_severity]${NC} $alert_datetime - $alert_service: $alert_message"
        fi
    done
    
    echo
}

# Cleanup old monitoring data
cleanup_monitoring_data() {
    local days="${1:-7}"
    
    log_section "CLEANING MONITORING DATA"
    
    log_info "Removing monitoring data older than $days days..."
    
    # Clean metrics
    if [[ -d "$METRICS_DIR" ]]; then
        local metrics_cleaned
        metrics_cleaned=$(find "$METRICS_DIR" -name "metrics_*.json" -mtime +$days -delete -print 2>/dev/null | wc -l)
        log_info "Cleaned $metrics_cleaned old metrics files"
    fi
    
    # Clean alerts
    if [[ -d "$ALERTS_DIR" ]]; then
        local alerts_cleaned
        alerts_cleaned=$(find "$ALERTS_DIR" -name "alert_*.json" -mtime +$days -delete -print 2>/dev/null | wc -l)
        log_info "Cleaned $alerts_cleaned old alert files"
    fi
    
    # Clean logs
    if [[ -d "$LOGS_DIR" ]]; then
        local logs_cleaned
        logs_cleaned=$(find "$LOGS_DIR" -name "*.log" -mtime +$days -delete -print 2>/dev/null | wc -l)
        log_info "Cleaned $logs_cleaned old log files"
    fi
    
    log_success "Monitoring data cleanup completed"
}

# Export monitoring data
export_monitoring_data() {
    local output_file="${1:-monitoring_export_$(date +%Y%m%d_%H%M%S).tar.gz}"
    
    log_section "EXPORTING MONITORING DATA"
    
    if [[ ! -d "$MONITOR_DATA_DIR" ]]; then
        log_error "No monitoring data found"
        return 1
    fi
    
    log_info "Exporting monitoring data to: $output_file"
    
    tar -czf "$output_file" -C "$PROJECT_ROOT" ".monitoring" 2>/dev/null
    
    if [[ -f "$output_file" ]]; then
        local file_size
        file_size=$(ls -lh "$output_file" | awk '{print $5}')
        log_success "Monitoring data exported: $output_file ($file_size)"
    else
        log_error "Failed to export monitoring data"
        return 1
    fi
}

# Main function
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "check"|"single")
            run_single_check
            ;;
        "monitor"|"continuous")
            run_continuous_monitoring
            ;;
        "metrics")
            show_metrics "$@"
            ;;
        "alerts")
            show_alerts "$@"
            ;;
        "cleanup")
            cleanup_monitoring_data "$@"
            ;;
        "export")
            export_monitoring_data "$@"
            ;;
        "init")
            init_monitoring
            ;;
        "help"|"-h"|"--help")
            cat << EOF
PyAirtable Service Health Monitoring System

Usage: $0 <command> [options]

Commands:
  check                   Run single health check for all services
  monitor                 Start continuous monitoring with dashboard
  metrics [hours]         Show metrics summary (default: 24h)
  alerts [hours]          Show recent alerts (default: 24h)
  cleanup [days]          Clean old monitoring data (default: 7 days)
  export [file]           Export monitoring data to archive
  init                    Initialize monitoring system
  help                    Show this help message

Examples:
  $0 check                        # Run single health check
  $0 monitor                      # Start continuous monitoring
  $0 metrics 12                   # Show last 12 hours metrics
  $0 alerts 6                     # Show last 6 hours alerts
  $0 cleanup 3                    # Clean data older than 3 days
  $0 export monitoring.tar.gz     # Export to specific file

Monitoring Features:
  ✅ Real-time health checks for all services
  ✅ Response time monitoring
  ✅ Automatic alert generation
  ✅ Historical metrics collection
  ✅ Interactive dashboard
  ✅ Configurable thresholds
  ✅ Data export and cleanup

Configuration:
  CHECK_INTERVAL              Monitoring interval in seconds (default: 30)
  ALERT_THRESHOLD_ERROR       Error threshold for critical alerts (default: 3)
  ALERT_THRESHOLD_WARNING     Warning threshold for alerts (default: 5)
  HEALTH_CHECK_TIMEOUT        Health check timeout in seconds (default: 10)
  METRICS_RETENTION_HOURS     Metrics retention period (default: 24)

Monitored Services:
$(printf "  • %s\n" "${!SERVICES[@]}" | sort)

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