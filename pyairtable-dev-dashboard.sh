#!/bin/bash

# PyAirtable Development Dashboard
# Interactive management interface for local development
# Provides real-time monitoring, debugging, and control capabilities

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NAMESPACE="${NAMESPACE:-pyairtable-dev}"
readonly MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-pyairtable-dev}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Service list
readonly SERVICES=(
    "postgres"
    "redis"
    "airtable-gateway"
    "mcp-server"
    "llm-orchestrator"
    "platform-services"
    "automation-services"
)

# Dashboard state
REFRESH_INTERVAL=5
AUTO_REFRESH=false
SELECTED_SERVICE=""

# Helper functions
print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                    PyAirtable Development Dashboard                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}                      Real-time Service Monitoring                         ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Namespace: ${NAMESPACE}  |  Profile: ${MINIKUBE_PROFILE}  |  Updated: $(date +'%H:%M:%S')${NC}\n"
}

get_service_status() {
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

get_service_health() {
    local service="$1"
    local port=""
    
    case "$service" in
        "postgres") port="5432" ;;
        "redis") port="6379" ;;
        "airtable-gateway") port="8002" ;;
        "mcp-server") port="8001" ;;
        "llm-orchestrator") port="8003" ;;
        "platform-services") port="8007" ;;
        "automation-services") port="8006" ;;
    esac
    
    if [[ -n "$port" ]] && kubectl run health-check-"$service" \
       --rm -i --restart=Never --image=curlimages/curl:latest \
       --namespace="$NAMESPACE" -- sh -c "curl -f -m 3 http://$service:$port/health" &> /dev/null; then
        echo "Healthy"
    else
        echo "Unhealthy"
    fi
}

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

display_service_overview() {
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│                            SERVICE OVERVIEW                                │${NC}"
    echo -e "${WHITE}├────────────────────┬────────────┬─────────┬─────────┬──────────┬─────────┤${NC}"
    echo -e "${WHITE}│ Service            │ Status     │ Ready   │ Health  │ CPU      │ Memory  │${NC}"
    echo -e "${WHITE}├────────────────────┼────────────┼─────────┼─────────┼──────────┼─────────┤${NC}"
    
    for service in "${SERVICES[@]}"; do
        local status_info
        status_info=$(get_service_status "$service")
        local status=$(echo "$status_info" | cut -d'|' -f1)
        local ready=$(echo "$status_info" | cut -d'|' -f2)
        local restarts=$(echo "$status_info" | cut -d'|' -f3)
        
        local health
        health=$(get_service_health "$service")
        
        local resource_info
        resource_info=$(get_resource_usage "$service")
        local cpu=$(echo "$resource_info" | cut -d'|' -f1)
        local memory=$(echo "$resource_info" | cut -d'|' -f2)
        
        # Color coding for status
        local status_color="${RED}"
        case "$status" in
            "Running") status_color="${GREEN}" ;;
            "Pending") status_color="${YELLOW}" ;;
            "CrashLoopBackOff") status_color="${RED}" ;;
        esac
        
        local health_color="${RED}"
        [[ "$health" == "Healthy" ]] && health_color="${GREEN}"
        
        printf "${WHITE}│ %-18s │ ${status_color}%-10s${WHITE} │ %-7s │ ${health_color}%-7s${WHITE} │ %-8s │ %-7s │${NC}\n" \
            "$service" "$status" "$ready" "$health" "$cpu" "$memory"
    done
    
    echo -e "${WHITE}└────────────────────┴────────────┴─────────┴─────────┴──────────┴─────────┘${NC}\n"
}

display_cluster_info() {
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│                            CLUSTER INFORMATION                             │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
    
    # Minikube status
    local minikube_status="Stopped"
    if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        minikube_status="Running"
    fi
    
    # Node information
    local node_info
    if node_info=$(kubectl get nodes --no-headers 2>/dev/null | head -1); then
        local node_status=$(echo "$node_info" | awk '{print $2}')
        local node_age=$(echo "$node_info" | awk '{print $5}')
        
        echo -e "Minikube Status: ${GREEN}$minikube_status${NC}"
        echo -e "Node Status: ${GREEN}$node_status${NC}"
        echo -e "Node Age: $node_age"
    else
        echo -e "Minikube Status: ${RED}$minikube_status${NC}"
    fi
    
    # Resource usage
    if command -v minikube &> /dev/null && minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        local minikube_ip
        minikube_ip=$(minikube ip -p "$MINIKUBE_PROFILE" 2>/dev/null || echo "N/A")
        echo -e "Minikube IP: $minikube_ip"
    fi
    
    echo
}

