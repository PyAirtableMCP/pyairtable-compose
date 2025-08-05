#!/bin/bash

# PyAirtable Health Monitor
# Comprehensive health monitoring and debugging for development environment
# Provides real-time monitoring, alerting, and diagnostic capabilities

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NAMESPACE="${NAMESPACE:-pyairtable-dev}"
readonly MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-pyairtable-dev}"
readonly LOG_DIR="${SCRIPT_DIR}/.health-logs"
readonly METRICS_DIR="${SCRIPT_DIR}/.metrics"

# Monitoring settings
readonly CHECK_INTERVAL=30
readonly ALERT_THRESHOLD=3
readonly HISTORY_RETENTION=24  # hours
readonly MAX_LOG_SIZE=10485760  # 10MB

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Services to monitor
readonly SERVICES=(
    "postgres"
    "redis"
    "airtable-gateway"
    "mcp-server"
    "llm-orchestrator"
    "platform-services"
    "automation-services"
)

# Health check definitions
declare -A HEALTH_CHECKS=(
    ["postgres"]="database"
    ["redis"]="redis"
    ["airtable-gateway"]="http:8002/health"
    ["mcp-server"]="http:8001/health"
    ["llm-orchestrator"]="http:8003/health"
    ["platform-services"]="http:8007/health"
    ["automation-services"]="http:8006/health"
)

# Alert tracking
declare -A ALERT_COUNTS=()
declare -A LAST_ALERT_TIME=()

# Initialize directories
init_directories() {
    mkdir -p "$LOG_DIR" "$METRICS_DIR"
    chmod 755 "$LOG_DIR" "$METRICS_DIR"
}

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$LOG_DIR/health-monitor.log"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_DIR/health-monitor.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_DIR/health-monitor.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_DIR/health-monitor.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_DIR/health-monitor.log"
}

# Health check implementations
check_database_health() {
    local service="$1"
    kubectl run health-check-db-$(date +%s) \
        --rm -i --restart=Never --image=postgres:16-alpine \
        --namespace="$NAMESPACE" -- \
        sh -c "pg_isready -h $service -p 5432 -U pyairtable" &> /dev/null
}

check_redis_health() {
    kubectl run health-check-redis-$(date +%s) \
        --rm -i --restart=Never --image=redis:7-alpine \
        --namespace="$NAMESPACE" -- \
        sh -c "redis-cli -h redis ping | grep -q PONG" &> /dev/null
}

check_http_health() {
    local service="$1"
    local endpoint="$2"
    kubectl run health-check-http-$(date +%s) \
        --rm -i --restart=Never --image=curlimages/curl:latest \
        --namespace="$NAMESPACE" -- \
        sh -c "curl -f -m 10 http://$service:$endpoint" &> /dev/null
}

# Perform health check for a service
perform_health_check() {
    local service="$1"
    local check_type="${HEALTH_CHECKS[$service]}"
    local result=0
    
    case "$check_type" in
        "database")
            check_database_health "$service" || result=1
            ;;
        "redis")
            check_redis_health || result=1
            ;;
        http:*)
            local endpoint="${check_type#http:}"
            check_http_health "$service" "$endpoint" || result=1
            ;;
        *)
            log_error "Unknown health check type: $check_type"
            result=1
            ;;
    esac
    
    return $result
}

# Get service pod status
get_pod_status() {
    local service="$1"
    local status="Unknown"
    local ready="0/0"
    local restarts="0"
    local age="Unknown"
    
    if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
        local pod_info
        pod_info=$(kubectl get pods -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | head -1)
        
        if [[ -n "$pod_info" ]]; then
            status=$(echo "$pod_info" | awk '{print $3}')
            ready=$(echo "$pod_info" | awk '{print $2}')
            restarts=$(echo "$pod_info" | awk '{print $4}')
            age=$(echo "$pod_info" | awk '{print $5}')
        fi
    fi
    
    echo "$status|$ready|$restarts|$age"
}

# Get resource usage
get_resource_usage() {
    local service="$1"
    local cpu="N/A"
    local memory="N/A"
    
    local metrics
    if metrics=$(kubectl top pod -n "$NAMESPACE" -l app="$service" --no-headers 2>/dev/null | head -1); then
        cpu=$(echo "$metrics" | awk '{print $2}')
        memory=$(echo "$metrics" | awk '{print $3}')
    fi
    
    echo "$cpu|$memory"
}

