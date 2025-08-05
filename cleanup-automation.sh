#!/bin/bash

# PyAirtable Cleanup Automation
# Comprehensive cleanup and maintenance for development environment
# Handles resource cleanup, log rotation, and environment reset

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

# Cleanup options
CLEAN_NAMESPACE=false
CLEAN_MINIKUBE=false
CLEAN_LOGS=false
CLEAN_IMAGES=false
CLEAN_VOLUMES=false
CLEAN_SECRETS=false
FORCE_CLEANUP=false

# Logging
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

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║              🧹 PyAirtable Cleanup Automation                               ║
║                                                                              ║
║  Comprehensive cleanup and maintenance for development environment           ║
║  • Resource cleanup • Log rotation • Environment reset • Cache clearing     ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

print_section() {
    echo -e "\n${PURPLE}═══ $* ═══${NC}\n"
}

# Check current status
check_environment_status() {
    print_section "ENVIRONMENT STATUS CHECK"
    
    # Check Minikube
    if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        log_info "Minikube cluster is running"
        
        # Check namespace
        if kubectl get namespace "$NAMESPACE" &> /dev/null; then
            local pod_count
            pod_count=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
            log_info "Namespace '$NAMESPACE' exists with $pod_count pods"
        else
            log_info "Namespace '$NAMESPACE' does not exist"
        fi
    else
        log_info "Minikube cluster is not running"
    fi
    
    # Check local artifacts
    local log_size=0
    local secrets_exist=false
    
    if [[ -d "${SCRIPT_DIR}/.dev-secrets" ]]; then
        secrets_exist=true
    fi
    
    if [[ -d "${SCRIPT_DIR}/.health-logs" ]]; then
        log_size=$(du -sh "${SCRIPT_DIR}/.health-logs" 2>/dev/null | cut -f1 || echo "0")
    fi
    
    log_info "Local secrets: $([ "$secrets_exist" = true ] && echo "exist" || echo "not found")"
    log_info "Health logs size: $log_size"
    
    echo
}

# Clean Kubernetes namespace
clean_namespace() {
    print_section "CLEANING KUBERNETES NAMESPACE"
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Namespace '$NAMESPACE' does not exist, skipping"
        return 0
    fi
    
    log_info "Deleting namespace: $NAMESPACE"
    
    # Show what will be deleted
    log_info "Resources to be deleted:"
    kubectl get all -n "$NAMESPACE" 2>/dev/null | head -20 || log_info "No resources found"
    
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo -e "${YELLOW}This will delete all resources in namespace '$NAMESPACE'${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Namespace cleanup cancelled"
            return 0
        fi
    fi
    
    # Delete namespace with grace period
    kubectl delete namespace "$NAMESPACE" --grace-period=30 &
    local delete_pid=$!
    
    # Show progress
    local timeout=300  # 5 minutes
    local elapsed=0
    while kill -0 $delete_pid 2>/dev/null && [[ $elapsed -lt $timeout ]]; do
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Namespace deletion in progress... (${elapsed}s)"
    done
    
    if kill -0 $delete_pid 2>/dev/null; then
        log_warning "Namespace deletion taking longer than expected, forcing..."
        kubectl delete namespace "$NAMESPACE" --force --grace-period=0 &> /dev/null || true
    fi
    
    wait $delete_pid 2>/dev/null || true
    log_success "Namespace cleaned"
}

# Clean Minikube cluster
clean_minikube() {
    print_section "CLEANING MINIKUBE CLUSTER"
    
    if ! minikube profile list 2>/dev/null | grep -q "$MINIKUBE_PROFILE"; then
        log_info "Minikube profile '$MINIKUBE_PROFILE' does not exist"
        return 0
    fi
    
    log_info "Stopping Minikube profile: $MINIKUBE_PROFILE"
    minikube stop -p "$MINIKUBE_PROFILE" || log_warning "Failed to stop Minikube gracefully"
    
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo -e "${YELLOW}This will completely delete the Minikube cluster '$MINIKUBE_PROFILE'${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Minikube cleanup cancelled"
            return 0
        fi
    fi
    
    log_info "Deleting Minikube profile: $MINIKUBE_PROFILE"
    minikube delete -p "$MINIKUBE_PROFILE" || log_warning "Failed to delete Minikube profile"
    
    log_success "Minikube cluster cleaned"
}