display_quick_actions() {
    echo -e "${WHITE}┌─────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│                              QUICK ACTIONS                                 │${NC}"
    echo -e "${WHITE}└─────────────────────────────────────────────────────────────────────────────┘${NC}"
    
    echo -e "${CYAN}Navigation:${NC}"
    echo -e "  [r] Refresh now    [a] Toggle auto-refresh ($([[ "$AUTO_REFRESH" == "true" ]] && echo "ON" || echo "OFF"))"
    echo -e "  [s] Service details    [l] View logs    [h] Health check"
    echo
    echo -e "${CYAN}Management:${NC}"
    echo -e "  [p] Port forwarding    [d] Deploy/restart    [c] Cleanup"
    echo -e "  [k] Kubectl shell      [m] Minikube dashboard"
    echo
    echo -e "${CYAN}Other:${NC}"
    echo -e "  [q] Quit    [?] Help"
    echo
}

service_details() {
    local service="$1"
    print_header
    
    echo -e "${WHITE}Service Details: ${CYAN}$service${NC}\n"
    
    # Deployment info
    echo -e "${YELLOW}Deployment Information:${NC}"
    kubectl describe deployment "$service" -n "$NAMESPACE" 2>/dev/null | head -20
    echo
    
    # Pod info
    echo -e "${YELLOW}Pod Information:${NC}"
    kubectl get pods -n "$NAMESPACE" -l app="$service" -o wide 2>/dev/null
    echo
    
    # Service info
    echo -e "${YELLOW}Service Information:${NC}"
    kubectl get service "$service" -n "$NAMESPACE" -o wide 2>/dev/null
    echo
    
    # Recent events
    echo -e "${YELLOW}Recent Events:${NC}"
    kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$service" --sort-by='.lastTimestamp' | tail -5
    
    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -n 1
}

view_logs() {
    local service="$1"
    local lines="${2:-50}"
    
    print_header
    echo -e "${WHITE}Logs for: ${CYAN}$service${NC} (last $lines lines)\n"
    
    if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
        kubectl logs deployment/"$service" -n "$NAMESPACE" --tail="$lines" --timestamps
    else
        echo -e "${RED}Service $service not found${NC}"
    fi
    
    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -n 1
}

setup_port_forwarding() {
    print_header
    echo -e "${WHITE}Port Forwarding Setup${NC}\n"
    
    echo -e "${YELLOW}Available services for port forwarding:${NC}"
    for i in "${!SERVICES[@]}"; do
        echo "  $((i+1)). ${SERVICES[i]}"
    done
    echo "  0. Forward all services"
    echo
    
    read -p "Select service (0-${#SERVICES[@]}): " choice
    
    if [[ "$choice" == "0" ]]; then
        echo -e "\n${CYAN}Setting up port forwarding for all services...${NC}"
        for service in "${SERVICES[@]}"; do
            local port=""
            case "$service" in
                "postgres") port="5432" ;;
                "redis") port="6379" ;;
                "airtable-gateway") port="8002" ;;
                "mcp-server") port="8001" ;;
                "llm-orchestrator") port="8003" ;;
                "platform-services") port="8007" ;;
                "automation-services") port="8006" ;;
            esac
            
            if [[ -n "$port" ]]; then
                kubectl port-forward -n "$NAMESPACE" service/"$service" "$port:$port" &
                echo "  $service: localhost:$port"
            fi
        done
        echo -e "\n${GREEN}Port forwarding active. Use 'pkill -f port-forward' to stop.${NC}"
    elif [[ "$choice" -ge 1 && "$choice" -le "${#SERVICES[@]}" ]]; then
        local service="${SERVICES[$((choice-1))]}"
        local port=""
        case "$service" in
            "postgres") port="5432" ;;
            "redis") port="6379" ;;
            "airtable-gateway") port="8002" ;;
            "mcp-server") port="8001" ;;
            "llm-orchestrator") port="8003" ;;
            "platform-services") port="8007" ;;
            "automation-services") port="8006" ;;
        esac
        
        if [[ -n "$port" ]]; then
            kubectl port-forward -n "$NAMESPACE" service/"$service" "$port:$port" &
            echo -e "\n${GREEN}Port forwarding active for $service: localhost:$port${NC}"
        fi
    fi
    
    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -n 1
}