# Record metrics
record_metrics() {
    local service="$1"
    local health_status="$2"
    local timestamp=$(date +%s)
    
    # Resource usage
    local usage
    usage=$(get_resource_usage "$service")
    local cpu=$(echo "$usage" | cut -d'|' -f1)
    local memory=$(echo "$usage" | cut -d'|' -f2)
    
    # Pod status
    local pod_info
    pod_info=$(get_pod_status "$service")
    local status=$(echo "$pod_info" | cut -d'|' -f1)
    local ready=$(echo "$pod_info" | cut -d'|' -f2)
    local restarts=$(echo "$pod_info" | cut -d'|' -f3)
    
    # Record to metrics file
    local metrics_file="$METRICS_DIR/$service.metrics"
    echo "$timestamp,$health_status,$status,$ready,$restarts,$cpu,$memory" >> "$metrics_file"
    
    # Rotate metrics file if too large
    if [[ -f "$metrics_file" ]] && [[ $(stat -f%z "$metrics_file" 2>/dev/null || stat -c%s "$metrics_file" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]]; then
        tail -1000 "$metrics_file" > "$metrics_file.tmp"
        mv "$metrics_file.tmp" "$metrics_file"
    fi
}

# Handle alerts
handle_alert() {
    local service="$1"
    local issue="$2"
    local current_time=$(date +%s)
    
    # Increment alert count
    ALERT_COUNTS["$service"]=$((${ALERT_COUNTS["$service"]:-0} + 1))
    
    # Check if we should trigger an alert
    if [[ ${ALERT_COUNTS["$service"]} -ge $ALERT_THRESHOLD ]]; then
        # Check if we haven't alerted recently (5 minutes)
        local last_alert=${LAST_ALERT_TIME["$service"]:-0}
        if [[ $((current_time - last_alert)) -gt 300 ]]; then
            trigger_alert "$service" "$issue"
            LAST_ALERT_TIME["$service"]=$current_time
        fi
    fi
}

# Trigger alert
trigger_alert() {
    local service="$1"
    local issue="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_error "ALERT: $service - $issue"
    
    # Log to alert file
    echo "[$timestamp] ALERT: $service - $issue" >> "$LOG_DIR/alerts.log"
    
    # Get diagnostic information
    get_diagnostic_info "$service" >> "$LOG_DIR/diagnostic-$service-$(date +%s).log"
    
    # Attempt automatic recovery
    attempt_recovery "$service"
}

# Clear alert
clear_alert() {
    local service="$1"
    ALERT_COUNTS["$service"]=0
}

# Attempt automatic recovery
attempt_recovery() {
    local service="$1"
    
    log_info "Attempting automatic recovery for $service"
    
    # Get recent logs
    kubectl logs deployment/"$service" -n "$NAMESPACE" --tail=50 > "$LOG_DIR/pre-recovery-$service.log" 2>/dev/null || true
    
    # Restart the service
    kubectl rollout restart deployment/"$service" -n "$NAMESPACE" &> /dev/null || {
        log_error "Failed to restart $service"
        return 1
    }
    
    # Wait for recovery
    local recovery_timeout=120
    local start_time=$(date +%s)
    
    while [[ $(($(date +%s) - start_time)) -lt $recovery_timeout ]]; do
        if perform_health_check "$service"; then
            log_success "Recovery successful for $service"
            return 0
        fi
        sleep 10
    done
    
    log_error "Recovery failed for $service after ${recovery_timeout}s"
    return 1
}

# Get diagnostic information
get_diagnostic_info() {
    local service="$1"
    
    echo "=== Diagnostic Information for $service ==="
    echo "Timestamp: $(date)"
    echo
    
    echo "--- Pod Status ---"
    kubectl get pods -n "$NAMESPACE" -l app="$service" -o wide
    echo
    
    echo "--- Pod Description ---"
    kubectl describe pod -n "$NAMESPACE" -l app="$service" | head -50
    echo
    
    echo "--- Recent Logs ---"
    kubectl logs deployment/"$service" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "No logs available"
    echo
    
    echo "--- Service Status ---"
    kubectl get service "$service" -n "$NAMESPACE" -o wide
    echo
    
    echo "--- Recent Events ---"
    kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$service" --sort-by='.lastTimestamp' | tail -10
    echo
    
    echo "--- Resource Usage ---"
    kubectl top pod -n "$NAMESPACE" -l app="$service" 2>/dev/null || echo "Metrics not available"
    echo
}

# Monitor single service
monitor_service() {
    local service="$1"
    
    # Check if deployment exists
    if ! kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
        log_warning "$service deployment not found, skipping"
        return
    fi
    
    # Perform health check
    local health_result="healthy"
    local issue=""
    
    if ! perform_health_check "$service"; then
        health_result="unhealthy"
        issue="Health check failed"
        handle_alert "$service" "$issue"
    else
        clear_alert "$service"
    fi
    
    # Check pod status
    local pod_info
    pod_info=$(get_pod_status "$service")
    local status=$(echo "$pod_info" | cut -d'|' -f1)
    local restarts=$(echo "$pod_info" | cut -d'|' -f3)
    
    # Check for crash loops
    if [[ "$status" == "CrashLoopBackOff" ]]; then
        health_result="error"
        issue="Service in CrashLoopBackOff"
        handle_alert "$service" "$issue"
    fi
    
    # Check for excessive restarts
    if [[ "$restarts" =~ ^[0-9]+$ ]] && [[ $restarts -gt 5 ]]; then
        health_result="warning"
        issue="High restart count: $restarts"
        handle_alert "$service" "$issue"
    fi
    
    # Record metrics
    record_metrics "$service" "$health_result"
    
    # Output status
    local color="${GREEN}"
    case "$health_result" in
        "unhealthy"|"error") color="${RED}" ;;
        "warning") color="${YELLOW}" ;;
    esac
    
    echo -e "${color}$service: $health_result${NC}"
    if [[ -n "$issue" ]]; then
        echo -e "  Issue: $issue"
    fi
}