# Clean local logs and artifacts
clean_logs() {
    print_section "CLEANING LOCAL LOGS AND ARTIFACTS"
    
    local cleaned_size=0
    
    # Health logs
    if [[ -d "${SCRIPT_DIR}/.health-logs" ]]; then
        local size_before
        size_before=$(du -s "${SCRIPT_DIR}/.health-logs" 2>/dev/null | cut -f1 || echo 0)
        
        log_info "Cleaning health logs..."
        rm -rf "${SCRIPT_DIR}/.health-logs"
        mkdir -p "${SCRIPT_DIR}/.health-logs"
        
        cleaned_size=$((cleaned_size + size_before))
        log_success "Health logs cleaned"
    fi
    
    # Metrics
    if [[ -d "${SCRIPT_DIR}/.metrics" ]]; then
        local size_before
        size_before=$(du -s "${SCRIPT_DIR}/.metrics" 2>/dev/null | cut -f1 || echo 0)
        
        log_info "Cleaning metrics..."
        rm -rf "${SCRIPT_DIR}/.metrics"
        mkdir -p "${SCRIPT_DIR}/.metrics"
        
        cleaned_size=$((cleaned_size + size_before))
        log_success "Metrics cleaned"
    fi
    
    # Deployment logs
    if [[ -f "${SCRIPT_DIR}/.minikube-dev.log" ]]; then
        local size_before
        size_before=$(du -s "${SCRIPT_DIR}/.minikube-dev.log" 2>/dev/null | cut -f1 || echo 0)
        
        log_info "Cleaning deployment logs..."
        rm -f "${SCRIPT_DIR}/.minikube-dev.log"
        
        cleaned_size=$((cleaned_size + size_before))
        log_success "Deployment logs cleaned"
    fi
    
    # Temporary files
    find "$SCRIPT_DIR" -name "*.tmp" -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "*.log.*" -delete 2>/dev/null || true
    
    if [[ $cleaned_size -gt 0 ]]; then
        log_success "Cleaned $(echo "$cleaned_size * 512 / 1024 / 1024" | bc)MB of logs and artifacts"
    else
        log_info "No logs to clean"
    fi
}

# Clean Docker images
clean_images() {
    print_section "CLEANING DOCKER IMAGES"
    
    # Switch to Minikube Docker environment if cluster exists
    if minikube status -p "$MINIKUBE_PROFILE" &> /dev/null; then
        log_info "Switching to Minikube Docker environment..."
        eval "$(minikube docker-env -p "$MINIKUBE_PROFILE")"
    fi
    
    # List PyAirtable images
    local images
    images=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "(pyairtable|airtable-gateway|mcp-server|llm-orchestrator)" || echo "")
    
    if [[ -z "$images" ]]; then
        log_info "No PyAirtable images found"
        return 0
    fi
    
    log_info "Found PyAirtable images:"
    echo "$images"
    
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo -e "${YELLOW}This will delete all PyAirtable Docker images${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Image cleanup cancelled"
            return 0
        fi
    fi
    
    # Remove images
    local image_names
    image_names=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(pyairtable|airtable-gateway|mcp-server|llm-orchestrator)" || echo "")
    
    if [[ -n "$image_names" ]]; then
        log_info "Removing PyAirtable images..."
        echo "$image_names" | xargs docker rmi -f 2>/dev/null || log_warning "Some images could not be removed"
        log_success "PyAirtable images cleaned"
    fi
    
    # Clean dangling images
    local dangling
    dangling=$(docker images -f "dangling=true" -q)
    if [[ -n "$dangling" ]]; then
        log_info "Cleaning dangling images..."
        echo "$dangling" | xargs docker rmi -f 2>/dev/null || true
        log_success "Dangling images cleaned"
    fi
}