health_check_all() {
    print_header
    echo -e "${WHITE}Comprehensive Health Check${NC}\n"
    
    echo -e "${YELLOW}Pod Health:${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    
    echo -e "${YELLOW}Service Endpoints:${NC}"
    for service in "${SERVICES[@]}"; do
        local health
        health=$(get_service_health "$service")
        local color="${RED}"
        [[ "$health" == "Healthy" ]] && color="${GREEN}"
        
        echo -e "  $service: ${color}$health${NC}"
    done
    echo
    
    echo -e "${YELLOW}Resource Usage:${NC}"
    kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics not available"
    echo
    
    echo -e "${YELLOW}Recent Events:${NC}"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
    
    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -n 1
}

deploy_restart() {
    print_header
    echo -e "${WHITE}Deploy/Restart Services${NC}\n"
    
    echo -e "${YELLOW}Available actions:${NC}"
    echo "  1. Restart all services"
    echo "  2. Restart specific service"
    echo "  3. Redeploy manifests"
    echo "  0. Cancel"
    echo
    
    read -p "Select action (0-3): " choice
    
    case "$choice" in
        "1")
            echo -e "\n${CYAN}Restarting all services...${NC}"
            for service in "${SERVICES[@]}"; do
                if kubectl get deployment "$service" -n "$NAMESPACE" &> /dev/null; then
                    kubectl rollout restart deployment/"$service" -n "$NAMESPACE"
                    echo "  Restarted: $service"
                fi
            done
            ;;
        "2")
            echo -e "\n${YELLOW}Available services:${NC}"
            for i in "${!SERVICES[@]}"; do
                echo "  $((i+1)). ${SERVICES[i]}"
            done
            echo
            read -p "Select service (1-${#SERVICES[@]}): " svc_choice
            
            if [[ "$svc_choice" -ge 1 && "$svc_choice" -le "${#SERVICES[@]}" ]]; then
                local service="${SERVICES[$((svc_choice-1))]}"
                echo -e "\n${CYAN}Restarting $service...${NC}"
                kubectl rollout restart deployment/"$service" -n "$NAMESPACE"
                kubectl rollout status deployment/"$service" -n "$NAMESPACE"
            fi
            ;;
        "3")
            echo -e "\n${CYAN}Redeploying manifests...${NC}"
            if [[ -d "${SCRIPT_DIR}/minikube-manifests-optimized" ]]; then
                kubectl apply -f "${SCRIPT_DIR}/minikube-manifests-optimized/"
            else
                kubectl apply -f "${SCRIPT_DIR}/minikube-manifests/"
            fi
            ;;
    esac
    
    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -n 1
}

cleanup_environment() {
    print_header
    echo -e "${WHITE}Cleanup Environment${NC}\n"
    
    echo -e "${RED}WARNING: This will delete all resources in namespace $NAMESPACE${NC}"
    echo -e "${YELLOW}Available cleanup options:${NC}"
    echo "  1. Clean namespace only (keep Minikube)"
    echo "  2. Clean everything (including Minikube cluster)"
    echo "  0. Cancel"
    echo
    
    read -p "Select cleanup option (0-2): " choice
    
    case "$choice" in
        "1")
            read -p "Are you sure you want to delete namespace $NAMESPACE? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${CYAN}Cleaning namespace...${NC}"
                kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
                echo -e "${GREEN}Namespace cleaned${NC}"
            fi
            ;;
        "2")
            read -p "Are you sure you want to delete the entire Minikube cluster? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${CYAN}Cleaning entire environment...${NC}"
                kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
                minikube delete -p "$MINIKUBE_PROFILE" || true
                echo -e "${GREEN}Environment cleaned${NC}"
            fi
            ;;
    esac
    
    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -n 1
}