# Monitor all services
monitor_all_services() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "\n${CYAN}=== Health Check at $timestamp ===${NC}"
    
    for service in "${SERVICES[@]}"; do
        monitor_service "$service"
    done
    
    echo
}

# Show current status
show_status() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                      PyAirtable Health Monitor                             ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Namespace: ${NAMESPACE}  |  Updated: $(date +'%H:%M:%S')${NC}\n"
    
    printf "%-20s %-12s %-10s %-8s %-10s %-8s %-8s\n" \
        "Service" "Status" "Ready" "Restarts" "Health" "CPU" "Memory"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    for service in "${SERVICES[@]}"; do
        if ! kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
            printf "%-20s ${RED}%-12s${NC} %-10s %-8s %-10s %-8s %-8s\n" \
                "$service" "NotFound" "-" "-" "-" "-" "-"
            continue
        fi
        
        local pod_info
        pod_info=$(get_pod_status "$service")
        local status=$(echo "$pod_info" | cut -d'|' -f1)
        local ready=$(echo "$pod_info" | cut -d'|' -f2)
        local restarts=$(echo "$pod_info" | cut -d'|' -f3)
        
        local usage
        usage=$(get_resource_usage "$service")
        local cpu=$(echo "$usage" | cut -d'|' -f1)
        local memory=$(echo "$usage" | cut -d'|' -f2)
        
        local health="Unknown"
        if perform_health_check "$service" 2>/dev/null; then
            health="Healthy"
        elif [[ "$status" == "Running" ]]; then
            health="Unhealthy"
        fi
        
        # Color coding
        local status_color="${RED}"
        case "$status" in
            "Running") status_color="${GREEN}" ;;
            "Pending") status_color="${YELLOW}" ;;
        esac
        
        local health_color="${RED}"
        [[ "$health" == "Healthy" ]] && health_color="${GREEN}"
        
        printf "%-20s ${status_color}%-12s${NC} %-10s %-8s ${health_color}%-10s${NC} %-8s %-8s\n" \
            "$service" "$status" "$ready" "$restarts" "$health" "$cpu" "$memory"
    done
    
    echo
    
    # Show alert summary
    local active_alerts=0
    for service in "${SERVICES[@]}"; do
        if [[ ${ALERT_COUNTS["$service"]:-0} -gt 0 ]]; then
            ((active_alerts++))
        fi
    done
    
    if [[ $active_alerts -gt 0 ]]; then
        echo -e "${RED}Active Alerts: $active_alerts${NC}"
        for service in "${SERVICES[@]}"; do
            if [[ ${ALERT_COUNTS["$service"]:-0} -gt 0 ]]; then
                echo -e "  ${RED}▲ $service (${ALERT_COUNTS["$service"]} failures)${NC}"
            fi
        done
        echo
    fi
}

