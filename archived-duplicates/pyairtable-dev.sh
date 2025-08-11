#!/bin/bash

# PyAirtable Development Environment Manager
# Master orchestrator for comprehensive Minikube deployment
# Author: Claude Deployment Engineer

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
readonly PROJECT_NAME="PyAirtable"
readonly VERSION="1.0.0"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Available components
declare -A COMPONENTS=(
    ["deploy"]="${SCRIPT_DIR}/deploy-minikube.sh"
    ["deps"]="${SCRIPTS_DIR}/dependency-manager.sh"
    ["secrets"]="${SCRIPTS_DIR}/secret-manager.sh"
    ["database"]="${SCRIPTS_DIR}/database-manager.sh"
    ["health"]="${SCRIPTS_DIR}/health-monitor.sh"
    ["logs"]="${SCRIPTS_DIR}/log-manager.sh"
)

# Logging functions
log() {
    echo -e "${WHITE}[$(date +'%H:%M:%S')]${NC} $*"
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

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║    ____        _    _      _        _     _        ____                       ║
║   |  _ \ _   _| |  | |    (_)      | |_  | |      |  _ \  ___ __   __         ║
║   | |_) | | | | |  | |    | |      | __| | |      | | | |/ _ \\ \\ / /         ║
║   |  __/| |_| | |__| |    | |      | |_  | |      | |_| |  __/ \\ V /          ║
║   |_|    \__, |\____/     |_|       \__| |_|      |____/ \___|  \_/           ║
║           __/ |                                                               ║
║          |___/                                                                ║
║                                                                               ║
║         🚀 Comprehensive Minikube Development Environment 🚀                  ║
║                                                                               ║
║  • One-command deployment      • Health monitoring                            ║
║  • Service orchestration       • Log aggregation                             ║
║  • Secret management          • Database migrations                          ║
║  • Dependency resolution      • Resource optimization                        ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    local missing_scripts=()
    
    # Check required tools
    for tool in kubectl minikube docker curl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    # Check component scripts
    for component in "${!COMPONENTS[@]}"; do
        local script_path="${COMPONENTS[$component]}"
        if [[ ! -f "$script_path" || ! -x "$script_path" ]]; then
            missing_scripts+=("$component: $script_path")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi
    
    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "Missing or non-executable scripts:"
        printf '  %s\n' "${missing_scripts[@]}"
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