show_help() {
    print_header
    echo -e "${WHITE}PyAirtable Development Dashboard Help${NC}\n"
    
    echo -e "${CYAN}Dashboard Features:${NC}"
    echo "  • Real-time service monitoring"
    echo "  • Resource usage tracking"
    echo "  • Health status checking"
    echo "  • Log viewing and analysis"
    echo "  • Port forwarding management"
    echo "  • Service restart capabilities"
    echo
    
    echo -e "${CYAN}Keyboard Shortcuts:${NC}"
    echo "  r - Refresh display"
    echo "  a - Toggle auto-refresh"
    echo "  s - View service details"
    echo "  l - View service logs"
    echo "  h - Run health check"
    echo "  p - Setup port forwarding"
    echo "  d - Deploy/restart services"
    echo "  c - Cleanup environment"
    echo "  k - Open kubectl shell"
    echo "  m - Open Minikube dashboard"
    echo "  q - Quit dashboard"
    echo
    
    echo -e "${CYAN}External Tools:${NC}"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs deployment/<service> -n $NAMESPACE"
    echo "  kubectl port-forward service/<service> <port>:<port> -n $NAMESPACE"
    echo "  minikube dashboard -p $MINIKUBE_PROFILE"
    echo
    
    echo -e "${BLUE}Press any key to return...${NC}"
    read -n 1
}

auto_refresh_loop() {
    while [[ "$AUTO_REFRESH" == "true" ]]; do
        sleep "$REFRESH_INTERVAL"
        if [[ "$AUTO_REFRESH" == "true" ]]; then
            display_dashboard
        fi
    done
}

display_dashboard() {
    print_header
    display_cluster_info
    display_service_overview
    display_quick_actions
}

handle_input() {
    local input="$1"
    
    case "$input" in
        "r"|"R")
            display_dashboard
            ;;
        "a"|"A")
            if [[ "$AUTO_REFRESH" == "true" ]]; then
                AUTO_REFRESH=false
            else
                AUTO_REFRESH=true
                auto_refresh_loop &
            fi
            display_dashboard
            ;;
        "s"|"S")
            echo -e "\n${YELLOW}Available services:${NC}"
            for i in "${!SERVICES[@]}"; do
                echo "  $((i+1)). ${SERVICES[i]}"
            done
            echo
            read -p "Select service (1-${#SERVICES[@]}): " choice
            
            if [[ "$choice" -ge 1 && "$choice" -le "${#SERVICES[@]}" ]]; then
                service_details "${SERVICES[$((choice-1))]}"
            fi
            display_dashboard
            ;;
        "l"|"L")
            echo -e "\n${YELLOW}Available services:${NC}"
            for i in "${!SERVICES[@]}"; do
                echo "  $((i+1)). ${SERVICES[i]}"
            done
            echo
            read -p "Select service (1-${#SERVICES[@]}): " choice
            
            if [[ "$choice" -ge 1 && "$choice" -le "${#SERVICES[@]}" ]]; then
                view_logs "${SERVICES[$((choice-1))]}"
            fi
            display_dashboard
            ;;
        "h"|"H")
            health_check_all
            display_dashboard
            ;;
        "p"|"P")
            setup_port_forwarding
            display_dashboard
            ;;
        "d"|"D")
            deploy_restart
            display_dashboard
            ;;
        "c"|"C")
            cleanup_environment
            display_dashboard
            ;;
        "k"|"K")
            echo -e "\n${CYAN}Opening kubectl shell...${NC}"
            echo "Namespace: $NAMESPACE"
            echo "Use 'exit' to return to dashboard"
            echo
            kubectl config set-context --current --namespace="$NAMESPACE"
            bash
            display_dashboard
            ;;
        "m"|"M")
            echo -e "\n${CYAN}Opening Minikube dashboard...${NC}"
            minikube dashboard -p "$MINIKUBE_PROFILE" &
            echo -e "${GREEN}Dashboard opening in browser...${NC}"
            sleep 2
            display_dashboard
            ;;
        "?")
            show_help
            display_dashboard
            ;;
        "q"|"Q")
            AUTO_REFRESH=false
            clear
            echo -e "${GREEN}PyAirtable Development Dashboard closed.${NC}"
            exit 0
            ;;
        *)
            display_dashboard
            ;;
    esac
}

# Main loop
main() {
    # Check prerequisites
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl not found. Please install kubectl.${NC}"
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${RED}Namespace $NAMESPACE not found. Please deploy the environment first.${NC}"
        exit 1
    fi
    
    # Initial display
    display_dashboard
    
    # Input loop
    while true; do
        read -n 1 -s input
        handle_input "$input"
    done
}

# Handle arguments
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Development Dashboard"
        echo
        echo "Usage: $0 [namespace]"
        echo
        echo "Default namespace: $NAMESPACE"
        echo "Default Minikube profile: $MINIKUBE_PROFILE"
        exit 0
        ;;
    *)
        if [[ -n "${1:-}" ]]; then
            NAMESPACE="$1"
        fi
        main
        ;;
esac