# Show metrics summary
show_metrics() {
    echo -e "${CYAN}Health Metrics Summary${NC}\n"
    
    for service in "${SERVICES[@]}"; do
        local metrics_file="$METRICS_DIR/$service.metrics"
        if [[ -f "$metrics_file" ]]; then
            echo -e "${WHITE}$service:${NC}"
            
            # Get recent health status
            local recent_checks=$(tail -10 "$metrics_file" | wc -l)
            local healthy_checks=$(tail -10 "$metrics_file" | grep -c "healthy" || echo 0)
            local health_percentage=$((healthy_checks * 100 / recent_checks))
            
            echo "  Health (last 10 checks): ${health_percentage}%"
            
            # Show recent failures if any
            local recent_failures=$(tail -10 "$metrics_file" | grep -v "healthy" | head -3)
            if [[ -n "$recent_failures" ]]; then
                echo "  Recent issues:"
                echo "$recent_failures" | while IFS=, read -r timestamp status pod_status ready restarts cpu memory; do
                    local human_time=$(date -d @"$timestamp" '+%H:%M:%S' 2>/dev/null || date -r "$timestamp" '+%H:%M:%S' 2>/dev/null || echo "$timestamp")
                    echo "    $human_time: $status"
                done
            fi
            echo
        fi
    done
}

# Continuous monitoring mode
continuous_monitor() {
    log_info "Starting continuous monitoring (interval: ${CHECK_INTERVAL}s)"
    
    while true; do
        show_status
        monitor_all_services
        sleep "$CHECK_INTERVAL"
    done
}

# Clean old logs and metrics
cleanup_old_data() {
    local retention_hours="${1:-$HISTORY_RETENTION}"
    
    log_info "Cleaning up data older than $retention_hours hours"
    
    # Clean old log files
    find "$LOG_DIR" -name "diagnostic-*.log" -mtime +$(echo "$retention_hours / 24" | bc) -delete 2>/dev/null || true
    
    # Trim metrics files
    for metrics_file in "$METRICS_DIR"/*.metrics; do
        if [[ -f "$metrics_file" ]]; then
            local cutoff_time=$(($(date +%s) - retention_hours * 3600))
            awk -F, -v cutoff="$cutoff_time" '$1 >= cutoff' "$metrics_file" > "$metrics_file.tmp"
            mv "$metrics_file.tmp" "$metrics_file"
        fi
    done
    
    log_success "Cleanup completed"
}

# Main execution
main() {
    init_directories
    
    case "${1:-monitor}" in
        "monitor"|"watch")
            continuous_monitor
            ;;
        "check")
            monitor_all_services
            ;;
        "status")
            show_status
            ;;
        "metrics")
            show_metrics
            ;;
        "alerts")
            if [[ -f "$LOG_DIR/alerts.log" ]]; then
                echo -e "${CYAN}Recent Alerts:${NC}"
                tail -20 "$LOG_DIR/alerts.log"
            else
                echo "No alerts recorded"
            fi
            ;;
        "cleanup")
            cleanup_old_data "${2:-$HISTORY_RETENTION}"
            ;;
        "diagnostic")
            local service="${2:-}"
            if [[ -z "$service" ]]; then
                echo "Usage: $0 diagnostic <service>"
                exit 1
            fi
            get_diagnostic_info "$service"
            ;;
        "help")
            echo "PyAirtable Health Monitor"
            echo
            echo "Usage: $0 [command] [options]"
            echo
            echo "Commands:"
            echo "  monitor      Continuous monitoring (default)"
            echo "  check        Single health check"
            echo "  status       Show current status"
            echo "  metrics      Show metrics summary"
            echo "  alerts       Show recent alerts"
            echo "  cleanup      Clean old data"
            echo "  diagnostic   Get diagnostic info for service"
            echo "  help         Show this help"
            echo
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Handle interrupt
cleanup() {
    echo -e "\n${YELLOW}Health monitor stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Run main function
main "$@"