# Clean persistent volumes
clean_volumes() {
    print_section "CLEANING PERSISTENT VOLUMES"
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Namespace does not exist, skipping volume cleanup"
        return 0
    fi
    
    # List persistent volumes
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    
    if [[ -z "$pvcs" ]]; then
        log_info "No persistent volumes found"
        return 0
    fi
    
    log_info "Found persistent volume claims:"
    kubectl get pvc -n "$NAMESPACE" 2>/dev/null || true
    
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo -e "${YELLOW}This will delete all persistent volumes and their data${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Volume cleanup cancelled"
            return 0
        fi
    fi
    
    # Delete PVCs
    log_info "Deleting persistent volume claims..."
    kubectl delete pvc --all -n "$NAMESPACE" --grace-period=30 || log_warning "Some PVCs could not be deleted"
    
    log_success "Persistent volumes cleaned"
}

# Clean development secrets
clean_secrets() {
    print_section "CLEANING DEVELOPMENT SECRETS"
    
    if [[ -d "${SCRIPT_DIR}/.dev-secrets" ]]; then
        log_info "Found development secrets directory"
        
        if [[ "$FORCE_CLEANUP" != "true" ]]; then
            echo -e "${YELLOW}This will delete all generated development secrets${NC}"
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Secrets cleanup cancelled"
                return 0
            fi
        fi
        
        log_info "Removing development secrets..."
        rm -rf "${SCRIPT_DIR}/.dev-secrets"
        log_success "Development secrets cleaned"
    else
        log_info "No development secrets found"
    fi
    
    # Clean access script
    if [[ -f "${SCRIPT_DIR}/dev-access.sh" ]]; then
        log_info "Removing development access script..."
        rm -f "${SCRIPT_DIR}/dev-access.sh"
        log_success "Development access script cleaned"
    fi
}

# Quick cleanup (namespace only)
quick_cleanup() {
    print_section "QUICK CLEANUP (NAMESPACE ONLY)"
    
    CLEAN_NAMESPACE=true
    FORCE_CLEANUP=true
    
    clean_namespace
    log_success "Quick cleanup completed"
}

# Full cleanup (everything)
full_cleanup() {
    print_section "FULL CLEANUP (EVERYTHING)"
    
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo -e "${RED}WARNING: This will delete EVERYTHING related to PyAirtable development${NC}"
        echo "- Minikube cluster"
        echo "- All Kubernetes resources"
        echo "- Development secrets"
        echo "- Local logs and metrics"
        echo "- Docker images"
        echo "- Persistent volumes"
        echo
        read -p "Are you absolutely sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Full cleanup cancelled"
            return 0
        fi
    fi
    
    CLEAN_NAMESPACE=true
    CLEAN_MINIKUBE=true
    CLEAN_LOGS=true
    CLEAN_IMAGES=true
    CLEAN_VOLUMES=true
    CLEAN_SECRETS=true
    
    clean_volumes
    clean_namespace
    clean_minikube
    clean_images
    clean_logs
    clean_secrets
    
    log_success "Full cleanup completed"
}