# Show system status
show_status() {
    log_section "SYSTEM STATUS"
    
    # Check if Minikube is running
    if command -v minikube &> /dev/null; then
        local minikube_status
        minikube_status=$(minikube status --format='{{.Host}}' 2>/dev/null || echo "NotRunning")
        
        if [[ "$minikube_status" == "Running" ]]; then
            log_success "Minikube is running"
            
            # Get cluster info
            local minikube_ip
            minikube_ip=$(minikube ip 2>/dev/null || echo "unknown")
            echo -e "  📍 Cluster IP: $minikube_ip"
            
            # Check kubectl context
            local current_context
            current_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
            echo -e "  🎯 Current context: $current_context"
        else
            log_warning "Minikube is not running"
        fi
    else
        log_warning "Minikube not found"
    fi
    
    # Check if services are deployed
    if kubectl cluster-info &> /dev/null; then
        echo
        echo -e "${CYAN}🔍 Service Status${NC}"
        
        local namespace="pyairtable"
        if kubectl get namespace "$namespace" &> /dev/null; then
            # Count pods
            local total_pods running_pods
            total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
            running_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
            
            echo -e "  📦 Pods: $running_pods/$total_pods running"
            
            # Count services
            local total_services
            total_services=$(kubectl get services -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
            echo -e "  🌐 Services: $total_services deployed"
            
            # Show recent deployments
            echo -e "\n  📋 Recent pods:"
            kubectl get pods -n "$namespace" --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5 | sed 's/^/    /' || echo "    No pods found"
        else
            log_info "Namespace '$namespace' not found - services not deployed"
        fi
    else
        log_warning "Cannot connect to Kubernetes cluster"
    fi
    
    # Component status
    echo
    echo -e "${CYAN}🛠  Component Status${NC}"
    for component in "${!COMPONENTS[@]}"; do
        local script_path="${COMPONENTS[$component]}"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            echo -e "  ✅ $component"
        else
            echo -e "  ❌ $component (missing or not executable)"
        fi
    done
}

# Full deployment workflow
deploy_full() {
    log_section "FULL DEPLOYMENT WORKFLOW"
    
    log_info "Starting comprehensive deployment..."
    
    # Step 1: Generate secrets
    log_info "Step 1/6: Generating secrets..."
    if "${COMPONENTS[secrets]}" generate; then
        log_success "Secrets generated"
    else
        log_error "Secret generation failed"
        return 1
    fi
    
    # Step 2: Deploy infrastructure
    log_info "Step 2/6: Deploying infrastructure..."
    if "${COMPONENTS[deploy]}"; then
        log_success "Infrastructure deployed"
    else
        log_error "Infrastructure deployment failed"
        return 1
    fi
    
    # Step 3: Initialize database
    log_info "Step 3/6: Initializing database..."
    if "${COMPONENTS[database]}" init && "${COMPONENTS[database]}" migrate; then
        log_success "Database initialized"
    else
        log_error "Database initialization failed"
        return 1
    fi
    
    # Step 4: Wait for services to be ready
    log_info "Step 4/6: Waiting for services..."
    if "${COMPONENTS[deps]}" start; then
        log_success "Services are ready"
    else
        log_warning "Some services may not be fully ready"
    fi
    
    # Step 5: Run health checks
    log_info "Step 5/6: Running health checks..."
    if "${COMPONENTS[health]}" check; then
        log_success "Health checks passed"
    else
        log_warning "Some health checks failed"
    fi
    
    # Step 6: Show status
    log_info "Step 6/6: Deployment summary..."
    show_status
    
    log_success "Full deployment completed!"
    
    # Show access information
    echo
    echo -e "${GREEN}🎉 PyAirtable is ready for development!${NC}"
    echo
    echo -e "${CYAN}📋 Quick Commands:${NC}"
    echo -e "  View logs:        $0 logs view"
    echo -e "  Monitor health:   $0 health monitor"
    echo -e "  Manage services:  $0 deps status"
    echo -e "  Database ops:     $0 database status"
    echo
    
    if command -v minikube &> /dev/null && minikube status &> /dev/null; then
        local api_url
        api_url=$(minikube service api-gateway --namespace=pyairtable --url 2>/dev/null || echo "http://localhost:30080")
        echo -e "${CYAN}🌐 Access URLs:${NC}"
        echo -e "  API Gateway:      $api_url"
        echo -e "  Frontend:         ${api_url/30080/30081}"
    fi
}

# Quick start (minimal deployment)
quick_start() {
    log_section "QUICK START DEPLOYMENT"
    
    log_info "Starting minimal deployment for quick development..."
    
    # Generate secrets
    log_info "Generating secrets..."
    "${COMPONENTS[secrets]}" generate --force &> /dev/null || true
    
    # Deploy with minimal validation
    log_info "Deploying infrastructure..."
    if "${COMPONENTS[deploy]}"; then
        log_success "Quick deployment completed!"
        
        # Basic status check
        sleep 10
        "${COMPONENTS[health]}" check &> /dev/null || true
        
        echo
        echo -e "${GREEN}🚀 Quick start completed!${NC}"
        echo -e "${CYAN}Run '$0 status' to see detailed information${NC}"
    else
        log_error "Quick deployment failed"
        return 1
    fi
}

# Development dashboard
dev_dashboard() {
    log_section "DEVELOPMENT DASHBOARD"
    
    while true; do
        clear
        print_banner
        show_status
        
        echo
        echo -e "${CYAN}🎛  Development Dashboard${NC}"
        echo -e "${CYAN}───────────────────────${NC}"
        echo -e "  [1] 📊 Monitor Health        [6] 🔄 Restart Services"
        echo -e "  [2] 📋 View Logs             [7] 🗃  Database Operations"
        echo -e "  [3] 🔍 Search Logs           [8] 🔐 Secret Management"
        echo -e "  [4] 📈 Service Dependencies  [9] 🧹 Cleanup & Archive"
        echo -e "  [5] ⚡ Quick Health Check    [0] 🚪 Exit Dashboard"
        echo
        read -p "Select option (0-9): " -r choice
        
        case "$choice" in
            1)
                "${COMPONENTS[health]}" monitor
                ;;
            2)
                echo -e "\n${CYAN}Select service:${NC}"
                echo "  all, api-gateway, frontend, postgres, redis, etc."
                read -p "Service (default: all): " -r service
                "${COMPONENTS[logs]}" view "${service:-all}"
                read -p "Press Enter to continue..." -r
                ;;
            3)
                read -p "Search pattern: " -r pattern
                if [[ -n "$pattern" ]]; then
                    "${COMPONENTS[logs]}" search "$pattern"
                    read -p "Press Enter to continue..." -r
                fi
                ;;
            4)
                "${COMPONENTS[deps]}" deps
                read -p "Press Enter to continue..." -r
                ;;
            5)
                "${COMPONENTS[health]}" check
                read -p "Press Enter to continue..." -r
                ;;
            6)
                echo -e "\n${CYAN}Service to restart (or 'all'):${NC}"
                read -p "Service: " -r service
                if [[ -n "$service" ]]; then
                    "${COMPONENTS[deps]}" restart "$service"
                fi
                read -p "Press Enter to continue..." -r
                ;;
            7)
                echo -e "\n${CYAN}Database Operations:${NC}"
                echo -e "  [1] Status  [2] Migrate  [3] Backup  [4] Reset"
                read -p "Choose (1-4): " -r db_choice
                case "$db_choice" in
                    1) "${COMPONENTS[database]}" status ;;
                    2) "${COMPONENTS[database]}" migrate ;;
                    3) "${COMPONENTS[database]}" backup ;;
                    4) "${COMPONENTS[database]}" reset ;;
                esac
                read -p "Press Enter to continue..." -r
                ;;
            8)
                echo -e "\n${CYAN}Secret Management:${NC}"
                echo -e "  [1] Status  [2] Generate  [3] Rotate  [4] Backup"
                read -p "Choose (1-4): " -r secret_choice
                case "$secret_choice" in
                    1) "${COMPONENTS[secrets]}" status ;;
                    2) "${COMPONENTS[secrets]}" generate ;;
                    3) "${COMPONENTS[secrets]}" rotate ;;
                    4) "${COMPONENTS[secrets]}" backup ;;
                esac
                read -p "Press Enter to continue..." -r
                ;;
            9)
                echo -e "\n${CYAN}Cleanup Operations:${NC}"
                echo -e "  [1] Logs  [2] Database  [3] Monitoring  [4] All"
                read -p "Choose (1-4): " -r cleanup_choice
                case "$cleanup_choice" in
                    1) "${COMPONENTS[logs]}" cleanup ;;
                    2) "${COMPONENTS[database]}" cleanup ;;
                    3) "${COMPONENTS[health]}" cleanup ;;
                    4) 
                        "${COMPONENTS[logs]}" cleanup
                        "${COMPONENTS[database]}" cleanup
                        "${COMPONENTS[health]}" cleanup
                        ;;
                esac
                read -p "Press Enter to continue..." -r
                ;;
            0)
                log_info "Exiting dashboard"
                break
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Component delegation
delegate_to_component() {
    local component="$1"
    shift
    
    if [[ -z "${COMPONENTS[$component]:-}" ]]; then
        log_error "Unknown component: $component"
        return 1
    fi
    
    local script_path="${COMPONENTS[$component]}"
    
    if [[ ! -f "$script_path" || ! -x "$script_path" ]]; then
        log_error "Component script not found or not executable: $script_path"
        return 1
    fi
    
    # Execute component with remaining arguments
    "$script_path" "$@"
}

# Cleanup everything
cleanup_all() {
    log_section "CLEANING UP EVERYTHING"
    
    log_warning "This will remove all PyAirtable resources from Minikube"
    read -p "Are you sure? (yes/no): " -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled"
        return 0
    fi
    
    # Stop services gracefully
    log_info "Stopping services..."
    "${COMPONENTS[deps]}" stop &> /dev/null || true
    
    # Delete namespace (this removes everything)
    log_info "Removing namespace..."
    kubectl delete namespace pyairtable --ignore-not-found=true
    
    # Clean up local data
    log_info "Cleaning up local data..."
    "${COMPONENTS[logs]}" cleanup &> /dev/null || true
    "${COMPONENTS[health]}" cleanup &> /dev/null || true
    
    # Clean up secrets
    log_info "Cleaning up secrets..."
    rm -rf "${SCRIPT_DIR}/.secrets" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

# Show help
show_help() {
    print_banner
    
    cat << EOF
${CYAN}PyAirtable Development Environment Manager v${VERSION}${NC}

${YELLOW}Usage:${NC} $0 <command> [options]

${YELLOW}Main Commands:${NC}
  ${GREEN}deploy${NC}                Full deployment workflow (recommended)
  ${GREEN}quick${NC}                 Quick start deployment
  ${GREEN}dashboard${NC}             Interactive development dashboard
  ${GREEN}status${NC}                Show system status
  ${GREEN}cleanup${NC}               Clean up all resources

${YELLOW}Component Commands:${NC}
  ${GREEN}deps${NC} <cmd>            Service dependency management
  ${GREEN}secrets${NC} <cmd>         Secret generation and management
  ${GREEN}database${NC} <cmd>        Database operations and migrations
  ${GREEN}health${NC} <cmd>          Health monitoring and alerting
  ${GREEN}logs${NC} <cmd>            Log aggregation and analysis

${YELLOW}Examples:${NC}
  $0 deploy                      # Full deployment
  $0 quick                       # Quick start
  $0 dashboard                   # Interactive dashboard
  $0 status                      # Show status
  $0 logs view api-gateway       # View API gateway logs
  $0 health monitor              # Start health monitoring
  $0 secrets generate            # Generate secrets
  $0 database migrate            # Run database migrations
  $0 deps restart api-gateway    # Restart API gateway

${YELLOW}Component Help:${NC}
  $0 <component> help            # Show component-specific help

${YELLOW}Quick Actions:${NC}
  # Complete setup from scratch
  $0 deploy

  # Monitor system health
  $0 health monitor

  # View all logs
  $0 logs view all

  # Search for errors
  $0 logs search "error"

  # Interactive management
  $0 dashboard

${YELLOW}Architecture:${NC}
  • Frontend (Next.js)           - Port 30081
  • API Gateway (Go)             - Port 30080
  • Microservices (Python/Go)    - Internal ports
  • PostgreSQL Database          - Internal
  • Redis Cache                  - Internal

${YELLOW}Features:${NC}
  ✅ One-command deployment       ✅ Health monitoring
  ✅ Service orchestration        ✅ Log aggregation  
  ✅ Secret management           ✅ Database migrations
  ✅ Dependency resolution       ✅ Resource optimization
  ✅ Interactive dashboard       ✅ Comprehensive validation

${YELLOW}Support:${NC}
  For issues and documentation, check the project README.
  Log files are stored in .logs/ directory.
EOF
}

# Main function
main() {
    local command="${1:-help}"
    
    # Handle special cases first
    case "$command" in
        "help"|"-h"|"--help"|"")
            show_help
            exit 0
            ;;
        "version"|"-v"|"--version")
            echo "PyAirtable Development Environment Manager v${VERSION}"
            exit 0
            ;;
    esac
    
    # Check prerequisites for all commands except help
    if ! check_prerequisites; then
        log_error "Prerequisites not met. Please install missing tools."
        exit 1
    fi
    
    # Handle commands
    case "$command" in
        "deploy")
            deploy_full
            ;;
        "quick")
            quick_start
            ;;
        "dashboard"|"dash")
            dev_dashboard
            ;;
        "status")
            show_status
            ;;
        "cleanup")
            cleanup_all
            ;;
        "deps"|"dependencies")
            shift
            delegate_to_component "deps" "$@"
            ;;
        "secrets"|"secret")
            shift
            delegate_to_component "secrets" "$@"
            ;;
        "database"|"db")
            shift
            delegate_to_component "database" "$@"
            ;;
        "health"|"monitor")
            shift
            delegate_to_component "health" "$@"
            ;;
        "logs"|"log")
            shift
            delegate_to_component "logs" "$@"
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