# Interactive cleanup menu
interactive_cleanup() {
    while true; do
        clear
        print_banner
        check_environment_status
        
        echo -e "${CYAN}Cleanup Options:${NC}"
        echo "1. Quick cleanup (namespace only)"
        echo "2. Clean namespace and resources"
        echo "3. Clean Minikube cluster"
        echo "4. Clean logs and artifacts"
        echo "5. Clean Docker images"
        echo "6. Clean persistent volumes"
        echo "7. Clean development secrets"
        echo "8. Full cleanup (everything)"
        echo "9. Custom cleanup"
        echo "0. Exit"
        echo
        
        read -p "Select option (0-9): " choice
        echo
        
        case "$choice" in
            1)
                quick_cleanup
                ;;
            2)
                CLEAN_NAMESPACE=true
                CLEAN_VOLUMES=true
                clean_volumes
                clean_namespace
                ;;
            3)
                CLEAN_MINIKUBE=true
                clean_minikube
                ;;
            4)
                CLEAN_LOGS=true
                clean_logs
                ;;
            5)
                CLEAN_IMAGES=true
                clean_images
                ;;
            6)
                CLEAN_VOLUMES=true
                clean_volumes
                ;;
            7)
                CLEAN_SECRETS=true
                clean_secrets
                ;;
            8)
                full_cleanup
                ;;
            9)
                echo "Custom cleanup options:"
                echo "Select what to clean (y/n):"
                
                read -p "Namespace? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_NAMESPACE=true
                read -p "Minikube? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_MINIKUBE=true
                read -p "Logs? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_LOGS=true
                read -p "Images? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_IMAGES=true
                read -p "Volumes? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_VOLUMES=true
                read -p "Secrets? " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]] && CLEAN_SECRETS=true
                
                echo
                [[ "$CLEAN_VOLUMES" == "true" ]] && clean_volumes
                [[ "$CLEAN_NAMESPACE" == "true" ]] && clean_namespace
                [[ "$CLEAN_MINIKUBE" == "true" ]] && clean_minikube
                [[ "$CLEAN_IMAGES" == "true" ]] && clean_images
                [[ "$CLEAN_LOGS" == "true" ]] && clean_logs
                [[ "$CLEAN_SECRETS" == "true" ]] && clean_secrets
                ;;
            0)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                CLEAN_NAMESPACE=true
                shift
                ;;
            --minikube)
                CLEAN_MINIKUBE=true
                shift
                ;;
            --logs)
                CLEAN_LOGS=true
                shift
                ;;
            --images)
                CLEAN_IMAGES=true
                shift
                ;;
            --volumes)
                CLEAN_VOLUMES=true
                shift
                ;;
            --secrets)
                CLEAN_SECRETS=true
                shift
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --all)
                CLEAN_NAMESPACE=true
                CLEAN_MINIKUBE=true
                CLEAN_LOGS=true
                CLEAN_IMAGES=true
                CLEAN_VOLUMES=true
                CLEAN_SECRETS=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # If no options specified, run interactive mode
    if [[ "$CLEAN_NAMESPACE" == "false" && "$CLEAN_MINIKUBE" == "false" && \
          "$CLEAN_LOGS" == "false" && "$CLEAN_IMAGES" == "false" && \
          "$CLEAN_VOLUMES" == "false" && "$CLEAN_SECRETS" == "false" ]]; then
        interactive_cleanup
        return
    fi
    
    # Run selected cleanup operations
    print_banner
    check_environment_status
    
    [[ "$CLEAN_VOLUMES" == "true" ]] && clean_volumes
    [[ "$CLEAN_NAMESPACE" == "true" ]] && clean_namespace
    [[ "$CLEAN_MINIKUBE" == "true" ]] && clean_minikube
    [[ "$CLEAN_IMAGES" == "true" ]] && clean_images
    [[ "$CLEAN_LOGS" == "true" ]] && clean_logs
    [[ "$CLEAN_SECRETS" == "true" ]] && clean_secrets
    
    log_success "Cleanup operations completed"
}

# Command line handling
case "${1:-}" in
    "help"|"-h"|"--help")
        echo "PyAirtable Cleanup Automation"
        echo
        echo "Usage: $0 [command] [options]"
        echo
        echo "Commands:"
        echo "  quick      Quick cleanup (namespace only)"
        echo "  full       Full cleanup (everything)"
        echo "  status     Show environment status"
        echo "  help       Show this help"
        echo
        echo "Options:"
        echo "  --namespace   Clean Kubernetes namespace"
        echo "  --minikube    Clean Minikube cluster"
        echo "  --logs        Clean logs and artifacts"
        echo "  --images      Clean Docker images"
        echo "  --volumes     Clean persistent volumes"
        echo "  --secrets     Clean development secrets"
        echo "  --all         Clean everything"
        echo "  --force       Skip confirmation prompts"
        echo
        echo "Examples:"
        echo "  $0                           # Interactive mode"
        echo "  $0 quick                     # Quick cleanup"
        echo "  $0 full                      # Full cleanup"
        echo "  $0 --namespace --logs        # Clean namespace and logs"
        echo "  $0 --all --force             # Clean everything without prompts"
        echo
        exit 0
        ;;
    "quick")
        print_banner
        quick_cleanup
        ;;
    "full")
        print_banner
        full_cleanup
        ;;
    "status")
        print_banner
        check_environment_status
        ;;
    "")
        main
        ;;
    *)
        # Treat as options
        main "$@"
        ;;
esac